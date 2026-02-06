package main

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"config-refinery/internal/dedup"
	"config-refinery/internal/parser"
	"config-refinery/internal/scanner"
	"config-refinery/internal/storage"
	"config-refinery/internal/tester"
	"config-refinery/internal/types"
	"config-refinery/internal/wifi"
)

const (
	InputDir  = "internal/inputs"
	OutputDir = "output"
	TempDir   = "temp"
	CacheFile = "2_unique.txt"
)

func main() {
	fmt.Println("╔══════════════════════════════════════════════╗")
	fmt.Println("║      Config Refinery - Speed & Stability     ║")
	fmt.Println("╚══════════════════════════════════════════════╝")
	
	startTime := time.Now()
	createDirectories()
	
	var configsToTest []types.Config
	usingCache := false

	// --- 1. Smart Resume System ---
	if fileExists(filepath.Join(OutputDir, CacheFile)) {
		fmt.Println("\n[?] Found cached data.")
		fmt.Print("    Use cache and SKIP download? (y/n): ")
		
		scanner := bufio.NewScanner(os.Stdin)
		if scanner.Scan() {
			response := strings.ToLower(strings.TrimSpace(scanner.Text()))
			if response == "y" || response == "yes" || response == "" {
				usingCache = true
				fmt.Println("\n[1/5] 📦 Loading from Cache...")
				configsToTest = loadConfigsFromFile(filepath.Join(OutputDir, CacheFile))
				fmt.Printf("    ✓ Loaded %d configs.\n", len(configsToTest))
				goto L4_SCAN
			}
		}
	}

	// --- 2. Download Phase ---
	if !usingCache {
		fmt.Println("\n⚠️  Action: CONNECT VPN to download subscriptions.")
		fmt.Print("    Press ENTER when ready...")
		fmt.Scanln()
	}

	fmt.Println("\n[1/5] 📥 Scanning Sources...")
	{
		parsedConfigs, err := parseInputDirectory()
		if err != nil || len(parsedConfigs) == 0 {
			fmt.Println("❌ No configs found.")
			os.Exit(1)
		}
		saveCheckpoint("1_all_parsed.txt", parsedConfigs)

		fmt.Println("\n[2/5] 🗑️  Deduplication...")
		uniqueConfigs := dedupConfigs(parsedConfigs)
		saveCheckpoint(CacheFile, uniqueConfigs)
		storage.UpdateMasterFile(uniqueConfigs)
		
		configsToTest = uniqueConfigs
	}

L4_SCAN:
	// --- 3. L4 Scan ---
	fmt.Println("\n[3/5] 🔍 L4 Filtration (TCP Check)...")
	liveConfigs := performTCPFiltering(configsToTest)
	if len(liveConfigs) == 0 {
		fmt.Println("❌ No live L4 configs.")
		os.Exit(0)
	}
	saveCheckpoint("3_live_l4.txt", liveConfigs)

	// --- 4. L7 Test ---
	fmt.Println("\n[4/5] ⚡ L7 Verification (High Precision)...")
	fmt.Println("🛑 ACTION: DISCONNECT VPN NOW to prevent loopback errors!")
	fmt.Print("    Press ENTER to start mining: ")
	fmt.Scanln()

	fmt.Printf("    Target: %d configs | Workers: 20\n", len(liveConfigs))
	
	validConfigs := performL7Testing(liveConfigs)
	
	if len(validConfigs) == 0 {
		fmt.Println("\n❌ No valid configs found.")
		fmt.Println("💡 Tip: Check 'output/debug_errors.log'")
		os.Exit(0)
	}

	// --- 5. Save Results ---
	fmt.Println("\n\n[5/5] 💾 Saving Results...")
	baseName := getSessionName()
	sortAndWriteOutput(validConfigs, baseName)
	
	printStatistics(len(configsToTest), len(liveConfigs), len(validConfigs), time.Since(startTime))
}

// --- Helper Functions ---

func createDirectories() {
	os.MkdirAll(InputDir, 0755)
	os.MkdirAll(OutputDir, 0755)
	os.MkdirAll(TempDir, 0755)
}

func fileExists(filename string) bool {
	info, err := os.Stat(filename)
	if os.IsNotExist(err) { return false }
	return !info.IsDir()
}

func loadConfigsFromFile(path string) []types.Config {
	p := parser.NewParser()
	configs, _ := p.ParseFile(path)
	return configs
}

