package tester

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"syscall"
	"time"

	"config-refinery/internal/types"
)

type Tester struct {
	singBoxPath string
	maxWorkers  int
	debugFile   *os.File
	mu          sync.Mutex
}

func NewTester() (*Tester, error) {
	possiblePaths := []string{"./bin/sing-box.exe", "./sing-box.exe", "sing-box.exe"}
	var singBoxPath string
	for _, path := range possiblePaths {
		if _, err := os.Stat(path); err == nil {
			singBoxPath = path
			break
		}
	}
	if singBoxPath == "" {
		if ex, err := os.Executable(); err == nil {
			singBoxPath = filepath.Join(filepath.Dir(ex), "bin", "sing-box.exe")
		}
	}
	if _, err := os.Stat(singBoxPath); err != nil {
		return nil, fmt.Errorf("sing-box.exe not found")
	}

	os.MkdirAll("output", 0755)
	debugFile, _ := os.Create("output/debug_errors.log")

	return &Tester{
		singBoxPath: singBoxPath,
		maxWorkers:  20,
		debugFile:   debugFile,
	}, nil
}

func (t *Tester) logError(config types.Config, err error, detail string) {
	t.mu.Lock()
	defer t.mu.Unlock()
	if t.debugFile != nil {
		msg := fmt.Sprintf("[%s] Config: %s | Error: %v | Log: %s\n--------------------\n", 
			time.Now().Format("15:04:05"), config.Address, err, detail)
		t.debugFile.WriteString(msg)
	}
}

func (t *Tester) TestConfigs(configs []types.Config, notify chan<- int) []types.Config {
	if len(configs) == 0 { return configs }

	jobs := make(chan types.Config, len(configs))
	results := make(chan types.Config, len(configs))
	var wg sync.WaitGroup
	semaphore := make(chan struct{}, t.maxWorkers)

	go func() {
		wg.Wait()
		close(results)
		if t.debugFile != nil { t.debugFile.Close() }
	}()

	for i := 0; i < t.maxWorkers; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for config := range jobs {
				semaphore <- struct{}{}
				
				latency, err := t.MeasureLatency(config)
				if err != nil {
					config.Latency = 9999
				} else {
					config.Latency = latency
				}
				results <- config
				
				if notify != nil { notify <- 1 }
				<-semaphore
			}
		}()
	}

	go func() {
		for _, config := range configs { jobs <- config }
		close(jobs)
	}()

	var final []types.Config
	for c := range results { final = append(final, c) }
	return final
}

func (t *Tester) getFreePort() (int, error) {
	addr, err := net.ResolveTCPAddr("tcp4", "127.0.0.1:0")
	if err != nil { return 0, err }
	l, err := net.ListenTCP("tcp4", addr)
	if err != nil { return 0, err }
	defer l.Close()
	return l.Addr().(*net.TCPAddr).Port, nil
}

func (t *Tester) waitForPort(port int, timeout time.Duration) bool {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		conn, err := net.DialTimeout("tcp4", fmt.Sprintf("127.0.0.1:%d", port), 200*time.Millisecond)
		if err == nil {
			conn.Close()
			return true
		}
		time.Sleep(200 * time.Millisecond)
	}
	return false
}

