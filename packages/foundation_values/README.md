# Foundation Values

純 Dart 共用值型別；不依賴 Flutter、資料庫或其他業務套件。目前包含 Money／Currency、PublicId／WorkspaceId／OperationId／OperationKey、BusinessDate／UtcInstant，以及 FxRate／FxObservation。

Money 使用 BigInt 做運算並檢查 signed 64-bit 保存範圍；JSON 的 minorUnits 為字串。手動輸入超過精度拒絕；計算結果才可透過 quantize 採 half-away-from-zero-v1。分攤採 truncate-last-remainder-v1，前 n−1 份朝零截斷，最後一份吸收尾差。

Currency 的三位大寫代碼只是 denomination 格式，不代表已核實 ISO 清單或支援市場。scale 工程上限 18，輸入文字上限 128 字元，單次分攤上限 10,000 份；超出拒絕，不靜默調整。正式資料入口需由版本化 reference data 提供幣別與 scale。股數／成本的通用 Decimal 尚待另一批實作。

FxRate 用正 BigInt ratio 保存精確匯率，十進位解析／反向／交叉換算不先取捨；最後 convert 才沿 Money 的政策量化與檢查溢位。FxObservation 保存實際報價日期與取得時間，預設拒絕以舊值冒充當日值。JSON v1 只用字串保存分子分母，未知必要格式拒絕。詳見[精確 FX 契約](../../docs/architecture/exact-fx-values.md)，不是行情供應商或 Ledger 跨幣入帳實作。

```sh
dart pub get --enforce-lockfile
dart analyze
dart test --reporter expanded
```

對應 [VAL-01～05](../../docs/foundation/foundation-acceptance.md)，涵蓋精確加總、幣別／scale 不相容、正負分攤、量化、溢位及 JSON round trip。此套件通過不等於 Ledger、Android 或備份 gate 通過。

運算依據：[Dart BigInt](https://api.dart.dev/dart-core/BigInt-class.html)。

身份產生使用 [uuid 4.6.0](https://pub.dev/packages/uuid/versions/4.6.0)，接收端額外強制 UUID v7 與 RFC variant，正規化為小寫。OperationKey 包含 workspace；相同意圖重試須保留 ID，不可每次自動產生新 ID。生成樣本無重複不代表數學上不會碰撞，正式儲存仍需唯一鍵。

BusinessDate 接受 0001～9999 的有效日曆日期，不附帶時區，不自動轉午夜。UtcInstant 嚴格文字格式只接受 Z 與最多六位小數；其他 offset 的輸入須明確解析後透過 DateTime 建構轉 UTC。無效日期／時間拒絕，不讓 DateTime 的自動進位掩蓋錯誤。IANA 時區資料與事件的當地時間 context 留待業務資料模型接入，沒有宣稱完整時區規則引擎。

## 精確計算邊界

Money.quantizeRatio 以主要幣別單位的有理數作最後取位，與 Money.quantize、FxRate.convert 共用 half-away-from-zero-v1。只接受正分母，分子／分母各限 4,096 bits，結果仍受有號 64-bit minor units 限制。手動輸入仍用嚴格 Money.parse；此接口不改 JSON 格式或匯率資料來源。
