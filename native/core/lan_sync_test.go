package core

import (
	"testing"
)

func TestLanSyncStartStopWithoutInterfaceEnumeration(t *testing.T) {
	engine := &nativeEngine{downloader: &Downloader{cfg: Config{dataDir: t.TempDir()}}, directory: t.TempDir()}
	ls := newLanSync(engine)
	if err := ls.start(); err != nil {
		t.Fatalf("start = %v", err)
	}
	if ls.httpServer == nil || ls.discovery == nil || ls.httpPort == 0 {
		t.Fatal("LAN 同步伺服器或探索未啟動")
	}
	ls.stop()
	if ls.httpServer != nil || ls.discovery != nil {
		t.Fatal("stop 後應完全關閉")
	}
}
