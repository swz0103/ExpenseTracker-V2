import 'package:test/test.dart';
import 'package:vault/backup_security.dart';

void main() {
  const policy = PasswordPolicy.standard;

  test('the standard policy: 8 characters at least, not digits alone', () {
    // Provisional numbers (an open decision of the owner).
    expect(policy.minimumLength, 8);
    expect(policy.digitsOnlyAllowed, isFalse);
  });

  test('length is counted in characters after NFC normalization', () {
    expect(policy.check('abcdefg'), PasswordProblem.tooShort);
    expect(policy.check('abcdefgh'), isNull);
    // 7 Chinese characters are 7, not their 21 UTF-8 bytes.
    expect(policy.check('我的記帳本密碼'), PasswordProblem.tooShort);
    expect(policy.check('我的記帳本的密碼'), isNull);
    // "e" + combining acute (2 code points) is 1 after NFC: 7 in all.
    expect(policy.check('caféabc'), PasswordProblem.tooShort);
    expect(policy.check('caféabcd'), isNull);
  });

  test('digits alone are refused, of any script and any length', () {
    expect(policy.check('12345678'), PasswordProblem.allDigits);
    expect(policy.check('123456789012'), PasswordProblem.allDigits);
    // Full-width digits typed on a Chinese keyboard.
    expect(policy.check('１２３４５６７８'), PasswordProblem.allDigits);
    expect(policy.check('1234567a'), isNull);
    // Too short is said first.
    expect(policy.check('123456'), PasswordProblem.tooShort);
  });

  test('a password in use can be checked against today\'s rule', () {
    expect(policy.isBelow('123456'), isTrue);
    expect(policy.isBelow('correct horse'), isFalse);
  });

  test('the codec sets passwords under the policy, unlocks any', () async {
    final codec = KeyringCodec(kdf: PasswordKdf.insecureForTests);
    expect(codec.policy.minimumLength, 8);
    await expectLater(
      codec.create('12345678'),
      throwsA(
        isA<KeyringException>()
            .having((e) => e.error, 'error', KeyringError.weakPassword)
            .having(
              (e) => e.passwordProblem,
              'problem',
              PasswordProblem.allDigits,
            ),
      ),
    );
    // A codec told of a shorter minimum (as the tools are) keeps an old
    // six-digit password, and the standard codec still unlocks it.
    final old = KeyringCodec(
      kdf: PasswordKdf.insecureForTests,
      minimumPassword: 6,
    );
    expect(old.policy.minimumLength, 6);
    final legacy = (await old.create('123456')).keyring;
    final opened = await codec.unlockWithPassword(legacy, '123456');
    expect(opened.keyring.id, legacy.id);
    await expectLater(
      opened.changePassword('654321'),
      throwsA(const KeyringException(KeyringError.weakPassword)),
    );
  });

  test('the backup passphrase rule: 12 characters at least', () {
    const rule = PasswordPolicy.passphrase;
    expect(rule.minimumLength, 12);
    expect(rule.digitsOnlyAllowed, isFalse);
    // 11 characters ("correct hor") are refused, 12 ("correct hors") pass.
    expect(rule.check('correct hor'), PasswordProblem.tooShort);
    expect(rule.check('correct hors'), isNull);
    expect(rule.check('123456789012'), PasswordProblem.allDigits);
    // The password rule is unchanged: 8 characters still do.
    expect(PasswordPolicy.standard.check('correct '), isNull);
  });

  test('the codec sets passphrases under the stricter rule', () async {
    final codec = KeyringCodec(kdf: PasswordKdf.insecureForTests);
    expect(codec.passphrasePolicy.minimumLength, 12);
    final keys = await codec.create('correct horse');
    await expectLater(
      keys.unlocked.setPassphrase('correct hor'),
      throwsA(
        isA<KeyringException>()
            .having((e) => e.error, 'error', KeyringError.weakPassword)
            .having(
              (e) => e.passwordProblem,
              'problem',
              PasswordProblem.tooShort,
            )
            .having((e) => e.minimumLength, 'minimum', 12),
      ),
    );
    // A password refused says its own minimum.
    await expectLater(
      keys.unlocked.changePassword('short'),
      throwsA(
        isA<KeyringException>().having((e) => e.minimumLength, 'minimum', 8),
      ),
    );
    // An 11-character passphrase set before the rule (as the tools still
    // may) keeps opening with today's codec.
    final old = KeyringCodec(
      kdf: PasswordKdf.insecureForTests,
      minimumPassword: 6,
    );
    expect(old.passphrasePolicy.minimumLength, 6);
    final legacy = await (await old.create('correct horse')).unlocked
        .setPassphrase('correct hor');
    final opened = await codec.unlockWithPassphrase(
      Keyring.parse(legacy.keyring.exported.encode()),
      'correct hor',
    );
    expect(opened.databaseKey, legacy.databaseKey);
  });
}
