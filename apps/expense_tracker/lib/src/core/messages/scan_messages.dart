import '../platform/scan.dart';

/// What 掃發票 says of the scanner itself: the wait for it, and each way
/// it can fail, with what to do next.
abstract final class ScanMessages {
  /// The step named in the error log.
  static const step = '掃發票';

  /// Said while the phone fetches the scanner, before it can open.
  static const preparing = '第一次使用要先下載掃描器，請稍候…';

  /// What a scan that did not work says, and what to do about it.
  static String failure(ScanFailure failure) => switch (failure) {
    ScanFailure.unavailable =>
      '無法下載掃描器。請確認手機有網路、還有儲存空間，並且 Google Play 服務已開啟並更新，'
          '再按一次「掃發票」；也可以直接手動輸入這張發票。',
    ScanFailure.busy => '掃描器已經開著',
    ScanFailure.failed => '沒有掃到。請再按一次「掃發票」，或直接手動輸入這張發票。',
  };
}
