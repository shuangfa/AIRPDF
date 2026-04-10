@echo off
setlocal EnableDelayedExpansion

rem Root of this repo (directory containing this script)
set "ROOT=%~dp0"
pushd "%ROOT%"

rem === AIR SDK 51.1.3 (override with AIR_SDK_HOME) ===
if not defined AIR_SDK_HOME set "AIR_SDK_HOME=E:\AIRSDK\AIRSDK_Windows51.1.3"
set "PATH=%AIR_SDK_HOME%\bin;%PATH%"

if not exist "%AIR_SDK_HOME%\lib\win\FlashRuntimeExtensions.lib" (
  echo ERROR: FlashRuntimeExtensions.lib not found. Set AIR_SDK_HOME to your AIR SDK.
  exit /b 1
)

set "OUT=%ROOT%bin"
if not exist "%OUT%" mkdir "%OUT%"

echo === AS3 SWC ===
call "%AIR_SDK_HOME%\bin\acompc.bat" +configname=air -source-path "%ROOT%as3\src" -include-classes com.airpdf.PdfAne -output "%OUT%\PdfAne.swc"
if errorlevel 1 goto :fail

rem ADT 51.x expects library.swf listed under -platform (use -C bin). Extract from SWC.
tar -xf "%OUT%\PdfAne.swc" -C "%OUT%" library.swf
if errorlevel 1 goto :fail

echo === Native DLL Win32 ===
set "VCVARS="
for %%V in (
  "%ProgramFiles(x86)%\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat"
  "%ProgramFiles(x86)%\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat"
  "%ProgramFiles%\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvarsall.bat"
  "%ProgramFiles(x86)%\Microsoft Visual Studio\2019\BuildTools\VC\Auxiliary\Build\vcvarsall.bat"
  "%ProgramFiles(x86)%\Microsoft Visual Studio\2019\Community\VC\Auxiliary\Build\vcvarsall.bat"
) do if exist %%~V set "VCVARS=%%~V"

if not defined VCVARS (
  echo ERROR: vcvarsall.bat not found. Install "Desktop development with C++" ^(x86/32-bit tools^).
  exit /b 1
)

call "%VCVARS%" x86
if errorlevel 1 goto :fail

rem Auto-enable PDFium if third_party layout exists ^(bblanchon: lib\pdfium.lib or lib\pdfium.dll.lib^).
if not defined USE_PDFIUM (
  if exist "%ROOT%native\third_party\pdfium\include\fpdfview.h" (
    if exist "%ROOT%native\third_party\pdfium\lib\pdfium.lib" set "USE_PDFIUM=1"
    if exist "%ROOT%native\third_party\pdfium\lib\pdfium.dll.lib" set "USE_PDFIUM=1"
    if defined USE_PDFIUM set "PDFIUM_DIR=%ROOT%native\third_party\pdfium"
  )
)

set "CLFLAGS=/nologo /O2 /MD /LD /EHsc /W3 /utf-8 /DWIN32 /D_USE_MATH_DEFINES /DUSE_PDFIUM=0"
set "PDFIUM_INC="
set "PDFIUM_LIB="

if /i "%USE_PDFIUM%"=="1" (
  if not defined PDFIUM_DIR set "PDFIUM_DIR=%ROOT%native\third_party\pdfium"
  if not exist "%PDFIUM_DIR%\include\fpdfview.h" (
    echo ERROR: PDFIUM_DIR missing include\fpdfview.h — run fetch-pdfium.bat or set PDFIUM_DIR.
    exit /b 1
  )
  if exist "%PDFIUM_DIR%\lib\pdfium.lib" (
    set "PDFIUM_IMPLIB=%PDFIUM_DIR%\lib\pdfium.lib"
  ) else if exist "%PDFIUM_DIR%\lib\pdfium.dll.lib" (
    set "PDFIUM_IMPLIB=%PDFIUM_DIR%\lib\pdfium.dll.lib"
  ) else (
    echo ERROR: PDFIUM_DIR missing lib\pdfium.lib or lib\pdfium.dll.lib
    exit /b 1
  )
  set "CLFLAGS=/nologo /O2 /MD /LD /EHsc /W3 /utf-8 /DWIN32 /D_USE_MATH_DEFINES /DUSE_PDFIUM=1"
  set "PDFIUM_INC=/I"%PDFIUM_DIR%\include""
  set "PDFIUM_LIB=!PDFIUM_IMPLIB!"
  if exist "%PDFIUM_DIR%\bin\pdfium.dll" (
    copy /Y "%PDFIUM_DIR%\bin\pdfium.dll" "%OUT%\" >nul 2>&1
  ) else (
    copy /Y "%PDFIUM_DIR%\lib\pdfium.dll" "%OUT%\" >nul 2>&1
  )
  echo PDFium ON: %PDFIUM_DIR%
) else (
  echo.
  echo ------------------------------------------------------------------
  echo   NO PDFium linked — pages show CHECKERBOARD only ^(placeholder^).
  echo   Real PDF: run fetch-pdfium.bat then build.bat again, or: build-pdfium.bat
  echo ------------------------------------------------------------------
  echo.
)

cl %CLFLAGS% /I"%AIR_SDK_HOME%\include" /I"%ROOT%native\src" %PDFIUM_INC% "%ROOT%native\src\PdfAne.cpp" /link /DLL /OUT:"%OUT%\PdfAne.dll" "%AIR_SDK_HOME%\lib\win\FlashRuntimeExtensions.lib" user32.lib %PDFIUM_LIB%
if errorlevel 1 goto :fail

echo === Package ANE ===
rem Run from project root: paths must be relative to cwd; platform needs library.swf + native DLL(s) via -C bin.
rem NOTE: Do not chain "if A if B (...) else (...)" — else binds to inner if, so when A is false neither branch runs.
if /i "%USE_PDFIUM%"=="1" (
  if exist "%OUT%\pdfium.dll" (
    call "%AIR_SDK_HOME%\bin\adt.bat" -package -target ane "bin\PdfAne.ane" "extension.xml" -swc "bin\PdfAne.swc" -platform Windows-x86 -C bin library.swf PdfAne.dll pdfium.dll
  ) else (
    call "%AIR_SDK_HOME%\bin\adt.bat" -package -target ane "bin\PdfAne.ane" "extension.xml" -swc "bin\PdfAne.swc" -platform Windows-x86 -C bin library.swf PdfAne.dll
  )
) else (
  call "%AIR_SDK_HOME%\bin\adt.bat" -package -target ane "bin\PdfAne.ane" "extension.xml" -swc "bin\PdfAne.swc" -platform Windows-x86 -C bin library.swf PdfAne.dll
)
if errorlevel 1 goto :fail
if not exist "%OUT%\PdfAne.ane" (
  echo ERROR: adt finished but bin\PdfAne.ane was not created.
  goto :fail
)

echo.
echo OK: %ROOT%bin\PdfAne.ane
popd
exit /b 0

:fail
echo BUILD FAILED
popd
exit /b 1
