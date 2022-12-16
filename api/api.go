package api

import (
	"monitor/config"
	"monitor/utils"
	"strconv"
	"strings"
)
import "github.com/guonaihong/gout"

type ApiResponse struct {
	Data ApiData `json:"data"`
}

type ApiData struct {
	StockInfoList []StockCurrentInfo `json:"diff"`
}

type StockCurrentInfo struct {
	Price        float64 `json:"f2"`
	Diff         float64 `json:"f3"`
	Code         string  `json:"f12"`
	Type         int     `json:"f13"` // 0-SH,1-SZ
	Name         string  `json:"f14"`
	HighestPrice float64 `json:"f15"`
	OpenPrice    float64 `json:"f16"`
	BasePrice    float64 `json:"f18"`
	StockCode    string  `json:"f232"` // 转债对应的正股
}

func QueryStockInfo(codeList *[]config.StockConfig) map[string]StockCurrentInfo {
	var codeStr = strings.Join(utils.MapToStr(codeList, stockCodeToApiCode), ",")
	url := "https://push2.eastmoney.com/api/qt/ulist.np/get?fields=f2,f3,f12,f13,f14,f15,f16,f18,f232&fltt=2&secids=" + codeStr
	var response ApiResponse
	var result = make(map[string]StockCurrentInfo)
	err := gout.GET(url).Debug(false).BindJSON(&response).Do()
	if err != nil {
		return result
	}
	for _, info := range response.Data.StockInfoList {
		info.Name = strings.ReplaceAll(info.Name, " ", "")
		result[info.Code] = info
	}
	return result
}

func QueryOneStockInfoByCode(code string) []StockCurrentInfo {
	var codeStr = stockCodeToApiCode(config.StockConfig{Code: code})
	url := "https://push2.eastmoney.com/api/qt/ulist.np/get?fields=f2,f3,f12,f13,f14,f15,f16,f18,f232&fltt=2&secids=" + codeStr
	var response ApiResponse

	err := gout.GET(url).Debug(false).BindJSON(&response).Do()
	if err != nil {
		return []StockCurrentInfo{}
	}
	return response.Data.StockInfoList
}

func stockCodeToApiCode(stock config.StockConfig) string {
	s := stock.Code
	if stock.Type != nil {
		return strconv.Itoa(*stock.Type) + "." + stock.Code
	}
	// [0, 1, 105, 106, 116] // 深A、沪A、美股1、美股2、港股
	typeList := []int{0, 1, 105, 106, 116}

	return strings.Join(utils.MapToStr(&typeList, func(i int) string {
		return strconv.Itoa(i) + "." + s
	}), ",")
}
