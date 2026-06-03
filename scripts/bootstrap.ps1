#Requires -Version 5.1
<#
.SYNOPSIS
    Bootstrap automatico do videokit em Windows: FFmpeg + Python 3.12+ + pip core.

.DESCRIPTION
    Deteta o que esta em falta e instala via winget (sem privilegios admin).
    Em seguida instala pacotes Python core: openai-whisper, mediapipe, opencv-python.
    Para features adicionais (diarization, translation, tts, audio-separation, bg-removal)
    usa install-feature.ps1.

.PARAMETER AutoYes
    Nao perguntar; instalar tudo o que faltar. Util para Claude Code workflow.

.PARAMETER CheckOnly
    So reportar o que falta. Exit 0 se tudo OK, exit 1 se algo em falta.

.PARAMETER SkipFFmpeg
    Saltar instalacao de FFmpeg.

.PARAMETER SkipPython
    Saltar instalacao de Python.

.PARAMETER SkipPip
    Saltar instalacao de pacotes pip core.

.EXAMPLE
    .\bootstrap.ps1                  # interativo, pergunta antes de instalar
    .\bootstrap.ps1 -AutoYes         # auto, sem perguntar
    .\bootstrap.ps1 -CheckOnly       # so reporta
#>

param(
    [switch]$AutoYes,
    [switch]$CheckOnly,
    [switch]$SkipFFmpeg,
    [switch]$SkipPython,
    [switch]$SkipPip
)

$ErrorActionPreference = "Stop"

# --- Helpers ---

function Test-Cmd {
    param([string]$Command)
    try { $null = Get-Command $Command -ErrorAction Stop; return $true } catch { return $false }
}

function Test-Python312 {
    if (-not (Test-Cmd "python")) { return $false }
    try {
        $output = python --version 2>&1
        if ($output -match "Python (\d+)\.(\d+)") {
            $major = [int]$matches[1]
            $minor = [int]$matches[2]
            return ($major -gt 3) -or ($major -eq 3 -and $minor -ge 12)
        }
    } catch {}
    return $false
}

function Test-Winget {
    return (Test-Cmd "winget")
}

function Confirm-Install {
    param([string]$Question)
    if ($AutoYes) { return $true }
    $response = Read-Host "$Question (Y/n)"
    if ([string]::IsNullOrEmpty($response)) { return $true }
    return ($response.ToLowerInvariant() -in @("y","yes","s","sim"))
}

function Install-WingetPackage {
    param([string]$Id, [string]$Name)
    Write-Host "  A instalar $Name via winget..." -ForegroundColor Cyan
    & winget install --id $Id --accept-source-agreements --accept-package-agreements --silent
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "winget retornou exit $LASTEXITCODE (pode ser 'ja instalado' ou falha real)"
    }
}

function Refresh-Path {
    $machinePath = [System.Environment]::GetEnvironmentVariable("PATH", "Machine")
    $userPath = [System.Environment]::GetEnvironmentVariable("PATH", "User")
    $env:PATH = "$machinePath;$userPath"
}

# --- Header ---

Write-Host ""
Write-Host "=== videokit bootstrap (Windows) ===" -ForegroundColor Green
Write-Host ""

# --- Verificacoes iniciais ---

$hasFFmpeg = Test-Cmd "ffmpeg"
$hasPython312 = Test-Python312
$hasWinget = Test-Winget

Write-Host "Estado atual:"
Write-Host "  ffmpeg:        $(if ($hasFFmpeg) { 'OK' } else { 'EM FALTA' })" -ForegroundColor $(if ($hasFFmpeg) { 'Green' } else { 'Yellow' })
Write-Host "  Python 3.12+:  $(if ($hasPython312) { 'OK' } else { 'EM FALTA' })" -ForegroundColor $(if ($hasPython312) { 'Green' } else { 'Yellow' })
Write-Host "  winget:        $(if ($hasWinget) { 'OK' } else { 'EM FALTA' })" -ForegroundColor $(if ($hasWinget) { 'Green' } else { 'Red' })
Write-Host ""

