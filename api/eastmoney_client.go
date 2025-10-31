package api

import (
	"context"
	"fmt"
	"log"
	"monitor/entity"
	"monitor/utils"
	"strconv"
	"strings"
	"time"

	"github.com/guonaihong/gout"
)

// EastMoneyAPI 东财API客户端
type EastMoneyAPI struct {
	config *APIConfig
	baseURL string
}

// NewEastMoneyAPI 创建东财API客户端
func NewEastMoneyAPI(config *APIConfig) *EastMoneyAPI {
	return &EastMoneyAPI{
		config:  config,
		baseURL: "https://push2delay.eastmoney.com/api/qt/ulist.np/get",
	}
}

// QueryStockInfo 查询股票信息
func (e *EastMoneyAPI) QueryStockInfo(ctx context.Context, codeList *[]entity.StockConfig) (map[string]entity.StockCurrentInfo, error) {
	if codeList == nil || len(*codeList) == 0 {
		return make(map[string]entity.StockCurrentInfo), nil
	}

	codeStr := strings.Join(utils.MapToStr(codeList, stockCodeToApiCodeV2), ",")
	url := fmt.Sprintf("%s?fields=f2,f3,f12,f13,f14,f15,f16,f18,f232&fltt=2&secids=%s", e.baseURL, codeStr)

	var response ApiResponse
	var result = make(map[string]entity.StockCurrentInfo)

	// 实现重试机制
	err := e.retryRequest(ctx, func() error {
		return gout.GET(url).
			SetTimeout(e.config.Timeout).
			Debug(false).
			BindJSON(&response).
			Do()
	})

	if err != nil {
		return result, fmt.Errorf("东财API请求失败: %w", err)
	}

	if response.Data.StockInfoList == nil {
		return result, fmt.Errorf("东财API返回数据为空")
	}

	// 处理美股盘外交易时间
	usStart, usEnd := e.getUSMarketHours()

	for _, info := range response.Data.StockInfoList {
		info.Name = strings.ReplaceAll(info.Name, " ", "")

		// 美股盘外时间处理
		if e.isUSStock(info.Type) && e.isUSAfterHours(usStart, usEnd) {
			if outPrice, err := e.queryOutPrice(ctx, info); err == nil && outPrice != nil {
				info.Price = outPrice.Price
				info.Diff = outPrice.Diff
			}
		}

		result[info.Code] = info
	}

	return result, nil
}

// QueryOneStockInfo 查询单个股票信息
func (e *EastMoneyAPI) QueryOneStockInfo(ctx context.Context, code string) ([]entity.StockCurrentInfo, error) {
	codeStr := stockCodeToApiCodeV2(entity.StockConfig{Code: code})
	url := fmt.Sprintf("%s?fields=f2,f3,f12,f13,f14,f15,f16,f18,f232&fltt=2&secids=%s", e.baseURL, codeStr)

	var response ApiResponse

	err := e.retryRequest(ctx, func() error {
		return gout.GET(url).
			SetTimeout(e.config.Timeout).
			Debug(false).
			BindJSON(&response).
			Do()
	})

	if err != nil {
		return nil, fmt.Errorf("查询单个股票失败: %w", err)
	}

	return response.Data.StockInfoList, nil
}

// retryRequest 重试请求
func (e *EastMoneyAPI) retryRequest(ctx context.Context, requestFunc func() error) error {
	var lastErr error

	for attempt := 1; attempt <= e.config.MaxRetries; attempt++ {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}

		lastErr = requestFunc()
		if lastErr == nil {
			return nil
		}

		if attempt < e.config.MaxRetries {
			waitTime := time.Duration(attempt) * e.config.RetryDelay
			log.Printf("东财API调用失败 (尝试 %d/%d)，%v 后重试: %v", attempt, e.config.MaxRetries, waitTime, lastErr)

			select {
			case <-ctx.Done():
				return ctx.Err()
			case <-time.After(waitTime):
			}
		}
	}

	return fmt.Errorf("达到最大重试次数 (%d): %w", e.config.MaxRetries, lastErr)
}

// queryOutPrice 查询盘外价格（内部方法）
func (e *EastMoneyAPI) queryOutPrice(ctx context.Context, stock entity.StockCurrentInfo) (*entity.StockOutPrice, error) {
	// 这里应该调用新浪API，但为了解耦，我们通过接口调用
	// 在实际使用中，这个方法会被Client统一管理
	return nil, fmt.Errorf("盘外价格查询需要通过Client统一接口")
}

// getUSMarketHours 获取美股交易时间
func (e *EastMoneyAPI) getUSMarketHours() (int, int) {
	usStart := 22
	usEnd := 5
	if utils.IsUsDST() {
		usStart = 21
		usEnd = 4
	}
	return usStart, usEnd
}

// isUSStock 判断是否为美股
func (e *EastMoneyAPI) isUSStock(stockType int) bool {
	return stockType == 105 || stockType == 106 || stockType == 107
}

// isUSAfterHours 判断是否在美股盘外时间
func (e *EastMoneyAPI) isUSAfterHours(usStart, usEnd int) bool {
	return utils.CheckNowBefore(usStart, 30) && utils.CheckNowAfter(usEnd, 0)
}

// stockCodeToApiCodeV2 转换股票代码为API代码（新版本）
func stockCodeToApiCodeV2(stock entity.StockConfig) string {
	s := stock.Code
	if stock.Type != nil {
		return strconv.Itoa(*stock.Type) + "." + stock.Code
	}

	// [0, 1, 105, 106, 116] // 深A、沪A、美股1、美股2、港股
	typeList := []int{0, 1, 105, 106, 107, 116}

	return strings.Join(utils.MapToStr(&typeList, func(i int) string {
		return strconv.Itoa(i) + "." + s
	}), ",")
}