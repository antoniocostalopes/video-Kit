#Requires -Version 5.1
<#
.SYNOPSIS
    Aplica efeitos visuais FFmpeg: transicoes xfade entre clips, LUTs, vignette, film grain.

.DESCRIPTION
    Tres modos via -Mode:
      Transition  - junta dois clips com efeito xfade
      Lut         - aplica LUT .cube ao input
      Grade       - aplica color grading customizado (eq, vignette, grain)

.PARAMETER Mode
    Transition | Lut | Grade

.PARAMETER InputFile
    Video de input (Lut, Grade).

.PARAMETER InputA / InputB
    Dois videos a juntar (Transition).

.PARAMETER OutputFile
    Path de output mp4.

.PARAMETER Transition
    Tipo de transicao xfade. Default: 'fade'. Lista: fade, fadeblack, fadewhite, distance,
    wipeleft, wiperight, wipeup, wipedown, slideleft, slideright, slideup, slidedown,
    smoothleft, smoothright, smoothup, smoothdown, circlecrop, rectcrop, circleopen, circleclose,
    horzopen, horzclose, vertopen, vertclose, diagbl, diagbr, diagtl, diagtr, hlslice, hrslice,
    vuslice, vdslice, dissolve, pixelize, radial, hblur, wipetl, wipetr, wipebl, wipebr, squeezeh, squeezev.

.PARAMETER Duration
    Duracao da transicao em segundos. Default: 0.5.

.PARAMETER Offset
    Em transicao, em que segundo de InputA a transicao comeca. Default: duration(A) - Duration.

.PARAMETER LutFile
    Caminho para .cube file (Lut mode).

.PARAMETER LutIntensity
    Mistura entre original e LUT. 0.0 = sem efeito, 1.0 = LUT puro. Default 1.0.

.PARAMETER VignetteStrength
    0.0 (nenhum) a 1.0 (forte). Default 0 (off). 0.4 e tipico cinematografico.

.PARAMETER FilmGrain
    Intensidade de grain. 0 (off) a 20. Default 0.

.PARAMETER Brightness
    -1.0 a 1.0. Default 0.

.PARAMETER Contrast
    0.0 a 2.0. Default 1.0 (sem mudanca).

.PARAMETER Saturation
    0.0 a 3.0. Default 1.0.

.PARAMETER WorkspaceDir
    Default: pasta da skill.
#>

