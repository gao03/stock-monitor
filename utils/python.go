package utils

import (
	_ "embed"
	"log"
	"os"
	"os/exec"
	"strings"
)

//go:embed assets/update_stock_monitor_by_easemoney.py
var updateStockByEastMoneyScriptContent string

func UpdateStockByEastMoney() {
	cmd := exec.Command(os.Getenv("STOCK_MONITOR_PYTHON"), "-")
	cmd.Stdin = strings.NewReader(updateStockByEastMoneyScriptContent)

	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	err := cmd.Run()
	if err != nil {
		log.Fatal(err)
	}

	return
}
