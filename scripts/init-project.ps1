#Requires -Version 5.1
<#
.SYNOPSIS
    Cria pasta de projeto AO LADO do video source (ou em -OutputDir explicito).
    Copia source, deteta media info via ffprobe, escreve project.json.

.PARAMETER InputVideo
    Caminho ABSOLUTO para o video raw. Obrigatorio.

.PARAMETER OutputDir
    Pasta-pai onde criar a pasta do projeto. Default: <dir-do-source>\videokit-projects\
    Se passado, a pasta do projeto e criada como <OutputDir>\YYYY-MM-DD_slug\.

.PARAMETER Slug
    Slug ASCII para o nome da pasta. Default: derivado do nome do ficheiro.

.PARAMETER Mode
    'full' ou 'cut-only'. Default: 'full'.

.PARAMETER SubtitleStyle
    'completas', 'karaoke', 'highlights', 'sem'. Default: 'completas'.

.EXAMPLE
    .\init-project.ps1 -InputVideo C:\Downloads\meu.mp4
    # cria C:\Downloads\videokit-projects\2026-06-03_meu\

.EXAMPLE
    .\init-project.ps1 -InputVideo C:\raw\pitch.mov -OutputDir D:\edited
    # cria D:\edited\2026-06-03_pitch\
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$InputVideo,

    [string]$OutputDir = "",

    [string]$Slug = "",

    [ValidateSet("full","cut-only")]
    [string]$Mode = "full",

    [ValidateSet("completas","karaoke","highlights","sem")]
    [string]$SubtitleStyle = "completas"
)

$ErrorActionPreference = "Stop"
$SkillDir = Split-Path -Parent $PSScriptRoot

function ConvertTo-Slug {
    param([string]$Text)
    $t = $Text.ToLowerInvariant()
    $t = $t -replace "[áàâãä]", "a"
    $t = $t -replace "[éèêë]", "e"
    $t = $t -replace "[íìîï]", "i"
    $t = $t -replace "[óòôõö]", "o"
    $t = $t -replace "[úùûü]", "u"
    $t = $t -replace "[ç]", "c"
    $t = $t -replace "[ñ]", "n"
    $t = $t -replace "[^a-z0-9]+", "-"
    $t = $t.Trim("-")
    if ($t.Length -gt 50) { $t = $t.Substring(0, 50).TrimEnd("-") }
    if ([string]::IsNullOrEmpty($t)) { $t = "video" }
    return $t
}

function Get-MediaInfo {
    param([string]$FfprobeBin, [string]$Path)

    $cmd = "`"$FfprobeBin`" -v error -select_streams v:0 -show_entries stream=width,height,r_frame_rate,codec_name,duration:format=duration:stream_side_data=rotation -of json `"$Path`" 2>&1"
    $jsonOut = cmd /c $cmd | Out-String

    try {
        $data = $jsonOut | ConvertFrom-Json
    } catch {
        throw "ffprobe nao devolveu JSON valido para $Path. Output: $jsonOut"
    }

    $stream = $data.streams[0]
    $w = [int]$stream.width
    $h = [int]$stream.height
    $codec = $stream.codec_name

    $fpsParts = $stream.r_frame_rate -split "/"
    $fps = [double]::Parse($fpsParts[0], [System.Globalization.CultureInfo]::InvariantCulture) / [double]::Parse($fpsParts[1], [System.Globalization.CultureInfo]::InvariantCulture)
    $fps = [math]::Round($fps, 3)

    $durStr = $data.format.duration
    if (-not $durStr) { $durStr = $stream.duration }
    $duration = [double]::Parse($durStr, [System.Globalization.CultureInfo]::InvariantCulture)
    $duration = [math]::Round($duration, 3)

    $rotation = 0
    if ($stream.side_data_list) {
        foreach ($sd in $stream.side_data_list) {
            if ($sd.rotation) {
                $rotation = [int]$sd.rotation
                break
            }
        }
    }

    $displayW = if ($rotation -in 90, -90, 270, -270) { $h } else { $w }
    $displayH = if ($rotation -in 90, -90, 270, -270) { $w } else { $h }

    $aspect = [math]::Round($displayW / $displayH, 3)
    $aspectName = "custom"
    if ([math]::Abs($aspect - 1.778) -lt 0.05) { $aspectName = "16:9" }
    elseif ([math]::Abs($aspect - 0.5625) -lt 0.05) { $aspectName = "9:16" }
    elseif ([math]::Abs($aspect - 1.0) -lt 0.05) { $aspectName = "1:1" }
    elseif ([math]::Abs($aspect - 1.333) -lt 0.05) { $aspectName = "4:3" }

    return [ordered]@{
        width = $w
        height = $h
        display_width = $displayW
        display_height = $displayH
        rotation = $rotation
        fps = $fps
        duration_s = $duration
        codec = $codec
        aspect_ratio = $aspectName
    }
}

# --- Validacao inicial ---

