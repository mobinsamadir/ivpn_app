package parser

import (
	"bufio"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"regexp"
	"strconv"
	"strings"
	"time"

	"config-refinery/internal/types"
)

// Regex برای استخراج لینک‌های کانفیگ از میان متن
var configLinkRegex = regexp.MustCompile(`(vmess|vless|trojan|ss|ssr)://[a-zA-Z0-9-._~:/?#\[\]@!$&'()*+,;=%]+`)

type Parser struct {
	client *http.Client
}

// NewParser یک پارسر جدید با قابلیت تشخیص خودکار پروکسی می‌سازد
func NewParser() *Parser {
	var proxyURL *url.URL
	
	// 1. اولویت اول: تست پورت HTTP (10809) - پایدارتر برای دانلود ساب
	if isPortOpen("127.0.0.1", "10809") {
		proxyURL, _ = url.Parse("http://127.0.0.1:10809")
	} else if isPortOpen("127.0.0.1", "10808") {
		// 2. اولویت دوم: تست پورت SOCKS (10808)
		proxyURL, _ = url.Parse("socks5://127.0.0.1:10808")
		fmt.Println("   ⚠️  HTTP Proxy (10809) closed. Using SOCKS5 (10808).")
	} else {
		// 3. اگر هیچکدام باز نبود، هشدار بده (حالت Direct)
		fmt.Println("   ❌ Warning: No VPN detected on 10808/10809. Downloads might fail.")
	}

	// تنظیمات شبکه با تایم‌اوت‌های دقیق
	transport := &http.Transport{
		DialContext: (&net.Dialer{
			Timeout:   30 * time.Second,
			KeepAlive: 30 * time.Second,
		}).DialContext,
		MaxIdleConns:        100,
		IdleConnTimeout:     90 * time.Second,
		TLSHandshakeTimeout: 10 * time.Second,
		DisableKeepAlives:   false,
	}

	// اگر پروکسی پیدا شد، آن را ست کن
	if proxyURL != nil {
		transport.Proxy = http.ProxyURL(proxyURL)
	}

	return &Parser{
		client: &http.Client{
			Transport: transport,
			Timeout:   60 * time.Second, // تایم‌اوت کلی ۱ دقیقه برای هر درخواست
		},
	}
}

// تابع کمکی برای چک کردن باز بودن پورت روی لوکال‌هاست
func isPortOpen(ip, port string) bool {
	timeout := 500 * time.Millisecond
	conn, err := net.DialTimeout("tcp", net.JoinHostPort(ip, port), timeout)
	if err != nil {
		return false
	}
	if conn != nil {
		conn.Close()
		return true
	}
	return false
}

// fetchWithHeaders ارسال درخواست با هدرهای شبیه‌سازی شده مرورگر
func (p *Parser) fetchWithHeaders(url string) (*http.Response, error) {
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, err
	}

	req.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
	req.Header.Set("Accept", "text/plain,text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8")
	req.Header.Set("Connection", "keep-alive")

	return p.client.Do(req)
}

// ParseFile خواندن فایل و استخراج کانفیگ‌ها
func (p *Parser) ParseFile(filePath string) ([]types.Config, error) {
	file, err := os.Open(filePath)
	if err != nil {
		return nil, fmt.Errorf("failed to open file: %w", err)
	}
	defer file.Close()

	var configs []types.Config
	scanner := bufio.NewScanner(file)

	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		// نادیده گرفتن لینک‌های پروکسی تلگرام (باعث ارور 400 می‌شوند)
		if strings.Contains(line, "t.me/proxy") || strings.Contains(line, "tg://proxy") {
			continue
		}

		// اگر لینک سابسکریپشن بود
		if strings.HasPrefix(line, "http://") || strings.HasPrefix(line, "https://") {
			subConfigs, err := p.parseSubscriptionURL(line)
			if err != nil {
				// فقط وارنینگ چاپ کن و ادامه بده، برنامه نباید قطع شود
				fmt.Printf("      ⚠️  Warning: failed to parse sub: %v\n", err)
				continue
			}
			configs = append(configs, subConfigs...)
		} else {
			// استخراج لینک مستقیم از خط
			cleanLine := p.extractConfigLink(line)
			if cleanLine == "" {
				cleanLine = line
			}
			config, err := p.ParseDirectLink(cleanLine)
			if err == nil && config != nil {
				configs = append(configs, *config)
			}
		}
	}
	return configs, scanner.Err()
}

// ParseDirectLink پارس کردن یک لینک تکی کانفیگ
func (p *Parser) ParseDirectLink(link string) (*types.Config, error) {
	// تلاش برای دیکود اگر Base64 بود
	decodedLink, err := p.universalDecodeBase64(link)
	if err == nil {
		link = decodedLink
	}
	
	cleanLink := p.extractConfigLink(link)
	if cleanLink != "" {
		link = cleanLink
	}

	return p.parseConfigLink(link)
}

