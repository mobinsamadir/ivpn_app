void main() {
  // Desired Regex: (vless|vmess|trojan|ss)://[^\s<>"'{}|\\^`]+
  // In Dart String:
  final pattern = '(vless|vmess|trojan|ss):\\/\\/[^\\s<>"\'{}|\\\\^`]+';
  final regex = RegExp(pattern, caseSensitive: false, multiLine: true);

  print("Pattern: $pattern");

  final inputs = [
    'vless://abc',
    'vmess://abc/def',
    'vless://abc\'def', // Should be matched until '
    'vless://abc"def', // Should be matched until "
  ];

  for (final input in inputs) {
    final match = regex.firstMatch(input)?.group(0);
    print("Input: $input -> Match: $match");
  }
}
