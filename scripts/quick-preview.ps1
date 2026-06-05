#Requires -Version 5.1
<#
.SYNOPSIS
    Render rapido de um segmento curto para confirmar efeito/legenda/grade antes do final.

.DESCRIPTION
    Em vez de re-render do video inteiro (15+ min) para ver se um zoom ou cor ficou bem,
    extrai uma janela de 5-15s e aplica so o efeito pedido em ultrafast. ~30s-2min.

    Procura input nesta ordem:
      1. renders/edited_subs.mp4 (com legendas)
      2. renders/edited.mp4
      3. source/<original>

.PARAMETER ProjectDir
    Path absoluto do projeto videokit.

.PARAMETER Start
    Inicio em segundos (default 0).

.PARAMETER Duration
    Duracao da preview em segundos (default 5).

.PARAMETER Label
    Nome curto que vai aparecer no nome do ficheiro de output (default "preview").

.PARAMETER WithSubs
    Queima legendas (usa edit/subtitles.ass).

.PARAMETER WithLut
    Path para .cube. Aplica LUT.

.PARAMETER LutIntensity
    Intensidade do LUT (0.0-1.0). Default 1.0.

.PARAMETER WithZoom
    Aplica zoompan: --from-zoom 1.0 --to-zoom 1.25 ao longo da preview.

.PARAMETER FromZoom
    Zoom inicial (default 1.0).

.PARAMETER ToZoom
    Zoom final (default 1.25).

.PARAMETER Scale
    Resolucao da preview (default 720 para ser rapido; 1080 para ver detalhe; 0 = original).

.EXAMPLE
    .\quick-preview.ps1 -ProjectDir C:\v\projects\2026-06-05_x -Start 45 -Duration 6 -WithZoom -Label zoom_45s

.EXAMPLE
    .\quick-preview.ps1 -ProjectDir X -Start 12 -Duration 8 -WithLut ..\..\assets\luts\cinematic.cube -LutIntensity 0.7
#>

param(
    [Parameter(Mandatory=$true)][string]$ProjectDir,
    [double]$Start = 0,
    [double]$Duration = 5,
    [string]$Label = "preview",
    [switch]$WithSubs,
    [string]$WithLut = "",
    [double]$LutIntensity = 1.0,
    [switch]$WithZoom,
    [double]$FromZoom = 1.0,
    [double]$ToZoom = 1.25,
    [int]$Scale = 720
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $ProjectDir)) { Write-Error "ProjectDir nao existe: $ProjectDir"; exit 1 }
$ProjectDir = (Resolve-Path $ProjectDir).Path

$skillDir = Split-Path -Parent $PSScriptRoot
$envReport = Get-Content (Join-Path $skillDir "cache\env-report.json") -Raw | ConvertFrom-Json
$ffmpegBin = $envReport.ffmpeg_bin

$projectJson = Get-Content (Join-Path $ProjectDir "project.json") -Raw | ConvertFrom-Json
$displayW = $projectJson.media.display_width
$displayH = $projectJson.media.display_height
$fps = $projectJson.media.fps

# --- Escolher input ---
$candidates = @(
    (Join-Path $ProjectDir "renders\edited_subs.mp4"),
    (Join-Path $ProjectDir "renders\edited.mp4"),
    (Join-Path $ProjectDir $projectJson.source.local_copy)
)
$input = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $input) { Write-Error "Nenhum input candidato encontrado em $ProjectDir"; exit 1 }
Write-Host "Input: $input" -ForegroundColor Cyan

# --- Output ---
$previewDir = Join-Path $ProjectDir "cache\preview"
New-Item -ItemType Directory -Path $previewDir -Force | Out-Null
$timestamp = Get-Date -Format "HHmmss"
$safeLabel = $Label -replace "[^a-zA-Z0-9_-]", "_"
$output = Join-Path $previewDir "${timestamp}_${safeLabel}.mp4"

# --- Filter chain ---
$filters = @()

