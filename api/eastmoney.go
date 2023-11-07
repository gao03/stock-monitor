package api

import (
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
	url := "https://push2.eastmoney.com/api/qt/ulist.np/get?fields=f2,f3,f12,f13,f14,f15,f16,f18,f232&fltt=2&secids=" + codeStr
	var response ApiResponse
	var result = make(map[string]entity.StockCurrentInfo)
	err := gout.GET(url).Debug(false).BindJSON(&response).Do()
	if err != nil {
		return result
	}
	usStart := 22
	usEnd := 5
	if isDST() {
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

func isDST() bool {
	loc, _ := time.LoadLocation("America/New_York")
	t := time.Now().In(loc)
	_, offset := t.Zone()
	return offset/60/60 == -4 // 夏令时时，美国东部时间为UTC-4
}

func QueryOneStockInfoByCode(code string) []entity.StockCurrentInfo {
	var codeStr = stockCodeToApiCode(entity.StockConfig{Code: code})
	url := "https://push2.eastmoney.com/api/qt/ulist.np/get?fields=f2,f3,f12,f13,f14,f15,f16,f18,f232&fltt=2&secids=" + codeStr
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
