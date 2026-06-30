import sys

with open('lib/screens/connection_home_screen.dart', 'r') as f:
    content = f.read()

search = """  @override
  Widget build(BuildContext context) {
    return Scaffold("""

replace = """  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0A0A),
        body: Center(
          child: CircularProgressIndicator(color: Colors.blueAccent),
        ),
      );
    }

    return Scaffold("""

if search in content:
    content = content.replace(search, replace)
    with open('lib/screens/connection_home_screen.dart', 'w') as f:
        f.write(content)
    print("Successfully replaced.")
else:
    print("Search string not found.")
