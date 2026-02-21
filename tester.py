import asyncio
import json
import os
import zipfile
import subprocess
import shutil
import aiohttp
import sys
from collections import Counter
from v2ray_utils import test_connection, decode_base64

# --- CONFIGURATION ---
XRAY_BIN_DIR = "bin"
XRAY_BIN = os.path.join(XRAY_BIN_DIR, "xray")
XRAY_ZIP = "xray.zip"
XRAY_DOWNLOAD_URL = "https://github.com/XTLS/Xray-core/releases/download/v1.8.4/Xray-linux-64.zip"

INPUT_FILE = "unique_configs.json"
OUTPUT_FILE = "real_delay_passed.txt"
CONCURRENCY = 80
PORT_START = 10000

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

async def worker(queue, results, stats, port_offset):
    """
    Worker to process configs from the queue.
    """
    local_port = PORT_START + port_offset

    while True:
        try:
            config = queue.get_nowait()
        except asyncio.QueueEmpty:
            break

        success, delay, error = await test_connection(config, local_port)

        if success:
            results.append((config, delay))
            stats["passed"] += 1
        else:
            stats[error] += 1

        stats["total"] += 1
        if stats["total"] % 500 == 0:
            print(f"Processed {stats['total']} configs...")

        queue.task_done()

async def main():
    # 1. Setup Environment
    await download_xray()

    if not os.path.exists(INPUT_FILE):
        print(f"{INPUT_FILE} not found. Run aggregator.py first.")
        return

    with open(INPUT_FILE, "r") as f:
        configs = json.load(f)

    if not configs:
        print("No configs to test.")
        return

    print(f"Starting tests for {len(configs)} configs with concurrency {CONCURRENCY}...")

    # 2. Setup Queue and Workers
    queue = asyncio.Queue()
    for config in configs:
        queue.put_nowait(config)

    results = []
    stats = Counter()

    tasks = []
    for i in range(CONCURRENCY):
        task = asyncio.create_task(worker(queue, results, stats, i))
        tasks.append(task)

    # 3. Wait for Completion
    await asyncio.gather(*tasks)

    # 4. Summary Report
    print("\n" + "="*40)
    print("SUMMARY REPORT")
    print("="*40)
    print(f"Total Configs: {stats['total']}")
    print(f"Passed:        {stats['passed']}")
    print(f"Failed:        {stats['total'] - stats['passed']}")
    print("-" * 20)
    print("Failure Reasons:")
    for reason, count in stats.items():
        if reason not in ["total", "passed"]:
            print(f"  {reason}: {count}")
    print("="*40)

    # 5. Save Results
    # Sort by delay (fastest first)
    results.sort(key=lambda x: x[1])

    with open(OUTPUT_FILE, "w") as f:
        for config, delay in results:
            if "raw_uri" in config:
                f.write(f"{config['raw_uri']}\n")
            else:
                # Fallback if raw_uri is missing (should not happen with updated v2ray_utils)
                pass

    print(f"Saved {len(results)} passed configs to {OUTPUT_FILE}")

if __name__ == "__main__":
    asyncio.run(main())
