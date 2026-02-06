import 'dart:math';

class ChartUtils {
  /// Calculates jitter: average absolute difference between consecutive samples
  static double calculateJitter(List<int> samples) {
    if (samples.length < 2) return 0.0;
    
    // Filter out -1 (failures) for jitter calculation
    final validSamples = samples.where((s) => s > 0).toList();
    if (validSamples.length < 2) return 0.0;
    
    double sumOfDifferences = 0;
    for (int i = 1; i < validSamples.length; i++) {
      sumOfDifferences += (validSamples[i] - validSamples[i - 1]).abs();
    }
    
    return sumOfDifferences / (validSamples.length - 1);
  }

  static double calculateStandardDeviation(List<int> samples) {
    final validSamples = samples.where((s) => s > 0).toList();
    if (validSamples.isEmpty) return 0.0;
    
    double mean = validSamples.reduce((a, b) => a + b) / validSamples.length;
    double variance = validSamples.map((x) => pow(x - mean, 2)).reduce((a, b) => a + b) / validSamples.length;
    
    return sqrt(variance);
  }

  /// Calculates Moving Average for UI smoothing
  static List<double> calculateMovingAverage(List<int> samples, int windowSize) {
    if (samples.isEmpty) return [];
    
    List<double> result = [];
    for (int i = 0; i < samples.length; i++) {
      int start = max(0, i - windowSize + 1);
      int end = i + 1;
      final window = samples.sublist(start, end).where((s) => s > 0).toList();
      
      if (window.isEmpty) {
        result.add(0.0);
      } else {
        result.add(window.reduce((a, b) => a + b) / window.length);
      }
    }
    return result;
  }
}
