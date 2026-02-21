import base64
import json
import asyncio
import re
import hashlib
import subprocess
import os
import aiohttp
from urllib.parse import urlparse, parse_qs

# --- CONFIGURATION ---
XRAY_BIN = "./bin/xray"  # Path to Xray executable
TCP_TIMEOUT = 1.5
REAL_DELAY_TIMEOUT = 3.0
REAL_DELAY_CONCURRENCY = 80
TEST_URL = "http://cp.cloudflare.com/"
EXPECTED_RESPONSE_CODE = 204

def decode_base64(s):
    """Robust base64 decoding."""
    s = s.strip()
    missing_padding = len(s) % 4
    if missing_padding:
        s += '=' * (4 - missing_padding)
    try:
        return base64.b64decode(s).decode('utf-8', errors='ignore')
    except Exception:
        return ""

def get_config_hash(config):
    """
    Generates a unique hash for a config based ONLY on core connection details.
    Ignores 'ps' (remark/name).
    """
    core_data = ""
    protocol = config.get("protocol")

    if protocol == "vmess":
        # Hash based on: add, port, id, net, path, tls
        core_data = f"{config.get('add')}|{config.get('port')}|{config.get('id')}|{config.get('net')}|{config.get('path')}|{config.get('tls')}"
    elif protocol == "vless":
        # Hash based on: add, port, id, encryption, type, security, path
        core_data = f"{config.get('add')}|{config.get('port')}|{config.get('id')}|{config.get('encryption')}|{config.get('type')}|{config.get('security')}|{config.get('path')}"
    elif protocol == "trojan":
         # Hash based on: add, port, password, sni
        core_data = f"{config.get('add')}|{config.get('port')}|{config.get('password')}|{config.get('sni')}"
    elif protocol == "shadowsocks":
         # Hash based on: add, port, method, password
        core_data = f"{config.get('add')}|{config.get('port')}|{config.get('method')}|{config.get('password')}"
    else:
        # Fallback for unknown protocols
        core_data = json.dumps(config, sort_keys=True)

    return hashlib.md5(core_data.encode()).hexdigest()

def parse_vmess(url):
    try:
        b64 = url.replace("vmess://", "")
        json_str = decode_base64(b64)
        data = json.loads(json_str)
        return {
            "protocol": "vmess",
            "add": data.get("add"),
            "port": int(data.get("port")),
            "id": data.get("id"),
            "aid": data.get("aid", 0),
            "net": data.get("net", "tcp"),
            "type": data.get("type", "none"),
            "host": data.get("host", ""),
            "path": data.get("path", ""),
            "tls": data.get("tls", ""),
            "ps": data.get("ps", ""),
            "raw_uri": url
        }
    except Exception:
        return None

def parse_vless(url):
    try:
        parsed = urlparse(url)
        params = parse_qs(parsed.query)
        user_info = parsed.username

        return {
            "protocol": "vless",
            "add": parsed.hostname,
            "port": parsed.port,
            "id": user_info,
            "encryption": params.get("encryption", ["none"])[0],
            "type": params.get("type", ["tcp"])[0],
            "security": params.get("security", ["none"])[0],
            "path": params.get("path", [""])[0],
            "host": params.get("host", [""])[0],
            "sni": params.get("sni", [""])[0],
            "fp": params.get("fp", [""])[0],
            "ps": parsed.fragment,
            "raw_uri": url
        }
    except Exception:
        return None

def parse_trojan(url):
    try:
        parsed = urlparse(url)
        params = parse_qs(parsed.query)

        return {
            "protocol": "trojan",
            "add": parsed.hostname,
            "port": parsed.port,
            "password": parsed.username,
            "sni": params.get("sni", [""])[0] or params.get("peer", [""])[0],
            "type": params.get("type", ["tcp"])[0],
            "security": params.get("security", ["tls"])[0], # Trojan usually implies TLS
            "path": params.get("path", [""])[0],
            "host": params.get("host", [""])[0],
             "ps": parsed.fragment,
             "raw_uri": url
        }
    except Exception:
        return None

def parse_shadowsocks(url):
    try:
        # ss://base64(method:password)@server:port#remark
        # or ss://base64(method:password@server:port)#remark
        clean_url = url.replace("ss://", "")
        if "#" in clean_url:
            main_part, ps = clean_url.split("#", 1)
        else:
            main_part = clean_url
            ps = ""

        # Try decoding the whole thing first (SIP002)
        decoded = decode_base64(main_part)

        if "@" in decoded:
            # method:password@server:port
            user_pass, server_port = decoded.split("@", 1)
            method, password = user_pass.split(":", 1)
            server, port = server_port.rsplit(":", 1)
        elif "@" in main_part:
            # base64(method:password)@server:port
            user_pass_b64, server_port = main_part.split("@", 1)
            user_pass = decode_base64(user_pass_b64)
            method, password = user_pass.split(":", 1)
            server, port = server_port.rsplit(":", 1)
        else:
             return None

        return {
            "protocol": "shadowsocks",
            "add": server,
            "port": int(port),
            "method": method,
            "password": password,
            "ps": ps,
            "raw_uri": url
        }

    except Exception:
        return None

