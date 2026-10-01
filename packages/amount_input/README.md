# Amount Input

金額輸入業務的純 Dart 計算單元，只依賴 Foundation Values。由 App 明確計算並確認套用；本套件不寫入 Ledger 或草稿。

公開接口為 `calculateAmount(Currency, String) → AmountCalculation`，結果包含 `money` 與 `rounded`。語法、百分比定義、資源限制、錯誤、精度與驗收見[完整契約](../../docs/features/amount-calculator.md)。

本機執行 `dart test`；案例包含運算優先順序、十進位精度、最後取位、異常輸入、有號儲存邊界及分數消去 corpus。迴圈內多個輸入不計為額外獨立測試。
