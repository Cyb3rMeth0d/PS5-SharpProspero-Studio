#requires -Version 5.1
param(
    [string]$SdkRoot = "",
    [string]$PrivateModulesPath = ""
)

$ErrorActionPreference = "Stop"
$distributionRoot = [System.IO.Path]::GetFullPath($PSScriptRoot)
$launcherProject = Join-Path $distributionRoot "desktop-launcher\SharpProsperoStudio.Desktop.csproj"
if (-not $SdkRoot) {
    $SdkRoot = [System.IO.Path]::GetFullPath(
        (Join-Path $distributionRoot "..\..\..\..\PS5-COMPILAR-HOMEBREW-main\PS5-COMPILAR-HOMEBREW-main")
    )
}
if (-not (Test-Path -LiteralPath (Join-Path $SdkRoot "LICENSE") -PathType Leaf) -or
    -not (Test-Path -LiteralPath (Join-Path $SdkRoot "build\build-app.ps1") -PathType Leaf)) {
    throw "La ruta debe apuntar al checkout fuente de SharpProspero."
}

$projectRoot = Join-Path $distributionRoot "desktop-launcher"
$objRoot = Join-Path $projectRoot "obj"
$bundlePath = Join-Path $objRoot "compiler-toolchain.zip"
$bundlePartialPath = "$bundlePath.partial"
$resolvedPrivateModulesPath = ""
$privateModuleBundlePath = Join-Path $objRoot "private-modules.zip"
$privateIconPath = Join-Path $objRoot "private-studio.ico"
$privateIconSource = Join-Path $distributionRoot "Yo-Removebg.png"
New-Item -ItemType Directory -Path $objRoot -Force | Out-Null
foreach ($temporaryPath in @($bundlePath, $bundlePartialPath, $privateModuleBundlePath, $privateIconPath)) {
    if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
        Remove-Item -LiteralPath $temporaryPath -Force
    }
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::Open(
    $bundlePartialPath,
    [System.IO.Compression.ZipArchiveMode]::Create
)

function Add-SourceFile([string]$SourcePath, [string]$ArchivePath) {
    $entry = $script:Archive.CreateEntry(
        ($ArchivePath -replace '\\', '/'),
        [System.IO.Compression.CompressionLevel]::Optimal
    )
    $input = [System.IO.File]::OpenRead($SourcePath)
    try {
        $output = $entry.Open()
        try { $input.CopyTo($output) }
        finally { $output.Dispose() }
    } finally {
        $input.Dispose()
    }
}

