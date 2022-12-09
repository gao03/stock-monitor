package main

import (
	_ "embed"
	"fmt"
	"github.com/getlantern/systray"
	"github.com/kardianos/osext"
	"github.com/ncruces/zenity"
	"github.com/patrickmn/go-cache"
	"github.com/samber/lo"
	"log"
	"monitor/api"
	"monitor/config"
	"monitor/constant/StockType"
	"monitor/dialog"
	"monitor/entity"
	"monitor/utils"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"syscall"
	"time"
)

var titleLength = 0

// MonitorPushCache 价格监控的提醒，每个股票每个提醒 5分钟发一次
var MonitorPushCache = cache.New(5*time.Minute, 10*time.Minute)

func main() {
	if len(os.Args) == 1 {
		// 如果传了参数，就不用后台运行的模式
		background("/tmp/stock-monitor-daemon.log")
	}

	systray.Run(onReady, func() {
		if utils.Browser != nil {
			defer utils.Browser.Close()
		}
	})
}

// @link https://zhuanlan.zhihu.com/p/146192035
func background(logFile string) {
	executeFilePath, err1 := os.Executable()
	if err1 != nil {
		log.Println("Executable error", err1)
		executeFilePath = os.Args[0]
	}

	envName := "XW_DAEMON" //环境变量名称
	envValue := "SUB_PROC" //环境变量值

	val := os.Getenv(envName) //读取环境变量的值,若未设置则为空字符串
	if val == envValue {      //监测到特殊标识, 判断为子进程,不再执行后续代码
		return
	}

	/*以下是父进程执行的代码*/

	//因为要设置更多的属性, 这里不使用`exec.Command`方法, 直接初始化`exec.Cmd`结构体
	cmd := &exec.Cmd{
		Path: executeFilePath,
		Args: os.Args,      //注意,此处是包含程序名的
		Env:  os.Environ(), //父进程中的所有环境变量
	}

	//为子进程设置特殊的环境变量标识
	cmd.Env = append(cmd.Env, fmt.Sprintf("%s=%s", envName, envValue))

	//若有日志文件, 则把子进程的输出导入到日志文件
	if logFile != "" {
		stdout, err := os.OpenFile(logFile, os.O_WRONLY|os.O_APPEND|os.O_CREATE, 0666)
		if err != nil {
			log.Fatal(os.Getpid(), ": 打开日志文件错误:", err)
		}
		cmd.Stderr = stdout
		cmd.Stdout = stdout
	}

	//异步启动子进程
	err := cmd.Start()
	if err != nil {
		log.Println("启动子进程失败2:", err)
	} else {
		os.Exit(0)
	}
	return
}

func onReady() {
	systray.SetTitle("monitor")

	checkTodayRefreshConfig()

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
		addMenuItem("刷新", updateAndRestart)
		addMenuItem("添加", addStockToConfig)
		addMenuItem("退出", systray.Quit)
	})
}

func updateAndRestart() {
	systray.SetTitle("刷新中...")
	utils.UpdateStockByEastMoney()
	checkAndCompleteConfig()
	restartSelf()
}

func addStockToConfig() {
	stockCurrentInfo := dialog.InputNewStock()
	if stockCurrentInfo == nil {
		return
	}

	stock := config.StockConfig{
		Code:              stockCurrentInfo.Code,
		Type:              &stockCurrentInfo.Type,
		Name:              stockCurrentInfo.Name,
		ShowInTitle:       BoolPointer(false),
		EnableRealTimePic: false,
	}
	stockList := config.ReadConfigFromFile()
	newStockList := append(*stockList, stock)
	config.WriteConfig(&newStockList)
	checkAndCompleteConfig()
	restartSelf()
}

func removeStockFromConfig(stock config.StockConfig) func() {
	return func() {
		err := zenity.Question("确定要删除 " + stock.Name + " ?")
		if err != nil {
			return
		}
		stockList := config.ReadConfigFromFile()
		newStockList := lo.Filter(*stockList, func(item config.StockConfig, index int) bool {
			return item.Code != stock.Code
		})
		config.WriteConfig(&newStockList)
		checkAndCompleteConfig()
		restartSelf()
	}
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

	infoMap := api.QueryStockInfo(stockConfigList)

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

			addSubMenuItem(menu, "删除", removeStockFromConfig(item))
			if item.EnableRealTimePic {
				figureMenuItem := addSubMenuItem(menu, "", nil)
				updateTimeMenuItem := addSubMenuItem(menu, "查询中...", nil)

				go utils.RegisterUpdateStockFigure(GenerateXueqiuUrl(&current), figureMenuItem, updateTimeMenuItem)
			}
		}
		stock := entity.Stock{
			Code:        item.Code,
			Config:      item,
			CurrentInfo: current,
			MenuItem:    menu,
		}
		stockList = append(stockList, &stock)
		updateSubMenuTitle(&stock)
		checkStockMonitorPrice(&stock)
	}
	systray.SetTitle(generateTitle(flag, stockList))
}

