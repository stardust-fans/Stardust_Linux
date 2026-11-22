#requires -Version 5.1
# Generates StardustArch's original branding artwork. No Arch Linux logo or
# other official mark is copied or traced here.
Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Stop'

$out = Join-Path $PSScriptRoot '..\StardustArch\airootfs\etc\calamares\branding\stardustarch'
$out = [System.IO.Path]::GetFullPath($out)
New-Item -ItemType Directory -Force -Path $out | Out-Null

function New-BrushGradient {
    param($Rect, $C1, $C2, [System.Drawing.Drawing2D.LinearGradientMode]$Mode)
    return New-Object System.Drawing.Drawing2D.LinearGradientBrush($Rect, $C1, $C2, $Mode)
}

function Draw-Star {
    param($G, [float]$Cx, [float]$Cy, [float]$Outer, [float]$Inner, $Brush)
    $pts = New-Object 'System.Drawing.PointF[]' 8
    for ($i = 0; $i -lt 8; $i++) {
        $r = if (($i % 2) -eq 0) { $Outer } else { $Inner }
        $a = (-[Math]::PI / 2) + ($i * [Math]::PI / 4)
        $pts[$i] = New-Object System.Drawing.PointF(
            ([float]($Cx + [Math]::Cos($a) * $r)),
            ([float]($Cy + [Math]::Sin($a) * $r)))
    }
    $G.FillPolygon($Brush, $pts)
    $brush.Dispose()
}

function New-Logo {
    param([int]$Size)
    $bmp = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)

    $pad = [float]($Size * 0.035)
    $rect = New-Object System.Drawing.RectangleF($pad, $pad, ($Size - 2 * $pad), ($Size - 2 * $pad))
    $bg1 = [System.Drawing.Color]::FromArgb(255, 10, 15, 32)
    $bg2 = [System.Drawing.Color]::FromArgb(255, 29, 44, 82)
    $bg = New-BrushGradient $rect $bg1 $bg2 ([System.Drawing.Drawing2D.LinearGradientMode]::ForwardDiagonal)
    $g.FillEllipse($bg, $rect)
    $bg.Dispose()

    $rim = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(180, 116, 192, 255), [float]($Size * 0.006))
    $g.DrawEllipse($rim, $rect)
    $rim.Dispose()

    # Orbital ring, intentionally distinct from any distribution logo.
    $state = $g.Save()
    $g.TranslateTransform([float]($Size / 2), [float]($Size / 2))
    $g.RotateTransform(-24)
    $orbit = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(210, 95, 220, 235), [float]($Size * 0.012))
    $g.DrawEllipse($orbit, [float](-$Size * 0.34), [float](-$Size * 0.17), [float]($Size * 0.68), [float]($Size * 0.34))
    $orbit.Dispose()
    $g.Restore($state)

    $starRect = New-Object System.Drawing.RectangleF(0, 0, $Size, $Size)
    $gold1 = [System.Drawing.Color]::FromArgb(255, 255, 244, 196)
    $gold2 = [System.Drawing.Color]::FromArgb(255, 240, 198, 116)
    $starBrush = New-BrushGradient $starRect $gold2 $gold1 ([System.Drawing.Drawing2D.LinearGradientMode]::Vertical)
    Draw-Star -G $g -Cx ([float]($Size / 2)) -Cy ([float]($Size / 2)) -Outer ([float]($Size * 0.27)) -Inner ([float]($Size * 0.055)) -Brush $starBrush

    $dotBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(235, 116, 236, 255))
    $g.FillEllipse($dotBrush, [float]($Size * 0.72), [float]($Size * 0.49), [float]($Size * 0.035), [float]($Size * 0.035))
    $dotBrush.Dispose()

    $g.Dispose()
    return $bmp
}

