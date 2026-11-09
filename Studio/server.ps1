#requires -Version 5.1
param(
    [int]$Port = 8765,
    [string]$SdkRoot = "",
    [string]$ModulesPath = ""
)

$ErrorActionPreference = "Stop"
$script:UiRoot = [System.IO.Path]::GetFullPath($PSScriptRoot)
$script:Jobs = @{}
$script:ModulesRoot = $ModulesPath
$script:PackageSupported = $false
$script:ShutdownRequested = $false
$script:ShutdownToken = $env:SHARP_PROSPERO_STUDIO_SHUTDOWN_TOKEN
$script:ServerRoot = $SdkRoot
$script:PowerShellExe = (Get-Process -Id $PID).Path
$script:Prefix = "http://127.0.0.1:$Port/"
$script:Origin = "http://127.0.0.1:$Port"
$script:LogRoot = Join-Path ([System.IO.Path]::GetTempPath()) "SharpProsperoStudio"
New-Item -ItemType Directory -Path $script:LogRoot -Force | Out-Null

if (-not $script:ServerRoot -and $env:SHARPPROSPERO_ROOT) {
    $script:ServerRoot = $env:SHARPPROSPERO_ROOT
}
if (-not $script:ServerRoot) {
    $script:ServerRoot = [System.IO.Path]::GetFullPath(
        (Join-Path $script:UiRoot "..\..\..\..\PS5-COMPILAR-HOMEBREW-main\PS5-COMPILAR-HOMEBREW-main")
    )
}

function Resolve-SdkRoot([string]$Path) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "No existe la carpeta del SDK indicada."
    }

    $resolved = (Resolve-Path -LiteralPath $Path).Path
    if (-not (Test-Path -LiteralPath (Join-Path $resolved "build\build-app.ps1") -PathType Leaf) -or
        -not (Test-Path -LiteralPath (Join-Path $resolved "samples") -PathType Container)) {
        throw "La carpeta debe ser la raiz de SharpProspero e incluir build\build-app.ps1 y samples."
    }
    return $resolved
}

function Resolve-ModulesPath([string]$Path) {
    if (-not $Path) { return "" }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "No existe la carpeta de modulos indicada."
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

function Test-PackageSupport([string]$Root) {
    if (-not $Root) { return $false }
    return [bool](
        (Test-Path -LiteralPath (Join-Path $Root "tools\SharpProspero.Packager\SharpProspero.Packager.csproj") -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $Root "tools\SharpProspero.Packager\LibProsperoPkg.dll") -PathType Leaf)
    )
}

