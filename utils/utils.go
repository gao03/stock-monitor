package utils

import (
	_ "embed"
	"encoding/json"
	"errors"
	"github.com/ncruces/zenity"
	"math"
	"os"
	"os/user"
	"path/filepath"
	"strconv"
	"strings"
	"time"
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
	f := strconv.FormatFloat(num, 'f', 3, 64)
	if f[len(f)-1] == '0' {
		return f[:len(f)-1]
	}
	return f
}

func CheckIsMarketClose() bool {
	if CheckIsMarketCloseDay() {
		return true
	}

	t := time.Now()
	minute := t.Hour()*60 + t.Minute()
	return minute > 11*60+40 && minute < 13*60
}

func CheckIsMarketCloseDay() bool {
	t := time.Now()
	if t.Weekday() == time.Saturday || t.Weekday() == time.Sunday {
		return true
	}

	minute := t.Hour()*60 + t.Minute()

	// 9.15 - 11:40, 13:00-15:10 中间跑，其他时间休息
	if minute < 9*60+15 || minute > 15*60+10 {
		return true
	}

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
// 9 最新价格等于9
// +3、-3：价格涨跌幅值
// |3%, |+3%, |-3%: 相对于成本价的涨跌幅比例
// 参数：监控配置、
func CalcMinAndMaxMonitorPrice(monitor string, basePrice float64, costPrice float64) (float64, float64) {
	minPrice := math.MaxFloat64
	maxPrice := math.SmallestNonzeroFloat64
	relativeToCost := false
	onlyIncr := false
	onlyDesc := false
	isPercentage := false
	if strings.HasPrefix(monitor, "|") {
		relativeToCost = true
		monitor = monitor[1:]
	}
	if strings.HasPrefix(monitor, "+") {
		onlyIncr = true
		monitor = monitor[1:]
	} else if strings.HasPrefix(monitor, "-") {
		onlyDesc = true
		monitor = monitor[1:]
	}
	if strings.HasSuffix(monitor, "%") {
		isPercentage = true
		monitor = monitor[:len(monitor)-1]
	}
	// 去掉符号以后，剩下的就是正整数
	monitorPrice, err := strconv.ParseFloat(monitor, 64)
	if err != nil || monitorPrice <= 0 {
		return minPrice, maxPrice
	}
	// 绝对价格的监控
	if !isPercentage && !onlyDesc && !onlyIncr {
		return monitorPrice, monitorPrice
	}
	calcBasePrice := If(relativeToCost, costPrice, basePrice)
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
		minPrice = math.MaxFloat64
	}
	if onlyDesc {
		maxPrice = math.SmallestNonzeroFloat64
	}
	return minPrice, maxPrice
}

func CheckMonitorPrice(monitor string, basePrice float64, costPrice float64, currentPrice float64) bool {
	min, max := CalcMinAndMaxMonitorPrice(monitor, basePrice, costPrice)
	return currentPrice < min || currentPrice > max
}

func Notify(title string, content string, url string) {
	//head := ""
	//if content == "" {
	//	head = title
	//	title = ""
	//} else {
	//	head = content
	//}
	zenity.Warning("Are you sure you want to proceed?",
		zenity.Title("Warning"),
		zenity.NoIcon,
		zenity.OKLabel(""))
	//note := gosxnotifier.NewNotification(head)
	//note.Title = "股票监控"
	//note.Link = url
	//note.Subtitle = title
	//err := note.Push()
	//if err != nil {
	//	log.Fatal(err)
	//	return
	//}
	//notify.Notify("", title, content, iconFilePath)
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
