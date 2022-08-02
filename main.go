package main

import (
	"fmt"
	"github.com/getlantern/systray"
	"github.com/kardianos/osext"
	"log"
	"monitor/api"
	"monitor/config"
	"monitor/constant/StockType"
	"monitor/entity"
	"monitor/utils"
	"os"
	"os/exec"
	"strings"
	"syscall"
	"time"
)

var titleLength = 0

func main() {
	err := background("/tmp/daemon.log")
	if err != nil {
		log.Fatal("启动子进程失败1:", err)
	}

	systray.Run(onReady, func() {
		if utils.Browser != nil {
			defer utils.Browser.Close()
		}
	})
}

//@link https://zhuanlan.zhihu.com/p/146192035
func background(logFile string) error {
	executeFilePath, err1 := os.Executable()
	if err1 != nil {
		log.Println("Executable error", err1)
		executeFilePath = os.Args[0]
	}

	envName := "XW_DAEMON" //环境变量名称
	envValue := "SUB_PROC" //环境变量值

	val := os.Getenv(envName) //读取环境变量的值,若未设置则为空字符串
	if val == envValue {      //监测到特殊标识, 判断为子进程,不再执行后续代码
		return nil
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
	return nil
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
	}
	systray.SetTitle(generateTitle(flag, stockList))
}

func GenerateXueqiuUrl(current *api.StockCurrentInfo) string {
	url := "https://xueqiu.com/S/S"
	typeStr := ""
	switch current.Type {
	case StockType.SHEN_ZHEN:
		typeStr = "Z"
	case StockType.SHANG_HAI:
		typeStr = "H"
	default:
		typeStr = "S"
	}
	return url + typeStr + current.Code
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
	var priceList []string
	for _, stock := range stockList {
		currentTotal += stock.CurrentInfo.Price * stock.Config.Position
		totalCost += stock.Config.CostPrice * stock.Config.Position
		if stock.Config.ShopInTitle {
			priceList = append(priceList, utils.FloatToStr(stock.CurrentInfo.Price))
		}
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

	if titleLength < len(result) {
		titleLength = len(result)
	} else {
		diff := titleLength - len(result)
		for i := 0; i < diff; i++ {
			result += " "
		}
	}

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
	infoMap := api.QueryStockInfo(stockList)

	var validStock []config.StockConfig

	for _, stock := range *stockList {
		info, ok := infoMap[stock.Code]

		if !ok {
			continue
		}
		if stock.Name == "" {
			stock.ShopInTitle = true
		}
		stock.Name = info.Name
		stock.Type = &info.Type
		validStock = append(validStock, stock)
	}

	config.WriteConfig(&validStock)

	restartSelf()
}
