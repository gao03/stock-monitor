package dialog

import (
	"github.com/ncruces/zenity"
	"github.com/samber/lo"
	"log"
	"monitor/api"
	"monitor/utils"
	"regexp"
)

func InputNewStock() *api.StockCurrentInfo {
	codeOrName, err := zenity.Entry("输入股票编号/名称：")
	if err != nil {
		log.Fatal(err)
		return nil
	}

	isAlphaNum := regexp.MustCompile(`^[A-Za-z0-9]+$`).MatchString
	var stockList []api.StockCurrentInfo
	if isAlphaNum(codeOrName) {
		stockList = api.QueryOneStockInfoByCode(codeOrName)
	} else {
		stockByNameList := utils.SearchStockByName(codeOrName)
		stockList = lo.Map(stockByNameList, func(item utils.StockBaseInfo, index int) api.StockCurrentInfo {
			return api.StockCurrentInfo{
				Code: item.Code,
				Type: item.Type,
				Name: item.Name,
			}
		})
	}

	if len(stockList) == 0 {
		_ = zenity.Error("股票不存在：" + codeOrName)
		return nil
	}
	var stock api.StockCurrentInfo
	if len(stockList) > 1 {
		stockNameList := lo.Map(stockList, func(item api.StockCurrentInfo, index int) string {
			return item.Name
		})
		selectStockName, err := zenity.ListItems("该Code对应多个股票，请选择", stockNameList...)
		if err != nil {
			log.Println(err)
			return nil
		}
		fl := lo.Filter(stockList, func(item api.StockCurrentInfo, index int) bool {
			return item.Name == selectStockName
		})
		if len(fl) == 0 {
			_ = zenity.Error("添加异常")
			return nil
		}
		stock = fl[0]
	} else {
		stock = stockList[0]
	}

	err = zenity.Question("确认添加[ " + stock.Name + " ]?")
	if err != nil {
		println("err", err)
		return nil
	}

	return &stock
}

func Confirm(message string) bool {
	err := zenity.Question(message)
	if err != nil {
		println("err", err)
		return false
	}

	return true
}

func Input(message string) string {
	s, err := zenity.Entry(message)
	if err != nil {
		println(err)
		return ""
	}
	return s
}
