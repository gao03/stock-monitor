package app

import (
	"context"
	"fmt"
	"monitor/api"
	"monitor/config"
	"monitor/pkg/logger"
	"monitor/service"
	"monitor/ui"
	"os"
	"os/signal"
	"sync"
	"syscall"
	"time"

	"github.com/getlantern/systray"
)

// App 应用程序主结构
type App struct {
	configManager  *config.Manager
	apiClient      *api.Client
	monitorService *service.MonitorService
	uiManager      *ui.Manager
	logger         *logger.Logger

	ctx    context.Context
	cancel context.CancelFunc
	wg     sync.WaitGroup
}

// Config 应用程序配置
type Config struct {
	LogLevel    logger.Level
	LogFile     string
	ConfigFile  string
	UpdateInterval time.Duration
}

// DefaultConfig 返回默认配置
func DefaultConfig() *Config {
	return &Config{
		LogLevel:       logger.INFO,
		LogFile:        "",
		ConfigFile:     "",
		UpdateInterval: 2 * time.Second,
	}
}

// New 创建新的应用程序实例
func New(cfg *Config) (*App, error) {
	if cfg == nil {
		cfg = DefaultConfig()
	}

	// 初始化日志系统
	if err := logger.InitDefault(cfg.LogLevel, cfg.LogFile); err != nil {
		return nil, fmt.Errorf("初始化日志系统失败: %w", err)
	}

	// 替换标准库的log
	logger.ReplaceStdLogger()

	ctx, cancel := context.WithCancel(context.Background())

	// 创建配置管理器
	configManager := config.NewManager(cfg.ConfigFile)

	// 创建API客户端
	apiClient := api.NewClient(api.DefaultAPIConfig())

	// 创建监控服务
	monitorService := service.NewMonitorService(apiClient, configManager)

	// 创建UI管理器
	uiManager := ui.NewManager(monitorService, configManager)

	app := &App{
		configManager:  configManager,
		apiClient:      apiClient,
		monitorService: monitorService,
		uiManager:      uiManager,
		logger:         logger.GetDefault(),
		ctx:            ctx,
		cancel:         cancel,
	}

	return app, nil
}

// Run 运行应用程序
func (a *App) Run() error {
	a.logger.Info("股票监控应用程序启动")

	// 设置信号处理
	a.setupSignalHandler()

	// 启动系统托盘
	systray.Run(a.onReady, a.onExit)

	return nil
}

// onReady 系统托盘就绪回调
func (a *App) onReady() {
	a.logger.Info("系统托盘初始化完成")

	// 初始化UI
	if err := a.uiManager.Initialize(); err != nil {
		a.logger.Error("UI初始化失败: %v", err)
		return
	}

	// 启动定时更新
	a.startPeriodicUpdate()

	a.logger.Info("应用程序启动完成")
}

// onExit 退出回调
func (a *App) onExit() {
	a.logger.Info("应用程序正在退出...")
	a.Stop()
}

// startPeriodicUpdate 启动定时更新
func (a *App) startPeriodicUpdate() {
	a.wg.Add(1)
	go func() {
		defer a.wg.Done()

		ticker := time.NewTicker(2 * time.Second) // 固定2秒间隔
		defer ticker.Stop()

		// 立即执行一次
		a.updateStockInfo()

		for {
			select {
			case <-a.ctx.Done():
				a.logger.Debug("定时更新任务退出")
				return
			case <-ticker.C:
				a.updateStockInfo()
			}
		}
	}()
}

// updateStockInfo 更新股票信息
func (a *App) updateStockInfo() {
	stockList, err := a.monitorService.UpdateStockInfo()
	if err != nil {
		a.logger.Warn("更新股票信息失败: %v", err)
		// 即使出错也要更新UI，使用缓存数据
		stockList = a.monitorService.GetLastSuccessfulData()
	}

	if stockList != nil {
		a.uiManager.UpdateStockInfo(stockList)
	}
}

// Stop 停止应用程序
func (a *App) Stop() {
	a.logger.Info("正在停止应用程序...")

	// 取消上下文
	a.cancel()

	// 停止服务
	a.monitorService.Stop()

	// 等待所有goroutine结束
	done := make(chan struct{})
	go func() {
		a.wg.Wait()
		close(done)
	}()

	// 等待最多5秒
	select {
	case <-done:
		a.logger.Info("所有服务已停止")
	case <-time.After(5 * time.Second):
		a.logger.Warn("等待服务停止超时")
	}
}

// setupSignalHandler 设置信号处理
func (a *App) setupSignalHandler() {
	c := make(chan os.Signal, 1)
	signal.Notify(c, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		sig := <-c
		a.logger.Info("收到信号: %v", sig)
		systray.Quit()
	}()
}

// GetStats 获取应用程序统计信息
func (a *App) GetStats() map[string]interface{} {
	cacheItems, _ := a.apiClient.GetCacheStats()

	return map[string]interface{}{
		"cache_items":    cacheItems,
		"stocks_count":   len(a.configManager.GetStockConfigs()),
		"last_update":    time.Now().Format("2006-01-02 15:04:05"),
	}
}