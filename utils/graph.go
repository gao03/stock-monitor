package utils

import (
	"github.com/getlantern/systray"
	"github.com/go-rod/rod"
	"github.com/go-rod/rod/lib/devices"
	"github.com/go-rod/rod/lib/launcher"
	"github.com/go-rod/rod/lib/utils"
	"log"
	"strings"
	"time"
)

var BROWSER *rod.Browser

func RegisterUpdateStockFigure(url string, figureMenuItem *systray.MenuItem, updateTimeMenuItem *systray.MenuItem) {
	if BROWSER == nil {
		BROWSER = newBrowser()
	}
	NewTicker(1*time.Minute, func() {
		updateStockFigure(url, figureMenuItem, updateTimeMenuItem)
	})
}

func newBrowser() *rod.Browser {
	iPhoneX := devices.Device{
		Capabilities: []string{
			"touch",
			"mobile",
		},
		Screen: devices.Screen{
			DevicePixelRatio: 3,
			Horizontal: devices.ScreenSize{
				Height: 375,
				Width:  812,
			},
			Vertical: devices.ScreenSize{
				Height: 812,
				Width:  375,
			},
		},
		Title:     "iPhone X",
		UserAgent: "Mozilla/5.0 (iPhone; CPU iPhone OS 13_2_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/13.0.3 Mobile/15E148 Safari/604.1 Edg/86.0.4240.111",
	}

	launch := launcher.New().Bin("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome").MustLaunch()
	browser := rod.New().ControlURL(launch).MustConnect().DefaultDevice(iPhoneX)
	return browser
}

func updateStockFigure(url string, figureMenuItem *systray.MenuItem, updateTimeMenuItem *systray.MenuItem) {
	print("更新中")
	println(url)
	updateTimePrefix := "更新时间："
	if CheckIsMarketClose() {
		// 如果是闭市，那就只执行一次
		if strings.Contains(updateTimeMenuItem.String(), updateTimePrefix) {
			return
		}
	}

	updateTimeMenuItem.SetTitle("更新中...")

	page := BROWSER.MustPage(url)

	time.Sleep(5 * time.Second)

	screenshot := page.MustScreenshot()
	image, err := utils.CropImage(screenshot, 0, 0, 520, 1125, 800)
	if err != nil {
		log.Fatalln("err in image", err)
	} else {
		figureMenuItem.SetIconWithSize(image, 375, 240)
		updateTime := time.Now().Format("15:04:05")
		updateTimeMenuItem.SetTitle(updateTimePrefix + updateTime)
	}

	updateSelfFunc := func() {
		updateStockFigure(url, figureMenuItem, updateTimeMenuItem)
	}
	On(figureMenuItem.ClickedCh, updateSelfFunc)
	On(updateTimeMenuItem.ClickedCh, updateSelfFunc)
}
