# tooling/mutation：變異測試

> 把帳本的計算一次改壞一個小地方（`>=` 改成 `>`、少一天、拿掉「以今日為準」的過濾…），看測試有沒有抓到。沒抓到的（SURVIVED）就是測試的缺口。

最早是審查 11 的一次性腳本，這裡是可以重跑的版本；每晚由 `.github/workflows/mutation.yml` 跑一次。

## 檔案

| 檔案 | 用途 |
| --- | --- |
| `mutate.py` | 執行器：套用一個變異、跑那一區的測試、還原檔案 |
| `mutants.py` | 變異清單：`(id, 區, 檔案, 原文, 改成)`，原文必須在檔案裡恰好出現一次；`AREAS` 是每一區跑哪些測試；`EQUIVALENT` 是改了也不會改變行為的變異（不計分，要寫理由） |
| `baseline.json` | 每一區的最低分數（整數百分比），**只准升高** |
| `test_mutate.py` | 執行器本身的測試（不需要 Dart） |

## 結果怎麼算

- `KILLED`：有測試失敗（或逾時）。
- `SURVIVED`：測試全過，沒有測試注意到這個改動。
- `EQUIVALENT`：列在 `mutants.EQUIVALENT`，不計分。
- `INVALID`：原文找不到或不只一處，或改了編譯不過；不計分，但會列出來——程式改了之後要把那一行改指向新的程式。

分數 = KILLED ÷（KILLED + SURVIVED），無條件捨去成整數百分比。

## 怎麼跑

執行器會**直接改檔案**（每個變異跑完就還原），所以一律在 `git archive` 的複本上跑，不要在 checkout 裡跑；根目錄有 `.git` 時會拒絕（除非加 `--in-place`）。

```
copy=$(mktemp -d)
git archive HEAD | tar -x -C "$copy"
python3 "$copy/tooling/mutation/mutate.py" --areas report,budget --out /tmp/report.tsv
```

- `--areas core,trade,...` 或 `all`；區名見 `mutants.AREAS`。
- `--out FILE`：結果一行一個變異，邊跑邊寫；**已經在檔案裡的變異不會重跑**，中斷後用同一個 `--out` 再跑就會接著跑。
- `--ids report-14,report-23` 或一個列了 id 的檔案：只跑這些。
- `--wide`：每個變異改跑 `AREAS_WIDE` 那一大組 app 測試，用來確認「這一區的測試沒抓到，但別處有抓到」。
- `--check`：任何一區低於 `baseline.json` 就失敗（退出碼 1）；高於時提示更新。
- `--update`：把 `baseline.json` 提高到這次的分數，**不會調低**。

開始變異前，每一區的測試會先原樣跑一次；原本就失敗時直接停止（不然每個變異都會算成 KILLED）。

執行器的測試：`python3 tooling/mutation/test_mutate.py`。

## 新增或修改變異

在 `mutants.py` 對應的區段加一行 `M('區', 檔案, '原文', '改成')`。id 依區內順序編號，所以**只往後加**，不要在中間插入（會讓之前的結果對不上）；程式改了、原文不見了，就在原位置把原文改成新的對應寫法，保留 id。

一個變異存活時，先判斷：

1. 真的缺測試 → 補一個行為測試（字面期望值，算式寫在註解）。
2. 改了也不會改變行為 → 加進 `EQUIVALENT`，寫清楚為什麼。
3. 在別處的測試抓得到（`--wide` 才 KILLED）→ 最好還是在那一區補一個測試。

補完測試後，在複本上用 `--ids` 重跑那些變異，再用 `--update` 提高基線。
