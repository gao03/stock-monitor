package dialog

import (
	"log"
	"monitor/api"
	"monitor/entity"
	"monitor/utils"
	"regexp"
	"strconv"
	"strings"

	"github.com/ncruces/zenity"
	"github.com/samber/lo"
)

func InputNewStock() *entity.StockConfig {
	codeOrName, err := zenity.Entry("输入 股票编号/名称[#是否置顶][#持仓成本][#持仓数量][#是否启用时分图]")
	if err != nil {
		log.Fatal(err)
		return nil
	}

	inputList := strings.Split(codeOrName, "#")
	stock := entity.StockConfig{
		ShowInTitle:       utils.BoolPointer(false),
		EnableRealTimePic: false,
	}
	if len(inputList) > 1 {
		// 后续可以支持其他配置
		codeOrName = inputList[0]
		// 第二个字段是是否展示在状态栏
		stock.ShowInTitle = utils.BoolPointer(inputList[1] == "1")
		if len(inputList) > 2 {
			data, err := strconv.ParseFloat(inputList[2], 64)
			if err != nil {
				stock.CostPrice = data
			}
		}
		if len(inputList) > 3 {
			data, err := strconv.ParseFloat(inputList[3], 64)
			if err != nil {
				stock.Position = data
			}
		}
		if len(inputList) > 4 {
			stock.EnableRealTimePic = inputList[4] == "1"
		}
	}

	isAlphaNum := regexp.MustCompile(`^[A-Za-z0-9]+$`).MatchString
	var stockList []entity.StockCurrentInfo
	if isAlphaNum(codeOrName) {
		stockList = api.QueryOneStockInfoByCode(codeOrName)
	} else {
		stockByNameList := utils.SearchStockByName(codeOrName)
		stockList = lo.Map(stockByNameList, func(item utils.StockBaseInfo, index int) entity.StockCurrentInfo {
			return entity.StockCurrentInfo{
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
	var stockCurrentInfo entity.StockCurrentInfo
	if len(stockList) > 1 {
		stockNameList := lo.Map(stockList, func(item entity.StockCurrentInfo, index int) string {
			return item.Name
		})
		selectStockName, err := zenity.ListItems("该Code对应多个股票，请选择", stockNameList...)
		if err != nil {
			log.Println(err)
			return nil
		}
		fl := lo.Filter(stockList, func(item entity.StockCurrentInfo, index int) bool {
			return item.Name == selectStockName
		})
		if len(fl) == 0 {
			_ = zenity.Error("添加异常")
			return nil
		}
		stockCurrentInfo = fl[0]
	} else {
		stockCurrentInfo = stockList[0]
	}

	stock.Name = stockCurrentInfo.Name
	stock.Code = stockCurrentInfo.Code
	stock.Type = &stockCurrentInfo.Type

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
