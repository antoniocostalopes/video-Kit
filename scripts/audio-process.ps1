#Requires -Version 5.1
<#
.SYNOPSIS
    Processamento de audio profissional via FFmpeg: denoise, normalize, ducking, compressor.

.DESCRIPTION
    Aplica uma cadeia de processamento ao audio do video. Flags ativam etapas.
    Combinacao tipica para voz: -Denoise -Normalize -Compress

.PARAMETER InputFile
    Video ou audio de input.

.PARAMETER OutputFile
    Path de output (mp4 ou wav).

.PARAMETER Denoise
    Aplica RNNoise para remover ruido de fundo (ar condicionado, hiss).

.PARAMETER Normalize
    Aplica EBU R128 loudnorm para nivel consistente.

.PARAMETER TargetLufs
    LUFS alvo. Default -14 (YouTube). Reels: -16. TikTok: -13. Broadcast: -23.

.PARAMETER Compress
    Compressor suave para voz mais presente.

.PARAMETER Deess
    Atenua sibilantes (5-9kHz).

.PARAMETER Music
    Path opcional para musica de fundo. Mistura com ducking automatico.

.PARAMETER MusicVolume
    Volume base da musica (0.0-1.0). Default 0.25 (~-12dB).

.PARAMETER Preset
    Nome de plataforma (youtube, youtube-shorts, reels, tiktok, podcast-video, linkedin, twitter-x).
    Quando passado, sobrescreve TargetLufs com o valor do preset em assets/platform-presets.json.

.PARAMETER WorkspaceDir
    Default: pasta da skill.

.EXAMPLE
    .\audio-process.ps1 -InputFile C:\v\raw.mp4 -OutputFile C:\v\clean.mp4 -Denoise -Normalize -Compress

.EXAMPLE
    .\audio-process.ps1 -InputFile C:\v\raw.mp4 -OutputFile C:\v\reels.mp4 -Denoise -Normalize -Preset reels
#>

