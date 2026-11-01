@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul
echo ============================================
echo   UEVR ???? ????
echo   ??? %%APPDATA%%\UnrealVRMod\*\scripts
echo ============================================
echo.
set "ROOT=%APPDATA%\UnrealVRMod"
set /a N=0
if not exist "%ROOT%" goto noroot
for /d %%D in ("%ROOT%\*") do (
  if exist "%%D\scripts" (
    copy /Y "%~dp0walkinplace.lua" "%%D\scripts\uevr_walkinplace.lua" >nul
    echo   [??] %%D\scripts
    set /a N+=1
  )
)
if !N!==0 goto noscripts
echo.
echo ??? !N! ?????????? UEVR ???? Reload Script?
goto end
:noroot
echo [X] ??? %ROOT%
echo     ??? UEVR ?????????????????
goto end
:noscripts
echo [!] ??? scripts ?????? UEVR ???????
:end
echo.
pause
