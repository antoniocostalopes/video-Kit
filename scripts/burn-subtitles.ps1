#Requires -Version 5.1
<#
.SYNOPSIS
    Queima legendas ASS num video via FFmpeg.

.PARAMETER InputVideo
    Caminho para o video base.

.PARAMETER Subtitles
    Caminho para o ficheiro .ass.

.PARAMETER Output
    Caminho para o video output.

.PARAMETER Preset
    'draft' (rapido) ou 'final' (lento, melhor qualidade). Default: 'draft'.

.PARAMETER WorkspaceDir
    Pasta onde fica cache/env-report.json. Default: pasta da skill.
#>

param(
    [Parameter(Mandatory=$true)][string]$InputVideo,
    [Parameter(Mandatory=$true)][string]$Subtitles,
    [Parameter(Mandatory=$true)][string]$Output,
    [ValidateSet("draft","final")][string]$Preset = "draft",
    [string]$WorkspaceDir = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $InputVideo)) {
    Write-Error "Video nao encontrado: $InputVideo"
    exit 1
}
if (-not (Test-Path $Subtitles)) {
    Write-Error "Legendas nao encontradas: $Subtitles"
    exit 1
}

$envReportPath = Join-Path $WorkspaceDir "cache\env-report.json"
if (-not (Test-Path $envReportPath)) {
    Write-Error "cache\env-report.json nao existe. Corre detect-env.ps1 primeiro."
    exit 1
}

$env = Get-Content $envReportPath -Raw | ConvertFrom-Json
$ffmpegBin = $env.ffmpeg_bin

if (-not $env.libass_available) {
    Write-Warning "libass nao disponivel no ffmpeg. Vou tentar mesmo assim, mas pode falhar."
}

# Output dir
$outDir = Split-Path -Parent $Output
if ($outDir -and -not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

# Escape path para o filtro subtitles (precisa de duplo escape em Windows)
# ffmpeg filtros usam ':' como separator; em paths Windows C:\... vira C\:/...
$subsAbs = (Resolve-Path $Subtitles).Path
$subsForFilter = $subsAbs -replace "\\", "/" -replace ":", "\:" -replace "'", "\\'"

if ($Preset -eq "draft") {
    $videoArgs = @(
        "-c:v", "libx264",
        "-preset", "ultrafast",
        "-crf", "28",
        "-pix_fmt", "yuv420p"
    )
} else {
    $videoArgs = @(
        "-c:v", "libx264",
        "-preset", "slow",
        "-crf", "18",
        "-pix_fmt", "yuv420p",
        "-movflags", "+faststart"
    )
}

Write-Host "Queimando legendas ($Preset)..."
Write-Host "  Input:  $InputVideo"
Write-Host "  Subs:   $Subtitles"
Write-Host "  Output: $Output"

# subtitles filter aceita paths com ':' se escaparmos como '\:' E forward slashes.
# Mas o mais robusto e copiar o .ass para a pasta do output e referenciar pelo nome.
$tmpAssName = "__skv_subs_" + [System.Guid]::NewGuid().ToString("N").Substring(0,8) + ".ass"
$outFileDir = Split-Path -Parent $Output
$tmpAssPath = Join-Path $outFileDir $tmpAssName
Copy-Item -Path $subsAbs -Destination $tmpAssPath -Force

$ffmpegArgs = @(
    "-y",
    "-i", $InputVideo,
    "-vf", "subtitles=$tmpAssName"
) + $videoArgs + @(
    "-c:a", "copy",
    $Output
)

function Invoke-FfmpegBurn {
    param([string[]]$Arguments)
    $errFile = [System.IO.Path]::GetTempFileName()
    $outFile = [System.IO.Path]::GetTempFileName()
    try {
        $proc = Start-Process -FilePath $ffmpegBin -ArgumentList $Arguments `
                -NoNewWindow -Wait -PassThru `
                -RedirectStandardError $errFile -RedirectStandardOutput $outFile
        if ($proc.ExitCode -ne 0) {
            Write-Host (Get-Content $errFile -Raw) -ForegroundColor Red
            throw "ffmpeg falhou (exit $($proc.ExitCode))"
        }
    } finally {
        Remove-Item $errFile, $outFile -ErrorAction SilentlyContinue
    }
}

try {
    Push-Location $outFileDir
    Invoke-FfmpegBurn -Arguments $ffmpegArgs
} finally {
    Pop-Location
    Remove-Item $tmpAssPath -ErrorAction SilentlyContinue
}

if (-not (Test-Path $Output)) {
    Write-Error "ffmpeg correu sem erro mas output nao existe: $Output"
    exit 1
}

$size = (Get-Item $Output).Length
Write-Host "OK Output gerado: $Output ($([math]::Round($size / 1MB, 1)) MB)" -ForegroundColor Green
