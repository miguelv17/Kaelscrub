@echo off
REM ============================================================
REM  Lanzador de doble clic para Mantenimiento_Windows.ps1
REM  Debe estar en la MISMA carpeta que el archivo .ps1.
REM  El propio script pedira permisos de administrador solo.
REM ============================================================

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Mantenimiento_Windows.ps1"
pause
