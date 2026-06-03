#Requires -Version 5.1
<#
.SYNOPSIS
    Instala pacotes Python por feature pack.

.PARAMETER Feature
    Um de: core, diarization, translation, tts, audio-separation, bg-removal, all.

.EXAMPLE
    .\install-feature.ps1 diarization
    .\install-feature.ps1 all
#>

param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateSet("core","diarization","translation","tts","audio-separation","bg-removal","all")]
    [string]$Feature,

    [switch]$Upgrade
)

$ErrorActionPreference = "Stop"

# Mapping feature -> pacotes pip
$packs = @{
    "core"             = @("openai-whisper", "mediapipe", "opencv-python")
    "diarization"      = @("pyannote.audio", "torch", "torchaudio")
    "translation"      = @("argostranslate")
    "tts"              = @("piper-tts")
    "audio-separation" = @("demucs", "torch", "torchaudio")
    "bg-removal"       = @("rembg", "opencv-python", "pillow")
}

# Resolver lista de pacotes
if ($Feature -eq "all") {
    $allPackages = @()
    foreach ($k in $packs.Keys) { $allPackages += $packs[$k] }
    $packages = $allPackages | Sort-Object -Unique
    $totalSize = "~5GB"
} else {
    $packages = $packs[$Feature]
    $totalSize = switch ($Feature) {
        "core"             { "~300MB" }
        "diarization"      { "~500MB" }
        "translation"      { "~150MB + ~100MB por par de linguas" }
        "tts"              { "~50MB" }
        "audio-separation" { "~2GB (torch + demucs models)" }
        "bg-removal"       { "~250MB (modelo U2Net ~170MB sob demanda)" }
        default            { "varios MB" }
    }
}

# Check python
$pythonBin = Get-Command python -ErrorAction SilentlyContinue
if (-not $pythonBin) {
    Write-Error "Python nao encontrado no PATH. Corre bootstrap.ps1 primeiro."
    exit 1
}

Write-Host ""
Write-Host "=== install-feature: $Feature ===" -ForegroundColor Green
Write-Host "Pacotes: $($packages -join ', ')"
Write-Host "Download estimado: $totalSize"
Write-Host ""

$pipArgs = @("-m","pip","install","--user")
if ($Upgrade) { $pipArgs += "--upgrade" }
$pipArgs += $packages

& python @pipArgs 2>&1 | Out-Host

if ($LASTEXITCODE -ne 0) {
    Write-Error "pip falhou (exit $LASTEXITCODE)"
    exit $LASTEXITCODE
}

Write-Host ""
Write-Host "OK feature '$Feature' instalada" -ForegroundColor Green

# Notas especiais
if ($Feature -eq "diarization" -or $Feature -eq "all") {
    Write-Host ""
    Write-Host "NOTA diarization: precisa de HF_TOKEN da huggingface.co" -ForegroundColor Yellow
    Write-Host "  1. Cria token gratuito em https://huggingface.co/settings/tokens"
    Write-Host "  2. Aceita termos em https://huggingface.co/pyannote/speaker-diarization-3.1"
    Write-Host "  3. Define: `$env:HF_TOKEN = 'hf_xxx...'"
}
if ($Feature -eq "translation" -or $Feature -eq "all") {
    Write-Host ""
    Write-Host "NOTA translation: pacotes de linguas descarregados sob demanda na 1a corrida (~100MB cada par)." -ForegroundColor Cyan
}
if ($Feature -eq "tts" -or $Feature -eq "all") {
    Write-Host ""
    Write-Host "NOTA tts: voice models descarregados sob demanda (~50-100MB cada voz)." -ForegroundColor Cyan
}
