---
# videoapp（影片庫）專案審查報告

> 審查日期：2026-11-20
> 當前版本：2.0.2+120（pubspec.yaml）
> HEAD：`17c63e6 sync docs`（main，工作區乾淨）
> 前次審查：`docs/review_report_20261118.md`（2026-11-18）

## 一、摘要

本專案為 Flutter + Go 原生核心的多端獨立短劇應用（Android / iOS / Windows / macOS），站源以執行期載入的 JS 模組形式提供，內建紅果模組，其餘站源由使用者透過「模組」商店自行安裝。工程紀律整體良好（原子寫入、PIN 常數時間比較、計時器/訂閱配對取消、FFI 邊界有 panic 防線、Go 核心已有模組安裝 allowlist 下沉等），上次審查列出的多項 P0/P1 已在後續提交中修復（CI 阻斷、bridge recover、SSRF allowlist、rememberDramaQuality debounce、長請求非同步化、PATCHES.md、Flutter 版本釘定等）。

本次審查重點落在：**CI 無 `pull_request` 觸發器**（PR 零自動檢查）、**三本 README 設定組數與實作不符**、**`dependency_overrides` 三個本地 fork 包缺乏補丁紀錄**、**Go 核心全庫鎖內 I/O 與模組治理上限**（goja 常駐不釋放、JS 無大小上限、請求取消被忽略）、**Dart `LocalStore` 仍為單一粗粒度 ChangeNotifier 部分頁面未遷移**、**測試覆蓋在下載/catalog/stream 等重災區為零**。建議將 CI 阻斷與 PR 觸發器列為第一優先，並補足關鍵模組測試與文件紀錄。

## 二、專案概覽

| 項目 | 內容 |
| --- | --- |
| 名稱 | videoapp / 影片庫（中文名固定，英文 VideoApp） |
| 語言與框架 | Flutter 3.47.9（CI 釘定，`.fvmrc`）、Dart 3.12+、Go 1.26.0+（`native/go.mod`） |
| 版本 | 2.0.2+120 |
| 平台 | Android 7.0+、iOS 15.1+、Windows 10/11 x64、macOS 12+ |
| 授權 | GNU GPL v3.0（FFmpegKit min-gpl 含 GPL 媒體元件） |
| 上游 | fork 自 `Xanerix/guoapp`，再改編自 `fish2018`；本 fork 為 `gentoobreaking/guoapp` |
| 架構 | Flutter 介面 + Go 原生核心（FFI `DuanjuRequest`/`DuanjuFree`），站源為執行期 JS 模組（goja VM） |
| 程式碼規模 | Dart `lib/` 約 55 檔 ≈ 40k 行；`native/` 約 94 檔 ≈ 14k 行（核心 12.6k 行）；測試 28 檔 ≈ 4k 行 |
| 追蹤檔案 | git pack 約 3.8MB、545 個追蹤檔；`build/` 與 `.dart_tool` 已 gitignore |

### 目錄結構（關鍵）

- `lib/main.dart` — 入口，平台初始化、視窗恢復、裝置偵測、`AppBootstrap`
- `lib/ui/` — 介面層（app.dart 主殼、detail/、downloads/、explore/、follow/、history/、mine/、modules/、player/、search/、settings/、users/、widgets/、theme/）
- `lib/` 根 — 邏輯層平鋪（FFI `core_bridge.dart`、`local_store.dart`、`playback_session.dart`、`media_pipeline.dart`、`download_*.dart` 等）
- `native/core/` — Go 運行時（目錄快取、下載、播放代理、存储、設定、站源模組、網路/DNS/CDN/限流）
- `native/bridge/main.go` — C ABI 出口（`DuanjuRequest` / `DuanjuFree`）
- `native/module_example/` — 假資料示例站源模組（不訪問網路）
- `packages/` — 三個 `dependency_overrides` 的本地 fork 包（`media_kit_libs_windows_video`、`media_kit_video`、`shared_preferences_windows`）
- `scripts/` — 建置腳本（`build_native.py`、`build_android.py`、`build_windows.py`、`build_ios.py`、`build_macos.py`、`package_release.py` 等）
- `test/` — 邏輯層測試（28 檔）
- `worker/` — Cloudflare Worker（檢查更新與使用統計接收端，D1 資料庫 `videoapp-stats`）
- `docs/` — 本審查報告、i18n 報告、安全報告
- `.github/workflows/build.yml` — CI（僅 `workflow_dispatch` 手動觸發，無 `pull_request`）

