# market_adapters

`market_data` 的 dart:io 傳輸層：只連 TWSE、TPEx、臺灣銀行三個主機的 HTTPS，不跟隨轉址，每個階段 10 秒逾時，回應有大小上限。
