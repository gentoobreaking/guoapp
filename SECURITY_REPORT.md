# 專案安全審計報告

**專案名稱：** videoapp  
**專案路徑：** `~/Projects/tv/videoapp`  
**審計日期：** 2026 年 11 月 20 日  
**審計範圍：** 全部原始程式碼（Dart、Go、JavaScript、Kotlin、Swift、C/C++）  
**審計結果：** **未發現 backdoor、eval 代碼、rootkit 或不明主動聯外程式碼**

---

## 1. 摘要

經過對 `~/Projects/tv/videoapp` 全部原始程式碼的系統性檢查，**未發現任何後門（backdoor）、動態代碼執行（eval/exec）、rootkit、權限提升程式碼，或不明的主動外聯連線**。

該專案為 Flutter/Dart 影音站源應用，搭配 Go 原生核心（`duanju_core`）。所有網路連線均為應用正當功能（站源索引、模組下載、更新檢查、DNS 解析），且皆經過嚴格的大小限制、超時控制、路徑遍歷防護與白名單驗證。

---

## 2. 審計範圍與方法

### 2.1 檢查的程式語言與檔案類型

| 語言 | 檔案副檔名 | 檢查內容 |
|------|-----------|---------|
| Dart | `*.dart` | UI、業務邏輯、本地儲存、媒體管線、更新提示 |
| Go | `*.go` | 原生核心、模組載入、網路傳輸、下載管理、串流伺服器 |
| JavaScript | `*.js` | Cloudflare Worker 更新服務、站源模組範例 |
| Kotlin | `*.kt` | Android 原生橋接（MainActivity、TextInputBridge） |
| Swift | `*.swift` | iOS/macOS 原生橋接（AppDelegate、SceneDelegate） |
| Objective-C | `*.m`, `*.mm` | iOS 原生橋接 |
| C/C++ | `*.c`, `*.cpp`, `*.h` | Windows 原生運行、FFI 邊界 |
| 測試檔案 | `*_test.go`, `*_test.dart` | 單元測試（僅供參考，非生產程式碼） |

排除目錄：`build/`、` .git/`、`.dart_tool/`、`~/Library/`（開發環境殘留檔案）。

### 2.2 掃描惡意特徵

針對以下危險模式進行全文檢索：

- 動態代碼執行：`eval(`、`exec(`、`system(`、`shell_exec(`、`popen(`、`os/exec`、`ProcessBuilder`、`Runtime.getRuntime`、`Process.run`、`Process.start`
- 權限提升與 rootkit：`su`、`root`、`sudo`、`chmod`、`chown`、`setuid`、`setgid`、`/etc/`、`/var/`、`cron`、`launchd`、`systemd`
- 惡意混淆：`base64`、`rot13`、`xor`、`decrypt`、`encrypt`、`AES`、`DES`、`RC4`（作為雜湊/金鑰處理則排除）
- 外聯網路：`http://`、`https://`、`WebSocket`、`fetch(`、`XMLHttpRequest`、`net.Dial`、`net.Listen`
- 硬編碼 IP：`\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}`

---

## 3. 惡意程式碼特徵檢查結果

### 3.1 後門與危險呼叫

| 特徵 | 檢查結果 | 說明 |
|------|---------|------|
| `eval()` / `exec()` / `system()` | ❌ 未發現 | Dart 與 Go 原始碼中無危險動態執行呼叫 |
| `os/exec` / `ProcessBuilder` | ❌ 未發現 | Go 中的 `Command` 僅為內部 JSON 指令分派，非外部命令執行 |
| Dart `Process.run` / `Process.start` | ❌ 未發現 | 無子行程啟動 |
| Kotlin `Runtime.getRuntime().exec()` | ❌ 未發現 | 僅 `Runtime.getRuntime().exit(0)` 用於應用重啟（正常行為） |
| `unsafe.Pointer` / `syscall` | ⚠️ 僅 FFI | Go FFI 字串釋放與 Windows 代理 API，屬正常原生開發 |
| `su` / `root` / `sudo` / `chmod` / `chown` | ❌ 未發現 | 出現的 "root" 僅為 Flutter Navigator 根導覽與目錄術語 |

### 3.2 Rootkit 與持久化行為

| 特徵 | 檢查結果 | 說明 |
|------|---------|------|
| `/etc/`、`/var/`、`/tmp/` 寫入 | ❌ 未發現 | 無系統層級檔案操作 |
| `cron` / `launchd` / `systemd` | ❌ 未發現 | 無定時任務或服務持久化 |
| `setuid` / `setgid` | ❌ 未發現 | 無權限提升 |
| 隱藏檔案/目錄操作 | ❌ 未發現 | 無 rootkit 隱藏行為 |

### 3.3 惡意混淆與加密

