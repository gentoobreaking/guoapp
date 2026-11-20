package core

import (
	"context"
	"net/http"
	"net/url"
	"sync"
	"testing"
	"time"
)

func newLimiterTestRequest(method, host string) *http.Request {
	u := &url.URL{Scheme: "https", Host: host, Path: "/test"}
	req, err := http.NewRequest(method, u.String(), nil)
	if err != nil {
		panic(err)
	}
	return req
}

func newLimiterTestResponse(statusCode int) *http.Response {
	return &http.Response{
		StatusCode: statusCode,
		Header:     make(http.Header),
		Request:    newLimiterTestRequest("GET", "example.invalid"),
		Body:       http.NoBody,
	}
}

func TestRequestLimiterAcquireRelease(t *testing.T) {
	ctx := context.Background()
	limiter := newRequestLimiter(10, 0)

	req := newLimiterTestRequest("GET", "example.invalid")

	release, err := limiter.acquire(ctx, req)
	if err != nil {
		t.Fatalf("acquire 失敗：%v", err)
	}
	release()
}

func TestRequestLimiterConcurrencyLimit(t *testing.T) {
	ctx := context.Background()
	limiter := newRequestLimiter(2, 0)

	var active int
	var maxActive int
	var mu sync.Mutex

	var wg sync.WaitGroup
	for i := 0; i < 10; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			req := newLimiterTestRequest("GET", "example.invalid")
			release, err := limiter.acquire(ctx, req)
			if err != nil {
				t.Errorf("acquire 失敗：%v", err)
				return
			}
			mu.Lock()
			active++
			if active > maxActive {
				maxActive = active
			}
			mu.Unlock()
			time.Sleep(10 * time.Millisecond)
			mu.Lock()
			active--
			mu.Unlock()
			release()
		}()
	}
	wg.Wait()

	if maxActive > 2 {
		t.Errorf("並發數超過限制：最大 %d，預期 <= 2", maxActive)
	}
}

func TestRequestLimiterIntervalLimit(t *testing.T) {
	ctx := context.Background()
	interval := 100 * time.Millisecond
	limiter := newRequestLimiter(10, interval)

	req1 := newLimiterTestRequest("GET", "example.invalid")
	release1, err := limiter.acquire(ctx, req1)
	if err != nil {
		t.Fatalf("第一次 acquire 失敗：%v", err)
	}
	release1()

	// 立即再次 acquire 同一個 source，應該需要等待 interval
	req2 := newLimiterTestRequest("GET", "example.invalid")
	start := time.Now()
	release2, err := limiter.acquire(ctx, req2)
	if err != nil {
		t.Fatalf("第二次 acquire 失敗：%v", err)
	}
	elapsed := time.Since(start)
	release2()

	if elapsed < interval {
		t.Errorf("間隔限制未生效：經過 %v，預期 >= %v", elapsed, interval)
	}
}

func TestRequestLimiterBackoffBlocksAcquire(t *testing.T) {
	ctx := context.Background()
	limiter := newRequestLimiter(10, 0)

	req := newLimiterTestRequest("GET", "blocked.example.invalid")
	resp := newLimiterTestResponse(http.StatusForbidden)

	limiter.observeBlock(req, resp)

	// 再次 acquire 同一個 host，應該因為 backoff 而失敗
	req2 := newLimiterTestRequest("GET", "blocked.example.invalid")
	_, err := limiter.acquire(ctx, req2)
	if err == nil {
		t.Fatal("預期 acquire 因為 backoff 而失敗，但沒有錯誤")
	}

	// 不同的 host 應該仍然可以 acquire
	req3 := newLimiterTestRequest("GET", "other.example.invalid")
	release, err := limiter.acquire(ctx, req3)
	if err != nil {
		t.Fatalf("不同 host 應該可以 acquire：%v", err)
	}
	release()
}

func TestRequestLimiterContextCancel(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	limiter := newRequestLimiter(1, 0)

	req1 := newLimiterTestRequest("GET", "example.invalid")
	release1, err := limiter.acquire(ctx, req1)
	if err != nil {
		t.Fatalf("第一次 acquire 失敗：%v", err)
	}

	// 第二個 acquire 應該被阻塞，因為 concurrency=1
	req2 := newLimiterTestRequest("GET", "example.invalid")
	acquireDone := make(chan error, 1)
	go func() {
		_, err := limiter.acquire(ctx, req2)
		acquireDone <- err
	}()

	// 取消 context
	cancel()

	select {
	case err := <-acquireDone:
		if err != context.Canceled {
			t.Fatalf("預期 context.Canceled，得到 %v", err)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("context 取消後 acquire 應該返回錯誤")
	}

	release1()
}

func TestRequestLimiterObserveForbiddenStreak(t *testing.T) {
	ctx := context.Background()
	limiter := newRequestLimiter(10, 0)

	host := "streak.example.invalid"
	for i := 0; i < forbiddenStreakLimit; i++ {
		req := newLimiterTestRequest("GET", host)
		resp := newLimiterTestResponse(http.StatusForbidden)
		limiter.observe(req, resp)
	}

	// 連續 forbiddenStreakLimit 次 403 後，應該觸發 backoff
	req := newLimiterTestRequest("GET", host)
	_, err := limiter.acquire(ctx, req)
	if err == nil {
		t.Fatal("預期 acquire 因為連續 403 而被 backoff 阻擋，但沒有錯誤")
	}
}

func TestRequestLimiterObserveResetsForbiddenStreak(t *testing.T) {
	ctx := context.Background()
	limiter := newRequestLimiter(10, 0)

	host := "reset.example.invalid"
	// 先觸發幾次 403，但不達到極限
	for i := 0; i < forbiddenStreakLimit-1; i++ {
		req := newLimiterTestRequest("GET", host)
		resp := newLimiterTestResponse(http.StatusForbidden)
		limiter.observe(req, resp)
	}

	// 一次成功響應應該重置 streak
	req := newLimiterTestRequest("GET", host)
	resp := newLimiterTestResponse(http.StatusOK)
	limiter.observe(req, resp)

	// 現在應該可以正常 acquire
	release, err := limiter.acquire(ctx, req)
	if err != nil {
		t.Fatalf("成功響應後應該可以 acquire：%v", err)
	}
	release()
}
