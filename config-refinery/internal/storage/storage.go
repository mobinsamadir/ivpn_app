package storage

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"config-refinery/internal/dedup"
	"config-refinery/internal/parser"
	"config-refinery/internal/types"
)

const (
	MasterFile = "master_configs.txt"
)

// UpdateMasterFile adds new configs to the master file, deduplicates them, and returns all configs
func UpdateMasterFile(newConfigs []types.Config) ([]types.Config, error) {
	// Read existing configs from the master file if it exists
	existingConfigs, err := readMasterFile()
	if err != nil {
		// If file doesn't exist, start with empty slice
		if !os.IsNotExist(err) {
			return nil, fmt.Errorf("failed to read master file: %w", err)
		}
		existingConfigs = []types.Config{}
	}

	// Combine existing and new configs
	allConfigs := append(existingConfigs, newConfigs...)

	// Deduplicate the configs
	d := dedup.NewDeduplicator()
	uniqueConfigs := d.Deduplicate(allConfigs)

	// Write all unique configs back to the master file
	err = writeMasterFile(uniqueConfigs)
	if err != nil {
		return nil, fmt.Errorf("failed to write master file: %w", err)
	}

	return uniqueConfigs, nil
}

// LoadMasterFile reads and parses all configs from the master file
func LoadMasterFile() ([]types.Config, error) {
	return readMasterFile()
}

// readMasterFile reads configs from the master file
func readMasterFile() ([]types.Config, error) {
	file, err := os.Open(MasterFile)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	var configs []types.Config
	scanner := bufio.NewScanner(file)
	p := parser.NewParser()

	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			continue
		}

		// Parse the config link to get a proper Config struct
		config, err := p.ParseDirectLink(line)
		if err != nil {
			// If parsing fails, skip this line but continue processing others
			fmt.Printf("Warning: failed to parse config '%s': %v\n", line, err)
			continue
		}
		if config != nil {
			configs = append(configs, *config)
		}
	}

	return configs, scanner.Err()
}

// writeMasterFile writes configs to the master file
func writeMasterFile(configs []types.Config) error {
	// Create the file (will overwrite existing)
	file, err := os.Create(MasterFile)
	if err != nil {
		return err
	}
	defer file.Close()

	writer := bufio.NewWriter(file)
	defer writer.Flush()

	for _, config := range configs {
		_, err := writer.WriteString(config.Original + "\n")
		if err != nil {
			return err
		}
	}

	return nil
}

// SaveTempConfigs saves configs to a temporary file for recovery
func SaveTempConfigs(configs []types.Config, stage string) error {
	tempDir := "temp"
	if err := os.MkdirAll(tempDir, 0755); err != nil {
		return fmt.Errorf("failed to create temp directory: %w", err)
	}

	filename := filepath.Join(tempDir, fmt.Sprintf("configs_%s.txt", stage))
	file, err := os.Create(filename)
	if err != nil {
		return err
	}
	defer file.Close()

	writer := bufio.NewWriter(file)
	for _, config := range configs {
		writer.WriteString(config.Original + "\n")
	}
	writer.Flush()

	return nil
}