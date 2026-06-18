import os
import re

def strip_qualifier(filepath, qualifier):
    if not os.path.exists(filepath):
        print(f"File {filepath} not found")
        return
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    # Find the class definition block
    class_match = re.search(r'(class\s+' + qualifier + r'\s*(?::\s*[^{]+)?\{)(.*?)(^\s*\};\s*$)', content, re.MULTILINE | re.DOTALL)
    if class_match:
        prefix = class_match.group(1)
        body = class_match.group(2)
        suffix = class_match.group(3)
        
        # In the body, replace `Qualifier::` with ``
        body = body.replace(f"{qualifier}::", "")
        
        # Replace the class block back into the content
        content = content[:class_match.start()] + prefix + body + suffix + content[class_match.end():]

    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)

base_path = 'packages/screen_retriever_windows/windows'
strip_qualifier(f'{base_path}/screen_retriever_windows_plugin.h', 'ScreenRetrieverWindowsPlugin')
print("✅ C++ files patched successfully with regex targeting class definitions.")
