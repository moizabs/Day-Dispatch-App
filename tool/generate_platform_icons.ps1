Add-Type -AssemblyName System.Drawing

$sourcePath = Join-Path $PSScriptRoot '..\assets\branding\daydispatch_app_icon.png'
$source = [System.Drawing.Image]::FromFile($sourcePath)

function Write-ResizedPng {
    param([string]$Path, [int]$Width, [int]$Height = $Width)

    $bitmap = New-Object System.Drawing.Bitmap($Width, $Height)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.DrawImage($source, 0, 0, $Width, $Height)
    $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose()
    $bitmap.Dispose()
}

$androidSizes = @{
    'mipmap-mdpi' = 48
    'mipmap-hdpi' = 72
    'mipmap-xhdpi' = 96
    'mipmap-xxhdpi' = 144
    'mipmap-xxxhdpi' = 192
}
foreach ($entry in $androidSizes.GetEnumerator()) {
    $path = Join-Path $PSScriptRoot "..\android\app\src\main\res\$($entry.Key)\ic_launcher.png"
    Write-ResizedPng $path $entry.Value
}

$assetFolders = @(
    (Join-Path $PSScriptRoot '..\ios\Runner\Assets.xcassets\AppIcon.appiconset'),
    (Join-Path $PSScriptRoot '..\macos\Runner\Assets.xcassets\AppIcon.appiconset')
)
foreach ($folder in $assetFolders) {
    Get-ChildItem $folder -Filter '*.png' | ForEach-Object {
        $existing = [System.Drawing.Image]::FromFile($_.FullName)
        $width = $existing.Width
        $height = $existing.Height
        $existing.Dispose()
        Write-ResizedPng $_.FullName $width $height
    }
}

Write-ResizedPng (Join-Path $PSScriptRoot '..\web\icons\Icon-192.png') 192
Write-ResizedPng (Join-Path $PSScriptRoot '..\web\icons\Icon-512.png') 512
Write-ResizedPng (Join-Path $PSScriptRoot '..\web\icons\Icon-maskable-192.png') 192
Write-ResizedPng (Join-Path $PSScriptRoot '..\web\icons\Icon-maskable-512.png') 512
Write-ResizedPng (Join-Path $PSScriptRoot '..\web\favicon.png') 32

$windowsBitmap = New-Object System.Drawing.Bitmap($source, 256, 256)
$icon = [System.Drawing.Icon]::FromHandle($windowsBitmap.GetHicon())
$stream = [System.IO.File]::Create(
    (Join-Path $PSScriptRoot '..\windows\runner\resources\app_icon.ico')
)
$icon.Save($stream)
$stream.Dispose()
$icon.Dispose()
$windowsBitmap.Dispose()
$source.Dispose()
