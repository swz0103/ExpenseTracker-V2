# 設計系統

> 畫面怎麼長、用哪些顏色、字級和元件。程式在 `apps/expense_tracker/lib/src/core/look/`；頁面不自己寫顏色、字級、按鈕樣式（`design_rules_test` 檢查）。

## 原則

- 大圖示、色塊，少用清單與白卡堆疊；卡片本身就是表單（名稱、金額直接在卡上輸入）。
- 字少、不重複：一個資訊只出現一次。
- 不花俏：動畫 200～300 ms，尊重「減少動畫」；震動只用在完成、拖曳換位、超支、開關。
- 設定細項與選擇器開在畫面中間的面板，表單用底部面板。
- 淺色與深色同時設計，深色不是淺色的反轉。

## 顏色

每個顏色是 `Shade`（同時有淺色與深色值，畫的時候才決定），集中在 `theme.dart`：

| 類別 | 名稱 | 用在 |
| --- | --- | --- |
| 底與面 | `Hue.paper` `white` `surface` `group` `tile` `hero` `line` | 頁面底、輸入框、按鈕底、清單分組、主卡、分隔線 |
| 文字 | `Hue.ink` `muted` `faint` `hint` | 主要、次要、停用、待填 |
| 意義 | `Hue.accent` `positive` `negative` `transfer` `investment` | 介面主色、收入、支出、轉帳、投資 |
| 帳戶類型 | `Hue.cash` `bank` `wallet` `card` `holdings` `receivable` | 帳戶卡與分組 |
| 疊加 | `Hue.glass` `scrim` `lift` `float` `halo` `none` | 色卡上的霧面、面板後的暗幕、拿起的陰影 |
| 工具 | `ToolHue.*` | 每個工具在更多、自己的頁面與總覽卡片的顏色 |
| 色盤 | `Palette.*`、`Hue.categoryColors`、`Hue.shades` | 工具與設定的色塊、分類可選的顏色、圖表 |

配色函式（`kit/colours.dart`）：

| 函式 | 做什麼 |
| --- | --- |
| `tintOf(c, a)` | `c` 混進底色的淡色塊（深色下與帳戶卡一樣深） |
| `deepOf(c)` | 淡色塊上的字，自動加深到 4.5:1 |
| `wordsOn(c)` | 實色底上的字（白或黑） |
| `chosenFill` `chosenInk` `chosenEdge` | 選中狀態：淺色實心；深色改成淡底加同色框與字 |
| `shownColor(c)` | 使用者選的分類色在深色下的柔和版（存的值不變） |

深色規則：不出現比帳戶卡更亮的色塊（`tintOf` 在深色下越濃增加越慢）；選中與實心按鈕用 `chosenFill`；圖示用「深底＋淡色圖示」（`SquareIcon`）；層次靠底、卡、按鈕三階亮度，不靠陰影。

## 字級

`TextSize`（`type.dart`），頁面只寫角色、不寫數字：

| 角色 | 大小 | 用在 |
| --- | --- | --- |
| `tiny` | 11 | 日曆格裡的「到期」 |
| `caption` | 12 | 圖例、小標籤 |
| `small` | 13 | 次要說明、數量、日期 |
| `body` | 15 | 一般文字、列名、欄位 |
| `title` | 17 | 卡片與區塊標題 |
| `heading` | 20 | 頁面與面板標題 |
| `large` | 24 | 卡片上的數字 |
| `figure` | 28 | 主卡的數字 |
| `big` | 34 | 頁面的主角數字 |
| `hero` | 44 | 最大的數字 |
| `display` | 56 | 解鎖與救援碼的數字 |

字型：Nunito（數字與英文）＋ Noto Sans TC（中文），只用 App 自帶的字（`font_coverage_test`）。

## 元件

| 需要 | 用 | 檔案 |
| --- | --- | --- |
| 有標題的頁面 | `HeadedList` ＋ `CenterHeader`（子頁）或 `PageHeader`（分頁） | `headers.dart`、`kit/headers.dart` |
| 頁面主卡 | 收支：`BalanceHero`（結餘＋收支長條）；其他：`HeroFigure`，外框 `HeroCard` | `core/ui/balance_hero.dart`、`kit/figures.dart` |
| 帶數字的小卡、並排 | `FigureCard`、`CardRow` | `kit/figures.dart` |
| 色塊卡、可點的方塊 | `ColorCard`、`CardGrid` | `kit/cards.dart` |
| 清單分組、報價列 | `GroupBox`、`QuoteBoard` | `kit/figures.dart`、`kit/boards.dart` |
| 區塊標題、表單分組 | `SectionTitle`、`FormGroup`（小標題＋淺灰底上的選項） | `kit/figures.dart` |
| 大的分段選擇 | `BigSegments` | `kit/cards.dart` |
| 小的選項 | `ChoicePill`、`Segments` | `controls.dart` |
| 開關 | `ToggleRow` ＋ `TickSwitch`（整列可點） | `kit/marks.dart` |
| 設定格 | `SettingCard` | `kit/cards.dart` |
| 中間面板 | `showPanel`、`CenterPanel`、`PanelButton` | `kit/panels.dart` |
| 底部面板、整頁工作 | `showSheet`、`openFlow` | `feedback.dart` |
| 確認、輸入文字 | `confirm`、`askText` | `dialogs.dart` |
| 日期區間、時間 | `pickDateRange`、`pickTime` | `time_panels.dart` |
| 按鈕 | `solidButton`、`wordButton` 給 `FilledButton`／`TextButton` | `kit/buttons.dart` |
| 不換行的短字 | `OneLine` | `kit/words.dart` |
| 報價列、空狀態、⋯ 選單 | `QuoteBoard`、`EmptyState`、`DotsMenu` | `kit/boards.dart` |
| 圖示 | `GlyphIcon`；卡片與色塊用方形 `SquareIcon`，清單列與選單用圓形 `RoundIcon`；新圖示加在 `tool/glyphs.py` 再產生 | `glyphs.dart`、`kit/marks.dart` |
| 小標記 | `Pill`、`LegendKey`、`RingGauge` | `kit/marks.dart` |

認得帳本的元件（紀錄列、帳戶選擇、計算機、金額顯示）在 `core/ui/`。

白卡元件已退場（[ADR-0006](adr/0006-retire-white-cards.md)），頁面不寫白底加陰影的卡（`design_rules_test`）。

## 版面規則

- 每一頁在 320／360／412 dp、字級 100／130／150%、淺深色下都要：不溢位、字不重疊、不縮到六成以下、12 字以內不換行（`test/app/layout_*_test.dart`）。
- 點擊範圍至少 48 dp 且有名稱（`accessibility_test`）；文字與底色至少 4.5:1（`colour_contrast_test`）。
- 標題固定在上；內容放得下（只差底部留白）時頁面不能拖。
- 金額欄整列點了開計算機；開關整列可點。
