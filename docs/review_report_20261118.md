---

# guoapp Review 報告

> **2026-11-18 現況複核**：本報告寫作後程式碼已有變動——原第一節的「切集凍結幀」WIP 已在 commit `9fd9ca6`（回退雙播放器交接，恢復單播放器淡出淡入過場）整包回退。實測當前 HEAD：`flutter analyze lib test` 0 error、`flutter test` 151 項全過、`go build ./...` OK。第一節已改寫為反映現狀，其餘各節主張已逐條抽驗、全部屬實。

規模：Dart `lib/` 130 檔 ≈40k 行；Go `native/` 87 檔 ≈14k 行（其中核心 12.6k 行）；測試 Dart 28 檔 4k 行、Go 10 檔 1.4k 行。專案整體工程紀律其實相當好（原子寫入、常數時間比較 PIN、120k 次 HMAC 的 PBKDF2、計時器/訂閱都有配對取消、錯誤訊息中文化），問題集中在下面幾處。

## 一、CI 不會擋壞程式碼（原 P0「編譯不過」已由回退解決）

> **現況更新（2026-11-18）**：原報告的 P0 是「未提交的切集凍結幀 WIP 造成 7 個 compile error」。該 WIP 已在 commit `9fd9ca6` **整包回退**，改用單播放器淡出淡入過場；全庫已無 `transitionFrame` / `transitionSize` / `_clearTransitionFrame`，`player_surface.dart`、`television_player_page.dart` 的相關呼叫點一併消失。實測：`flutter analyze lib test` → **0 error**（exit 0，僅剩 76 條 SDK 3.50.0 對 `package:flutter/material.dart` 的棄用雜訊，見第七節第 7 點）、`flutter test` → **151 項全過**、`go build ./...` → OK。原「補完凍結幀 WIP」的動工項作廢。
>
> 附帶：`detail_page.dart` 曾疑因 diff 移除 `if (plan == null) return;` 而讓 `rememberDramaQuality` 在 plan 為空時誤跑。現況 `repository.resolve` 回傳非可空 `Future<PlaybackPlan>`（`core_bridge.dart:215`），plan 為空會以例外被 `_probeQuality` 外層 `catch (_) {}` 接住，不會誤記畫質；該改動已隨 WIP 提交，風險解除。

**但破窗的根源還在**：這個狀態當初之所以沒被擋下，是因為 `.github/workflows/build.yml:41-52` 把 `dart format`、`dart analyze --fatal-infos`、`flutter test`、`go test -race` **全部標了 `continue-on-error: true`**。就算壞程式碼被 commit + 手動触发工作流，四平台安裝包照樣出、Release 照樣建。第 45 行註解只為「測試不阻塞」辯護，但 analyze／format 也一起不擋了（format 明明已加 `--set-exit-if-changed`，卻被 continue-on-error 抵銷）。建議至少讓 `dart analyze` 與 `go test` 恢復阻斷，format 維持 `--set-exit-if-changed` 並移除其 continue-on-error；另外工作流只有 `workflow_dispatch`、**沒有 `pull_request` 觸發器**，PR 完全沒有自動檢查。

配套（複核後仍成立）：
- `_settleSwitch()`（`playback_session.dart:955-969`）目前仍是 30×80ms 輪詢等「新集播出」，建議改成監聽 `stream.playing` ＋ Completer，順便避免與 `_switching` 競態。

順帶：`prepare` job 只驗 tag／Release 重複；Release 步驟從 CHANGELOG 擷取版本小節，標題不符時 `changes` 為空就**靜默發佈、不帶更新說明**（`:302-312`），建議改為找不到標題就 fail。

## 二、P0：跨語言整合層有兩個真洞（都已在原始碼驗證）

