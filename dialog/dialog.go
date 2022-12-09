package dialog

import (
	"github.com/ncruces/zenity"
	"github.com/samber/lo"
	"log"
	"monitor/api"
)

func InputNewStock() *api.StockCurrentInfo {
	code, err := zenity.Entry("输入股票编号：")
	if err != nil {
		log.Fatal(err)
		return nil
	}

	stockList := api.QueryOneStockInfoByCode(code)
	if len(stockList) == 0 {
		_ = zenity.Error("Code不存在：" + code)
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
