package config

import (
	"encoding/json"
	"fmt"
	"log"
	"monitor/entity"
	"monitor/utils"
	"os"
	"path/filepath"
	"sync"
	"time"
)

// Manager 配置管理器 - macOS专用
type Manager struct {
	fileName    string
	cache       []entity.StockConfig
	lastModTime time.Time
	mu          sync.RWMutex
}

// NewManager 创建配置管理器
func NewManager(fileName string) *Manager {
	if fileName == "" {
		fileName = utils.ExpandUser("~/.config/StockMonitor.json")
	}

	return &Manager{
		fileName: fileName,
	}
}

// GetStockConfigs 获取股票配置列表
func (m *Manager) GetStockConfigs() []entity.StockConfig {
	m.mu.RLock()

	// 检查文件是否被修改
	if m.needsReload() {
		m.mu.RUnlock()
		m.reload()
		m.mu.RLock()
	}

	result := make([]entity.StockConfig, len(m.cache))
	copy(result, m.cache)
	m.mu.RUnlock()

	return result
}

// needsReload 检查是否需要重新加载
func (m *Manager) needsReload() bool {
	if len(m.cache) == 0 {
		return true
	}

	stat, err := os.Stat(m.fileName)
	if err != nil {
		return false
	}

	return stat.ModTime().After(m.lastModTime)
}

// reload 重新加载配置
func (m *Manager) reload() {
	m.mu.Lock()
	defer m.mu.Unlock()

	configs, modTime, err := m.loadFromFile()
	if err != nil {
		log.Printf("加载配置文件失败: %v", err)
		return
	}

	m.cache = configs
	m.lastModTime = modTime
	log.Printf("配置已重新加载，共 %d 个股票", len(configs))
}

// loadFromFile 从文件加载配置
func (m *Manager) loadFromFile() ([]entity.StockConfig, time.Time, error) {
	var configs []entity.StockConfig
	var modTime time.Time

	// 获取文件修改时间
	stat, err := os.Stat(m.fileName)
	if err != nil {
		if os.IsNotExist(err) {
			return configs, modTime, nil
		}
		return nil, modTime, fmt.Errorf("获取文件状态失败: %w", err)
	}
	modTime = stat.ModTime()

	// 读取文件内容
	data, err := os.ReadFile(m.fileName)
	if err != nil {
		return nil, modTime, fmt.Errorf("读取配置文件失败: %w", err)
	}

	// 解析JSON
	if err := json.Unmarshal(data, &configs); err != nil {
		return nil, modTime, fmt.Errorf("解析配置文件失败: %w", err)
	}

	return configs, modTime, nil
}

// SaveStockConfigs 保存股票配置
func (m *Manager) SaveStockConfigs(configs []entity.StockConfig) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	// 确保目录存在
	if err := m.ensureConfigDir(); err != nil {
		return fmt.Errorf("创建配置目录失败: %w", err)
	}

	// 序列化为JSON
	data, err := json.MarshalIndent(configs, "", "  ")
	if err != nil {
		return fmt.Errorf("序列化配置失败: %w", err)
	}

	// 写入文件
	if err := os.WriteFile(m.fileName, data, 0644); err != nil {
		return fmt.Errorf("写入配置文件失败: %w", err)
	}

	// 更新缓存
	m.cache = make([]entity.StockConfig, len(configs))
	copy(m.cache, configs)

	// 更新修改时间
	if stat, err := os.Stat(m.fileName); err == nil {
		m.lastModTime = stat.ModTime()
	}

	log.Printf("配置已保存，共 %d 个股票", len(configs))
	return nil
}

// ensureConfigDir 确保配置目录存在
func (m *Manager) ensureConfigDir() error {
	dir := filepath.Dir(m.fileName)
	return os.MkdirAll(dir, 0755)
}

// IsConfigRefreshToday 检查配置是否今天已刷新
func (m *Manager) IsConfigRefreshToday() bool {
	stat, err := os.Stat(m.fileName)
	if err != nil {
		return false
	}

	modTime := stat.ModTime()
	now := time.Now()
	return modTime.Year() == now.Year() &&
		modTime.Month() == now.Month() &&
		modTime.Day() == now.Day()
}

// HasEastMoneyAccount 检查是否配置了东财账户
func (m *Manager) HasEastMoneyAccount() bool {
	return os.Getenv("EAST_MONEY_USER") != "" && os.Getenv("STOCK_MONITOR_PYTHON") != ""
}

// GetConfigFileName 获取配置文件名
func (m *Manager) GetConfigFileName() string {
	return m.fileName
}

// AddStock 添加股票
func (m *Manager) AddStock(stock entity.StockConfig) error {
	configs := m.GetStockConfigs()

	// 检查是否已存在
	for _, config := range configs {
		if config.Code == stock.Code {
			return fmt.Errorf("股票 %s 已存在", stock.Code)
		}
	}

	configs = append(configs, stock)
	return m.SaveStockConfigs(configs)
}

// RemoveStock 移除股票
func (m *Manager) RemoveStock(code string) error {
	configs := m.GetStockConfigs()

	var newConfigs []entity.StockConfig
	found := false

	for _, config := range configs {
		if config.Code != code {
			newConfigs = append(newConfigs, config)
		} else {
			found = true
		}
	}

	if !found {
		return fmt.Errorf("股票 %s 不存在", code)
	}

	return m.SaveStockConfigs(newConfigs)
}

// UpdateStock 更新股票配置
func (m *Manager) UpdateStock(code string, updateFunc func(*entity.StockConfig) error) error {
	configs := m.GetStockConfigs()

	found := false
	for i := range configs {
		if configs[i].Code == code {
			if err := updateFunc(&configs[i]); err != nil {
				return err
			}
			found = true
			break
		}
	}

	if !found {
		return fmt.Errorf("股票 %s 不存在", code)
	}

	return m.SaveStockConfigs(configs)
}