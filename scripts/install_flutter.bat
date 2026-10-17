@echo off
setlocal
set FLUTTER_VERSION=3.41.9
set "INSTALL_DIR=G:\ProgramData"
set "FLUTTER_BIN=%INSTALL_DIR%\flutter\bin"
set ZIP=%TEMP%\flutter_windows_%FLUTTER_VERSION%-stable.zip

REM China mirrors (remove these 4 lines if you do not need them)
set FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
set PUB_HOSTED_URL=https://pub.flutter-io.cn
setx FLUTTER_STORAGE_BASE_URL %FLUTTER_STORAGE_BASE_URL% >nul
setx PUB_HOSTED_URL %PUB_HOSTED_URL% >nul

for %%D in ("%INSTALL_DIR%") do set "INSTALL_DRIVE=%%~dD"
if not exist "%INSTALL_DRIVE%\" goto :no_drive
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"
if not exist "%INSTALL_DIR%" goto :no_dir
if exist "%FLUTTER_BIN%\flutter.bat" goto :already_installed

set URL=%FLUTTER_STORAGE_BASE_URL%/flutter_infra_release/releases/stable/windows/flutter_windows_%FLUTTER_VERSION%-stable.zip
set MAX_TRIES=10
set TRY=0

REM --retry-all-errors needs curl 7.71+; older Windows 10 builds ship an older curl
set CURL_RETRY=--retry 20 --retry-delay 3
curl --help all 2>nul | findstr /c:"--retry-all-errors" >nul && set CURL_RETRY=%CURL_RETRY% --retry-all-errors

REM The zip is kept in %TEMP% until it is complete, so re-running the script resumes it
echo Download file: %ZIP%

:download
set /a TRY+=1
echo Downloading Flutter %FLUTTER_VERSION% (attempt %TRY% of %MAX_TRIES%) ...
curl -L -C - %CURL_RETRY% -o "%ZIP%" "%URL%"
if errorlevel 1 goto :download_failed

echo Checking zip ...
tar -tf "%ZIP%" >nul 2>nul
if errorlevel 1 (
  echo Zip is incomplete or corrupt, deleting it and downloading again.
  del "%ZIP%"
  goto :download_failed
)
goto :extract

:download_failed
if %TRY% GEQ %MAX_TRIES% (
  echo Download failed after %MAX_TRIES% attempts. Run this script again to resume.
  pause
  exit /b 1
)
echo Download interrupted, retrying in 5 seconds ...
timeout /t 5 /nobreak >nul
goto :download

:extract
echo Extracting ...
tar -xf "%ZIP%" -C "%INSTALL_DIR%"
if errorlevel 1 (echo Extract failed. & pause & exit /b 1)
del "%ZIP%"

:path
REM Add flutter\bin to the USER path (PowerShell avoids setx truncating PATH)
powershell -NoProfile -Command "$p=[Environment]::GetEnvironmentVariable('Path','User'); $b='%FLUTTER_BIN%'; if(-not $p){$p=''}; if(($p -split ';') -notcontains $b){[Environment]::SetEnvironmentVariable('Path',($p.TrimEnd(';')+';'+$b),'User')}"

set "PATH=%PATH%;%FLUTTER_BIN%"

echo.
echo Accept Android licenses (type y when asked). Android Studio must be installed first.
call flutter doctor --android-licenses
call flutter doctor

echo.
echo Done. Open a NEW terminal, go to the project folder, then run:
echo   flutter pub get
echo   flutter build apk
pause
exit /b 0

:already_installed
echo Flutter already exists in "%INSTALL_DIR%\flutter", skipping download.
goto :path

:no_drive
echo Drive %INSTALL_DRIVE% does not exist. Edit INSTALL_DIR at the top of this script.
pause
exit /b 1

:no_dir
echo Cannot create "%INSTALL_DIR%". Run this script as administrator,
echo or change INSTALL_DIR at the top of this script to a folder like G:\dev.
pause
exit /b 1
