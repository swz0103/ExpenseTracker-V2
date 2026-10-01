# Android 實機驗證紀錄

日期：2026-09-27。裝置：Samsung SM-A5660，Android 16／API 36，ARM64。只使用合成 fixture，App ID 為 `dev.expensetracker.prototype.android_foundation`，沒有正式發版或真實帳本。

對應[Android 原型](../../prototypes/android_foundation/README.md)、[階段 1](implementation-plan.md#階段-1驗證地基再建立正式開發基線)、[KEY-01～08](../foundation/storage-lifecycle-contract.md#8-必須執行的驗收)與 [BACKUP-01～04](../foundation/foundation-acceptance.md#資料演進與保護)。此紀錄僅標示實際執行的子集，不把一台裝置的結果擴張成完整平台認證。

## 已執行的基本與乾淨還原

- `device_probe_test.dart`：真實安全儲存寫入／讀回，SQLCipher 建庫／關閉重開，100+20−5=115，兩個還原目標的獨立 slot、完整 snapshot 與 receipt replay；同程序重複兩次通過。
- `clean_restore_test.dart`，password：備份從上述實機帳本匯出，保存到電腦後只清除原型 App 的資料；重新準備 envelope、預期合成 snapshot 與密碼，未提供來源 DB、來源 key 或救援文字。完整還原、115 餘額與重送不重複入帳通過。
- password 新程序重開：保留 App 資料後再啟動測試；重新讀安全儲存並核對相同 generation／slot、完整 snapshot、receipt。電腦亦比較兩次結果身份完全相同。
- recovery：再次清除原型 App 資料，僅提供同份 envelope、預期合成 snapshot 及救援文字；不提供密碼。完整還原與 receipt replay 通過，generation／slot 與 password 案例不同。
- recovery 新程序重開：再次啟動後完整資料、115 餘額、receipt replay 與前次 generation／slot 均一致，通過。

每次乾淨還原先確認來源 key 欄位不存在、原 `foundation_fixture_v1` 目錄不存在；輸入目錄恰好只有三個指定檔案。預期 snapshot 是公開固定測試資料，用於比對，不是還原所需的隱藏來源。

這是同一手機上清除 App 資料後的乾淨環境，不是第二台硬體；不同裝置、OS 重開機及所有廠商的 Keystore 行為仍未驗證。

## 平台故障子集

`platform_failure_test.dart` 的四項實機測試全部通過：

- 平台 slot 不存在時拒絕且不補 key；已存在的 slot 再次建立會失敗，原值不變；未知格式讀取失敗而原值保留。
- 真實加密檔存在但指定平台欄位缺 key 時，KeyAccess 拒絕，沒有新 key，DB bytes 不變。
- 加密 v1 fixture 升級到新增欄位後注入例外，schema、版本及七張權威表完整回滾；再次使用平台讀回的 key 可升級至 v2，餘額 115、外鍵一致。
- 在新增索引後注入例外亦完整回滾，可再試成功。

後兩項是裝置上的 exception rollback，不是程序被 OS 中止或斷電；先前 host process-exit 證據不混算成裝置中止驗證。新增入口的靜態分析、架構邊界掃描及 17 項既有 host 金鑰測試亦通過。

## 測試工具與失敗紀錄

Flutter 3.47.5 的 integration test 預設會在測試結束後 uninstall App。最初兩次通過只算同程序基本案例，不能據此證明跨程序持久化。後續均使用 `--no-uninstall`，由測試 orchestration 明確決定何時只清除這個 fixture App。

第一次 password 乾淨還原在 suite 載入前出現 `Connection closed before test suite loaded`，未執行到還原；輸入檔案保持完整。重新啟動後通過，失敗的啟動不列為驗收通過，也不據此宣稱已找出根因。

手機上的測試憑證檔只限合成 fixture；沒有輸出來源裝置的 DB key。正式產品不得以這種明文測試檔保存密碼或救援文字。操作只清除指定 debug App，不清理其他 App、個人資料或整台手機。

## 重現入口

從 `prototypes/android_foundation` 執行，裝置 ID 由本機連線清單取得，不提交到 repository：

```powershell
flutter test integration_test/device_probe_test.dart -d <device> --no-uninstall
flutter test integration_test/clean_restore_test.dart -d <device> --no-uninstall --dart-define=PROBE_MODE=password
flutter test integration_test/clean_restore_test.dart -d <device> --no-uninstall --dart-define=PROBE_MODE=recovery
flutter test integration_test/platform_failure_test.dart -d <device> --no-uninstall
```

乾淨案例需要先保存原型輸出的 `files/probe_export`，核對合成 envelope／expected JSON；只清除上述 fixture App 後，用 `run-as` 將 envelope.json、credential.txt、expected.json 放入其 `files/clean_input`，每次只提供一種 credential。要驗證跨程序重開時，不再清除資料，重跑同模式並比對 `files/clean_result.json` 的非秘密身份。

平台 migration 案例需將 repository 中固定的 [v1.sql](../../prototypes/modular_persistence/test/fixtures/v1.sql) 放到此 App 的 `files/fixture_input/v1.sql`；不可換成使用者匯入的任意 SQL。測試每次新建獨立 fixture DB／slot，不修改乾淨還原目標。

## 尚未通過的完整 gate

目前結果沒有覆蓋真實斷電／磁碟滿、OS 強制中止每個持久化邊界、完整升級前備份協調、正式憑證延續、金鑰清理輪替、系統備份／截圖限制的所有裝置行為或效能長期資料集。Architecture Baseline 維持 rc1；完整 M1／M2／M3 仍未交付。
