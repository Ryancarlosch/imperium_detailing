Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-ComandoFlutter {
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

$diretorioScript = Split-Path -Parent $MyInvocation.MyCommand.Path
$raizProjeto = Split-Path -Parent $diretorioScript
$pubspec = Join-Path $raizProjeto 'pubspec.yaml'

if (-not (Test-Path $pubspec)) {
    throw "pubspec.yaml nao encontrado em: $pubspec"
}

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Flutter nao foi encontrado no PATH.'
}

Push-Location $raizProjeto

try {
    $conteudoOriginal = [System.IO.File]::ReadAllText($pubspec)
    $padraoVersao = '(?m)^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$'
    $correspondencia = [System.Text.RegularExpressions.Regex]::Match(
        $conteudoOriginal,
        $padraoVersao
    )

    if (-not $correspondencia.Success) {
        throw 'Nao foi possivel localizar uma linha version: X.Y.Z+BUILD no pubspec.yaml.'
    }

    $major = [int]$correspondencia.Groups[1].Value
    $minor = [int]$correspondencia.Groups[2].Value
    $patch = [int]$correspondencia.Groups[3].Value
    $build = [int]$correspondencia.Groups[4].Value

    $novaVersaoNome = "$major.$minor.$($patch + 1)"
    $novoBuild = $build + 1
    $novaVersaoCompleta = "$novaVersaoNome+$novoBuild"

    Write-Host ''
    Write-Host 'Imperium Detailing - Geracao de APK Release' -ForegroundColor Yellow
    Write-Host "Versao atual : $major.$minor.$patch+$build"
    Write-Host "Nova versao  : $novaVersaoCompleta" -ForegroundColor Green

    Invoke-ComandoFlutter -Descricao 'Resolver dependencias' -Comando {
        flutter pub get
    }

    Invoke-ComandoFlutter -Descricao 'Gerar APK release' -Comando {
        flutter build apk --release --build-name $novaVersaoNome --build-number $novoBuild
    }

    $apkPadrao = Join-Path $raizProjeto 'build\app\outputs\flutter-apk\app-release.apk'
    $pastaReleases = Join-Path $raizProjeto 'build\releases'
    $nomeArquivoVersionado = "imperium-detailing-v$novaVersaoNome-build$novoBuild.apk"
    $apkVersionado = Join-Path $pastaReleases $nomeArquivoVersionado

    if (-not (Test-Path $apkPadrao)) {
        throw "O Flutter informou sucesso, mas o APK nao foi encontrado em: $apkPadrao"
    }

    New-Item -ItemType Directory -Path $pastaReleases -Force | Out-Null
    Copy-Item -Path $apkPadrao -Destination $apkVersionado -Force

    $novaLinha = "version: $novaVersaoCompleta"
    $regexVersao = New-Object System.Text.RegularExpressions.Regex($padraoVersao)
    $conteudoAtualizado = $regexVersao.Replace(
        $conteudoOriginal,
        $novaLinha,
        1
    )

    $utf8SemBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($pubspec, $conteudoAtualizado, $utf8SemBom)

    Write-Host ''
    Write-Host 'APK GERADO COM SUCESSO.' -ForegroundColor Green
    Write-Host "Versao gravada no pubspec: $novaVersaoCompleta"
    Write-Host "APK padrao               : $apkPadrao"
    Write-Host "Copia versionada          : $apkVersionado"
    Write-Host ''
} catch {
    Write-Host ''
    Write-Host 'FALHA AO GERAR APK.' -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host 'A versao do pubspec.yaml nao foi alterada.' -ForegroundColor Yellow
    exit 1
} finally {
    Pop-Location
}
