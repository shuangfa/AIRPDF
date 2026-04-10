@echo off
setlocal
set "ROOT=%~dp0"
set "DEST=%ROOT%native\third_party\pdfium"
set "URL=https://github.com/bblanchon/pdfium-binaries/releases/download/chromium/7763/pdfium-win-x86.tgz"
set "MIRROR=https://mirror.ghproxy.com/https://github.com/bblanchon/pdfium-binaries/releases/download/chromium/7763/pdfium-win-x86.tgz"
set "TGZ=%TEMP%\pdfium-win-x86.tgz"

echo Downloading PDFium Win32 ^(x86^)...
curl -fL --retry 2 --connect-timeout 45 -o "%TGZ%" "%URL%"
if errorlevel 1 (
  echo Primary URL failed, trying mirror...
  curl -fL --retry 2 --connect-timeout 45 -o "%TGZ%" "%MIRROR%"
)
if errorlevel 1 (
  echo ERROR: download failed. Install curl or save the .tgz manually to:
  echo   %TGZ%
  echo from: %URL%
  exit /b 1
)

if exist "%DEST%" rd /s /q "%DEST%"
mkdir "%DEST%"
echo Extracting...
tar -xzf "%TGZ%" -C "%DEST%"
if errorlevel 1 (
  echo ERROR: tar extract failed.
  exit /b 1
)

if not exist "%DEST%\include\fpdfview.h" (
  pushd "%DEST%"
  for /d %%D in (*) do (
    if exist "%%~fD\include\fpdfview.h" (
      echo Moving nested folder %%D into %DEST% ...
      robocopy "%%~fD" "." /E /MOVE /NFL /NDL /NJH /NJS >nul
    )
  )
  popd
)
if not exist "%DEST%\include\fpdfview.h" (
  echo ERROR: include\fpdfview.h not found under %DEST%
  exit /b 1
)
if not exist "%DEST%\lib\pdfium.lib" if not exist "%DEST%\lib\pdfium.dll.lib" (
  echo ERROR: no import library: expected lib\pdfium.lib or lib\pdfium.dll.lib
  exit /b 1
)
if not exist "%DEST%\bin\pdfium.dll" if not exist "%DEST%\lib\pdfium.dll" (
  echo ERROR: pdfium.dll not found under bin\ or lib\
  exit /b 1
)

echo OK: %DEST%
echo Run build.bat — it will auto-link PDFium when this folder is present.
exit /b 0
