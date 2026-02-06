@echo off
echo Running Config-Refinery...

if not exist bin mkdir bin
if not exist output mkdir output

go run main.go

if %ERRORLEVEL% == 0 (
    echo Application completed successfully!
) else (
    echo Application failed!
    pause
    exit /b %ERRORLEVEL%
)