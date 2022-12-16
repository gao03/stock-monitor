package utils

import (
	_ "embed"
	"github.com/go-playground/assert/v2"
	"math"
	"testing"
)

func TestCalcMinAndMaxMonitorPrice_Percentage(t *testing.T) {
	min, max := CalcMinAndMaxMonitorPrice("3%", 10.0, 9.0)
	assert.Equal(t, min, 9.7)
	assert.Equal(t, max, 10.3)
}

func TestCalcMinAndMaxMonitorPrice_PercentagePositive(t *testing.T) {
	min, max := CalcMinAndMaxMonitorPrice("+4%", 10.0, 9.0)
	assert.Equal(t, min, math.MaxFloat64)
	assert.Equal(t, max, 10.4)
}

func TestCalcMinAndMaxMonitorPrice_PercentageNegative(t *testing.T) {
	min, max := CalcMinAndMaxMonitorPrice("-5%", 10.0, 9.0)
	assert.Equal(t, min, 9.5)
	assert.Equal(t, max, math.SmallestNonzeroFloat64)
}

func TestCalcMinAndMaxMonitorPrice_Percentage_Cost(t *testing.T) {
	min, max := CalcMinAndMaxMonitorPrice("|1%", 10.0, 9.0)
	assert.Equal(t, min, 8.91)
	assert.Equal(t, max, 9.09)
}

func TestCalcMinAndMaxMonitorPrice_PercentagePositive_Cost(t *testing.T) {
	min, max := CalcMinAndMaxMonitorPrice("|+2%", 10.0, 9.0)
	assert.Equal(t, min, math.MaxFloat64)
	assert.Equal(t, max, 9.18)
}

func TestCalcMinAndMaxMonitorPrice_PercentageNegative_Cost(t *testing.T) {
	min, max := CalcMinAndMaxMonitorPrice("|-5%", 10.0, 9.0)
	assert.Equal(t, min, 8.55)
	assert.Equal(t, max, math.SmallestNonzeroFloat64)
}

func TestCalcMinAndMaxMonitorPrice_Absolute(t *testing.T) {
	min, max := CalcMinAndMaxMonitorPrice("11", 10.0, 9.0)
	assert.Equal(t, min, 11.0)
	assert.Equal(t, max, 11.0)
}

func TestCalcMinAndMaxMonitorPrice_Add(t *testing.T) {
	min, max := CalcMinAndMaxMonitorPrice("+2", 10.0, 9.0)
	assert.Equal(t, min, math.MaxFloat64)
	assert.Equal(t, max, 12.0)
}

func TestCalcMinAndMaxMonitorPrice_Sub(t *testing.T) {
	min, max := CalcMinAndMaxMonitorPrice("-2", 10.0, 9.0)
	assert.Equal(t, min, 8.0)
	assert.Equal(t, max, math.SmallestNonzeroFloat64)
}

func TestCalcMinAndMaxMonitorPrice_Add_Cost(t *testing.T) {
	min, max := CalcMinAndMaxMonitorPrice("|+2", 10.0, 9.0)
	assert.Equal(t, min, math.MaxFloat64)
	assert.Equal(t, max, 11.0)
}

func TestCalcMinAndMaxMonitorPrice_Sub_Cost(t *testing.T) {
	min, max := CalcMinAndMaxMonitorPrice("|-2", 10.0, 9.0)
	assert.Equal(t, min, 7.0)
	assert.Equal(t, max, math.SmallestNonzeroFloat64)
}

func TestNotify(t *testing.T) {
	Notify("京山轻机", "当前价格21.5; 涨幅9%", "https://xueqiu.com/")
}
