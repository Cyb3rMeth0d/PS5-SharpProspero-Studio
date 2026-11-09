# SharpProspero

SharpProspero es un SDK y una cadena de herramientas en C# para crear aplicaciones homebrew para la plataforma Prospero. Usa .NET NativeAOT para compilar el codigo administrado a codigo nativo y herramientas propias para enlazar los modulos y generar sus paquetes.

El repositorio permite crear tres tipos de artefacto:

- **Aplicaciones**: modulos con `eboot.bin` y metadatos `sce_sys`, empaquetables como `.pkg` o como una carpeta de archivos.
- **Bibliotecas PRX**: modulos reutilizables por otras aplicaciones.
- **Payloads**: ejecutables ELF creados para un entorno de carga compatible; su compilacion y API se describen en la documentacion especifica.

## Como funciona

Para una aplicacion, el pipeline se encarga de las siguientes etapas:

```mermaid
flowchart LR
    A[Codigo C#] --> B[Compilacion NativeAOT]
    B --> C[Objeto x86-64]
    C --> D[Enlazador SharpProspero]
    D --> E[eboot.bin]
    E --> F[Metadatos y archivos del modulo]
    F --> G[Paquete .pkg o carpeta]
```

1. El proyecto se publica para `linux-x64`; NativeAOT produce el objeto nativo.
2. El enlazador de SharpProspero combina ese objeto con el runtime necesario y resuelve las referencias a servicios del sistema.
3. El empaquetador reune `eboot.bin`, los metadatos `sce_sys` y, cuando corresponde, las bibliotecas `sce_module`.
4. `build/build-app.ps1` coordina estos pasos. En Windows ejecuta la compilacion NativeAOT mediante WSL; el enlazado y el empaquetado se ejecutan desde el sistema anfitrion.

Un `dotnet build` normal compila la solucion de la SDK y sus herramientas, pero no genera un paquete de aplicacion. Para ello se usa el script del pipeline. Los payloads producen un `.elf` y no pasan por la etapa de empaquetado de aplicaciones.

## Que incluye

La biblioteca `SharpProspero` agrupa APIs por areas: ciclo de vida de aplicaciones, graficos 2D y 3D, entrada, audio, multimedia, almacenamiento, memoria, red, interfaz, temporizacion, diagnostico e interop con servicios del sistema. La aplicacion habitual deriva de `ProsperoApp` e implementa su comportamiento por frame.

El repositorio tambien contiene herramientas para enlazar y empaquetar, inspeccionar modulos y trabajar con bindings y recursos, ademas de proyectos de ejemplo listos para adaptar.

## Requisitos e instalacion

Se necesita Git para clonar el repositorio y el **.NET 10 SDK** para compilar la solucion y sus herramientas. Para generar un modulo NativeAOT, el compilador tambien debe ejecutarse en Linux x64: directamente en Linux o dentro de WSL2 desde Windows. NativeAOT requiere `clang` y `zlib1g-dev` en Linux. El runtime NativeAOT se restaura desde .NET; no hace falta instalar un runtime pack, enlazador ni archivos stub externos.

Para compilar aplicaciones que necesitan modulos redistribuibles del sistema, instala el SDK oficial de
Prospero y configura `SCE_PROSPERO_SDK_DIR` con su carpeta raiz. El pipeline toma de
`target/sce_module` los modulos que la aplicacion debe llevar consigo y que no estan ya en el proyecto.
El ejemplo Neon Arcade necesita `libc.prx`, por lo que esa dependencia debe estar disponible en el SDK
oficial. No se incluye el binario del SDK en este repositorio.

### Windows x64

Si Git no esta instalado, se puede instalar con WinGet:

```powershell
winget install --id Git.Git --exact
```

Instala PowerShell 7 para usar los comandos `pwsh` de esta guia (Windows PowerShell 5.1 tambien puede ejecutar los scripts del repositorio):

```powershell
winget install --id Microsoft.PowerShell --exact --scope user
```

Instala .NET 10 en el perfil de usuario con el instalador oficial de Microsoft:

```powershell
$installScript = Join-Path $env:TEMP 'dotnet-install.ps1'
Invoke-WebRequest https://dot.net/v1/dotnet-install.ps1 -OutFile $installScript
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installScript -Channel 10.0 -InstallDir "$env:USERPROFILE\.dotnet"
$dotnetPath = Join-Path $env:USERPROFILE '.dotnet'
[Environment]::SetEnvironmentVariable('DOTNET_ROOT', $dotnetPath, 'User')
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (($userPath -split ';') -notcontains $dotnetPath) {
    [Environment]::SetEnvironmentVariable('Path', "$userPath;$dotnetPath", 'User')
}
$env:DOTNET_ROOT = $dotnetPath
$env:Path = "$dotnetPath;$env:Path"
dotnet --version
```