param(
    [Parameter(Mandatory=$true)][ValidateSet("Transition","Lut","Grade")][string]$Mode,
    [string]$InputFile = "",
    [string]$InputA = "",
    [string]$InputB = "",
    [Parameter(Mandatory=$true)][string]$OutputFile,
    [string]$Transition = "fade",
    [double]$Duration = 0.5,
    [Nullable[double]]$Offset = $null,
    [string]$LutFile = "",
    [double]$LutIntensity = 1.0,
    [double]$VignetteStrength = 0.0,
    [int]$FilmGrain = 0,
    [double]$Brightness = 0.0,
    [double]$Contrast = 1.0,
    [double]$Saturation = 1.0,
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
$ffprobeBin = $envReport.ffprobe_bin

function Get-Duration {
    param([string]$Path)
    $cmd = "`"$ffprobeBin`" -v error -show_entries format=duration -of default=nw=1:nk=1 `"$Path`" 2>&1"
    $s = (cmd /c $cmd).Trim()
    return [double]::Parse($s, [System.Globalization.CultureInfo]::InvariantCulture)
}

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

# ============================================================
# Mode: Transition
# ============================================================

if ($Mode -eq "Transition") {
    if (-not (Test-Path $InputA)) { Write-Error "InputA nao existe: $InputA"; exit 1 }
    if (-not (Test-Path $InputB)) { Write-Error "InputB nao existe: $InputB"; exit 1 }
    $InputA = (Resolve-Path $InputA).Path
    $InputB = (Resolve-Path $InputB).Path

    $durA = Get-Duration $InputA
    if (-not $Offset) {
        $Offset = $durA - $Duration
    }
    if ($Offset -lt 0) { $Offset = 0 }

    Write-Host "Transition: $Transition ($Duration s, offset $Offset)"

    # Filter para xfade video + acrossfade audio
    $filterComplex = "[0:v][1:v]xfade=transition=${Transition}:duration=${Duration}:offset=${Offset}[v];" +
                     "[0:a][1:a]acrossfade=d=${Duration}[a]"

    $ffargs = @(
        "-y",
        "-i", $InputA,
        "-i", $InputB,
        "-filter_complex", $filterComplex,
        "-map", "[v]",
        "-map", "[a]",
        "-c:v", "libx264",
        "-preset", "medium",
        "-crf", "20",
        "-pix_fmt", "yuv420p",
        "-c:a", "aac",
        "-b:a", "192k",
        $OutputFile
    )
    Invoke-Ffmpeg -Arguments $ffargs -Description "xfade $Transition"
    Write-Host "OK $OutputFile" -ForegroundColor Green
    exit 0
}

# ============================================================
# Mode: Lut
# ============================================================

if ($Mode -eq "Lut") {
    if (-not (Test-Path $InputFile)) { Write-Error "Input nao existe: $InputFile"; exit 1 }
    if (-not (Test-Path $LutFile)) { Write-Error "LUT nao existe: $LutFile"; exit 1 }
    $InputFile = (Resolve-Path $InputFile).Path
    $LutFile = (Resolve-Path $LutFile).Path

    # Filtro lut3d nao aceita paths com ':' (Windows drive letter) mesmo escapado.
    # Workaround: copiar o LUT para a pasta do output e referenciar so pelo nome.
    $outDir = Split-Path -Parent ((Resolve-Path -LiteralPath (Split-Path -Parent $OutputFile)).Path)
    if ([string]::IsNullOrEmpty($outDir)) { $outDir = (Get-Location).Path }
    $tmpLutName = "__skv_lut_" + [System.Guid]::NewGuid().ToString("N").Substring(0,8) + ".cube"
    $outFileDir = Split-Path -Parent $OutputFile
    if (-not (Test-Path $outFileDir)) { New-Item -ItemType Directory -Path $outFileDir -Force | Out-Null }
    $tmpLutPath = Join-Path $outFileDir $tmpLutName
    Copy-Item -Path $LutFile -Destination $tmpLutPath -Force

    if ($LutIntensity -ge 0.99) {
        $videoFilter = "lut3d=$tmpLutName"
    } else {
        $videoFilter = "split[a][b];[b]lut3d=$tmpLutName[graded];[a][graded]blend=all_mode=normal:all_opacity=$LutIntensity"
    }

    Write-Host "LUT: $(Split-Path -Leaf $LutFile) (intensity $LutIntensity)"

    $ffargs = @(
        "-y",
        "-i", $InputFile,
        "-vf", $videoFilter,
        "-c:v", "libx264",
        "-preset", "medium",
        "-crf", "20",
        "-pix_fmt", "yuv420p",
        "-c:a", "copy",
        $OutputFile
    )
    try {
        Push-Location $outFileDir
        Invoke-Ffmpeg -Arguments $ffargs -Description "Apply LUT"
    } finally {
        Pop-Location
        Remove-Item $tmpLutPath -ErrorAction SilentlyContinue
    }
    Write-Host "OK $OutputFile" -ForegroundColor Green
    exit 0
}

# ============================================================
# Mode: Grade (color + vignette + grain)
# ============================================================

if ($Mode -eq "Grade") {
    if (-not (Test-Path $InputFile)) { Write-Error "Input nao existe: $InputFile"; exit 1 }
    $InputFile = (Resolve-Path $InputFile).Path

    $filters = @()

    if ($Brightness -ne 0.0 -or $Contrast -ne 1.0 -or $Saturation -ne 1.0) {
        $filters += "eq=brightness=${Brightness}:contrast=${Contrast}:saturation=${Saturation}"
    }

    if ($VignetteStrength -gt 0) {
        # vignette com forca controlada via angle (PI/5 = forte, PI/3 = subtil)
        # Usar formula: angle = PI/3 - strength * (PI/3 - PI/6) -> 0..1 maps to subtil..forte
        $angle = "PI/3-${VignetteStrength}*(PI/6)"
        $filters += "vignette=angle=$angle"
    }

    if ($FilmGrain -gt 0) {
        # noise filter; allf=t para temporal (cintilação), c0s = strength
        $filters += "noise=alls=${FilmGrain}:allf=t"
    }

    if ($filters.Count -eq 0) {
        Write-Warning "Nenhum efeito de grade selecionado. Output sera copia do input."
        Copy-Item -Path $InputFile -Destination $OutputFile -Force
        exit 0
    }

    Write-Host "Grade: $($filters -join ', ')"

    $ffargs = @(
        "-y",
        "-i", $InputFile,
        "-vf", ($filters -join ","),
        "-c:v", "libx264",
        "-preset", "medium",
        "-crf", "20",
        "-pix_fmt", "yuv420p",
        "-c:a", "copy",
        $OutputFile
    )
    Invoke-Ffmpeg -Arguments $ffargs -Description "Color grade"
    Write-Host "OK $OutputFile" -ForegroundColor Green
}
