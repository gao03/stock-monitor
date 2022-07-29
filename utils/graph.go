package utils

import (
	"bytes"
	"fmt"
	"github.com/getlantern/systray"
	"github.com/go-rod/rod"
	"github.com/go-rod/rod/lib/devices"
	"github.com/go-rod/rod/lib/launcher"
	"github.com/go-rod/rod/lib/utils"
	"image"
	"log"
	"time"
)

var Browser *rod.Browser
var pageList = []*rod.Page{}
var pageCount = 0

func RegisterUpdateStockFigure(url string, figureMenuItem *systray.MenuItem, updateTimeMenuItem *systray.MenuItem) {
	if Browser == nil {
		Browser = newBrowser()
	}

	updateTimeMenuItem.SetTitle("更新中...")

	page := Browser.MustPage(url)
	pageList = append(pageList, page)
	pageCount++

	time.Sleep(5 * time.Second)

	if CheckIsMarketCloseDay() {
		fetchNewScreenshot(page, figureMenuItem, updateTimeMenuItem)
		// 如果是闭市，那就只执行一次
		// 执行结束就关闭浏览器
		defer func(Browser *rod.Browser) {
			pageCount--
			if pageCount == 0 && Browser != nil {
				err := Browser.Close()
				if err != nil {
					println(err)
				}
				Browser = nil
			}
		}(Browser)
	} else {
		NewTicker(10*time.Second, func() {
			fetchNewScreenshot(page, figureMenuItem, updateTimeMenuItem)
		})
		updateSelfFunc := func() {
			RegisterUpdateStockFigure(url, figureMenuItem, updateTimeMenuItem)
		}
		On(figureMenuItem.ClickedCh, updateSelfFunc)
		On(updateTimeMenuItem.ClickedCh, updateSelfFunc)
	}
}

func newBrowser() *rod.Browser {
	device := devices.Device{
		Capabilities: []string{
			"touch",
			"desktop",
		},
		Screen: devices.Screen{
			DevicePixelRatio: 3,
			Horizontal: devices.ScreenSize{
				Height: 1024,
				Width:  1024,
			},
			Vertical: devices.ScreenSize{
				Height: 1024,
				Width:  1024,
			},
		},
		Title:     "IPad",
		UserAgent: "Mozilla/5.0 (iPad; CPU OS 11_0 like Mac OS X) AppleWebKit/604.1.34 (KHTML, like Gecko) Version/11.0 Mobile/15A5341f Safari/604.1",
	}
	launch := launcher.New().Bin("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome").Headless(true).MustLaunch()
	browser := rod.New().ControlURL(launch).MustConnect().DefaultDevice(device)
	return browser
}

func fetchNewScreenshot(page *rod.Page, figureMenuItem *systray.MenuItem, updateTimeMenuItem *systray.MenuItem) {
	defer func() {
		if err := recover(); err != nil {
			fmt.Println(err)
		}
	}()
	screenshot, err := elementScreenshot(page.MustElement(".snbchart"))
	if err != nil {
		log.Fatalln("err in image", err)
	} else {
		screenshotConfig, _, err := image.DecodeConfig(bytes.NewBuffer(screenshot))
		width, height := 500.0, 300.0
		if err == nil {
			height = float64(screenshotConfig.Height) * (width / float64(screenshotConfig.Width))
		}
		figureMenuItem.SetIconWithSize(screenshot, uint32(width), uint32(height))
		updateTime := time.Now().Format("15:04:05")
		updateTimeMenuItem.SetTitle("更新时间：" + updateTime)
	}
}

func elementScreenshot(element *rod.Element) ([]byte, error) {
	page := element.Page()
	screenshot, err := page.Screenshot(false, nil)
	if err != nil {
		return nil, err
	}
	bodyElement, err := page.Element("body")
	if err != nil {
		return nil, err
	}
	bodyShape, err := bodyElement.Shape()
	if err != nil {
		return nil, err
	}
	pageBox := bodyShape.Box()

	screenshotConfig, _, err := image.DecodeConfig(bytes.NewBuffer(screenshot))
	if err != nil {
		log.Fatalln(err)
		return nil, err
	}
	box := element.MustShape().Box()
	diff := float64(screenshotConfig.Width) / pageBox.Width

	return utils.CropImage(screenshot, 0,
		int(box.X*diff),
		int(box.Y*diff),
		int(box.Width*diff),
		int(box.Height*diff),
	)
}