1. **FFI 邊界沒有 panic 防線**：`native/bridge/main.go:12-21` 的 `DuanjuRequest` 沒有 `defer recover()`。唯一防線是 `core.NativeRequest` 自己的 recover（`app_runtime.go:286-291`），它只保護**呼叫它的那條 goroutine**——下載 worker（`app_downloads.go:453`）、封面抓取（`app_covers.go:140`）、串流 server（`app_stream.go:78,129`）、SSDP（`app_cast.go:99,190`）這些背景 goroutine 一旦 panic 就是直接 abort host process（Flutter／iOS app 閃退）。`native/bridge` 目前 **0 行測試**。建議：`DuanjuRequest` 加 recover，並對每個 `go func` 的入口加 recover＋記 Diary。
2. **模組 host allowlist 可繞過 → SSRF**：`allowedAddress` 全庫只有 4 個檢查點（`module_script.go:486` fetchText、`:491` mirrors 過濾、`:501` fetch、`module_host.go:80` reserve），而 `fetchPlaylist`（`:479-484`）、`prepareWebMedia`（`:413-416`）、`finishMedia` **完全沒檢查**，直通 `provider_host.go:114-119` → `network_media.go:70-100`（只驗 `IsProviderHTTPMediaURL`、不走限流器）。這在「第三方 JS 模組執行時載入」的威脅模型下是最實質的一個洞：模組可讓 app 對任意 http(s)（內網、`169.254.169.254`）發請求。建議把 `allowedAddress` 下沉到 `provider_host` 的媒體出口，一次擋全部。

同層還有：**Dart 的 `_call` 為 `moveDownloads`/`deleteAllData` 給 620s 逾時**（`core_bridge.dart:725`），而 Go 這兩個Action 真的會持 `engine.mu` 全域鎖跑完整目錄複製（`app_data.go:68-97`、`app_storage.go:147-239`）→ 這十分鐘裡所有原生呼叫全部塞住。建議這兩項改為非同步 job ＋ 進度查詢，別用同步長請求；另 `nativeState.Lock()` 裡做模組載入（`app_runtime.go:325-333`）也會序列化啟動期的其他請求。

## 三、P1：Dart 狀態管理——全域粗粒度 Notifier

這是 Dart 側最值得改的一項，且是純利基（不改行為也能感受得到）：

- `LocalStore` 是**單一 ChangeNotifier**，`_notify()` 有 23 個呼叫點；而 `explore/follow/history/mine/downloads/users/settings` 等 8+ 個頁面的 `build()` 根部就是 `ListenableBuilder(listenable: ...store)`（`explore_page.dart:135`、`follow_page.dart:135`、`history_page.dart:132`、`mine_page.dart:43`、`downloads_page.dart:134`、`settings_page.dart:250`…）。任何一項設定變動 → 這些頁面**整棵子樹重建**。
- 特別糟的是 `rememberDramaQuality`（`local_store.dart:412`）：每次開詳情頁、每次播放都會跑，不只 `_notify()`，還把**整張 dramaQualities map 重寫磁碟**（`_saveDramaQualities`），而且沒有 debounce。連續開 10 個詳情頁 = 10 次全量寫檔 + 10 次全頁重建（TV 上是 10 列選集網格等級的重建量）。
- 建議：把 `LocalStore` 拆成幾個關注點各自的 `ChangeNotifier`／`ValueNotifier`（favorites / history / settings / users / qualityFilter），`LocalStore` 留作 facade；`rememberDramaQuality` 的存檔加 300–500ms 合併。
- 對照組：播放器的做法是對的——`PlaybackSession` 不為 position 發通知，`PlayerSurface` 自己訂 `stream.position` 只在控制列可見時 `setState`（`player_surface.dart:108-121`），dispose 也完整取消。這套模式可以複製到 store。

## 四、P1/P2：分層與上帝檔