| 特徵 | 檢查結果 | 說明 |
|------|---------|------|
| base64 / hex 編碼 | ⚠️ 合法使用 | 僅用於媒體金鑰、圖片資料、檔案指紋、安裝令牌、站源加密工具（非混淆） |
| AES / ECDH / HKDF / MD5 / SHA256 | ⚠️ 合法使用 | 給 JS 站源使用的加密 API（`aesCbcEncrypt`、`ecdhP256`、`hkdfSha256` 等），屬站源功能工具 |
| 動態代碼簽名驗證 | ✅ 存在 | 模組安裝前驗證 SHA256 雜湊，防止篡改 |

---

## 4. 主動聯外連線清單

所有外聯連線皆為應用正當功能，無不明後門連線。

| 用途 | 地址 / 來源 | 性質 | 說明 |
|------|------------|------|------|
| 站源模組索引 | `https://raw.githubusercontent.com/guoapp-modules/index/main/index.json` | 正當 | 獲取可安裝的 JS 站源模組列表 |
| 模組文件下載 | `https://cdn.jsdelivr.net/gh/guoapp-modules/...` | 正當 | 下載站源模組 ZIP 安裝包 |
| 更新檢查 | `nativeUpdateServer`（編譯時注入，原始碼為空） | 正當（可選） | `/v1/latest`、`/v1/ping`；僅當安裝包配置更新伺服器後才啟用，目前原始碼中為空字串，功能停用 |
| 使用統計回報 | `nativeUpdateServer`（同上） | 正當（可選） | 回報安裝 ID、版本、平台、建構編號 |
| DoH DNS 解析 | `https://dns.alidns.com/resolve`、`https://dns.google/resolve` | 正當 | 備用 DNS-over-HTTPS，僅用於解析站源域名 |
| GitHub API | `https://api.github.com/repos/Xanerix/guoapp/releases/latest` | 正當 | Cloudflare Worker 定期檢查 Release 以更新版本資訊 |
| 作者鏈接 | `https://github.com/fish2018` | 正當 | UI 中的作者專案鏈接，僅供顯示 |
| 青空次元站源 | `https://www.sorani.net/` | 正當 | CLAUDE.md 允許的站源之一，登入與驗證碼功能 |

### 4.1 Dart 層 `Uri.parse` 使用

| 檔案 | 行號 | 內容 | 性質 |
|------|------|------|------|
| `lib/ui/update_prompt.dart` | 130 | `Uri.parse(url)` | 正當，用戶輸入的更新 URL |
| `lib/ui/settings/sorani_account_view.dart` | 176 | `Uri.parse(_soraniSite)` | 正當，青空次元官網 |
| `lib/ui/settings/settings_sections.dart` | 620 | `Uri.parse(url)` | 正當，用戶輸入的代理 URL |

### 4.2 硬編碼 IP 檢查

全部 IP 僅為本地地址，無外聯硬編碼 IP：

- `127.0.0.1`、`localhost`、`::1`：本地串流伺服器、本地播放、代理繞過
- `192.168.x.x`：僅出現在測試檔案（`app_cast_test.go`），模擬局域網投屏設備
- `239.255.255.250`：SSDP 多播位址，用於局域網投屏設備發現
- `0.0.0.0/8`、`100.64.0.0/10`、`192.0.0.0/24` 等：僅出現在 `network_dns_addresses.go` 作為私有/保留位址範圍過濾

---

## 5. JS 模組站源沙箱安全機制

應用本身**不內置站源**，站源是運行時加載的 JavaScript 模組。安全機制如下：

| 機制 | 說明 |
|------|------|
| **goja 沙箱** | JS 模組運行在 Go 的 goja JavaScript 引擎中，無法直接存取檔案系統、網路或原生 API |
| **Host API 白名單** | JS 僅能調用暴露的 host 物件成員（`fetch`、`fetchText`、`parseUrl`、`aesCbcDecrypt` 等），無 `eval`、`Function`、`require`、`process`、`fs` 等危險 API |
| **網域白名單** | `fetch` 僅能訪問模組 `manifest.json` 中聲明的 `hosts` 域名，其他網域會被拒絕 |
| **模組大小限制** | `main.js` 最大 4 MB，安裝包最大 8 MB，manifest 最大 64 KB |
| **執行超時** | 單次模組呼叫最長 60 秒，快速操作 5 秒，海報修復 15 秒 |
| **SHA256 驗證** | 模組安裝前驗證 manifest 與 entry 的 SHA256 雜湊，防止篡改 |
| **睡眠限制** | `sleep` 最長 1 分鐘，防止阻塞 |
| **快取限制** | 模組快取最多 512 條，單條最大 1 MB，防止記憶體耗盡 |
| **HTML 解析限制** | `parseHtml` 輸入最大 8 MB |

---

