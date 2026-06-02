class PhoneUtils {
  static String? normalize(String? phone) {
    if (phone == null) return null;
    // Remove all non-numeric characters
    String digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    // Take only last 10 digits
    if (digits.length > 10) {
      return digits.substring(digits.length - 10);
    }
    return digits;
  }
}
