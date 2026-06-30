import sys

with open('android/app/src/main/kotlin/com/example/ivpn_new/SingboxVpnService.kt', 'r') as f:
    content = f.read()

if "import kotlinx.coroutines.sync.Mutex" not in content:
    lines = content.split('\n')
    for i, line in enumerate(lines):
        if line.startswith('import kotlinx.coroutines.launch'):
            lines.insert(i, "import kotlinx.coroutines.sync.Mutex")
            lines.insert(i, "import kotlinx.coroutines.sync.withLock")
            break
    content = '\n'.join(lines)
    with open('android/app/src/main/kotlin/com/example/ivpn_new/SingboxVpnService.kt', 'w') as f:
        f.write(content)
    print("Added imports.")
else:
    print("Imports already present.")
