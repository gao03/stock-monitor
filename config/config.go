package config

import (
	"encoding/json"
	"io/ioutil"
	"log"
	"monitor/utils"
)

var FILE_NAME = utils.ExpandUser("~/.config/StockMonitor.json")

var LATEST_CONFIG *[]StockConfig

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

type StockConfig struct {
	Code              string   `json:"code"`
	Type              *int     `json:"type"`
	CostPrice         float64  `json:"cost"`
	Position          float64  `json:"position"`
	Name              string   `json:"name"`
	ShopInTitle       bool     `json:"showInTitle"`
	EnableRealTimePic bool     `json:"enableRealTimePic"`
	MonitorPrices     []string `json:"monitorPrices"`
}

func ReadConfig() *[]StockConfig {
	if LATEST_CONFIG != nil {
		return LATEST_CONFIG
	}

	LATEST_CONFIG = ReadConfigFromFile()
	return LATEST_CONFIG
}

func ReadConfigFromFile() *[]StockConfig {
	var result []StockConfig

	data, err := ioutil.ReadFile(FILE_NAME)
	if err != nil {
		return &result
	}

	err = json.Unmarshal(data, &result)
	if err != nil {
		log.Fatalln(err)
	}

	return &result
}

func WriteConfig(lst *[]StockConfig) {
	data, err := json.MarshalIndent(*lst, "", "  ")
	if err != nil {
		log.Fatalln("err in json ", err)
		return
	}
	err = ioutil.WriteFile(FILE_NAME, data, 0644)
	if err != nil {
		log.Fatalln("err in write file", err)
		return
	}
}