## 6. 防禦機制（反證無惡意意圖）

代碼中大量存在安全防禦機制，進一步證明無後門意圖：

| 防禦機制 | 實作位置 | 說明 |
|---------|---------|------|
| HTTP 響應大小限制 | `provider_host.go`、`app_download_transfer.go` | 預設 4 MB、播放列表 4 MB、manifest 64 KB、模組包 8 MB |
| 請求超時控制 | `app_runtime.go`、`network_dns.go` | 45 秒主請求、8 秒背景、4 秒 DNS、15 秒海報修復、6 秒 SSDP |
| 重定向次數限制 | `app_runtime.go`、`provider_host.go` | 最多 10 次，跨域重定向會清除預覽令牌標頭 |
| 路徑遍歷防護 | `app_storage.go`、`provider_host.go` | `nativePathInside` 檢查、`filepath.Base` 檢查、禁止符號連結 |
| 下載任務數量限制 | `app_downloads.go` | 最多 5000 條下載記錄 |
| 並發限制 | `network_limiter.go` | 目錄最多 3 併發、下載段最多 8 併發 |
| 診斷日誌輪替 | `diagnostics.go` | 5 MB 單一檔案上限，最多 2 個備份，單條 5 KB 限制 |
| 訪問控制 | `core_bridge.dart`、`app_settings.go` | 管理員權限、用戶鎖定、來源權限、PIN 驗證（HMAC-SHA256） |
| 安全寫入 | `app_downloads.go`、`local_files.dart` | 暫存檔 + 重命名（atomic write），避免損毀 |
| TLS 最低版本 | `app_runtime.go` | `tls.VersionTLS12`，禁止較弱 TLS 版本 |
| 媒體協議白名單 | `playback_session.dart` | `protocol_whitelist=[http,https,tcp,tls,crypto,data,file]`，本地播放僅 `[file,crypto,data]` |

---

## 7. 發現項目說明（非威脅）

以下項目在掃描中出現，經確認均為正常應用行為，非威脅：

| 項目 | 檔案 | 說明 |
|------|------|------|
| `Runtime.getRuntime().exit(0)` | `android/.../MainActivity.kt:148` | 應用重啟時結束行程，正常行為 |
| `net.Dial` / `net.Listen` | `app_stream.go`、`app_cast.go` | 本地串流伺服器（127.0.0.1）與局域網投屏發現 |
| `base64` / `hex` / `AES` | `module_host.go`、`app_covers.go` 等 | 站源加密工具、媒體金鑰、圖片資料、檔案指紋 |
| `WebSocket` 關鍵字 | 無匹配 | 未發現 WebSocket 使用 |
| `new Function(` / `setTimeout` / `setInterval` | 無匹配 | Worker JS 中未使用 |

---

## 8. 建議

雖然原始碼層面未發現威脅，為了進一步強化安全，建議：

1. **防火牆限制**：在用戶端防火牆中僅允許該應用連線必要的域名（GitHub、Cloudflare、DoH 端點、站源聲明的域名）。
2. **謹慎安裝站源**：僅安裝信任的 JS 站源模組，因為站源可在其聲明的域名白名單內發出網路請求。
3. **關閉更新檢查**：`nativeUpdateServer` 目前原始碼為空，功能已停用；如編譯時注入了實際伺服器，建議確認其來源可信。
4. **定期審計站源**：站源模組是運行時動態載入的，建議定期檢查已安裝模組的來源與程式碼。
5. **編譯產物審計**：`build/` 目錄中的編譯產物（`.so`、`.aar`、`.jar`）未在本次原始碼審計範圍內，如需進一步確認建議對二進位檔案進行病毒掃描與靜態分析。

---

## 9. 審計檔案統計

| 類別 | 檔案數量 |
|------|---------|
| Dart 原始碼 | 約 130 個 |
| Go 原始碼 | 約 60 個 |
| JavaScript | 2 個 |
| Kotlin | 2 個 |
| Swift / Objective-C | 約 10 個 |
| C/C++ / 標頭檔 | 約 20 個 |
| 測試檔案 | 約 30 個 |
| 排除目錄 | `build/`、`.git/`、`.dart_tool/`、`~/Library/` |

---

## 10. 結論

**`~/Projects/tv/videoapp` 未發現 backdoor、eval 代碼、rootkit 或不明主動聯外程式碼。** 該專案為一個具備站源沙箱機制的影音應用，所有網路連線皆為正當功能，並配備完整的防禦機制（大小限制、超時控制、路徑防護、白名單驗證、SHA256 模組驗證等）。

原始碼層面安全，可放心使用。如需對編譯後的二進位檔案或特定站源模組進行額外審計，請另行提出。

---

*本報告僅針對原始程式碼進行靜態審計，不包含動態執行行為監測或網路流量分析。*