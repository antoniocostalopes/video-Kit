#Requires -Version 5.1
<#
.SYNOPSIS
    Orquestra o render de um projeto videokit.

.DESCRIPTION
    Aplica EDL (cortes) e opcionalmente overlays/efeitos. Suporta phases:
      cut       - aplica edl.json -> renders/edited.mp4
      subs      - queima legendas -> renders/edited_subs.mp4
      effects   - aplica zoompan / efeitos de beats_plan -> cache/base_with_effects.mp4
      overlays  - composita overlays HTML (PNG sequence ou MOV) -> renders/draft|final
      all       - tudo em sequencia
      verify    - extrai frames para verify/ e devolve sumario

.PARAMETER ProjectDir
    Caminho para projects/YYYY-MM-DD_slug/.

.PARAMETER Phase
    'cut' | 'subs' | 'effects' | 'overlays' | 'all' | 'verify'. Default: 'all'.

.PARAMETER Quality
    'draft' (rapido) ou 'final' (lento, melhor qualidade). Default: 'draft'.

.PARAMETER WorkspaceDir
    Pasta onde fica cache/env-report.json. Default: pasta da skill.
#>

param(
    [Parameter(Mandatory=$true)][string]$ProjectDir,
    [ValidateSet("cut","subs","effects","overlays","all","verify")][string]$Phase = "all",
    [ValidateSet("draft","final")][string]$Quality = "draft",
    [switch]$CleanCache,
    [string]$WorkspaceDir = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $ProjectDir)) {
    Write-Error "ProjectDir nao existe: $ProjectDir"
    exit 1
}
$ProjectDir = (Resolve-Path $ProjectDir).Path

$envReportPath = Join-Path $WorkspaceDir "cache\env-report.json"
if (-not (Test-Path $envReportPath)) {
    Write-Error "env-report.json nao existe em $envReportPath"
    exit 1
}
$env = Get-Content $envReportPath -Raw | ConvertFrom-Json
$ffmpegBin = $env.ffmpeg_bin
$ffprobeBin = $env.ffprobe_bin

$projectJsonPath = Join-Path $ProjectDir "project.json"
$project = Get-Content $projectJsonPath -Raw | ConvertFrom-Json

# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------

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

function Get-VideoCodecArgs([string]$q) {
    if ($q -eq "draft") {
        return @("-c:v","libx264","-preset","ultrafast","-crf","28","-pix_fmt","yuv420p")
    } else {
        return @("-c:v","libx264","-preset","slow","-crf","18","-pix_fmt","yuv420p","-movflags","+faststart")
    }
}

function Update-ProjectField([string]$Field, $Value) {
    $project | Add-Member -NotePropertyName $Field -NotePropertyValue $Value -Force
    $json = $project | ConvertTo-Json -Depth 10
    [IO.File]::WriteAllText($projectJsonPath, $json, [Text.UTF8Encoding]::new($false))
}

# ------------------------------------------------------------------
# Phase: cut
# ------------------------------------------------------------------

