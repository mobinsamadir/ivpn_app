import 'package:flutter_test/flutter_test.dart';
import '../lib/services/config_manager.dart';

void main() {
  test('extractDriveConfirmationLink should extract link from HTML with ID', () {
    const html = '''
      <html>
        <body>
          <a id="uc-download-link" class="goog-inline-block jfk-button jfk-button-action" href="/uc?export=download&amp;confirm=t&amp;id=12345">Download anyway</a>
        </body>
      </html>
    ''';
    final link = ConfigManager.extractDriveConfirmationLink(html);
    expect(link, '/uc?export=download&confirm=t&id=12345');
  });

  test('extractDriveConfirmationLink should extract link from HTML with href containing confirm=', () {
    const html = '''
      <html>
        <body>
          <a href="/uc?export=download&amp;confirm=TESTTOKEN&amp;id=12345">Download anyway</a>
        </body>
      </html>
    ''';
    final link = ConfigManager.extractDriveConfirmationLink(html);
    expect(link, '/uc?export=download&confirm=TESTTOKEN&id=12345');
  });

  test('extractDriveConfirmationLink should fail gracefully on missing link', () {
    const html = '<html><body>No link here</body></html>';
    final link = ConfigManager.extractDriveConfirmationLink(html);
    expect(link, isNull);
  });

  test('extractDriveConfirmationLink should extract link using Regex fallback', () {
    const html = '''
      <html>
        <body>
          <script>
            window.location.href = "/uc?export=download&confirm=REGEX_TOKEN&id=12345";
          </script>
        </body>
      </html>
    ''';
    final link = ConfigManager.extractDriveConfirmationLink(html);
    expect(link, '/uc?export=download&confirm=REGEX_TOKEN&id=12345');
  });
}
