package api

import (
	"context"
	"fmt"
	"log"
	"monitor/entity"
	"sync"
	"time"

	"github.com/patrickmn/go-cache"
)

// APIConfig API客户端配置 - macOS专用
type APIConfig struct {
	Timeout     time.Duration
	MaxRetries  int
	RetryDelay  time.Duration
	CacheExpiry time.Duration
}

// DefaultAPIConfig 返回macOS优化的默认配置
func DefaultAPIConfig() *APIConfig {
	return &APIConfig{
		Timeout:     10 * time.Second,
		MaxRetries:  3,
		RetryDelay:  time.Second,
		CacheExpiry: 30 * time.Minute,
	}
}

// Client 统一的API客户端
type Client struct {
	config    *APIConfig
	cache     *cache.Cache
	eastMoney *EastMoneyAPI
	sina      *SinaAPI
	mu        sync.RWMutex
}

// NewClient 创建新的API客户端
func NewClient(config *APIConfig) *Client {
	if config == nil {
		config = DefaultAPIConfig()
	}

	c := &Client{
		config: config,
		cache:  cache.New(config.CacheExpiry, config.CacheExpiry*2),
	}

	c.eastMoney = NewEastMoneyAPI(config)
	c.sina = NewSinaAPI(config)

	return c
}

// QueryStockInfo 查询股票信息（主接口）
func (c *Client) QueryStockInfo(ctx context.Context, stockConfigs *[]entity.StockConfig) (map[string]entity.StockCurrentInfo, error) {
	if stockConfigs == nil || len(*stockConfigs) == 0 {
		return make(map[string]entity.StockCurrentInfo), nil
	}

	codes := make([]string, len(*stockConfigs))
	for i, config := range *stockConfigs {
		codes[i] = config.Code
	}

	// 首先尝试从缓存获取
	result := make(map[string]entity.StockCurrentInfo)
	missingCodes := make([]string, 0)

	c.mu.RLock()
	for _, code := range codes {
		if cached, found := c.cache.Get(fmt.Sprintf("stock_%s", code)); found {
			if info, ok := cached.(entity.StockCurrentInfo); ok {
				result[code] = info
				continue
			}
		}
		missingCodes = append(missingCodes, code)
	}
	c.mu.RUnlock()

	// 如果所有数据都在缓存中，直接返回
	if len(missingCodes) == 0 {
		return result, nil
	}

	// 从API获取缺失的数据
	freshData, err := c.eastMoney.QueryStockInfo(ctx, stockConfigs)
	if err != nil {
		log.Printf("东财API调用失败: %v", err)
		// 如果有部分缓存数据，返回缓存数据而不是错误
		if len(result) > 0 {
			return result, nil
		}
		return nil, fmt.Errorf("获取股票数据失败: %w", err)
	}

	// 更新缓存并合并结果
	c.mu.Lock()
	for code, info := range freshData {
		c.cache.Set(fmt.Sprintf("stock_%s", code), info, cache.DefaultExpiration)
		result[code] = info
	}
	c.mu.Unlock()

	return result, nil
}

// QueryOutPrice 查询盘外价格
func (c *Client) QueryOutPrice(ctx context.Context, stock entity.StockCurrentInfo) (*entity.StockOutPrice, error) {
	cacheKey := fmt.Sprintf("out_price_%s", stock.Code)

	c.mu.RLock()
	if cached, found := c.cache.Get(cacheKey); found {
		c.mu.RUnlock()
		if price, ok := cached.(*entity.StockOutPrice); ok {
			return price, nil
		}
	}
	c.mu.RUnlock()

	price, err := c.sina.QueryOutPrice(ctx, stock)
	if err != nil {
		return nil, fmt.Errorf("查询盘外价格失败: %w", err)
	}

	if price != nil {
		c.mu.Lock()
		c.cache.Set(cacheKey, price, 5*time.Minute) // 盘外价格缓存5分钟
		c.mu.Unlock()
	}

	return price, nil
}

// ClearCache 清理缓存
func (c *Client) ClearCache() {
	c.mu.Lock()
	c.cache.Flush()
	c.mu.Unlock()
}

// GetCacheStats 获取缓存统计信息
func (c *Client) GetCacheStats() (int, int) {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.cache.ItemCount(), 0 // go-cache不提供命中率统计
}