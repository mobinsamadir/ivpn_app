import os

def strip_qualifier(filepath, qualifier):
    if not os.path.exists(filepath):
        return
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    # Remove the illegal class qualifiers
    content = content.replace(f" {qualifier}::", " ")

    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)

base_path = 'packages/window_manager/windows'
strip_qualifier(f'{base_path}/window_manager.cpp', 'WindowManager')
strip_qualifier(f'{base_path}/window_manager_plugin.cpp', 'WindowManagerPlugin')
print("✅ C++ files patched successfully in the flattened directory.")
