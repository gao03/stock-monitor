package config

import (
	"encoding/json"
	"fmt"
	"log"
	"monitor/entity"
	"monitor/utils"
	"os"
	"time"
)

var FILE_NAME = utils.ExpandUser("~/.config/StockMonitor.json")

var LATEST_CONFIG *[]entity.StockConfig

type ShowInTitleType bool

func (e *ShowInTitleType) UnmarshalJSON(b []byte) error {
	var s string
	if err := json.Unmarshal(b, &s); err != nil {
		return err
	}
	if s == "" {
		*e = true
	} else {
		*e = s == "true"
	}
	return nil
}

func ReadConfig() *[]entity.StockConfig {
	if LATEST_CONFIG != nil {
		return LATEST_CONFIG
	}

	LATEST_CONFIG = ReadConfigFromFile()
	return LATEST_CONFIG
}

func ReadConfigFromFile() *[]entity.StockConfig {
	var result []entity.StockConfig

	data, err := os.ReadFile(FILE_NAME)
	if err != nil {
		return &result
	}

	err = json.Unmarshal(data, &result)
	if err != nil {
		log.Fatalln(err)
	}

	return &result
}

func IsConfigRefreshToday() bool {
	file, err := os.Stat(FILE_NAME)

	if err != nil {
		fmt.Println(err)
		return false
	}

	modTime := file.ModTime()
	now := time.Now()
	return modTime.Year() == now.Year() &&
		modTime.Month() == now.Month() &&
		modTime.Day() == now.Day()
}

func HasEastMoneyAccount() bool {
	return os.Getenv("EAST_MONEY_USER") != "" && os.Getenv("STOCK_MONITOR_PYTHON") != ""
}

func WriteConfig(lst *[]entity.StockConfig) {
	data, err := json.MarshalIndent(*lst, "", "  ")
	if err != nil {
		log.Fatalln("err in json ", err)
		return
	}
	err = os.WriteFile(FILE_NAME, data, 0644)
	if err != nil {
		log.Fatalln("err in write file", err)
		return
	}
}