function Get-AppProjects {
    if (-not (Test-Path -LiteralPath $script:ServerRoot -PathType Container)) { return @() }
    $samplesRoot = Join-Path $script:ServerRoot "samples"
    if (-not (Test-Path -LiteralPath $samplesRoot -PathType Container)) { return @() }

    $projects = @()
    foreach ($file in Get-ChildItem -LiteralPath $samplesRoot -Filter "*.csproj" -File -Recurse) {
        $contents = Get-Content -LiteralPath $file.FullName -Raw
        if ($contents -notmatch '(?is)<Import\b[^>]*Prospero\.App\.props' -or
            $contents -match '(?is)<ProsperoModuleKind>\s*Prx\s*</ProsperoModuleKind>') {
            continue
        }

        $relative = $file.FullName.Substring($samplesRoot.TrimEnd('\').Length).TrimStart('\')
        $id = $relative -replace '\\', '/'
        $name = [System.IO.Path]::GetFileName($file.DirectoryName)
        $projects += [pscustomobject]@{
            id = $id
            name = $name
        }
    }
    return @($projects | Sort-Object name)
}

function Get-UniqueTitleId([string]$ProjectPath) {
    $usedIds = @{}
    $metadataPaths = @()
    $samplesRoot = Join-Path $script:ServerRoot "samples"
    if (Test-Path -LiteralPath $samplesRoot -PathType Container) {
        $metadataPaths += @(Get-ChildItem -LiteralPath $samplesRoot -Filter "param.json" -File -Recurse |
            ForEach-Object { $_.FullName })
    }
    $projectDirectory = Split-Path -Parent $ProjectPath
    $metadataPaths += Join-Path $projectDirectory "sce_sys\param.json"
    $metadataPaths += Join-Path $projectDirectory "out\module\sce_sys\param.json"

    foreach ($metadataPath in ($metadataPaths | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) { continue }
        try {
            $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json -ErrorAction Stop
            $existingId = [string]$metadata.titleId
            if ($existingId -match '^[A-Z]{4}[0-9]{5}$') {
                $usedIds[$existingId] = $true
            }
        } catch {
            Write-Warning "No se pudo leer el Title ID de '$metadataPath': $($_.Exception.Message)"
        }
    }

    $stateRoot = Join-Path $env:LOCALAPPDATA "SharpProsperoStudio"
    New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
    $ledgerPath = Join-Path $stateRoot "generated-titleids.txt"
    $lockPath = Join-Path $stateRoot "generated-titleids.lock"
    $lockStream = $null
    $lockDeadline = [DateTime]::UtcNow.AddSeconds(10)
    while ($null -eq $lockStream) {
        try {
            $lockStream = [System.IO.File]::Open(
                $lockPath,
                [System.IO.FileMode]::OpenOrCreate,
                [System.IO.FileAccess]::ReadWrite,
                [System.IO.FileShare]::None
            )
        } catch [System.IO.IOException] {
            if ([DateTime]::UtcNow -ge $lockDeadline) {
                throw "No se pudo reservar el registro de Title IDs; otra compilacion podria estar actualizandolo."
            }
            Start-Sleep -Milliseconds 100
        }
    }

    try {
        if (Test-Path -LiteralPath $ledgerPath -PathType Leaf) {
            foreach ($recordedId in [System.IO.File]::ReadAllLines($ledgerPath)) {
                if (-not $recordedId) { continue }
                if ($recordedId -notmatch '^[A-Z]{4}[0-9]{5}$') {
                    throw "El registro local de Title IDs contiene un valor no valido: '$recordedId'."
                }
                $usedIds[$recordedId] = $true
            }
        }

        $random = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        try {
            for ($attempt = 0; $attempt -lt 100000; $attempt++) {
                $bytes = New-Object byte[] 4
                $random.GetBytes($bytes)
                $number = [int]([System.BitConverter]::ToUInt32($bytes, 0) % 100000)
                $candidate = "PPSA{0:D5}" -f $number
                if ($usedIds.ContainsKey($candidate)) { continue }

                [System.IO.File]::AppendAllText(
                    $ledgerPath,
                    $candidate + [Environment]::NewLine,
                    (New-Object System.Text.UTF8Encoding($false))
                )
                return $candidate
            }
        } finally {
            $random.Dispose()
        }
        throw "No quedan Title IDs PPSA disponibles sin colision en el registro local."
    } finally {
        $lockStream.Dispose()
    }
}

function Get-ToolStatus {
    $dotnetCommand = Get-Command "dotnet.exe" -ErrorAction SilentlyContinue
    if (-not $dotnetCommand) { $dotnetCommand = Get-Command "dotnet" -ErrorAction SilentlyContinue }
    $dotnetVersion = ""
    if ($dotnetCommand) {
        try {
            $installedSdks = @(& $dotnetCommand.Source --list-sdks 2>$null)
            $net10Sdk = $installedSdks | Where-Object { $_ -match '^10\.\d' } | Select-Object -First 1
            if ($net10Sdk) {
                $dotnetVersion = "10.x instalado"
            } else {
                $dotnetVersion = "Requiere .NET 10"
            }
        } catch {
            $dotnetVersion = "No se pudo consultar"
        }
    }
    $wslCommand = Get-Command "wsl.exe" -ErrorAction SilentlyContinue
    $wslDotnet10 = $false
    if ($wslCommand) {
        try {
            $wslSdks = @(& $wslCommand.Source -e bash -lc "dotnet --list-sdks" 2>$null)
            $wslDotnet10 = [bool]($wslSdks | Where-Object { $_ -match '^10\.\d' } | Select-Object -First 1)
        } catch {
            $wslDotnet10 = $false
        }
    }
    return @{
        dotnet = @{ available = [bool]($dotnetCommand -and $dotnetVersion -eq "10.x instalado"); version = $dotnetVersion }
        wsl = @{ available = [bool]$wslCommand; dotnet10 = $wslDotnet10 }
    }
}

function Write-JsonResponse($Context, [int]$StatusCode, $Value) {
    $json = ConvertTo-Json -InputObject $Value -Depth 8 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $Context.Response.StatusCode = $StatusCode
    $Context.Response.ContentType = "application/json; charset=utf-8"
    $Context.Response.ContentLength64 = $bytes.Length
    $Context.Response.Headers["Cache-Control"] = "no-store"
    $Context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Context.Response.Close()
}

function Write-StaticResponse($Context, [string]$FileName) {
    $filePath = Join-Path $script:UiRoot $FileName
    if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
        Write-JsonResponse $Context 404 @{ error = "No se encontro el recurso solicitado." }
        return
    }
    $contentType = switch ([System.IO.Path]::GetExtension($filePath)) {
        ".html" { "text/html; charset=utf-8" }
        ".css" { "text/css; charset=utf-8" }
        ".js" { "application/javascript; charset=utf-8" }
        ".png" { "image/png" }
        default { "application/octet-stream" }
    }
    $bytes = [System.IO.File]::ReadAllBytes($filePath)
    $Context.Response.StatusCode = 200
    $Context.Response.ContentType = $contentType
    $Context.Response.ContentLength64 = $bytes.Length
    $Context.Response.Headers["Cache-Control"] = "no-store"
    $Context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Context.Response.Close()
}

function Read-RequestJson($Context) {
    if ($Context.Request.ContentLength64 -gt 32768) { throw "La solicitud supera el tamano permitido." }
    $reader = New-Object System.IO.StreamReader($Context.Request.InputStream, $Context.Request.ContentEncoding)
    try { return ($reader.ReadToEnd() | ConvertFrom-Json) }
    finally { $reader.Dispose() }
}

function Quote-ProcessArgument([string]$Value) {
    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('"')
    $slashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq [char]92) {
            $slashes++
            continue
        }
        if ($character -eq [char]34) {
            if ($slashes -gt 0) { [void]$builder.Append([char]92, ($slashes * 2)) }
            [void]$builder.Append([char]92)
            [void]$builder.Append([char]34)
        } else {
            if ($slashes -gt 0) { [void]$builder.Append([char]92, $slashes) }
            [void]$builder.Append($character)
        }
        $slashes = 0
    }
    if ($slashes -gt 0) { [void]$builder.Append([char]92, ($slashes * 2)) }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function Get-JobLogs($Job) {
    $lines = @()
    foreach ($path in @($Job.stdoutPath, $Job.stderrPath)) {
        if (Test-Path -LiteralPath $path) {
            $stream = [System.IO.File]::Open(
                $path,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::Read,
                [System.IO.FileShare]::ReadWrite
            )
            try {
                $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8, $true)
                try {
                    $text = $reader.ReadToEnd()
                    if ($text) { $lines += @($text -split "`r?`n" | Where-Object { $_ -ne "" }) }
                } finally {
                    $reader.Dispose()
                }
            } finally {
                $stream.Dispose()
            }
        }
    }
    if ($lines.Count -gt 800) { $lines = @($lines | Select-Object -Last 800) }
    return $lines
}

