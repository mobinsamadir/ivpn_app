import asyncio
import json
import os
import shutil
import datetime
import aiohttp
import zipfile
from collections import Counter
from v2ray_utils import test_connection, parse_vmess, parse_vless, parse_trojan, parse_shadowsocks, decode_base64, test_tcp_connection

# --- CONFIGURATION ---
XRAY_BIN_DIR = "bin"
XRAY_BIN = os.path.join(XRAY_BIN_DIR, "xray")
XRAY_ZIP = "xray.zip"
XRAY_DOWNLOAD_URL = "https://github.com/XTLS/Xray-core/releases/download/v1.8.4/Xray-linux-64.zip"

INPUT_FILE = "real_delay_passed.txt"
RESULTS_BASE_DIR = "local_results"
CONCURRENCY = 80
PORT_START = 20000

async def download_xray():
    """Downloads and extracts Xray core if not present."""
    if os.path.exists(XRAY_BIN):
        print(f"Xray binary found at {XRAY_BIN}")
        return

    print("Downloading Xray Core...")
    os.makedirs(XRAY_BIN_DIR, exist_ok=True)

    async with aiohttp.ClientSession() as session:
        async with session.get(XRAY_DOWNLOAD_URL) as response:
            if response.status == 200:
                with open(XRAY_ZIP, "wb") as f:
                    f.write(await response.read())
            else:
                print(f"Failed to download Xray: {response.status}")
                return

    print("Extracting Xray...")
    try:
        with zipfile.ZipFile(XRAY_ZIP, "r") as zip_ref:
            zip_ref.extractall(XRAY_BIN_DIR)

        # Ensure executable permission
        os.chmod(XRAY_BIN, 0o755)
        print("Xray installed successfully.")
    except Exception as e:
        print(f"Error extracting Xray: {e}")
    finally:
        if os.path.exists(XRAY_ZIP):
            os.remove(XRAY_ZIP)

async def worker(queue, results, log_file_handle, stats, port_offset, session):
    local_port = PORT_START + port_offset

    while True:
        try:
            config_uri = queue.get_nowait()
        except asyncio.QueueEmpty:
            break

        # Re-parse the URI since we are reading from txt
        config = None
        if config_uri.startswith("vmess://"):
            config = parse_vmess(config_uri)
        elif config_uri.startswith("vless://"):
            config = parse_vless(config_uri)
        elif config_uri.startswith("trojan://"):
            config = parse_trojan(config_uri)
        elif config_uri.startswith("ss://"):
            config = parse_shadowsocks(config_uri)

        if not config:
            stats["InvalidConfig"] += 1
            queue.task_done()
            continue

        # TCP Pre-Check
        if not await test_tcp_connection(config['add'], config['port'], timeout=1.5):
            log_file_handle.write(f"{datetime.datetime.now()} - TCP Failed - {config_uri[:50]}...\n")
            stats['TCP_Failed'] += 1
            stats["total"] += 1
            queue.task_done()
            continue

        success, delay, error = await test_connection(config, local_port, session=session)

        # Log result
        log_msg = f"Port {local_port}: {error if error else 'SUCCESS'} ({delay}ms) - {config_uri[:50]}..."
        log_file_handle.write(f"{datetime.datetime.now()} - {log_msg}\n")
        log_file_handle.flush() # Ensure real-time logging

        result_entry = {
            "config": config_uri,
            "delay_ms": delay,
            "error": error
        }
        results.append(result_entry)

        if success:
            stats["passed"] += 1
        else:
            stats[error] += 1

        stats["total"] += 1
        if stats["total"] % 100 == 0:
            print(f"Processed {stats['total']} configs...")

        queue.task_done()

async def main():
    await download_xray()

    if not os.path.exists(INPUT_FILE):
        print(f"{INPUT_FILE} not found!")
        return

    timestamp = datetime.datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    output_dir = os.path.join(RESULTS_BASE_DIR, timestamp)
    os.makedirs(output_dir, exist_ok=True)

    log_path = os.path.join(output_dir, "test.log")
    json_path = os.path.join(output_dir, "detailed_results.json")
    txt_path = os.path.join(output_dir, "real_delay_passed.txt")

    with open(INPUT_FILE, "r") as f:
        uris = [line.strip() for line in f if line.strip()]

    print(f"Testing {len(uris)} configs locally...")
    print(f"Output directory: {output_dir}")

    queue = asyncio.Queue()
    for uri in uris:
        queue.put_nowait(uri)

    results = []
    stats = Counter()

    with open(log_path, "w") as log_file:
        async with aiohttp.ClientSession() as session:
            tasks = []
            for i in range(CONCURRENCY):
                task = asyncio.create_task(worker(queue, results, log_file, stats, i, session))
                tasks.append(task)

            await asyncio.gather(*tasks)

    # Sort results by delay (fastest first), pushing errors (-1) to the end?
    def sort_key(item):
        d = item["delay_ms"]
        if d == -1:
            return float('inf') # Push to end
        return d

    results.sort(key=sort_key)

    # Save JSON
    with open(json_path, "w") as f:
        json.dump(results, f, indent=2)

    # Save TXT (Passed only)
    passed_configs = [r["config"] for r in results if r["delay_ms"] != -1]
    with open(txt_path, "w") as f:
        f.write("\n".join(passed_configs))

    print("\n" + "="*40)
    print("LOCAL TEST SUMMARY")
    print("="*40)
    print(f"Total:  {stats['total']}")
    print(f"Passed: {stats['passed']}")
    print(f"Failed: {stats['total'] - stats['passed']}")
    print("-" * 20)
    for reason, count in stats.items():
         if reason not in ["total", "passed"]:
            print(f"  {reason}: {count}")
    print(f"Results saved to {output_dir}")

if __name__ == "__main__":
    asyncio.run(main())
