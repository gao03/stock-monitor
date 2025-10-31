package pool

import (
	"monitor/entity"
	"sync"
)

// StockPool 股票对象池
type StockPool struct {
	pool sync.Pool
}

// NewStockPool 创建股票对象池
func NewStockPool() *StockPool {
	return &StockPool{
		pool: sync.Pool{
			New: func() interface{} {
				return &entity.Stock{}
			},
		},
	}
}

// Get 获取股票对象
func (p *StockPool) Get() *entity.Stock {
	return p.pool.Get().(*entity.Stock)
}

// Put 归还股票对象
func (p *StockPool) Put(stock *entity.Stock) {
	// 重置对象状态
	stock.Code = ""
	stock.CurrentInfo = entity.StockCurrentInfo{}
	stock.Config = entity.StockConfig{}
	stock.MenuItem = nil

	p.pool.Put(stock)
}

// StringPool 字符串切片池
type StringPool struct {
	pool sync.Pool
}

// NewStringPool 创建字符串切片池
func NewStringPool() *StringPool {
	return &StringPool{
		pool: sync.Pool{
			New: func() interface{} {
				return make([]string, 0, 10) // 预分配10个容量
			},
		},
	}
}

// Get 获取字符串切片
func (p *StringPool) Get() []string {
	return p.pool.Get().([]string)
}

// Put 归还字符串切片
func (p *StringPool) Put(slice []string) {
	// 重置切片但保留容量
	slice = slice[:0]
	p.pool.Put(slice)
}

// BytePool 字节切片池
type BytePool struct {
	pool sync.Pool
}

// NewBytePool 创建字节切片池
func NewBytePool(size int) *BytePool {
	return &BytePool{
		pool: sync.Pool{
			New: func() interface{} {
				return make([]byte, 0, size)
			},
		},
	}
}

// Get 获取字节切片
func (p *BytePool) Get() []byte {
	return p.pool.Get().([]byte)
}

// Put 归还字节切片
func (p *BytePool) Put(buf []byte) {
	// 重置切片但保留容量
	buf = buf[:0]
	p.pool.Put(buf)
}

// 全局对象池实例
var (
	GlobalStockPool  = NewStockPool()
	GlobalStringPool = NewStringPool()
	GlobalBytePool   = NewBytePool(1024) // 1KB缓冲区
)