def generate_xray_config(config, local_port):
    """
    Generates a full Xray JSON configuration for a specific inbound port.
    """
    outbound = {}

    # Safe int conversion helper
    def safe_int(val, default=443):
        try:
            if val is None:
                return default
            return int(val)
        except (ValueError, TypeError):
            return default

    if config["protocol"] == "vmess":
        outbound = {
            "protocol": "vmess",
            "settings": {
                "vnext": [{
                    "address": config["add"],
                    "port": safe_int(config.get("port")),
                    "users": [{"id": config["id"], "alterId": safe_int(config.get("aid", 0)), "security": "auto"}]
                }]
            },
            "streamSettings": {
                "network": config["net"],
                "security": config["tls"],
                "tlsSettings": {"serverName": config.get("host") or config.get("add"), "allowInsecure": True},
                "wsSettings": {"path": config.get("path"), "headers": {"Host": config.get("host") or config.get("add")}} if config["net"] == "ws" else None,
                "grpcSettings": {"serviceName": config.get("path")} if config["net"] == "grpc" else None,
                "httpSettings": {"path": config.get("path"), "host": [config.get("host") or config.get("add")]} if config["net"] == "http" else None
            }
        }
    elif config["protocol"] == "vless":
        outbound = {
            "protocol": "vless",
            "settings": {
                "vnext": [{
                    "address": config["add"],
                    "port": safe_int(config.get("port")),
                    "users": [{"id": config["id"], "encryption": config["encryption"], "flow": config.get("flow", "")}]
                }]
            },
            "streamSettings": {
                "network": config["type"],
                "security": config["security"],
                "tlsSettings": {"serverName": config.get("sni") or config.get("host") or config["add"], "allowInsecure": True},
                "realitySettings": {"serverName": config.get("sni") or config.get("host") or config["add"], "publicKey": config.get("pbk"), "shortId": config.get("sid")} if config["security"] == "reality" else None,
                "wsSettings": {"path": config.get("path"), "headers": {"Host": config.get("host") or config["add"]}} if config["type"] == "ws" else None,
                "grpcSettings": {"serviceName": config.get("path")} if config["type"] == "grpc" else None
            }
        }
    elif config["protocol"] == "trojan":
        outbound = {
            "protocol": "trojan",
            "settings": {
                "servers": [{"address": config["add"], "port": safe_int(config.get("port")), "password": config["password"]}]
            },
            "streamSettings": {
                "network": config.get("type", "tcp"),
                "security": "tls",
                "tlsSettings": {"serverName": config.get("sni") or config.get("host") or config["add"], "allowInsecure": True},
                "wsSettings": {"path": config.get("path"), "headers": {"Host": config.get("host") or config["add"]}} if config.get("type") == "ws" else None,
                "grpcSettings": {"serviceName": config.get("path")} if config.get("type") == "grpc" else None
            }
        }
    elif config["protocol"] == "shadowsocks":
         outbound = {
            "protocol": "shadowsocks",
            "settings": {
                "servers": [{"address": config["add"], "port": safe_int(config.get("port")), "method": config["method"], "password": config["password"]}]
            }
        }

    return {
        "log": {"loglevel": "none"},
        "inbounds": [{
            "port": local_port,
            "protocol": "http",
            "settings": {"timeout": 0}
        }],
        "outbounds": [outbound]
    }

async def test_tcp_connection(host, port, timeout=TCP_TIMEOUT):
    """
    Performs a quick TCP handshake to verify the server is reachable.
    """
    try:
        _, writer = await asyncio.wait_for(
            asyncio.open_connection(host, port),
            timeout=timeout
        )
        writer.close()
        await writer.wait_closed()
        return True
    except:
        return False

async def test_connection(config, local_port, session=None):
    """
    Tests a configuration by spawning an Xray subprocess, piping the config via stdin,
    and attempting an HTTP request through the local HTTP proxy using aiohttp.
    Returns: (success: bool, delay_ms: int, error_reason: str)
    """
    process = None
    try:
        xray_config = generate_xray_config(config, local_port)
        xray_json = json.dumps(xray_config).encode('utf-8')

        # Start Xray process
        process = await asyncio.create_subprocess_exec(
            XRAY_BIN, "-config", "stdin:",
            stdin=subprocess.PIPE,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE
        )

        # Write config to stdin and close it
        process.stdin.write(xray_json)
        await process.stdin.drain()
        process.stdin.close()

        # Wait a brief moment for Xray to initialize
        await asyncio.sleep(0.5)

        # Test connection using aiohttp through the proxy
        proxy_url = f"http://127.0.0.1:{local_port}"
        start_time = asyncio.get_event_loop().time()

        try:
            # Helper function to perform request
            async def perform_request(req_session):
                async with req_session.get(TEST_URL, proxy=proxy_url, timeout=REAL_DELAY_TIMEOUT) as response:
                    await response.read() # Ensure body is fully read
                    return response.status

            if session:
                status = await perform_request(session)
            else:
                async with aiohttp.ClientSession() as local_session:
                    status = await perform_request(local_session)

            if status == 204 or status == 200:
                end_time = asyncio.get_event_loop().time()
                delay = int((end_time - start_time) * 1000)
                return True, delay, None
            else:
                return False, -1, f"HTTP_{status}"

        except asyncio.TimeoutError:
            return False, -1, "Timeout"
        except aiohttp.ClientError:
            return False, -1, "ConnectionError"
        except Exception as e:
             return False, -1, f"RequestError: {str(e)}"

    except Exception as e:
        return False, -1, f"XrayCrash: {str(e)}"
    finally:
        if process:
            try:
                # Robust process termination to prevent zombies
                process.terminate()
                try:
                    await asyncio.wait_for(process.wait(), timeout=2.0)
                except asyncio.TimeoutError:
                    process.kill()
                    await process.wait()
            except ProcessLookupError:
                pass
            except Exception as e:
                # Last resort kill if something weird happens
                try:
                    process.kill()
                except:
                    pass
