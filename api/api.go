package api

import (
	"monitor/utils"
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
}

func QueryStockInfo(codeList []string) map[string]StockCurrentInfo {
	var codeStr = strings.Join(utils.MapStr(codeList, func(s string) string {
		return "0." + s + "," + "1." + s
	}), ",")
	url := "https://push2.eastmoney.com/api/qt/ulist.np/get?fields=f2,f3,f12,f13,f14,f15,f16,f18&fltt=2&secids=" + codeStr
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