- **UI 直接打邏輯層**：`lib/ui/` 有 30+ 檔 import `local_store.dart`（共 220 處 `store.*` 呼叫）、13 檔 import `core_bridge.dart`（62 處 `repository.*`）。DEVELOPMENT.md 寫「邏輯層平鋪在 lib/」，實際上頁面自己組裝 store＋repository＋權限判斷。後果就是 CLAUDE.md 的「UI 不寫測試」——因為沒法測。低成本起步：把每個頁面的資料組裝抽成 `*_feed.dart` / `*_state.dart`（專案裡已有 `drama_feed`、`explore_feed`、`follow_state`、`download_overview` 這些先例），頁面只留 build。
- **上帝檔**（都 >1000 行，且混了多個關注點）：
  - `detail_page.dart` 1737 行：`_DetailPageState` 混合 build／自動播放／預開／畫質探測／下載，還有 400+ 行的 `_openMenu`（`:1322` 起）與 130 行的 `_Metrics`（`:26-159`）。選集網格邏輯應抽到 `ui/player/episode_grid.dart`（已存在）或 detail 專屬元件檔。
  - `landscape_player_page.dart` 1532 行、`portrait_player_page.dart` 1186、`television_player_page.dart` 1361：三個頁面共享元件做得不錯（`player_surface`/`player_video`/`episode_grid`/`playback_sheets`/`swipe_controls` 都有抽），重複的是手勢/面板/旋轉/控制列顯隱邏輯，可考慮共用 controller。
  - `playback_session.dart` 1395 行、`local_store.dart` 1325 行：後者單檔案混合了持久化、遷移、使用者/權限、設定、追劇、畫質、搜尋記錄。
- **`AppRepository` 是 40+ 方法的胖介面，且預設實作都是 no-op/throw**（`core_bridge.dart:71-217`）。這是刻意給 `test/support/fakes.dart:146 FakeRepository` 用的（我已確認），但副作用是「忘記實作」不會被編譯器抓到，只會在執行時拋「當前環境不支援…」。建議把 no-op 預設值移到獨立的 `FakeRepository`，`AppRepository` 只留抽象簽名。
- **平台判斷散落 20 個檔**：`Platform.isX` 47 處＋`defaultTargetPlatform` 23 處，其中 `playback_session.dart` 自己就有 7 處。建議集中到一個 `platform_capabilities.dart`（`isDesktop`/`supportsAlwaysOnTop`/`supportsForegroundTask`…），別在狀態類裡判平台。
- 順帶發現的 contract drift：`core_bridge.dart:666-672` 為 `action == 'lan'` 設了權限豁免，但 **Go 的 dispatch 沒有 `case "lan"`**（`app_runtime.go:363-486` 已逐條列出），且 lib/ 全庫只有這一個 `'lan'` 字串——沒有任何 Dart 程式送得出這個 action。是已移除功能的残留，刪掉即可。

## 五、P2：Go 核心（subagent 深讀 + 我抽驗）

除第二節的兩個 P0 外，高優先級的是：

1. **全庫鎖內 I/O**：`engine.mu`／`downloads.mu` 持有期間大量做磁碟與網路——`writeCatalogDiskLocked` 寫 ≤32MB JSON 時持鎖（`app_catalog_cache.go:316,325`）、下載進度每秒重寫索引時持鎖（`app_downloads.go:466`）、每次瀏覽器請求都開一次診斷檔案（`network_browser.go:202-211`）、CENC 解密持 `cencMu` 跑 64 次順序 HTTP（`app_stream_cenc.go:46-63`）。
2. **Timeout/連線管理**：`provider_host.go:266` 的 direct client **沒有 Timeout**；`http.Client` 有 4 處按值複製；CDN/瀏覽器快取淘汰是「隨機刪一筆 map」（`network_cdn.go:163`、`network_browser.go:110`）；DoH 繞過限流器（`network_dns.go:73`），DNS 快取無上限。
3. **模組執行期治理**：goja VM 每模組最多 4 個、常駐不釋放（卸載也不釋）；`quickCall` 在 `context.Background()` 上跑最多 5 秒 JS，**忽略請求取消**（`module_capabilities.go:39`，`app_metadata.go:10` 等著它）；模組回傳 JSON 無大小上限。
4. **模組安裝鏈**：接受任意 `http://` 明文位址（`module_install.go:197`）；商店索引本身無簽名（只有檔案 sha256）；`index.json` 的 `Folder` 欄位可跳出下載根目錄（`app_downloads.go:121` vs `app_download_collections.go:11`），而 `deleteAllData` 會不檢查就 `RemoveAll` 這個目錄（`app_data.go:89`）。
5. **其他**：源碼裡有硬寫的 AES key/IV 與 XOR key（`app_covers.go:245-262`）；`SOAPACTION` header 用未驗證的設備 XML 拼接（`app_cast.go:233`）；LAN 串流 server 綁所有介面且無鑑權、主 127.0.0.1 listener 從未關閉（`app_stream.go:72,129`）；錯誤脫屑保留 URL path（`helpers.go:32`）→ 帶簽名的媒體網址會出現在使用者可見錯誤裡。

