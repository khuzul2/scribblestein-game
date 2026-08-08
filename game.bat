@echo off
setlocal enabledelayedexpansion

rem ============================================================================
rem  Scribblestein - one-click launcher for Windows
rem
rem  Clone the repo, double-click this file. It finds Godot (downloading the
rem  pinned version if you do not have it), imports the assets on first run,
rem  and starts the game.
rem
rem    game.bat            play
rem    game.bat editor     straight into the level editor
rem    game.bat lab        straight into the Lab
rem    game.bat level      straight into Level 01
rem    game.bat test       run the test suite (headless)
rem    game.bat check      validate the data and the art (headless)
rem    game.bat godot      open the project in the Godot editor
rem
rem  The engine version is pinned deliberately (docs/TECH_SPEC.md section 1).
rem  A Godot already on your PATH is used only if it is that version, so a
rem  4.4 or 4.9 install lying around cannot quietly change how the game runs.
rem ============================================================================

rem Work from the repo root, wherever this was launched from.
cd /d "%~dp0"

set "GODOT_VERSION=4.7.1"
set "GODOT_BUILD=Godot_v%GODOT_VERSION%-stable_win64"
set "GODOT_DIR=%~dp0bin"
set "GODOT_EXE=%GODOT_DIR%\%GODOT_BUILD%.exe"
set "GODOT_URL=https://github.com/godotengine/godot/releases/download/%GODOT_VERSION%-stable/%GODOT_BUILD%.exe.zip"
set "GODOT_ZIP=%GODOT_DIR%\godot.zip"

set "MODE=%~1"
if "%MODE%"=="" set "MODE=play"

if /i "%MODE%"=="help"   goto :usage
if /i "%MODE%"=="/?"     goto :usage
if /i "%MODE%"=="-h"     goto :usage
if /i "%MODE%"=="--help" goto :usage

call :find_godot
if errorlevel 1 goto :failed

call :first_run_import
if errorlevel 1 goto :failed

rem Dispatch by name rather than "goto :run_%MODE%": a jump to a label that does
rem not exist aborts the script with a bare error, which is a poor way to learn
rem you made a typo.
if /i "%MODE%"=="play"   goto :run_play
if /i "%MODE%"=="editor" goto :run_editor
if /i "%MODE%"=="lab"    goto :run_lab
if /i "%MODE%"=="level"  goto :run_level
if /i "%MODE%"=="test"   goto :run_test
if /i "%MODE%"=="tests"  goto :run_test
if /i "%MODE%"=="check"  goto :run_check
if /i "%MODE%"=="godot"  goto :run_godot
goto :unknown_mode


rem ---------------------------------------------------------------------------
rem  Finding the engine
rem ---------------------------------------------------------------------------
:find_godot
rem 1. An explicit override always wins, for anyone running a custom build.
if defined GODOT (
  if exist "%GODOT%" (
    set "GODOT_EXE=%GODOT%"
    echo Using Godot from the GODOT variable: "!GODOT_EXE!"
    exit /b 0
  )
  echo GODOT is set to "%GODOT%" but there is no file there. Ignoring it.
)

rem 2. A copy this script downloaded earlier.
if exist "%GODOT_EXE%" (
  echo Using Godot %GODOT_VERSION% from bin\.
  exit /b 0
)

rem 3. One already on the PATH, but only at the pinned version.
where godot.exe >nul 2>&1
if not errorlevel 1 (
  for /f "usebackq tokens=*" %%v in (`godot.exe --version 2^>nul`) do set "FOUND=%%v"
  echo !FOUND! | findstr /b /c:"%GODOT_VERSION%" >nul
  if not errorlevel 1 (
    set "GODOT_EXE=godot.exe"
    echo Using Godot !FOUND! from your PATH.
    exit /b 0
  )
  echo Found Godot !FOUND! on your PATH, but this project is pinned to %GODOT_VERSION%.
  echo Downloading the pinned build instead - your install is left alone.
)

rem 4. Fetch it. About 84 MB, once.
echo.
echo Godot %GODOT_VERSION% is not here yet. Downloading it into bin\ ...
echo   %GODOT_URL%
if not exist "%GODOT_DIR%" mkdir "%GODOT_DIR%"

