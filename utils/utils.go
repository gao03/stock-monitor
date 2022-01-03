package utils

import (
	"encoding/json"
	"errors"
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

func MapStr(vs []string, f func(string) string) []string {
	vsm := make([]string, len(vs))
	for i, v := range vs {
		vsm[i] = f(v)
	}
	return vsm
}

func FloatToStr(num float64) string {
	return strconv.FormatFloat(num, 'f', 2, 64)
}

func CheckIsMarketClose() bool {
	t := time.Now()
	if t.Weekday() == time.Saturday || t.Weekday() == time.Sunday {
		return true
	}

	minute := t.Hour()*60 + t.Minute()

	// 9.15 - 11:40, 13:00-15:10 中间跑，其他时间休息
	if minute < 9*60+15 || (minute > 11*60+40 && minute < 13*60) || minute > 15*60+10 {
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