function New-Banner {
    $bmp = New-Object System.Drawing.Bitmap(920, 160, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $g.Clear([System.Drawing.Color]::Transparent)

    $logo = New-Logo 128
    $g.DrawImage($logo, 8, 16, 128, 128)
    $logo.Dispose()

    $font = New-Object System.Drawing.Font('Segoe UI', 48, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 238, 242, 255))
    $g.DrawString('StardustArch', $font, $brush, 158, 30)
    $font.Dispose()

    $font2 = New-Object System.Drawing.Font('Segoe UI', 20, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
    $brush2 = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(220, 168, 190, 226))
    $g.DrawString('derived from Arch Linux  |  Plasma  |  ready on first boot', $font2, $brush2, 162, 96)
    $font2.Dispose()
    $brush.Dispose()
    $brush2.Dispose()

    $g.Dispose()
    return $bmp
}

function New-Wallpaper {
    $bmp = New-Object System.Drawing.Bitmap(1920, 1080, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $g.Clear([System.Drawing.Color]::FromArgb(255, 5, 8, 20))

    $rect = New-Object System.Drawing.RectangleF(0, 0, 1920, 1080)
    $bg = New-BrushGradient $rect ([System.Drawing.Color]::FromArgb(255, 5, 8, 20)) ([System.Drawing.Color]::FromArgb(255, 18, 31, 63)) ([System.Drawing.Drawing2D.LinearGradientMode]::ForwardDiagonal)
    $g.FillRectangle($bg, $rect)
    $bg.Dispose()

    $rand = New-Object System.Random(20261122)
    for ($i = 0; $i -lt 420; $i++) {
        $x = $rand.Next(0, 1920)
        $y = $rand.Next(0, 1080)
        $a = $rand.Next(30, 190)
        $s = if ($rand.NextDouble() -gt 0.93) { 3 } else { 1 }
        $b = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb($a, 210, 226, 255))
        $g.FillEllipse($b, $x, $y, $s, $s)
        $b.Dispose()
    }

    # Concentric orbital arcs on the right.
    $state = $g.Save()
    $g.TranslateTransform(1590, 410)
    $g.RotateTransform(-22)
    foreach ($spec in @(@(760, 310, 80), @(580, 220, 120), @(400, 140, 160))) {
        $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb($spec[2], 92, 210, 238), 2)
        $g.DrawEllipse($pen, -[float]$spec[0] / 2, -[float]$spec[1] / 2, [float]$spec[0], [float]$spec[1])
        $pen.Dispose()
    }
    $g.Restore($state)

    $glow = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(38, 80, 170, 255))
    $g.FillEllipse($glow, 1160, 100, 760, 760)
    $glow.Dispose()

    $logo = New-Logo 360
    $g.DrawImage($logo, 150, 265, 360, 360)
    $logo.Dispose()

    $titleFont = New-Object System.Drawing.Font('Segoe UI', 100, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $titleBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 242, 246, 255))
    $g.DrawString('StardustArch', $titleFont, $titleBrush, 130, 650)
    $titleFont.Dispose()
    $titleBrush.Dispose()

    $subFont = New-Object System.Drawing.Font('Segoe UI', 30, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
    $subBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(230, 183, 204, 237))
    $g.DrawString('derived from Arch Linux  |  KDE Plasma  |  built to be used, not configured', $subFont, $subBrush, 136, 785)
    $subFont.Dispose()
    $subBrush.Dispose()

    $rule = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(180, 240, 198, 116), 3)
    $g.DrawLine($rule, 136, 850, 760, 850)
    $rule.Dispose()

    $smallFont = New-Object System.Drawing.Font('Segoe UI', 22, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
    $smallBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(190, 147, 168, 205))
    $g.DrawString('Live / Install medium  |  not affiliated with or endorsed by the Arch Linux project', $smallFont, $smallBrush, 136, 880)
    $smallFont.Dispose()
    $smallBrush.Dispose()

    $g.Dispose()
    return $bmp
}

$logo = New-Logo 512
$logo.Save((Join-Path $out 'logo.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$logo.Dispose()

$banner = New-Banner
$banner.Save((Join-Path $out 'banner.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$banner.Dispose()

# The wallpaper is the user-supplied bg.png, converted once to wallpaper.jpg
# (2560x1600, darkened for UI readability). Do not generate a competing
# wallpaper.png here.

Get-ChildItem $out -Filter '*.png' | Select-Object Name, Length
