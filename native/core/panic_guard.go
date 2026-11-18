package core

import (
	"fmt"
	"os"
	"runtime/debug"
	"time"
)

// guardBackground 在背景 goroutine 入口兜底：任何 panic 只记诊断，不让它把整个宿主进程 abort 掉。
// downloader 为 nil 时退回 stderr。必须放在 goroutine 内 defer 链的最前（最后执行），
// 让 wg.Done / conn.Close 等清理先跑完再回收 panic。
func guardBackground(downloader *Downloader, where string) {
	if r := recover(); r != nil {
		message := fmt.Sprintf("背景任务 %s 发生 panic：%v\n%s", where, r, debug.Stack())
		if downloader != nil {
			downloader.recordDiagnostic(diagnosticEvent{
				Time:    time.Now(),
				Level:   "error",
				Event:   "panic",
				Source:  where,
				Message: message,
			})
			return
		}
		fmt.Fprintln(os.Stderr, message)
	}
}
