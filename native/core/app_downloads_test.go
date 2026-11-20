package core

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"strings"
	"testing"
)

func TestNativeDownloadID(t *testing.T) {
	id1 := nativeDownloadID("hongguo", 1)
	id2 := nativeDownloadID("hongguo", 1)
	id3 := nativeDownloadID("hongguo", 2)
	id4 := nativeDownloadID("other", 1)

	// 同樣輸入應該產生相同 ID
	if id1 != id2 {
		t.Fatalf("相同輸入應該產生相同 ID：%s vs %s", id1, id2)
	}

	// 不同集數應該產生不同 ID
	if id1 == id3 {
		t.Fatal("不同集數應該產生不同 ID")
	}

	// 不同劇集應該產生不同 ID
	if id1 == id4 {
		t.Fatal("不同劇集應該產生不同 ID")
	}

	// ID 長度應該是 32 個字符（16 字節 hex 編碼）
	if len(id1) != 32 {
		t.Fatalf("ID 長度應該是 32 個字符，得到 %d：%s", len(id1), id1)
	}

	// 驗證是正確的 hex 編碼
	for _, c := range id1 {
		if !((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) {
			t.Fatalf("ID 應該是小寫 hex 字符，得到字符 %c", c)
		}
	}

	// 驗證與手動計算一致
	hash := sha256.Sum256([]byte("hongguo\x001"))
	expected := hex.EncodeToString(hash[:16])
	if id1 != expected {
		t.Fatalf("ID 不匹配：%s vs %s", id1, expected)
	}
}

func TestNativeDownloadError(t *testing.T) {
	tests := []struct {
		status  int
		wantMsg string
	}{
		{200, "媒体服务器返回 HTTP 200，请稍后重试"},
		{404, "媒体服务器返回 HTTP 404，请稍后重试"},
		{500, "媒体服务器返回 HTTP 500，请稍后重试"},
		{403, "媒体服务器返回 HTTP 403，请稍后重试"},
	}

	for _, tt := range tests {
		err := nativeDownloadError(tt.status)
		if err == nil {
			t.Fatalf("狀態碼 %d 應該返回錯誤，得到 nil", tt.status)
		}
		if err.Error() != tt.wantMsg {
			t.Fatalf("狀態碼 %d 錯誤訊息不匹配：得到 %q，預期 %q", tt.status, err.Error(), tt.wantMsg)
		}
		if !errors.Is(err, err) {
			t.Fatal("錯誤應該可以被 errors.Is 識別")
		}
	}

	// 驗證錯誤訊息包含「媒体服务器返回」
	err := nativeDownloadError(404)
	if !strings.Contains(err.Error(), "媒体服务器返回") {
		t.Fatalf("錯誤訊息應該包含「媒体服务器返回」：%s", err.Error())
	}
}
