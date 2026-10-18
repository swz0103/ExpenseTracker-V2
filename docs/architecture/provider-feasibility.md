# ADR-06：雲端備份、行情與匯率來源

狀態：已決定（2026-10-04）。原則：個人日常使用，每種外部資料只用**一個免費、免帳號**的來源，不做備援與交叉核對；查不到就明說查不到，不拿舊值或 1:1 頂替。完整的評估過程在 git 歷史。

## 備份：Google Drive（`drive.file`）

- 只申請 `drive.file`：App 只能看到自己建立的檔案。不用 `appDataFolder`，因為使用者無法從 Drive 介面取回檔案。
- 每次備份是一個獨立、不覆寫的加密檔；保留政策由 App 自己管理（日、週、月分代）。
- 上傳可續傳；完成後核對大小與 SHA-256 才算成功。下載分段並核對，還原時仍以備份本身的加密驗證為準。
- token 不存在 App 裡，撤銷登入只會停掉雲端工作，本機記帳照常。
- Google 端設定（Android OAuth client、簽章 SHA-1）見 [Google Drive 設定](../delivery/google-drive-setup.md)。

## 台股：TWSE 與 TPEx 每日收盤

- 上市：`openapi.twse.com.tw/v1/exchangeReport/STOCK_DAY_ALL`；上櫃：`www.tpex.org.tw/openapi/v1/tpex_mainboard_daily_close_quotes`。都是政府資料開放授權第 1 版，畫面上要標示來源。
- 只收一般股票與 ETF 的代號；民國日期嚴格驗證；「--」是沒有成交，不是 0；價格保留十進位文字。
- 只有最新收盤，不提供歷史或盤中價。存股、市值估算看收盤價就夠。

**不做盤中行情**：證交所的即時資訊要簽約付費；免帳號的來源（證交所網頁內部 API、Yahoo）都是非正式介面，隨時可能變動。Fugle、Twelve Data 要申請 API key，對個人記帳沒有必要。

## 匯率：臺灣銀行牌告

- `rate.bot.com.tw/xrt/flcsv/0/day`，每個幣別有現金與即期的買入、賣出價。
- 外幣帳戶以「即期買入」估值，也就是把外幣賣回給銀行可以拿到的台幣。
- 舊版 App 也用這個來源，又是實際換匯時會看的價格。實際換匯的金額以使用者記下的為準，牌告只用來估值。

**不再使用** ECB、央行（CBC）、Frankfurter：它們是參考匯率，不是銀行實際成交的價格，還需要多來源路由。
