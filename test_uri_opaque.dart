void main() {
  try {
    var u = Uri.parse('vless:eyJhZGQiOiIxMjcuMC4wLjEiLCJwb3J0Ijo0NDN9');
    print('Scheme: ${u.scheme}');
    print('Host: ${u.host}');
    print('Path: ${u.path}');
  } catch (e) {
    print('Error: $e');
  }
}
