@echo off
rem PowerShell and cmd entry point for ai\helpers\leak-check.sh; leak-check is the one for Git Bash.
rem Git for Windows puts git on PATH but not sh, so sh is found beside git: <Git>\cmd\git.exe -> <Git>\bin\sh.exe
setlocal
set "SH=sh"
where sh >nul 2>nul && goto run
set "GITEXE="
for /f "delims=" %%G in ('where git 2^>nul') do if not defined GITEXE set "GITEXE=%%G"
if not defined GITEXE (echo leak-check: neither sh nor git is on PATH; install Git for Windows 1>&2 & exit /b 1)
for %%D in ("%GITEXE%\..\..") do set "SH=%%~fD\bin\sh.exe"
if not exist "%SH%" (echo leak-check: no Git Bash sh.exe at %SH% 1>&2 & exit /b 1)
:run
"%SH%" "%~dp0..\ai\helpers\leak-check.sh" %*
