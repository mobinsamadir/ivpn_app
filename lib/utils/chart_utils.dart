import 'dart:math';

class ChartUtils {
  /// Calculates jitter: average absolute difference between consecutive samples
  static double calculateJitter(List<int> samples) {
    if (samples.length < 2) return 0.0;

    double sumOfDifferences = 0;
    int validCount = 0;
    int lastValidSample = -1;

    for (int i = 0; i < samples.length; i++) {
      if (samples[i] > 0) {
        if (lastValidSample != -1) {
          sumOfDifferences += (samples[i] - lastValidSample).abs();
          validCount++;
        }
        lastValidSample = samples[i];
      }
    }

    if (validCount == 0) return 0.0;
    return sumOfDifferences / validCount;
  }

  static double calculateStandardDeviation(List<int> samples) {
    int validCount = 0;
    double sum = 0;

    for (final s in samples) {
      if (s > 0) {
        sum += s;
        validCount++;
      }
    }

    if (validCount == 0) return 0.0;

    double mean = sum / validCount;
    double varianceSum = 0;

    for (final s in samples) {
      if (s > 0) {
        varianceSum += pow(s - mean, 2);
      }
    }

    double variance = varianceSum / validCount;
    return sqrt(variance);
  }

  /// Calculates Moving Average for UI smoothing
  static List<double> calculateMovingAverage(
    List<int> samples,
    int windowSize,
  ) {
    if (samples.isEmpty) return [];

    List<double> result = List.filled(samples.length, 0.0);
    double currentSum = 0;
    int currentValidCount = 0;

    for (int i = 0; i < samples.length; i++) {
      // Add current element
      if (samples[i] > 0) {
        currentSum += samples[i];
        currentValidCount++;
      }

      // Remove element that falls out of the window
      if (i >= windowSize) {
        int outIndex = i - windowSize;
        if (samples[outIndex] > 0) {
          currentSum -= samples[outIndex];
          currentValidCount--;
        }
      }

      if (currentValidCount == 0) {
        result[i] = 0.0;
      } else {
        result[i] = currentSum / currentValidCount;
      }
    }
    return result;
  }
}
