package core

import (
	"errors"
	"io/fs"
	"os"
	"path/filepath"
)

func nativeTreeSize(root string) int64 {
	var total int64
	_ = filepath.WalkDir(root, func(_ string, entry fs.DirEntry, err error) error {
		if err != nil || entry.IsDir() || entry.Type()&os.ModeSymlink != 0 {
			return nil
		}
		if info, err := entry.Info(); err == nil {
			total += info.Size()
		}
		return nil
	})
	return total
}

func nativeClearDirectory(directory string) []string {
	entries, err := os.ReadDir(directory)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return []string{directory + "：" + err.Error()}
	}
	var leftover []string
	for _, entry := range entries {
		path := filepath.Join(directory, entry.Name())
		if err := os.RemoveAll(path); err != nil {
			leftover = append(leftover, path+"："+err.Error())
		}
	}
	return leftover
}

func (cache *nativeCoverCache) clear() {
	cache.mu.Lock()
	defer cache.mu.Unlock()
	_ = os.RemoveAll(cache.directory)
	cache.entries = map[string]nativeCoverEntry{}
	cache.size = 0
}

func (engine *nativeEngine) cacheBytes() int64 {
	return nativeTreeSize(engine.cacheDirectory)
}

func (engine *nativeEngine) clearCache() error {
	engine.downloads.mu.Lock()
	root := engine.downloads.root
	engine.downloads.mu.Unlock()
	if nativePathInside(engine.cacheDirectory, engine.directory) || nativePathInside(engine.cacheDirectory, root) {
		return errors.New("缓存目录包含应用数据，无法清理")
	}
	engine.covers.clear()
	if leftover := nativeClearDirectory(engine.cacheDirectory); len(leftover) > 0 {
		return errors.New("部分缓存正在使用，未能全部清理")
	}
	return nil
}
