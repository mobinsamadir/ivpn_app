package dedup

import (
	"crypto/sha256"
	"fmt"
	"config-refinery/internal/types"
)

// Deduplicator handles removal of duplicate configurations
type Deduplicator struct{}

// NewDeduplicator creates a new deduplicator instance
func NewDeduplicator() *Deduplicator {
	return &Deduplicator{}
}

// Deduplicate removes duplicate configurations based on critical fields
func (d *Deduplicator) Deduplicate(configs []types.Config) []types.Config {
	seen := make(map[string]bool)
	var uniqueConfigs []types.Config

	for _, config := range configs {
		hash := d.generateHash(config)
		if !seen[hash] {
			seen[hash] = true
			uniqueConfigs = append(uniqueConfigs, config)
		}
	}

	return uniqueConfigs
}

// generateHash creates a SHA256 hash based on critical config fields
func (d *Deduplicator) generateHash(config types.Config) string {
	// Create a string combining critical fields that determine uniqueness
	// Ignore fields like Remark that don't affect the actual connection
	key := fmt.Sprintf("%s|%s|%d|%s", config.Protocol, config.Address, config.Port, config.ID)

	// Generate SHA256 hash
	hash := sha256.Sum256([]byte(key))

	// Convert to hex string
	return fmt.Sprintf("%x", hash)
}