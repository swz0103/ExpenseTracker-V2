# data_exchange

檔案匯入匯出，只依賴 `foundation_values`。

- `parseEInvoices`：讀財政部電子發票平台下載的「消費明細」CSV。欄位依表頭找，不依順序；同一張發票的品項加總、品名去重；作廢的發票略過。任何一列讀不懂就整份停下，並指出第幾行。發票號碼可以用來跳過已記過的發票。
- `readCsv`／`writeCsv`：CSV 讀寫。寫出時帶 BOM、使用 CRLF，Excel 打開不會亂碼；逗號、引號、換行都會正確加上引號。

App 要匯出明細時，自己組好欄位（日期、類型、帳戶、分類、金額、備註），再交給 `writeCsv`。
