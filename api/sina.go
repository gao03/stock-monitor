package api

import (
	"github.com/guonaihong/gout"
	"log"
	"monitor/entity"
	"regexp"
	"strconv"
	"strings"
)

func QueryStockOutInfo(stock entity.StockCurrentInfo) *entity.StockOutPrice {
	var response string
	err := gout.GET("https://hq.sinajs.cn/rn").
		SetQuery(gout.H{"list": "gb_" + strings.ToLower(stock.Code)}).
		SetHeader(gout.H{"Referer": "https://sina.com.cn"}).
		Debug(true).
		BindBody(&response).
		Do()
	if err != nil {
		log.Println(err)
		return nil
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
