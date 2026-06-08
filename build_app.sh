# Simple Build Script for IVPN Flutter App
# This script provides easy commands to build the app

# Function to display help
show_help() {
    echo "IVPN Flutter App - Build Script"
    echo "==============================="
    echo "Usage: ./build_app.bat [option]"
    echo ""
    echo "Options:"
    echo "  build-apk      - Build Android APK (release)"
    echo "  build-windows  - Build Windows app (release)"
    echo "  build-all      - Build for both platforms"
    echo "  clean          - Clean build artifacts"
    echo "  help           - Show this help message"
    echo ""
}

# Main script logic
case "$1" in
    "build-apk")
        echo "Building Android APK..."
        flutter build apk --release
        echo "APK built at: build/app/outputs/flutter-apk/app-release.apk"
        ;;
    "build-windows")
        echo "Building Windows app..."
        flutter build windows --release
        echo "Windows app built at: build/windows/runner/Release/"
        ;;
    "build-all")
        echo "Building for all platforms..."
        flutter build apk --release
        flutter build windows --release
        echo "Builds completed!"
        echo "APK: build/app/outputs/flutter-apk/app-release.apk"
        echo "Windows: build/windows/runner/Release/"
        ;;
    "clean")
        echo "Cleaning build artifacts..."
        flutter clean
        echo "Clean completed!"
        ;;
    "help"|"-h"|"--help"|*)
        show_help
        ;;
esac