package core

import (
	"net/http"
	"net/url"
	"testing"
)

func TestNativeStreamServerLANPlaylist(t *testing.T) {
	stream := &nativeStreamServer{address: "http://192.168.1.100:8080"}

	// 不同 origin，應該替換地址
	request := &http.Request{
		Host: "10.0.0.5:9090",
		URL:  &url.URL{Host: "10.0.0.5:9090"},
	}
	body := "http://192.168.1.100:8080/playlist.m3u8\nhttp://192.168.1.100:8080/segment.ts\n"
	result := stream.lanPlaylist(request, body)
	expected := "http://10.0.0.5:9090/playlist.m3u8\nhttp://10.0.0.5:9090/segment.ts\n"
	if result != expected {
		t.Fatalf("lanPlaylist 替換地址錯誤：\n得到：%s\n預期：%s", result, expected)
	}

	// 相同 origin，不應該替換
	request2 := &http.Request{
		Host: "192.168.1.100:8080",
		URL:  &url.URL{Host: "192.168.1.100:8080"},
	}
	result2 := stream.lanPlaylist(request2, body)
	if result2 != body {
		t.Fatalf("相同 origin 應該保持原樣：\n得到：%s\n預期：%s", result2, body)
	}

	// 空 body
	result3 := stream.lanPlaylist(request, "")
	if result3 != "" {
		t.Fatalf("空 body 應該返回空字符串：%s", result3)
	}

	// 只包含非匹配地址
	body4 := "http://other.example.com/playlist.m3u8\n"
	result4 := stream.lanPlaylist(request, body4)
	if result4 != body4 {
		t.Fatalf("非匹配地址應該保持原樣：\n得到：%s\n預期：%s", result4, body4)
	}
}

func TestNativeStreamServerLANPlaylistMultipleOccurrences(t *testing.T) {
	stream := &nativeStreamServer{address: "http://10.0.0.1:8080"}
	request := &http.Request{
		Host: "192.168.1.50:3000",
		URL:  &url.URL{Host: "192.168.1.50:3000"},
	}

	// 多個相同地址都應該被替換
	body := "http://10.0.0.1:8080/a\nhttp://10.0.0.1:8080/a\nhttp://10.0.0.1:8080/b\n"
	result := stream.lanPlaylist(request, body)
	expected := "http://192.168.1.50:3000/a\nhttp://192.168.1.50:3000/a\nhttp://192.168.1.50:3000/b\n"
	if result != expected {
		t.Fatalf("多個地址替換錯誤：\n得到：%s\n預期：%s", result, expected)
	}
}

func TestNativeStreamServerLANPlaylistWithQueryString(t *testing.T) {
	stream := &nativeStreamServer{address: "http://10.0.0.1:8080"}
	request := &http.Request{
		Host: "192.168.1.50:3000",
		URL:  &url.URL{Host: "192.168.1.50:3000"},
	}

	// 包含查詢字符串的地址
	body := "http://10.0.0.1:8080/playlist.m3u8?token=abc123\n"
	result := stream.lanPlaylist(request, body)
	expected := "http://192.168.1.50:3000/playlist.m3u8?token=abc123\n"
	if result != expected {
		t.Fatalf("查詢字符串替換錯誤：\n得到：%s\n預期：%s", result, expected)
	}
}

func TestNativeDownloadIDConsistency(t *testing.T) {
	// 驗證 nativeDownloadID 與 app_downloads_test.go 一致
	id1 := nativeDownloadID("hongguo", 1)
	id2 := nativeDownloadID("hongguo", 1)
	if id1 != id2 {
		t.Fatal("相同輸入應該產生相同 ID")
	}

	// 驗證長度為 32 個字符
	if len(id1) != 32 {
		t.Fatalf("ID 長度應該是 32 個字符，得到 %d", len(id1))
	}

	// 驗證只有小寫 hex 字符
	for _, c := range id1 {
		if !((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) {
			t.Fatalf("ID 應該是小寫 hex，得到字符 %c", c)
		}
	}
}
