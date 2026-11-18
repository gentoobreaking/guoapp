package core

import (
	"context"
	"net/http"
)

// mediaAddressChecker 校验媒体请求的目标地址（来源为模块清单的 host allowlist）。
type mediaAddressChecker func(raw string) error

type MediaAddressCheckerKey struct{}

// withMediaAddressChecker 由 jsProvider 在呼叫 host 的媒体方法（FetchPlaylist /
// PrepareWebMedia / FinishMedia）时注入，让 Downloader 的媒体出口统一执行 allowlist。
func withMediaAddressChecker(ctx context.Context, check mediaAddressChecker) context.Context {
	return context.WithValue(ctx, MediaAddressCheckerKey{}, check)
}

func mediaAddressCheckerFrom(ctx context.Context) mediaAddressChecker {
	check, _ := ctx.Value(MediaAddressCheckerKey{}).(mediaAddressChecker)
	return check
}

// checkedMediaClient 限制媒体请求的重定向目标仍在模块 allowlist 内。
func checkedMediaClient(client *http.Client, check mediaAddressChecker) *http.Client {
	scoped := *client
	previous := scoped.CheckRedirect
	scoped.CheckRedirect = func(request *http.Request, via []*http.Request) error {
		if previous != nil {
			if err := previous(request, via); err != nil {
				return err
			}
		}
		return check(request.URL.String())
	}
	return &scoped
}
