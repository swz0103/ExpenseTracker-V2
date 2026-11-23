import 'dart:io';

import 'package:core/app_core.dart' show FixedClock;
import 'package:core/foundation_values.dart' show UtcInstant;
import 'package:expense_tracker/src/core/diagnostics/error_log.dart';
import 'package:expense_tracker/src/core/platform/startup.dart';
import 'package:expense_tracker/src/core/time/app_clock.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_vault.dart';

const _password = 'correct horse battery';
const _wrong = KeyringException(KeyringError.wrongSecret);

/// Stands in for an Android Keystore key behind the fingerprint prompt:
/// [answer] is how the next prompt ends.
final class PromptedKey implements DeviceKeyWrapper {
  /// Null confirms; otherwise the prompt ends with this.
  Object? answer;
  var prompts = 0;
  final _secrets = <String, List<int>>{};

  /// The person turned the prompt down (改用密碼, or back), as
  /// `DeviceKeyBlob.refusal` names it.
  static final declined = PlatformException(code: 'declined');

  /// The prompt ended another way (too many tries, the phone's own stop).
  static final cancelled = PlatformException(code: 'cancelled');

  void _ask() {
    prompts++;
    if (answer case final error?) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
  }

  @override
  Future<List<int>> wrap(List<int> secret, List<int> context) async {
    _ask();
    final handle = 'blob-${_secrets.length}';
    _secrets[handle] = List.of(secret);
    return handle.codeUnits;
  }

  @override
  Future<List<int>> unwrap(List<int> wrapped, List<int> context) async {
    _ask();
    final secret = _secrets[String.fromCharCodes(wrapped)];
    if (secret == null) throw StateError('not this device');
    return secret;
  }
}