function Add-SourceTree([string]$RelativePath) {
    $sourceDirectory = Join-Path $script:SdkRoot $RelativePath
    if (-not (Test-Path -LiteralPath $sourceDirectory -PathType Container)) {
        throw "Falta una carpeta requerida del compilador: $RelativePath"
    }
    foreach ($file in Get-ChildItem -LiteralPath $sourceDirectory -File -Recurse) {
        $localPath = $file.FullName.Substring($sourceDirectory.TrimEnd('\').Length).TrimStart('\')
        $segments = $localPath -split '\\'
        if ($segments | Where-Object { $_ -in @("bin", "obj", "out", "TestResults", ".vs") }) { continue }
        if ($segments | Where-Object { $_ -in @("sce_module", "payloads") }) { continue }
        if ($file.Extension -in @(".dll", ".exe", ".prx", ".sprx", ".elf", ".self", ".pkg")) { continue }
        $archivePath = Join-Path $RelativePath $localPath
        Add-SourceFile $file.FullName $archivePath
    }
}

function New-PrivateExecutableIcon([string]$SourcePath, [string]$DestinationPath) {
    if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
        throw "The web logo needed for the private executable icon is missing: $SourcePath"
    }

    Add-Type -AssemblyName System.Drawing
    $source = [System.Drawing.Bitmap]::FromFile($SourcePath)
    $frames = @()
    try {
        $cropSize = [Math]::Min(245, [Math]::Min($source.Width, $source.Height))
        foreach ($size in @(16, 24, 32, 48, 64, 128, 256)) {
            $bitmap = New-Object System.Drawing.Bitmap -ArgumentList $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
            try {
                $graphics.Clear([System.Drawing.Color]::Transparent)
                $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
                $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
                $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                $graphics.DrawImage(
                    $source,
                    [System.Drawing.Rectangle]::new(0, 0, $size, $size),
                    [System.Drawing.Rectangle]::new(0, 0, $cropSize, $cropSize),
                    [System.Drawing.GraphicsUnit]::Pixel
                )
                $memory = New-Object System.IO.MemoryStream
                try {
                    $bitmap.Save($memory, [System.Drawing.Imaging.ImageFormat]::Png)
                    $frames += ,@{ Size = $size; Bytes = $memory.ToArray() }
                } finally {
                    $memory.Dispose()
                }
            } finally {
                $graphics.Dispose()
                $bitmap.Dispose()
            }
        }
    } finally {
        $source.Dispose()
    }

    $stream = [System.IO.File]::Open(
        $DestinationPath,
        [System.IO.FileMode]::Create,
        [System.IO.FileAccess]::Write,
        [System.IO.FileShare]::None
    )
    try {
        $writer = New-Object System.IO.BinaryWriter($stream)
        try {
            $writer.Write([uint16]0)
            $writer.Write([uint16]1)
            $writer.Write([uint16]$frames.Count)
            $imageOffset = 6 + (16 * $frames.Count)
            foreach ($frame in $frames) {
                $dimension = if ($frame.Size -eq 256) { [byte]0 } else { [byte]$frame.Size }
                $writer.Write($dimension)
                $writer.Write($dimension)
                $writer.Write([byte]0)
                $writer.Write([byte]0)
                $writer.Write([uint16]1)
                $writer.Write([uint16]32)
                $writer.Write([uint32]$frame.Bytes.Length)
                $writer.Write([uint32]$imageOffset)
                $imageOffset += $frame.Bytes.Length
            }
            foreach ($frame in $frames) {
                $writer.Write($frame.Bytes)
            }
        } finally {
            $writer.Dispose()
        }
    } finally {
        $stream.Dispose()
    }
}

try {
    $script:Archive = $archive
    $script:SdkRoot = (Resolve-Path -LiteralPath $SdkRoot).Path

    foreach ($file in @(
        "LICENSE",
        "README.md",
        "Directory.Build.props",
        "docs\setup.md",
        "docs\build-pipeline.md"
    )) {
        $path = Join-Path $script:SdkRoot $file
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Falta el archivo requerido para distribuir el código fuente: $file"
        }
        Add-SourceFile $path $file
    }

    foreach ($file in @(
        "build\build-app.ps1",
        "build\InternalBridge.props",
        "build\Prospero.App.props",
        "build\Prospero.App.targets"
    )) {
        $path = Join-Path $script:SdkRoot $file
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Falta un archivo requerido del compilador: $file"
        }
        Add-SourceFile $path $file
    }

    foreach ($tree in @(
        "runtime",
        "src\SharpProspero",
        "tools\SharpProspero.Bindings.Generator",
        "tools\SharpProspero.Link",
        "tools\SharpProspero.Prx",
        "tools\SharpProspero.Texture"
    )) {
        Add-SourceTree $tree
    }

    $samplesRoot = Join-Path $script:SdkRoot "samples"
    $includedSamples = 0
    foreach ($sample in Get-ChildItem -LiteralPath $samplesRoot -Directory) {
        if ($sample.Name -like "prospero-payload-*" -or
            $sample.Name -in @("kstuffSharp", "kstuffSharp-installer", "prospero-prx")) {
            continue
        }
        $appProject = Get-ChildItem -LiteralPath $sample.FullName -Filter "*.csproj" -File -Recurse |
            Where-Object {
                $_.FullName -notmatch '\\(bin|obj|out|tests)\\' -and
                (Get-Content -LiteralPath $_.FullName -Raw) -match '(?is)<Import\b[^>]*Prospero\.App\.props' -and
                (Get-Content -LiteralPath $_.FullName -Raw) -notmatch '(?is)<ProsperoModuleKind>\s*Prx\s*</ProsperoModuleKind>'
            } | Select-Object -First 1
        if (-not $appProject) { continue }
        Add-SourceTree ("samples\" + $sample.Name)
        $includedSamples++
    }
    if ($includedSamples -eq 0) { throw "No se encontró ninguna muestra de aplicación para incluir." }
} finally {
    if ($null -ne $archive) { $archive.Dispose() }
    $script:Archive = $null
    $script:SdkRoot = $null
}

