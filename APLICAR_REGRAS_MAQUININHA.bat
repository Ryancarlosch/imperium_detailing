@echo off
setlocal

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0APLICAR_REGRAS_MAQUININHA.ps1" -Projeto "%CD%"

if errorlevel 1 (
  echo.
  echo ERRO ao aplicar as alteracoes.
  pause
  exit /b 1
)

echo.
echo Arquivos substituidos com sucesso.
pause