func parseInputDirectory() ([]types.Config, error) {
	files, _ := os.ReadDir(InputDir)
	var allConfigs []types.Config
	p := parser.NewParser()
	
	for _, file := range files {
		if file.IsDir() { continue }
		path := filepath.Join(InputDir, file.Name())
		fmt.Printf("    ➜ %s\n", file.Name())
		configs, _ := p.ParseFile(path)
		if len(configs) > 0 {
			allConfigs = append(allConfigs, configs...)
		}
	}
	return allConfigs, nil
}

func saveCheckpoint(filename string, configs []types.Config) {
	path := filepath.Join(OutputDir, filename)
	file, _ := os.Create(path)
	defer file.Close()
	for _, c := range configs {
		file.WriteString(c.Original + "\n")
	}
}

func dedupConfigs(configs []types.Config) []types.Config {
	d := dedup.NewDeduplicator()
	return d.Deduplicate(configs)
}

func performTCPFiltering(configs []types.Config) []types.Config {
	s := scanner.NewScanner()
	s.Timeout = 2000 * time.Millisecond // 2 ثانیه برای شناسایی سرورهای کند ولی خوب
	return s.ScanConfigs(configs)
}

func performL7Testing(configs []types.Config) []types.Config {
	t, err := tester.NewTester()
	if err != nil {
		fmt.Printf("❌ Error: %v\n", err)
		return nil
	}

	progressChan := make(chan int)
	total := len(configs)
	
	go func() {
		processed := 0
		for range progressChan {
			processed++
			fmt.Printf("\r    ⏳ Testing: [%d/%d] (%d%%) ", processed, total, (processed*100)/total)
		}
	}()

	testedConfigs := t.TestConfigs(configs, progressChan)
	close(progressChan)

	var valid []types.Config
	for _, c := range testedConfigs {
		// پینگ زیر 3000 میلی‌ثانیه یعنی قابل استفاده
		if c.Latency > 0 && c.Latency < 3000 {
			valid = append(valid, c)
		}
	}
	return valid
}

// ساخت نام فایل بر اساس وای‌فای یا زمان
func getSessionName() string {
	w := wifi.NewWiFiDetector()
	ssid, err := w.GetCurrentSSID()
	
	timestamp := time.Now().Format("2006-01-02_15-04") // مثلا: 2024-05-20_18-30
	
	if err != nil || ssid == "" {
		// اگر وای‌فای نبود، فقط زمان
		return fmt.Sprintf("Export_%s", timestamp)
	}
	
	// اگر وای‌فای بود: WiFiName_Timestamp
	safeSSID := sanitizeFilename(ssid)
	return fmt.Sprintf("%s_%s", safeSSID, timestamp)
}

func sortAndWriteOutput(configs []types.Config, baseName string) {
	// مرتب‌سازی بر اساس پینگ
	sort.Slice(configs, func(i, j int) bool { return configs[i].Latency < configs[j].Latency })
	
	fileName := fmt.Sprintf("%s.txt", baseName)
	path := filepath.Join(OutputDir, fileName)
	
	f, _ := os.Create(path)
	defer f.Close()
	
	f.WriteString(fmt.Sprintf("// Config Refinery Export | %s\n", baseName))
	f.WriteString(fmt.Sprintf("// Count: %d | Sorted by Latency\n\n", len(configs)))
	
	for _, c := range configs {
		f.WriteString(fmt.Sprintf("[%dms] %s\n", c.Latency, c.Original))
	}
	fmt.Printf("    ✅ Saved to: %s\n", path)
}

func sanitizeFilename(name string) string {
	invalidChars := []string{"<", ">", ":", "\"", "/", "\\", "|", "?", "*"}
	for _, char := range invalidChars {
		name = strings.ReplaceAll(name, char, "_")
	}
	return strings.TrimSpace(name)
}

func printStatistics(total, l4, l7 int, duration time.Duration) {
	fmt.Println("\n" + strings.Repeat("═", 50))
	fmt.Printf("📊 Done in %v\n", duration.Round(time.Second))
	fmt.Printf("   • Scanned: %d\n", total)
	fmt.Printf("   • Online:  %d\n", l4)
	fmt.Printf("   • VALID:   %d\n", l7)
	fmt.Println(strings.Repeat("═", 50))
}