if ($WithZoom) {
    $rate = [math]::Round(($ToZoom - $FromZoom) / [math]::Max($Duration, 0.5), 6)
    $expr = "if(between(in_time,0,$Duration),min(${FromZoom}+${rate}*in_time,${ToZoom}),1)"
    $filters += "zoompan=z='$expr':d=1:s=${displayW}x${displayH}:fps=$fps"
}

if ($WithLut -and (Test-Path $WithLut)) {
    # Copia LUT para temp dir e usa nome relativo (FFmpeg lut3d nao gosta de paths Windows com ':')
    $lutTemp = Join-Path $previewDir ("__lut_" + [System.IO.Path]::GetFileName($WithLut))
    Copy-Item $WithLut $lutTemp -Force
    $lutName = [System.IO.Path]::GetFileName($lutTemp)
    if ($LutIntensity -ge 0.99) {
        $filters += "lut3d=$lutName"
    } else {
        $filters += "split[a][b];[b]lut3d=$lutName[g];[a][g]blend=all_mode=normal:all_opacity=$LutIntensity"
    }
}

if ($WithSubs) {
    $assPath = Join-Path $ProjectDir "edit\subtitles.ass"
    if (-not (Test-Path $assPath)) { Write-Error "WithSubs pedido mas edit\subtitles.ass nao existe"; exit 1 }
    # subtitles= so funciona com / e escapar ':' em paths Windows
    $assForFilter = ($assPath -replace "\\", "/" -replace ":", "\:")
    # Tem de vir DEPOIS de scale para alinhamento correto se for legenda absoluta — mantemos antes para simplicidade.
    $filters += "subtitles='$assForFilter'"
}

if ($Scale -gt 0) {
    # Scale preservando aspect (height baseado no scale, largura derivada)
    $filters += "scale=-2:$Scale"
}

# --- ffmpeg ---
$workDir = if ($WithLut) { $previewDir } else { (Get-Location).Path }

$ffargs = @(
    "-y",
    "-ss", $Start.ToString("0.000", [System.Globalization.CultureInfo]::InvariantCulture),
    "-i", $input,
    "-t", $Duration.ToString("0.000", [System.Globalization.CultureInfo]::InvariantCulture)
)
if ($filters.Count -gt 0) { $ffargs += @("-vf", ($filters -join ",")) }
$ffargs += @(
    "-c:v", "libx264", "-preset", "ultrafast", "-crf", "26",
    "-pix_fmt", "yuv420p",
    "-c:a", "aac", "-b:a", "128k",
    $output
)

Write-Host "Preview: ${Duration}s a partir de ${Start}s" -ForegroundColor Yellow
if ($filters.Count -gt 0) { Write-Host "  Filtros: $($filters -join ' | ')" }

$prevLoc = Get-Location
try {
    Set-Location $workDir
    $errFile = [System.IO.Path]::GetTempFileName()
    $proc = Start-Process -FilePath $ffmpegBin -ArgumentList $ffargs `
            -NoNewWindow -Wait -PassThru `
            -RedirectStandardError $errFile -RedirectStandardOutput ([System.IO.Path]::GetTempFileName())
    if ($proc.ExitCode -ne 0) {
        Write-Host (Get-Content $errFile -Raw) -ForegroundColor Red
        throw "ffmpeg falhou (exit $($proc.ExitCode))"
    }
    Remove-Item $errFile -ErrorAction SilentlyContinue
} finally {
    Set-Location $prevLoc
    # Limpa LUT temporario
    if ($WithLut) {
        $lutTemp = Join-Path $previewDir ("__lut_" + [System.IO.Path]::GetFileName($WithLut))
        Remove-Item $lutTemp -ErrorAction SilentlyContinue
    }
}

$sizeMb = [math]::Round((Get-Item $output).Length / 1MB, 2)
Write-Host "OK preview: $output ($sizeMb MB)" -ForegroundColor Green
Write-Host "Abre em qualquer player para confirmar antes de re-render."
