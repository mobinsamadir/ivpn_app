package scanner

import (
	"fmt"
	"net"
	"sync"
	"time"

	"config-refinery/internal/types"
)

type Scanner struct {
	Timeout time.Duration // با حرف بزرگ (Public) برای دسترسی در main.go
}

func NewScanner() *Scanner {
	return &Scanner{
		Timeout: 800 * time.Millisecond, // مقدار پیش‌فرض
	}
}

// ScanConfigs انجام تست TCP سریع روی لیست کانفیگ‌ها
func (s *Scanner) ScanConfigs(configs []types.Config) []types.Config {
	// کانال برای جمع‌آوری نتایج (Buffered برای جلوگیری از بلاک شدن)
	results := make(chan types.Config, len(configs))
	var wg sync.WaitGroup

	// سمافور برای کنترل تعداد همزمان (1000 ترد)
	// این روش از Worker Pool ساده‌تر و به همان اندازه کارآمد است
	semaphore := make(chan struct{}, 1000)

	for _, config := range configs {
		wg.Add(1)
		go func(cfg types.Config) {
			defer wg.Done()
			
			semaphore <- struct{}{} // گرفتن اجازه اجرا (Slot)
			
			if s.isAlive(cfg) {
				results <- cfg
			}
			
			<-semaphore // آزاد کردن اسلات
		}(config)
	}

	// بستن کانال نتایج وقتی تمام تسک‌ها تمام شدند
	go func() {
		wg.Wait()
		close(results)
	}()

	// جمع‌آوری کانفیگ‌های سالم از کانال
	var liveConfigs []types.Config
	for config := range results {
		liveConfigs = append(liveConfigs, config)
	}

	return liveConfigs
}

// isAlive تست اتصال TCP به پورت سرور
func (s *Scanner) isAlive(config types.Config) bool {
	if config.Address == "" || config.Port == 0 {
		return false
	}

	address := fmt.Sprintf("%s:%d", config.Address, config.Port)
	
	// استفاده از s.Timeout که الان در main.go قابل تنظیم است
	conn, err := net.DialTimeout("tcp", address, s.Timeout)
	if err != nil {
		return false
	}
	if conn != nil {
		conn.Close()
		return true
	}
	return false
}