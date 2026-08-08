param(
    [Parameter(Mandatory)]
    [string]$OutputDir
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
[IO.Directory]::CreateDirectory($OutputDir) | Out-Null

function New-IconBitmap {
    param([int]$Width, [int]$Height, [string]$Path, [switch]$Wide)

    $bitmap = New-Object Drawing.Bitmap($Width, $Height)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.Clear([Drawing.Color]::FromArgb(31, 41, 55))

        $unit = [Math]::Min($Width, $Height)
        $markSize = [int]($unit * 0.72)
        $markLeft = if ($Wide) { [int](($Width - $markSize) / 2) } else { [int](($Width - $markSize) / 2) }
        $markTop = [int](($Height - $markSize) / 2)
        $barWidth = [int]($markSize / 3)
        $barTop = $markTop + [int]($markSize * 0.62)
        $barHeight = [Math]::Max(2, [int]($markSize * 0.16))

        $brushes = @(
            (New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(16, 163, 127))),
            (New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(37, 99, 235))),
            (New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(109, 40, 217)))
        )
        try {
            for ($index = 0; $index -lt 3; $index++) {
                $graphics.FillRectangle($brushes[$index], $markLeft + ($index * $barWidth), $barTop, $barWidth, $barHeight)
            }
        }
        finally {
            foreach ($brush in $brushes) { $brush.Dispose() }
        }

        $penWidth = [Math]::Max(2, [int]($unit * 0.045))
        $pen = New-Object Drawing.Pen([Drawing.Color]::White, $penWidth)
        $pen.StartCap = [Drawing.Drawing2D.LineCap]::Round
        $pen.EndCap = [Drawing.Drawing2D.LineCap]::Round
        try {
            $left = $markLeft + [int]($markSize * 0.16)
            $right = $markLeft + [int]($markSize * 0.84)
            $upper = $markTop + [int]($markSize * 0.30)
            $lower = $markTop + [int]($markSize * 0.50)
            $arrow = [int]($markSize * 0.13)
            $graphics.DrawLine($pen, $left, $upper, $right, $upper)
            $graphics.DrawLine($pen, $right, $upper, $right - $arrow, $upper - $arrow)
            $graphics.DrawLine($pen, $right, $upper, $right - $arrow, $upper + $arrow)
            $graphics.DrawLine($pen, $right, $lower, $left, $lower)
            $graphics.DrawLine($pen, $left, $lower, $left + $arrow, $lower - $arrow)
            $graphics.DrawLine($pen, $left, $lower, $left + $arrow, $lower + $arrow)
        }
        finally { $pen.Dispose() }

        $bitmap.Save($Path, [Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

New-IconBitmap 50 50 (Join-Path $OutputDir 'StoreLogo.png')
New-IconBitmap 44 44 (Join-Path $OutputDir 'Square44x44Logo.png')
New-IconBitmap 150 150 (Join-Path $OutputDir 'Square150x150Logo.png')
New-IconBitmap 310 150 (Join-Path $OutputDir 'Wide310x150Logo.png') -Wide
New-IconBitmap 44 44 (Join-Path $OutputDir 'Square44x44Logo.targetsize-44_altform-unplated.png')
