# Config-Refinery

A high-performance CLI tool to process, filter, and test V2Ray/Sing-box configurations from subscription links.

## Features

- **Streaming Processing**: Efficiently handles large numbers of configurations without loading everything into memory
- **Multi-stage Filtering**: L4 (TCP handshake) and L7 (latency testing) verification
- **Protocol Support**: vmess, vless, trojan, shadowsocks (ss), shadowsocksr (ssr)
- **Progress Tracking**: Real-time progress bar showing processing status
- **WiFi-aware Output**: Automatically detects current WiFi SSID and saves results to a file named after it
- **Deduplication**: Removes duplicate configurations based on critical fields

## Architecture

The tool follows a pipeline pattern:
```
Ingest -> Parse -> Scan -> Test -> Save
```

1. **Ingest**: Reads lines from `subs.txt`
2. **Parse**: Converts subscription URLs and direct config links to structured configs
3. **Scan (Stage 1)**: Performs fast TCP handshake tests with worker pool (500 concurrent workers)
4. **Test (Stage 2)**: Performs L7 verification using sing-box.exe to measure latency
5. **Save**: Outputs sorted configurations to `./output/[SSID_NAME].txt`

## Requirements

- Go 1.21+
- sing-box.exe in `./bin/` directory (for L7 testing)

## Installation

1. Clone the repository
2. Install dependencies: `go mod tidy`
3. Place `sing-box.exe` in the `./bin/` directory (optional, skipping will skip L7 testing)
4. Build: `go build -o config-refinery.exe main.go`

## Usage

1. Prepare your `subs.txt` file with mixed content (Direct config links, Subscription URLs)
2. Run the application: `./config-refinery.exe`
3. Results will be saved to `./output/[YOUR_WIFI_SSID].txt`

## Configuration File Format

The `subs.txt` file can contain:
- Direct configuration links (vmess://, vless://, trojan://, ss://, ssr://)
- Subscription URLs
- Comments starting with `#`

Example:
```
# VMess example
vmess://eyJhZGQiOiJleGFtcGxlLmNvbSIsInBvcnQiOjQ0MywiaWQiOiJhYWFhYWFhYS1iYmJiLWNjY2MtZGRkZC1lZWVlZWVlZWVlZWUiLCJhaWQiOjY0LCJzY3kiOiJhdXRvIiwibmV0Ijoid3MiLCJ0eXBlIjoiIiwicHMiOiJFeGFtcGxlIFZNRXNzIENvbmZpZyIsInRscyI6InRscyIsInNuaSI6ImV4YW1wbGUuY29tIiwicGF0aCI6Ii9hcGkvdjEvcmF5In0=

# VLess example
vless://aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee@vless.example.com:443?encryption=none&type=ws&host=vless.example.com&path=/path#VLessExample

# Subscription URL
https://raw.githubusercontent.com/example/subscriptions/main/configs.txt
```

## Output Format

The output file contains configurations sorted by latency in ascending order:
```
[125ms] vmess://...
[142ms] vless://...
[168ms] trojan://...
```

## Performance Notes

- Stage 1 (L4 filtering) uses a worker pool with 500 concurrent connections
- Connection timeout is set to 2 seconds for fast TCP handshake testing
- Memory usage is kept low by streaming data through channels
- Progress bar updates in real-time to show processing status