if (-not (Test-Path $InputVideo)) {
    Write-Error "Video nao encontrado: $InputVideo"
    exit 1
}
$InputVideo = (Resolve-Path $InputVideo).Path

$envReportPath = Join-Path $SkillDir "cache\env-report.json"
if (-not (Test-Path $envReportPath)) {
    Write-Host "env-report.json nao existe. A correr detect-env..."
    & (Join-Path $PSScriptRoot "detect-env.ps1")
    if (-not (Test-Path $envReportPath)) {
        Write-Error "detect-env falhou. Abortar."
        exit 1
    }
}

$envReport = Get-Content $envReportPath -Raw | ConvertFrom-Json
$ffprobeBin = $envReport.ffprobe_bin
if (-not $ffprobeBin) {
    Write-Error "ffprobe_bin nao definido em env-report.json"
    exit 1
}

# --- Decidir OutputDir ---

if ([string]::IsNullOrEmpty($OutputDir)) {
    $sourceParent = Split-Path -Parent $InputVideo
    $OutputDir = Join-Path $sourceParent "videokit-projects"
}
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}
$OutputDir = (Resolve-Path $OutputDir).Path

# --- Slug e pasta ---

if ([string]::IsNullOrEmpty($Slug)) {
    $stem = [System.IO.Path]::GetFileNameWithoutExtension($InputVideo)
    $Slug = ConvertTo-Slug $stem
}

$today = Get-Date -Format "yyyy-MM-dd"
$projectName = "${today}_${Slug}"
$projectDir = Join-Path $OutputDir $projectName

if (Test-Path $projectDir) {
    Write-Warning "Pasta ja existe: $projectDir"
    $suffix = 2
    while (Test-Path "${projectDir}-${suffix}") { $suffix++ }
    $projectDir = "${projectDir}-${suffix}"
    Write-Host "Usando: $projectDir"
}

# --- Estrutura ---

$subfolders = @(
    "source", "transcripts", "edit", "edit\segments",
    "overlays", "renders", "renders\draft", "renders\final",
    "verify", "cache", "logs"
)

foreach ($f in $subfolders) {
    New-Item -ItemType Directory -Path (Join-Path $projectDir $f) -Force | Out-Null
}

# --- Copia source ---

$sourceFileName = [System.IO.Path]::GetFileName($InputVideo)
$sourceDest = Join-Path $projectDir "source\$sourceFileName"
Copy-Item -Path $InputVideo -Destination $sourceDest

Write-Host "Source copiado para $sourceDest"

# --- Media info via ffprobe ---

Write-Host "Analisando media com ffprobe..."
$media = Get-MediaInfo -FfprobeBin $ffprobeBin -Path $sourceDest

Write-Host "  Resolucao: $($media.width)x$($media.height) (display: $($media.display_width)x$($media.display_height))"
Write-Host "  Rotation:  $($media.rotation) deg"
Write-Host "  FPS:       $($media.fps)"
Write-Host "  Duracao:   $($media.duration_s)s"
Write-Host "  Aspect:    $($media.aspect_ratio)"

# --- project.json ---

$projectJson = [ordered]@{
    name = $projectName
    slug = $Slug
    created_at = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
    skill_dir = $SkillDir
    source = @{
        original_path = $InputVideo
        local_copy = "source\$sourceFileName"
    }
    media = $media
    settings = [ordered]@{
        mode = $Mode
        subtitle_style = $SubtitleStyle
        language = "pt"
        transcript_provider = "local"
    }
    transcript = $null
    edit = $null
    beats = $null
    renders = [ordered]@{
        draft = $null
        final = $null
    }
    checklist = [ordered]@{
        duration_verified = $false
        audio_present = $false
        silences_reviewed = $false
        codec_verified = $false
        resolution_correct = $false
        subtitles_synced_or_skipped = $false
        files_in_project_folder = $true
        verify_frames_extracted = $false
    }
    events = @()
    notes_path = "notes.md"
}

$projectJsonPath = Join-Path $projectDir "project.json"
$json = $projectJson | ConvertTo-Json -Depth 10
[IO.File]::WriteAllText($projectJsonPath, $json, [Text.UTF8Encoding]::new($false))

$notesPath = Join-Path $projectDir "notes.md"
$notesContent = "# Notas de $projectName`n`nCriado em $(Get-Date -Format 'yyyy-MM-dd HH:mm')`nSource: $InputVideo`n`n## Decisoes`n`n## Excecoes ao pipeline`n"
[IO.File]::WriteAllText($notesPath, $notesContent, [Text.UTF8Encoding]::new($false))

Write-Host ""
Write-Host "OK Projeto criado: $projectDir" -ForegroundColor Green
Write-Host "  project.json: $projectJsonPath"
Write-Host "  modo: $Mode"
Write-Host "  legendas: $SubtitleStyle"

# Output JSON-like to stdout para o agente parsear o path
@{ project_dir = $projectDir; project_name = $projectName } | ConvertTo-Json -Compress
