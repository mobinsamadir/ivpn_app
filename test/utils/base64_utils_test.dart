import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/utils/base64_utils.dart';

void main() {
  group('Base64Utils', () {
    group('safeDecode', () {
      test('decodes basic Base64 string correctly', () {
        expect(Base64Utils.safeDecode('SGVsbG8='), equals('Hello'));
      });

      test('decodes URL-safe Base64 string correctly', () {
        // "Hello-World_" encoded in URL-safe base64: SGVsbG8tV29ybGRf
        expect(
          Base64Utils.safeDecode('SGVsbG8tV29ybGRf'),
          equals('Hello-World_'),
        );
      });

      test('decodes Base64 string missing padding', () {
        expect(Base64Utils.safeDecode('SGVsbG8'), equals('Hello'));
      });

      test('decodes Base64 string with whitespace', () {
        expect(Base64Utils.safeDecode('SGVsb G8='), equals('Hello'));
        expect(Base64Utils.safeDecode(' SGVsbG8= \n'), equals('Hello'));
      });

      test('returns empty string for empty input', () {
        expect(Base64Utils.safeDecode(''), equals(''));
      });

      test('handles decoding failure based on returnOriginalOnFail flag', () {
        // Invalid base64 sequence
        const invalidInput = 'NOT_BASE64!@#%';

        // returnOriginalOnFail = false (default) -> returns empty string
        expect(Base64Utils.safeDecode(invalidInput), equals(''));

        // returnOriginalOnFail = true -> returns original input
        expect(
          Base64Utils.safeDecode(invalidInput, returnOriginalOnFail: true),
          equals(invalidInput),
        );
      });

      test(
        'handles Base64 strings that decode to invalid UTF-8 gracefully',
        () {
          // "//79" decodes to bytes [0xff, 0xfe, 0xfd] which is not valid UTF-8
          const invalidUtf8Base64 = '//79';

          expect(Base64Utils.safeDecode(invalidUtf8Base64), equals(''));
          expect(
            Base64Utils.safeDecode(
              invalidUtf8Base64,
              returnOriginalOnFail: true,
            ),
            equals(invalidUtf8Base64),
          );
        },
      );

      test('handles extremely large strings without crashing', () {
        // Create a large repeated string and correctly base64 encode it
        final massiveExpected = 'Hello' * 50000;
        final massiveBase64 = base64Encode(utf8.encode(massiveExpected));

        expect(Base64Utils.safeDecode(massiveBase64), equals(massiveExpected));
      });

      test('handles malformed base64 strings gracefully', () {
        // Odd length strings
        expect(Base64Utils.safeDecode('SGVsbG8==='), equals(''));
        // Characters outside base64 alphabet
        expect(Base64Utils.safeDecode('SGVsbG8^'), equals(''));
      });
    });

    group('isBase64', () {
      test('returns true for valid Base64 string', () {
        expect(
          Base64Utils.isBase64('SGVsbG8gV29ybGQ='),
          isTrue,
        ); // "Hello World"
      });

      test('returns false for invalid Base64 string', () {
        expect(Base64Utils.isBase64('NOT BASE64!@#%!'), isFalse);
      });

      test('returns false for empty string', () {
        expect(Base64Utils.isBase64(''), isFalse);
      });

      test('returns true for URL-safe Base64 string', () {
        // "+/" replaced with "-_"
        expect(
          Base64Utils.isBase64('SGVsbG8tV29ybGRf'),
          isTrue,
        ); // "Hello-World_"
      });

      test('returns true for valid Base64 string missing padding', () {
        expect(Base64Utils.isBase64('SGVsbG8gV29ybGQ'), isTrue);
      });

      test('returns false for purely numeric non-base64', () {
        expect(Base64Utils.isBase64('12345'), isFalse);
      });

      test(
        'returns false for strings that could be decoded with just padding added but are invalid length',
        () {
          // SGVs = "Hel"
          // SGVsb = "Hel" + half a byte - invalid base64 length
          expect(Base64Utils.isBase64('SGVsb'), isFalse);
        },
      );
    });
  });
}
