# 撰寫規範

> 改程式、加功能、寫測試、寫文件、提交與發版的規則。照這份做，測試會擋下大部分偏離的地方；擋不下的寫在「靠人守」。

## 一、加一個功能的步驟

| 步驟 | 做什麼 | 規則來源 |
| --- | --- | --- |
| 1 | 決定放哪：屬於某個功能就放 `features/<功能>/`，所有功能都要用的才放 `core/` | [architecture.md](architecture.md#app-內部分層) |
| 2 | 資料與規則寫在 `model/`（不碰畫面），表單寫在 `forms/`，頁面寫在 `ui/` | `layers_test` |
| 3 | 純計算（不需要帳本狀態）放 `packages/domain`，App 只呼叫 | [architecture.md](architecture.md#模組) |
| 4 | 新頁面：在 `core/navigation/nav.dart` 加一個 `AppRoute`，`app/shell.dart` 對應頁面；一次性的整頁工作（排序、匯入）用 `openFullScreen` | `layers_test` |
| 5 | 畫面只用設計系統：`AppColors`、`TextSize`、`solidButton`／`wordButton`、components 元件 | [design.md](design.md)、`app_design_syntax_test` |
| 6 | 頁面加進 `test/support/places.dart`，版面、無障礙、截圖就會涵蓋它 | — |
| 7 | 寫測試（見第三節），跑全部測試 | — |
| 8 | 更新文件（見第四節）、版號與 `whats_new.txt`（見第五節） | — |

## 二、程式

### 放哪裡

- 依賴只能往下：`app/` → `features/` → `core/` → 套件（`packages/`、`infrastructure/`）。
- 功能可以用別的功能的 `model/` 與 `forms/`（例如開它的表單），不能用它的 `ui/`；功能之間不能互相需要。需要同一個東西的兩個功能，把它搬到 `core/`。
- `core/` 分十部分，各自只能用表上允許的部分（[architecture.md](architecture.md#core-的十個部分)）。資料夾名稱集中在 `test/support/layout.dart`，改名只改那裡。
- 搬檔案用 `python3 tool/move.py 舊路徑=新路徑`（在 `apps/expense_tracker` 下執行），它會改好所有 import。

### 錯誤

- 每個 `catch` 做三件事之一：用 `ErrorLog.instance.record('做什麼', error)` 記下、重新拋出，或在區塊第一行用註解說明為何什麼都不用做（`error_rules_test`）。
- 不把例外原樣放進給人看的訊息；要附上原因時用 `ErrorLog.describe(error)`，它去掉路徑、引號內的字和數字。
- `record` 第三個參數是堆疊（`catch (error, stack)`）；沒給時用 `Error` 自己的堆疊，再沒有就記下呼叫 `record` 的位置。堆疊只留程式的函式名與原始檔行號，上限是 `ErrorLog.maxFrames`、`ErrorLog.maxStackChars`。
- `record` 不做檔案工作：先留在記憶體，最多 `ErrorLog.flushDelay` 後一批寫入（離開 App、發生未處理錯誤時立刻寫）。同一個錯誤連續發生只記一筆加次數。
- 預期中的失敗不用例外：回傳 sealed 的結果型別（例如 `ScanOutcome`、`UpdateStatus`），由 `core/messages` 轉成給人看的話。
- 沒人接住的錯誤由 `UnhandledErrors` 統一處理：開發與測試照樣顯示；正式版記下後用一則提示告訴使用者（最多每 `UnhandledErrors.noteGap` 一次）。
- 失敗後照常繼續的步驟（讀不到設定用預設值、快取重抓）也要記下，名稱放在 `ErrorSteps`。

### 大小與拆分

- 大小是參考，不是上限：檔案 600 行、函式 80 行、函式庫連同 `part` 1,200 行。超過時依職責拆，或在它上方註明為什麼一份比較好；拆的標準是每一份只做一件事、讀得懂，不是湊行數。
- 拆的方式：計算移到 `model/`（純 Dart、各有測試）；畫面依區塊拆成有公開建構參數的元件，放在一般函式庫，不用 `part`（`part` 不會讓函式庫變小，還共用全部私有成員）。區塊要讀寫表單時透過介面（例：`ComposeActions`）。
- 剛導入參考值時已超過的，列在 `tooling/architecture_checks/test/code_size_test.dart` 的債務清單，只准變小。

### 規則的例外

- 規則測試不列檔名。破例寫在程式旁：在那一行或它上方的註解寫 `// Exception to <規則>: <原因>`；整個檔案的例外寫在檔案最上方的註解。規則名稱：`error words`、`the radius scale`、`ledger words`、`motion`、`the motion scale`、`file length`、`function length`、`library length`。
- 動畫時間用 `Motion` 的標準值（Material 3：`short2` 100 ms 到 `extraLong1` 700 ms），一律經 `Motion.of(context, …)`，伸縮用 `MotionSize`；減少動態效果開啟時不動。停留時間（例如提示訊息多久消失）不是動畫，要標註例外，不可歸零。
- 定義所在的檔案（例如日期格式在 `dates.dart`、時間在 `core/time/`）本來就是規則的一部分，不算例外。

### 命名與註解

- 名稱用業界通用詞，不自創：依序查 Dart／Flutter、Android 官方、DDD（Evans）、PoEAA（Fowler）、會計與證券用語。名稱說它是什麼，不說怎麼做；不用縮寫（`Id`、`Json`、`Csv` 除外）；同一概念程式、資料夾、檔名同一個詞。改掉的舊名列在 `naming_test`，不准回來；改名用 `tool/reroute.py`（依分析器錯誤改寫呼叫處）或 `tool/move.py`，不用文字取代。
- 檔名後綴：`_page` 整頁、`_sheet` 底部面板、`_dialog` 中央面板、`_section` 頁面一段、`_form` 表單狀態（不含畫面）、`_editor` 編輯表單畫面、`_card`／`_tile` 清單一項、`_repository` 擁有狀態、`_service` 只讀計算、`_commands` 寫入指令、`_adapter` 平台轉接、`_data_source` 資料實際存放處。
- 檔名小寫底線，名稱說明內容（`loan_blocks.dart`），不用 `_2`、`utils`、`helpers`。
- 公開的類別、函式都有 `///` 文件註解，用英文寫「它是什麼、什麼時候用」；畫面上的中文字直接寫在註解裡對照（例：`/// 定期交易: …`）。
- 註解說「為什麼」，不重述程式在做什麼。
- 畫面文字用繁體中文，短、不重複；同一件事全 App 同一個說法。

### 畫面

- 顏色、字級、按鈕只從 `core/design_system` 拿，頁面裡不寫色碼、字級數字、`styleFrom`（`app_syntax_test`、`app_design_syntax_test` 讀語法樹檢查，註解與字串不會誤判）。
- 短標籤用 `OneLine`（放不下先縮到 75%，再放不下以…結尾），不讓它斷成兩行（版面測試檢查 12 字以內的文字）。
- 有標題的頁面用 `HeadedList`，標題固定、內容捲動；內容放得下時不能拖動。

## 三、測試

| 放哪 | 測什麼 |
| --- | --- |
| `test/<lib/src 底下的路徑>/<檔名>_test.dart` | 只測一個檔：`lib/src/a/b.dart` 的測試是 `test/a/b_test.dart` |
| `test/scenarios/` | 跨好幾個檔的情境：帳本、各功能的流程 |
| `test/rules/` | 全 App 的規則：分層、設計系統、版面、無障礙、命名、備份規則 |
| `test/support/` | 測試共用的工具與假物件（`places.dart`、`layout.dart`…） |
| `test/perf/` | 效能門檻與基準 |
| 各套件的 `test/` | 套件的規則與格式 |

- 修 bug 先寫一個會重現它的測試，確認在舊程式上失敗、修正後通過。
- 按按鈕、分頁、選項一律用 `core/design_system/keys.dart` 的 `Keys`（`find.byKey(Keys.save)`）；新的可按元件要測就先加一個 key。`find.text` 只用來確認畫面文字，或點帳本裡的資料本身（某筆紀錄、某個帳戶）（`test_rules_test` 檢查）。
- 版面、無障礙、對比測試自動涵蓋 `places.dart` 裡的每一頁：新頁面一定要加進去。
- 不跳過、不停用測試來讓 CI 變綠。

## 四、文件

### 每份文件的用途

| 文件 | 寫什麼 | 什麼時候改 |
| --- | --- | --- |
| [README（根目錄）](../README.md) | App 介紹、安裝 | 功能大改時 |
| [product.md](product.md) | App 能做什麼（給使用者看） | 新增或拿掉功能時 |
| [architecture.md](architecture.md) | 模組、分層、帳本、資料流、外部來源 | 結構或依賴規則改變時 |
| [design.md](design.md) | 設計系統與畫面規則 | 加 token、元件或畫面規則時 |
| [conventions.md](conventions.md) | 本文件 | 規則改變時 |
| [development.md](development.md) | 開發、測試、CI、發版 | 工具或流程改變時 |
| [android.md](android.md) | Android 端的實作與設定 | 改 Kotlin、權限、Google 設定時 |
| [CHANGELOG.md](CHANGELOG.md) | 每版改了什麼 | 每個版本 |
| [acceptance.md](acceptance.md) | 要在手機上確認的事，依功能分 | 畫面或手機行為改變時；驗收完打勾 |
| [roadmap.md](roadmap.md) | 現況數字、待辦、已知限制、刻意不做 | 發現或解決時；做完的移到 CHANGELOG |
| [adr/](adr/) | 重大決策的理由 | 做出新的取捨時加一篇，不改舊的結論 |
| 各模組 README | 模組做什麼、對外入口、不做什麼 | 改模組的公開行為時 |

### 寫法

- 開頭一行 `>` 摘要：這份文件回答什麼問題。
- 文件開頭一行摘要（`> `）；長度不設上限，寫清楚比壓短重要。
- 摘要、長度與每個連結都由 `tooling/architecture_checks/test/docs_test.dart` 檢查（ADR 除外）。
- 能用表格就用表格，能用條列就不寫長段落；一段不超過三句。
- 寫現在的狀態，不寫歷史；歷史在 CHANGELOG、ADR 與 git。
- 同一件事只寫在一個地方，其他地方連結過去。
- 提到程式時寫檔名或識別字（`HeadedList`），不貼大段程式碼。

### ADR

- 檔名 `adr/NNNN-主題.md`，內容：狀態與日期、背景、決策、後果。
- 決策改變時加新的 ADR，在舊的狀態列寫「由 ADR-NNNN 取代」，不改寫舊的內容；整篇都已被取代或做完、只剩歷史的 ADR 刪掉，現況寫在 architecture.md。

## 五、提交與發版

- 版號 `主.次.修`，三碼各在什麼時候變見 [ADR-0011](adr/0011-version-numbers.md)：第一碼是舊版 App 讀不了新資料或有人被留在後面（1.0 前固定 0），第二碼是使用者看得到新的或不一樣的東西，第三碼是看不到刻意的改變（修 bug、效能）。要發布時才升版：PR 可以不升，合併後不發布，等下一個升版的 PR 一起發；一次發布只升一次；升了某一碼，後面歸零；只升不降。
- 每個版本：`pubspec.yaml` 版號、`whats_new.txt`（三行以內，給使用者看）、CHANGELOG 一節；發行前升級套件一次並記在 [development.md](development.md#套件升級)。
- commit 訊息用英文：第一行說做了什麼，空一行後條列重點。
- 一個 PR 一件事（一批回饋或一次整理）；PR 說明列出改了什麼、怎麼驗證。
- 合併到 main 後 CI 自動建置、簽章、發布；App 內更新會讀到新版。
- 發布到 main 後，CI 自動為新版本打標籤 `v<版本>`，打在該版第一次發布的組建上，之後不移動；舊版本的 release 與標籤都保留（`android.yml`）。
- 每個次版號留一份它寫出的帳本與備份：`MAKE_FIXTURES=1 flutter test test/scenarios/ledger/persistence/old_books_test.dart`，產生的檔案進版控後不再改（[ADR-0010](adr/0010-data-that-lasts.md)）。少了這一份，`old_books_test` 失敗。