function Invoke-CutPhase {
    $edlPath = Join-Path $ProjectDir "edit\edl.json"
    if (-not (Test-Path $edlPath)) {
        throw "edit\edl.json nao existe. Corre auto-cut.py primeiro."
    }
    $edl = Get-Content $edlPath -Raw | ConvertFrom-Json
    $source = Join-Path $ProjectDir $edl.source

    $segDir = Join-Path $ProjectDir "edit\segments"
    New-Item -ItemType Directory -Path $segDir -Force | Out-Null

    $rotation = [int]$project.media.rotation
    $needsReencode = ($rotation -in 90, -90, 270, -270)

    Write-Host "Phase: cut ($($edl.segments_keep.Count) segmentos)..."

    $concatList = Join-Path $ProjectDir "edit\concat.txt"
    $listLines = @()

    foreach ($seg in $edl.segments_keep) {
        $segFile = Join-Path $segDir "$($seg.id).mp4"
        $duration = $seg.end - $seg.start

        $ffargs = @(
            "-y",
            "-ss", "$($seg.start)",
            "-to", "$($seg.end)",
            "-i", $source,
            "-map", "0:v:0",
            "-map", "0:a:0"
        )

        if ($needsReencode) {
            $ffargs += @("-c:v","libx264","-preset","fast","-crf","20")
            if ($rotation -in 90, -90) { $ffargs += @("-vf","transpose=1") }
            elseif ($rotation -in 270, -270) { $ffargs += @("-vf","transpose=2") }
        } else {
            $ffargs += @("-c:v","copy")
        }
        $ffargs += @("-c:a","aac","-b:a","192k","-avoid_negative_ts","make_zero", $segFile)

        Invoke-Ffmpeg -Arguments $ffargs -Description "Cortar $($seg.id) ($($seg.start)..$($seg.end))"
        $listLines += "file '$segFile'"
    }

    [IO.File]::WriteAllText($concatList, ($listLines -join "`n"), [Text.UTF8Encoding]::new($false))

    $editedOut = Join-Path $ProjectDir "renders\edited.mp4"
    $ffargs = @("-y","-f","concat","-safe","0","-i",$concatList,"-c","copy",$editedOut)
    Invoke-Ffmpeg -Arguments $ffargs -Description "Concatenar $($edl.segments_keep.Count) segmentos"

    Write-Host "OK renders\edited.mp4 gerado" -ForegroundColor Green
    Update-ProjectField "renders" @{ edited = "renders/edited.mp4"; draft = $null; final = $null }
}

# ------------------------------------------------------------------
# Phase: subs
# ------------------------------------------------------------------

function Invoke-SubsPhase {
    $style = $project.settings.subtitle_style
    if ($style -eq "sem") {
        Write-Host "subtitle_style=sem - skip"
        return
    }

    $assPath = Join-Path $ProjectDir "edit\subtitles.ass"
    if (-not (Test-Path $assPath)) {
        throw "edit\subtitles.ass nao existe. Skill deve gerar a partir do template antes de chamar este phase."
    }

    $input = Join-Path $ProjectDir "renders\edited.mp4"
    $output = Join-Path $ProjectDir "renders\edited_subs.mp4"

    $burnScript = Join-Path $PSScriptRoot "burn-subtitles.ps1"
    & $burnScript -InputVideo $input -Subtitles $assPath -Output $output -Preset $Quality -WorkspaceDir $WorkspaceDir
}

# ------------------------------------------------------------------
# Phase: effects
# ------------------------------------------------------------------

function Invoke-EffectsPhase {
    $beatsPlanPath = Join-Path $ProjectDir "beats_plan.json"
    if (-not (Test-Path $beatsPlanPath)) {
        Write-Host "beats_plan.json nao existe - sem efeitos a aplicar"
        return
    }
    $bp = Get-Content $beatsPlanPath -Raw | ConvertFrom-Json
    if (-not $bp.video_effects -or $bp.video_effects.Count -eq 0) {
        Write-Host "beats_plan sem video_effects - skip"
        return
    }

    $inputCandidate = Join-Path $ProjectDir "renders\edited_subs.mp4"
    if (-not (Test-Path $inputCandidate)) {
        $inputCandidate = Join-Path $ProjectDir "renders\edited.mp4"
    }

    $w = $project.media.display_width
    $h = $project.media.display_height
    $fps = $project.media.fps

    # Constroi filter_complex para zoompan
    $filters = @()
    foreach ($vfx in $bp.video_effects) {
        if ($vfx.type -eq "zoompan") {
            $s = $vfx.start
            $e = $vfx.end
            $maxZoom = if ($vfx.max_zoom) { $vfx.max_zoom } else { 1.25 }
            $rate = [math]::Round(($maxZoom - 1) / [math]::Max($e - $s, 0.5), 4)
            $expr = "if(between(in_time,$s,$e),min(1+$rate*(in_time-$s),$maxZoom),1)"
            $filters += "zoompan=z='$expr':d=1:s=${w}x${h}:fps=$fps"
        }
    }

    $output = Join-Path $ProjectDir "cache\base_with_effects.mp4"
    $videoArgs = Get-VideoCodecArgs $Quality

    if ($filters.Count -gt 0) {
        $ffargs = @(
            "-y",
            "-i", $inputCandidate,
            "-vf", ($filters -join ",")
        ) + $videoArgs + @("-c:a","copy",$output)
        Invoke-Ffmpeg -Arguments $ffargs -Description "Aplicar $($filters.Count) efeitos de video"
        Write-Host "OK cache\base_with_effects.mp4 gerado" -ForegroundColor Green
    }
}

