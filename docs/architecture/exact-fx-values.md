# 精確 FX 值型別與觀測日期

範圍：[RC-04](architecture-baseline-v1.0-rc1.md#rc-04) 的計算地基。`foundation_values` 新增 `FxRate`／`FxObservation`，不改 Ledger schema、備份格式或 UI；尚非跨幣轉帳與行情能力完成。

## 表示與換算

`FxRate(base, quote)` 的語意固定為 **1 單位 base 主幣額 = numerator / denominator 單位 quote 主幣額**。正十進位文字先轉成整數係數與十的次方，再約分；不經 double。反向與交叉匯率保留有理數，1/3 不必先截成某個小數位數。

這是 FX 所需的小型精確計算型別，使用既有 Dart BigInt，不新增通用 Decimal 函式庫；股數、單價、成本的欄位精度與呈現仍留待相應業務。十進位原始輸入仍應由業務紀錄保存需要的顯示／來源 context，正規化 ratio 只表達數值。

- 文字最長 128 字元，分子／分母各最多 128 位十進位數字，必須大於 0。超界拒絕，不能把不可計算變成匯率 0 或 1。
- `inverse()` 精確交換分子分母；`then()` 先消去共同因數才相乘，禁止中間幣別／scale 不一致。不能用不同日期的觀測自動組成一個假裝同日的 quote；Application 必須保留所有來源 context。
- `convert(Money)` 按兩邊 currency scale 計算最後 minor units，沿用 `half-away-from-zero-v1`，最後才檢查 Money 的 signed 64-bit 上限。
- 同一 currency code 只接受相同 scale 與 1:1 identity；不以這個型別表達同幣費用或帶損益的循環換匯，費用與多筆實際交易須明列。
- `fromAmounts()` 只從兩邊正本金推算精確比率；不改寫原金額，也不宣稱該值來自 provider。退款／反轉仍用原已入帳金額與既定財務規則。

例：0.01 USD 乘 1/3 的 USD/EUR 再乘 3 的 EUR/GBP，合成匯率為 1，最後得到 0.01 GBP。若中途先產生已量化的 EUR Money，數值會失去，故不可拿那條路徑作為交叉匯率計算。

## 序列化與日期契約

rate JSON v1 保存兩邊 code／scale 與字串 numerator／denominator，不保存 binary float；未知版本／欄位、數字型 ratio 或不合法幣別拒絕。數值正規化後可穩定比較與序列化。率本身尚未量化，業務保存換算結果時仍須另外記錄 `FxRate.roundingPolicy`，不可把這份值型別 JSON 當作完整 Audit。

`FxObservation` 分開保存 rate、短來源識別、實際 `asOf` 業務日期與 `retrievedAt` UTC 瞬間。`rateFor(requested)` 預設只接受同日；使用 last-known 必須明確傳入 `allowEarlier`，較新的觀測永遠不能冒充較舊的請求日。這源自 [provider 初查](provider-feasibility.md)遇到的「HTTP 200 但回覆較早日期」，測試使用合成值。

`allowEarlier` 不代表已通過時效或交易日檢查。允許多舊、週末／假日、來源優先次序與 UI 過期狀態屬於下一層策略；不得因回傳 rate 就移除原觀測日期。來源字串通過格式不代表來源已核實，也沒有建立網路 adapter。

## 驗證

18 項新增案例、連同原有 17 項共 35 項通過：極小小數、反向／交叉比率、三種以上 scale、正負 tie、int64 邊界與溢位、actual principals、跨 scale 拒絕、資源上限、超過 2^53 的 JSON、未知格式與日期策略。另以 11,552 組合成比例／金額核對結果距精確值不超過半個 minor unit，正負結果對稱。靜態分析通過，完整依賴回歸以 PR CI 為準。

待完成：Ledger 跨幣 posting、Conversion reference／Audit 保存、provider 無損解析、取價與過期策略、投資 Decimal、正式資料 migration／備份與 Android 驗收。不把 pure-Dart 測試標為 M1-03 完成。
