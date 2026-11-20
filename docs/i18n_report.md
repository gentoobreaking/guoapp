---

# App 介面語系選項（繁中／簡中／英文）可行性報告

> 2026-11-18。目標：在 設定 中新增介面語言選項——繁體中文／簡體中文／English。
> 本報告只做評估與設計，未動工。

## 一、現況盤點（數字已實測）

- App **沒有任何 i18n 基礎設施**：`MaterialApp`（`lib/ui/app.dart:214`）寫死 `locale: Locale('zh', 'CN')`、`supportedLocales: [Locale('zh', 'CN')]`（`:219-220`）。
- `pubspec.yaml:12` 已有 `flutter_localizations`（SDK 自帶，未啟用 delegates）。
- App 自有中文字串 **約 2,386 處、散落在 85 個 Dart 檔**（UI 標籤、提示、選單、列舉文案全為硬編碼簡中）。直寫 `Text('中文…')` 有 155 處，其餘多在 `SnackBar`、`StatusView(message:)`、設定列、列舉對照表（如 `_decoders`、`_proxyModes`）等。
- **Go 側 69 個檔**的錯誤訊息為中文，經 FFI 直接成為使用者可見文案（`app_runtime.go` dispatch、各 `app_*.go`）；`lib/core_bridge.dart` 的 `_call` 統一把它們變成 `AppFailure`。
- `DiaryService.add`、日記檢視、`MainActivity.kt`（locale 處理）也各有少量中文。

## 二、硬限制（決定整個方案形狀）

**Flutter 沒有全域字串轉換鉤子。** `LocalizationsDelegate` 只影響框架層字串（tooltip、日期選擇器、無障礙標籤）；App 自己的字串是建構子裡的字面值，任何 delegate 都碰不到。因此：

- 想讓**全部**介面隨語言切換，唯一乾淨的辦法是把每個字串路由過一個 helper／ARB——沒有繞過這一步的捷徑。
- 「簡→繁」是**確定性字元映射**（可程式化自動完成）；「英文」是**真正的翻譯**（2,386 條，無法自動生成，只能人工）。

## 三、方案比較

| 方案 | 內容 | 成本 | 達成效果 |
| --- | --- | --- | --- |
| **A. 骨架先行** | 語言設定＋locale 接線＋框架層字串隨語言切＋FFI／Diary 咽喉點簡→繁轉換 | 小（1 輪內） | 繁中／英文覆蓋**框架層與原生錯誤訊息**；App 自有介面仍簡中 |
| **B. 全量 i18n** | ~2,386 字串遷 ARB／`gen_l10n`；繁中以 OpenCC 字表自動生成初稿＋人工校對；英文人工翻譯；Go 訊息過轉換層 | 大（多輪；有 const 回歸風險，見第五節） | 三語完整 |
| **C. 繁中先行** | 機械掃描把 UI 字串包進 `T()` helper；繁中靠字表執行期轉換全域生效；英文暫緩 | 中大（1–2 輪） | 繁中完整；英文選項暫不上 |
| **D. 源碼直接轉繁中** | 不做語言選項；OpenCC（s2twp）一次性轉換 `lib/`＋`native/`＋`test/` 的中文字面值與註釋（~2,400 處 UI 字串＋69 個 Go 檔），App 定格為繁中專屬 | 小（約半輪：轉換分鐘級＋稽核 key 型字面值＋跑測試） | 全部介面與原生錯誤訊息即為繁中；**無選項、不可切換** |

### 方案 D 的稽核要點（唯一真功夫）

轉換時必須把「**與外部資料比對的字面值**」加入白名單保持簡體，否則匹配破裂。已初查到的實例：

- `app_runtime.go:232`、`app_catalog_cache.go:256`：`case "短剧", "真人剧"…` 比對**站源模組回傳的分類名**（外部資料是簡體）→ 保持簡體，或改為對傳入值先做歸一化
- `lib/catalog_sort.dart:52`、`lib/hongguo_series.dart:80`：`character == '百'` 解析**劇名中的中文數字** → 保持簡體
- `lib/models.dart:222`：`fresh.title == '短剧'` 比對**站源標題** → 保持簡體
- 反例（可放心轉）：`message.contains('安全驗證')` 這類比對自家 Go 錯誤訊息——Dart 與 Go 用同一轉換工具即仍匹配

### 方案 D 的取捨

App 定格為繁中專屬：日後若再加「語言選項」，簡中變成逆向翻譯目標，工程量大於方案 B/C。適合使用者群確定為繁中、且無回供簡中選項計畫的 fork。

## 四、建議架構（若採 B 或 C，技術設計如下）

### 4.1 語言設定（共用）