// parseSubscriptionURL دانلود سابسکریپشن با قابلیت Retry
func (p *Parser) parseSubscriptionURL(subURL string) ([]types.Config, error) {
	var resp *http.Response
	var err error

	// ۳ بار تلاش برای دانلود (Retry Logic)
	for i := 0; i < 3; i++ {
		resp, err = p.fetchWithHeaders(subURL)
		if err == nil && resp.StatusCode == http.StatusOK {
			break
		}
		time.Sleep(1 * time.Second)
	}

	if err != nil {
		return nil, fmt.Errorf("fetch failed after retries: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("bad status: %d", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	content := string(body)
	if decoded, err := p.universalDecodeBase64(content); err == nil {
		content = decoded
	}

	return p.extractConfigsFromText(content)
}

// universalDecodeBase64 دیکودر هوشمند Base64
func (p *Parser) universalDecodeBase64(input string) (string, error) {
	input = strings.TrimSpace(input)
	if input == "" {
		return "", fmt.Errorf("empty input")
	}
	
	// حذف کاراکترهای اضافی
	cleaned := strings.Map(func(r rune) rune {
		if strings.ContainsRune(" \n\r\t", r) {
			return -1
		}
		return r
	}, input)

	// اضافه کردن Padding استاندارد
	if m := len(cleaned) % 4; m != 0 {
		cleaned += strings.Repeat("=", 4-m)
	}

	// تست فرمت‌های مختلف
	if d, err := base64.StdEncoding.DecodeString(cleaned); err == nil {
		return string(d), nil
	}
	if d, err := base64.URLEncoding.DecodeString(cleaned); err == nil {
		return string(d), nil
	}
	if d, err := base64.RawStdEncoding.DecodeString(cleaned); err == nil {
		return string(d), nil
	}
	if d, err := base64.RawURLEncoding.DecodeString(cleaned); err == nil {
		return string(d), nil
	}

	return "", fmt.Errorf("invalid base64")
}

// extractConfigLink استخراج لینک با Regex
func (p *Parser) extractConfigLink(text string) string {
	matches := configLinkRegex.FindStringSubmatch(text)
	if len(matches) > 0 {
		return matches[0]
	}
	return ""
}

func (p *Parser) extractConfigsFromText(content string) ([]types.Config, error) {
	var configs []types.Config
	content = strings.ReplaceAll(content, "\r\n", "\n")
	lines := strings.Split(content, "\n")

	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}

		cleanLine := p.extractConfigLink(line)
		if cleanLine == "" {
			cleanLine = line
		}

		if config, _ := p.parseConfigLink(cleanLine); config != nil {
			configs = append(configs, *config)
		}
	}
	return configs, nil
}

func (p *Parser) parseConfigLink(link string) (*types.Config, error) {
	lowerLink := strings.ToLower(link)
	switch {
	case strings.HasPrefix(lowerLink, "vmess://"):
		return p.parseVMess(link)
	case strings.HasPrefix(lowerLink, "vless://"):
		return p.parseVLess(link)
	case strings.HasPrefix(lowerLink, "trojan://"):
		return p.parseTrojan(link)
	case strings.HasPrefix(lowerLink, "ss://"):
		return p.parseShadowsocks(link)
	case strings.HasPrefix(lowerLink, "ssr://"):
		return p.parseShadowsocksr(link)
	default:
		return nil, fmt.Errorf("unsupported protocol")
	}
}

// --- Protocol Parsers ---

func (p *Parser) parseVMess(link string) (*types.Config, error) {
	encoded := strings.TrimPrefix(link, "vmess://")
	decoded, err := p.universalDecodeBase64(encoded)
	if err != nil {
		return nil, err
	}

	var conf map[string]interface{}
	if err := json.Unmarshal([]byte(decoded), &conf); err != nil {
		return nil, err
	}

	addr, _ := conf["add"].(string)
	var port int
	switch v := conf["port"].(type) {
	case float64:
		port = int(v)
	case string:
		port, _ = strconv.Atoi(v)
	}
	id, _ := conf["id"].(string)
	ps, _ := conf["ps"].(string)

	return &types.Config{Protocol: "vmess", Address: addr, Port: port, ID: id, Remark: ps, Original: link}, nil
}

func (p *Parser) parseVLess(link string) (*types.Config, error) {
	u, err := url.Parse(link)
	if err != nil {
		return nil, err
	}
	port, _ := strconv.Atoi(u.Port())
	return &types.Config{Protocol: "vless", Address: u.Hostname(), Port: port, ID: u.User.Username(), Remark: u.Fragment, Original: link}, nil
}

func (p *Parser) parseTrojan(link string) (*types.Config, error) {
	u, err := url.Parse(link)
	if err != nil {
		return nil, err
	}
	port, _ := strconv.Atoi(u.Port())
	return &types.Config{Protocol: "trojan", Address: u.Hostname(), Port: port, ID: u.User.Username(), Remark: u.Fragment, Original: link}, nil
}

func (p *Parser) parseShadowsocks(link string) (*types.Config, error) {
	// ShadowSocks requires complex parsing for L4, so we use placeholders to be safe.
	// The Tester module handles full parsing later.
	return &types.Config{Protocol: "shadowsocks", Address: "127.0.0.1", Port: 0, Original: link}, nil
}

func (p *Parser) parseShadowsocksr(link string) (*types.Config, error) {
	return &types.Config{Protocol: "shadowsocksr", Address: "127.0.0.1", Port: 0, Original: link}, nil
}