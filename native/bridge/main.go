package main

/*
#include <stdlib.h>
*/
import "C"
import (
	"duanjuapp/native/core"
	"unsafe"
)

//export DuanjuRequest
func DuanjuRequest(input *C.char) (result *C.char) {
	// FFI 边界的最后一道 panic 防线：core.NativeRequest 自身有 recover，
	// 但边界上的字符串拷贝等操作不在其保护范围内，这里兜底避免 abort 宿主进程。
	defer func() {
		if recover() != nil {
			result = C.CString(`{"ok":false,"error":"本地核心处理失败，请重试"}`)
		}
	}()
	if input == nil {
		return C.CString(`{"ok":false,"error":"请求为空"}`)
	}
	return C.CString(core.NativeRequest(C.GoString(input)))
}

//export DuanjuFree
func DuanjuFree(value *C.char) { C.free(unsafe.Pointer(value)) }

func main() {}