function Update-JobState($Job) {
    if ($Job.state -ne "running") { return }
    $Job.process.Refresh()
    if (-not $Job.process.HasExited) { return }
    $Job.process.WaitForExit()
    if (Test-Path -LiteralPath $Job.exitCodePath) {
        $exitCodeText = [System.IO.File]::ReadAllText($Job.exitCodePath).Trim()
        $parsedExitCode = 0
        if ([int]::TryParse($exitCodeText, [ref]$parsedExitCode)) {
            $Job.exitCode = $parsedExitCode
        }
    } elseif ($null -ne $Job.process.ExitCode) {
        $Job.exitCode = $Job.process.ExitCode
    }
    if ($null -eq $Job.exitCode) { $Job.exitCode = 1 }
    $Job.state = if ($Job.exitCode -eq 0) { "succeeded" } else { "failed" }
    $Job.detail = if ($Job.exitCode -eq 0) { "Compilacion completada." } else { "El proceso termino con codigo $($Job.exitCode)." }
}

function Start-Build($Context) {
    if (-not $script:ServerRoot) { throw "Configura primero la ruta del SDK SharpProspero." }
    $script:ServerRoot = Resolve-SdkRoot $script:ServerRoot
    $tools = Get-ToolStatus
    if (-not $tools.dotnet.available) { throw "Instala .NET 10 en Windows antes de compilar." }
    if (-not $tools.wsl.available) { throw "Instala WSL2 antes de compilar en Windows." }
    if (-not $tools.wsl.dotnet10) { throw "Instala .NET 10 dentro de tu distribucion WSL antes de compilar." }
    $request = Read-RequestJson $Context
    $projectId = [string]$request.project
    $customProjectPath = [string]$request.projectPath
    $output = [string]$request.output
    if ($output -notin @("Package", "Folder")) { throw "El formato debe ser Package o Folder." }
    if ($output -eq "Package" -and -not $script:PackageSupported) {
        throw "Esta distribucion solo incluye salida de carpeta. No redistribuye el empaquetador .pkg."
    }

    if ($customProjectPath.Trim()) {
        if (-not [System.IO.Path]::IsPathRooted($customProjectPath) -or $customProjectPath.StartsWith("\\")) {
            throw "Indica la ruta local completa a un archivo .csproj."
        }
        $projectPath = [System.IO.Path]::GetFullPath($customProjectPath)
        if ([System.IO.Path]::GetExtension($projectPath) -ne ".csproj" -or
            -not (Test-Path -LiteralPath $projectPath -PathType Leaf)) {
            throw "No se encontro el archivo .csproj indicado."
        }
        $projectContents = Get-Content -LiteralPath $projectPath -Raw
        if ($projectContents -notmatch '(?is)<Import\b[^>]*Prospero\.App\.props' -or
            $projectContents -match '(?is)Prospero\.Payload\.props|<ProsperoModuleKind>\s*Prx\s*</ProsperoModuleKind>') {
            throw "El proyecto debe ser una aplicacion SharpProspero; los payloads y las bibliotecas PRX no se compilan desde esta interfaz."
        }
        $project = [pscustomobject]@{ name = [System.IO.Path]::GetFileName((Split-Path -Parent $projectPath)) }
    } else {
        $project = Get-AppProjects | Where-Object { $_.id -eq $projectId } | Select-Object -First 1
        if (-not $project) { throw "Selecciona un proyecto de aplicacion valido de la lista del SDK." }

        $samplesRoot = Join-Path $script:ServerRoot "samples"
        $projectPath = [System.IO.Path]::GetFullPath((Join-Path $samplesRoot ($project.id -replace '/', '\')))
        $projectPrefix = [System.IO.Path]::GetFullPath($samplesRoot).TrimEnd('\') + '\'
        if (-not $projectPath.StartsWith($projectPrefix, [System.StringComparison]::OrdinalIgnoreCase) -or
            -not (Test-Path -LiteralPath $projectPath -PathType Leaf)) {
            throw "La ruta del proyecto no pertenece a samples del SDK."
        }
    }

    $titleId = ""
    $projectMetadata = Join-Path (Split-Path -Parent $projectPath) "sce_sys\param.json"
    if (Test-Path -LiteralPath $projectMetadata -PathType Leaf) {
        $titleId = Get-UniqueTitleId $projectPath
    }

    $id = [guid]::NewGuid().ToString("N")
    $stdoutPath = Join-Path $script:LogRoot "$id.out.log"
    $stderrPath = Join-Path $script:LogRoot "$id.err.log"
    $runnerScript = Join-Path $script:UiRoot "run-build.ps1"
    $exitCodePath = Join-Path $script:LogRoot "$id.exit"
    $arguments = @(
        "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $runnerScript,
        "-ProjectPath", $projectPath, "-Output", $output, "-SdkRoot", $script:ServerRoot,
        "-ExitCodePath", $exitCodePath, "-TitleId", $titleId
    ) | ForEach-Object { Quote-ProcessArgument ([string]$_) }
    if ($script:ModulesRoot) {
        $arguments += Quote-ProcessArgument "-ModulesPath"
        $arguments += Quote-ProcessArgument $script:ModulesRoot
    }

    $process = Start-Process -FilePath $script:PowerShellExe `
        -ArgumentList ($arguments -join " ") `
        -WorkingDirectory (Split-Path -Parent $projectPath) `
        -WindowStyle Hidden `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath `
        -PassThru

    $outputPath = Join-Path (Split-Path -Parent $projectPath) "out"
    if ($output -eq "Folder") { $outputPath = Join-Path $outputPath "module" }
    $script:Jobs[$id] = [pscustomobject]@{
        id = $id
        project = $project.name
        titleId = $titleId
        outputPath = $outputPath
        stdoutPath = $stdoutPath
        stderrPath = $stderrPath
        exitCodePath = $exitCodePath
        process = $process
        state = "running"
        exitCode = $null
        detail = "Compilacion en curso."
    }
    Write-JsonResponse $Context 202 @{ id = $id; state = "running"; titleId = $titleId }
}

function Handle-Request($Context) {
    $request = $Context.Request
    if ($request.Headers["Origin"] -and $request.Headers["Origin"] -ne $script:Origin) {
        Write-JsonResponse $Context 403 @{ error = "Origen no permitido." }
        return
    }
    if ($request.Headers["Host"] -ne "127.0.0.1:$Port") {
        Write-JsonResponse $Context 403 @{ error = "Host no permitido." }
        return
    }

    $path = $request.Url.AbsolutePath
    $method = $request.HttpMethod
    if ($method -eq "POST" -and $path -eq "/api/shutdown") {
        if (-not $script:ShutdownToken -or
            $request.Headers["X-SharpProspero-Shutdown"] -ne $script:ShutdownToken) {
            Write-JsonResponse $Context 403 @{ error = "Solicitud de cierre no autorizada." }
            return
        }
        foreach ($job in $script:Jobs.Values) { Update-JobState $job }
        if (@($script:Jobs.Values | Where-Object { $_.state -eq "running" }).Count -gt 0) {
            Write-JsonResponse $Context 409 @{ error = "Espera a que termine la compilacion antes de cerrar Studio." }
            return
        }
        Write-JsonResponse $Context 200 @{ stopped = $true }
        $script:ShutdownRequested = $true
        return
    }
    if ($method -eq "GET" -and $path -eq "/") {
        Write-StaticResponse $Context "index.html"
        return
    }
    if ($method -eq "GET" -and $path -in @("/style.css", "/demo.js", "/Yo-Removebg.png")) {
        Write-StaticResponse $Context $path.TrimStart('/')
        return
    }
    if ($method -eq "GET" -and $path -eq "/api/status") {
        $tools = Get-ToolStatus
        $validSdk = $false
        if ($script:ServerRoot) {
            try { $script:ServerRoot = Resolve-SdkRoot $script:ServerRoot; $validSdk = $true }
            catch { $validSdk = $false }
        }
        Write-JsonResponse $Context 200 @{
            sdkRoot = $script:ServerRoot
            validSdk = $validSdk
            modulesPath = $script:ModulesRoot
            modulesReady = [bool]($script:ModulesRoot -and (Test-Path -LiteralPath (Join-Path $script:ModulesRoot "libc.prx") -PathType Leaf))
            packageSupported = $script:PackageSupported
            dotnet = $tools.dotnet
            wsl = $tools.wsl
        }
        return
    }
    if ($method -eq "GET" -and $path -eq "/api/projects") {
        Write-JsonResponse $Context 200 @{ projects = @(Get-AppProjects) }
        return
    }
    if ($method -eq "POST" -and $path -eq "/api/config") {
        $body = Read-RequestJson $Context
        $serverRoot = Resolve-SdkRoot ([string]$body.sdkRoot)
        $modulesRoot = Resolve-ModulesPath ([string]$body.modulesPath)
        $script:ServerRoot = $serverRoot
        $script:ModulesRoot = $modulesRoot
        $script:PackageSupported = Test-PackageSupport $serverRoot
        Write-JsonResponse $Context 200 @{ sdkRoot = $script:ServerRoot; modulesPath = $script:ModulesRoot }
        return
    }
    if ($method -eq "POST" -and $path -eq "/api/build") {
        if (@($script:Jobs.Values | Where-Object { $_.state -eq "running" }).Count -gt 0) {
            Write-JsonResponse $Context 409 @{ error = "Ya hay una compilacion en curso." }
            return
        }
        Start-Build $Context
        return
    }
    if ($method -eq "GET" -and $path -match '^/api/jobs/([a-f0-9]{32})$') {
        $id = $Matches[1]
        if (-not $script:Jobs.ContainsKey($id)) {
            Write-JsonResponse $Context 404 @{ error = "No se encontro esa compilacion." }
            return
        }
        $job = $script:Jobs[$id]
        Update-JobState $job
        Write-JsonResponse $Context 200 @{
            id = $job.id
            project = $job.project
            titleId = $job.titleId
            state = $job.state
            exitCode = $job.exitCode
            detail = $job.detail
            outputPath = $job.outputPath
            logs = @(Get-JobLogs $job)
        }
        return
    }
    Write-JsonResponse $Context 404 @{ error = "Ruta no encontrada." }
}

if ($script:ServerRoot -and (Test-Path -LiteralPath $script:ServerRoot -PathType Container)) {
    try { $script:ServerRoot = Resolve-SdkRoot $script:ServerRoot }
    catch { Write-Warning $_.Exception.Message }
}
if ($script:ModulesRoot) {
    try { $script:ModulesRoot = Resolve-ModulesPath $script:ModulesRoot }
    catch { Write-Warning $_.Exception.Message; $script:ModulesRoot = "" }
}
$script:PackageSupported = Test-PackageSupport $script:ServerRoot

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($script:Prefix)
try {
    $listener.Start()
} catch {
    Write-Error "No se pudo iniciar el servicio local en $($script:Prefix). $($_.Exception.Message)"
    exit 1
}

Write-Host "SharpProspero Studio: $($script:Origin)"
Write-Host "SDK: $script:ServerRoot"
Start-Process $script:Origin

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        try {
            Handle-Request $context
            if ($script:ShutdownRequested) { break }
        } catch {
            Write-Warning $_.Exception.Message
            try {
                if ($context.Response.OutputStream.CanWrite) {
                    Write-JsonResponse $context 400 @{ error = $_.Exception.Message }
                }
            } catch {
                $context.Response.Abort()
            }
        }
    }
} finally {
    $listener.Stop()
    $listener.Close()
    foreach ($job in $script:Jobs.Values) {
        if (-not $job.process.HasExited) { $job.process.Kill() }
        $job.process.Dispose()
    }
}
