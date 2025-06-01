@echo off

mkdir bin 2>nul 
set project_name="app"

odin build src -out:bin/%project_name%.exe
if errorlevel 1 (
    echo Build failed.
    exit /b 1
)

cd bin
.\%project_name%.exe
