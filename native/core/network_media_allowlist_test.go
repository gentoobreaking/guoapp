package core

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestMediaAddressCheckerBlocksRequest(t *testing.T) {
	ctx := withMediaAddressChecker(context.Background(), func(string) error {
		return errors.New("模块清单未声明访问该地址")
	})
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, "http://127.0.0.1:1/playlist.m3u8", nil)
	if err != nil {
		t.Fatal(err)
	}
	downloader := &Downloader{ModuleAllowlistStrict: true}
	if _, err := downloader.doMediaRequestWithClient(request, &http.Client{}); err == nil {
		t.Fatal("allowlist 之外的媒体请求应当被拒绝")
	}
}

func TestMediaAddressCheckerBlocksRedirect(t *testing.T) {
	target := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, _ *http.Request) {
		_, _ = writer.Write([]byte("#EXTM3U\n"))
	}))
	defer target.Close()

	origin := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		http.Redirect(writer, request, target.URL, http.StatusFound)
	}))
	defer origin.Close()

	ctx := withMediaAddressChecker(context.Background(), func(raw string) error {
		if raw == target.URL {
			return errors.New("模块清单未声明访问该地址")
		}
		return nil
	})
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, origin.URL, nil)
	if err != nil {
		t.Fatal(err)
	}
	downloader := &Downloader{client: &http.Client{}, ModuleAllowlistStrict: true}
	if _, err := downloader.doMediaRequest(request); err == nil {
		t.Fatal("重定向到 allowlist 之外的地址应当被拒绝")
	}
}
