import 'package:flutter_test/flutter_test.dart';
import 'package:daydispatch/features/vin_scanner/vin_validator.dart';

void main() {
  group('VinValidator', () {
    test('validates standard 17-character VIN', () {
      const validVin = '1HGCM82633A004352';
      expect(VinValidator.isValidVin(validVin), isTrue);
      expect(VinValidator.extractAndNormalize(validVin), equals(validVin));
    });

    test('normalizes lowercase and removes whitespace and hyphens', () {
      const formatted = ' 1hgcm82633a-004352 ';
      expect(VinValidator.extractAndNormalize(formatted), equals('1HGCM82633A004352'));
    });

    test('rejects VIN with forbidden letters I, O, Q', () {
      expect(VinValidator.isValidVin('1HGCM82633I004352'), isFalse);
      expect(VinValidator.isValidVin('1HGCM82633O004352'), isFalse);
      expect(VinValidator.isValidVin('1HGCM82633Q004352'), isFalse);
    });

    test('rejects VIN with incorrect length', () {
      expect(VinValidator.isValidVin('1HGCM82633A00435'), isFalse); // 16 chars
      expect(VinValidator.isValidVin('1HGCM82633A0043529'), isFalse); // 18 chars
    });

    test('extracts 17-character VIN from barcode payload with prefix/suffix', () {
      const barcodeWithPrefix = 'I1HGCM82633A004352'; // Some Code 39 have leading 'I'
      expect(VinValidator.extractAndNormalize(barcodeWithPrefix), equals('1HGCM82633A004352'));
    });

    test('extracts VIN from multiline OCR text', () {
      const ocrText = '''
VEHICLE REGISTRATION
VIN: 1HGCM82633A004352
MAKE: HONDA
MODEL: ACCORD
''';
      expect(VinValidator.extractFromOcrText(ocrText), equals('1HGCM82633A004352'));
    });

    test('extracts VIN from OCR text with O-for-0 character confusion', () {
      const ocrTextWithO = 'VIN: 1HGCM82633AO04352'; // 'O' instead of '0'
      expect(VinValidator.extractFromOcrText(ocrTextWithO), equals('1HGCM82633A004352'));
    });
  });
}
