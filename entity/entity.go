package entity

import (
	"github.com/getlantern/systray"
	"monitor/api"
	"monitor/config"
)

type Stock struct {
	Code        string
	CurrentInfo api.StockCurrentInfo
	Config      config.StockConfig
	MenuItem    *systray.MenuItem
}