## 六、P2：測試覆蓋的洞（數字是我實測的）

- `native/bridge`（C ABI）**0.0%**、`cmd/moduletool` 0.0%；`native/core` 整體 22.0%。零測試的重災區：下載（982 行）、catalog cache（393）、limiter（287）、stream server（442）、DNS/CDN（380）。橋接層建議至少測 malloc/free 配對、垃圾輸入、假 panic 回收。
- Dart 側 30 個邏輯層檔無對應測試，不該漏的是 `playback_loader`、`playback_recovery`、`media_pipeline`、`local_snapshot`、`portable_data`、`background_downloads`、`download_preferences`、`cover_decoder`。以你自己訂的「只測資料相容、權限、邏輯層」標準，`local_snapshot`／`portable_data`／`playback_recovery` 是缺席重點。
- `core_bridge_test.dart` 目前只測到權限閘門（在 FFI 之前就拋），`_call` 的 JSON 編解碼、逾時、epoch 護欄、cancelRead 路徑都沒測到。
- 另外 Go 測試會改全域 provider registry，套件無法 `t.Parallel()`（`module_script_test.go:398`）。

## 七、P2/P3：文件與環境漂移（都已對照實作）

1. `DEVELOPMENT.md:5` 寫 Go `1.24.1+`，但 `native/go.mod:3` 要求 **`go 1.26.0`**——照文件裝 1.24/1.25 直接起不來。
2. 三份 README 都寫「設定 8 組：外觀、播放、下載、站源、代理、用戶、關於、診斷」；實際 `SettingsGroup`（`settings_sections.dart:29-38`）是 **9 組**：外觀、播放、**彈幕**、下載、**存儲**、代理、用戶、關於、診斷（2.0.1 已移除「站源」組）。
3. `worker/src/index.js:1` 硬寫 `repository = 'Xanerix/guoapp'`，而本 fork 是 `gentoobreaking/guoapp`。Go 端 `app_update.go:147` 會校驗發布頁必須以 `{PROJECT_URL}/releases/` 開頭——fork 若把 `UPDATE_SERVER_URL` 指向這個 Worker 且 `PROJECT_URL` 設成本 fork，**每次檢查更新都會報「發布頁不屬於本项目」**。建議 repo 名改 wrangler var；`wrangler.toml:11` 的 `database_id` 也建議改由 secret 注入。
4. Worker `/v1/ping` 無限流無鑑權（D1 寫入可被灌）；`scheduled()` 的 fetch 無 try/catch，GitHub 掛掉整點 cron 就默默失敗。
5. **三個 `dependency_overrides` 沒有任何紀錄**：`packages/media_kit_video`（796KB、31 個 dart 檔＝整包 fork）、`shared_preferences_windows`、`media_kit_libs_windows_video`。DEVELOPMENT.md 只提了其中一個。沒有 PATCHES 檔案說明改了什麼，就沒辦法安全升上游——這是中長期最大的維護債，建議補一份 `packages/*/PATCHES.md`（甚至改成 upstream patch 檔）。
6. `CLAUDE.md` 裡的 `../guoapp-sources`、`../guoapp-modules` 在本機不存在（`~/Projects/tv/` 只有 `guoapp`）；`scripts/tv_remote.ps1`、`resize_window.ps1` 完全沒文件。
7. Flutter 版本沒釘檔：CI 釘 3.47.9、本機 3.50.0 → 本機 analyze 多出 76 條雜訊（全是 SDK 把 `package:flutter/material.dart` 標成棄用、指向 SDK 裡根本不存在的 `material_ui`，我確認過 `packages/` 下沒有該 package）。加 `.fvmrc` 釘死，否則真實錯誤會被埋掉。

