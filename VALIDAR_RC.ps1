$ErrorActionPreference = 'Stop'

function Invoke-ImperiumStep {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [scriptblock]$Action
    )

    Write-Host ""
    Write-Host "==> $Name"
    & $Action

    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "FALHA RC: $Name (codigo $LASTEXITCODE)"
        exit $LASTEXITCODE
    }
}

$raizProjeto = Split-Path -Parent $MyInvocation.MyCommand.Path
Push-Location $raizProjeto

try {
    Write-Host ""
    Write-Host "============================================="
    Write-Host " IMPERIUM MANAGER - VALIDACAO RELEASE CANDIDATE"
    Write-Host "============================================="

    Invoke-ImperiumStep -Name "Flutter pub get" -Action {
        flutter pub get
    }

    Invoke-ImperiumStep -Name "Formatacao Dart" -Action {
        dart format --output=none --set-exit-if-changed lib test
    }

    Invoke-ImperiumStep -Name "Flutter analyze" -Action {
        flutter analyze
    }

    Invoke-ImperiumStep -Name "Flutter test" -Action {
        flutter test
    }

    Invoke-ImperiumStep -Name "Build Android release" -Action {
        flutter build apk --release
    }

    Invoke-ImperiumStep -Name "Build Web release" -Action {
        flutter build web --target lib/main_web_bootstrap.dart --release
    }

    Invoke-ImperiumStep -Name "Git diff check" -Action {
        git diff --check
    }

    Write-Host ""
    Write-Host "RELEASE CANDIDATE ANDROID/WEB APROVADO."
} finally {
    Pop-Location
}