# ------------------------------------------------------------------
# Phase: overlays
# ------------------------------------------------------------------

function Invoke-OverlaysPhase {
    $base = Join-Path $ProjectDir "cache\base_with_effects.mp4"
    if (-not (Test-Path $base)) {
        $base = Join-Path $ProjectDir "renders\edited_subs.mp4"
    }
    if (-not (Test-Path $base)) {
        $base = Join-Path $ProjectDir "renders\edited.mp4"
    }

    $overlayDir = Join-Path $ProjectDir "overlays"
    $overlays = @(Get-ChildItem -Path $overlayDir -Filter "*.mov" -ErrorAction SilentlyContinue) + @(Get-ChildItem -Path $overlayDir -Filter "*.mp4" -ErrorAction SilentlyContinue)

    $outDir = Join-Path $ProjectDir "renders\$Quality"
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    $out = Join-Path $outDir "$Quality.mp4"

    if ($overlays.Count -eq 0) {
        Write-Host "Sem overlays - a copiar base para $out"
        Copy-Item -Path $base -Destination $out -Force
        Update-ProjectField "renders" @{ $Quality = "renders/$Quality/$Quality.mp4" }
        return
    }

    # Le beats_plan para timing dos overlays
    $beatsPlanPath = Join-Path $ProjectDir "beats_plan.json"
    if (-not (Test-Path $beatsPlanPath)) {
        throw "beats_plan.json necessario para mapping overlay -> timing"
    }
    $bp = Get-Content $beatsPlanPath -Raw | ConvertFrom-Json

    # Constroi filter_complex
    $inputs = @("-i", $base)
    foreach ($ov in $overlays) {
        $inputs += @("-i", $ov.FullName)
    }

    $chain = "[0:v]"
    $i = 1
    foreach ($beat in $bp.beats) {
        $overlayName = $beat.id + ".mov"
        $ov = $overlays | Where-Object Name -eq $overlayName | Select-Object -First 1
        if (-not $ov) { continue }
        $start = $beat.start
        $end = $beat.start + $beat.duration
        $next = "v$i"
        $chain += "[$($i):v]overlay=0:0:enable='between(t,$start,$end)'[$next];[$next]"
        $i++
    }
    $chain = $chain.TrimEnd(';[v','[v]') + ",format=yuv420p[outv]"

    $videoArgs = Get-VideoCodecArgs $Quality
    $args = @("-y") + $inputs + @("-filter_complex", $chain, "-map", "[outv]", "-map", "0:a:0") + $videoArgs + @("-c:a","aac","-b:a","192k",$out)

    Invoke-Ffmpeg -Arguments $ffargs -Description "Compositar $($overlays.Count) overlays"
    Write-Host "OK renders\$Quality\$Quality.mp4 gerado" -ForegroundColor Green
    Update-ProjectField "renders" @{ $Quality = "renders/$Quality/$Quality.mp4" }
}

# ------------------------------------------------------------------
# Phase: verify
# ------------------------------------------------------------------

