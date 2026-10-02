# 帳戶生命週期正式接線主機證據（2026-10-02）

## 行為範圍

- App 可改名、設定資產摘要、封存、重新啟用及關閉帳戶。
- 不提供已存在帳戶的幣別或開戶日改寫。
- 封存不刪歷史、不釋放 32 帳戶上限；非 active 帳戶不能新增一般交易。
- 關閉在同一交易核對 Ledger 零餘額與 unresolved 信用卡授權。
- operation replay、內容碰撞、expected version、receipt／audit、容量與 portable snapshot 都 fail closed。
- 關閉日、原因與接手帳戶保存；重新啟用不清除最近 closure metadata。

## 驗證

- `account_lifecycle_session_test.dart`：2/2 通過；冪等、operation 衝突、stale version、改名、摘要、封存、重啟、關閉、二次關閉、重開、非零餘額及 pending authorization。
- `account_lifecycle_widget_test.dart`：1/1 通過；正式設定入口及完整可操作流程。
- 帳戶明細／資產摘要關聯回歸：3/3 通過；R11 App 組合共 4/4。
- validated_restore 完整套件：131/131 通過。
- architecture_checks：22/22 通過。
- expense_preview、ledger_generation、modular_persistence、validated_restore 靜態分析：零問題。
- `git diff --check`：通過。

validated_restore 的 Drift 多實例訊息為既有測試診斷；131 項 assertion 全數通過，本批未隱藏該警告。

## 未涵蓋

- Android 真機、跨裝置同帳戶併發、process death 與正式候選 APK/AAB。
- 未把封存描述為容量回收；帳戶實體仍計入既有 32 帳戶上限。