rem $ProgressPreference is the difference between seconds and minutes: the
rem progress bar Invoke-WebRequest draws costs more than the download does.
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ProgressPreference='SilentlyContinue';" ^
  "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;" ^
  "try { Invoke-WebRequest -Uri '%GODOT_URL%' -OutFile '%GODOT_ZIP%' } catch { Write-Host $_.Exception.Message; exit 1 }"
if errorlevel 1 (
  echo.
  echo Could not download Godot. Check your connection, or install Godot %GODOT_VERSION%
  echo yourself from https://godotengine.org/download and either put it on your
  echo PATH or set GODOT to the full path of the .exe, then run this again.
  exit /b 1
)

echo Unpacking ...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "try { Expand-Archive -Path '%GODOT_ZIP%' -DestinationPath '%GODOT_DIR%' -Force } catch { Write-Host $_.Exception.Message; exit 1 }"
if errorlevel 1 (
  echo Could not unpack "%GODOT_ZIP%".
  exit /b 1
)
del /q "%GODOT_ZIP%" >nul 2>&1

if not exist "%GODOT_EXE%" (
  rem The archive layout has changed between releases before, so find the
  rem executable rather than assuming where it landed. The console build sits
  rem beside the normal one and is not the one to launch.
  for %%f in ("%GODOT_DIR%\Godot_v*_win64.exe") do (
    echo %%~nf | findstr /i "console" >nul
    if errorlevel 1 set "GODOT_EXE=%%~ff"
  )
)
if not exist "%GODOT_EXE%" (
  echo Downloaded the archive but could not find the Godot executable inside it.
  exit /b 1
)
echo Godot %GODOT_VERSION% is ready.
exit /b 0


rem ---------------------------------------------------------------------------
rem  First run: import the assets
rem ---------------------------------------------------------------------------
:first_run_import
if exist ".godot\imported" exit /b 0

echo.
echo First run - importing assets. This takes a minute and happens only once.
rem Twice on purpose: the first pass registers the global classes, the second
rem imports everything that depends on them.
"%GODOT_EXE%" --headless --import >nul 2>&1
"%GODOT_EXE%" --headless --import
if errorlevel 1 (
  echo.
  echo Import failed. Run "game.bat check" to see what the validator says.
  exit /b 1
)
echo Import done.
exit /b 0


rem ---------------------------------------------------------------------------
rem  What to run
rem ---------------------------------------------------------------------------
:run_play
echo.
echo Starting Scribblestein. Build a creature in the Lab, then WORLD MAP to play.
"%GODOT_EXE%"
goto :done

:run_editor
echo Opening the level editor.
"%GODOT_EXE%" -- --scene=editor --level=level_01_margins
goto :done

:run_lab
"%GODOT_EXE%" -- --scene=lab
goto :done

:run_level
"%GODOT_EXE%" -- --scene=level_01_margins
goto :done

:run_test
echo Running the test suite. This takes a few minutes.
"%GODOT_EXE%" --headless -s tools/run_tests.gd
goto :done

:run_check
echo Validating art and data ...
"%GODOT_EXE%" --headless -s tools/validate_assets.gd
if errorlevel 1 goto :failed
echo.
echo Booting to check the data files ...
"%GODOT_EXE%" --headless --quit
goto :done

:run_godot
echo Opening the project in the Godot editor.
"%GODOT_EXE%" -e
goto :done


rem ---------------------------------------------------------------------------
:usage
echo.
echo   Scribblestein - a 2D creature-builder platformer (Godot %GODOT_VERSION%)
echo.
echo   game.bat            play the game
echo   game.bat editor     the level editor
echo   game.bat lab        straight into the Lab
echo   game.bat level      straight into Level 01 "The Margins"
echo   game.bat test       run the test suite
echo   game.bat check      validate the art and the data
echo   game.bat godot      open the project in the Godot editor
echo.
echo   Controls: A/D move - Space jump (hold to glide, tap again to double jump)
echo             W climb - S roll/crouch - LMB/J attack - RMB/K tail - Esc pause
echo.
echo   Your save and any levels or music you make live in
echo     %%APPDATA%%\Godot\app_userdata\Scribblestein
echo.
goto :eof


:unknown_mode
echo Unknown option "%MODE%".
goto :usage


:failed
echo.
echo Something went wrong. See the messages above.
pause
exit /b 1


:done
if errorlevel 1 (
  echo.
  echo Godot exited with an error.
  pause
  exit /b 1
)
exit /b 0
