package api

import (
	"encoding/base64"
	"errors"
	"github.com/guonaihong/gout"
	"github.com/samber/lo"
	"log"
	"strconv"
	"time"
)

const debug = true

type BaiduApi struct {
	ClientId           string
	ClientSecret       string
	AccessToken        string
	AccessTokenExpires int64
}

type OcrTableResult struct {
	Header []string
	Body   []map[string]string
}

func (b *BaiduApi) OcrTable(image []byte) (error, OcrTableResult) {
	img := base64.StdEncoding.EncodeToString(image)
	resp := ocrResponse{}

	err := gout.
		// 设置POST方法和url
		POST("https://aip.baidubce.com/rest/2.0/ocr/v1/table").
		SetQuery(gout.H{"access_token": b.GetOrRefreshAccessToken()}).
		SetWWWForm(gout.H{"image": img}).
		Debug(debug).
		SetProxy("http://127.0.0.1:8899").
		BindJSON(&resp).
		Do()
	if err != nil || resp.TablesResult == nil || len(resp.TablesResult) == 0 || resp.TablesResult[0].Body == nil {
		log.Println(err)
		return errors.New("解析失败"), OcrTableResult{}
	}

	body := resp.TablesResult[0].Body

	rows := lo.PartitionBy(body, func(item ocrTableBody) int {
		return item.RowStart
	})

	result := OcrTableResult{}
	header := make(map[int]string)
	for _, row := range rows {
		one := lo.SliceToMap(row, func(item ocrTableBody) (int, string) {
			return item.ColStart, item.Words
		})
		if len(result.Header) == 0 {
			header = one
			result.Header = lo.Values(one)
			continue
		}
		data := lo.SliceToMap(row, func(item ocrTableBody) (string, string) {
			key := strconv.Itoa(item.ColStart)
			headerName, ok := header[item.ColStart]
			if ok {
				key = headerName
			}
			return key, item.Words
		})
		result.Body = append(result.Body, data)
	}

	return nil, result
}

func (b *BaiduApi) GetOrRefreshAccessToken() string {
	if b.AccessToken == "" || b.AccessTokenExpires < time.Now().Unix() {
		b.refreshAccessToken()
	}
	return b.AccessToken
}

func (b *BaiduApi) refreshAccessToken() string {
	resp := tokenApiResponse{}

	err := gout.
		// 设置POST方法和url
		POST("https://aip.baidubce.com/oauth/2.0/token").
		SetQuery(gout.H{
			"grant_type":    "client_credentials",
			"client_id":     b.ClientId,
			"client_secret": b.ClientSecret,
		}).
		Debug(debug).
		BindJSON(&resp).
		Do()
	if err != nil || resp.AccessToken == "" {
		return ""
	}
	b.AccessToken = resp.AccessToken
	b.AccessTokenExpires = resp.ExpiresIn + time.Now().Unix()
	return b.AccessToken
}

type tokenApiResponse struct {
	ExpiresIn   int64  `json:"expires_in"`
	AccessToken string `json:"access_token"`
}

type ocrTableBody struct {
	CellLocation []struct {
		X int `json:"x"`
		Y int `json:"y"`
	} `json:"cell_location"`
	ColStart int    `json:"col_start"`
	RowStart int    `json:"row_start"`
	RowEnd   int    `json:"row_end"`
	ColEnd   int    `json:"col_end"`
	Words    string `json:"words"`
}
type ocrResponse struct {
	TablesResult []struct {
		TableLocation []struct {
			X int `json:"x"`
			Y int `json:"y"`
		} `json:"table_location"`
		Header []interface{}  `json:"header"`
		Body   []ocrTableBody `json:"body"`
		Footer []interface{}  `json:"footer"`
	} `json:"tables_result"`
	TableNum int   `json:"table_num"`
	LogID    int64 `json:"log_id"`
}
