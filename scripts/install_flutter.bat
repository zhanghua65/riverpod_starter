@echo off
setlocal
set FLUTTER_VERSION=3.41.9
set INSTALL_DIR=C:\dev
set ZIP=%TEMP%\flutter_windows_%FLUTTER_VERSION%-stable.zip

REM China mirrors (remove these 4 lines if you do not need them)
set FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
set PUB_HOSTED_URL=https://pub.flutter-io.cn
setx FLUTTER_STORAGE_BASE_URL %FLUTTER_STORAGE_BASE_URL% >nul
setx PUB_HOSTED_URL %PUB_HOSTED_URL% >nul

if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"
if exist "%INSTALL_DIR%\flutter\bin\flutter.bat" (
  echo Flutter already exists in %INSTALL_DIR%\flutter, skipping download.
  goto :path
)

echo Downloading Flutter %FLUTTER_VERSION% ...
curl -L -o "%ZIP%" "%FLUTTER_STORAGE_BASE_URL%/flutter_infra_release/releases/stable/windows/flutter_windows_%FLUTTER_VERSION%-stable.zip"
if errorlevel 1 (echo Download failed. & pause & exit /b 1)

echo Extracting ...
tar -xf "%ZIP%" -C "%INSTALL_DIR%"
if errorlevel 1 (echo Extract failed. & pause & exit /b 1)
del "%ZIP%"

:path
REM Add flutter\bin to the USER path (PowerShell avoids setx truncating PATH)
powershell -NoProfile -Command "$p=[Environment]::GetEnvironmentVariable('Path','User'); $b='%INSTALL_DIR%\flutter\bin'; if(-not $p){$p=''}; if(($p -split ';') -notcontains $b){[Environment]::SetEnvironmentVariable('Path',($p.TrimEnd(';')+';'+$b),'User')}"

set PATH=%PATH%;%INSTALL_DIR%\flutter\bin

echo.
echo Accept Android licenses (type y when asked). Android Studio must be installed first.
call flutter doctor --android-licenses
call flutter doctor

echo.
echo Done. Open a NEW terminal, go to the project folder, then run:
echo   flutter pub get
echo   flutter build apk
pause
