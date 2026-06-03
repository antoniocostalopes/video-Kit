#Requires -Version 5.1
<#
.SYNOPSIS
    Descarrega modelos e assets gratuitos necessarios para a skill (RNNoise, LUTs, etc.).
    Idempotente: so descarrega o que falta.

.PARAMETER What
    'rnnoise', 'all'. Default: 'all'.
#>

param(
    [ValidateSet("rnnoise","all")]
    [string]$What = "all"
)

$ErrorActionPreference = "Stop"
$SkillDir = Split-Path -Parent $PSScriptRoot

function Fetch-IfMissing {
    param([string]$Url, [string]$Destination, [string]$Description)
    if (Test-Path $Destination) {
        Write-Host "OK ja existe: $Description"
        return
    }
    $dir = Split-Path -Parent $Destination
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    Write-Host "  A descarregar $Description..."
    try {
        Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing
        $size = (Get-Item $Destination).Length
        Write-Host "  OK ($([math]::Round($size / 1KB, 1)) KB) -> $Destination" -ForegroundColor Green
    } catch {
        Write-Error "Falhou: $($_.Exception.Message)"
        throw
    }
}

if ($What -eq "rnnoise" -or $What -eq "all") {
    Write-Host "RNNoise models (denoise para arnndn filter)..."
    # cb.rnnn = conjoined burgers, modelo geral para voz humana
    $rnDir = Join-Path $SkillDir "assets\audio-models"
    Fetch-IfMissing `
        -Url "https://raw.githubusercontent.com/GregorR/rnnoise-models/master/conjoined-burgers-2018-08-28/cb.rnnn" `
        -Destination (Join-Path $rnDir "cb.rnnn") `
        -Description "RNNoise model cb.rnnn"
}

Write-Host ""
Write-Host "OK Assets verificados." -ForegroundColor Green
