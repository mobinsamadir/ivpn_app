import asyncio
import aiohttp
import json
import os
import re
from v2ray_utils import parse_vmess, parse_vless, parse_trojan, parse_shadowsocks, get_config_hash, decode_base64

SOURCES_FILE = "sources.txt"
OUTPUT_FILE = "unique_configs.json"
TIMEOUT = 30  # Seconds to fetch a source

async def fetch_source(session, url):
    try:
        async with session.get(url, timeout=TIMEOUT) as response:
            if response.status == 200:
                return await response.text()
            else:
                print(f"Failed to fetch {url}: Status {response.status}")
                return ""
    except Exception as e:
        print(f"Error fetching {url}: {e}")
        return ""

async def main():
    if not os.path.exists(SOURCES_FILE):
        print(f"{SOURCES_FILE} not found!")
        return

    with open(SOURCES_FILE, "r") as f:
        urls = [line.strip() for line in f if line.strip() and not line.startswith("#")]

    if not urls:
        print("No sources found.")
        return

    print(f"Fetching {len(urls)} sources...")

    async with aiohttp.ClientSession() as session:
        tasks = [fetch_source(session, url) for url in urls]
        results = await asyncio.gather(*tasks)

    # Combine all results
    combined_content = "\n".join(results)

    # Process potential base64 blocks (Subscription links often return base64 encoded text)
    # We will try to decode lines that look like base64, or the whole file if applicable
    processed_lines = []

    # 1. Split by newlines first
    raw_lines = combined_content.splitlines()

    for line in raw_lines:
        line = line.strip()
        if not line:
            continue

        # If line is a valid config URL, add it
        if re.match(r'^(vmess|vless|trojan|ss)://', line):
            processed_lines.append(line)
        else:
            # Try to decode it as base64
            try:
                decoded = decode_base64(line)
                # If decoding yields valid config lines, add them
                if "vmess://" in decoded or "vless://" in decoded or "trojan://" in decoded or "ss://" in decoded:
                     for sub_line in decoded.splitlines():
                         sub_line = sub_line.strip()
                         if re.match(r'^(vmess|vless|trojan|ss)://', sub_line):
                             processed_lines.append(sub_line)
            except:
                pass

    unique_configs = {}
    print(f"Processing {len(processed_lines)} potential config lines...")

    for line in processed_lines:
        config = None
        if line.startswith("vmess://"):
            config = parse_vmess(line)
        elif line.startswith("vless://"):
            config = parse_vless(line)
        elif line.startswith("trojan://"):
            config = parse_trojan(line)
        elif line.startswith("ss://"):
            config = parse_shadowsocks(line)

        if config:
            # Strict Deduplication
            config_hash = get_config_hash(config)
            if config_hash not in unique_configs:
                unique_configs[config_hash] = config

    print(f"Found {len(unique_configs)} unique configurations.")

    with open(OUTPUT_FILE, "w") as f:
        json.dump(list(unique_configs.values()), f, indent=2)
    print(f"Saved to {OUTPUT_FILE}")

if __name__ == "__main__":
    asyncio.run(main())
