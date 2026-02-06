package wifi

import (
	"fmt"
	"os/exec"
	"strings"
)

type WiFiDetector struct{}

func NewWiFiDetector() *WiFiDetector {
	return &WiFiDetector{}
}

// GetCurrentSSID نام وای‌فای متصل شده را برمی‌گرداند
func (w *WiFiDetector) GetCurrentSSID() (string, error) {
	// دستور مخصوص ویندوز برای گرفتن اطلاعات وای‌فای
	cmd := exec.Command("netsh", "wlan", "show", "interfaces")
	output, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("failed to execute netsh: %w", err)
	}

	outputStr := string(output)
	lines := strings.Split(outputStr, "\n")

	for _, line := range lines {
		line = strings.TrimSpace(line)
		// دنبال خطی می‌گردیم که با "SSID" شروع شود (اما نه BSSID)
		if strings.Contains(line, " SSID") && !strings.Contains(line, "BSSID") {
			parts := strings.Split(line, ":")
			if len(parts) > 1 {
				ssid := strings.TrimSpace(parts[1])
				if ssid != "" {
					return ssid, nil
				}
			}
		}
	}

	return "", fmt.Errorf("no wifi connection found")
}