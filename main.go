package main

import (
	"github.com/getlantern/systray"
	"github.com/kardianos/osext"
	"log"
	"monitor/api"
	"monitor/config"
	"monitor/entity"
	"monitor/utils"
	"os"
	"os/exec"
	"strings"
	"syscall"
	"time"
)

func main() {
	systray.Run(onReady, func() {
		if utils.Browser != nil {
			defer utils.Browser.Close()
		}
	})
}

func onReady() {
	systray.SetTitle("monitor")

	flag := false
	codeToMenuItemMap := make(map[string]*systray.MenuItem)

	duration := 2 * time.Second

	utils.NewTicker(duration, func() {
		updateStockInfo(&flag, codeToMenuItemMap)
	})

	time.AfterFunc(duration, func() {
		systray.AddSeparator()
		addMenuItem("配置", openConfigFileAndWait)
		addMenuItem("重启", restartSelf)
		addMenuItem("退出", systray.Quit)
	})
}

func restartSelf() {
	self, err := osext.Executable()
	if err != nil {
		log.Fatalln(err)
		return
	}
	args := os.Args
	env := os.Environ()
	err = syscall.Exec(self, args, env)
	if err != nil {
		log.Fatalln(err)
	}
}

func addMenuItem(title string, onClick func()) *systray.MenuItem {
	menu := systray.AddMenuItem(title, "")
	utils.On(menu.ClickedCh, onClick)
	return menu
}

func addSubMenuItem(menu *systray.MenuItem, title string, onClick func()) *systray.MenuItem {
	subMenu := menu.AddSubMenuItem(title, "")
	if onClick != nil {
		utils.On(subMenu.ClickedCh, onClick)
	}
	return subMenu
}

func updateStockInfo(flag *bool, codeToMenuItemMap map[string]*systray.MenuItem) {
	if utils.CheckIsMarketClose() {
		// map 为空表示程序还没运行，先让它执行一次
		if len(codeToMenuItemMap) > 0 {
			return
		}
	}

	stockConfigList := config.ReadConfig()
	if len(*stockConfigList) == 0 {
		return
	}

	codeList := make([]string, len(*stockConfigList))
	for i, v := range *stockConfigList {
		codeList[i] = v.Code
	}

	infoMap := api.QueryStockInfo(codeList)

	var stockList []*entity.Stock
	for _, item := range *stockConfigList {
		current, ok := infoMap[item.Code]
		if !ok {
			continue
		}
		menu, ok := codeToMenuItemMap[item.Code]
		if !ok {
			menu = addMenuItem(item.Code, func() {
				exec.Command("open", GenerateXueqiuUrl(&current)).Start()
			})
			codeToMenuItemMap[item.Code] = menu

			figureMenuItem := addSubMenuItem(menu, "", nil)
			updateTimeMenuItem := addSubMenuItem(menu, "查询中...", nil)

			go utils.RegisterUpdateStockFigure(GenerateXueqiuUrl(&current), figureMenuItem, updateTimeMenuItem)
		}
		stock := entity.Stock{
			Code:        item.Code,
			Config:      item,
			CurrentInfo: current,
			MenuItem:    menu,
		}
		stockList = append(stockList, &stock)
		updateSubMenuTitle(&stock)
	}
	systray.SetTitle(generateTitle(flag, stockList))
}

func GenerateXueqiuUrl(current *api.StockCurrentInfo) string {
	url := "https://xueqiu.com/S/S"
	if current.Type == 0 {
		url += "Z"
	} else {
		url += "H"
	}
	return url + current.Code
}

func updateSubMenuTitle(stock *entity.Stock) {
	var result = stock.CurrentInfo.Name + "\t" +
		utils.FloatToStr(stock.CurrentInfo.Price) + "\t" +
		utils.FloatToStr(stock.CurrentInfo.Diff)

	stock.MenuItem.SetTitle(result)
}

func generateTitle(flag *bool, stockList []*entity.Stock) string {
	currentTotal := 0.0
	totalCost := 0.0
	var priceList = make([]string, len(stockList))
	for idx, stock := range stockList {
		currentTotal += stock.CurrentInfo.Price * stock.Config.Position
		totalCost += stock.Config.CostPrice * stock.Config.Position
		priceList[idx] = utils.FloatToStr(stock.CurrentInfo.Price)
	}
	var result = "●"
	if *flag {
		result = "○"
	}
	*flag = !*flag

	if totalCost > 0 {
		diff := (currentTotal/totalCost - 1) * 100
		result = result + utils.FloatToStr(diff) + "% "
	}

	// title 的格式：●闪烁标识 当前盈亏比 股票价格1 | 股票价格2
	result = result + strings.Join(priceList, " | ")

	return result
}

func openConfigFileAndWait() {
	cmd := exec.Command("code", "--wait", config.FILE_NAME)
	err := cmd.Start()
	if err != nil {
		log.Fatalf("failed to call cmd.Run(): %v", err)
	}
	go func() {
		err = cmd.Wait()
		checkAndCompleteConfig()
	}()
}

func checkAndCompleteConfig() {
	stockList := config.ReadConfigFromFile()

	codeList := make([]string, len(*stockList))
	for i, v := range *stockList {
		codeList[i] = v.Code
	}
	infoMap := api.QueryStockInfo(codeList)

	var validStock []config.StockConfig
	for _, stock := range *stockList {
		info, ok := infoMap[stock.Code]
		if !ok {
			continue
		}
		stock.Name = info.Name
		validStock = append(validStock, stock)
	}

	config.WriteConfig(&validStock)

	restartSelf()
}
