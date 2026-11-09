#requires -Version 5.1
param(
    [string]$SdkRoot = "",
    [Parameter(Mandatory = $true)][string]$PrivateModulesPath
)

$ErrorActionPreference = "Stop"
$distributionRoot = [System.IO.Path]::GetFullPath($PSScriptRoot)
$launcherRoot = Join-Path $distributionRoot "desktop-launcher"
$outputRoot = Join-Path $distributionRoot "dist-private"
$outputPath = Join-Path $outputRoot "SharpProsperoStudio-Source.zip"
$temporaryPath = "$outputPath.partial"

if (-not $SdkRoot) {
    $SdkRoot = [System.IO.Path]::GetFullPath(
        (Join-Path $distributionRoot "..\..\..\..\PS5-COMPILAR-HOMEBREW-main\PS5-COMPILAR-HOMEBREW-main")
    )
}
$SdkRoot = (Resolve-Path -LiteralPath $SdkRoot).Path
$PrivateModulesPath = (Resolve-Path -LiteralPath $PrivateModulesPath).Path
if (-not (Test-Path -LiteralPath (Join-Path $SdkRoot "LICENSE") -PathType Leaf) -or
    -not (Test-Path -LiteralPath (Join-Path $SdkRoot "build\build-app.ps1") -PathType Leaf)) {
    throw "SdkRoot must point to the SharpProspero source checkout."
}
if (-not (Test-Path -LiteralPath (Join-Path $PrivateModulesPath "libc.prx") -PathType Leaf)) {
    throw "PrivateModulesPath must contain libc.prx directly at its root."
}
if (-not (Test-Path -LiteralPath (Join-Path $distributionRoot "README-PRIVADO.md") -PathType Leaf)) {
    throw "README-PRIVADO.md is required to document this private build."
}

New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
foreach ($path in @($outputPath, $temporaryPath)) {
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        Remove-Item -LiteralPath $path -Force
    }
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::Open(
    $temporaryPath,
    [System.IO.Compression.ZipArchiveMode]::Create
)
$script:Archive = $archive
$script:SdkRoot = $SdkRoot
$script:SourceRoot = "SharpProsperoStudio-source"

