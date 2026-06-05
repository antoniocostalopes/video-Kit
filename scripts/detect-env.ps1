#Requires -Version 5.1
<#
.SYNOPSIS
    Deteta ferramentas instaladas e escreve cache/env-report.json no workspace atual.

.DESCRIPTION
    Procura caminhos absolutos de ffmpeg, ffprobe, python.
    Verifica se openai-whisper esta instalado.
    Verifica suporte de libass no ffmpeg.
    Output em cache/env-report.json (UTF-8 sem BOM).

.PARAMETER WorkspaceDir
    Pasta onde criar cache/env-report.json. Default: pasta da skill (~/.claude/skills/videokit/).
    Override apenas para testes ou setups customizados.

.EXAMPLE
    .\detect-env.ps1
    # escreve em ~/.claude/skills/videokit/cache/env-report.json
#>

param(
    [string]$WorkspaceDir = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"

function Get-AbsolutePath {
    param([string]$Command)
    try {
        $cmd = Get-Command $Command -ErrorAction Stop
        return $cmd.Source
    } catch {
        return $null
    }
}

function Test-WhisperInstalled {
    param([string]$PythonBin)
    if (-not $PythonBin) { return $false }
    try {
        $out = & $PythonBin -c "import whisper; print('ok')" 2>&1
        return ($out -match "^ok")
    } catch {
        return $false
    }
}

function Test-LibassSupport {
    param([string]$FfmpegBin)
    if (-not $FfmpegBin) { return $false }
    try {
        $out = cmd /c "`"$FfmpegBin`" -hide_banner -filters 2>&1"
        return ($out -match "subtitles")
    } catch {
        return $false
    }
}

function Get-HwEncoders {
    param([string]$FfmpegBin)
    $result = [ordered]@{
        nvenc = $false
        videotoolbox = $false
        qsv = $false
        amf = $false
    }
    if (-not $FfmpegBin) { return $result }
    try {
        $out = cmd /c "`"$FfmpegBin`" -hide_banner -encoders 2>&1"
        if ($out -match "h264_nvenc")        { $result.nvenc = $true }
        if ($out -match "h264_videotoolbox") { $result.videotoolbox = $true }
        if ($out -match "h264_qsv")          { $result.qsv = $true }
        if ($out -match "h264_amf")          { $result.amf = $true }
    } catch {}
    return $result
}

function Get-FfmpegVersion {
    param([string]$FfmpegBin)
    if (-not $FfmpegBin) { return $null }
    try {
        $out = cmd /c "`"$FfmpegBin`" -version 2>&1" | Select-Object -First 1
        if ($out -match "ffmpeg version (\S+)") {
            return $Matches[1]
        }
    } catch {}
    return $null
}

function Get-PythonVersion {
    param([string]$PythonBin)
    if (-not $PythonBin) { return $null }
    try {
        $out = & $PythonBin --version 2>&1
        if ($out -match "Python (\S+)") {
            return $Matches[1]
        }
    } catch {}
    return $null
}

Write-Host "Detetando ambiente em $WorkspaceDir..."

$cacheDir = Join-Path $WorkspaceDir "cache"
if (-not (Test-Path $cacheDir)) {
    New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
}

$ffmpegBin = Get-AbsolutePath "ffmpeg"
$ffprobeBin = Get-AbsolutePath "ffprobe"
$pythonBin = Get-AbsolutePath "python"
if (-not $pythonBin) {
    $pythonBin = Get-AbsolutePath "python3"
}

$whisperInstalled = Test-WhisperInstalled -PythonBin $pythonBin
$libassAvailable = Test-LibassSupport -FfmpegBin $ffmpegBin
$ffmpegVersion = Get-FfmpegVersion -FfmpegBin $ffmpegBin
$pythonVersion = Get-PythonVersion -PythonBin $pythonBin
$hwEncoders = Get-HwEncoders -FfmpegBin $ffmpegBin

$envReport = [ordered]@{
    timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
    os = "windows"
    os_version = [Environment]::OSVersion.VersionString
    ffmpeg_bin = $ffmpegBin
    ffmpeg_version = $ffmpegVersion
    ffprobe_bin = $ffprobeBin
    libass_available = $libassAvailable
    hw_encoders = $hwEncoders
    python_bin = $pythonBin
    python_version = $pythonVersion
    whisper_installed = $whisperInstalled
    elevenlabs_key_present = (-not [string]::IsNullOrEmpty($env:ELEVENLABS_API_KEY))
    openai_key_present = (-not [string]::IsNullOrEmpty($env:OPENAI_API_KEY))
    workspace_dir = $WorkspaceDir
}

$json = $envReport | ConvertTo-Json -Depth 5
$reportPath = Join-Path $cacheDir "env-report.json"

[IO.File]::WriteAllText($reportPath, $json, [Text.UTF8Encoding]::new($false))

function Show-OrMissing([string]$v) { if ([string]::IsNullOrEmpty($v)) { return "(nao encontrado)" } else { return $v } }

Write-Host "OK Ambiente detetado:" -ForegroundColor Green
Write-Host "  ffmpeg:  $(Show-OrMissing $ffmpegBin)"
Write-Host "  ffprobe: $(Show-OrMissing $ffprobeBin)"
Write-Host "  python:  $(Show-OrMissing $pythonBin) $pythonVersion"
Write-Host "  whisper: $(if ($whisperInstalled) { 'instalado' } else { 'NAO instalado (pip install openai-whisper)' })"
Write-Host "  libass:  $(if ($libassAvailable) { 'disponivel' } else { 'NAO disponivel (fallback necessario)' })"
$activeHw = @()
if ($hwEncoders.nvenc)        { $activeHw += "NVENC" }
if ($hwEncoders.videotoolbox) { $activeHw += "VideoToolbox" }
if ($hwEncoders.qsv)          { $activeHw += "Intel QSV" }
if ($hwEncoders.amf)          { $activeHw += "AMD AMF" }
Write-Host "  hwaccel: $(if ($activeHw.Count -gt 0) { $activeHw -join ', ' } else { 'nenhum (so software)' })"
Write-Host ""
Write-Host "Report: $reportPath"

if (-not $ffmpegBin -or -not $ffprobeBin) {
    Write-Host ""
    Write-Host "AVISO: ffmpeg ou ffprobe nao encontrado. Instala antes de continuar:" -ForegroundColor Yellow
    Write-Host "  winget install Gyan.FFmpeg"
    exit 1
}

if (-not $pythonBin) {
    Write-Host ""
    Write-Host "AVISO: Python nao encontrado. Instala:" -ForegroundColor Yellow
    Write-Host "  winget install Python.Python.3.12"
    exit 1
}

exit 0
