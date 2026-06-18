#!/bin/bash
echo "🧹 Cleaning Flutter project..."
flutter clean
echo "🗑️ Removing ephemeral Windows files..."
rm -rf windows/flutter/ephemeral
rm -rf windows/flutter/ephemeral/.plugin_symlinks
echo "📦 Regenerating plugins..."
flutter pub get
echo "✅ Environment is ready for build."