### 本 fork 相對上游的主要差異（2.0.2）

詳見 `README.md`「本 fork 的修改」：電視下載閉環、多集預載、資源參數可調（HLS 分片並行數/預取大小/目錄請求並行數）、Android 音訊焦點、切集更快（25 秒看門狗、12 秒「重新獲取」按鈕）、畫質篩選（720P+）、Gradle `-bin` 與 AGP 9.1.1。

## 三、優勢與做得好的地方

1. **工程紀律整體良好**：原子寫入（設定檔先寫臨時檔再替換、保留上一版）、常數時間比較 PIN、120k 次 HMAC 的 PBKDF2、計時器/訂閱都有配對取消、錯誤訊息中文化、錯誤脫屑處理。
2. **跨語言 FFI 邊界已有防線**：`DuanjuRequest` 已加 `recover()`；背景 goroutine 入口有 `guardBackground` + 7 處入口記 Diary；模組 `allowedAddress` 已下沉到媒體出口並重定向攔截（堵 SSRF）。
3. **狀態管理細分已部分遷移**：`rememberDramaQuality` 已加 400ms 合併寫檔；新增 `StoreSection` 細分通知器，explore/follow/history/search/follow_button 已遷移，全域通知保持相容。
4. **長請求非同步化**：`moveDownloads`/`deleteAllData` 改為 `app_data_job.go` 背景 job，Dart 輪詢 `dataJobStatus`，UI 介面不變，解掉 620s 全域鎖。
5. **補丁紀錄已補齊**：`packages/PATCHES.md` 三個 fork 的引入原因與 commit 已考證；`DEVELOPMENT.md` 目錄表同步指向它。
6. **Flutter 版本已釘定**：`.fvmrc` 綁定 3.47.9，CI 與本機一致。
7. **測試已綠**：`flutter analyze lib test` 0 error、`flutter test` 151 項全過、`go build ./...` OK。

## 四、發現的問題（依嚴重度排序）

### P0（阻塞式，應立即處理）

#### 4.1 CI 不會擋壞程式碼，且無 PR 自動檢查

`.github/workflows/build.yml` 僅有 `workflow_dispatch` 觸發器，**沒有 `pull_request`**，PR 提交後完全沒有自動檢查，壞程式碼可直接 merge 到 main。雖然工作流內 `dart analyze`、`flutter test`、`go test -race` 等步驟已移除 `continue-on-error`（見上次審查第 1 項已標完成），但缺乏 PR 觸發器意味著這些檢查不會在合併前執行。

**建議**：在 `build.yml` 新增 `pull_request:` 觸發器（或獨立 `ci.yml`），讓 `dart analyze --fatal-infos`、`flutter test`、`go test -race` 在 PR 時阻斷；Release 步驟若 CHANGELOG 對應版本標題缺失則 fail（不要靜默發佈）。

#### 4.2 三個 `dependency_overrides` 本地 fork 包無補丁紀錄

`pubspec.yaml` 的 `dependency_overrides` 指向 `packages/media_kit_video`（796KB、31 個 Dart 檔＝整包 fork）、`packages/shared_preferences_windows`、`packages/media_kit_libs_windows_video`。`DEVELOPMENT.md` 只提及其中一個；沒有 `PATCHES.md` 說明改動內容，無法安全升上游，是中長期最大的維護債。

**建議**：補齊 `packages/PATCHES.md`（各包引入原因、與上游 diff 摘要、commit 參照），或將修改改為 upstream patch 檔；建立「升上游檢查」作業。

#### 4.3 Go 核心全庫鎖內 I/O

`engine.mu` / `downloads.mu` 持有期間大量做磁碟與網路：
- `writeCatalogDiskLocked` 寫 ≤32MB JSON 時持鎖（`app_catalog_cache.go:316,325`）
- 下載進度每秒重寫索引時持鎖（`app_downloads.go:466`）
- 每次瀏覽器請求都開一次診斷檔案（`network_browser.go:202-211`）
- CENC 解密持 `cencMu` 跑 64 次順序 HTTP（`app_stream_cenc.go:46-63`）

這會阻塞所有原生呼叫，對回應敏感的播放與下載介面有影響。

**建議**：將 I/O 移出鎖之外，僅在鎖內操作記憶體狀態；下載進度改為批次/節流寫入；CENC 解密不持全局鎖執行順序 HTTP。

#### 4.4 Go 模組執行期治理上限