- `LocalStore` settings 新增 key `language`：`system`（預設）／`zh_Hant`／`zh_CN`／`en`。
- `app.dart`：`locale:` 由 store 讀出（`system` 時為 null，交給 `localeResolutionCallback`）；`supportedLocales: [zh_CN, zh_Hant, en]`；加 `GlobalMaterialLocalizations.delegate`、`GlobalWidgetsLocalizations.delegate`、`GlobalCupertinoLocalizations.delegate`——框架層字串（含繁正體 `zh_Hant`）即刻正確切換。
- 設定頁新組「語言」或放「外觀」內；切換立即生效（`settingsUpdates` 通知器已就位，第 4 步的產物直接複用）。

### 4.2 繁中：字級轉換 + 小詞表

- 實作 `zh_convert.dart`：OpenCC `s2twp`（台灣正體）風格——字級映射表＋少量詞級修正（`鼠标→滑鼠`、`視頻→影片`、`軟件→軟體`、`屏幕→螢幕`、`網絡→網路`…本 app 高頻詞預估 ~60 條）。
- 表驅動、可離線、無外部依賴；轉換只發生在 locale 為 `zh_Hant` 時（`zh_CN`／`en` 直接原樣返回，零成本）。

### 4.3 字串路由 helper（C／B 的核心）

```dart
// UI 側：能保 const 的場景用 widget 形式，其餘用函式
class T extends StatelessWidget {  // const T('追剧') 取代 const Text('追剧')
  const T(this.text, {super.key, this.style, ...});
}
String t(String text) => ...;      // SnackBar、列舉對照表等
```

- **繁中**：`t()`／`T` 內部調 `zh_convert`，全域生效，無需翻譯資源。
- **英文**：`t()` 先查 ARB 對照表，查無則回落簡中——所以英文要完整就必須做完 ARB 遷移（方案 B 的主體工作量）。

### 4.4 Go 錯誤訊息（中央咽喉點已存在）

- `_call`（`core_bridge.dart:710-750`）是**所有** Go 訊息進 UI 的唯一通道：在此對 `response['error']` 做 `zh_convert` 即可覆蓋 69 個 Go 檔的全部中文訊息，**Go 端零改動**。
- `DiaryService.add` 同理（日記簡繁轉換）。
- 英文模式下的 Go 訊息：維持簡中顯示（原生訊息英文化是另一個專案量級，建議記錄為已知限制）。

## 五、風險與注意事項

1. **const 回歸**：~155 處 `const Text(...)` 改 `const T(...)` 可保 const；但包進 `t()` 的呼叫點會失 const。重建成本集中在列表網格——已有 `StoreSection` 細分通知器兜底，風險可控。
2. **測試斷言**：`flutter test` 151 項有部分斷言比對中文文案，繁中轉換需保證 `zh_CN` 行為完全不變（轉換只在 `zh_Hant` 生效）。
3. **字表正確性**：字級映射有少數一對多（`干→乾/幹`），需詞級修正表兜底；上線前用主要頁面截圖人工過一遍。
4. **Android/iOS 系統語言**：`MainActivity.kt` 已有 locale 處理，`system` 模式需與其對齊（Flutter `localeResolutionCallback` 以 supportedLocales 匹配即可，原生側不需改）。
5. **英文的長尾**：除字串外，日期格式、數字、彈幕樣式文字等走 `intl`；英文模式是長期維護負擔（每次新增功能都要補翻譯）。

## 六、建議動工順序

| 步驟 | 項目 | 成本 | 效果 |
| --- | --- | --- | --- |
| 1 | 語言設定＋locale 接線＋三個 delegates（方案 A 骨架） | 小 | 框架層字串三語正確；選項出現在設定 |
| 2 | `zh_convert` 字表＋詞表＋單元測試（含 `干` 一對多用例） | 小 | 繁中轉換基礎就緒 |
| 3 | `_call`／`DiaryService` 咽喉點轉換 | 极小 | **原生錯誤訊息繁中生效**（覆蓋 69 個 Go 檔） |
| 4 | （C 路線）機械掃描包 `T()`／`t()`，分批：設定頁 → 主框架 → 探索/追劇/歷史 → 播放器 → 下載 | 中大（1–2 輪） | 繁中全域生效 |
| 5 | （B 路線）ARB 遷移＋英文人工翻譯，按第 4 步同樣分批 | 大（多輪） | 英文完整 |

## 七、結論

- **最小可用組合 = 步驟 1+2+3**：設定裡出現語言選項，框架層與全部原生錯誤訊息即時三語（繁中精確、英文框架層正確），成本約一個小輪次。
- **繁中全域生效**（步驟 4）是純機械工作，可分頁分批，風險低。
- **英文完整**（步驟 5）是 2,386 條的人工翻譯與長期維護承諾，建議等繁中落地後再評估優先級；若英文不是近期剛需，選項可先以「跟隨系統／繁中／簡中」上線，英文後補。

需要我從步驟 1 開始動工的話說一聲即可。
