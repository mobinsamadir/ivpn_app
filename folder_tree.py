import os
import json
import sys

# لیست پوشه‌هایی که باید نادیده گرفته شوند
IGNORE_PATTERNS = {'.git', '__pycache__', '.idea', '.vscode', 'venv', 'env', 'node_modules', '.DS_Store', 'dist', 'build'}

def get_directory_structure(rootdir):
    """
    ساخت دیکشنری برای JSON
    """
    dir_name = os.path.basename(rootdir)
    if dir_name == "":
        dir_name = rootdir
        
    dir_structure = {'name': dir_name, 'type': 'directory', 'children': []}

    try:
        items = sorted(os.listdir(rootdir))
        for item in items:
            if item in IGNORE_PATTERNS:
                continue
                
            path = os.path.join(rootdir, item)
            
            if os.path.isdir(path):
                dir_structure['children'].append(get_directory_structure(path))
            else:
                dir_structure['children'].append({'name': item, 'type': 'file'})
    except PermissionError:
        pass

    return dir_structure

def generate_visual_tree(rootdir, prefix=""):
    """
    ساخت نمودار متنی (Visual Tree)
    """
    lines = []
    
    try:
        items = sorted(os.listdir(rootdir))
        # حذف آیتم‌های ایگنور شده از لیست پردازش
        items = [i for i in items if i not in IGNORE_PATTERNS]
        
        count = len(items)
        for i, item in enumerate(items):
            path = os.path.join(rootdir, item)
            is_last = (i == count - 1)
            
            connector = "└── " if is_last else "├── "
            lines.append(f"{prefix}{connector}{item}")
            
            if os.path.isdir(path):
                extension = "    " if is_last else "│   "
                lines.extend(generate_visual_tree(path, prefix + extension))
                
    except PermissionError:
        pass
        
    return lines

def main(target_dir):
    if not os.path.exists(target_dir):
        print(f"Error: Directory '{target_dir}' not found.")
        return

    print(f"Scanning: {target_dir}")

    # 1. تولید فایل JSON
    print("Generating JSON...")
    json_data = get_directory_structure(target_dir)
    with open('folder_tree.json', 'w', encoding='utf-8') as f:
        json.dump(json_data, f, indent=2, ensure_ascii=False)

    # 2. تولید فایل متنی (TXT)
    print("Generating Text Tree...")
    text_lines = [os.path.basename(target_dir) + "/"]
    text_lines.extend(generate_visual_tree(target_dir))
    
    with open('folder_tree.txt', 'w', encoding='utf-8') as f:
        f.write("\n".join(text_lines))

    print("Done!")
    print(" -> folder_tree.json (Created)")
    print(" -> folder_tree.txt  (Created - Use this for a quick overview)")

if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else "."
    target = os.path.abspath(target)
    main(target)