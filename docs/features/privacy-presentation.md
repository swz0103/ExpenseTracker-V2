# 金額遮罩與基本無障礙

範圍：M1-02 的帳戶餘額、交易列表及基本操作回饋。依據 [RC-02](../architecture/architecture-baseline-v1.0-rc1.md#rc-02)、[RC-15](../architecture/architecture-baseline-v1.0-rc1.md#rc-15)、[Full Vision Q047](../architecture/full-vision-baseline.md#q047)、[Q095](../architecture/full-vision-baseline.md#q095)。這是既定完整 Privacy Presentation 的第一個可驗證使用流程，不代表 RC-15 或全部無障礙 gate 完成。

後續補強：[鎖定時取消確認窗、下拉與操作選單](lock-transient-routes.md)，涵蓋退場中的浮層及確認回呼工作階段保護。

## 使用流程

帳本右上角提供「隱藏金額／顯示金額」。隱藏時，現有帳戶餘額與交易金額統一呈現 `••••`，螢幕閱讀器只取得「帳戶餘額已隱藏」或「交易金額已隱藏」。共用 `presentMoney` 在隱藏分支不格式化實際金額，`MoneyView` 排除子文字的重複朗讀。

金額遮罩不隱藏帳戶、分類、商家、Tag 或日期，也不改寫財務資料。正在編輯的金額欄保留輸入文字，方便確認；進入背景仍使用既有鎖定流程。遮罩不是匿名化匯出或備份內容過濾，匯出的加密帳本仍保留完整金額。

可見狀態保留原有整數 Money 格式，包含負數、零位與兩位幣別及大整數，不轉成浮點數。格式化函式由原畫面移至純 Dart 呈現單元，並直接沿用既有 Money.majorText，消除第二套字串格式規則；財務計算仍在既有 Domain。

## 保存與失敗處理

偏好存於 V2 平台 secure storage，slot 為 `privacy_v1_<profile identity>`。僅提供 `visible`、`hidden`；沒有既有偏好時維持原有顯示，未知值或讀取失敗一律隱藏。解鎖後先讀偏好，再交付帳戶與交易畫面，避免載入途中先顯示金額。

- 隱藏立即作用於畫面，再保存並讀回驗證。
- 顯示必須先保存且讀回相符，成功後才揭露。
- 寫入或讀回失敗，本次 App 開啟期間維持隱藏，顯示保存失敗訊息；重新整理或鎖定後解鎖都不清除此暫時保護，只有成功的使用者切換會清除。
- App 被終止前若保存未完成，下次啟動依實際持久偏好決定；本次暫時隱藏不是已持久保存的承諾。
- 鎖定會清掉畫面與 profile identity；進行中的讀寫由 session epoch 判定失效，過期結果不能重新揭露畫面。已經完成的偏好寫入可能保留，視為先前明確要求的設定。

偏好是目的裝置／profile 的呈現設定，不寫進 Ledger，不影響 operation receipt、schema 7 或 snapshot 6。還原另一個 workspace 保留目的 profile 的設定；不同 profile 即使使用相同 vault adapter 也不共用 slot。沒有讀取或搬移舊 App 的偏好、帳本或金鑰。

## 排版與操作回饋

共用 `FinancialSummary` 在窄螢幕或較大文字時，將金額放在說明下方，避免長名稱與金額爭用列表尾端寬度。金額完整保留，不用省略號遮掉數位，也不縮小使用者選定的字體。頁面切換重設列表位置；同頁載入更多仍保留位置。

金額與交易操作有明確朗讀標籤，錯誤／結果訊息加入 live region。現有操作仍使用 Material 按鈕，保留鎖定、忙碌與確認行為。

## 驗證與未完成範圍

本機驗證證據以 [privacy-presentation-host-2026-09-27.json](../test-results/2026-09-27/privacy-presentation-host-2026-09-27.json) 為準。涵蓋 profile 隔離、偏好重開、錯誤／未知值、鎖定競態、還原前後財務 snapshot 一致、可見與隱藏 semantics、保存失敗後重試及完整 App 回歸。

排版案例為 320／600 logical pixels、1／2／3.2 倍字體、長名稱及最大測試金額；驗證無 overflow、完整金額、操作標籤及 Android touch target guideline。實際 App 流程另以 360 × 740 驗證。這些是主機 widget 測試，不代替真實 TalkBack、裝置字體、對比與 reduced motion 驗收。

仍須後續完成：全 App i18n 與共用表單、完整 Design System、minimal 模式、附件／搜尋／通知等新增表面的共用隱私策略。背景與 Recent Apps 預覽沿用既有保護，Android 實機 gate 待使用者回來；尚未實作的 Widget／Shortcut 不建立虛假入口。M1／M2／M3 其餘 CORE 仍依 [實作安排](../delivery/implementation-plan.md) 接續。

## 本機重現

在 `prototypes/expense_preview` 執行：

```powershell
flutter analyze --no-pub
flutter test --no-pub --concurrency=1 --reporter expanded
```

測試使用合成資料、測試 vault 與受保護的暫存目錄清理；不操作手機。完整主機套件與大量資料既有證據另列，不能把本次 App 回歸說成所有套件或雲端重跑。