## 八、P3：其他

- `android/app/build.gradle.kts:60` release 沒開 minify/shrink（又要出三種 ABI）；`namespace = "com.guoapp"` 寫死而 `applicationId` 吃環境變數，兩者不同步；`:83-97` 用正則改 `GeneratedPluginRegistrant` 拔 integration_test plugin 的 hack，每次升 Flutter 都要重驗。
- iOS `NSAllowsArbitraryLoads=true`（必要，但建議在 DEVELOPMENT.md 說明是為了站源 HTTP）。
- `MainActivity.kt` 770 行一個 Activity 混了 locale/TV 偵測/方向/PiP/音訊焦點/匯出影片/權限/method channel；`android/.../GeneratedPluginRegistrant.java` 是提交進库的產物。
- 約 10–15 處 `catch (_) {}` 分散在 `app_device.dart`(9 處)、`poster_glow.dart:102`、`system_color.dart:15` 等（都是盡力而為的副作用通道，可接受，但建議丟進 `DiaryService` 而不是吞掉）。
- 靜態可變狀態：`AppDevice._deviceHandlers`、`CoreBridge._coverPaths`(有 2000 上限，OK)、`DiaryService._entries`(500 上限，OK)、`PictureInPicture.instance`（**它 addDeviceHandler 後從不 remove**，`playback_session.dart:1363` 有對照組；程序級 singleton 所以實務無害）。
- 本機磁碟：`build/` 3.2GB、`.dart_tool` 275MB（都已 gitignore，repo 本身很乾淨：git pack 3.8MB、545 個追蹤檔）。
- CI 未 SHA 釘版 actions、無 Dependabot／CodeQL／gosec。

## 建議動工順序（2026-11-18 依現況重排）

> 原第 1 步「補完凍結幀 WIP」已作廢（WIP 已回退，程式碼已回綠）。**CI 阻斷升為第一優先**——這次編譯不過的狀態能存活到被 review 發現，正是因為 CI 不擋。

| 步骤 | 項目 | 成本 | 狀態 |
| --- | --- | --- | --- |
| 1 | CI：`dart analyze` + `go test` 恢復阻斷，format 移除 `continue-on-error`，加 `pull_request` 觸發器，CHANGELOG 缺失就 fail | 极小 | ✅ 已完成（2026-11-18，待首次 CI 驗證） |
| 2 | bridge 加 recover；後台 goroutine 入口加 recover | 小 | ✅ 已完成（`guardBackground` ＋ 7 處入口、`DuanjuRequest` recover） |
| 3 | `allowedAddress` 下沉到媒體出口，堵 SSRF | 小 | ✅ 已完成（ctx 注入 `doMediaRequestWithClient` ＋ 重定向攔截，含 2 個新測試） |
| 4 | `rememberDramaQuality` debounce ＋ 拆 LocalStore 關注點 Notifier | 中 | ✅ 已完成（400ms 合併寫檔＋重建；新增 `StoreSection` 細分通知器，explore/follow/history/search/follow_button 已遷移，全局通知保持相容） |
| 5 | `moveDownloads`/`deleteAllData` 改非同步 job（解掉 620s 全域鎖） | 中 | ✅ 已完成（`app_data_job.go`：同步段只做校驗即回傳，重 I/O 在背景 goroutine＋`guardBackground`，Dart 輪詢 `dataJobStatus`；UI 介面不變） |
| 6 | detail_page 抽選集網格；補 `local_snapshot`/`playback_recovery` 測試 | 中 | |
| 7 | 補 `packages/PATCHES.md`、修 README 設定組數與 Go 版本文件、加 `.fvmrc` 釘 Flutter 版本 | 极小 | ✅ 已完成（PATCHES.md 三個 fork 的引入原因與 commit 都已考證；DEVELOPMENT.md 目錄表同步指向它） |

需要我動手的話，從第 1 步（CI 阻斷）開始最安全——它讓後面每一項都有防回歸的底線。要我做哪幾項？
