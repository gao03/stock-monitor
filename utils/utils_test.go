package utils

import (
	_ "embed"
	"math"
	"testing"
)

func TestCalcMinAndMaxMonitorPrice(t *testing.T) {
	type args struct {
		rule           string
		todayBasePrice float64
		costPrice      float64
	}
	tests := []struct {
		name string
		args args
		min  float64
		max  float64
	}{
		{"Percentage", args{"3%", 11.0, 9.0}, 9.7, 10.3},
		{"PercentagePositive", args{"+4%", 10.0, 9.0}, math.SmallestNonzeroFloat64, 10.4},
		{"PercentageNegative", args{"-5%", 10.0, 9.0}, 9.5, math.MaxFloat64},
		{"Percentage_Cost", args{"|1%", 10.0, 9.0}, 8.91, 9.09},
		{"PercentagePositive_Cost", args{"|+2%", 10.0, 9.0}, math.SmallestNonzeroFloat64, 9.18},
		{"Percentage_NegativeCost", args{"|-5%", 10.0, 9.0}, 8.55, math.MaxFloat64},
		{"Absolute", args{"1", 10.0, 9.0}, 9, 11},
		{"Absolute_Up", args{"11+", 10.0, 9.0}, math.SmallestNonzeroFloat64, 11},
		{"Absolute_Down", args{"11-", 10.0, 9.0}, 11, math.MaxFloat64},
		{"Add", args{"+2", 10.0, 9.0}, math.SmallestNonzeroFloat64, 12},
		{"Sub", args{"-2", 10.0, 9.0}, 8, math.MaxFloat64},
		{"Add_Cost", args{"|+2", 10.0, 9.0}, math.SmallestNonzeroFloat64, 11},
		{"Sub_Cost", args{"|-2", 10.0, 9.0}, 7, math.MaxFloat64},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, got1 := CalcMinAndMaxMonitorPrice(tt.args.rule, tt.args.todayBasePrice, tt.args.costPrice)
			if got != tt.min {
				t.Errorf("CalcMinAndMaxMonitorPrice(%v) got min = %v, except min %v", tt.args, got, tt.min)
			}
			if got1 != tt.max {
				t.Errorf("CalcMinAndMaxMonitorPrice(%v) got max = %v, except max %v", tt.args, got1, tt.max)
			}
		})
	}
}