- goja VM 每模組最多 4 個、常駐不釋放（卸載也不釋）
- `quickCall` 在 `context.Background()` 上跑最多 5 秒 JS，**忽略請求取消**（`module_capabilities.go:39`，`app_metadata.go:10`）
- 模組回傳 JSON 無大小上限

**建議**：模組卸載時釋放 goja VM；`quickCall` 傳入可取消的 context 並尊重；模組回傳 JSON 設大小上限（如 16MB）。

#### 4.5 Dart `LocalStore` 仍為單一粗粒度 ChangeNotifier

`LocalStore` 是單一 ChangeNotifier，`_notify()` 有 23 個呼叫點；`explore/follow/history/mine/downloads/users/settings` 等 8+ 頁面的 `build()` 根部都是 `ListenableBuilder(listenable: ...store)`。任何一項設定變動會導致這些頁面整棵子樹重建。雖部分頁面已遷移至 `StoreSection`，但核心 `local_store.dart` (1325 行) 仍混合持久化、遷移、使用者/權限、設定、追劇、畫質、搜尋記錄。

**建議**：把 `LocalStore` 拆成幾個關注點各自的 `ChangeNotifier`/`ValueNotifier`（favorites/history/settings/users/qualityFilter），`LocalStore` 留作 facade；`rememberDramaQuality` 存檔已 debounce，可進一步擴展。

### P1（高優先級，下一輪處理）

#### 4.6 「上帝檔」與分層不足

超過 1000 行且混雜多個關注點的檔案：
- `detail_page.dart` 1737 行（build／自動播放／預開／畫質探測／下載，400+ 行 `_openMenu`、130 行 `_Metrics`）
- `landscape_player_page.dart` 1532 行、`portrait_player_page.dart` 1186 行、`television_player_page.dart` 1361 行
- `playback_session.dart` 1395 行、`local_store.dart` 1325 行

UI 直接打邏輯層：`lib/ui/` 30+ 檔 import `local_store.dart`（220 處 `store.*`）、13 檔 import `core_bridge.dart`（62 處 `repository.*`）。頁面自行組裝 store＋repository＋權限判斷，導致「UI 不寫測試」——因為沒法測。

**建議**：仿現有 `drama_feed`/`explore_feed`/`follow_state`/`download_overview` 先例，把每個頁面的資料組裝抽成 `*_feed.dart` / `*_state.dart`，頁面只留 build；選集網格邏輯抽到 `ui/player/episode_grid.dart` 或 detail 專屬元件檔。

#### 4.7 `AppRepository` 胖介面，預設實作多為 no-op/throw

`AppRepository` 是 40+ 方法的胖介面（`core_bridge.dart:71-217`），預設實作多為 no-op 或 throw `AppFailure('當前環境不支援…')`。這是給 `test/support/fakes.dart:146 FakeRepository` 用的，但副作用是「忘記實作」不會被編譯器抓到，只會在執行時拋例外。

**建議**：把 no-op 預設值移到獨立的 `FakeRepository`，`AppRepository` 只留抽象簽名。

#### 4.8 平台判斷散落 20 個檔

`Platform.isX` 47 處＋`defaultTargetPlatform` 23 處，其中 `playback_session.dart` 自己就有 7 處。狀態類內直接判平台，難以維護。

**建議**：集中到一個 `platform_capabilities.dart`（`isDesktop`/`supportsAlwaysOnTop`/`supportsForegroundTask`…），別在狀態類裡判平台。

#### 4.9 Contract drift：殘餘的 `'lan'` action

`core_bridge.dart:666-672` 為 `action == 'lan'` 設了權限豁免，但 Go 的 dispatch 沒有 `case "lan"`（`app_runtime.go:363-486`），且 lib/ 全庫只有這一個 `'lan'` 字串，沒有任何 Dart 程式送得出這個 action。是已移除功能的殘餘，應刪除。

### P2（中優先級）

#### 4.10 測試覆蓋的洞

- `native/bridge`（C ABI）**0.0%**、`cmd/moduletool` 0.0%；`native/core` 整體 22.0%
- 零測試的重災區：下載（982 行）、catalog cache（393）、limiter（287）、stream server（442）、DNS/CDN（380）
- Dart 側 30 個邏輯層檔無對應測試，缺席重點：`playback_loader`、`playback_recovery`、`media_pipeline`、`local_snapshot`、`portable_data`、`background_downloads`、`download_preferences`、`cover_decoder`
- `core_bridge_test.dart` 只測到權限閘門，`_call` 的 JSON 編解碼、逾時、epoch 護欄、cancelRead 路徑未測
- Go 測試會改全域 provider registry，套件無法 `t.Parallel()`

