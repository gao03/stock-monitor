package api

import (
	"log"
	"monitor/entity"
	"monitor/utils"
	"strconv"
	"strings"
	"time"

	"github.com/guonaihong/gout"
)

type ApiResponse struct {
	Data ApiData `json:"data"`
}

type ApiData struct {
	StockInfoList []entity.StockCurrentInfo `json:"diff"`
}

func QueryStockInfo(codeList *[]entity.StockConfig) map[string]entity.StockCurrentInfo {
	var codeStr = strings.Join(utils.MapToStr(codeList, stockCodeToApiCode), ",")
	url := "https://push2delay.eastmoney.com/api/qt/ulist.np/get?fields=f2,f3,f12,f13,f14,f15,f16,f18,f232&fltt=2&secids=" + codeStr
	var response ApiResponse
	var result = make(map[string]entity.StockCurrentInfo)

	// 实现重试机制，最多重试3次
	maxRetries := 3
	var err error
	for attempt := 1; attempt <= maxRetries; attempt++ {
		err = gout.GET(url).
			SetTimeout(10*time.Second). // 设置10秒超时
			Debug(false).
			BindJSON(&response).
			Do()

		if err == nil && response.Data.StockInfoList != nil && len(response.Data.StockInfoList) > 0 {
			// 成功获取到数据，跳出重试循环
			break
		}

		if attempt < maxRetries {
			// 等待一段时间后重试，使用指数退避策略
			waitTime := time.Duration(attempt) * time.Second
			log.Printf("东财API调用失败 (尝试 %d/%d)，%v 后重试: %v", attempt, maxRetries, waitTime, err)
			time.Sleep(waitTime)
		} else {
			log.Printf("东财API调用失败，已达到最大重试次数 (%d)，返回空结果: %v", maxRetries, err)
			return result
		}
	}
	usStart := 22
	usEnd := 5
	if utils.IsUsDST() {
		usStart = 21
		usEnd = 4
	}
	for _, info := range response.Data.StockInfoList {
		info.Name = strings.ReplaceAll(info.Name, " ", "")
		if info.Type == 105 || info.Type == 106 || info.Type == 107 {
			if utils.CheckNowBefore(usStart, 30) && utils.CheckNowAfter(usEnd, 0) {
				outInfo := QueryStockOutInfo(info)
				if outInfo != nil {
					// log.Printf("stock out info [%s]: %v", info.Code, outInfo)
					info.Price = outInfo.Price
					info.Diff = outInfo.Diff
				}
			}
		}
		result[info.Code] = info
	}
	return result
}

func QueryOneStockInfoByCode(code string) []entity.StockCurrentInfo {
	var codeStr = stockCodeToApiCode(entity.StockConfig{Code: code})
	url := "https://push2delay.eastmoney.com/api/qt/ulist.np/get?fields=f2,f3,f12,f13,f14,f15,f16,f18,f232&fltt=2&secids=" + codeStr
	var response ApiResponse

	err := gout.GET(url).Debug(false).BindJSON(&response).Do()
	if err != nil {
		return []entity.StockCurrentInfo{}
	}
	return response.Data.StockInfoList
}

func stockCodeToApiCode(stock entity.StockConfig) string {
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
