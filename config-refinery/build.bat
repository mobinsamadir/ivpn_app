@echo off
echo Building Config-Refinery...

if not exist bin mkdir bin

go build -o bin/config-refinery.exe main.go

if %ERRORLEVEL% == 0 (
    echo Build successful! Binary is located at bin/config-refinery.exe
) else (
    echo Build failed!
    exit /b %ERRORLEVEL%
)