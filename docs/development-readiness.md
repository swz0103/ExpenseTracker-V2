# ExpenseTracker V2 — 開發前置準備

日期：2026-09-26  
狀態：GitHub 私人 repository 已建立；等待 Android 命令列工具與必要授權準備完成，再進功能實作。

## 本輪授權與工作順序

使用者要求直接建立新的 GitHub 專案，並先集中處理需要其完成的準備。這更新了先前「只看計畫」及「Freeze 後才建立 repository」的時序：可以先建立私人 repository 保存文件，但文件初始化不等於 Architecture Freeze；正式功能仍依[實作計畫](implementation-plan.md)先完成規格與地基驗證。

已建立私人 [swz0103/ExpenseTracker-V2](https://github.com/swz0103/ExpenseTracker-V2)，建立前已確認無同名 repository。預設分支為 `main`，文件使用 `docs/architecture-and-implementation-plan` 分支提交。只納入專案文件與必要根目錄檔案，不上傳 `.work/`、同步的 `sources/`、認證、金鑰或本機帳本。初始 README 由 GitHub 建立，後續文件走 PR，不直接 push main。

## 已檢查的環境

- Git 與 GitHub CLI 已安裝；Git 提交身份已存在。
- GitHub 連接器及 CLI 已確認帳號為 `swz0103`；使用者已完成本次官方裝置登入授權，repository 建立成功。
- Android Studio 已安裝，內附 Java 21 可執行。
- Android SDK 已存在，包含 Android 36／36.1、Build Tools 35／36 與可執行的 adb；不是缺少整套 Android 環境。
- 在已檢查的 PATH／常見位置未找到 Flutter；Android command-line tools 及可用模擬器設定尚待準備。未找到不等於已完整掃描所有磁碟。

以上是當下檢查結果，不是 Flutter doctor 全通過，也不代表 Android App 已能建置。

## 需要使用者先做

GitHub 授權已完成，不需重做。**目前只需安裝 Android SDK Command-line Tools 並完成必要授權。** 當下工具未安裝；官方索引顯示新版工具引用 android-sdk-license，本機既有授權紀錄未能確認與此次授權文字一致，因此不替使用者自動接受。

1. 開啟 Android Studio；首頁選 **More Actions → SDK Manager**，或已開專案時選 **Tools → SDK Manager**。
2. 開啟 **SDK Tools**，勾選 **Android SDK Command-line Tools (latest)**。
3. 按 **Apply**，閱讀並完成必要授權與安裝，完成後告知助手。

依據：[Flutter 官方 Android 設定](https://docs.flutter.dev/platform-integration/android/setup)、[Android sdkmanager 說明](https://developer.android.com/tools/sdkmanager)。Flutter 由助手後續準備，不要求使用者額外安裝。GitHub 授權代碼未存入 repository。

## 助手可以處理，不先交給使用者

- 確認 Flutter 正式版本與安裝位置，準備 Flutter／Dart 及 PATH／專案環境；不任意替換既有 Android Studio。此次命令列工具經使用者完成安裝與必要授權後，再驗證 SDK。
- 檢查 Flutter doctor、必要 licenses、可用模擬器；能由模擬器完成前期驗證時，不要求使用者現在連接手機。
- 建立 repository、文件分支與可審查的 PR。README 初始化屬建立專案；後續內容遵守分支／PR 流程，不直接 push main。
- 完成實作計畫階段 0 的架構規格與代表案例，之後才執行技術原型與功能實作。

此次已提出命令列工具與授權步驟；模擬器若另外需要系統管理員／BIOS 設定，確認實際需要後再集中提出，目前不要求變更系統設定。

## 現在不用做

不需先申請雲端資料庫、行情付費帳號或商店帳號，也不需提供真實帳本、付款資訊、API 密鑰或發版金鑰。到需要該整合的批次時，先核實方案與權限，再提出必要準備。
