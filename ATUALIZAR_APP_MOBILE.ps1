param(
    [switch]$SemGit,
    [switch]$SemTestes,
    [switch]$NaoInstalar
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Etapa {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Descricao,
        [Parameter(Mandatory = $true)]
        [scriptblock]$Comando
    )

    Write-Host ''
    Write-Host "==> $Descricao" -ForegroundColor Cyan
    & $Comando

    if ($LASTEXITCODE -ne 0) {
        throw "$Descricao falhou com codigo de saida $LASTEXITCODE."
    }
}

$raizProjeto = Split-Path -Parent $MyInvocation.MyCommand.Path
$pubspec = Join-Path $raizProjeto 'pubspec.yaml'
$apkPadrao = Join-Path $raizProjeto 'build\app\outputs\flutter-apk\app-release.apk'
$pastaReleases = Join-Path $raizProjeto 'build\releases'
$apkTeste = Join-Path $pastaReleases 'imperium-manager-mobile-latest.apk'

if (-not (Test-Path $pubspec)) {
    throw "pubspec.yaml nao encontrado em: $pubspec"
}

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Flutter nao foi encontrado no PATH.'
}

Push-Location $raizProjeto

try {
    Write-Host ''
    Write-Host '=============================================' -ForegroundColor Yellow
    Write-Host ' IMPERIUM MANAGER - ATUALIZAR APP MOBILE' -ForegroundColor Yellow
    Write-Host '=============================================' -ForegroundColor Yellow

    if (-not $SemGit) {
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
            throw 'Git nao foi encontrado no PATH. Use -SemGit somente se os arquivos ja estiverem atualizados.'
        }

        $alteracoes = @(git status --porcelain)
        if ($LASTEXITCODE -ne 0) {
            throw 'Nao foi possivel verificar o estado do Git.'
        }

        if ($alteracoes.Count -gt 0) {
            Write-Host ''
            Write-Host 'Existem alteracoes locais ainda nao salvas no Git.' -ForegroundColor Yellow
            Write-Host 'Para proteger seu trabalho, o script NAO vai sobrescrever esses arquivos.' -ForegroundColor Yellow
            Write-Host 'Depois de salvar/commit essas alteracoes, execute novamente.' -ForegroundColor Yellow
            Write-Host 'Se voce sabe que os arquivos locais ja sao os corretos, use:' -ForegroundColor Yellow
            Write-Host '  .\ATUALIZAR_APP_MOBILE.ps1 -SemGit' -ForegroundColor White
            throw 'Atualizacao Git interrompida por seguranca.'
        }

        Invoke-Etapa -Descricao 'Buscar atualizacoes da branch desenvolvimento' -Comando {
            git fetch origin desenvolvimento
        }

        Invoke-Etapa -Descricao 'Selecionar branch desenvolvimento' -Comando {
            git checkout desenvolvimento
        }

        Invoke-Etapa -Descricao 'Atualizar codigo do Imperium' -Comando {
            git pull --ff-only origin desenvolvimento
        }
    }

    Invoke-Etapa -Descricao 'Resolver dependencias Flutter' -Comando {
        flutter pub get
    }

    Invoke-Etapa -Descricao 'Validar formatacao Dart' -Comando {
        dart format --output=none --set-exit-if-changed lib test
    }

    Invoke-Etapa -Descricao 'Flutter analyze' -Comando {
        flutter analyze
    }

    if (-not $SemTestes) {
        Invoke-Etapa -Descricao 'Executar testes' -Comando {
            flutter test
        }
    }

    Invoke-Etapa -Descricao 'Gerar APK release' -Comando {
        flutter build apk --release
    }

    if (-not (Test-Path $apkPadrao)) {
        throw "APK nao encontrado em: $apkPadrao"
    }

    New-Item -ItemType Directory -Path $pastaReleases -Force | Out-Null
    Copy-Item -Path $apkPadrao -Destination $apkTeste -Force

    Write-Host ''
    Write-Host 'APK GERADO COM SUCESSO.' -ForegroundColor Green
    Write-Host "APK: $apkTeste" -ForegroundColor Green

    if (-not $NaoInstalar) {
        $adb = Get-Command adb -ErrorAction SilentlyContinue
        if ($null -eq $adb) {
            Write-Host ''
            Write-Host 'ADB nao encontrado no PATH. O APK foi gerado, mas nao foi instalado automaticamente.' -ForegroundColor Yellow
        } else {
            $linhasDispositivos = @(& adb devices)
            if ($LASTEXITCODE -ne 0) {
                throw 'Falha ao consultar dispositivos pelo ADB.'
            }

            $dispositivos = @(
                $linhasDispositivos | Where-Object {
                    $_ -match "\tdevice$"
                }
            )

            if ($dispositivos.Count -eq 0) {
                Write-Host ''
                Write-Host 'Nenhum celular Android autorizado foi encontrado pelo ADB.' -ForegroundColor Yellow
                Write-Host 'Conecte o celular com Depuracao USB ativa e execute novamente, ou instale o APK manualmente.' -ForegroundColor Yellow
            } else {
                Invoke-Etapa -Descricao 'Atualizar aplicativo no celular sem apagar os dados' -Comando {
                    adb install -r $apkPadrao
                }
                Write-Host ''
                Write-Host 'APP ATUALIZADO NO CELULAR COM SUCESSO.' -ForegroundColor Green
            }
        }
    }

    Write-Host ''
    Write-Host 'Pronto para testar:' -ForegroundColor Green
    Write-Host '1. Abra o Imperium Manager no celular.'
    Write-Host '2. Entre com o MESMO e-mail e senha usados no Web.'
    Write-Host '3. Confirme se empresa, plano e dados sincronizados aparecem corretamente.'
    Write-Host ''
} catch {
    Write-Host ''
    Write-Host 'FALHA NA ATUALIZACAO DO APP.' -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
} finally {
    Pop-Location
}