param(
    [Parameter(Mandatory=$true)][string]$InputFile,
    [Parameter(Mandatory=$true)][string]$OutputFile,
    [switch]$Denoise,
    [switch]$Normalize,
    [double]$TargetLufs = -14.0,
    [switch]$Compress,
    [switch]$Deess,
    [string]$Music = "",
    [double]$MusicVolume = 0.25,
    [string]$Preset = "",
    [string]$WorkspaceDir = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"

# --- Env report ---
$envReportPath = Join-Path $WorkspaceDir "cache\env-report.json"
if (-not (Test-Path $envReportPath)) {
    & (Join-Path $PSScriptRoot "detect-env.ps1")
}
$envReport = Get-Content $envReportPath -Raw | ConvertFrom-Json
$ffmpegBin = $envReport.ffmpeg_bin

# --- Preset de plataforma (sobrescreve TargetLufs) ---
if (-not [string]::IsNullOrEmpty($Preset)) {
    $presetsPath = Join-Path $WorkspaceDir "assets\platform-presets.json"
    if (Test-Path $presetsPath) {
        $presets = Get-Content $presetsPath -Raw | ConvertFrom-Json
        if ($presets.PSObject.Properties.Name -contains $Preset) {
            $TargetLufs = [double]$presets.$Preset.audio.target_lufs
            Write-Host "Preset '$Preset' aplicado: target_lufs=$TargetLufs" -ForegroundColor Cyan
        } else {
            $available = ($presets.PSObject.Properties.Name -join ", ")
            Write-Warning "Preset '$Preset' nao existe. Disponiveis: $available. A usar TargetLufs=$TargetLufs."
        }
    } else {
        Write-Warning "$presetsPath em falta. A usar TargetLufs=$TargetLufs."
    }
}

# --- Validacao ---
if (-not (Test-Path $InputFile)) { Write-Error "Input nao existe: $InputFile"; exit 1 }
$InputFile = (Resolve-Path $InputFile).Path
if ($Music -and -not (Test-Path $Music)) { Write-Error "Music nao existe: $Music"; exit 1 }
if ($Music) { $Music = (Resolve-Path $Music).Path }

# --- Modelo RNNoise se Denoise ---
$modelForFilter = ""
if ($Denoise) {
    $modelPath = Join-Path $WorkspaceDir "assets\audio-models\cb.rnnn"
    if (-not (Test-Path $modelPath)) {
        Write-Host "Modelo RNNoise nao encontrado. A descarregar..."
        & (Join-Path $PSScriptRoot "download-assets.ps1") -What rnnoise
    }
    if (-not (Test-Path $modelPath)) {
        Write-Error "Modelo RNNoise nao disponivel."
        exit 1
    }
    $modelForFilter = $modelPath -replace "\\", "/" -replace ":", "\:"
}

# --- Filtros de audio (encadeados) ---
$audioFilters = @()
if ($Denoise)  { $audioFilters += "arnndn=m=$modelForFilter" }
if ($Deess)    { $audioFilters += "equalizer=f=7000:t=q:w=1.5:g=-3" }
if ($Compress) { $audioFilters += "acompressor=threshold=-18dB:ratio=2.5:attack=8:release=180:makeup=2" }
if ($Normalize){ $audioFilters += "loudnorm=I=$TargetLufs:TP=-1.5:LRA=11" }

# --- Helper para chamar ffmpeg sem o bug de stderr-as-error do PS 5.1 ---
function Invoke-Ffmpeg {
    param([string[]]$Arguments, [string]$Description)
    Write-Host "  > $Description"
    $errFile = [System.IO.Path]::GetTempFileName()
    $outFile = [System.IO.Path]::GetTempFileName()
    try {
        $proc = Start-Process -FilePath $ffmpegBin -ArgumentList $Arguments `
                -NoNewWindow -Wait -PassThru `
                -RedirectStandardError $errFile -RedirectStandardOutput $outFile
        if ($proc.ExitCode -ne 0) {
            Write-Host (Get-Content $errFile -Raw) -ForegroundColor Red
            throw "ffmpeg falhou: $Description (exit $($proc.ExitCode))"
        }
    } finally {
        Remove-Item $errFile, $outFile -ErrorAction SilentlyContinue
    }
}

# --- Caso 1: sem musica ---

if ([string]::IsNullOrEmpty($Music)) {
    Write-Host "Audio processing (sem musica)..."
    Write-Host "  Filtros: $(if ($audioFilters.Count) { $audioFilters -join ', ' } else { 'nenhum' })"

    $ffargs = @("-y","-i",$InputFile,"-c:v","copy")
    if ($audioFilters.Count -gt 0) {
        $ffargs += @("-af", ($audioFilters -join ","))
    }
    $ffargs += @("-c:a","aac","-b:a","192k",$OutputFile)

    Invoke-Ffmpeg -Arguments $ffargs -Description "Audio process"
    Write-Host "OK Output: $OutputFile ($([math]::Round((Get-Item $OutputFile).Length / 1MB, 1)) MB)" -ForegroundColor Green
    exit 0
}

# --- Caso 2: com musica + ducking ---

Write-Host "Audio processing com musica + ducking..."

$voiceFilters = if ($audioFilters.Count -gt 0) { ($audioFilters -join ",") + "," } else { "" }
$filterComplex = "[0:a]${voiceFilters}asplit=2[vmix][vsc];" +
                 "[1:a]volume=$MusicVolume[mbase];" +
                 "[mbase][vsc]sidechaincompress=threshold=0.05:ratio=20:attack=5:release=300:level_sc=0.8[mduck];" +
                 "[vmix][mduck]amix=inputs=2:duration=first:dropout_transition=3[outa]"

$ffargs = @(
    "-y",
    "-i", $InputFile,
    "-i", $Music,
    "-filter_complex", $filterComplex,
    "-map", "0:v?",
    "-map", "[outa]",
    "-c:v", "copy",
    "-c:a", "aac",
    "-b:a", "192k",
    "-shortest",
    $OutputFile
)

Invoke-Ffmpeg -Arguments $ffargs -Description "Audio process + duck"
Write-Host "OK Output: $OutputFile ($([math]::Round((Get-Item $OutputFile).Length / 1MB, 1)) MB)" -ForegroundColor Green
