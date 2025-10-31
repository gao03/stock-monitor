package main

import (
	"flag"
	"fmt"
	"log"
	"monitor/pkg/app"
	"monitor/pkg/logger"
	"os"
	"os/exec"
	"syscall"
	"time"

	"github.com/kardianos/osext"
)

var (
	logLevel   = flag.String("log-level", "info", "日志级别 (debug, info, warn, error, fatal)")
	logFile    = flag.String("log-file", "", "日志文件路径，空表示输出到控制台")
	configFile = flag.String("config", "", "配置文件路径，空表示使用默认路径")
	daemon     = flag.Bool("daemon", true, "是否以守护进程模式运行")
	version    = flag.Bool("version", false, "显示版本信息")
)

const (
	appVersion = "2.0.0"
	appName    = "股票监控"
)

func main() {
	flag.Parse()

	if *version {
		fmt.Printf("%s v%s\n", appName, appVersion)
		os.Exit(0)
	}

	// 如果启用守护进程模式且没有传递参数，则后台运行
	if *daemon && len(os.Args) == 1 {
		runInBackground()
		return
	}

	// 解析日志级别
	level := parseLogLevel(*logLevel)

	// 创建应用程序配置
	cfg := &app.Config{
		LogLevel:       level,
		LogFile:        *logFile,
		ConfigFile:     *configFile,
		UpdateInterval: 2 * time.Second,
	}

	// 创建应用程序实例
	application, err := app.New(cfg)
	if err != nil {
		log.Fatalf("创建应用程序失败: %v", err)
	}

	// 运行应用程序
	if err := application.Run(); err != nil {
		log.Fatalf("运行应用程序失败: %v", err)
	}
}

// parseLogLevel 解析日志级别
func parseLogLevel(level string) logger.Level {
	switch level {
	case "debug":
		return logger.DEBUG
	case "info":
		return logger.INFO
	case "warn":
		return logger.WARN
	case "error":
		return logger.ERROR
	case "fatal":
		return logger.FATAL
	default:
		return logger.INFO
	}
}

// runInBackground 后台运行
func runInBackground() {
	executeFilePath, err := os.Executable()
	if err != nil {
		log.Printf("获取可执行文件路径失败: %v", err)
		executeFilePath = os.Args[0]
	}

	envName := "XW_DAEMON"
	envValue := "SUB_PROC"

	// 检查是否已经是子进程
	if os.Getenv(envName) == envValue {
		return
	}

	// 准备子进程命令
	cmd := &exec.Cmd{
		Path: executeFilePath,
		Args: append(os.Args, "--daemon=false"), // 禁用子进程的守护模式
		Env:  append(os.Environ(), fmt.Sprintf("%s=%s", envName, envValue)),
	}

	// 设置日志文件
	logFile := "/tmp/stock-monitor-daemon.log"
	if stdout, err := os.OpenFile(logFile, os.O_WRONLY|os.O_APPEND|os.O_CREATE, 0666); err == nil {
		cmd.Stderr = stdout
		cmd.Stdout = stdout
	}

	// 启动子进程
	if err := cmd.Start(); err != nil {
		log.Fatalf("启动后台进程失败: %v", err)
	}

	fmt.Printf("后台进程已启动，PID: %d，日志文件: %s\n", cmd.Process.Pid, logFile)
	os.Exit(0)
}

// restartSelf 重启自身（工具函数，供其他模块使用）
func restartSelf() {
	self, err := osext.Executable()
	if err != nil {
		log.Printf("获取可执行文件路径失败: %v", err)
		return
	}

	args := os.Args
	env := os.Environ()

	if err := syscall.Exec(self, args, env); err != nil {
		log.Printf("重启失败: %v", err)
	}
}