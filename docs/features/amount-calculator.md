# 金額欄內建計算器

> 這是舊版 App（`prototypes/`，已於 2026-10-03 移除）時期的規格，留作行為對照。新架構以 [ADR-0001](../adr/0001-target-architecture.md) 與 [STATUS.md](../STATUS.md) 為準。

範圍：M1-02／[Full Vision Q025](../architecture/full-vision-baseline.md#q025)、[RC-02](../architecture/architecture-baseline-v1.0-rc1.md#rc-02)、[RC-04](../architecture/architecture-baseline-v1.0-rc1.md#rc-04)。本批交付期初餘額及手動收支金額的完整計算、套用、草稿與入帳路徑；不代表 M1 或 Design System 全部完成。

## 使用流程

金額欄可以輸入一般數字或算式，例如 `120 + 85 − 20`。點欄內「計算金額」先看到 `TWD 185.00`，再按「套用結果」才取代原文字。輸入算式或按計算不會更改帳本；仍須既有建立帳戶／儲存收支操作才會入帳。

若需要取位，結果旁明確提示幣別與小數位數；套用前保留原算式。除以零、括號錯誤、資源上限或金額溢位都保留文字且不提供套用。修改算式、換帳戶幣別、鎖定或表單停用會讓舊提案失效，不能將舊結果套用到新幣別。

目前計算按鈕有朗讀標籤，錯誤與結果有 live region。放大文字可換行，套用保持可操作。金額編輯沿用[隱私呈現契約](privacy-presentation.md)，正在編輯的文字與計算結果可見；回到帳本後仍遵守遮罩。

## 語法與精度

- 支援 ASCII `+ - * /`、`− × ÷`、小數、括號、一元正負號及百分比。
- 先算括號，再算乘除，最後加減；同級由左至右。`1 − −2 = 3`，但 `1**2` 不合法。
- 百分比固定是後綴除以 100，不隨前一個數改成加成：`100 + 10% = 100.10`，`100 × (1 − 10%) = 90`。結果區提示 `10% = 0.1` 與折扣例子。
- 前導零不當八進位；`00012.50`、`.5`、`1.` 可在明確計算後標準化。一般直接儲存仍走嚴格 Money.parse，沒有放寬原手動輸入精度。
- 不支援隱式乘法、指數、千分位分隔、函式、變數或遠端規則；例如 `2(3)`、`1e2` 必須修正。
- 128 個 UTF-16 code units、最多 96 個 token、括號深度 16；超界拒絕，不截斷算式。UI 超長貼上整次拒絕並保留先前文字，避免截短後改變計算值。中間有理數約分並限制為 4,096 bits，沒有 eval 或浮點數。
- 中間步驟維持 BigInt 有理數；只在最後依幣別小數位，以既有 `half-away-from-zero-v1` 取位。`1 ÷ 3 × 3 = 1.00`；`1 ÷ 3 = 0.33` 並提示取位。最後仍受 Money 有號 64-bit minor units 保護。

## 業務與保存邊界

獨立 `packages/amount_input` 只依賴 Foundation Values。公開 `calculateAmount(currency, expression)` 回傳 Money 與是否實際發生精度損失，沒有保存、Flutter、交易或帳戶依賴。App 只取得提案，套用仍走原金額欄變更回呼。

回查發現 Money.quantize 與 FxRate.convert 各自有同一取位演算法，因此加入 `Money.quantizeRatio` 作為共用計算邊界；既有十進位取位與 FX 沿用此接口。分母必須為正，運算資源有界，manual parse 與序列化格式不變。既有金額／FX 規則與整合回歸必須一同驗證。

解析失敗回傳 AmountInputException 的 syntax、divisionByZero 或 complexity；最後超出可保存範圍由 MoneyException 拒絕。例外文字不含使用者算式或金額。

原算式沿用[手動草稿](manual-entry-drafts.md)既有 amount 文字欄加密保存，不新增表或草稿格式。套用把文字改成標準 Money.majorText，保留原 draft／operation identity。未套用算式不能由 submit 偷偷求值；交易仍由原 Domain 驗證，支出／收入不因計算結果而放寬正數等規則。

計算過程不另外保存為正式金融事件或審計公式。套用前保存在本機草稿；套用後，草稿與未來入帳保存所選金額。schema 7、snapshot 6 與加密格式不變。升級／備份／還原對未完成草稿的 gate 保留。

## 驗證

以本批主機證據及大量資料結果為準；文件存在不代表執行通過。

驗證正常四則、百分比、取位、前導零、解析錯誤、零除、溢位、token／深度限制、分數消去與負數，以及提案不能自行改值、幣別變更／編輯失效、無障礙及窄螢幕。實際 App 包括期初計算、收支草稿鎖定恢復、提交中斷不重複、刪除合成來源資料與 vault keys 後的乾淨還原。

大量資料沿用商家工具，加入 `calculator` 模式：4,999 筆金額分別經分數消去、取位與百分比計算，再接到既有 5,000 事件／metadata／重送／雙憑證還原驗證。期望金額與最終餘額由固定獨立整數累加，不以計算器輸出作唯一 oracle。其餘歷史升級與原生程序中斷由完整主機清單涵蓋。

主機命令：

```powershell
./tooling/run-host-checks.ps1 -Offline
# 完整主機結束後，在 prototypes/expense_preview 中執行
dart run tool/merchant_scale.dart calculator
```

不操作手機、不啟用雲端工作；裝置鍵盤與 TalkBack 驗收仍待使用者回來。共用表單、日期選擇、i18n 等 M1-02 工作繼續接續，未在此批宣稱完成。