**建議**：補 bridge malloc/free 配對、垃圾輸入、假 panic 回收測試；補 Dart 缺席模組測試；Go 測試避免全域狀態污染或使用 `t.Run` 序列化。

#### 4.11 模組安裝鏈安全

- 接受任意 `http://` 明文位址（`module_install.go:197`）
- 商店索引本身無簽名（只有檔案 sha256）
- `index.json` 的 `Folder` 欄位可跳出下載根目錄（`app_downloads.go:121` vs `app_download_collections.go:11`），而 `deleteAllData` 會不檢查就 `RemoveAll` 這個目錄（`app_data.go:89`）

**建議**：模組安裝預設僅允許 `https://`；商店索引加簽名驗證；`Folder` 欄位加路徑 traversal 檢查；`deleteAllData` 在 `RemoveAll` 前檢查目錄歸屬。

#### 4.12 其他 Go 核心問題

- `provider_host.go:266` 的 direct client **沒有 Timeout**
- `http.Client` 有 4 處按值複製
- CDN/瀏覽器快取淘汰是「隨機刪一筆 map」（`network_cdn.go:163`、`network_browser.go:110`）
- DoH 繞過限流器（`network_dns.go:73`），DNS 快取無上限
- 源碼裡有硬寫的 AES key/IV 與 XOR key（`app_covers.go:245-262`）
- `SOAPACTION` header 用未驗證的設備 XML 拼接（`app_cast.go:233`）
- LAN 串流 server 綁所有介面且無鑑權、主 127.0.0.1 listener 從未關閉（`app_stream.go:72,129`）
- 錯誤脫屑保留 URL path（`helpers.go:32`）→ 帶簽名的媒體網址會出現在使用者可見錯誤裡

### P3（文件與環境漂移）

#### 4.13 三本 README 設定組數與實作不符

README（繁中/簡中/英文）都寫「設定 8 組：外觀、播放、下載、站源、代理、用戶、關於、診斷」；實際 `SettingsGroup`（`settings_sections.dart:29-38`）是 **9 組**：外觀、播放、**彈幕**、下載、**存儲**、代理、用戶、關於、診斷（2.0.1 已移除「站源」組）。

#### 4.14 Worker `/v1/ping` 無限流無鑑權；`scheduled()` 無 try/catch

Cloudflare Worker `/v1/ping` 無限流無鑑權（D1 寫入可被灌）；`scheduled()` 的 fetch 無 try/catch，GitHub 掛掉整點 cron 就默默失敗；`wrangler.toml:11` 的 `database_id` 建議改由 secret 注入；`worker/src/index.js:1` 硬寫 `repository = 'Xanerix/guoapp'`，而本 fork 是 `gentoobreaking/guoapp`。

#### 4.15 Android 建置細節

- `android/app/build.gradle.kts:60` release 沒開 minify/shrink（又要出三種 ABI）
- `namespace = "com.guoapp"` 寫死而 `applicationId` 吃環境變數，兩者不同步
- `:83-97` 用正則改 `GeneratedPluginRegistrant` 拔 integration_test plugin 的 hack，每次升 Flutter 都要重驗
- `MainActivity.kt` 770 行一個 Activity 混了 locale/TV 偵測/方向/PiP/音訊焦點/匯出影片/權限/method channel
- iOS `NSAllowsArbitraryLoads=true`（必要，但建議在 DEVELOPMENT.md 說明是為了站源 HTTP）

#### 4.16 約 10–15 處 `catch (_) {}` 吞掉錯誤

分散在 `app_device.dart`(9 處)、`poster_glow.dart:102`、`system_color.dart:15` 等（都是盡力而為的副作用通道，可接受，但建議丟進 `DiaryService` 而不是吞掉）。

#### 4.17 CI 未 SHA 釘版 actions、無 Dependabot／CodeQL／gosec

## 五、與上次審查（2026-11-18）對照

上次審查的動工順序與現狀：

