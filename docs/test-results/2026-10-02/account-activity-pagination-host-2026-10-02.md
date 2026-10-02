# 帳戶活動獨立分頁主機證據（2026-10-02）

## 行為範圍

- 帳戶明細以 account ID 直接查詢 Ledger，不依賴首頁 30 筆快取。
- keyset 分頁包含來源帳戶與轉帳目的帳戶；轉入使用實際 received 金額。
- sheet 分離首次／後續 loading、empty、error／retry 與 hasMore。
- request epoch、mounted 與解鎖檢查隔離關閉或鎖定後的晚到結果。
- 無關帳戶或重複 keyset row 會拒絕合併；原有交易分類摘要保持顯示。

## 驗證

- `account_entries_engine_test.dart`：1/1 通過；31 筆支出加轉帳形成 30+3 兩頁，頁間無重疊，來源／目的帳戶皆命中。
- `account_report_widget_test.dart`：2/2 通過；31 筆以上顯示可操作的「載入較早活動」，320px 與雙倍文字仍可使用。
- 帳戶、搜尋與活動關聯組合：7/7 通過。
- architecture_checks：22/22 通過。
- `flutter analyze`（expense_preview）：零問題。
- `git diff --check`：通過。

## 未涵蓋

- Android 系統返回、process death 與真機記憶體／效能；分別由 R05、R08、R06 gate 處理。
- 本批沒有提高 5,000 events 或 portable payload 上限。
