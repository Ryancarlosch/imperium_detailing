param(
    [switch]$CorrigirFormatacao
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$raizProjeto = Split-Path -Parent $PSScriptRoot

if (-not (Test-Path (Join-Path $raizProjeto 'pubspec.yaml'))) {
    Write-Host 'ERRO: pubspec.yaml nao encontrado.' -ForegroundColor Red
    Write-Host 'Mantenha este arquivo dentro da pasta scripts do projeto.' -ForegroundColor Yellow
    exit 1
}

function Executar-Etapa {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Titulo,

        [Parameter(Mandatory = $true)]
        [scriptblock]$Acao
    )

    Write-Host ''
    Write-Host '============================================================' -ForegroundColor DarkGray
    Write-Host $Titulo -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor DarkGray

    & $Acao

    if ($LASTEXITCODE -ne 0) {
        Write-Host ''
        Write-Host "FALHA: $Titulo" -ForegroundColor Red
        exit $LASTEXITCODE
    }

    Write-Host "OK: $Titulo" -ForegroundColor Green
}

Push-Location $raizProjeto

try {
    Write-Host ''
    Write-Host 'VALIDACAO DO PROJETO IMPERIUM DETAILING' -ForegroundColor Yellow
    Write-Host "Inicio: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')"
    Write-Host "Projeto: $raizProjeto"

    Executar-Etapa -Titulo '1. Restaurar dependencias' -Acao {
        flutter pub get
    }

    if ($CorrigirFormatacao) {
        Executar-Etapa -Titulo '2. Corrigir formatacao' -Acao {
            dart format lib test
        }
    }
    else {
        Executar-Etapa -Titulo '2. Verificar formatacao' -Acao {
            dart format --output=none --set-exit-if-changed lib test
        }
    }

    Executar-Etapa -Titulo '3. Executar Flutter Analyze' -Acao {
        flutter analyze
    }

    Executar-Etapa -Titulo '4. Executar testes automatizados' -Acao {
        flutter test
    }

    Executar-Etapa -Titulo '5. Verificar problemas de espacos no Git' -Acao {
        git diff --check
    }

    Write-Host ''
    Write-Host 'STATUS ATUAL DO GIT' -ForegroundColor Cyan
    git status --short

    if ($LASTEXITCODE -ne 0) {
        Write-Host 'Nao foi possivel consultar o Git.' -ForegroundColor Yellow
    }

    Write-Host ''
    Write-Host 'VALIDACAO CONCLUIDA COM SUCESSO.' -ForegroundColor Green
    Write-Host "Fim: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')"
}
catch {
    Write-Host ''
    Write-Host "ERRO INESPERADO: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
finally {
    Pop-Location
}