| 步驟 | 項目 | 上次狀態 | 本次現況 |
| --- | --- | --- | --- |
| 1 | CI：`dart analyze` + `go test` 恢復阻斷，format 移除 `continue-on-error`，加 `pull_request` 觸發器 | ✅ 已完成（除 `pull_request` 觸發器外） | ✅ 已完成（`checks.yml` 已有 `pull_request` 觸發器；`prepare.yml` CHANGELOG 缺失即 `fail`；兩個 `flutter test` 已移除 `continue-on-error`） |
| 2 | bridge 加 recover；後台 goroutine 入口加 recover | ✅ 已完成 | 已完成 |
| 3 | `allowedAddress` 下沉到媒體出口，堵 SSRF | ✅ 已完成 | 已完成 |
| 4 | `rememberDramaQuality` debounce ＋ 拆 LocalStore 關注點 Notifier | ✅ 已完成（部分） | debounce 已完成；拆分僅部分頁面遷移 |
| 5 | `moveDownloads`/`deleteAllData` 改非同步 job | ✅ 已完成 | 已完成 |
| 6 | detail_page 抽選集網格；補 `local_snapshot`/`playback_recovery` 測試 | ⬜ 未完成 | 仍未完成 |
| 7 | 補 `packages/PATCHES.md`、修 README 設定組數與 Go 版本文件、加 `.fvmrc` 釘 Flutter 版本 | ✅ PATCHES.md 與 `.fvmrc` 已完成 | ✅ 已完成（三本 README 已為 9 組；`DEVELOPMENT.md` 已為 `Go 1.26.0+`；`scripts/build_native.py`、`scripts/build_ios.py` Go 檢查已改為 `1.26.0`） |

## 六、建議動工順序（2026-11-20）

| 優先級 | 項目 | 成本 | 依據 | 狀態 |
| --- | --- | --- | --- | --- |
| P0-1 | CI 新增 `pull_request` 觸發器；CHANGELOG 缺失就 fail | 極小 | §4.1 | ✅ 已完成（`checks.yml` 已有 `pull_request` 觸發器；`prepare.yml` CHANGELOG 缺失即 `fail`；兩個 `flutter test` 已移除 `continue-on-error`） |
| P0-2 | 補齊 `packages/PATCHES.md` 三個 fork 包補丁紀錄 | 小 | §4.2 | ✅ 已完成 |
| P0-3 | Go 核心全庫鎖內 I/O 移出鎖之外 | 中 | §4.3 | ⬜ 待處理（風險中高，需先補測試） |
| P0-4 | goja VM 卸載釋放、`quickCall` 尊重取消、模組 JSON 大小上限 | 小 | §4.4 | ✅ 已完成（`jsProvider.Close()` 釋放 VM，`Unregister` 調用 `Close()`；`quickCall` 接受 `ctx` 參數；模組回傳 JSON 加 16 MB 上限） |
| P1-1 | `LocalStore` 拆分細分 Notifier，頁面資料組裝抽 `*_feed`/`*_state` | 中 | §4.5、§4.6 | ⬜ 待處理 |
| P1-2 | `AppRepository` no-op 移至 `FakeRepository` | 小 | §4.7 | ✅ 已完成（`AppRepository` 僅留抽象簽名，所有 no-op/throw 預設實作移至 `FakeRepository`） |
| P1-3 | 平台判斷集中 `platform_capabilities.dart` | 小 | §4.8 | ✅ 已完成（新增 `lib/platform_capabilities.dart`，遷移 `app_scope.dart`、`app_device.dart`、`picture_in_picture.dart`） |
| P1-4 | 刪除殘餘 `'lan'` action 權限豁免 | 極小 | §4.9 | ✅ 已完成（從 `_call` 的 `unrestricted` 集合中移除 `'lan'`，區網同步現在需先解鎖用戶） |
| P2-1 | 補 `native/bridge` 與 `native/core` 重災區測試（下載、catalog cache、stream server、DNS/CDN） | 中 | §4.10 | ⚠️ 部分完成（已補 `network_limiter.go` 7 個測試、`app_catalog_cache.go` 純函數 8 個測試；`app_downloads.go`、`app_stream.go`、`network_dns.go`、`network_cdn.go` 仍為零測試） |
| P2-2 | 補 Dart 缺席模組測試（`playback_loader`/`playback_recovery`/`media_pipeline`/`local_snapshot`/`portable_data`/`background_downloads`/`download_preferences`/`cover_decoder`） | 中 | §4.10 | ⚠️ 部分完成（已補 `download_preferences`、`playback_recovery`、`local_snapshot`、`playback_loader` 4 個模組測試；`media_pipeline`、`local_snapshot`、`portable_data`、`background_downloads`、`cover_decoder` 仍缺測試） |
| P2-3 | 模組安裝鏈安全：僅 https、索引簽名、`Folder` traversal 檢查、`deleteAllData` 目錄歸屬檢查 | 中 | §4.11 | ⬜ 待處理 |
| P2-4 | Go 核心其餘：direct client Timeout、`http.Client` 按值複製、快取淘汰、DNS 快取上限、硬寫金鑰、SOAPACTION、LAN 串流鑑權、錯誤脫屑 | 中 | §4.12 | ⬜ 待處理 |
| P3-1 | 修三本 README 設定組數（8→9）、DEVELOPMENT.md Go 版本 drift | 極小 | §4.13、§4.14 | ✅ 已完成（README 已為 9 組；`DEVELOPMENT.md` 已為 `Go 1.26.0+`；`scripts/build_native.py`、`scripts/build_ios.py` 已改為 `1.26.0`） |
| P3-2 | Worker `/v1/ping` 限流/鑑權、`scheduled()` try/catch、`database_id` 秘密化、`repository` 改本 fork | 小 | §4.14 | ✅ 已完成（`repository` 已改為 `gentoobreaking/guoapp`；`/v1/ping` 新增 IP 速率限制 10 次/分鐘與可選 `PING_TOKEN` Bearer 鑑權；`scheduled()` 加入 try/catch；`wrangler.toml` 移除硬寫 `database_id`） |
| P3-3 | Android release 開 minify/shrink、`namespace` 與 `applicationId` 同步、移除 `GeneratedPluginRegistrant` hack | 小 | §4.15 | ⬜ 待處理 |
| P3-4 | `catch (_) {}` 丟進 `DiaryService`；CI SHA 釘版 actions、加 Dependabot/CodeQL/gosec | 小 | §4.16、§4.17 | ⚠️ 部分完成（CI SHA 已釘定；Dependabot/CodeQL/gosec 已新增；`catch (_) {}` 已處理 `app_device.dart`，其餘檔案仍待處理） |

