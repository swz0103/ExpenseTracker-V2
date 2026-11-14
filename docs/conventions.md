# 撰寫規範

> 改程式、加功能、寫測試、寫文件、提交與發版的規則。照這份做，測試會擋下大部分偏離的地方；擋不下的寫在「靠人守」。

## 一、加一個功能的步驟

| 步驟 | 做什麼 | 規則來源 |
| --- | --- | --- |
| 1 | 決定放哪：屬於某個功能就放 `features/<功能>/`，所有功能都要用的才放 `core/` | [architecture.md](architecture.md#app-內部分層) |
| 2 | 資料與規則寫在 `model/`（不碰畫面），表單寫在 `compose/`，頁面寫在 `ui/` | `layers_test` |
| 3 | 純計算（不需要帳本狀態）放 `packages/domain`，App 只呼叫 | [architecture.md](architecture.md#模組) |
| 4 | 新頁面：在 `core/nav.dart` 加一個 `Place`，`app/shell.dart` 對應頁面；一次性的整頁工作（排序、匯入）用 `openFlow` | `layers_test` |
| 5 | 畫面只用設計系統：`Hue`、`TextSize`、`solidButton`／`wordButton`、kit 元件 | [design.md](design.md)、`design_rules_test` |
| 6 | 頁面加進 `test/app/places.dart`，版面、無障礙、截圖就會涵蓋它 | — |
| 7 | 寫測試（見第三節），跑全部測試 | — |
| 8 | 更新文件（見第四節）、版號與 `whats_new.txt`（見第五節） | — |

## 二、程式

### 放哪裡

- 依賴只能往下：`app/` → `features/` → `core/` → 套件（`packages/`、`infrastructure/`）。
- 功能可以用別的功能的 `model/` 與 `compose/`（例如開它的表單），不能用它的 `ui/`；功能之間不能互相需要。需要同一個東西的兩個功能，把它搬到 `core/`。
- `core/` 分六部分，各自只能用表上允許的部分（[architecture.md](architecture.md#core-的六個部分)）。
- 搬檔案用 `python3 tool/move.py 舊路徑=新路徑`（在 `apps/expense_tracker` 下執行），它會改好所有 import。

### 檔案長度

- 一個檔案 600 行以內（`layers_test` 檢查）。例外只有產生的 `glyphs.dart` 與帳本狀態 `ledger.dart`（800）。
- 快超過時依主題拆：`python3 tool/split.py <檔案>` 把後段的宣告搬到同一個 library 的 `part` 檔，再把檔名改成看得懂的名字。單一類別太長時，把一組方法搬到同檔 library 的 `extension`（例：`composer_pickers.dart`）。

### 命名與註解

- 檔名小寫底線，名稱說明內容（`loan_blocks.dart`），不用 `_2`、`utils`、`helpers`。
- 公開的類別、函式都有 `///` 文件註解，用英文寫「它是什麼、什麼時候用」；畫面上的中文字直接寫在註解裡對照（例：`/// 定期交易: …`）。
- 註解說「為什麼」，不重述程式在做什麼。
- 畫面文字用繁體中文，短、不重複；同一件事全 App 同一個說法。

### 畫面

- 顏色、字級、按鈕只從 `core/look` 拿，頁面裡不寫色碼、字級數字、`styleFrom`（`design_rules_test`）。
- 短標籤用 `OneLine`（放不下先縮到 75%，再放不下以…結尾），不讓它斷成兩行（版面測試檢查 12 字以內的文字）。
- 有標題的頁面用 `HeadedList`，標題固定、內容捲動；內容放得下時不能拖動。
- 動畫 200～300 ms，並尊重系統的「減少動畫」（`MediaQuery.disableAnimationsOf`）。

## 三、測試

| 放哪 | 測什麼 |
| --- | --- |
| `test/core/` | 帳本、規則、共用元件 |
| `test/features/<功能>/` | 該功能的 model、表單、頁面行為 |
| `test/app/` | 跨全 App 的規則：分層、設計系統、版面、無障礙、啟動、備份規則 |
| 各套件的 `test/` | 套件的規則與格式 |

- 修 bug 先寫一個會重現它的測試，確認在舊程式上失敗、修正後通過。
- 流程測試找元件時，優先用 `Key` 或語意標籤；只有在確認畫面文字本身時才用 `find.text`。
- 版面、無障礙、對比測試自動涵蓋 `places.dart` 裡的每一頁：新頁面一定要加進去。
- 不跳過、不停用測試來讓 CI 變綠。

## 四、文件

### 每份文件的用途

| 文件 | 寫什麼 | 什麼時候改 |
| --- | --- | --- |
| [README（根目錄）](../README.md) | App 介紹、安裝 | 功能大改時 |
| [product.md](product.md) | App 能做什麼（給使用者看） | 新增或拿掉功能時 |
| [architecture.md](architecture.md) | 模組、分層、資料流、外部來源 | 結構或依賴規則改變時 |
| [design.md](design.md) | 設計系統與畫面規則 | 加 token、元件或畫面規則時 |
| [conventions.md](conventions.md) | 本文件 | 規則改變時 |
| [development.md](development.md) | 開發、測試、CI、發版 | 工具或流程改變時 |
| [android.md](android.md) | Android 端的實作與設定 | 改 Kotlin、權限、Google 設定時 |
| [CHANGELOG.md](CHANGELOG.md) | 每版改了什麼 | 每個版本 |
| [acceptance.md](acceptance.md) | 待實機驗收的項目 | 每個版本；驗收完標記 |
| [roadmap.md](roadmap.md) | 已知限制、刻意不做、待辦 | 發現或解決時 |
| [adr/](adr/) | 重大決策的理由 | 做出新的取捨時加一篇，不改舊的結論 |
| 各模組 README | 模組做什麼、對外入口、不做什麼 | 改模組的公開行為時 |

### 寫法

- 開頭一行 `>` 摘要：這份文件回答什麼問題。
- 一份文件 150 行以內；超過就拆，或把細節留在程式註解。
- 摘要、長度與每個連結都由 `tooling/architecture_checks/test/docs_test.dart` 檢查（ADR 除外）。
- 能用表格就用表格，能用條列就不寫長段落；一段不超過三句。
- 寫現在的狀態，不寫歷史；歷史在 CHANGELOG、ADR 與 git。
- 同一件事只寫在一個地方，其他地方連結過去。
- 提到程式時寫檔名或識別字（`HeadedList`），不貼大段程式碼。

### ADR

- 檔名 `adr/NNNN-主題.md`，內容：狀態與日期、背景、決策、後果。
- 決策改變時加新的 ADR，在舊的狀態列寫「由 ADR-NNNN 取代」，不改寫舊的內容。

## 五、提交與發版

- 版號 `主.次.修`：新畫面或改版升次版號，只修 bug 或不改畫面的整理升修訂號；全部實機驗收通過才到 1.0.0。
- 每個版本：`pubspec.yaml` 版號、`whats_new.txt`（三行以內，給使用者看）、CHANGELOG 一節、acceptance 一節。
- commit 訊息用英文：第一行說做了什麼，空一行後條列重點。
- 一個 PR 一件事（一批回饋或一次整理）；PR 說明列出改了什麼、怎麼驗證。
- 合併到 main 後 CI 自動建置、簽章、發布；App 內更新會讀到新版。
