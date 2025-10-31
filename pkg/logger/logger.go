package logger

import (
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"runtime"
	"sync"
	"time"
)

// Level 日志级别
type Level int

const (
	DEBUG Level = iota
	INFO
	WARN
	ERROR
	FATAL
)

// String 返回日志级别的字符串表示
func (l Level) String() string {
	switch l {
	case DEBUG:
		return "DEBUG"
	case INFO:
		return "INFO"
	case WARN:
		return "WARN"
	case ERROR:
		return "ERROR"
	case FATAL:
		return "FATAL"
	default:
		return "UNKNOWN"
	}
}

// Logger 结构化日志记录器
type Logger struct {
	level      Level
	output     io.Writer
	mu         sync.Mutex
	prefix     string
	timeFormat string
}

// New 创建新的日志记录器
func New(level Level, output io.Writer) *Logger {
	return &Logger{
		level:      level,
		output:     output,
		timeFormat: "2006-01-02 15:04:05",
	}
}

// NewFileLogger 创建文件日志记录器
func NewFileLogger(level Level, filename string) (*Logger, error) {
	if err := os.MkdirAll(filepath.Dir(filename), 0755); err != nil {
		return nil, fmt.Errorf("创建日志目录失败: %w", err)
	}

	file, err := os.OpenFile(filename, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0666)
	if err != nil {
		return nil, fmt.Errorf("打开日志文件失败: %w", err)
	}

	return New(level, file), nil
}

// SetLevel 设置日志级别
func (l *Logger) SetLevel(level Level) {
	l.mu.Lock()
	l.level = level
	l.mu.Unlock()
}

// SetPrefix 设置日志前缀
func (l *Logger) SetPrefix(prefix string) {
	l.mu.Lock()
	l.prefix = prefix
	l.mu.Unlock()
}

// log 内部日志记录方法
func (l *Logger) log(level Level, format string, args ...interface{}) {
	if level < l.level {
		return
	}

	l.mu.Lock()
	defer l.mu.Unlock()

	// 获取调用者信息
	_, file, line, ok := runtime.Caller(2)
	var caller string
	if ok {
		caller = fmt.Sprintf("%s:%d", filepath.Base(file), line)
	} else {
		caller = "unknown"
	}

	// 格式化消息
	message := fmt.Sprintf(format, args...)

	// 构建日志行
	logLine := fmt.Sprintf("[%s] %s [%s] %s%s\n",
		time.Now().Format(l.timeFormat),
		level.String(),
		caller,
		l.prefix,
		message,
	)

	l.output.Write([]byte(logLine))
}

// Debug 记录调试信息
func (l *Logger) Debug(format string, args ...interface{}) {
	l.log(DEBUG, format, args...)
}

// Info 记录信息
func (l *Logger) Info(format string, args ...interface{}) {
	l.log(INFO, format, args...)
}

// Warn 记录警告
func (l *Logger) Warn(format string, args ...interface{}) {
	l.log(WARN, format, args...)
}

// Error 记录错误
func (l *Logger) Error(format string, args ...interface{}) {
	l.log(ERROR, format, args...)
}

// Fatal 记录致命错误并退出
func (l *Logger) Fatal(format string, args ...interface{}) {
	l.log(FATAL, format, args...)
	os.Exit(1)
}

// 全局日志记录器
var (
	defaultLogger *Logger
	once          sync.Once
)

// InitDefault 初始化默认日志记录器
func InitDefault(level Level, filename string) error {
	var err error
	once.Do(func() {
		if filename == "" {
			defaultLogger = New(level, os.Stdout)
		} else {
			defaultLogger, err = NewFileLogger(level, filename)
		}
	})
	return err
}

// GetDefault 获取默认日志记录器
func GetDefault() *Logger {
	if defaultLogger == nil {
		defaultLogger = New(INFO, os.Stdout)
	}
	return defaultLogger
}

// 全局便捷方法
func Debug(format string, args ...interface{}) {
	GetDefault().Debug(format, args...)
}

func Info(format string, args ...interface{}) {
	GetDefault().Info(format, args...)
}

func Warn(format string, args ...interface{}) {
	GetDefault().Warn(format, args...)
}

func Error(format string, args ...interface{}) {
	GetDefault().Error(format, args...)
}

func Fatal(format string, args ...interface{}) {
	GetDefault().Fatal(format, args...)
}

// SetLevel 设置全局日志级别
func SetLevel(level Level) {
	GetDefault().SetLevel(level)
}

// ReplaceStdLogger 替换标准库的log
func ReplaceStdLogger() {
	log.SetOutput(&stdLogWriter{logger: GetDefault()})
	log.SetFlags(0) // 清除标准log的格式，使用我们自己的格式
}

// stdLogWriter 标准库log的适配器
type stdLogWriter struct {
	logger *Logger
}

func (w *stdLogWriter) Write(p []byte) (n int, err error) {
	w.logger.Info(string(p))
	return len(p), nil
}