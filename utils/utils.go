package utils

import (
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"os"
	"os/user"
	"path/filepath"
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
