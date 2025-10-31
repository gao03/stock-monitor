package api

import (
	"context"
	"fmt"
	"log"
	"monitor/entity"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/guonaihong/gout"
)

// SinaAPI 新浪API客户端
type SinaAPI struct {
	config  *APIConfig
	baseURL string
}

// NewSinaAPI 创建新浪API客户端
func NewSinaAPI(config *APIConfig) *SinaAPI {
	return &SinaAPI{
		config:  config,
		baseURL: "https://hq.sinajs.cn/rn",
	}
}

// QueryOutPrice 查询盘外价格
func (s *SinaAPI) QueryOutPrice(ctx context.Context, stock entity.StockCurrentInfo) (*entity.StockOutPrice, error) {
	var response string

	err := s.retryRequest(ctx, func() error {
		return gout.GET(s.baseURL).
			SetQuery(gout.H{"list": "gb_" + strings.ToLower(stock.Code)}).
			SetHeader(gout.H{"Referer": "https://sina.com.cn"}).
			SetTimeout(s.config.Timeout).
			BindBody(&response).
			Do()
	})

	if err != nil {
		return nil, fmt.Errorf("新浪API请求失败: %w", err)
	}

	if response == "" {
		return nil, fmt.Errorf("新浪API返回空响应")
	}

	return s.parseResponse(response)
}

// parseResponse 解析响应数据
func (s *SinaAPI) parseResponse(response string) (*entity.StockOutPrice, error) {
	re := regexp.MustCompile("hq_str_(.*?)=\"(.*?)\"")
	sub := re.FindStringSubmatch(response)
	if len(sub) != 3 {
		return nil, fmt.Errorf("响应格式不正确")
	}

	data := strings.Split(sub[2], ",")
	if len(data) < 22 {
		return nil, fmt.Errorf("数据字段不足")
	}

	price, err1 := strconv.ParseFloat(strings.TrimSpace(data[21]), 64)
	diff, err2 := strconv.ParseFloat(strings.TrimSpace(data[22]), 64)

	if err1 != nil {
		return nil, fmt.Errorf("解析价格失败: %w", err1)
	}
	if err2 != nil {
		return nil, fmt.Errorf("解析涨跌幅失败: %w", err2)
	}

	return &entity.StockOutPrice{
		Price: price,
		Diff:  diff,
	}, nil
}

// retryRequest 重试请求
func (s *SinaAPI) retryRequest(ctx context.Context, requestFunc func() error) error {
	var lastErr error

	for attempt := 1; attempt <= s.config.MaxRetries; attempt++ {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}

		lastErr = requestFunc()
		if lastErr == nil {
			return nil
		}

		if attempt < s.config.MaxRetries {
			// 新浪API使用较短的重试间隔
			waitTime := time.Duration(attempt) * 500 * time.Millisecond
			log.Printf("新浪API调用失败 (尝试 %d/%d)，%v 后重试: %v", attempt, s.config.MaxRetries, waitTime, lastErr)

			select {
			case <-ctx.Done():
				return ctx.Err()
			case <-time.After(waitTime):
			}
		}
	}

	return fmt.Errorf("达到最大重试次数 (%d): %w", s.config.MaxRetries, lastErr)
}