import re

file_path = './lib/screens/connection_home_screen.dart'

with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Make double sure we remove ALL duplicate declarations of _consecutiveFailures and _lastAutoSwitchAttempt
content = re.sub(r"  int _consecutiveFailures = 0;\n", "", content)
content = re.sub(r"  DateTime\? _lastAutoSwitchAttempt;\n", "", content)

# Remove the one with spaces
content = re.sub(r"  int _consecutiveFailures = 0;", "", content)
content = re.sub(r"  DateTime\? _lastAutoSwitchAttempt;", "", content)
content = re.sub(r"  // NEW: Auto-switch throttle and limits\n", "", content)
content = re.sub(r"  // NEW: Auto-switch throttle and limits", "", content)


# Now add them exactly once where they belong
pattern = r"""  String _lastNativeStatus = "DISCONNECTED";
  bool _isAdmin = true;"""

repl = r"""  String _lastNativeStatus = "DISCONNECTED";
  bool _isAdmin = true;
  
  // NEW: Auto-switch throttle and limits
  int _consecutiveFailures = 0;
  DateTime? _lastAutoSwitchAttempt;"""

content = content.replace(pattern, repl)

# Let's fix the git merge conflict markers that are explicitly in the text
content = re.sub(r"<<<<<<< fix/android-singbox-crash\n", "", content)
content = re.sub(r"=======\n", "", content)
content = re.sub(r">>>>>>> main\n", "", content)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)
