@echo off
setlocal
set "SAMPLE=%~dp0"
set "ROOT=%SAMPLE%.."

if not defined AIR_SDK_HOME set "AIR_SDK_HOME=E:\AIRSDK\AIRSDK_Windows51.1.3"
set "SDK=%AIR_SDK_HOME%"

if not exist "%SAMPLE%ext" mkdir "%SAMPLE%ext"
if exist "%ROOT%\bin\PdfAne.ane" (
  copy /Y "%ROOT%\bin\PdfAne.ane" "%SAMPLE%ext\" >nul
) else (
  echo WARNING: %ROOT%\bin\PdfAne.ane not found — run ..\build.bat first.
)

echo === amxmlc ===
call "%SDK%\bin\amxmlc.bat" +configname=air ^
  -source-path+="%ROOT%\as3\src" ^
  -source-path+="%SAMPLE%src" ^
  -output="%SAMPLE%PdfTwoPageTest.swf" ^
  "%SAMPLE%src\PdfTwoPageTest.as"
if errorlevel 1 exit /b 1

echo.
echo OK: %SAMPLE%PdfTwoPageTest.swf
echo.
echo Run with 32-bit ADL ^(same AIR SDK^):
echo   "%SDK%\bin\adl.bat" -profile extendedDesktop -extdir "%SAMPLE%ext" "%SAMPLE%PdfTwoPageTest-app.xml" "%SAMPLE%"
exit /b 0
