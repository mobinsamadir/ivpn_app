import re

with open('pubspec.yaml', 'r') as f:
    content = f.read()

content = content.replace("  webview_flutter_platform_interface: ^2.15.1\n  webview_flutter_android: ^4.12.0\n", "")
content = content.replace("  webview_flutter: ^4.9.0\n", "  webview_flutter: ^4.9.0\n  webview_flutter_platform_interface: ^2.15.1\n  webview_flutter_android: ^4.12.0\n")

with open('pubspec.yaml', 'w') as f:
    f.write(content)
