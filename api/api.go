package api

import (
	"github.com/samber/lo"
	"monitor/config"
	"strconv"
	"strings"
)
import "github.com/guonaihong/gout"

type Response struct {
	Data StockInfoData `json:"data"`
}

type StockInfoData struct {
	StockInfoList []StockCurrentInfo `json:"diff"`
}

type StockCurrentInfo struct {
	Price        float64 `json:"f2"`
	Diff         float64 `json:"f3"`
	Code         string  `json:"f12"`
	Type         int     `json:"f13"`
	Name         string  `json:"f14"`
	HighestPrice float64 `json:"f15"`
	OpenPrice    float64 `json:"f16"`
	BasePrice    float64 `json:"f18"`
	StockCode    string  `json:"f232"` // 转债对应的正股
}

func QueryStockInfo(codeList *[]config.StockConfig) map[string]StockCurrentInfo {
	var codeStr = strings.Join(lo.Map(*codeList, stockCodeToApiCode), ",")
	url := "https://push2.eastmoney.com/api/qt/ulist.np/get?fields=f2,f3,f12,f13,f14,f15,f16,f18,f232&fltt=2&secids=" + codeStr
	var response Response
	var result = make(map[string]StockCurrentInfo)
	err := gout.GET(url).Debug(false).BindJSON(&response).Do()
	if err != nil {
		return result
	}
	return lo.SliceToMap(response.Data.StockInfoList, func(t StockCurrentInfo) (string, StockCurrentInfo) {
		return strings.ReplaceAll(t.Code, " ", ""), t
	})
}

func stockCodeToApiCode(stock config.StockConfig, _ int) string {
	s := stock.Code
	if stock.Type != nil {
		return strconv.Itoa(*stock.Type) + "." + stock.Code
	}
	// [0, 1, 105, 106, 116] // 深A、沪A、美股1、美股2、港股
	typeList := []int{0, 1, 105, 106, 116}
	return strings.Join(lo.Map(typeList, func(i int, _ int) string {
		return strconv.Itoa(i) + "." + s
	}), ",")
}
