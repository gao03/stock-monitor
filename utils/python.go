package utils

import (
	"bytes"
	_ "embed"
	"log"
	"os/exec"
	"strings"
)

func UpdateStockByEastMoney() {
	/*
		tell current window
			toggle hotkey window
		end tell
	*/

	cmd := exec.Command(`osascript`, "-s", "h", "-e", `
on wait_for(str)
	tell application "iTerm"
		tell current window
			set a to 0
			repeat until (a = 1)
				set op to text of current session
				if (op contains str) then
					set a to 1
					log op
				end if
				delay 1
			end repeat
		end tell
	end tell
end wait_for
tell application "iTerm"
	tell current window
		create tab with default profile
	end tell
end tell
tell application "Finder"
	set visible of process "iTerm2" to false
end tell
tell application "iTerm"
	tell current window
		tell current session
			write text "/usr/local/bin/python3.10 ~/sync/code/east_money/update_stock_monitor_by_easemoney.py"
			write text "printf 'done%.0s' {1..5}"
		end tell
		my wait_for("donedonedonedonedone")
		tell current tab
			close
		end tell
	end tell
end tell
`)

	var outb, errb bytes.Buffer
	cmd.Stdout = &outb
	cmd.Stderr = &errb
	err := cmd.Run()
	if err != nil {
		log.Fatal(err)
	}
	output := errb.String()
	start := strings.LastIndex(output, "easemoney.py")
	end := strings.Index(output, "donedonedonedonedone")

	scriptOutput := strings.TrimSpace(output[start+12 : end])
	log.Println(scriptOutput)
	return
}
