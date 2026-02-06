import os
import sys

def verify_build():
    print("Verifying project structure...")

    required_dirs = ["lib", "android", "windows", "scripts", "docker", "configs", "docs"]
    required_files = ["pubspec.yaml", "lib/main.dart"]

    all_good = True

    for dir in required_dirs:
        if not os.path.exists(dir):
            print(f"[ERROR] Missing directory: {dir}")
            all_good = False
        else:
            print(f"[OK] Directory exists: {dir}")

    for file in required_files:
        if not os.path.exists(file):
            print(f"[ERROR] Missing file: {file}")
            all_good = False
        else:
            print(f"[OK] File exists: {file}")

    if all_good:
        print("\n[SUCCESS] Project structure is correct!")
        return 0
    else:
        print("\n[ERROR] Project structure has issues!")
        return 1

if __name__ == "__main__":
    sys.exit(verify_build())