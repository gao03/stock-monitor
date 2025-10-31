package ui

import (
	"fmt"
	"monitor/config"
	"monitor/entity"
	"monitor/pkg/logger"
	"monitor/service"
	"monitor/utils"
	"os/exec"
	"sync"

	"github.com/getlantern/systray"
	"github.com/samber/lo"
)

// Manager UI管理器
type Manager struct {
	monitorService    *service.MonitorService
	configManager     *config.Manager
	logger            *logger.Logger

	codeToMenuItemMap map[string]*systray.MenuItem
	titleLength       int
	flag              bool
	mu                sync.RWMutex
}

// NewManager 创建UI管理器
func NewManager(monitorService *service.MonitorService, configManager *config.Manager) *Manager {
	return &Manager{
		monitorService:    monitorService,
		configManager:     configManager,
		logger:            logger.GetDefault(),
		codeToMenuItemMap: make(map[string]*systray.MenuItem),
	}
}

// Initialize 初始化UI
func (m *Manager) Initialize() error {
	systray.SetTitle("monitor")

	// 检查今日配置刷新
	m.checkTodayRefreshConfig()

	// 启用右键菜单
	systray.EnableRightMenu()
	m.addRightMenuItem("配置", m.openConfigFileAndWait)
	m.addRightMenuItem("重启", m.restartSelf)

	if m.configManager.HasEastMoneyAccount() {
		m.addRightMenuItem("刷新", m.updateAndRestart)
	}

	m.addRightMenuItem("添加", m.addStockToConfig)
	m.addRightMenuItem("退出", systray.Quit)

	return nil
}

// UpdateStockInfo 更新股票信息显示
func (m *Manager) UpdateStockInfo(stockList []*entity.Stock) {
	m.mu.Lock()
	defer m.mu.Unlock()

	// 更新菜单项
	for _, stock := range stockList {
		menu, exists := m.codeToMenuItemMap[stock.Code]
		if !exists {
			menu = m.addMenuItem(stock.Config.Code, m.openXueQiuUrl(stock.Config))
			m.codeToMenuItemMap[stock.Config.Code] = menu
			m.addSubMenuToStock(menu, stock.Config)
		}

		stock.MenuItem = menu
		m.updateSubMenuTitle(stock)
	}

	// 更新标题
	m.flag = !m.flag
	title := m.monitorService.GenerateTitle(&m.flag, stockList, &m.titleLength)
	systray.SetTitle(title)
}

// addMenuItem 添加菜单项
func (m *Manager) addMenuItem(title string, onClick func()) *systray.MenuItem {
	menu := systray.AddMenuItem(title, "")
	utils.On(menu.ClickedCh, onClick)
	return menu
}

// addRightMenuItem 添加右键菜单项
func (m *Manager) addRightMenuItem(title string, onClick func()) *systray.MenuItem {
	menu := systray.AddRightMenuItem(title, "")
	utils.On(menu.ClickedCh, onClick)
	return menu
}

// addSubMenuItem 添加子菜单项
func (m *Manager) addSubMenuItem(menu *systray.MenuItem, title string, onClick func()) *systray.MenuItem {
	subMenu := menu.AddSubMenuItem(title, "")
	if onClick != nil {
		utils.On(subMenu.ClickedCh, onClick)
	}
	return subMenu
}

// addSubMenuItemCheckbox 添加复选框子菜单项
func (m *Manager) addSubMenuItemCheckbox(menu *systray.MenuItem, title string, checked bool, onClick func()) *systray.MenuItem {
	subMenu := menu.AddSubMenuItemCheckbox(title, "", checked)
	if onClick != nil {
		utils.On(subMenu.ClickedCh, onClick)
	}
	return subMenu
}

// addSubMenuToStock 为股票添加子菜单
func (m *Manager) addSubMenuToStock(menu *systray.MenuItem, config entity.StockConfig) {
	m.addSubMenuItem(menu, "删除", m.removeStockFromConfig(config))

	m.addSubMenuItemCheckbox(menu, "置顶",
		config.ShowInTitle != nil && *config.ShowInTitle,
		m.updateStockShowInTitle(config))

	m.addSubMenuItem(menu, "监控", m.addStockMonitorRule(config))

	// 显示现有监控规则
	if len(config.MonitorRules) > 0 {
		for _, rule := range config.MonitorRules {
			m.addSubMenuItem(menu, "监控 "+rule, m.removeStockMonitorRule(config, rule))
		}
	}

	m.addSubMenuItemCheckbox(menu, "时分图", config.EnableRealTimePic,
		m.updateStockEnableRealTimePic(config))

	// 如果启用了时分图，添加相关菜单
	if config.EnableRealTimePic {
		figureMenuItem := m.addSubMenuItem(menu, "", nil)
		updateTimeMenuItem := m.addSubMenuItem(menu, "查询中...", nil)

		go utils.RegisterUpdateStockFigure(m.generateXueqiuUrl(config), figureMenuItem, updateTimeMenuItem)
	}
}

