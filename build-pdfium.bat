@echo off
rem Download PDFium Win32 (x86) then build ANE with real PDF rendering.
pushd "%~dp0"
call "%~dp0fetch-pdfium.bat"
if errorlevel 1 exit /b 1
call "%~dp0build.bat"
set "ERR=%ERRORLEVEL%"
popd
exit /b %ERR%
