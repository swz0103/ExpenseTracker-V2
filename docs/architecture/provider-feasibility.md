# ADR-06：雲端備份、行情與 FX 可行性

核對日期：2026-09-27。狀態：候選路線與公開端點初查完成，**ADR-06 尚未結案**；沒有新增登入授權、申請 key、付費或上傳帳務。依據 [RC-08](architecture-baseline-v1.0-rc1.md#rc-08)、[RC-14](architecture-baseline-v1.0-rc1.md#rc-14)、[Q056](full-vision-baseline.md#q056)、[Q018](full-vision-baseline.md#q018)。本文件細化 adapter 方向，不增加首批 UI 或改變 M1／M2／M3 順序。

## 備份：Google Drive v3／drive.file 作為首個候選

選擇 app 建立的可見資料夾與加密備份檔，使用 `drive.file` 的逐檔權限；不要求整個雲端硬碟讀寫權限。官方列它為 non-sensitive，仍需設定 OAuth 與適用的基本驗證，不能把 non-sensitive 解讀為免登入／免審查。[官方 scope 文件](https://developers.google.com/workspace/drive/api/guides/api-specific-auth)。

另一選擇 `appDataFolder` 只供 app 存取，使用者不能從 Drive UI 直接取檔；從 My Drive 移除 app 或手動刪 app data 會失去該資料夾。基於可攜還原需求，本輪不採它作唯一備份位置。本機匯出仍必做，雲端也不是同步。[官方 app data 說明](https://developers.google.com/workspace/drive/api/guides/appdata)。

接入契約（待 M2 實作）：

- 每次備份保存獨立、不可覆寫的 envelope blob；歷史清單由本 app 管理，不把供應商 revision 等同產品的保留政策。
- 上傳前保存 job／備份 ID、內容摘要與預先取得的 Drive file ID。逾時重試同一個 ID；遇 409 先讀回核對，不直接視為成功或換 ID 重複上傳。預產 ID 的 blob 建檔與安全重試有官方支援。[建立檔案](https://developers.google.com/workspace/drive/api/guides/create-file)、[上傳協定](https://developers.google.com/workspace/drive/api/guides/manage-uploads)。
- 只有完整上傳與內容核對後更新「最後成功時間」。下載後仍走 envelope／snapshot／世代驗證，remote checksum 不取代密碼學驗證。
- OAuth token 與資料庫 key 分開保存；撤銷登入只停雲端 job，本機記帳／備份可繼續。不能在 log 記 token、密碼、救援文字或帳務內容。
- 401／權限拒絕待重新授權；403 quota／429 依錯誤原因退避；5xx／逾時結果可能未定，透過原 file ID 核對。使用者移動或刪除檔案時明示雲端狀態，不刪本機帳本。

費用不能寫成永久免費：官方已列 2026-05-01 起的新專案 quota 模型及每日 billing threshold，並說明後續計費細節會提前公告。雲端儲存容量也另有帳戶限制；正式啟用前核對該專案實際 quota／billing。[Drive 使用限制](https://developers.google.com/workspace/drive/api/guides/limits)。本輪未建立 Cloud project 或 billing account。

未完成：Android OAuth client／簽章與 consent 設定、撤權／換帳號、真實上下載、背景執行與全新安裝取得同一備份。需要使用者的新授權時再提供具體設定步驟，不拿文件閱讀冒充已連線。

## 台股：TWSE 與 TPEx 分開處理盤後資料

上市候選為 `https://openapi.twse.com.tw/v1/exchangeReport/STOCK_DAY_ALL`；上櫃候選為 `https://www.tpex.org.tw/openapi/v1/tpex_mainboard_daily_close_quotes`。本機各一次 GET 均 HTTP 200，前者 1,380 列、後者 11,660 列，抽查首列日期皆 `1150924`；這是觀測時點的資料，不代表每天筆數固定或完整涵蓋歷史。[TWSE 官方端點](https://openapi.twse.com.tw/)、[TPEx 官方 schema](https://www.tpex.org.tw/openapi/swagger.json)。

對應政府資料集均標示日更新與免費、政府資料開放授權條款第 1 版；產品接入須保存來源與顯名。不能延伸推論所有交易所即時或歷史商品都採同一授權。[上市日成交資料集](https://data.gov.tw/dataset/11549)、[上櫃收盤資料集](https://data.gov.tw/dataset/11371)、[授權原文](https://data.gov.tw/license)。

工程限制：代號必須保留字串與前導零，以市場＋外部代號對應 Instrument；TPEx 集合包含其他商品，不能因有一列報價就開放權證或 ETN。民國日期轉換須嚴格驗證，無成交符號／空價是缺值，不是 0。價格保存十進位文字，記錄實際交易日、取得時間與調整類型；最新盤後集合不能冒充任意歷史日查詢、即時價格或 corporate-action 資料。

### 1–5 分鐘行情增補（2026-09-30）

使用者將股價更新目標改為 1–5 分鐘。官方 TWSE／TPEx 最新收盤仍是日終基準，不能滿足盤中需求。首個台股盤中 adapter 選 Fugle：官方文件提供即時 quote 及 `1`、`3`、`5` 分鐘等 intraday candles；基本會員方案目前標示 60 calls/minute 與 5 個 WebSocket 訂閱，需 API key。[日內 K 線契約](https://developer.fugle.tw/docs/data/http-api/intraday/candles/)；[驗證與端點](https://developer.fugle.tw/docs/data/http-api/getting-started/)；[方案與額度](https://developer.fugle.tw/docs/pricing/)。

已完成 REST 1／5 分鐘核心與 provider registry 接入，但只使用 fixture。App 不內嵌 key；後續由安全儲存提供，並需使用者註冊後做真實帳號驗證。免費個人方案不自動等於可公開散布行情，若 App 對外發布仍須另核對顯示／再散布授權。美股候選 Twelve Data 的免費方案目前標示 800 requests/day、8 trial WebSocket credits 與即時美股，但台灣屬 global trial／更高方案範圍，因此不拿它取代 Fugle 台股來源。[Twelve Data 個人方案](https://twelvedata.com/pricing)。Alpha Vantage 1／5 分鐘即時/延遲 intraday 官方文件列為 premium，本輪不作首選。[Alpha Vantage intraday](https://www.alphavantage.co/documentation/)。

### 免帳號來源重新決策（2026-10-01）

正式 App 預設不再註冊 Fugle／Twelve Data，也不顯示 API key 設定；兩個 adapter 只留作日後經使用者選擇的可選能力。TWSE 官方說明即時交易資訊需直接申請或透過已簽約資訊廠商取得，並列有授權與資訊費；延遲交易資訊的申請使用者同樣須簽訂使用契約，畫面還必須明示至少延遲二十分鐘。[TWSE 即時交易資訊](https://wwwc.twse.com.tw/zh/products/information/real-time.html)、[交易資訊使用規範](https://wwwc.twse.com.tw/zh/products/information/use.html)。TPEx 也將即時交易資訊列為需申請並簽約的資訊產品。[TPEx 資訊購買](https://www.tpex.org.tw/web/service/info_service/info_service.php?l=zh-tw)。

因此目前沒有選定同時符合免帳號、1–5 分鐘、正式穩定 API 與可供 App 使用授權的台股來源。官方 TWSE／TPEx OpenAPI 繼續只作日終基準；不使用未文件化的網站內部 JSON、HTML 抓取或把重複日終輪詢標成即時。1–5 分鐘 controller、路由、退避與提醒仍保留 provider-neutral，待未來確認合規來源即可接入。

## FX：Frankfurter v2，明確指定資料來源

候選路由：USD/TWD 先評估 RBA；EUR/USD、USD/JPY 先評估 ECB。傳 `providers` 並保存實際回覆日期。官方 v2 不需 API key，預設會混合多來源；本案選擇明確來源來維持可追溯性。[官方 v2 契約](https://frankfurter.dev/)。

本機公開 GET 的觀測：查詢日均為 `2026-09-25`。RBA USD/TWD、ECB EUR/USD 與 USD/JPY 均回覆同日；但 CBC USD/TWD 回覆 **2026-08-31**。未限定來源的 USD/TWD 回覆包含不同觀測日期的多個供應者。這證明 HTTP 200 與請求日期本身不能保證報價屬於該日；不能只把 request date 寫進估值紀錄。

接入時區分 exact-date、last-known 與 missing。使用者確認的實際成交兩邊金額優先，provider 更新不能改寫已入帳 FX。來源不足或無當日值就回報缺值／有日期的舊估值；本輪沒有宣稱跨 provider 自動 fallback 已完成。

Frankfurter 的軟體 MIT 不等於所有來源資料同一授權；官方也明示資料可能延遲、缺漏或修正。[資料權利邊界](https://frankfurter.dev/license/)。RBA 金融資料另有條款與第三方資料例外；ECB 要求來源標示，衍生計算應說明。本案保存 provider／原始日期／衍生方式，不將換算結果冒稱銀行成交報價。[RBA](https://www.rba.gov.au/copyright/)、[ECB](https://www.ecb.europa.eu/services/disclaimer/html/index.en.html)。正式 adapter 前仍需逐項確認所用 dataset 的上游來源與接入方式。

2026-10-01 實作狀態：正式 registry 已加入免 key 的 Frankfurter v2 direct-pair adapter，作為 ECB／CBC 之外的跨幣 fallback。回傳日期、base、quote、rate 與欄位數均核對；價格從原始十進位文字精確解析，未來日期、過期、缺值、限流及錯誤 payload fail closed。這是中央銀行參考匯率，不是交易即時匯率，也不改寫任何已入帳換匯。

## 美股：Alpha Vantage 日終候選，尚未開通

官方 GLOBAL_QUOTE 預設為日終資料；即時／15 分鐘延遲另有 premium 路徑。免費大部分資料集目前限制每日 25 requests，不能假設所有持倉可高頻更新。[API 文件](https://www.alphavantage.co/documentation/)、[額度說明](https://www.alphavantage.co/support/)。

保留作個人用途日終候選，未申請或使用新 key，也未把示範資料視為本人帳戶可用性。免費 key 的取得涉及 EULA；對外提供／商業用途需另核對授權，不能把私人專案的條件推到公開 App。[供應商條款](https://www.alphavantage.co/terms_of_service/)。若額度或授權不合需求，再提出具體替代方案與費用，不先繞過限制抓網頁。

## 下一個可實作邊界

先完成與 provider 無關的精確匯率值型別、取得日與來源保存契約，再用合成 fixture 驗證 adapter 的缺值、過期、錯幣別、限流與來源切換行為。Domain 不接 HTTP、OAuth 或供應商 JSON，App 未啟用的行情／雲端入口繼續隱藏。

ADR-06 的結案仍需：實際授權後 Drive 雙路乾淨還原、美股有效憑證與支援股票／ETF 清單、台股／FX 完整契約測試、來源與顯名／費用核對、離線／限流／撤權處理。公開端點 smoke check 只支持候選可行性，不代表上述能力 verified。
