package core

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"os"
	"path/filepath"
	"strings"
)

type nativeStorageInfo struct {
	Directory string `json:"directory"`
	Bytes     int64  `json:"bytes"`
	Free      int64  `json:"free"`
	Files     int    `json:"files"`
	Default   bool   `json:"default"`
}

func (engine *nativeEngine) storage() (nativeStorageInfo, error) {
	manager := engine.downloads
	manager.mu.Lock()
	root := manager.root
	manager.mu.Unlock()
	info := nativeStorageInfo{Directory: root, Default: root == engine.defaultDownloads}
	err := filepath.WalkDir(root, func(path string, entry os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if entry.Type()&os.ModeSymlink != 0 {
			return nil
		}
		if !entry.IsDir() {
			if stat, err := entry.Info(); err == nil {
				info.Bytes += stat.Size()
				info.Files++
			}
		}
		return nil
	})
	if err != nil {
		return info, errors.New("无法读取下载目录，请检查存储设备")
	}
	if !nativePathInside(root, engine.cacheDirectory) {
		info.Bytes += engine.cacheBytes()
	}
	info.Free = nativeFreeSpace(root)
	return info, nil
}

func nativeDownloadLocation(directory, fallback string) string {
	var value struct {
		Directory string `json:"directory"`
	}
	location := filepath.Join(directory, "download-location.json")
	body, _ := os.ReadFile(location)
	if json.Unmarshal(body, &value) == nil && filepath.IsAbs(value.Directory) {
		return filepath.Clean(value.Directory)
	}
	legacy := nativeDefaultDownloads(directory)
	if fallback != legacy && nativeDownloadsInUse(legacy) {
		data, _ := json.Marshal(map[string]string{"directory": legacy})
		_ = nativeDownloadWrite(location, data)
		return legacy
	}
	return fallback
}

func nativeDownloadsInUse(root string) bool {
	entries, err := os.ReadDir(root)
	if err != nil {
		return false
	}
	for _, entry := range entries {
		if entry.Name() != "index.json" {
			return true
		}
	}
	body, err := os.ReadFile(filepath.Join(root, "index.json"))
	if os.IsNotExist(err) {
		return false
	}
	var records []json.RawMessage
	return err != nil || json.Unmarshal(body, &records) != nil || len(records) > 0
}

func nativeDefaultDownloads(directory string) string {
	return filepath.Join(directory, "downloads")
}

func nativeCopyTree(ctx context.Context, source, target string) error {
	return filepath.WalkDir(source, func(path string, entry os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if err := ctx.Err(); err != nil {
			return err
		}
		if entry.Type()&os.ModeSymlink != 0 {
			return errors.New("下载目录中包含符号链接，无法迁移")
		}
		relative, err := filepath.Rel(source, path)
		if err != nil {
			return err
		}
		destination := filepath.Join(target, relative)
		if entry.IsDir() {
			return os.MkdirAll(destination, 0700)
		}
		input, err := os.Open(path)
		if err != nil {
			return err
		}
		defer input.Close()
		output, err := os.OpenFile(destination, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
		if err != nil {
			return err
		}
		defer output.Close()
		buffer := make([]byte, 512<<10)
		for {
			if err := ctx.Err(); err != nil {
				return err
			}
			count, readErr := input.Read(buffer)
			if count > 0 {
				written, err := output.Write(buffer[:count])
				if err != nil {
					return err
				}
				if written != count {
					return io.ErrShortWrite
				}
			}
			if readErr == io.EOF {
				break
			}
			if readErr != nil {
				return readErr
			}
		}
		return output.Sync()
	})
}

func nativePathInside(base, path string) bool {
	relative, err := filepath.Rel(base, path)
	return err == nil && relative != ".." && !strings.HasPrefix(relative, ".."+string(os.PathSeparator))
}

func nativePathsOverlap(first, second string) bool {
	return nativePathInside(first, second) || nativePathInside(second, first)
}

func (engine *nativeEngine) workLease(id, command string) (int, error) {
	engine.mu.Lock()
	defer engine.mu.Unlock()
	if engine.work == nil {
		engine.work = map[string]bool{}
	}
	manager := engine.downloads
	manager.mu.Lock()
	defer manager.mu.Unlock()
	if id != "" {
		if id != "storage" && id != "merge" {
			return 0, errors.New("无效的本地任务")
		}
		if command != "start" && command != "end" {
			return 0, errors.New("无效的本地任务操作")
		}
		if command == "start" {
			if engine.work[id] || manager.moving {
				return 0, errors.New("已有本地任务正在运行，请稍后重试")
			}
			if id == "storage" && engine.work["merge"] {
				return 0, errors.New("正在合并视频，请等合并完成后再迁移下载目录")
			}
			if id == "merge" && engine.work["storage"] {
				return 0, errors.New("正在迁移下载目录，请稍后再合并")
			}
			engine.work[id] = true
		} else {
			delete(engine.work, id)
		}
	}
	return len(engine.work) + len(manager.converting), nil
}