// updateSubMenuTitle 更新子菜单标题
func (m *Manager) updateSubMenuTitle(stock *entity.Stock) {
	var positionDiff = ""
	if stock.Config.Position > 0 {
		positionDiff = "\t" + utils.CalcReturn(stock.Config.CostPrice, stock.CurrentInfo.Price)
	}

	name := []rune(stock.CurrentInfo.Name)
	if len(name) > 4 {
		name = name[:4]
	}

	result := fmt.Sprintf("%-4s\t%-4s\t%-4s%4s",
		string(name),
		utils.FormatPrice(stock.CurrentInfo.Price),
		utils.FloatToStr(stock.CurrentInfo.Diff),
		positionDiff)

	stock.MenuItem.SetTitle(result)
}

// generateXueqiuUrl 生成雪球URL
func (m *Manager) generateXueqiuUrl(config entity.StockConfig) string {
	url := "https://xueqiu.com/S/"
	typeStr := ""

	if config.Type != nil {
		switch *config.Type {
		case 0: // 深圳
			typeStr = "SZ"
		case 1: // 上海
			typeStr = "SH"
		default:
			typeStr = ""
		}
	}

	return url + typeStr + config.Code
}

// openXueQiuUrl 打开雪球URL
func (m *Manager) openXueQiuUrl(config entity.StockConfig) func() {
	return func() {
		exec.Command("open", m.generateXueqiuUrl(config)).Start()
	}
}

// 配置相关操作方法
func (m *Manager) removeStockFromConfig(stock entity.StockConfig) func() {
	return func() {
		// TODO: 实现确认对话框
		if err := m.configManager.RemoveStock(stock.Code); err != nil {
			m.logger.Error("删除股票失败: %v", err)
			return
		}
		m.restartSelf()
	}
}

func (m *Manager) updateStockShowInTitle(stock entity.StockConfig) func() {
	return func() {
		newVal := stock.ShowInTitle == nil || !*stock.ShowInTitle
		err := m.configManager.UpdateStock(stock.Code, func(config *entity.StockConfig) error {
			config.ShowInTitle = utils.BoolPointer(newVal)
			return nil
		})
		if err != nil {
			m.logger.Error("更新股票置顶状态失败: %v", err)
			return
		}
		m.restartSelf()
	}
}

func (m *Manager) addStockMonitorRule(stock entity.StockConfig) func() {
	return func() {
		// TODO: 实现输入对话框
		rule := "待实现输入对话框"
		if rule == "" {
			return
		}

		err := m.configManager.UpdateStock(stock.Code, func(config *entity.StockConfig) error {
			config.MonitorRules = append(config.MonitorRules, rule)
			return nil
		})
		if err != nil {
			m.logger.Error("添加监控规则失败: %v", err)
			return
		}
		m.restartSelf()
	}
}

func (m *Manager) removeStockMonitorRule(stock entity.StockConfig, rule string) func() {
	return func() {
		err := m.configManager.UpdateStock(stock.Code, func(config *entity.StockConfig) error {
			config.MonitorRules = lo.Filter(config.MonitorRules, func(r string, _ int) bool {
				return r != rule
			})
			return nil
		})
		if err != nil {
			m.logger.Error("删除监控规则失败: %v", err)
			return
		}
		m.restartSelf()
	}
}

func (m *Manager) updateStockEnableRealTimePic(stock entity.StockConfig) func() {
	return func() {
		newVal := !stock.EnableRealTimePic
		err := m.configManager.UpdateStock(stock.Code, func(config *entity.StockConfig) error {
			config.EnableRealTimePic = newVal
			return nil
		})
		if err != nil {
			m.logger.Error("更新时分图状态失败: %v", err)
			return
		}
		m.restartSelf()
	}
}

// 应用程序操作方法
func (m *Manager) openConfigFileAndWait() {
	cmd := exec.Command("code", "--wait", m.configManager.GetConfigFileName())
	err := cmd.Start()
	if err != nil {
		m.logger.Error("打开配置文件失败: %v", err)
		return
	}

	go func() {
		err = cmd.Wait()
		// TODO: 检查并完成配置
		m.logger.Info("配置文件已关闭")
	}()
}

func (m *Manager) restartSelf() {
	// TODO: 实现重启逻辑
	m.logger.Info("重启应用程序")
	systray.Quit()
}

func (m *Manager) updateAndRestart() {
	systray.SetTitle("刷新中...")
	// TODO: 实现东财账户更新
	m.logger.Info("更新股票数据")
	m.restartSelf()
}

func (m *Manager) addStockToConfig() {
	// TODO: 实现添加股票对话框
	m.logger.Info("添加股票")
}

func (m *Manager) checkTodayRefreshConfig() {
	if !m.configManager.HasEastMoneyAccount() {
		return
	}
	if m.configManager.IsConfigRefreshToday() {
		return
	}
	m.updateAndRestart()
}