Para compilar artefactos NativeAOT en Windows, instala WSL2 y una distribucion Linux si aun no estan instalados. La instalacion inicial puede requerir reiniciar Windows:

```powershell
wsl --install -d Ubuntu
```

Abre Ubuntu y, dentro de esa terminal, instala el SDK .NET 10 para Linux. `curl` y `ca-certificates` se usan para descargar el instalador oficial:

```bash
sudo apt update
sudo apt install -y curl ca-certificates
curl -fsSL https://dot.net/v1/dotnet-install.sh -o dotnet-install.sh
bash dotnet-install.sh --channel 10.0
echo 'export DOTNET_ROOT="$HOME/.dotnet"' >> ~/.bashrc
echo 'export PATH="$DOTNET_ROOT:$PATH"' >> ~/.bashrc
source ~/.bashrc
dotnet --version
```

La compilacion normal de la solucion solo usa el SDK de Windows. WSL y su SDK son necesarios al generar los modulos; el script invoca WSL automaticamente. En Ubuntu, instala tambien las herramientas nativas requeridas por NativeAOT:

```bash
sudo apt update
sudo apt install -y clang zlib1g-dev
```

Guarda la ruta del checkout para las nuevas terminales de Windows:

```powershell
[Environment]::SetEnvironmentVariable('SHARPPROSPERO_ROOT', (Get-Location).Path, 'User')
$env:SHARPPROSPERO_ROOT = (Get-Location).Path
```

Indica tambien la carpeta raiz del SDK oficial de Prospero, que contiene `target\sce_module`:

```powershell
$env:SCE_PROSPERO_SDK_DIR = 'C:\ruta\al\ProsperoSDK'
[Environment]::SetEnvironmentVariable('SCE_PROSPERO_SDK_DIR', $env:SCE_PROSPERO_SDK_DIR, 'User')
```

### Linux x64

Instala Git, el .NET 10 SDK, `curl`, `ca-certificates`, `clang`, `zlib1g-dev` y PowerShell 7 (`pwsh`). En Ubuntu o Debian:

```bash
sudo apt update
sudo apt install -y git curl ca-certificates clang zlib1g-dev
curl -fsSL https://dot.net/v1/dotnet-install.sh -o dotnet-install.sh
bash dotnet-install.sh --channel 10.0
echo 'export DOTNET_ROOT="$HOME/.dotnet"' >> ~/.bashrc
echo 'export PATH="$DOTNET_ROOT:$HOME/.dotnet/tools:$PATH"' >> ~/.bashrc
source ~/.bashrc
dotnet --version
dotnet tool install --global PowerShell
pwsh --version
export SHARPPROSPERO_ROOT="$HOME/SharpProspero"
echo 'export SHARPPROSPERO_ROOT="$HOME/SharpProspero"' >> ~/.bashrc
export SCE_PROSPERO_SDK_DIR="$HOME/ProsperoSDK"
echo 'export SCE_PROSPERO_SDK_DIR="$HOME/ProsperoSDK"' >> ~/.bashrc
```

Actualiza `SHARPPROSPERO_ROOT` en `~/.bashrc` si el repositorio esta en otra ruta. En Windows, el valor se persiste con el comando de la seccion anterior. Desde la raiz del repositorio puedes configurarlo solo para la terminal actual:

```powershell
$env:SHARPPROSPERO_ROOT = (Get-Location).Path
```

`SCE_PROSPERO_SDK_DIR` debe apuntar a la raiz de una instalacion oficial del SDK; ajusta el ejemplo a su
ruta real. En Windows, configurala en PowerShell como se muestra en la seccion anterior.

Comprueba la instalacion desde la raiz:

```powershell
pwsh .\doctor.ps1
```

En Linux, ejecuta el mismo script con `pwsh doctor.ps1`. Consulta [Configuracion](docs/setup.md) para los detalles de cada sistema operativo.

## Archivos necesarios para compilar

Clona o descarga el repositorio completo; no basta con copiar solo `src/`. Estos archivos y carpetas
forman la cadena de compilacion:

