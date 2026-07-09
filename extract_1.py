import re

with open('lib/screens/connection_home_screen.dart', 'r') as f:
    code = f.read()

# The widget string
admin_widget = """
class _AdminWarningBanner extends StatelessWidget {
  final bool isAdmin;
  const _AdminWarningBanner({required this.isAdmin});

  @override
  Widget build(BuildContext context) {
    if (isAdmin) return const SliverToBoxAdapter(child: SizedBox.shrink());
    return SliverToBoxAdapter(
      child: Container(
        width: double.infinity,
        color: Colors.amberAccent.withValues(alpha: 0.2),
        padding: const EdgeInsets.symmetric(
          vertical: 8,
          horizontal: 16,
        ),
        child: Row(
          children: const [
            Icon(
              Icons.warning_amber_rounded,
              color: Colors.amberAccent,
              size: 20,
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                "For better connectivity, please run iVPN as Administrator.",
                style: TextStyle(
                  color: Colors.amberAccent,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
"""

# 1. Inject the widget at the end of the file.
code = code + "\n" + admin_widget + "\n"

# 2. Replace the inline code.
# The inline code is around line 711
target = """              if (Platform.isWindows && !_isAdmin)
                SliverToBoxAdapter(
                  child: Container(
                    width: double.infinity,
                    color: Colors.amberAccent.withOpacity(0.2),
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 16,
                    ),
                    child: Row(
                      children: const [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.amberAccent,
                          size: 20,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            "For better connectivity, please run iVPN as Administrator.",
                            style: TextStyle(
                              color: Colors.amberAccent,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),"""

replacement = """              if (Platform.isWindows) _AdminWarningBanner(isAdmin: _isAdmin),"""

if target in code:
    code = code.replace(target, replacement)
    print("Replaced target.")
else:
    print("Could not find target block.")

with open('lib/screens/connection_home_screen.dart', 'w') as f:
    f.write(code)
