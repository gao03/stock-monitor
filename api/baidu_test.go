package api

import (
	"github.com/go-playground/assert/v2"
	"monitor/utils"
	"os"
	"testing"
)

func TestBaiduApi_GetOrRefreshAccessToken(t *testing.T) {
	api := BaiduApi{
		ClientId:     "",
		ClientSecret: "",
	}
	token := api.GetOrRefreshAccessToken()
	println(token)
	assert.NotEqual(t, token, "")
}

func TestBaiduApi_OcrTable(t *testing.T) {
	api := BaiduApi{
		ClientId:     "",
		ClientSecret: "",
	}
	image, err := os.ReadFile("/Users/gaozhiqiang03/stock.png")
	if err != nil {
		return
	}
	err, result := api.OcrTable(image)
	assert.Equal(t, err, nil)

	assert.NotEqual(t, result, nil)

	println(utils.ToJsonForLog(result))
}
