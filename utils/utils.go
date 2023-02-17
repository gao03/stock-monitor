package utils

import (
	_ "embed"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"math"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/samber/lo"
)

func ToJson(v interface{}) string {
	s, err := json.Marshal(v)
	return checkToJson(s, err)
}

func ToJsonForLog(v interface{}) string {
	s, err := json.MarshalIndent(v, "", "  ")
	return checkToJson(s, err)
}

func FileIsExists(name string) bool {
	_, err := os.Stat(name)
	if err == nil {
		return true
	}
	if errors.Is(err, os.ErrNotExist) {
		return false
	}
	return false
}

func ExpandUser(path string) string {
	usr, _ := user.Current()
	dir := usr.HomeDir
	if strings.HasPrefix(path, "~/") {
		return filepath.Join(dir, path[2:])
	} else if path == "~" {
		return dir
	} else {
		return path
	}
}

func checkToJson(s []byte, err error) string {
	if err != nil {
		panic(err)
	}
	return string(s)
}

func MapToStr[T interface{} | int | float64](vs *[]T, f func(T) string) []string {
	vsm := make([]string, len(*vs))
	for i, v := range *vs {
		vsm[i] = f(v)
	}
	return vsm
}

func FloatToStr(num float64) string {
	return fmt.Sprintf("%6.02f", num)
}

func CalcReturn(cost float64, current float64) string {
	return FloatToStr((current - cost) / math.Abs(cost) * 100)
}

func FormatPrice(num float64) string {
	if num < 1 {
		return fmt.Sprintf("%6.03f", num)
	}
	return fmt.Sprintf("%6.02f", num)
}

func CheckIsMarketClose() bool {
	if CheckIsMarketCloseDay() {
		return true
	}

	t := time.Now()
	minute := t.Hour()*60 + t.Minute()
	return minute > 12*60+10 && minute < 13*60
}

func CheckIsMarketCloseDay() bool {
	t := time.Now()
	if t.Weekday() == time.Saturday || t.Weekday() == time.Sunday {
		return true
	}

	// minute := t.Hour()*60 + t.Minute()

	// 9.15 - 20:10 中间跑，其他时间休息
	// if t.Hour() < 9 || t.Hour() > 20 {
	// 	return true
	// }

	return false
}

func NewTicker(d time.Duration, callback func()) *time.Ticker {
	callback()
	ticker := time.NewTicker(d)
	go func() {
		for {
			select {
			case <-ticker.C:
				callback()
			}
		}
	}()
	return ticker
}

func On(c chan struct{}, callback func()) {
	go func() {
		for {
			select {
			case <-c:
				callback()
			}
		}
	}()
}

// CalcMinAndMaxMonitorPrice
// 3%(相当于+/-3%), +3%, -3%：价格涨跌幅比例
// 9+/9- 当前价格大于9/小于
// +3、-3：价格涨跌幅值
// |3%, |+3%, |-3%: 相对于成本价的涨跌幅比例
// 参数：监控配置、
func CalcMinAndMaxMonitorPrice(rule string, todayBasePrice float64, costPrice float64) (float64, float64) {
	minPrice := math.SmallestNonzeroFloat64
	maxPrice := math.MaxFloat64
	relativeToCost := false
	onlyIncr := false
	onlyDesc := false
	isPercentage := false
	isAbsolute := false
	isAbsoluteInc := true // 绝对值判断的涨/跌
	if strings.HasPrefix(rule, "|") {
		relativeToCost = true
		rule = rule[1:]
	}
	if strings.HasPrefix(rule, "+") {
		onlyIncr = true
		rule = rule[1:]
	} else if strings.HasPrefix(rule, "-") {
		onlyDesc = true
		rule = rule[1:]
	}
	if strings.HasSuffix(rule, "%") {
		isPercentage = true
		rule = rule[:len(rule)-1]
	}
	if strings.HasSuffix(rule, "+") || strings.HasSuffix(rule, "-") {
		isAbsolute = true
		isAbsoluteInc = rule[len(rule)-1] == '+'
		rule = rule[:len(rule)-1]
	}
	// 去掉符号以后，剩下的就是正整数
	monitorPrice, err := strconv.ParseFloat(rule, 64)
	if err != nil || monitorPrice <= 0 {
		return minPrice, maxPrice
	}
	// 绝对价格的监控
	if isAbsolute {
		if isAbsoluteInc {
			return minPrice, monitorPrice
		}
		return monitorPrice, maxPrice
	}
	calcBasePrice := If(relativeToCost, costPrice, todayBasePrice)
	if isPercentage {
		minPrice = calcBasePrice * (1 - monitorPrice/100)
		maxPrice = calcBasePrice * (1 + monitorPrice/100)
	} else {
		minPrice = calcBasePrice - monitorPrice
		maxPrice = calcBasePrice + monitorPrice
	}
	minPrice = RoundNum(minPrice, 2)
	maxPrice = RoundNum(maxPrice, 2)

	if onlyIncr {
		minPrice = math.SmallestNonzeroFloat64
	}
	if onlyDesc {
		maxPrice = math.MaxFloat64
	}
	return minPrice, maxPrice
}

