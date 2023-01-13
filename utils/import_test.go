package utils

import (
	"monitor/entity"
	"reflect"
	"testing"
)

func TestImportFromClipboardImage(t *testing.T) {
	tests := []struct {
		name string
		want []entity.StockConfig
	}{
		{"Init", nil},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := ImportFromClipboardImage(); !reflect.DeepEqual(got, tt.want) {
				t.Errorf("ImportFromClipboardImage() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestReadImageFromClipboard(t *testing.T) {
	println(ReadImageFromClipboard())
}
