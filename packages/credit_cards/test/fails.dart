import 'package:credit_cards/credit_cards.dart';
import 'package:test/test.dart';

/// Throws a [CreditCardException] with exactly [code], so a test fails
/// when a different rule rejects the input.
Matcher fails(CreditCardError code) => throwsA(
  isA<CreditCardException>().having((error) => error.code, 'code', code),
);