| Ruta | Para que se necesita |
|---|---|
| `SharpProspero.slnx` y `Directory.Build.props` | Solucion y configuracion compartida de .NET 10. |
| `src/SharpProspero/` | Biblioteca y APIs del SDK. |
| `tools/SharpProspero.*` | Generador de bindings, enlazador, lector/escritor PRX/SELF, empaquetador y herramientas de recursos. |
| `tools/SharpProspero.Packager/LibProsperoPkg.dll` | Dependencia del empaquetador; debe mantenerse junto a su proyecto. |
| `build/` y `doctor.ps1` | Targets MSBuild, propiedades y scripts del pipeline. |
| `samples/` | Proyectos de ejemplo, codigo nativo y recursos necesarios para reproducir sus compilaciones. |
| `runtime/imports/` | Catalogos de referencia del runtime que acompanan a las herramientas. |
| `docs/`, `README.md`, `CONTRIBUTING.md` y `LICENSE` | Instrucciones, referencia y licencia del repositorio. |

No se versionan ni se necesitan para una compilacion limpia las carpetas generadas `bin/`, `obj/` y
`out/`; NuGet y NativeAOT las vuelven a crear. Para validar la instalacion y compilar una aplicacion
desde la raiz del repositorio:

```powershell
pwsh .\doctor.ps1
dotnet restore .\SharpProspero.slnx
dotnet build .\SharpProspero.slnx
pwsh .\build\build-app.ps1 -ProjectPath .\samples\prospero-app\SampleApp.csproj -Output Folder
```

La ultima orden deja los archivos listos para probar en `samples/prospero-app/out/module`, sin crear
un PKG. Consulta [Pipeline de compilacion](docs/build-pipeline.md) para generar una carpeta de otro
proyecto o cambiar el formato de salida.

Para compilar el ejemplo Neon Arcade en formato carpeta, instala y configura primero el SDK oficial de
Prospero como se describio arriba, y ejecuta:

```powershell
pwsh .\build\build-app.ps1 -ProjectPath .\samples\prospero-arcade\Arcade.csproj -Output Folder
```

El resultado completo, incluido `eboot.bin`, `sce_sys` y el `libc.prx` requerido, queda en
`samples/prospero-arcade/out/module`. No se genera un PKG.

## Inicio rapido

Compila la solucion y prepara una copia de la muestra de aplicacion:

```powershell
dotnet build .\SharpProspero.slnx
$env:SHARPPROSPERO_ROOT = (Get-Location).Path
Copy-Item -Recurse .\samples\prospero-app .\MiApp
```

Genera los archivos del modulo en `MiApp\out\module`:

```powershell
pwsh .\build\build-app.ps1 -ProjectPath .\MiApp\SampleApp.csproj -Output Folder
```

Si se omite `-Output Folder`, el script genera un paquete `.pkg` por defecto. Para crear una aplicacion propia, adapta `Program.cs` y los campos de identidad de `sce_sys/param.json` en la copia de la muestra. Ver [Inicio guiado](docs/getting-started.md) y [referencia de metadatos](docs/param-json.md).

## Estructura del repositorio

| Ruta | Contenido |
|---|---|
| `src/SharpProspero/` | Biblioteca principal y APIs organizadas por area. |
| `tools/` | Proyectos de herramientas para bindings, enlazado, empaquetado y recursos. |
| `build/` | Propiedades y targets de MSBuild, scripts y pipeline de compilacion. |
| `samples/` | Ejemplos de aplicaciones, bibliotecas y payloads. |
| `docs/` | Guias de configuracion, arquitectura, APIs, herramientas y solucion de problemas. |
| `runtime/` | Notas sobre los archivos de runtime usados por el pipeline. |
| `SharpProspero.slnx` | Solucion de la biblioteca y las herramientas principales. |

## Documentacion

- [Inicio guiado](docs/getting-started.md): crear y compilar una aplicacion.
- [Configuracion](docs/setup.md): requisitos e instalacion en Windows y Linux.
- [Arquitectura](docs/architecture.md): componentes y APIs de la SDK.
- [Pipeline de compilacion](docs/build-pipeline.md): etapas de NativeAOT, enlazado y empaquetado.
- [Aplicaciones](docs/application-modules.md) y [muestras](docs/app-samples.md).
- [Payloads](docs/payloads.md), [compilacion](docs/payload-build.md) y [muestras](docs/payload-samples.md).
- [Herramientas de linea de comandos](docs/commands.md) y [solucion de problemas](docs/help.md).
- [Contribuciones](CONTRIBUTING.md).

## Creditos

- **SharpProspero y sus herramientas de compilacion**: SvenGDK, autor registrado en el historial del repositorio y titular del copyright indicado en la licencia.
- **Pruebas de lanzamiento y colaboracion en el diagnostico**: Cyb3rMeth0d.
- **Compilador NativeAOT de .NET**: Microsoft y los colaboradores del proyecto .NET Runtime. SharpProspero utiliza NativeAOT para compilar C# a codigo nativo; el enlazador y el empaquetador de Prospero forman parte de este repositorio.

## Licencia

GPL-3.0-or-later. Copyright (C) SvenGDK 2026.