func checkStockMonitorPrice(stock *entity.Stock) {
	monitors := stock.Config.MonitorPrices
	if monitors == nil || len(monitors) == 0 {
		return
	}
	for _, monitor := range monitors {
		result := utils.CheckMonitorPrice(monitor, stock.CurrentInfo.BasePrice, stock.Config.CostPrice, stock.CurrentInfo.Price)
		if result {
			var cacheKey = stock.Code + "-" + monitor
			_, found := MonitorPushCache.Get(cacheKey)
			if found {
				continue
			}
			MonitorPushCache.SetDefault(cacheKey, "")
			message := "当前价格" + utils.FormatPrice(stock.CurrentInfo.Price) + "; 涨幅" + utils.FloatToStr(stock.CurrentInfo.Diff) + "%"
			subtitle := "规则：" + monitor
			utils.Notify(stock.CurrentInfo.Name, subtitle, message, GenerateXueqiuUrl(&stock.CurrentInfo))
		}
	}
}

func GenerateXueqiuUrl(current *api.StockCurrentInfo) string {
	url := "https://xueqiu.com/S/"
	typeStr := ""
	switch current.Type {
	case StockType.SHEN_ZHEN:
		typeStr = "SZ"
	case StockType.SHANG_HAI:
		typeStr = "SH"
	default:
		typeStr = ""
	}
	return url + typeStr + current.Code
}

func updateSubMenuTitle(stock *entity.Stock) {
	var positionDiff = ""
	if stock.Config.Position > 0 {
		positionDiff = "\t" + utils.CalcReturn(stock.Config.CostPrice, stock.CurrentInfo.Price)
	}
	var result = stock.CurrentInfo.Name + "\t  " +
		utils.FormatPrice(stock.CurrentInfo.Price) + "\t" +
		utils.FloatToStr(stock.CurrentInfo.Diff) +
		positionDiff

	stock.MenuItem.SetTitle(result)
}

func generateTitle(flag *bool, stockList []*entity.Stock) string {
	currentTotal := lo.SumBy(stockList, func(stock *entity.Stock) float64 {
		return stock.CurrentInfo.Price * stock.Config.Position
	})
	totalCost := lo.SumBy(stockList, func(stock *entity.Stock) float64 {
		return stock.Config.CostPrice * stock.Config.Position
	})
	priceList := lo.FilterMap(stockList, func(stock *entity.Stock, _ int) (string, bool) {
		sit := stock.Config.ShowInTitle
		if sit == nil {
			sit = BoolPointer(false)
		}
		return utils.FormatPrice(stock.CurrentInfo.Price), *sit
	})

	titleList := []string{
		lo.If(*flag, "○").Else("●"),
		lo.If(totalCost > 0, utils.CalcReturn(totalCost, currentTotal)+"% ").Else(""),
		strings.Join(priceList, " | "),
	}

	// 给标题最后补上空格：保证标题的长度不会变化，导致闪来闪去的
	result := fmt.Sprintf("%-"+strconv.Itoa(titleLength-2)+"s", strings.Join(titleList, ""))
	titleLength = len(result)

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

func checkTodayRefreshConfig() {
	if config.IsConfigRefreshToday() {
		return
	}
	updateAndRestart()
}

func checkAndCompleteConfig() {
	stockList := config.ReadConfigFromFile()

	codeList := make([]string, len(*stockList))
	for i, v := range *stockList {
		codeList[i] = v.Code
	}
	infoMap := api.QueryStockInfo(stockList)

	var validStock []config.StockConfig

	for _, stock := range *stockList {
		info, ok := infoMap[stock.Code]

		if !ok {
			continue
		}
		if stock.ShowInTitle == nil {
			stock.ShowInTitle = BoolPointer(false)
		}
		stock.Name = info.Name
		stock.Type = &info.Type
		validStock = append(validStock, stock)
	}

	config.WriteConfig(&validStock)

	restartSelf()
}

func BoolPointer(b bool) *bool {
	return &b
}
