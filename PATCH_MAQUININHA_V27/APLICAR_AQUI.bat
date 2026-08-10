@echo off
setlocal EnableExtensions
title Imperium - Aplicar Regras da Maquininha V27

echo ==================================================
echo   IMPERIUM - REGRAS DA MAQUININHA V27
echo ==================================================
echo.

REM O projeto precisa ser a pasta PAI desta pasta PATCH.
for %%I in ("%~dp0..") do set "PROJETO=%%~fI"
set "PATCH=%~dp0"

echo Pasta detectada do projeto:
echo %PROJETO%
echo.

if not exist "%PROJETO%\pubspec.yaml" (
  echo ERRO: Nao encontrei pubspec.yaml na pasta acima desta PATCH.
  echo.
  echo A estrutura precisa ficar assim:
  echo.
  echo   SUA_PASTA_DO_IMPERIUM\
  echo     pubspec.yaml
  echo     lib\
  echo     PATCH_MAQUININHA_V27\
  echo       APLICAR_AQUI.bat
  echo.
  echo Mova a pasta PATCH_MAQUININHA_V27 inteira para dentro
  echo da pasta principal do projeto e execute novamente.
  echo.
  pause
  exit /b 1
)

if not exist "%PROJETO%\lib\pages" (
  echo ERRO: Nao encontrei lib\pages no projeto.
  pause
  exit /b 1
)

if not exist "%PROJETO%\lib\repositories" (
  echo ERRO: Nao encontrei lib\repositories no projeto.
  pause
  exit /b 1
)

if not exist "%PATCH%arquivos\lib\pages\pagamentos_page.dart" (
  echo ERRO: Arquivo pagamentos_page.dart nao encontrado dentro da PATCH.
  pause
  exit /b 1
)

if not exist "%PATCH%arquivos\lib\pages\regras_taxa_page.dart" (
  echo ERRO: Arquivo regras_taxa_page.dart nao encontrado dentro da PATCH.
  pause
  exit /b 1
)

if not exist "%PATCH%arquivos\lib\repositories\pagamento_repository.dart" (
  echo ERRO: Arquivo pagamento_repository.dart nao encontrado dentro da PATCH.
  pause
  exit /b 1
)

set "BACKUP=%PROJETO%\backup_regras_maquininha_%RANDOM%_%RANDOM%"

echo Criando backup em:
echo %BACKUP%
echo.

mkdir "%BACKUP%\lib\pages" >nul 2>&1
mkdir "%BACKUP%\lib\repositories" >nul 2>&1

if exist "%PROJETO%\lib\pages\pagamentos_page.dart" (
  copy /Y "%PROJETO%\lib\pages\pagamentos_page.dart" "%BACKUP%\lib\pages\pagamentos_page.dart" >nul
)

if exist "%PROJETO%\lib\pages\regras_taxa_page.dart" (
  copy /Y "%PROJETO%\lib\pages\regras_taxa_page.dart" "%BACKUP%\lib\pages\regras_taxa_page.dart" >nul
)

if exist "%PROJETO%\lib\repositories\pagamento_repository.dart" (
  copy /Y "%PROJETO%\lib\repositories\pagamento_repository.dart" "%BACKUP%\lib\repositories\pagamento_repository.dart" >nul
)

echo Substituindo arquivos...
echo.

copy /Y "%PATCH%arquivos\lib\pages\pagamentos_page.dart" "%PROJETO%\lib\pages\pagamentos_page.dart" >nul
if errorlevel 1 goto :erro

copy /Y "%PATCH%arquivos\lib\pages\regras_taxa_page.dart" "%PROJETO%\lib\pages\regras_taxa_page.dart" >nul
if errorlevel 1 goto :erro

copy /Y "%PATCH%arquivos\lib\repositories\pagamento_repository.dart" "%PROJETO%\lib\repositories\pagamento_repository.dart" >nul
if errorlevel 1 goto :erro

echo ==================================================
echo   ALTERACOES APLICADAS COM SUCESSO
echo ==================================================
echo.
echo Backup salvo em:
echo %BACKUP%
echo.
echo Agora, na pasta do projeto, rode:
echo.
echo   flutter analyze
echo   flutter test
echo   flutter build apk --release
echo.
pause
exit /b 0

:erro
echo.
echo ==================================================
echo ERRO AO COPIAR OS ARQUIVOS
echo ==================================================
echo.
echo O backup foi mantido em:
echo %BACKUP%
echo.
echo Tire uma foto desta tela e envie para o ChatGPT.
echo.
pause
exit /b 1
