# 精確匯率值型別

範圍：`foundation_values` 的 `FxRate`，跨幣轉帳、外幣估值與牌告匯率都用它。

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

報價日期由使用的地方保存：牌告匯率的 `BankRates.asOf`，以及入帳時記下的台幣約當（`PostingMetadata.homeValue`）。
