package metrics

import (
	"runtime"
	"sync"
	"time"
)

// Metrics 性能指标收集器
type Metrics struct {
	mu sync.RWMutex

	// API调用统计
	ApiCallCount    int64
	ApiSuccessCount int64
	ApiErrorCount   int64
	ApiTotalTime    time.Duration

	// 内存统计
	MemStats runtime.MemStats

	// 更新统计
	UpdateCount     int64
	LastUpdateTime  time.Time
	UpdateErrors    int64

	// 缓存统计
	CacheHits   int64
	CacheMisses int64

	startTime time.Time
}

// NewMetrics 创建性能指标收集器
func NewMetrics() *Metrics {
	return &Metrics{
		startTime: time.Now(),
	}
}

// RecordApiCall 记录API调用
func (m *Metrics) RecordApiCall(duration time.Duration, success bool) {
	m.mu.Lock()
	defer m.mu.Unlock()

	m.ApiCallCount++
	m.ApiTotalTime += duration

	if success {
		m.ApiSuccessCount++
	} else {
		m.ApiErrorCount++
	}
}

// RecordUpdate 记录更新操作
func (m *Metrics) RecordUpdate(success bool) {
	m.mu.Lock()
	defer m.mu.Unlock()

	m.UpdateCount++
	m.LastUpdateTime = time.Now()

	if !success {
		m.UpdateErrors++
	}
}

// RecordCacheHit 记录缓存命中
func (m *Metrics) RecordCacheHit() {
	m.mu.Lock()
	m.CacheHits++
	m.mu.Unlock()
}

// RecordCacheMiss 记录缓存未命中
func (m *Metrics) RecordCacheMiss() {
	m.mu.Lock()
	m.CacheMisses++
	m.mu.Unlock()
}

// UpdateMemStats 更新内存统计
func (m *Metrics) UpdateMemStats() {
	m.mu.Lock()
	runtime.ReadMemStats(&m.MemStats)
	m.mu.Unlock()
}

// GetSnapshot 获取指标快照
func (m *Metrics) GetSnapshot() MetricsSnapshot {
	m.mu.RLock()
	defer m.mu.RUnlock()

	// 更新内存统计
	runtime.ReadMemStats(&m.MemStats)

	return MetricsSnapshot{
		Uptime:          time.Since(m.startTime),
		ApiCallCount:    m.ApiCallCount,
		ApiSuccessCount: m.ApiSuccessCount,
		ApiErrorCount:   m.ApiErrorCount,
		ApiSuccessRate:  m.calculateSuccessRate(),
		AvgApiTime:      m.calculateAvgApiTime(),
		UpdateCount:     m.UpdateCount,
		LastUpdateTime:  m.LastUpdateTime,
		UpdateErrors:    m.UpdateErrors,
		CacheHits:       m.CacheHits,
		CacheMisses:     m.CacheMisses,
		CacheHitRate:    m.calculateCacheHitRate(),
		MemoryUsage:     m.MemStats.Alloc,
		TotalAlloc:      m.MemStats.TotalAlloc,
		GCCount:         m.MemStats.NumGC,
		Goroutines:      runtime.NumGoroutine(),
	}
}

// calculateSuccessRate 计算API成功率
func (m *Metrics) calculateSuccessRate() float64 {
	if m.ApiCallCount == 0 {
		return 0
	}
	return float64(m.ApiSuccessCount) / float64(m.ApiCallCount) * 100
}

// calculateAvgApiTime 计算平均API响应时间
func (m *Metrics) calculateAvgApiTime() time.Duration {
	if m.ApiCallCount == 0 {
		return 0
	}
	return m.ApiTotalTime / time.Duration(m.ApiCallCount)
}

// calculateCacheHitRate 计算缓存命中率
func (m *Metrics) calculateCacheHitRate() float64 {
	total := m.CacheHits + m.CacheMisses
	if total == 0 {
		return 0
	}
	return float64(m.CacheHits) / float64(total) * 100
}

// MetricsSnapshot 指标快照
type MetricsSnapshot struct {
	Uptime          time.Duration `json:"uptime"`
	ApiCallCount    int64         `json:"api_call_count"`
	ApiSuccessCount int64         `json:"api_success_count"`
	ApiErrorCount   int64         `json:"api_error_count"`
	ApiSuccessRate  float64       `json:"api_success_rate"`
	AvgApiTime      time.Duration `json:"avg_api_time"`
	UpdateCount     int64         `json:"update_count"`
	LastUpdateTime  time.Time     `json:"last_update_time"`
	UpdateErrors    int64         `json:"update_errors"`
	CacheHits       int64         `json:"cache_hits"`
	CacheMisses     int64         `json:"cache_misses"`
	CacheHitRate    float64       `json:"cache_hit_rate"`
	MemoryUsage     uint64        `json:"memory_usage"`
	TotalAlloc      uint64        `json:"total_alloc"`
	GCCount         uint32        `json:"gc_count"`
	Goroutines      int           `json:"goroutines"`
}

// 全局指标收集器
var GlobalMetrics = NewMetrics()

// 便捷函数
func RecordApiCall(duration time.Duration, success bool) {
	GlobalMetrics.RecordApiCall(duration, success)
}

func RecordUpdate(success bool) {
	GlobalMetrics.RecordUpdate(success)
}

func RecordCacheHit() {
	GlobalMetrics.RecordCacheHit()
}

func RecordCacheMiss() {
	GlobalMetrics.RecordCacheMiss()
}

func GetSnapshot() MetricsSnapshot {
	return GlobalMetrics.GetSnapshot()
}