function Add-ArchiveFile([string]$SourcePath, [string]$ArchivePath) {
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

function Add-SdkTree([string]$RelativePath) {
    $sourceDirectory = Join-Path $script:SdkRoot $RelativePath
    if (-not (Test-Path -LiteralPath $sourceDirectory -PathType Container)) {
        throw "Required SDK source folder is missing: $RelativePath"
    }
    foreach ($file in Get-ChildItem -LiteralPath $sourceDirectory -File -Recurse) {
        $relativeFile = $file.FullName.Substring($sourceDirectory.TrimEnd('\').Length).TrimStart('\')
        $segments = $relativeFile -split '\\'
        if ($segments | Where-Object { $_ -in @("bin", "obj", "out", "TestResults", ".vs") }) { continue }
        if ($segments | Where-Object { $_ -in @("sce_module", "payloads") }) { continue }
        if ($file.Extension -in @(".dll", ".exe", ".prx", ".sprx", ".elf", ".self", ".pkg")) { continue }
        Add-ArchiveFile $file.FullName (Join-Path "$($script:SourceRoot)\SharpProspero" (Join-Path $RelativePath $relativeFile))
    }
}

try {
    $studioFiles = @(
        @{ Source = (Join-Path $launcherRoot "Program.cs"); Archive = "desktop-launcher\Program.cs" },
        @{ Source = (Join-Path $launcherRoot "SharpProsperoStudio.Desktop.csproj"); Archive = "desktop-launcher\SharpProsperoStudio.Desktop.csproj" },
        @{ Source = (Join-Path $distributionRoot "index.html"); Archive = "index.html" },
        @{ Source = (Join-Path $distributionRoot "style.css"); Archive = "style.css" },
        @{ Source = (Join-Path $distributionRoot "demo.js"); Archive = "demo.js" },
        @{ Source = (Join-Path $distributionRoot "server.ps1"); Archive = "server.ps1" },
        @{ Source = (Join-Path $distributionRoot "run-build.ps1"); Archive = "run-build.ps1" },
        @{ Source = (Join-Path $distributionRoot "build-distribution.ps1"); Archive = "build-distribution.ps1" },
        @{ Source = (Join-Path $distributionRoot "build-source-archive.ps1"); Archive = "build-source-archive.ps1" },
        @{ Source = (Join-Path $distributionRoot "Yo-Removebg.png"); Archive = "Yo-Removebg.png" },
        @{ Source = (Join-Path $distributionRoot "README-PRIVADO.md"); Archive = "README-PRIVADO.md" },
        @{ Source = (Join-Path $distributionRoot "README-EXE.md"); Archive = "README-EXE.md" }
    )
    foreach ($file in $studioFiles) {
        if (-not (Test-Path -LiteralPath $file.Source -PathType Leaf)) {
            throw "Studio source file is missing: $($file.Source)"
        }
        Add-ArchiveFile $file.Source (Join-Path $script:SourceRoot (Join-Path "Studio" $file.Archive))
    }

    foreach ($relativeFile in @(
        "LICENSE",
        "README.md",
        "Directory.Build.props",
        "docs\setup.md",
        "docs\build-pipeline.md",
        "build\build-app.ps1",
        "build\InternalBridge.props",
        "build\Prospero.App.props",
        "build\Prospero.App.targets"
    )) {
        $sourceFile = Join-Path $SdkRoot $relativeFile
        if (-not (Test-Path -LiteralPath $sourceFile -PathType Leaf)) {
            throw "Required SDK source file is missing: $relativeFile"
        }
        Add-ArchiveFile $sourceFile (Join-Path "$SourceRoot\SharpProspero" $relativeFile)
    }

    foreach ($tree in @(
        "runtime",
        "src\SharpProspero",
        "tools\SharpProspero.Bindings.Generator",
        "tools\SharpProspero.Link",
        "tools\SharpProspero.Prx",
        "tools\SharpProspero.Texture"
    )) {
        Add-SdkTree $tree
    }

    $samplesRoot = Join-Path $SdkRoot "samples"
    $sampleCount = 0
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
        Add-SdkTree ("samples\" + $sample.Name)
        $sampleCount++
    }
    if ($sampleCount -eq 0) { throw "No application samples were found in the SDK source." }

    $moduleHash = (Get-FileHash -LiteralPath (Join-Path $PrivateModulesPath "libc.prx") -Algorithm SHA256).Hash
    $buildInfo = @"
# Source package build information

- Private executable: ``dist-private\SharpProsperoStudio.exe``
- SDK application samples included: $sampleCount
- Private module: ``libc.prx`` (not included in this source package)
- SHA-256 of the local module used for the private build: ``$moduleHash``

This archive contains the Studio source and the SharpProspero source tree embedded in the executable. It intentionally excludes compiled outputs, the private ``libc.prx`` binary, other proprietary SDK binaries and package-builder dependencies. To reproduce the private executable, provide a module folder you are authorized to use and follow ``Studio\README-PRIVADO.md``.
"@
    $buildInfoPath = Join-Path $env:TEMP ("SharpProsperoStudio-source-build-" + [guid]::NewGuid().ToString("N") + ".md")
    [System.IO.File]::WriteAllText($buildInfoPath, $buildInfo, (New-Object System.Text.UTF8Encoding($false)))
    try {
        Add-ArchiveFile $buildInfoPath (Join-Path $SourceRoot "BUILD-INFO.md")
    } finally {
        Remove-Item -LiteralPath $buildInfoPath -Force
    }
} finally {
    $archive.Dispose()
    $script:Archive = $null
    $script:SdkRoot = $null
    $script:SourceRoot = $null
}

Move-Item -LiteralPath $temporaryPath -Destination $outputPath -Force
$item = Get-Item -LiteralPath $outputPath
$hash = (Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash
Write-Output "Source archive: $($item.FullName)"
Write-Output "Size: $([math]::Round($item.Length / 1MB, 1)) MiB"
Write-Output "SHA-256: $hash"
