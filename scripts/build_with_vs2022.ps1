# Set the CMAKE_GENERATOR environment variable to force VS 2022
$env:CMAKE_GENERATOR = "Visual Studio 17 2022"

Write-Host "CMAKE_GENERATOR set to: $env:CMAKE_GENERATOR" -ForegroundColor Green

# Run the Flutter build command
Write-Host "Starting Flutter build for Windows..." -ForegroundColor Yellow
flutter build windows --release

# Check the exit code
if ($LASTEXITCODE -eq 0) {
    Write-Host "Build completed successfully!" -ForegroundColor Green
} else {
    Write-Host "Build failed with exit code: $LASTEXITCODE" -ForegroundColor Red
}