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
        Write-Host "FALHA: $Name (codigo $LASTEXITCODE)"
        exit $LASTEXITCODE
    }
}

Invoke-ImperiumStep -Name "Flutter analyze" -Action {
    flutter analyze
}

Invoke-ImperiumStep -Name "Flutter test" -Action {
    flutter test
}

Invoke-ImperiumStep -Name "Git diff check" -Action {
    git diff --check
}

Write-Host ""
Write-Host "VALIDACAO IMPERIUM APROVADA."