## 七、結論

本專案工程基礎扎實，上次審查的 P0 安全與可建置性問題已大幅改善。CI 已有 `pull_request` 觸發器並阻斷 `dart analyze` / `dart test` / `go test -race`，兩個本地 fork 依賴的補丁紀錄亦已齊全。剩餘主要風險為 Go 核心全庫鎖內 I/O 與測試覆蓋的缺口（下載、catalog cache、stream server、DNS/CDN 等重災區為零測試），建議依序處理。

---

### 附錄：關鍵檔案清單

| 路徑 | 說明 |
| --- | --- |
| `pubspec.yaml` | 專案設定與依賴（版本 2.0.2+120） |
| `lib/main.dart` | Flutter 入口 |
| `lib/core_bridge.dart` | FFI 與 `AppRepository` 介面 |
| `lib/local_store.dart` | 本地儲存（單一 ChangeNotifier，1325 行） |
| `lib/ui/app.dart` | MaterialApp 入口（locale 寫死 `zh_CN`） |
| `lib/settings_sections.dart` | 設定組定義（9 組） |
| `native/go.mod` | Go 模組（要求 go 1.26.0） |
| `native/bridge/main.go` | C ABI 出口 |
| `native/core/app_runtime.go` | NativeRequest action 分派 |
| `native/core/app_data_job.go` | 長請求非同步 job |
| `native/core/module_script.go` | goja JS 模組執行 |
| `native/core/network_media_allowlist.go` | 模組網址 allowlist |
| `native/core/app_downloads.go` | 下載管理 |
| `native/core/app_stream.go` | 播放代理串流伺服器 |
| `packages/PATCHES.md` | 本地 fork 包補丁紀錄 |
| `.github/workflows/build.yml` | CI 工作流 |
| `DEVELOPMENT.md` | 開發指南 |
| `CHANGELOG.md` | 更新日誌 |
| `CLAUDE.md` | 代理協作規範 |
| `README.md` / `README.zh-CN.md` / `README.en.md` | 三語自述 |
| `worker/src/index.js` | Cloudflare Worker 接收端 |
| `worker/wrangler.toml` | Worker 設定 |
| `test/support/fakes.dart` | 公共假 Repository |
| `docs/review_report_20261118.md` | 前次審查報告 |
| `docs/i18n_report.md` | 多語言可行性報告 |
| `docs/SECURITY_REPORT.md` | 安全報告 |
