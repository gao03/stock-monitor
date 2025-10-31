package api

import (
	"github.com/guonaihong/gout"
	"log"
	"monitor/entity"
	"regexp"
	"strconv"
	"strings"
	"time"
)

func QueryStockOutInfo(stock entity.StockCurrentInfo) *entity.StockOutPrice {
	var response string

	// 实现重试机制，最多重试3次
	maxRetries := 3
	var err error
	for attempt := 1; attempt <= maxRetries; attempt++ {
		err = gout.GET("https://hq.sinajs.cn/rn").
			SetQuery(gout.H{"list": "gb_" + strings.ToLower(stock.Code)}).
			SetHeader(gout.H{"Referer": "https://sina.com.cn"}).
			SetTimeout(8*time.Second). // 设置8秒超时
			BindBody(&response).
			Do()

		if err == nil && response != "" {
			// 成功获取到数据，跳出重试循环
			break
		}

		if attempt < maxRetries {
			// 等待一段时间后重试
			waitTime := time.Duration(attempt) * 500 * time.Millisecond
			log.Printf("新浪API调用失败 (尝试 %d/%d)，%v 后重试: %v", attempt, maxRetries, waitTime, err)
			time.Sleep(waitTime)
		} else {
			log.Printf("新浪API调用失败，已达到最大重试次数 (%d): %v", maxRetries, err)
			return nil
		}
	}
	re := regexp.MustCompile("hq_str_(.*?)=\"(.*?)\"")
	sub := re.FindStringSubmatch(response)
	if len(sub) != 3 {
		return nil
	}
	data := strings.Split(sub[2], ",")
	if len(data) < 22 {
		return nil
	}
	price, err1 := strconv.ParseFloat(strings.TrimSpace(data[21]), 64)
	diff, err2 := strconv.ParseFloat(strings.TrimSpace(data[22]), 64)
	if err1 != nil || err2 != nil {
		return nil
	}
	return &entity.StockOutPrice{
		Price: price,
		Diff:  diff,
	}
}
