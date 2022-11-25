package utils

import (
	_ "embed"
	"fmt"
	"io"
	"log"
	"os"
	"os/exec"
)

func UpdateStockByEastMoney() {
	cmd := exec.Command(`osascript`, "-s", "h", "-e", `tell application "iTerm"
	tell current window
		toggle hotkey window
	end tell
	tell current session of current window
		write text "/usr/local/bin/python3.10 /Users/gaozhiqiang03/sync/code/east_money/update_stock_monitor_by_easemoney.py"
	end tell
end tell`)
	stderr, err := cmd.StderrPipe()
	log.SetOutput(os.Stderr)

	if err != nil {
		log.Fatal(err)
	}

	if err := cmd.Start(); err != nil {
		log.Fatal(err)
	}

	slurp, _ := io.ReadAll(stderr)
	fmt.Printf("%s\n", slurp)

	if err := cmd.Wait(); err != nil {
		log.Fatal(err)
	}
	// TODO: 需要等待完成
}
