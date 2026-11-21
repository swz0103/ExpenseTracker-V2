# ADR-0004：設計系統只在一處，頁面只用名字

- 狀態：採用（2026-11-14）；2026-11-21 改寫：路徑與規則測試改成現行的
- 現況：[design.md](../design.md)

## 背景

頁面裡寫了 391 個字級數字（12 種以上的大小）、49 個色碼、46 個各自設定的按鈕樣式。深色模式調整時漏掉好幾個按鈕與色塊，字級在不同頁面不一致。

## 決策

- 設計系統在 `lib/src/core/design_system/`：字級是 `TextSize` 的角色，顏色在 `AppColors`（或 `Palette`）裡有名字，間距與圓角是 `Space`、`Radii` 的級距，動畫時間是 `Motion` 的標準值。分類顏色是資料，可以出現在帳本與範例帳本。
- 按鈕樣式由 `solidButton`、`wordButton` 產生，深色的處理只寫在那裡。
- 規則讀語法樹（`tooling/architecture_checks/test/app_syntax_test.dart`、`app_design_syntax_test.dart`）：設計系統以外不能寫色碼、字級數字、`styleFrom`、不在級距上的間距與圓角；註解與字串不會誤判。

## 後果

- 調整一個顏色或字級，所有頁面與兩種主題一起變。
- 新元件要先加進設計系統，頁面才能用。
