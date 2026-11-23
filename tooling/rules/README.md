# tooling/rules：規則檢查器

> 用程式檢查「目標架構與規則」，現有的違規記在 `baseline.json`，只准變少，新增的一律擋下。

## 棘輪（ratchet）是什麼

每條規則數出每個檔案有幾處違規，和 `baseline.json` 比：

- 某檔違規比基線多、或基線沒有的檔出現違規：**失敗**（新增的違規）。
- 某檔違規比基線少：**也失敗**，要求更新基線（清單只准縮短，改善必須留下紀錄）。
- 完全相符：通過。

## 怎麼跑

```
dart pub get --enforce-lockfile            # 在 tooling/rules
dart test                                  # 規則本身的測試
dart run tooling/rules/bin/check.dart      # 在 repo 根目錄，檢查全部規則
dart run tooling/rules/bin/check.dart --rule B3-clock   # 只檢查一條
dart run tooling/rules/bin/check.dart --list            # 列出規則
```

## 怎麼更新基線

修掉違規之後：

```
dart run tooling/rules/bin/check.dart --update
```

`--update` 不會讓任何數字變大。真的要接受新增的違規（例如搬檔案造成的）才加
`--allow-growth`，並在 PR 說明原因。

路徑設定全部在 `lib/src/config.dart`；搬動程式碼時只改那一個檔案。
`owners.yaml` 是「單一來源」登記表（規則 B1）：47 項各自今天由誰負責、目標位置在哪、
狀態是 `owned`／`scattered`／`planned`。

## 規則一覽

| 規則 | 防止什麼 |
| --- | --- |
| `A2-feature-isolation` | 一個功能（`features/X`）引用另一個功能（`features/Y`）的檔案 |
| `A3-ui-no-data` | 功能的畫面碼直接引用 storage、vault、market，或 `app/android`、`core/ledger/persistence` |
| `A4-pure-calc` | `packages/core`、`packages/domain`、`packages/ledger/*` 引用 Flutter、`dart:io`／`ui`／`ffi`，或讀時鐘、`Random` |
| `B2-number-format` | 在格式化層之外自己 `toStringAsFixed`、`int.parse` 等處理數字 |
| `B3-clock` | 在時間層與啟動點之外呼叫 `DateTime.now()`，或手寫 `padLeft(2, '0')` 補零 |
| `B7-status-words` | 狀態用詞（已逾期、超支、已賣光、已入帳、已略過、已結清…，清單在 `config.dart` 的 `statusWords`）寫在狀態呈現檔 `design_system/display/status.dart`／`status_messages.dart` 以外 |
| `B9-text-literals` | 在功能與 `app/` 裡直接寫中文字串，而不是放進 `core/messages` |
| `D2-no-part` | 使用 `part`／`part of` 把一個函式庫拆成多個檔 |
| `E1-catch-handled` | `catch` 之後既沒重拋、也沒記錄，把錯誤吞掉 |
| `C1-tests-exist` | core／domain 的檔案、`packages/ledger/*/lib` 的每個檔案、或某個功能，完全沒有對應的測試檔 |

每條規則的已知誤判寫在原始碼開頭的註解（`lib/src/rules/`）。
