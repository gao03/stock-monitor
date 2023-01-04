package main

import (
	_ "embed"
	"fmt"
	"github.com/getlantern/systray"
	"github.com/kardianos/osext"
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
	"sort"
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

	systray.EnableRightMenu()
	addRightMenuItem("配置", openConfigFileAndWait)
	addRightMenuItem("重启", restartSelf)
	if config.HasEastMoneyAccount() {
		addRightMenuItem("刷新", updateAndRestart)
	}
	addRightMenuItem("添加", addStockToConfig)
	addRightMenuItem("退出", systray.Quit)
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
		confirm := dialog.Confirm("确定要删除 " + stock.Name + " ?")
		if !confirm {
			return
		}

		ChangeConfigAndRestart(func(stockList *[]config.StockConfig) []config.StockConfig {
			return lo.Filter(*stockList, func(item config.StockConfig, index int) bool {
				return item.Code != stock.Code
			})
		})
	}
}

func ChangeConfigAndRestart(changeFunc func(stockList *[]config.StockConfig) []config.StockConfig) {
	stockList := config.ReadConfigFromFile()
	newConfig := changeFunc(stockList)
	sort.Slice(newConfig, func(i, j int) bool {
		// 如果两个都没配置showInTitle，或者2个都配置了，那就保持原来的顺序
		if utils.IsTrue(newConfig[i].ShowInTitle) == utils.IsTrue(newConfig[j].ShowInTitle) {
			return i < j
		}
		// 否则，配置了showInTitle的排在前面
		return utils.IsTrue(newConfig[i].ShowInTitle)
	})
	config.WriteConfig(&newConfig)
	checkAndCompleteConfig()
	restartSelf()
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

func addRightMenuItem(title string, onClick func()) *systray.MenuItem {
	menu := systray.AddRightMenuItem(title, "")
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
func addSubMenuItemCheckbox(menu *systray.MenuItem, title string, checked bool, onClick func()) *systray.MenuItem {
	subMenu := menu.AddSubMenuItemCheckbox(title, "", checked)
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
			menu = addMenuItem(item.Code, OpenXueQiuUrl(item))
			codeToMenuItemMap[item.Code] = menu

			addSubMenuToStock(menu, item)
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

func OpenXueQiuUrl(item config.StockConfig) func() {
	return func() {
		exec.Command("open", GenerateXueqiuUrl(item)).Start()
	}
}

func addSubMenuToStock(menu *systray.MenuItem, item config.StockConfig) {
	addSubMenuItem(menu, "删除", removeStockFromConfig(item))

	addSubMenuItemCheckbox(menu, "置顶", item.ShowInTitle != nil && *item.ShowInTitle, updateStockShowInTitle(item))

	addSubMenuItem(menu, "监控", addStockMonitorRule(item))
	if len(item.MonitorRules) > 0 {
		for _, rule := range item.MonitorRules {
			addSubMenuItem(menu, "监控 "+rule, removeStockMonitorRule(item, rule))
		}
	}

	addSubMenuItemCheckbox(menu, "时分图", item.EnableRealTimePic, updateStockEnableRealTimePic(item))

	if item.EnableRealTimePic {
		figureMenuItem := addSubMenuItem(menu, "", nil)
		updateTimeMenuItem := addSubMenuItem(menu, "查询中...", nil)

		go utils.RegisterUpdateStockFigure(GenerateXueqiuUrl(item), figureMenuItem, updateTimeMenuItem)
	}
}

func updateStockEnableRealTimePic(stock config.StockConfig) func() {
	return func() {
		newVal := !stock.EnableRealTimePic
		op := lo.If(newVal, "启用").Else("关闭")
		confirm := dialog.Confirm("确定要" + op + stock.Name + "的时分图 ?")
		if !confirm {
			return
		}
		ChangeConfigAndRestart(func(stockList *[]config.StockConfig) []config.StockConfig {
			return lo.Map(*stockList, func(item config.StockConfig, index int) config.StockConfig {
				if item.Code == stock.Code {
					item.EnableRealTimePic = newVal
				}
				return item
			})
		})
	}
}

func updateStockShowInTitle(stock config.StockConfig) func() {
	return func() {
		newVal := stock.ShowInTitle == nil || !*stock.ShowInTitle
		opMessage := "置顶"
		if !newVal {
			opMessage = "取消置顶"
		}
		confirm := dialog.Confirm("确定要" + opMessage + stock.Name + " ?")
		if !confirm {
			return
		}
		ChangeConfigAndRestart(func(stockList *[]config.StockConfig) []config.StockConfig {
			return lo.Map(*stockList, func(item config.StockConfig, index int) config.StockConfig {
				if item.Code == stock.Code {
					item.ShowInTitle = BoolPointer(newVal)
				}
				return item
			})
		})
	}
}

func addStockMonitorRule(stock config.StockConfig) func() {
	return func() {
		rule := dialog.Input("输入给 " + stock.Name + " 添加的监控规则：")
		if rule == "" {
			return
		}
		ChangeConfigAndRestart(func(stockList *[]config.StockConfig) []config.StockConfig {
			return lo.Map(*stockList, func(item config.StockConfig, index int) config.StockConfig {
				if item.Code == stock.Code {
					item.MonitorRules = append(item.MonitorRules, rule)
				}
				return item
			})
		})
	}
}

func removeStockMonitorRule(stock config.StockConfig, rule string) func() {
	return func() {
		confirm := dialog.Confirm("确定要删除 " + stock.Name + " 的监控规则[" + rule + "] ?")
		if !confirm {
			return
		}
		ChangeConfigAndRestart(func(stockList *[]config.StockConfig) []config.StockConfig {
			return lo.Map(*stockList, func(item config.StockConfig, index int) config.StockConfig {
				if item.Code == stock.Code {
					item.MonitorRules = lo.Filter(item.MonitorRules, func(iu string, idx int) bool {
						return iu != rule
					})
				}
				return item
			})
		})
	}
}

func checkStockMonitorPrice(stock *entity.Stock) {
	rules := stock.Config.MonitorRules
	if rules == nil || len(rules) == 0 {
		return
	}
	todayBasePrice := stock.CurrentInfo.BasePrice
	costPrice := stock.Config.CostPrice
	currentPrice := stock.CurrentInfo.Price

	checkCacheAndNotify := func(rule string) {
		var cacheKey = stock.Code + "-" + rule
		_, found := MonitorPushCache.Get(cacheKey)
		if found {
			return
		}
		MonitorPushCache.SetDefault(cacheKey, "")
		message := "当前价格" + utils.FormatPrice(currentPrice) + "; 涨幅" + utils.FloatToStr(stock.CurrentInfo.Diff) + "%"
		subtitle := "规则：" + rule
		utils.Notify(stock.CurrentInfo.Name, subtitle, message, GenerateXueqiuUrl(stock.Config))
	}

	for _, rule := range rules {
		result := utils.CheckMonitorPrice(rule, todayBasePrice, costPrice, currentPrice)
		if result {
			checkCacheAndNotify(rule)
		}
	}

	if stock.Config.Position > 0 && costPrice > todayBasePrice && costPrice < currentPrice {
		// 持仓大于0 且 持仓成本大于昨天收盘价格 且 持仓成本小于当前价格
		checkCacheAndNotify("回本")
	}

}

func GenerateXueqiuUrl(config config.StockConfig) string {
	url := "https://xueqiu.com/S/"
	typeStr := ""
	switch *config.Type {
	case StockType.SHEN_ZHEN:
		typeStr = "SZ"
	case StockType.SHANG_HAI:
		typeStr = "SH"
	default:
		typeStr = ""
	}
	return url + typeStr + config.Code
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
	if !config.HasEastMoneyAccount() {
		return
	}
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
