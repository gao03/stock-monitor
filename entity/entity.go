package entity

import (
	"github.com/getlantern/systray"
)

type Stock struct {
	Code        string
	CurrentInfo StockCurrentInfo
	Config      StockConfig
	MenuItem    *systray.MenuItem
}

type StockConfig struct {
	Code              string   `json:"code"`
	Type              *int     `json:"type"`
	CostPrice         float64  `json:"cost"`
	Position          float64  `json:"position"`
	Name              string   `json:"name"`
	ShowInTitle       *bool    `json:"showInTitle"`
	EnableRealTimePic bool     `json:"enableRealTimePic"`
	MonitorRules      []string `json:"monitorRules"`
}

type StockCurrentInfo struct {
	Price        float64 `json:"f2"`
	Diff         float64 `json:"f3"`
	Code         string  `json:"f12"`
	Type         int     `json:"f13"` // 0-SH,1-SZ
	Name         string  `json:"f14"`
	HighestPrice float64 `json:"f15"`
	OpenPrice    float64 `json:"f16"`
	BasePrice    float64 `json:"f18"`
	StockCode    string  `json:"f232"` // 转债对应的正股
}

// StockOutPrice 盘前/盘后价格
type StockOutPrice struct {
	Price float64
	Diff  float64
}