function Invoke-VerifyPhase {
    $target = Join-Path $ProjectDir "renders\$Quality\$Quality.mp4"
    if (-not (Test-Path $target)) {
        $target = Join-Path $ProjectDir "renders\final\final.mp4"
        if (-not (Test-Path $target)) {
            $target = Join-Path $ProjectDir "renders\draft\draft.mp4"
        }
    }
    if (-not (Test-Path $target)) {
        throw "Nenhum render encontrado em renders/"
    }

    # Duracao
    $cmd = "`"$ffprobeBin`" -v error -show_entries format=duration -of default=nw=1:nk=1 `"$target`" 2>&1"
    $durStr = (cmd /c $cmd).Trim()
    $duration = [double]::Parse($durStr, [System.Globalization.CultureInfo]::InvariantCulture)

    Write-Host "Duracao: $duration s"

    # Extrair frames
    $verifyDir = Join-Path $ProjectDir "verify"
    New-Item -ItemType Directory -Path $verifyDir -Force | Out-Null

    $timestamps = @(
        1.0,
        [math]::Round($duration * 0.25, 2),
        [math]::Round($duration * 0.5, 2),
        [math]::Round($duration * 0.75, 2),
        [math]::Round($duration - 1.0, 2)
    )

    # Junta picos de efeitos
    $beatsPlanPath = Join-Path $ProjectDir "beats_plan.json"
    if (Test-Path $beatsPlanPath) {
        $bp = Get-Content $beatsPlanPath -Raw | ConvertFrom-Json
        if ($bp.video_effects) {
            foreach ($vfx in $bp.video_effects) {
                $peak = [math]::Round(($vfx.start + $vfx.end) / 2, 2)
                $timestamps += $peak
            }
        }
    }

    $timestamps = $timestamps | Sort-Object -Unique | Where-Object { $_ -ge 0 -and $_ -le $duration }

    Write-Host "Extraindo $($timestamps.Count) frames para verify\..."
    foreach ($t in $timestamps) {
        $tFmt = "{0:0.000}" -f $t
        $out = Join-Path $verifyDir "frame_$tFmt.png"
        $ffargs = @("-y","-ss",$tFmt,"-i",$target,"-frames:v","1",$out)
        Invoke-Ffmpeg -Arguments $ffargs -Description "Frame $tFmt s"
    }

    # silencedetect
    $silenceCmd = "`"$ffmpegBin`" -i `"$target`" -af silencedetect=n=-30dB:d=2 -f null - 2>&1"
    $silenceOut = cmd /c $silenceCmd
    $silenceCount = ($silenceOut | Select-String "silence_start").Count

    Write-Host "Silencios > 2s: $silenceCount"
    Write-Host "OK Verificacao concluida ($($timestamps.Count) frames em verify/)" -ForegroundColor Green

    Update-ProjectField "checklist" @{
        duration_verified = $true
        verify_frames_extracted = $true
        silences_reviewed = ($silenceCount -le 1)
    }
}

# ------------------------------------------------------------------
# Dispatch
# ------------------------------------------------------------------

switch ($Phase) {
    "cut"      { Invoke-CutPhase }
    "subs"     { Invoke-SubsPhase }
    "effects"  { Invoke-EffectsPhase }
    "overlays" { Invoke-OverlaysPhase }
    "verify"   { Invoke-VerifyPhase }
    "all" {
        Invoke-CutPhase
        Invoke-SubsPhase
        Invoke-EffectsPhase
        Invoke-OverlaysPhase
        Invoke-VerifyPhase
    }
}

# Auto-cleanup do cache/ se pedido
if ($CleanCache) {
    $cacheDir = Join-Path $ProjectDir "cache"
    if (Test-Path $cacheDir) {
        Write-Host "A limpar cache/ (-CleanCache pedido)..."
        Get-ChildItem -Path $cacheDir -Recurse | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
        Write-Host "OK cache/ limpo (verify/ e renders/ mantidos)" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "Phase '$Phase' concluida." -ForegroundColor Green