func CheckMonitorPrice(rule string, todayBasePrice float64, costPrice float64, currentPrice float64) bool {
	min, max := CalcMinAndMaxMonitorPrice(rule, todayBasePrice, costPrice)
	return currentPrice < min || currentPrice > max
}

func Notify(title string, subtitle string, content string, url string) {
	err := exec.Command("terminal-notifier",
		"-title", title,
		"-message", content,
		"-subtitle", subtitle,
		"-open", url,
	).Run()
	if err != nil {
		log.Fatalln(err)
		return
	}
}

// Exists 判断所给路径文件/文件夹是否存在
func Exists(path string) bool {
	_, err := os.Stat(path) //os.Stat获取文件信息
	if err != nil {
		if os.IsExist(err) {
			return true
		}
		return false
	}
	return true
}

// IsDir 判断所给路径是否为文件夹
func IsDir(path string) bool {
	s, err := os.Stat(path)
	if err != nil {
		return false
	}
	return s.IsDir()
}

// IsFile 判断所给路径是否为文件
func IsFile(path string) bool {
	return !IsDir(path)
}

func RoundNum(val float64, precision int) float64 {
	p := math.Pow10(precision)
	return math.Floor(val*p+0.5) / p
}

func If[T any](condition bool, trueVal, falseVal T) T {
	if condition {
		return trueVal
	}
	return falseVal
}

func IsTrue(b *bool) bool {
	return b != nil && *b
}

type StockBaseInfo struct {
	Code string `json:"code"`
	Type int    `json:"type"` // 0-SH,1-SZ
	Name string `json:"name"`
}

//go:embed assets/all_stock.json
var allStockStr string

func SearchStockByName(name string) []StockBaseInfo {
	var result []StockBaseInfo

	err := json.Unmarshal([]byte(allStockStr), &result)

	if err != nil {
		return []StockBaseInfo{}
	}

	lst := lo.Filter(result, func(item StockBaseInfo, index int) bool {
		return item.Name == name
	})
	if len(lst) > 0 {
		return lst
	}
	return lo.Filter(result, func(item StockBaseInfo, index int) bool {
		return strings.Contains(item.Name, name)
	})
}

func CheckNowBetween(startHour, startMinute, endHour, endMinute int) bool {
	return CheckNowAfter(startHour, startMinute) && CheckNowBefore(endHour, endMinute)
}

func CheckNowBefore(hour, minute int) bool {
	now := time.Now()
	nm := now.Hour()*60 + now.Minute()
	return nm < hour*60+minute
}

func CheckNowAfter(hour, minute int) bool {
	now := time.Now()
	nm := now.Hour()*60 + now.Minute()
	return nm > hour*60+minute
}

func BoolPointer(b bool) *bool {
	return &b
}
