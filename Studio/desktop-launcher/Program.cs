using System.Diagnostics;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Sockets;
using System.Reflection;
using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Windows.Forms;

namespace SharpProsperoStudio.Desktop;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        using var mutex = new Mutex(true, @"Local\SharpProsperoStudio.Desktop", out bool isFirstInstance);
        if (!isFirstInstance)
        {
            MessageBox.Show(
                "SharpProspero Studio ya está abierto.",
                "SharpProspero Studio",
                MessageBoxButtons.OK,
                MessageBoxIcon.Information);
            return;
        }

        ApplicationConfiguration.Initialize();
        Application.Run(new LauncherForm());
    }
}

internal sealed class LauncherForm : Form
{
    private const int PreferredPort = 8766;
    private const string ResourcePrefix = "SharpProsperoStudio.Assets.";
    private readonly string _dataRoot = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "SharpProsperoStudio");
    private readonly string _appRoot;
    private readonly string _settingsPath;
    private readonly string _shutdownToken = Convert.ToHexString(RandomNumberGenerator.GetBytes(32));
    private readonly HttpClient _httpClient = new() { Timeout = TimeSpan.FromSeconds(2) };
    private readonly Label _stateLabel = new();
    private readonly Label _requirementsLabel = new();
    private readonly TextBox _sdkRootTextBox = new();
    private readonly TextBox _moduleFolderTextBox = new();
    private readonly Button _openButton = new();
    private readonly Button _applySdkButton = new();
    private readonly Button _openSourcesButton = new();
    private readonly System.Windows.Forms.Timer _healthTimer = new() { Interval = 800 };
    private readonly object _logLock = new();
    private Process? _serverProcess;
    private StreamWriter? _serverLog;
    private Uri? _studioUri;
    private string? _sdkRoot;
    private string? _bundledSdkRoot;
    private bool _browserOpened;
    private bool _isClosing;
    private bool _allowClose;
    private int _port;

    public LauncherForm()
    {
        _appRoot = Path.Combine(_dataRoot, "app");
        _settingsPath = Path.Combine(_dataRoot, "settings.json");
        Text = "SharpProspero Studio";
        StartPosition = FormStartPosition.CenterScreen;
        ClientSize = new Size(680, 430);
        MinimumSize = new Size(680, 430);
        MaximumSize = new Size(680, 430);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        ShowInTaskbar = true;
        Font = new Font("Segoe UI", 9F);

        BuildLayout();
        LoadSdkSetting();
        _healthTimer.Tick += async (_, _) => await CheckServerAsync();
        Shown += async (_, _) => await StartServerAsync();
        FormClosing += OnFormClosing;
    }

    private void BuildLayout()
    {
        var title = new Label
        {
            Text = "SharpProspero Studio",
            Font = new Font("Segoe UI Semibold", 18F, FontStyle.Bold),
            AutoSize = true,
            Location = new Point(24, 22)
        };
        var subtitle = new Label
        {
            Text = "Compilador local de aplicaciones homebrew",
            ForeColor = Color.DimGray,
            AutoSize = true,
            Location = new Point(27, 60)
        };
        _stateLabel.Text = "Iniciando el servicio local…";
        _stateLabel.AutoSize = false;
        _stateLabel.Location = new Point(27, 102);
        _stateLabel.Size = new Size(560, 24);
        _stateLabel.Font = new Font("Segoe UI Semibold", 10F, FontStyle.Bold);

        var sdkLabel = new Label
        {
            Text = "Raíz del SDK (contiene build\\build-app.ps1)",
            AutoSize = true,
            Location = new Point(27, 145)
        };
        _sdkRootTextBox.Location = new Point(27, 171);
        _sdkRootTextBox.Size = new Size(492, 27);
        _sdkRootTextBox.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;

        var browseButton = new Button
        {
            Text = "Buscar…",
            Location = new Point(532, 169),
            Size = new Size(120, 30),
            Anchor = AnchorStyles.Top | AnchorStyles.Right
        };
        browseButton.Click += (_, _) => BrowseSdkRoot();
        _sdkRootTextBox.TextChanged += (_, _) => _applySdkButton.Enabled = true;

        var moduleLabel = new Label
        {
            Text = "Carpeta que contiene libc.prx (el archivo va directamente dentro)",
            AutoSize = true,
            Location = new Point(27, 207)
        };
        _moduleFolderTextBox.Location = new Point(27, 233);
        _moduleFolderTextBox.Size = new Size(492, 27);
        _moduleFolderTextBox.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
        _moduleFolderTextBox.TextChanged += (_, _) => _applySdkButton.Enabled = true;

        var browseModulesButton = new Button
        {
            Text = "Buscar…",
            Location = new Point(532, 231),
            Size = new Size(120, 30),
            Anchor = AnchorStyles.Top | AnchorStyles.Right
        };
        browseModulesButton.Click += (_, _) => BrowseModuleFolder();

        _applySdkButton.Text = "Aplicar carpeta";
        _applySdkButton.Location = new Point(532, 289);
        _applySdkButton.Size = new Size(120, 30);
        _applySdkButton.Anchor = AnchorStyles.Top | AnchorStyles.Right;
        _applySdkButton.Enabled = false;
        _applySdkButton.Click += async (_, _) => await ApplySdkRootAsync();

        _requirementsLabel.Text = "Comprobando requisitos…";
        _requirementsLabel.AutoSize = false;
        _requirementsLabel.Location = new Point(27, 282);
        _requirementsLabel.Size = new Size(492, 50);
        _requirementsLabel.ForeColor = Color.DimGray;

        _openSourcesButton.Text = "Carpeta del compilador";
        _openSourcesButton.Location = new Point(27, 370);
        _openSourcesButton.Size = new Size(170, 36);
        _openSourcesButton.Enabled = false;
        _openSourcesButton.Click += (_, _) => OpenCompilerFolder();

        var prerequisitesButton = new Button
        {
            Text = "Requisitos",
            Location = new Point(208, 370),
            Size = new Size(105, 36)
        };
        prerequisitesButton.Click += (_, _) => ShowRequirements();

        _openButton.Text = "Abrir Studio";
        _openButton.Location = new Point(326, 370);
        _openButton.Size = new Size(140, 36);
        _openButton.Enabled = false;
        _openButton.Click += (_, _) => OpenStudio();

        var closeButton = new Button
        {
            Text = "Cerrar Studio",
            Location = new Point(512, 370),
            Size = new Size(140, 36),
            Anchor = AnchorStyles.Bottom | AnchorStyles.Right
        };
        closeButton.Click += async (_, _) => await CloseStudioAsync();

        Controls.AddRange([
            title, subtitle, _stateLabel, sdkLabel, _sdkRootTextBox, browseButton,
            moduleLabel, _moduleFolderTextBox, browseModulesButton,
            _applySdkButton, _requirementsLabel, _openSourcesButton, prerequisitesButton,
            _openButton, closeButton
        ]);
    }

    private void LoadSdkSetting()
    {
        try
        {
            if (File.Exists(_settingsPath))
            {
                using JsonDocument document = JsonDocument.Parse(File.ReadAllText(_settingsPath));
                if (document.RootElement.TryGetProperty("sdkRoot", out JsonElement value))
                    _sdkRootTextBox.Text = value.GetString() ?? string.Empty;
                if (document.RootElement.TryGetProperty("modulesPath", out JsonElement modules))
                    _moduleFolderTextBox.Text = modules.GetString() ?? string.Empty;
            }
        }
        catch (JsonException exception)
        {
            MessageBox.Show(
                $"No se pudo leer la configuración guardada:\n{exception.Message}",
                "Configuración",
                MessageBoxButtons.OK,
                MessageBoxIcon.Warning);
        }

        if (string.IsNullOrWhiteSpace(_sdkRootTextBox.Text))
            _sdkRootTextBox.Text = FindSdkRoot() ?? string.Empty;
        _sdkRoot = ValidateSdkRoot(_sdkRootTextBox.Text) ? Path.GetFullPath(_sdkRootTextBox.Text) : null;
        if (string.IsNullOrWhiteSpace(_moduleFolderTextBox.Text) && _sdkRoot is not null)
        {
            string defaultModules = Path.Combine(_sdkRoot, "target", "sce_module");
            if (Directory.Exists(defaultModules))
                _moduleFolderTextBox.Text = defaultModules;
        }
    }

    private static string? FindSdkRoot()
    {
        string? configured = Environment.GetEnvironmentVariable("SHARPPROSPERO_ROOT");
        if (ValidateSdkRoot(configured))
            return Path.GetFullPath(configured!);

        string bundled = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "SharpProsperoStudio",
            "toolchains");
        if (Directory.Exists(bundled))
        {
            foreach (string candidate in Directory.GetDirectories(bundled))
                if (ValidateSdkRoot(candidate))
                    return candidate;
        }

        DirectoryInfo? directory = new(AppContext.BaseDirectory);
        while (directory is not null)
        {
            if (ValidateSdkRoot(directory.FullName))
                return directory.FullName;

            string sibling = Path.Combine(
                directory.FullName,
                "PS5-COMPILAR-HOMEBREW-main",
                "PS5-COMPILAR-HOMEBREW-main");
            if (ValidateSdkRoot(sibling))
                return sibling;

            directory = directory.Parent;
        }
        return null;
    }

    private static bool ValidateSdkRoot(string? path) =>
        !string.IsNullOrWhiteSpace(path) &&
        Directory.Exists(path) &&
        File.Exists(Path.Combine(path, "build", "build-app.ps1")) &&
        Directory.Exists(Path.Combine(path, "samples"));

    private static bool SupportsTemplateContentIds(string? path)
    {
        string buildScript = string.IsNullOrWhiteSpace(path)
            ? string.Empty
            : Path.Combine(path, "build", "build-app.ps1");
        if (!File.Exists(buildScript)) return false;

        string script = File.ReadAllText(buildScript);
        return script.Contains("APP_CONTENTID", StringComparison.Ordinal) &&
               script.Contains("HOMEBREW00000001", StringComparison.Ordinal);
    }

    private void BrowseSdkRoot()
    {
        using var dialog = new FolderBrowserDialog
        {
            Description = "Selecciona la carpeta raíz del checkout de SharpProspero.",
            UseDescriptionForTitle = true,
            InitialDirectory = Directory.Exists(_sdkRootTextBox.Text)
                ? _sdkRootTextBox.Text
                : Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)
        };
        if (dialog.ShowDialog(this) == DialogResult.OK)
            _sdkRootTextBox.Text = dialog.SelectedPath;
    }

    private void BrowseModuleFolder()
    {
        using var dialog = new FolderBrowserDialog
        {
            Description = "Selecciona la carpeta que contiene libc.prx y los módulos compatibles.",
            UseDescriptionForTitle = true,
            InitialDirectory = Directory.Exists(_moduleFolderTextBox.Text)
                ? _moduleFolderTextBox.Text
                : Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)
        };
        if (dialog.ShowDialog(this) == DialogResult.OK)
            _moduleFolderTextBox.Text = dialog.SelectedPath;
    }

    private async Task ApplySdkRootAsync()
    {
        string path = _sdkRootTextBox.Text.Trim();
        if (!ValidateSdkRoot(path))
        {
            MessageBox.Show(
                "La carpeta debe contener build\\build-app.ps1 y samples.",
                "Ruta de SharpProspero no válida",
                MessageBoxButtons.OK,
                MessageBoxIcon.Warning);
            return;
        }

        string modulesPath = _moduleFolderTextBox.Text.Trim();
        if (modulesPath.Length > 0 && !Directory.Exists(modulesPath))
        {
            MessageBox.Show(
                "La carpeta de módulos indicada no existe. Déjala vacía si todavía no tienes módulos redistribuibles.",
                "Carpeta de módulos no válida",
                MessageBoxButtons.OK,
                MessageBoxIcon.Warning);
            return;
        }

        _sdkRoot = Path.GetFullPath(path);
        _sdkRootTextBox.Text = _sdkRoot;
        if (modulesPath.Length > 0)
            _moduleFolderTextBox.Text = Path.GetFullPath(modulesPath);
        SaveSettings();
        _applySdkButton.Enabled = false;

        if (_studioUri is not null)
        {
            using var content = new StringContent(
                JsonSerializer.Serialize(new
                {
                    sdkRoot = _sdkRoot,
                    modulesPath = _moduleFolderTextBox.Text.Trim()
                }),
                Encoding.UTF8,
                "application/json");
            try
            {
                using HttpResponseMessage response = await _httpClient.PostAsync(
                    new Uri(_studioUri, "/api/config"), content);
                if (!response.IsSuccessStatusCode)
                    throw new HttpRequestException($"El servicio respondió HTTP {(int)response.StatusCode}.");
            }
            catch (HttpRequestException exception)
            {
                _applySdkButton.Enabled = true;
                MessageBox.Show(
                    $"No se pudo aplicar la carpeta al servicio:\n{exception.Message}",
                    "SharpProspero Studio",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
                return;
            }
        }
        _stateLabel.Text = "Ruta del SDK guardada.";
    }

    private async Task StartServerAsync()
    {
        try
        {
            ExtractAssets();
            _bundledSdkRoot = ExtractCompilerBundle();
            string? privateModulesRoot = ExtractPrivateModules();
            if (privateModulesRoot is not null &&
                !File.Exists(Path.Combine(_moduleFolderTextBox.Text.Trim(), "libc.prx")))
            {
                _moduleFolderTextBox.Text = privateModulesRoot;
                SaveSettings();
            }
            string bundledRootPrefix = Path.GetFullPath(
                Path.Combine(_dataRoot, "toolchains")) + Path.DirectorySeparatorChar;
            bool selectedBundledSdk = _sdkRoot is null ||
                _sdkRoot.StartsWith(bundledRootPrefix, StringComparison.OrdinalIgnoreCase);
            bool selectedSdkSupportsTemplateIds = SupportsTemplateContentIds(_sdkRoot);
            if ((selectedBundledSdk || !selectedSdkSupportsTemplateIds) &&
                ValidateSdkRoot(_bundledSdkRoot))
            {
                _sdkRoot = _bundledSdkRoot;
                _sdkRootTextBox.Text = _bundledSdkRoot;
                SaveSettings();
            }
            _port = FindAvailablePort();
            _studioUri = new Uri($"http://127.0.0.1:{_port}/");
            _serverProcess = StartPowerShellServer();
            _healthTimer.Start();
            await CheckServerAsync();
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or InvalidOperationException)
        {
            _stateLabel.Text = "No se pudo iniciar el servicio.";
            MessageBox.Show(
                $"SharpProspero Studio no pudo iniciarse:\n{exception.Message}",
                "Error al iniciar",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
        }
    }

    private void ExtractAssets()
    {
        Directory.CreateDirectory(_appRoot);
        string[] names = ["index.html", "style.css", "demo.js", "server.ps1", "run-build.ps1", "Yo-Removebg.png"];
        Assembly assembly = Assembly.GetExecutingAssembly();
        foreach (string name in names)
        {
            string resourceName = ResourcePrefix + name;
            using Stream resource = assembly.GetManifestResourceStream(resourceName)
                ?? throw new InvalidOperationException($"No se encontró el recurso integrado {resourceName}.");
            string destination = Path.Combine(_appRoot, name);
            using var output = new FileStream(destination, FileMode.Create, FileAccess.Write, FileShare.None);
            resource.CopyTo(output);
        }
    }

    private string ExtractCompilerBundle()
    {
        using Stream resource = Assembly.GetExecutingAssembly().GetManifestResourceStream(
            ResourcePrefix + "compiler-toolchain.zip")
            ?? throw new InvalidOperationException("No se encontró el código fuente del compilador integrado.");
        using var buffer = new MemoryStream();
        resource.CopyTo(buffer);
        byte[] archiveBytes = buffer.ToArray();
        string fingerprint = Convert.ToHexString(SHA256.HashData(archiveBytes));
        string destinationRoot = Path.Combine(_dataRoot, "toolchains", fingerprint);
        string completionMarker = Path.Combine(destinationRoot, ".bundle-complete");
        if (File.Exists(completionMarker))
            return destinationRoot;

        Directory.CreateDirectory(destinationRoot);
        string fullRoot = Path.GetFullPath(destinationRoot) + Path.DirectorySeparatorChar;
        using var archiveStream = new MemoryStream(archiveBytes, writable: false);
        using var archive = new ZipArchive(archiveStream, ZipArchiveMode.Read);
        foreach (ZipArchiveEntry entry in archive.Entries)
        {
            string relativePath = entry.FullName.Replace('/', Path.DirectorySeparatorChar);
            if (Path.IsPathRooted(relativePath) ||
                relativePath.Split(Path.DirectorySeparatorChar).Any(part => part is "." or ".."))
                throw new InvalidOperationException("El archivo de fuentes integrado contiene una ruta no segura.");

            string destination = Path.GetFullPath(Path.Combine(destinationRoot, relativePath));
            if (!destination.StartsWith(fullRoot, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Una ruta del archivo de fuentes sale de su carpeta de instalación.");
            if (entry.FullName.EndsWith("/", StringComparison.Ordinal))
            {
                Directory.CreateDirectory(destination);
                continue;
            }

            Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
            using Stream input = entry.Open();
            using var output = new FileStream(destination, FileMode.Create, FileAccess.Write, FileShare.None);
            input.CopyTo(output);
        }

        File.WriteAllText(completionMarker, fingerprint, new UTF8Encoding(false));
        return destinationRoot;
    }

    private string? ExtractPrivateModules()
    {
        using Stream? resource = Assembly.GetExecutingAssembly().GetManifestResourceStream(
            ResourcePrefix + "private-modules.zip");
        if (resource is null) return null;

        using var buffer = new MemoryStream();
        resource.CopyTo(buffer);
        byte[] archiveBytes = buffer.ToArray();
        string fingerprint = Convert.ToHexString(SHA256.HashData(archiveBytes));
        string destinationRoot = Path.Combine(_dataRoot, "private-modules", fingerprint);
        string completionMarker = Path.Combine(destinationRoot, ".bundle-complete");
        if (File.Exists(completionMarker) &&
            File.Exists(Path.Combine(destinationRoot, "libc.prx")))
            return destinationRoot;

        Directory.CreateDirectory(destinationRoot);
        string fullRoot = Path.GetFullPath(destinationRoot) + Path.DirectorySeparatorChar;
        using var archiveStream = new MemoryStream(archiveBytes, writable: false);
        using var archive = new ZipArchive(archiveStream, ZipArchiveMode.Read);
        foreach (ZipArchiveEntry entry in archive.Entries)
        {
            string relativePath = entry.FullName.Replace('/', Path.DirectorySeparatorChar);
            if (Path.IsPathRooted(relativePath) ||
                relativePath.Split(Path.DirectorySeparatorChar).Any(part => part is "." or ".."))
                throw new InvalidOperationException("El archivo de módulos integrado contiene una ruta no segura.");

            string destination = Path.GetFullPath(Path.Combine(destinationRoot, relativePath));
            if (!destination.StartsWith(fullRoot, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Una ruta del archivo de módulos sale de su carpeta de instalación.");
            Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
            using Stream input = entry.Open();
            using var output = new FileStream(destination, FileMode.Create, FileAccess.Write, FileShare.None);
            input.CopyTo(output);
        }

        if (!File.Exists(Path.Combine(destinationRoot, "libc.prx")))
            throw new InvalidOperationException("El archivo de módulos integrado no contiene libc.prx.");
        File.WriteAllText(completionMarker, fingerprint, new UTF8Encoding(false));
        return destinationRoot;
    }

    private Process StartPowerShellServer()
    {
        string windowsDirectory = Environment.GetFolderPath(Environment.SpecialFolder.System);
        string powershell = Path.Combine(windowsDirectory, "WindowsPowerShell", "v1.0", "powershell.exe");
        string serverScript = Path.Combine(_appRoot, "server.ps1");
        if (!File.Exists(powershell) || !File.Exists(serverScript))
            throw new FileNotFoundException("No se encontró Windows PowerShell o el servidor integrado.");

        Directory.CreateDirectory(_dataRoot);
        var log = new StreamWriter(
            new FileStream(Path.Combine(_dataRoot, "server.log"), FileMode.Append, FileAccess.Write, FileShare.Read),
            new UTF8Encoding(false)) { AutoFlush = true };
        _serverLog = log;

        var startInfo = new ProcessStartInfo
        {
            FileName = powershell,
            WorkingDirectory = _appRoot,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        };
        startInfo.ArgumentList.Add("-NoProfile");
        startInfo.ArgumentList.Add("-ExecutionPolicy");
        startInfo.ArgumentList.Add("Bypass");
        startInfo.ArgumentList.Add("-File");
        startInfo.ArgumentList.Add(serverScript);
        startInfo.ArgumentList.Add("-Port");
        startInfo.ArgumentList.Add(_port.ToString());
        startInfo.ArgumentList.Add("-SdkRoot");
        startInfo.ArgumentList.Add(_sdkRoot ?? _bundledSdkRoot ?? string.Empty);
        startInfo.ArgumentList.Add("-ModulesPath");
        startInfo.ArgumentList.Add(_moduleFolderTextBox.Text.Trim());
        startInfo.Environment["SHARP_PROSPERO_STUDIO_SHUTDOWN_TOKEN"] = _shutdownToken;

        var process = new Process { StartInfo = startInfo, EnableRaisingEvents = true };
        process.OutputDataReceived += (_, eventArgs) => WriteServerLog(eventArgs.Data);
        process.ErrorDataReceived += (_, eventArgs) => WriteServerLog(eventArgs.Data);
        process.Exited += (_, _) =>
        {
            if (IsDisposed || _isClosing) return;
            BeginInvoke(() =>
            {
                if (_isClosing) return;
                _healthTimer.Stop();
                _openButton.Enabled = false;
                _stateLabel.Text = $"El servicio se cerró (código {process.ExitCode}).";
            });
        };
        if (!process.Start())
            throw new InvalidOperationException("Windows PowerShell no pudo iniciarse.");
        process.BeginOutputReadLine();
        process.BeginErrorReadLine();
        return process;
    }

    private void WriteServerLog(string? line)
    {
        if (string.IsNullOrEmpty(line) || _serverLog is null) return;
        try
        {
            lock (_logLock)
                _serverLog.WriteLine(line);
        }
        catch (ObjectDisposedException)
        {
        }
        catch (IOException)
        {
        }
    }

    private static int FindAvailablePort()
    {
        try
        {
            using var preferred = new TcpListener(IPAddress.Loopback, PreferredPort);
            preferred.Start();
            preferred.Stop();
            return PreferredPort;
        }
        catch (SocketException)
        {
            using var listener = new TcpListener(IPAddress.Loopback, 0);
            listener.Start();
            int port = ((IPEndPoint)listener.LocalEndpoint).Port;
            listener.Stop();
            return port;
        }
    }

    private async Task CheckServerAsync()
    {
        if (_studioUri is null || _isClosing) return;
        if (_serverProcess?.HasExited == true)
        {
            _healthTimer.Stop();
            _stateLabel.Text = $"El servicio se cerró (código {_serverProcess.ExitCode}).";
            return;
        }

        try
        {
            using HttpResponseMessage response = await _httpClient.GetAsync(new Uri(_studioUri, "/api/status"));
            response.EnsureSuccessStatusCode();
            using JsonDocument status = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
            JsonElement root = status.RootElement;
            bool sdkReady = root.GetProperty("validSdk").GetBoolean();
            bool windowsDotnet = root.GetProperty("dotnet").GetProperty("available").GetBoolean();
            bool wslReady = root.GetProperty("wsl").GetProperty("available").GetBoolean() &&
                            root.GetProperty("wsl").GetProperty("dotnet10").GetBoolean();

            _stateLabel.Text = sdkReady
                ? $"Studio activo en 127.0.0.1:{_port}"
                : $"Servicio activo en 127.0.0.1:{_port}; configura la carpeta del SDK.";
            bool modulesReady = root.TryGetProperty("modulesReady", out JsonElement modulesValue) &&
                                modulesValue.GetBoolean();
            bool packageReady = root.TryGetProperty("packageSupported", out JsonElement packageValue) &&
                                packageValue.GetBoolean();
            _requirementsLabel.Text = $"SDK: {(sdkReady ? "listo" : "falta")} · " +
                                      $".NET 10: {(windowsDotnet ? "listo" : "falta")} · " +
                                      $"WSL: {(wslReady ? "listo" : "falta")} · " +
                                      $"módulos: {(modulesReady ? "listos" : "externos")}" +
                                      (packageReady ? " · PKG: listo" : " · salida: carpeta");
            _openButton.Enabled = true;
            _openSourcesButton.Enabled = _bundledSdkRoot is not null;

            if (!_browserOpened)
            {
                _browserOpened = true;
                OpenStudio();
            }

            if (sdkReady && root.TryGetProperty("sdkRoot", out JsonElement rootValue))
            {
                string? reportedRoot = rootValue.GetString();
                if (!string.IsNullOrWhiteSpace(reportedRoot) && _sdkRoot != reportedRoot)
                {
                    _sdkRoot = reportedRoot;
                    _sdkRootTextBox.Text = reportedRoot;
                    SaveSettings();
                }
            }
            if (root.TryGetProperty("modulesPath", out JsonElement configuredModules))
            {
                string path = configuredModules.GetString() ?? string.Empty;
                if (_moduleFolderTextBox.Text != path)
                    _moduleFolderTextBox.Text = path;
            }
        }
        catch (HttpRequestException)
        {
            _stateLabel.Text = "Iniciando el servicio local…";
        }
        catch (TaskCanceledException)
        {
            _stateLabel.Text = "Esperando respuesta del servicio local…";
        }
    }

    private void SaveSettings()
    {
        Directory.CreateDirectory(_dataRoot);
        File.WriteAllText(
            _settingsPath,
            JsonSerializer.Serialize(
                new LauncherSettings(_sdkRoot ?? string.Empty, _moduleFolderTextBox.Text.Trim()),
                new JsonSerializerOptions { WriteIndented = true, PropertyNamingPolicy = JsonNamingPolicy.CamelCase }),
            new UTF8Encoding(false));
    }

    private void OpenCompilerFolder()
    {
        if (_bundledSdkRoot is null || !Directory.Exists(_bundledSdkRoot)) return;
        try
        {
            Process.Start(new ProcessStartInfo(_bundledSdkRoot) { UseShellExecute = true });
        }
        catch (System.ComponentModel.Win32Exception exception)
        {
            MessageBox.Show(
                $"No se pudo abrir la carpeta de fuentes:\n{exception.Message}",
                "SharpProspero Studio",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
        }
    }

    private void ShowRequirements()
    {
        MessageBox.Show(
            "El código del compilador y las muestras de aplicaciones están incluidos en este ejecutable.\n\n" +
            "Para compilar en Windows también se necesita:\n" +
            "• .NET 10 SDK en Windows.\n" +
            "• WSL2 con una distribución Linux, .NET 10, clang y zlib1g-dev.\n" +
            "• Una carpeta de módulos compatible (por ejemplo, libc.prx) para las aplicaciones que la requieran.\n\n" +
            "WSL y sus herramientas se instalan por separado desde Windows. No se incluyen binarios del SDK de Prospero.\n" +
            "El instalador solo genera carpetas compiladas; el empaquetador .pkg no se incluye.",
            "Requisitos para compilar",
            MessageBoxButtons.OK,
            MessageBoxIcon.Information);
    }

    private void OpenStudio()
    {
        if (_studioUri is null) return;
        try
        {
            Process.Start(new ProcessStartInfo(_studioUri.ToString()) { UseShellExecute = true });
        }
        catch (InvalidOperationException exception)
        {
            MessageBox.Show(
                $"No se pudo abrir el navegador:\n{exception.Message}",
                "SharpProspero Studio",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
        }
        catch (System.ComponentModel.Win32Exception exception)
        {
            MessageBox.Show(
                $"No se pudo abrir el navegador:\n{exception.Message}",
                "SharpProspero Studio",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
        }
    }

    private async Task CloseStudioAsync()
    {
        if (_serverProcess is null || _serverProcess.HasExited)
        {
            _allowClose = true;
            Close();
            return;
        }

        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(_studioUri!, "/api/shutdown"));
            request.Headers.Add("X-SharpProspero-Shutdown", _shutdownToken);
            using HttpResponseMessage response = await _httpClient.SendAsync(request);
            if (response.StatusCode == HttpStatusCode.Conflict)
            {
                string message = await response.Content.ReadAsStringAsync();
                using JsonDocument document = JsonDocument.Parse(message);
                MessageBox.Show(
                    document.RootElement.GetProperty("error").GetString(),
                    "Compilación en curso",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Information);
                return;
            }
            response.EnsureSuccessStatusCode();
            _isClosing = true;
            _healthTimer.Stop();
            _allowClose = true;
            Close();
        }
        catch (HttpRequestException exception)
        {
            MessageBox.Show(
                $"No se pudo cerrar el servicio de forma segura:\n{exception.Message}",
                "SharpProspero Studio",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
        }
        catch (TaskCanceledException exception)
        {
            MessageBox.Show(
                $"El servicio no respondió al cierre:\n{exception.Message}",
                "SharpProspero Studio",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
        }
        catch (JsonException exception)
        {
            MessageBox.Show(
                $"El servicio devolvió una respuesta de cierre no válida:\n{exception.Message}",
                "SharpProspero Studio",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
        }
    }

    private async void OnFormClosing(object? sender, FormClosingEventArgs eventArgs)
    {
        if (_allowClose) return;
        eventArgs.Cancel = true;
        await CloseStudioAsync();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _healthTimer.Dispose();
            _httpClient.Dispose();
            _serverLog?.Dispose();
            _serverProcess?.Dispose();
        }
        base.Dispose(disposing);
    }

    private sealed record LauncherSettings(string SdkRoot, string ModulesPath);
}