func (t *Tester) MeasureLatency(config types.Config) (int, error) {
	localPort, err := t.getFreePort()
	if err != nil { return 0, err }

	singBoxConfig := t.generateSingBoxConfig(config, localPort)
	tempFile, err := os.CreateTemp("", "sb_*.json")
	if err != nil { return 0, err }
	defer os.Remove(tempFile.Name())

	json.NewEncoder(tempFile).Encode(singBoxConfig)
	tempFile.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	// FIX: Removed "-D" flag which caused the crash
	cmd := exec.CommandContext(ctx, t.singBoxPath, "run", "-c", tempFile.Name(), "--disable-color")
	if runtime.GOOS == "windows" {
		cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
	}
	
	var stderr bytes.Buffer
	cmd.Stderr = &stderr

	if err := cmd.Start(); err != nil { return 0, err }

	if !t.waitForPort(localPort, 8*time.Second) {
		cmd.Process.Kill()
		t.logError(config, fmt.Errorf("timeout port"), stderr.String())
		return 0, fmt.Errorf("timeout")
	}

	proxyUrl, _ := url.Parse(fmt.Sprintf("socks5://127.0.0.1:%d", localPort))
	client := &http.Client{
		Transport: &http.Transport{Proxy: http.ProxyURL(proxyUrl), DisableKeepAlives: true},
		Timeout: 5 * time.Second,
	}

	var lastErr error
	for i := 0; i < 2; i++ { 
		start := time.Now()
		resp, err := client.Head("http://www.gstatic.com/generate_204")
		if err == nil {
			resp.Body.Close()
			if resp.StatusCode == 204 || resp.StatusCode == 200 {
				if cmd.Process != nil { cmd.Process.Kill() }
				return int(time.Since(start).Milliseconds()), nil
			}
		}
		lastErr = err
		time.Sleep(300 * time.Millisecond)
	}
	
	if cmd.Process != nil { cmd.Process.Kill() }
	
	// Only log real failures (not just timeouts)
	if lastErr != nil {
		t.logError(config, lastErr, stderr.String())
	}
	
	return 0, fmt.Errorf("fail")
}

func (t *Tester) generateSingBoxConfig(config types.Config, localPort int) map[string]interface{} {
	dnsConfig := map[string]interface{}{
		"servers": []map[string]interface{}{
			{"tag": "google", "address": "8.8.8.8", "detour": "proxy"},
			{"tag": "local", "address": "local", "detour": "direct"},
		},
		"rules": []map[string]interface{}{
			{"outbound": "any", "server": "google"},
		},
	}

	sbConfig := map[string]interface{}{
		"log": map[string]interface{}{"level": "error", "output": "stderr"},
		"dns": dnsConfig,
		"inbounds": []map[string]interface{}{
			{"type": "socks", "tag": "in", "listen": "127.0.0.1", "listen_port": localPort},
		},
		"outbounds": []map[string]interface{}{},
	}
	
	outbound := map[string]interface{}{
		"type": config.Protocol, 
		"tag": "proxy", 
		"server": config.Address, 
		"server_port": config.Port,
	}
	
	switch config.Protocol {
	case "vmess":
		outbound["uuid"] = config.ID
		outbound["security"] = "auto"
		outbound["tls"] = map[string]interface{}{"enabled": true, "server_name": config.Address, "insecure": true}
	case "vless":
		outbound["uuid"] = config.ID
		outbound["tls"] = map[string]interface{}{"enabled": true, "server_name": config.Address, "insecure": true}
	case "trojan":
		outbound["password"] = config.ID
		outbound["tls"] = map[string]interface{}{"enabled": true, "server_name": config.Address, "insecure": true}
	case "shadowsocks":
		parts := t.parseShadowsocksConfig(config.Original)
		outbound["method"] = parts.method
		outbound["password"] = parts.password
	}
	
	direct := map[string]interface{}{"type": "direct", "tag": "direct"}
	sbConfig["outbounds"] = []map[string]interface{}{outbound, direct}
	return sbConfig
}

type ssParts struct { method, password string }
func (t *Tester) parseShadowsocksConfig(original string) ssParts {
	parts := strings.Split(original, "ss://")
	if len(parts) > 1 {
		encodedPart := strings.Split(parts[1], "@")[0]
		decodedBytes, err := base64.StdEncoding.DecodeString(encodedPart)
		if err != nil {
			decodedBytes, err = base64.URLEncoding.DecodeString(encodedPart)
		}
		if err == nil {
			str := string(decodedBytes)
			if idx := strings.Index(str, ":"); idx != -1 {
				return ssParts{method: str[:idx], password: str[idx+1:]}
			}
		}
	}
	return ssParts{method: "chacha20-ietf-poly1305", password: "example"}
}
func (t *Tester) parseShadowsocksrConfig(original string) ssParts {
	return ssParts{method: "chacha20", password: "example"}
}