# --- Check-only mode ---

if ($CheckOnly) {
    if ($hasFFmpeg -and $hasPython312) {
        Write-Host "Tudo OK." -ForegroundColor Green
        exit 0
    } else {
        Write-Host "Algo em falta. Corre sem -CheckOnly para instalar." -ForegroundColor Yellow
        exit 1
    }
}

# --- Pre-requisito: winget ---

if (-not $hasWinget) {
    if ((-not $hasFFmpeg -and -not $SkipFFmpeg) -or (-not $hasPython312 -and -not $SkipPython)) {
        Write-Error "winget nao disponivel. Necessario para instalar FFmpeg/Python automaticamente."
        Write-Host ""
        Write-Host "Instala 'App Installer' da Microsoft Store, ou descarrega manualmente:" -ForegroundColor Yellow
        Write-Host "  FFmpeg: https://www.gyan.dev/ffmpeg/builds/  (descarrega full build, adiciona ao PATH)"
        Write-Host "  Python: https://www.python.org/downloads/  (3.12+, marca 'Add to PATH')"
        exit 1
    }
}

# --- FFmpeg ---

if (-not $hasFFmpeg -and -not $SkipFFmpeg) {
    if (Confirm-Install "Instalar FFmpeg via winget?") {
        Install-WingetPackage -Id "Gyan.FFmpeg" -Name "FFmpeg"
        Refresh-Path
        if (Test-Cmd "ffmpeg") {
            Write-Host "  OK FFmpeg instalado" -ForegroundColor Green
        } else {
            Write-Warning "FFmpeg instalado mas nao detetado no PATH desta sessao. Reabre o terminal e tenta de novo."
        }
    } else {
        Write-Host "  Skip FFmpeg."
    }
}

# --- Python 3.12+ ---

if (-not $hasPython312 -and -not $SkipPython) {
    if (Confirm-Install "Instalar Python 3.13 via winget?") {
        Install-WingetPackage -Id "Python.Python.3.13" -Name "Python 3.13"
        Refresh-Path
        if (Test-Python312) {
            Write-Host "  OK Python 3.13 instalado" -ForegroundColor Green
        } else {
            Write-Warning "Python instalado mas nao detetado. Reabre o terminal e tenta de novo."
            exit 1
        }
    } else {
        Write-Host "  Skip Python."
    }
}

# --- pip core packages ---

if (-not $SkipPip) {
    $pythonBin = Get-Command python -ErrorAction SilentlyContinue
    if ($pythonBin) {
        Write-Host ""
        Write-Host "A instalar pacotes Python core (whisper, mediapipe, opencv)..." -ForegroundColor Cyan
        Write-Host "(download ~300MB-1GB, demora alguns minutos)"

        & python -m pip install --user --upgrade pip 2>&1 | Out-Host
        & python -m pip install --user --upgrade openai-whisper mediapipe opencv-python 2>&1 | Out-Host

        if ($LASTEXITCODE -eq 0) {
            Write-Host "  OK pacotes core instalados" -ForegroundColor Green
        } else {
            Write-Warning "pip exit $LASTEXITCODE"
            exit 1
        }
    } else {
        Write-Warning "Python nao disponivel. Skip pip install."
    }
}

# --- Sumario ---

Write-Host ""
Write-Host "=== bootstrap concluido ===" -ForegroundColor Green
Write-Host ""
Write-Host "Para features adicionais, usa install-feature.ps1:"
Write-Host "  .\install-feature.ps1 diarization        # pyannote-audio + torch"
Write-Host "  .\install-feature.ps1 translation        # argostranslate"
Write-Host "  .\install-feature.ps1 tts                # piper-tts"
Write-Host "  .\install-feature.ps1 audio-separation   # demucs + torch"
Write-Host "  .\install-feature.ps1 bg-removal         # rembg"
Write-Host "  .\install-feature.ps1 all                # tudo (~5GB download)"
Write-Host ""
Write-Host "Agora corre detect-env.ps1 para verificar e popular cache/env-report.json:"
Write-Host "  .\detect-env.ps1"
