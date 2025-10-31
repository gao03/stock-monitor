package service

import (
	"context"
	"fmt"
	"log"
	"monitor/api"
	"monitor/config"
	"monitor/entity"
	"monitor/utils"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/patrickmn/go-cache"
	"github.com/samber/lo"
)

// MonitorService 股票监控服务
type MonitorService struct {
	apiClient           *api.Client
	configManager       *config.Manager
	monitorPushCache    *cache.Cache
	returnCostPushCache *cache.Cache
	lastSuccessfulData  []*entity.Stock
	mu                  sync.RWMutex
	ctx                 context.Context
	cancel              context.CancelFunc
}

// NewMonitorService 创建监控服务
func NewMonitorService(apiClient *api.Client, configManager *config.Manager) *MonitorService {
	ctx, cancel := context.WithCancel(context.Background())

	return &MonitorService{
		apiClient:           apiClient,
		configManager:       configManager,
		monitorPushCache:    cache.New(5*time.Minute, 10*time.Minute),
		returnCostPushCache: cache.New(10*time.Hour, 10*time.Hour),
		ctx:                 ctx,
		cancel:              cancel,
	}
}

// UpdateStockInfo 更新股票信息
func (s *MonitorService) UpdateStockInfo() ([]*entity.Stock, error) {
	stockConfigs := s.configManager.GetStockConfigs()
	if len(stockConfigs) == 0 {
		return nil, nil
	}

	// 使用context控制超时
	ctx, cancel := context.WithTimeout(s.ctx, 30*time.Second)
	defer cancel()

	infoMap, err := s.apiClient.QueryStockInfo(ctx, &stockConfigs)
	if err != nil {
		log.Printf("获取股票信息失败: %v", err)
		// 返回缓存的数据
		s.mu.RLock()
		cachedData := s.lastSuccessfulData
		s.mu.RUnlock()
		return cachedData, err
	}

	var stockList []*entity.Stock
	var hasValidData bool

	for _, config := range stockConfigs {
		currentInfo, ok := infoMap[config.Code]
		if !ok {
			continue
		}

		stock := &entity.Stock{
			Code:        config.Code,
			Config:      config,
			CurrentInfo: currentInfo,
		}

		stockList = append(stockList, stock)
		hasValidData = true

		// 检查监控规则
		s.checkStockMonitorPrice(stock)
	}

	// 更新缓存
	if hasValidData {
		s.mu.Lock()
		s.lastSuccessfulData = stockList
		s.mu.Unlock()
	}

	return stockList, nil
}

// checkStockMonitorPrice 检查股票监控价格
func (s *MonitorService) checkStockMonitorPrice(stock *entity.Stock) {
	rules := stock.Config.MonitorRules
	if rules == nil || len(rules) == 0 {
		return
	}

	todayBasePrice := stock.CurrentInfo.BasePrice
	costPrice := stock.Config.CostPrice
	currentPrice := stock.CurrentInfo.Price

	checkCacheAndNotify := func(rule string, cache *cache.Cache) {
		cacheKey := stock.Code + "-" + rule
		if _, found := cache.Get(cacheKey); found {
			return
		}

		cache.SetDefault(cacheKey, "")
		message := fmt.Sprintf("当前价格%s; 涨幅%.2f%%",
			utils.FormatPrice(currentPrice),
			stock.CurrentInfo.Diff)
		subtitle := "规则：" + rule

		s.sendNotification(stock.CurrentInfo.Name, subtitle, message, stock.Config)
	}

	// 检查监控规则
	for _, rule := range rules {
		if utils.CheckMonitorPrice(rule, todayBasePrice, costPrice, currentPrice) {
			checkCacheAndNotify(rule, s.monitorPushCache)
		}
	}

	// 检查回本提醒
	if stock.Config.Position > 0 && costPrice > todayBasePrice && costPrice < currentPrice {
		checkCacheAndNotify("回本", s.returnCostPushCache)
	}
}

// sendNotification 发送通知
func (s *MonitorService) sendNotification(title, subtitle, message string, config entity.StockConfig) {
	url := s.generateXueqiuUrl(config)
	utils.Notify(title, subtitle, message, url)
}

// generateXueqiuUrl 生成雪球URL
func (s *MonitorService) generateXueqiuUrl(config entity.StockConfig) string {
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

// GenerateTitle 生成标题
func (s *MonitorService) GenerateTitle(flag *bool, stockList []*entity.Stock, titleLength *int) string {
	if stockList == nil || len(stockList) == 0 {
		return "●"
	}

	currentTotal := lo.SumBy(stockList, func(stock *entity.Stock) float64 {
		return stock.CurrentInfo.Price * stock.Config.Position
	})

	totalCost := lo.SumBy(stockList, func(stock *entity.Stock) float64 {
		return stock.Config.CostPrice * stock.Config.Position
	})

	priceList := lo.FilterMap(stockList, func(stock *entity.Stock, _ int) (string, bool) {
		return utils.FormatPrice(stock.CurrentInfo.Price), utils.CheckStockCanShowInTitle(stock.Config)
	})

	titleList := []string{
		lo.If(*flag, "○").Else("●"),
		lo.If(totalCost > 0, utils.CalcReturn(totalCost, currentTotal)+"% ").Else(""),
		strings.Join(priceList, " | "),
	}

	result := strings.Join(titleList, "")

	// 长度调整逻辑，避免闪烁
	if titleLength != nil {
		lengthDiff := len(result) - *titleLength
		if lengthDiff < 0 {
			lengthDiff = -1 * lengthDiff
		}
		// 如果差异不大，补空格保持长度一致
		if lengthDiff < 4 && *titleLength > 2 {
			result = fmt.Sprintf("%-"+strconv.Itoa(*titleLength-2)+"s", strings.Join(titleList, ""))
		}
		*titleLength = len(result)
	}

	return result
}

// GetLastSuccessfulData 获取最后成功的数据
func (s *MonitorService) GetLastSuccessfulData() []*entity.Stock {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.lastSuccessfulData
}

// Stop 停止服务
func (s *MonitorService) Stop() {
	s.cancel()
}