Move-Item -LiteralPath $bundlePartialPath -Destination $bundlePath -Force
$bundleBytes = (Get-Item -LiteralPath $bundlePath).Length
Write-Output "Compiler source bundle: $bundlePath ($([math]::Round($bundleBytes / 1MB, 1)) MiB; $includedSamples app samples)"
if ($PrivateModulesPath) {
    $moduleFile = Join-Path $PrivateModulesPath "libc.prx"
    if (-not (Test-Path -LiteralPath $moduleFile -PathType Leaf)) {
        throw "Private module folder must contain libc.prx at its root: $PrivateModulesPath"
    }
    $resolvedPrivateModulesPath = (Resolve-Path -LiteralPath $PrivateModulesPath).Path
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $privateArchive = [System.IO.Compression.ZipFile]::Open(
        $privateModuleBundlePath,
        [System.IO.Compression.ZipArchiveMode]::Create
    )
    try {
        foreach ($module in Get-ChildItem -LiteralPath $resolvedPrivateModulesPath -File) {
            if ($module.Extension -notin @(".prx", ".sprx", ".bin")) { continue }
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $privateArchive,
                $module.FullName,
                $module.Name,
                [System.IO.Compression.CompressionLevel]::Optimal
            ) | Out-Null
        }
    } finally {
        $privateArchive.Dispose()
    }
    New-PrivateExecutableIcon $privateIconSource $privateIconPath
    Write-Output "Private modules bundled from: $resolvedPrivateModulesPath"
    Write-Output "Private executable icon generated from: $privateIconSource"
}
try {
    $publishDirectory = Join-Path $distributionRoot $(if ($resolvedPrivateModulesPath) { "dist-private" } else { "dist" })
    $publishArguments = @("publish", $launcherProject, "-c", "Release", "-p:PublishDir=$publishDirectory\")
    if ($resolvedPrivateModulesPath) {
        $publishArguments += "-p:ApplicationIcon=$privateIconPath"
    }
    & dotnet @publishArguments
    if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed with exit code $LASTEXITCODE." }
} finally {
    foreach ($temporaryPath in @($bundlePath, $privateModuleBundlePath, $privateIconPath)) {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
    }
}

$outputDirectory = if ($resolvedPrivateModulesPath) { "dist-private" } else { "dist" }
$executable = Join-Path $distributionRoot "$outputDirectory\SharpProsperoStudio.exe"
if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
    throw "The distribution executable was not created: $executable"
}
$item = Get-Item -LiteralPath $executable
$hash = (Get-FileHash -LiteralPath $executable -Algorithm SHA256).Hash
Write-Output "Distribution executable: $($item.FullName)"
Write-Output "Size: $([math]::Round($item.Length / 1MB, 1)) MiB"
Write-Output "SHA-256: $hash"
$usageGuideName = if ($resolvedPrivateModulesPath) { "README-PRIVADO.md" } else { "README-EXE.md" }
$usageGuide = Join-Path $distributionRoot $usageGuideName
if (-not (Test-Path -LiteralPath $usageGuide -PathType Leaf)) {
    throw "The executable usage guide is missing: $usageGuide"
}
Copy-Item -LiteralPath $usageGuide -Destination (Join-Path $item.DirectoryName "README.md") -Force
Write-Output "Usage guide: $(Join-Path $item.DirectoryName 'README.md')"
