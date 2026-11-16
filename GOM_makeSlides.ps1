# GOM_makeSlides.ps1
#
# Builds a PowerPoint deck (opens in Google Slides) from the figures made by
# GOM_plotLSGupdate.m. Needs PowerPoint installed (Windows). Run in PowerShell:
#   powershell -ExecutionPolicy Bypass -File GOM_makeSlides.ps1
# Optional: -PreviewDir <folder> also exports every slide as a PNG.
#
# Inputs
#   <Root>\<SITE>\GOM_<SITE>_LSG_HourlyAves_*.png / _LSG_DailyV3_*.png  (plain LSGs)
#   <OutDir>\GOM_<SITE>_LSG_*_newDeploymentMarked.png                  (dashed-line LSGs)
#   <OutDir>\GOM_deployment_median_band_levels.csv                     (speaker notes, table)

param(
    [string]$Root      = 'L:\Shared drives\MBARC_GOM\GOM x SIO x NOAA\GOM Ambient Noise\HourlyAves',
    [string]$OutDir    = 'H:\GOM_LSG_2026',
    [string]$DeckName  = 'GOM_LSG_2026_update.pptx',
    [string]$Title     = 'Gulf of Mexico Ambient Noise',
    [string]$Subtitle  = '2025-2026 HARP deployments in the full long-term record',
    [string]$DateLine  = 'November 2026',
    [string]$PreviewDir = '',
    # optional: lines of "SITE<tab>observation" appended to that site's speaker notes
    [string]$ObsFile   = ''
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

# Site groups, in presentation order
$groups = [ordered]@{
    'Long-term sites (NRDA / RESTORE)'   = @('GC','MC','DT','LC','AC','DC','CE','MR')
    'Shipping-lane sites (NRDA)'          = @('TP','PCC')
    'Short-term sites (RESTORE year 6)'   = @('Y6B','Y6C','Y6D')
}

$nd = [char]0x2013; $mu = [char]0x00B5; $sq = [char]0x00B2
$units = "dB re 1 ${mu}Pa${sq}/Hz"

function Col([string]$hex) {   # PowerPoint wants BGR integers
    $r = [Convert]::ToInt32($hex.Substring(0,2),16)
    $g = [Convert]::ToInt32($hex.Substring(2,2),16)
    $b = [Convert]::ToInt32($hex.Substring(4,2),16)
    return $r + 256*$g + 65536*$b
}
$NAVY  = Col '14213D'; $TEAL = Col '0E6E73'; $INK = Col '1F2933'; $GREY = Col '5B6770'
$WHITE = Col 'FFFFFF'; $MIST = Col 'EAF1F4'; $AMBER = Col 'C8611A'; $LINE = Col 'C9D3DA'

# Octave bands reported as in MPL TM 678 (sec. 4.4.1): median hourly-average octave band levels.
# 31.5 Hz = seismic airguns, 63 / 125 Hz = shipping (125 Hz also covers Rice's whale calls), 500 Hz = weather
$bands = @(
    @{ Col = 'OB31_5'; Name = '31.5 Hz (airguns)' },
    @{ Col = 'OB63';   Name = '63 Hz (shipping)' },
    @{ Col = 'OB125';  Name = '125 Hz (shipping, Rice''s whale calls)' },
    @{ Col = 'OB500';  Name = '500 Hz (weather)' }
)
$obUnits = "dB re 1 ${mu}Pa${sq}"

$csvPath = Join-Path $OutDir 'GOM_deployment_median_band_levels.csv'
$rows = Import-Csv $csvPath
# made by the octave-band step (see README_old_vs_new.md): per deployment, and per site for Aug 2020 - Jul 2025
$oct  = @(Import-Csv (Join-Path $OutDir 'GOM_deployment_octave_bands.csv'))
$oct5 = @(Import-Csv (Join-Path $OutDir 'GOM_site_octave_bands_2020-2025.csv'))
if (-not $ObsFile) { $ObsFile = Join-Path $OutDir 'site_observations.txt' }
$obs = @{}
if (Test-Path $ObsFile) {
    foreach ($ln in Get-Content $ObsFile) {
        if ($ln -match '^\s*#' -or $ln -notmatch "`t") { continue }
        $k, $v = $ln -split "`t", 2
        $obs[$k.Trim()] = $v.Trim()
    }
}

$app  = New-Object -ComObject PowerPoint.Application
$pres = $app.Presentations.Add(0)
$pres.PageSetup.SlideWidth  = 960
$pres.PageSetup.SlideHeight = 540
$W = 960; $H = 540; $M = 36

function New-Slide {
    $s = $pres.Slides.Add($pres.Slides.Count + 1, 12)   # ppLayoutBlank
    return $s
}
function Add-Text($slide, [string]$text, $l, $t, $w, $h, $size, [bool]$bold, $color, [int]$align = 1, [string]$name = '') {
    $tb = $slide.Shapes.AddTextbox(1, $l, $t, $w, $h)
    if ($name) { $tb.Name = $name }
    $tf = $tb.TextFrame
    $tf.WordWrap = -1; $tf.AutoSize = 0
    $tf.MarginLeft = [single]0; $tf.MarginRight = [single]0; $tf.MarginTop = [single]0; $tf.MarginBottom = [single]0
    $tr = $tf.TextRange
    $tr.Text = $text
    $tr.Font.Name = 'Calibri'; $tr.Font.Size = [single]$size; $tr.Font.Color.RGB = $color
    $tr.Font.Bold = $(if ($bold) { -1 } else { 0 })
    $tr.ParagraphFormat.Alignment = $align
    return $tb
}
function Set-Bg($slide, $color) {
    $slide.FollowMasterBackground = 0
    $slide.Background.Fill.Solid()
    $slide.Background.Fill.ForeColor.RGB = $color
}
function Add-Notes($slide, [string]$text) {
    $slide.NotesPage.Shapes.Placeholders(2).TextFrame.TextRange.Text = $text
}
function Add-SlideTitle($slide, [string]$text, [string]$sub = '') {
    [void](Add-Text $slide $text $M 18 ($W - 2*$M) 34 26 $true $NAVY 1 'Title')
    if ($sub) { [void](Add-Text $slide $sub $M 50 ($W - 2*$M) 18 13 $false $GREY 1 'Subtitle') }
}
function Add-Card($slide, $l, $t, $w, $h, $fill) {
    $c = $slide.Shapes.AddShape(5, $l, $t, $w, $h)   # rounded rectangle
    $c.Adjustments.Item(1) = [single]0.06
    $c.Fill.ForeColor.RGB = $fill; $c.Line.Visible = 0
    return $c
}
function Find-Png([string]$dir, [string]$pattern) {
    $f = Get-ChildItem -Path $dir -Filter $pattern -File -ErrorAction SilentlyContinue |
         Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($f) { return $f.FullName } else { return $null }
}
function Add-FigurePair($slide, [string]$top, [string]$bottom, [string]$caption) {
    # NB: PowerShell variable names are case-insensitive -- don't reuse $w/$h here ($W/$H = slide size)
    $y = 76
    foreach ($p in @($top, $bottom)) {
        if (-not $p) { continue }
        $img = [System.Drawing.Image]::FromFile($p); $ar = $img.Height / $img.Width; $img.Dispose()
        $picW = $W - 2*$M + 12; $picH = $picW * $ar
        if ($picH -gt 206) { $picH = 206; $picW = $picH / $ar }
        [void]$slide.Shapes.AddPicture($p, 0, -1, ($W - $picW) / 2, $y, $picW, $picH)
        $y += $picH + 8
    }
    [void](Add-Text $slide "$caption   Colour: spectrum level, $units." `
        $M ($H - 26) ($W - 2*$M) 14 10.5 $false $GREY 1 'Caption')
}
function Fmt($v) { return ('{0:N1}' -f [double]$v) }
function IsNewRow($r) { return ($r.IsNew -eq '1' -or $r.IsNew -eq 'true') }
function Pct($v) { return ('{0:N0}%' -f [double]$v) }
function DbDiff($a, $b) { $d = [double]$a - [double]$b; return ('{0}{1:N1}' -f $(if ($d -ge 0) { '+' } else { '-' }), [math]::Abs($d)) }
function Site-Notes([string]$site) {
    $d = @($oct | Where-Object { $_.Site -eq $site } | Sort-Object Start)
    $new = @($d | Where-Object { IsNewRow $_ })
    $old = @($d | Where-Object { -not (IsNewRow $_) -and [double]$_.OB31_5 -gt 60 })
    $n = $new[-1]
    $tf = ($rows | Where-Object { $_.Deployment -eq $n.Deployment } | Select-Object -First 1).TF
    $lines = @()
    if ($obs.ContainsKey($site)) { $lines += $obs[$site]; $lines += "" }
    $lines += "$($n.Deployment): $($n.Start) to $($n.End), $($n.nHours) hours, TF $tf."
    if ($old.Count -gt 0) {
        $p = $old[-1]
        $five = $oct5 | Where-Object { $_.Site -eq $site } | Select-Object -First 1
        $lines += "Median hourly-average octave band levels ($obUnits): 2025${nd}2026 | 2020${nd}2025 median at $site (difference) | previous deployment $($p.Deployment)"
        foreach ($b in $bands) {
            $lines += "  $($b.Name): $(Fmt $n.($b.Col)) | $(Fmt $five.($b.Col)) ($(DbDiff $n.($b.Col) $five.($b.Col))) | $(Fmt $p.($b.Col))"
        }
    } else {
        $lines += "Median hourly-average octave band levels ($obUnits), first year at this site:"
        foreach ($b in $bands) { $lines += "  $($b.Name): $(Fmt $n.($b.Col))" }
    }
    return ($lines -join "`r`n")
}

# ---------------------------------------------------------------- Title
$s = New-Slide; Set-Bg $s $NAVY
[void](Add-Text $s $Title $M 170 ($W - 2*$M) 60 44 $true $WHITE 1 'Title')
[void](Add-Text $s $Subtitle $M 236 ($W - 2*$M) 30 22 $false (Col 'CFE3EA') 1 'Subtitle')
$siteCount = ($groups.Values | ForEach-Object { $_ }).Count
[void](Add-Text $s "Long-term spectrograms for $siteCount sites  |  $DateLine" $M 300 ($W - 2*$M) 22 16 $false (Col '9FB8C4') 1 'DateLine')

# ---------------------------------------------------------------- New deployments table
$s = New-Slide; Set-Bg $s $WHITE
$newRows = @($rows | Where-Object { $_.IsNew -eq '1' -or $_.IsNew -eq 'true' })
$order = @($groups.Values | ForEach-Object { $_ })
$newRows = $newRows | Sort-Object { [array]::IndexOf($order, $_.Site) }
Add-SlideTitle $s "$($newRows.Count) deployments recovered in 2026" 'Processed with GOM_runHourlyAves.m (df100 LTSAs, 1 Hz bins, TF = latest revision for each preamp)'
$nr = $newRows.Count + 1
$tbl = $s.Shapes.AddTable($nr, 5, $M, 80, $W - 2*$M, 22 * $nr).Table
$hdr = @('Site', 'Deployment', 'Recording period', 'Hours', 'Transfer function')
$widths = @(70, 170, 260, 90, 298)
for ($c = 1; $c -le 5; $c++) { $tbl.Columns.Item($c).Width = [single]$widths[$c-1] }
for ($r = 1; $r -le $nr; $r++) {
    if ($r -eq 1) { $vals = $hdr } else {
        $x = $newRows[$r-2]
        $vals = @($x.Site, $x.Deployment, "$($x.Start)  to  $($x.End)", ('{0:N0}' -f [int]$x.nHours), $x.TF)
    }
    for ($c = 1; $c -le 5; $c++) {
        $cell = $tbl.Cell($r, $c)
        $cell.Shape.Fill.Solid()
        $cell.Shape.Fill.ForeColor.RGB = $(if ($r -eq 1) { $NAVY } elseif ($r % 2 -eq 0) { $WHITE } else { $MIST })
        $tr = $cell.Shape.TextFrame.TextRange
        $tr.Text = [string]$vals[$c-1]
        $tr.Font.Name = 'Calibri'; $tr.Font.Size = [single]12
        $tr.Font.Color.RGB = $(if ($r -eq 1) { $WHITE } else { $INK })
        $tr.Font.Bold = $(if ($r -eq 1) { -1 } else { 0 })
        $cell.Shape.TextFrame.MarginTop = [single]2; $cell.Shape.TextFrame.MarginBottom = [single]2
    }
    $tbl.Rows.Item($r).Height = [single]22
}
Add-Notes $s "All deployments ran without empty hours. GC_18, MC_20 and Y6D_01 were added to the HARP data summary by hand (preamps 978, 927, 961). CE_06 uses the rev C TF for preamp 988. DT_18_01 and DT_18_02 (4-channel HARPs) were not on the decimated drives; Y6A was lost."

# ---------------------------------------------------------------- Methods / what changed
$s = New-Slide; Set-Bg $s $WHITE
Add-SlideTitle $s 'What the v3 daily spectrograms show' 'Each site slide: top = full record with the newest deployment marked; bottom = newest deployment only'
$cw = ($W - 2*$M - 24) / 2
$cards = @(
    @{ X = $M;            Head = 'v3 daily spectra';
       Body = "Daily median of the hourly, transfer-function-corrected spectra (10${nd}1000 Hz, 1 Hz bins)`rFIFO noise (50 Hz harmonics) removed where detected (45 deployments)`rDeck test (hours before each deployment's data start) removed`rNo amplitude threshold: every recorded day is kept`rBands: 31.5, 63, 125, 500 Hz octave bands (MPL TM 678)" },
    @{ X = $M + $cw + 24; Head = 'Updated in the shared folder';
       Body = "HourlyAves for all 13 new 2025${nd}2026 deployments`rv3 cleaned daily/hourly files (.mat, .csv) and LSGs for all 42 GOM sites`rREADME.txt in each site folder: every file and the script that made it`rOld v2 files moved to each site's Old files folder, with a README" }
)
foreach ($k in $cards) {
    [void](Add-Card $s $k.X 84 $cw 210 $MIST)
    [void](Add-Text $s $k.Head ($k.X + 20) 100 ($cw - 40) 26 19 $true $TEAL 1)
    $b = Add-Text $s $k.Body ($k.X + 20) 136 ($cw - 40) 150 15 $false $INK 1
    $b.TextFrame.TextRange.ParagraphFormat.Bullet.Visible = -1
    $b.TextFrame.TextRange.ParagraphFormat.Bullet.Type = 1          # ppBulletUnnumbered
    $b.TextFrame.TextRange.ParagraphFormat.Bullet.Character = 8226
    $b.TextFrame.TextRange.ParagraphFormat.SpaceAfter = [single]8
}
[void](Add-Card $s $M 314 ($W - 2*$M) 140 $NAVY)
[void](Add-Text $s '21 of 316' ($M + 24) 338 260 60 44 $true (Col 'F4B183') 1)
[void](Add-Text $s 'days kept at Y5A in the old v2 cleaned files' ($M + 24) 398 260 40 14 $false $WHITE 1)
[void](Add-Text $s ("The old cleaning script deleted every day whose 18${nd}25 Hz level was 82 dB or more, a limit tuned for Southern California. The GOM is much louder at low frequency, so this removed most of the record (DT, LC and AC kept 22${nd}25% of days). Products built from the old v2 files should be checked.") `
    ($M + 310) 336 ($W - 2*$M - 334) 130 14 $false $WHITE 1)
Add-Notes $s "Code and full explanation: github.com/MarineBioAcousticsRC/LTSA2LSG_v2 (README_old_vs_new.md). Anything built from the GOM *_cleaned_v2.mat or *_cleaned.csv files should be checked. HourlyAves files were never thresholded."

# ---------------------------------------------------------------- Site slides
$missing = @()
foreach ($g in $groups.Keys) {
    $s = New-Slide; Set-Bg $s $NAVY
    [void](Add-Text $s $g $M 200 ($W - 2*$M) 50 34 $true $WHITE 1 'Title')
    [void](Add-Text $s (($groups[$g]) -join '   ') $M 256 ($W - 2*$M) 30 20 $false (Col 'CFE3EA') 1)

    foreach ($site in $groups[$g]) {
        $full = Find-Png $OutDir "GOM_${site}_LSG_DailyV3_*_newDeploymentMarked.png"
        $zoom = Find-Png $OutDir "GOM_${site}_LSG_DailyV3_*_latestDeployment.png"
        if (-not $zoom) { $missing += $site; continue }
        $d = @($rows | Where-Object { $_.Site -eq $site } | Sort-Object Start)
        $new = @($d | Where-Object { $_.IsNew -eq '1' -or $_.IsNew -eq 'true' })
        $span = "$(([datetime]$d[0].Start).ToString('MMM yyyy')) $nd $(([datetime]$d[-1].End).ToString('MMM yyyy'))"

        $s = New-Slide; Set-Bg $s $WHITE
        if ($full) {
            Add-SlideTitle $s "GOM $site  |  $span" "$($d.Count) deployments; newest: $($new[-1].Deployment) (from $($new[-1].Start), dashed line)"
            Add-FigurePair $s $full $zoom "Daily median spectra (v3).  Top: full record.  Bottom: newest deployment."
        } else {
            Add-SlideTitle $s "GOM $site  |  first deployment, $span" "$($d[0].Deployment)"
            Add-FigurePair $s $zoom $null "Daily median spectra (v3)."
            # key numbers for this first deployment
            $q = $oct | Where-Object { $_.Deployment -eq $new[-1].Deployment } | Select-Object -First 1
            $stats = @(
                @{ V = "$(Fmt $q.OB31_5) dB"; L = "31.5 Hz octave band (airguns), median hourly level" },
                @{ V = "$(Fmt $q.OB125) dB";  L = "125 Hz octave band (shipping, Rice's whale calls)" },
                @{ V = "$(Fmt $q.OB500) dB";  L = "500 Hz octave band (weather)" }
            )
            $gap = 20; $cw3 = ($W - 2*$M - 2*$gap) / 3
            for ($i = 0; $i -lt $stats.Count; $i++) {
                $x = $M + $i * ($cw3 + $gap)
                [void](Add-Card $s $x 318 $cw3 150 $MIST)
                [void](Add-Text $s $stats[$i].V ($x + 20) 340 ($cw3 - 40) 50 36 $true $TEAL 1)
                [void](Add-Text $s $stats[$i].L ($x + 20) 396 ($cw3 - 40) 44 14 $false $INK 1)
            }
        }
        Add-Notes $s (Site-Notes $site)
    }
}

# ---------------------------------------------------------------- Summary: seismic levels 2025-2026
$s = New-Slide; Set-Bg $s $WHITE
Add-SlideTitle $s "Airgun-band noise levels in 2025${nd}2026" "Median hourly-average 31.5 Hz octave band level ($obUnits), compared with the 2020${nd}2025 median at each site (MPL TM 678)"
$sum = @()
foreach ($site in $order) {
    $nw = @($oct | Where-Object { $_.Site -eq $site -and (IsNewRow $_) } | Sort-Object Start)
    if ($nw.Count -eq 0) { continue }
    $hasOld = @($oct | Where-Object { $_.Site -eq $site -and -not (IsNewRow $_) }).Count -gt 0
    $five = $(if ($hasOld) { $oct5 | Where-Object { $_.Site -eq $site } | Select-Object -First 1 } else { $null })
    $sum += [pscustomobject]@{ Site = $site; New = $nw[-1]; Five = $five }
}
$sum = $sum | Sort-Object { -[double]$_.New.OB31_5 }
$nr = $sum.Count + 1
$tbl = $s.Shapes.AddTable($nr, 5, $M, 84, $W - 2*$M, 26 * $nr).Table
$hdr = @('Site', "31.5 Hz, 2025${nd}2026", "31.5 Hz, 2020${nd}2025", 'Difference (dB)', "125 Hz, 2025${nd}2026")
$widths = @(90, 200, 200, 190, 208)
for ($c = 1; $c -le 5; $c++) { $tbl.Columns.Item($c).Width = [single]$widths[$c-1] }
for ($r = 1; $r -le $nr; $r++) {
    if ($r -eq 1) { $vals = $hdr } else {
        $x = $sum[$r-2]
        $vals = @($x.Site, (Fmt $x.New.OB31_5),
                  $(if ($x.Five) { Fmt $x.Five.OB31_5 } else { "first year" }),
                  $(if ($x.Five) { DbDiff $x.New.OB31_5 $x.Five.OB31_5 } else { "" }),
                  (Fmt $x.New.OB125))
    }
    for ($c = 1; $c -le 5; $c++) {
        $cell = $tbl.Cell($r, $c)
        $cell.Shape.Fill.Solid()
        $hi = ($r -gt 1 -and [double]$sum[$r-2].New.OB31_5 -ge 105)
        $cell.Shape.Fill.ForeColor.RGB = $(if ($r -eq 1) { $NAVY } elseif ($hi -and $c -le 3) { Col 'FBE3D2' } elseif ($r % 2 -eq 0) { $WHITE } else { $MIST })
        $tr = $cell.Shape.TextFrame.TextRange
        $tr.Text = [string]$vals[$c-1]
        $tr.Font.Name = 'Calibri'; $tr.Font.Size = [single]13
        $tr.Font.Color.RGB = $(if ($r -eq 1) { $WHITE } else { $INK })
        $tr.Font.Bold = $(if ($r -eq 1 -or $c -eq 1) { -1 } else { 0 })
        $tr.ParagraphFormat.Alignment = $(if ($c -eq 1) { 1 } else { 2 })
        $cell.Shape.TextFrame.MarginTop = [single]2; $cell.Shape.TextFrame.MarginBottom = [single]2
    }
    $tbl.Rows.Item($r).Height = [single]26
}
Add-Notes $s ("Sorted from highest to lowest 31.5 Hz octave band level; shaded rows are at or above 105 dB. " +
    "As in MPL TM 678, the 31.5 Hz octave band represents airgun survey noise and the 63 and 125 Hz bands shipping noise in the absence of airguns (125 Hz also covers Rice's whale call frequencies). " +
    "Levels are medians of hourly-average octave band levels from the HourlyAves files, with FIFO noise interpolated out and the deck test removed as in v3; the 2020${nd}2025 medians (Aug 2020 ${nd} Jul 2025) reproduce the report (e.g. 109 dB at GC and CE at 31.5 Hz; 82 dB at DC at 125 Hz). " +
    "Airgun-band levels in 2025${nd}2026 were above the 2020${nd}2025 median at most long-term sites (GC, CE, MC, MR, LC), unchanged at AC and DC, and much lower at DT. " +
    "Tables: GOM_deployment_octave_bands.csv and GOM_site_octave_bands_2020-2025.csv.")

# ---------------------------------------------------------------- Discussion
$s = New-Slide; Set-Bg $s $WHITE
Add-SlideTitle $s 'Things to check' 'Open questions from this update'
$items = @(
    @{ Head = 'Quiet year at DT?';         Body = "31.5 Hz is 12 dB below DT_17 from the first month, but 125 Hz is unchanged: fewer surveys, or a low-frequency issue with preamp 947 (MC_19 also low)?" },
    @{ Head = 'Sensitivity drop-off';      Body = "AC_06, PCC_01 and Y6D_01: all bands fall in the last 2${nd}3 months (500 Hz 3${nd}5 dB below the same month in 2025). Check disk by disk." },
    @{ Head = 'Broken deployments';        Body = "GC_15 (Jul 2022${nd}Jul 2023) has ~29 dB in every band; DC_12 (late 2018) is negative. Fix or exclude." },
    @{ Head = 'Where were the surveys?';   Body = "Airgun band highest at CE, GC, LC, Y6D and AC; lowest at DC, DT, Y6C and Y6B. Compare with 2025${nd}2026 survey tracks." },
    @{ Head = 'Older TFs';                 Body = "9 earlier deployments (GA_01${nd}04, SL_01${nd}02, Y5A_01, GC05, MC06) not made with the latest TF revision; redo on hold." },
    @{ Head = 'Who used v2 files?';        Body = "Products built from GOM *_cleaned_v2 / *_cleaned.csv are missing most days and need revising." }
)
$gap = 20; $cw = ($W - 2*$M - 2*$gap) / 3; $ch = 196
for ($i = 0; $i -lt $items.Count; $i++) {
    $x = $M + ($i % 3) * ($cw + $gap); $y = 84 + [math]::Floor($i / 3) * ($ch + $gap)
    [void](Add-Card $s $x $y $cw $ch $MIST)
    [void](Add-Text $s ([string]($i + 1)) ($x + 18) ($y + 14) 30 34 26 $true $AMBER 1)
    [void](Add-Text $s $items[$i].Head ($x + 52) ($y + 20) ($cw - 68) 24 16 $true $TEAL 1)
    [void](Add-Text $s $items[$i].Body ($x + 18) ($y + 60) ($cw - 36) ($ch - 72) 14 $false $INK 1)
}
Add-Notes $s ("Monthly octave band medians for each new deployment: GOM_new_deployments_monthly_octave_bands.csv. " +
    "Item 2 follows the Sept 2026 email thread on hydrophone sensitivity loss (RW sites, VK_01_01_C4, TUX_02): the drop-off does not happen at a fixed point or in the same way each time, so sites used for ambient levels should be checked disk by disk. " +
    "The final month of each deployment is partial (recovery), so the late drops are candidates, not confirmed. Preamp 947 was also used for GC_16, Y1B and Y2D.")

# ---------------------------------------------------------------- Save
$deck = Join-Path $OutDir $DeckName
$pres.SaveAs($deck, 24)
Write-Output "Saved $deck ($($pres.Slides.Count) slides)"
if ($missing.Count -gt 0) { Write-Output "No figures found for: $($missing -join ', ')" }
if ($PreviewDir) {
    New-Item -ItemType Directory -Force $PreviewDir | Out-Null
    for ($i = 1; $i -le $pres.Slides.Count; $i++) {
        $pres.Slides($i).Export((Join-Path $PreviewDir ('slide-{0:D2}.png' -f $i)), 'PNG', 1600, 900)
    }
    Write-Output "Previews in $PreviewDir"
}
$pres.Close()
$app.Quit()
[void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($app)
