# 商家與基本別名

**狀態：開發中，只有 Domain 子集通過本機驗證。Merchant capability 尚未開放。**

接續 [Tag PR #46](https://github.com/swz0103/ExpenseTracker-V2/pull/46)（`10a49ba7ad67ee7d0dbca2a4c0e8a4000e3f3b9b`），在同一商家功能分支／PR 逐步完成全流程，不為每個輔助函式另開 PR。來源：[M1-02](implementation-plan.md)、[RC-05](architecture-baseline-v1.0-rc1.md#rc-05)、[FV-012](full-vision-baseline.md#fv-012)、[Q062](full-vision-baseline.md#q062)。

## 已實作與驗證的規則

`packages/merchants` 只依賴基礎值型別。相同名稱不代表相同身份；別名只回傳候選 canonical 身份，由呼叫端要求使用者確認。新金融事件必須選當前可用的 ID／版本，不能透過已合併來源悄悄轉換選擇。

已具備建立、改名、封存／啟用、明確合併、別名增刪、候選查找、版本衝突與 workspace 隔離。合併保留來源及其名稱／別名；歷史查詢可解析目前 canonical 身份。不同商家可以共用別名，因此可以出現多個候選。關閉 canonical 目標後，所有指向它的名稱／別名都停止成為可用候選，歷史仍可讀。

比對僅裁切首尾空白並做 Dart 無語系小寫轉換，保留標點及內部空白；不做模糊比對、分店／位置推測或 Unicode 正規化。改名不擅自把舊名稱存為新別名；需要時明確新增。來源合併後不可直接改寫，沒有隱式解除合併。每身份最多 16 個別名、每個 100 個 UTF-16 code units；持久化接入時還須納入整體 bytes／列數限制。

[本機證據](test-results/merchant-domain-host-2026-09-27.json)：Merchant 15 項與架構 15 項通過，包含不可變視圖、精確比對、歧義與明確合併、封存及重新啟用、增刪別名版本衝突、容量、跨 workspace、非法還原及一萬節點合併鏈。既有 App／DB 完全未接入此套件，不重跑相同版本的加密與 App 回歸，也不把過去全套結果當成新商家全流程已通過。

## 接續同一功能單位

1. 接入商家目前狀態及 command 歷史、receipt／Audit，沿既有 OperationWriter 做原子操作與重試；財務引用由 Ledger 主責。每筆收支最多選一個商家，與既有分類／Tag 一起提交。保留所有既有 receipt bytes。
2. 加入嚴格 snapshot manifest、歷史重播與引用核對、容量增量保護；預定新 schema 7／snapshot 6 及已知 6 → 7 安全升級路線。這些版本尚未實作，不能用開關冒充可用。來源、備份及雙憑證 gate 不變。
3. 完成 App 管理、別名增刪、候選確認、商家選取、明確合併及歷史顯示；新交易清空非明確複製的欄位。只接已驗證行為，不出現失效入口。
4. 跑正常／邊界／失敗／重試／篡改／乾淨還原／升級中斷及 UI；涉及既有格式時完整本機整合，必要大量資料與 APK 核對一併完成，再把完整 PR 改為待審查。

分店、位置、規則記憶與進階 Entity Resolution 繼續沿 rc1 保留；本批不預建這些引擎，不自動讀取舊版 App。