/// The lock gate's part of [Startup] (work package 3.1): wrong passwords
/// and recovery codes slowed down, the fingerprint turned on and off and
/// turned down without a fault, and a restore from settings given up.
void startupGateTests() {
  late Directory directory;
  late LedgerVault vault;

  /// The clock the app reads; a test moves it instead of waiting.
  late FixedClock clock;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('startup-gate-');
    vault = LedgerVault(
      directory,
      codec: KeyringCodec(kdf: PasswordKdf.insecureForTests),
    );
    clock = FixedClock(UtcInstant(DateTime.utc(2026, 11, 23, 9)));
    AppClock.use(clock);
  });

  tearDown(() {
    AppClock.reset();
    directory.deleteSync(recursive: true);
  });

  /// A ledger with a password, locked, as a new start of the app finds it.
  Future<Startup> locked({DeviceUnlock? device}) async {
    final first = Startup(vault, device: device);
    await first.setUp(_password);
    first.lock();
    return Startup(vault, device: device);
  }

  Future<void> wrongPasswords(Startup startup, int times) async {
    for (var i = 0; i < times; i++) {
      await expectLater(
        startup.unlockWithPassword('wrong password $i'),
        throwsA(_wrong),
      );
    }
  }

  Matcher delayedBy(Duration wait) =>
      throwsA(isA<UnlockDelayed>().having((e) => e.wait, 'wait', wait));

  group('wrong passwords (SEC-03)', () {
    test('four are refused at once; after the fifth the right password is '
        'not tried for 30 seconds, then opens', () async {
      final startup = await locked();
      await wrongPasswords(startup, 4);
      expect(await startup.unlockWait(), Duration.zero);
      await wrongPasswords(startup, 1);
      expect(await startup.unlockWait(), const Duration(seconds: 30));
      await expectLater(
        startup.unlockWithPassword(_password),
        delayedBy(const Duration(seconds: 30)),
      );
      expect(startup.state, isA<Locked>());
      clock.advance(const Duration(seconds: 29));
      await expectLater(
        startup.unlockWithPassword(_password),
        delayedBy(const Duration(seconds: 1)),
      );
      clock.advance(const Duration(seconds: 1));
      await startup.unlockWithPassword(_password);
      expect(startup.state, isA<Ready>());
      startup.lock();
    });

    test('a try refused for the wait is not counted as a wrong one', () async {
      final startup = await locked();
      await wrongPasswords(startup, 5);
      for (var i = 0; i < 20; i++) {
        await expectLater(
          startup.unlockWithPassword('guess $i'),
          delayedBy(const Duration(seconds: 30)),
        );
      }
      clock.advance(const Duration(seconds: 30));
      // The sixth wrong one: a minute, not what 25 would cost.
      await wrongPasswords(startup, 1);
      expect(await startup.unlockWait(), const Duration(minutes: 1));
    });

    test('closing the app does not start the count again', () async {
      final startup = await locked();
      await wrongPasswords(startup, 5);
      final restarted = Startup(vault);
      expect(await restarted.unlockWait(), const Duration(seconds: 30));
      await expectLater(
        restarted.unlockWithPassword(_password),
        delayedBy(const Duration(seconds: 30)),
      );
      expect(restarted.state, isA<Locked>());
    });

    test('the right password starts the count again', () async {
      final startup = await locked();
      await wrongPasswords(startup, 4);
      await startup.unlockWithPassword(_password);
      startup.lock();
      // Four more are free again.
      await wrongPasswords(startup, 4);
      expect(await startup.unlockWait(), Duration.zero);
      expect(
        File('${directory.path}/unlock-attempts.json').existsSync(),
        isTrue,
        reason: 'kept beside the keyring, not in the book',
      );
    });

    test('the clock set back does not shorten the wait', () async {
      final startup = await locked();
      await wrongPasswords(startup, 5);
      clock.advance(const Duration(seconds: 20));
      clock.advance(-const Duration(days: 2));
      // Not the 10 s that were left: the whole 30 s again.
      await expectLater(
        startup.unlockWithPassword(_password),
        delayedBy(const Duration(seconds: 30)),
      );
    });

    test('wrong recovery codes are counted with wrong passwords, and the '
        'wait holds for both', () async {
      final first = Startup(vault);
      final code = await first.setUp(_password);
      first.lock();
      final startup = Startup(vault);
      await wrongPasswords(startup, 3);
      // A code of the right shape that is not this ledger's.
      final other = await KeyringCodec(kdf: PasswordKdf.insecureForTests)
          .create(_password);
      for (var i = 0; i < 2; i++) {
        await expectLater(
          startup.unlockWithRecovery(other.recoveryCode),
          throwsA(_wrong),
        );
      }
      // 3 passwords + 2 codes = 5 wrong.
      expect(await startup.unlockWait(), const Duration(seconds: 30));
      await expectLater(
        startup.unlockWithRecovery(code),
        delayedBy(const Duration(seconds: 30)),
      );
      await expectLater(
        startup.unlockWithPassword(_password),
        delayedBy(const Duration(seconds: 30)),
      );
      clock.advance(const Duration(seconds: 30));
      await startup.unlockWithRecovery(code);
      expect(startup.state, isA<Ready>());
      startup.lock();
    });

    test('a code typed in the wrong shape is not a guess', () async {
      final startup = await locked();
      for (var i = 0; i < 8; i++) {
        await expectLater(
          startup.unlockWithRecovery('not a code'),
          throwsA(const KeyringException(KeyringError.invalidFormat)),
        );
      }
      expect(await startup.unlockWait(), Duration.zero);
    });

    test(
      'the fingerprint opens the ledger during the wait, and ends it',
      () async {
        final key = PromptedKey();
        final device = DeviceUnlock('phone', key);
        final startup = await locked(device: device);
        await wrongPasswords(startup, 5);
        expect(await startup.unlockWithDevice(), isTrue);
        expect(startup.state, isA<Ready>());
        startup.lock();
        expect(await startup.unlockWait(), Duration.zero);
      },
    );
  });

  group('the fingerprint (F39, F40, F52)', () {
    late PromptedKey key;
    late DeviceUnlock device;

    setUp(() {
      key = PromptedKey();
      device = DeviceUnlock('phone', key);
    });

    int noted() => ErrorLog.instance.entries.length;

    test('turned down on the lock screen, nothing is thrown or noted, and '
        'the ledger stays locked', () async {
      final startup = await locked(device: device);
      final before = noted();
      key.answer = PromptedKey.declined;
      expect(await startup.unlockWithDevice(), isFalse);
      expect(startup.state, isA<Locked>());
      expect(noted(), before);
    });

    test('a prompt that ends any other way is a failure', () async {
      final startup = await locked(device: device);
      key.answer = PromptedKey.cancelled;
      await expectLater(startup.unlockWithDevice(), throwsA(_wrong));
      expect(startup.state, isA<Locked>());
    });

    test('turned down when offered after the password, the ledger opens, '
        'nothing is noted, and it is not offered again', () async {
      final first = Startup(vault);
      await first.setUp(_password);
      first.lock();
      final before = noted();
      key.answer = PromptedKey.declined;
      final startup = Startup(vault, device: device);
      await startup.unlockWithPassword(_password);
      expect(startup.state, isA<Ready>());
      expect(startup.deviceEnrolled, isFalse);
      expect(noted(), before, reason: 'a choice, not a fault');
      expect(key.prompts, 1);
      startup.lock();
      await startup.unlockWithPassword(_password);
      expect(key.prompts, 1, reason: 'not asked again');
      startup.lock();
      // Turned off: the lock screen has no fingerprint to ask for.
      expect((startup.state as Locked).deviceUnlock, isFalse);
    });

    test('an enrolment that fails is noted and offered again', () async {
      final first = Startup(vault);
      await first.setUp(_password);
      first.lock();
      final before = noted();
      key.answer = StateError('keystore');
      final startup = Startup(vault, device: device);
      await startup.unlockWithPassword(_password);
      expect(noted(), before + 1);
      startup.lock();
      key.answer = null;
      await startup.unlockWithPassword(_password);
      expect(startup.deviceEnrolled, isTrue);
      startup.lock();
    });

    test('turned off in settings, the fingerprint no longer opens the '
        'ledger and a password unlock does not bring it back', () async {
      final startup = await locked(device: device);
      await startup.unlockWithPassword(_password);
      expect(startup.deviceEnrolled, isTrue);
      await startup.removeDevice();
      expect(startup.deviceEnrolled, isFalse);
      startup.lock();
      expect((startup.state as Locked).deviceUnlock, isFalse);
      expect((startup.state as Locked).askFirst, isFalse);
      final prompts = key.prompts;
      await startup.unlockWithPassword(_password);
      expect(startup.deviceEnrolled, isFalse);
      expect(key.prompts, prompts, reason: 'not offered');
      startup.lock();
    });

    test('turned on in settings, it opens the ledger again', () async {
      final startup = await locked(device: device);
      await startup.unlockWithPassword(_password);
      await startup.removeDevice();
      expect(await startup.enrolDevice(), isTrue);
      expect(startup.deviceEnrolled, isTrue);
      startup.lock();
      final state = startup.state as Locked;
      expect(state.deviceUnlock, isTrue);
      expect(state.askFirst, isTrue);
      expect(await startup.unlockWithDevice(), isTrue);
      startup.lock();
    });

    test('turning it on and turning the prompt down changes nothing and '
        'is no fault', () async {
      final startup = await locked(device: device);
      await startup.unlockWithPassword(_password);
      await startup.removeDevice();
      final before = noted();
      key.answer = PromptedKey.declined;
      expect(await startup.enrolDevice(), isFalse);
      expect(startup.deviceEnrolled, isFalse);
      expect(noted(), before);
      startup.lock();
    });

    test(
      'turning it on that fails is thrown for the settings to say',
      () async {
        final startup = await locked(device: device);
        await startup.unlockWithPassword(_password);
        await startup.removeDevice();
        key.answer = StateError('keystore');
        await expectLater(startup.enrolDevice(), throwsStateError);
        expect(startup.deviceEnrolled, isFalse);
        startup.lock();
      },
    );

    test('a phone without a fingerprint has none enrolled and nothing to '
        'turn off', () async {
      final startup = await locked();
      await startup.unlockWithPassword(_password);
      expect(startup.deviceEnrolled, isFalse);
      await startup.removeDevice();
      await expectLater(startup.enrolDevice(), throwsStateError);
      startup.lock();
    });
  });

  group('a restore from settings given up (F92)', () {
    test('the ledger opens again without the password, once', () async {
      final startup = Startup(vault);
      await startup.setUp(_password);
      final open = (startup.state as Ready).vault;
      open.store.write((w) => w.put('account', 'cash', '{"name":"現金"}'));
      startup.lockToRestore();
      expect(startup.state, isA<Locked>());
      expect(startup.canResume, isTrue);
      await startup.cancelRestore();
      final again = (startup.state as Ready).vault;
      expect(again.store.rows().single.id, 'cash');
      expect(startup.canResume, isFalse);
      expect(startup.takeResumed(), isTrue);
      expect(startup.takeResumed(), isFalse, reason: 'once');
      expect(startup.takeRestore(), isFalse, reason: 'no restore asked for');
      startup.lock();
    });

    test('once the app locks, the keys are let go and the password is asked '
        'for', () async {
      final startup = Startup(vault);
      await startup.setUp(_password);
      startup.lockToRestore();
      startup.lock();
      expect(startup.canResume, isFalse);
      await startup.cancelRestore();
      expect(startup.state, isA<Locked>());
      expect(startup.takeResumed(), isFalse);
    });

    test('a ledger locked the usual way cannot be resumed', () async {
      final startup = Startup(vault);
      await startup.setUp(_password);
      startup.lock();
      expect(startup.canResume, isFalse);
      await startup.cancelRestore();
      expect(startup.state, isA<Locked>());
    });

    test('a ledger opened by its password is not one resumed', () async {
      final startup = await locked();
      await startup.unlockWithPassword(_password);
      expect(startup.takeResumed(), isFalse);
      startup.lock();
    });
  });
}
