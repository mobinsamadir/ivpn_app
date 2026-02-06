package types

// Config represents a VPN configuration
type Config struct {
	Protocol string
	Address  string
	Port     int
	ID       string // For VMess/VLESS/Trojan, Password for SS/SSR
	Remark   string
	Original string
	Latency  int // Added for sorting later
}