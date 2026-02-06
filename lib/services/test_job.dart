enum TestType { speed, stability, adaptive, ping, health }

class TestJob {
  final TestType type;
  final Future<void> Function() task;
  final String name;
  final DateTime createdAt = DateTime.now();
  
  TestJob({
    required this.type,
    required this.task,
    this.name = 'Unnamed Job',
  });
  
  @override
  String toString() => 'TestJob($name, $type, ${createdAt.toIso8601String()})';
}
