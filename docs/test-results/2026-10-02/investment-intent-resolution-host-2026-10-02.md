# 投資待確認交易安全核對主機證據（2026-10-02）

## 範圍

- 外部稽核 R01：買入、賣出、股息與拆股在結果不明或確定拒絕後，必須能安全恢復。
- 核對以 Ledger 權威事實為準；secure vault intent 不作為已提交證據。
- 本批為 Windows 主機與 Flutter widget 證據，不取代 Android process death 實機驗收。

## 行為結論

- 完全相同的 operation／event／payload 已存在：完成 intent，不新增第二筆交易。
- 權威事實不存在：經二次確認後可捨棄 intent。
- 多筆、身分碰撞或內容不同：拒絕核對並保留 intent。
- vault 刪除或 read-back 失敗：拒絕核對並保留 intent。
- 使用者仍可沿用原固定識別重試；不產生新的 operation 或 event。

## 已執行驗證

- `flutter analyze`（expense_preview）：零問題。
- 買入／賣出／股息／拆股流程：8/8 通過。
- 投資畫面：8/8 通過，含核對二次確認與無重複入帳。
- modular persistence 投資賣出：7/7 通過，含 workspace 全部權威賣出查詢。
- 架構邊界與簽署發布規則：22/22 通過。
- `git diff --check`：通過。

流程測試會出現既有的 Drift 多資料庫實例警告；所有測試 assertion 通過。本批沒有把警告隱藏或當成已解決，仍留在效能／生命週期驗證工作中。
