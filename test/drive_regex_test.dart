
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Google Drive Confirm Token Regex', () {
    const htmlContent = '''
<!DOCTYPE html><html><head><title>Google Drive - Virus scan warning</title>
<meta http-equiv="content-type" content="text/html; charset=utf-8"/>
<style nonce="..."></style>
</head><body><div class="uc-main">
<div class="uc-error-caption">Google Drive can't scan this file for viruses.</div>
<div class="uc-error-subcaption">
  <span class="uc-name-size"><span class="uc-name">servers.txt</span> (1.2M)</span>
  is too large for Google to scan for viruses. Would you like to download it anyway?
</div>
<form id="downloadForm" action="https://drive.google.com/uc?export=download&amp;id=1S7CI5xq4bbnERZ1i1eGuYn5bhluh2LaW&amp;confirm=t&amp;uuid=..." method="post">
<input type="submit" id="uc-download-link" class="goog-inline-block jfk-button jfk-button-action" value="Download anyway"/>
</form>
<a href="/uc?export=download&amp;id=1S7CI5xq4bbnERZ1i1eGuYn5bhluh2LaW&amp;confirm=ABC-123_xyz">Download</a>
</div></body></html>
    ''';

    // 1. Extract token using simple Regex first (Fast)
    final confirmMatch = RegExp(r'confirm=([a-zA-Z0-9_-]+)').firstMatch(htmlContent);
    String? confirmToken = confirmMatch?.group(1);

    expect(confirmToken, isNotNull);
    expect(confirmToken, equals('t')); // It finds the first one 't' or 'ABC-123_xyz' depending on order. In the snippet above, it finds 't' inside action attribute.

    // Let's test with a clearer link if the form action one is not what we want.
    // Usually the confirm token is 't' or a random string.

    // Test with the other link style
    const linkContent = '/uc?export=download&confirm=ABC_123';
    final match2 = RegExp(r'confirm=([a-zA-Z0-9_-]+)').firstMatch(linkContent);
    expect(match2?.group(1), equals('ABC_123'));
  });
}
