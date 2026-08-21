@ECHO off
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0gh-mock.ps1" %*
