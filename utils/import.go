package utils

import (
	"log"
	"monitor/entity"
)
import "golang.design/x/clipboard"

func ImportFromClipboardImage() []entity.StockConfig {

	return nil
}

func ReadImageFromClipboard() []byte {
	err := clipboard.Init()
	if err != nil {
		log.Println(err)
		return nil
	}
	return clipboard.Read(clipboard.FmtImage)
}
