/// Vehicle Identification Number (VIN) validation and normalization utilities.
class VinValidator {
  VinValidator._();

  /// Standard 17-character VIN regex pattern:
  /// - Exactly 17 characters
  /// - Only uppercase alphanumeric characters
  /// - Excludes I, O, Q (per ISO 3779 / NHTSA standard)
  static final RegExp vinRegex = RegExp(r'^[A-HJ-NPR-Z0-9]{17}$');

  /// Cleans raw text by converting to uppercase and stripping any
  /// non-alphanumeric characters (spaces, hyphens, punctuation, symbols).
  static String cleanRawString(String raw) {
    return raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  }

  /// Checks if a string is a strictly valid 17-character VIN.
  static bool isValidVin(String? vin) {
    if (vin == null || vin.isEmpty) return false;
    final cleaned = cleanRawString(vin);
    return vinRegex.hasMatch(cleaned);
  }

  /// Attempts to extract and normalize a valid 17-character VIN from a scanned
  /// barcode or string value.
  /// 
  /// Returns the normalized 17-character VIN if found and valid, or null.
  static String? extractAndNormalize(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;

    final cleaned = cleanRawString(raw);

    // 1. Direct match: cleaned string is exactly 17 valid VIN characters
    if (vinRegex.hasMatch(cleaned)) {
      return cleaned;
    }

    // 2. Barcode payload contains prefix/suffix (e.g. Code 39 leading 'I' or 2D barcode payload)
    final match = RegExp(r'[A-HJ-NPR-Z0-9]{17}').firstMatch(cleaned);
    if (match != null) {
      return match.group(0);
    }

    return null;
  }

  /// Attempts to extract a valid 17-character VIN from OCR recognized text.
  /// 
  /// Checks tokens, lines, removes labels ("VIN:"), and applies standard OCR corrections
  /// for commonly confused characters (e.g. O/Q -> 0, I -> 1) since standard
  /// VINs never contain the letters I, O, or Q.
  static String? extractFromOcrText(String recognizedText) {
    if (recognizedText.trim().isEmpty) return null;

    // Split into tokens by whitespace, newlines, and common delimiter punctuation
    final tokens = recognizedText.split(RegExp(r'[\s:;#|=/\\,\-\*]+'));

    // 1. Check tokens directly
    for (final token in tokens) {
      final cleaned = cleanRawString(token);
      if (isValidVin(cleaned)) {
        return cleaned;
      }
    }

    // 2. Check tokens with common label prefixes stripped (e.g. "VIN1HGCM82633A004352")
    for (final token in tokens) {
      var cleaned = cleanRawString(token);
      for (final prefix in ['VINNUMBER', 'VINNO', 'VINNUM', 'VIN', 'CHASSISNO', 'CHASSIS']) {
        if (cleaned.startsWith(prefix) && cleaned.length > prefix.length) {
          cleaned = cleaned.substring(prefix.length);
          break;
        }
      }
      if (isValidVin(cleaned)) {
        return cleaned;
      }
      if (cleaned.length == 17) {
        final corrected = cleaned
            .replaceAll('I', '1')
            .replaceAll('O', '0')
            .replaceAll('Q', '0');
        if (isValidVin(corrected)) {
          return corrected;
        }
      }
    }

    // 3. Check tokens with OCR confusion corrections (I -> 1, O -> 0, Q -> 0)
    for (final token in tokens) {
      final cleaned = cleanRawString(token);
      if (cleaned.length == 17) {
        final corrected = cleaned
            .replaceAll('I', '1')
            .replaceAll('O', '0')
            .replaceAll('Q', '0');
        if (isValidVin(corrected)) {
          return corrected;
        }
      }
    }

    return null;
  }
}
