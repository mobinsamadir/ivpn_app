package utils

import (
	"math/rand"
	"time"

	"config-refinery/internal/types"
)

// SimulateLatencyTest simulates a latency test for a config
// In a real implementation, this would call sing-box to test the config
func SimulateLatencyTest(config types.Config) int {
	// Simulate a random latency between 50-1000ms
	rand.Seed(time.Now().UnixNano())
	return rand.Intn(950) + 50
}