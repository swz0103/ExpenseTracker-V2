# ExpenseTracker V2 — 開發前置準備

日期：2026-09-26  
狀態：GitHub 私人 repository、Flutter／Dart 與 Android 工具鏈已準備；主機端原型可執行，Android 裝置驗證尚待完成。

## 本輪授權與工作順序

使用者要求直接建立新的 GitHub 專案，並先集中處理需要其完成的準備。這更新了先前「只看計畫」及「Freeze 後才建立 repository」的時序：可以先建立私人 repository 保存文件，但初始化不等於 Architecture Freeze；正式功能仍依[實作計畫](implementation-plan.md)完成規格與地基驗證。

已建立私人 [swz0103/ExpenseTracker-V2](https://github.com/swz0103/ExpenseTracker-V2)，預設分支 main；工作分支為 docs/architecture-and-implementation-plan，透過 [Draft PR #1](https://github.com/swz0103/ExpenseTracker-V2/pull/1) 審查。初始 README 由 GitHub 建立，後續走 PR，不直接 push main。同步來源、暫存擷取資料、認證、金鑰與真實帳本不納入提交。

## 已完成

- Git 與 GitHub CLI 可用；提交身份已存在，使用者已完成 GitHub 登入授權，帳號 swz0103。
- 使用者已安裝 Android SDK Command-line Tools 並接受必要授權；flutter doctor -v 確認 Android toolchain 通過，Android licenses 全部已接受。
- Flutter stable 3.47.5／Dart 3.13.4 已安裝於本機 C:\Users\suwei\develop\flutter；framework ref 6a19cca56475dbfba1478ee68d7bd0c2ef891da1。已加入使用者 PATH，新開終端生效；分析回報已停用。
- Android Studio 內附 Java 21.0.10；Android SDK 包含 36／36.1、Build Tools 35／36、Platform Tools 與 Emulator。
- 主機端 SQLite 原型已通過靜態分析及 11 項測試，範圍見[驗證紀錄](foundation-validation.md)。

以上是本機觀察結果，不代表正式 Android App 已建置成功或完整架構已通過。

## 尚未完成

- 當下沒有連接 Android 手機，也沒有已建立的 AVD；模擬器加速檢查回報未安裝 hypervisor driver。主機端原型可繼續，Android 執行 gate 保留未完成。
- Android 加密資料庫、平台金鑰、乾淨環境備份還原與 migration 尚未實測。
- Windows 桌面用 Visual Studio 元件未齊；目前目標是 Android，此項不列為當期阻礙。

GitHub 登入與 Android 授權不需重做。目前可由助手繼續工程規格與主機端驗證。需要 Android 裝置時，再集中處理測試手機或模擬器加速所需設定，不以 host 測試代替裝置 gate。

## 暫時不需準備

不需先申請雲端資料庫、行情付費帳號或商店帳號，也不需提供真實帳本、付款資訊、API 密鑰或發版金鑰。到需要該整合的批次時，先核實方案與權限，再提出必要準備。

工具設定依據：[Flutter 官方安裝](https://docs.flutter.dev/install/manual)、[Android 設定](https://docs.flutter.dev/platform-integration/android/setup)。
