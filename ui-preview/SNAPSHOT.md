# 初版 UI 預覽快照 — v114

保存日期：2026-10-08（Asia/Taipei）。這是日々記帳 APP 形式的網站預覽，尚未整合到 Android 程式。

- 預覽原始碼 commit：`1083ec46962c7faf66413402f2129da14ca9ac39`
- Android 基底 commit：`b9b27c9d5936ca00704523b339ebd6eb1db47ec5`
- 線上預覽：https://expense-tracker-warm.suweizhe880103.chatgpt.site
- `dist/`、`tests/`、README 與設計文件逐檔保留；未包含託管設定、憑證、瀏覽器私有資料或開發暫存。
- `main` 與 Android 檔案未修改；本分支用於保存及後續整合參考。

## 本機預覽

從儲存庫根目錄執行：

```sh
python3 -m http.server 8080 --directory ui-preview/dist
```

開啟 http://localhost:8080。介面不需建置或安裝相依套件。資料為演示資料，變更僅存於各瀏覽器 localStorage。

## 執行驗證

測試使用 Node.js、`@napi-rs/canvas` 與 `sharp`。可在 ui-preview 目錄安裝本機測試依賴：

```sh
cd ui-preview
npm install --no-save --no-package-lock @napi-rs/canvas sharp
CODEX_PRIMARY_RUNTIME_NODE_MODULES="$PWD/node_modules" node tests/app-experience.cjs
CODEX_PRIMARY_RUNTIME_NODE_MODULES="$PWD/node_modules" node tests/waterfall-style.cjs
```

v114 已通過功能及資料一致性測試、瀑布圖 SVG 光柵檢查。字型元件寬度檢查涵蓋 320／390／430 px，並非瀏覽器或真機截圖。真機鍵盤、系統大字體尚未實測；行情為手動／JSON 匯入，尚未串接自動即時行情。

後續設計依據見 INTERFACE_DECISIONS.md；本輪驗收見 DESIGN_REVIEW.md。
