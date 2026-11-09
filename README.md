 <div align="center">

# 🎮 SharpProspero Studio

**A Native C# Development & Packaging Environment**

<p>
  <img src="https://img.shields.io/badge/PLATFORM-WINDOWS-0078D6?style=flat-square&logo=windows&logoColor=white" />
  <img src="https://img.shields.io/badge/PIPELINE-WSL2%20%2F%20NATIVEAOT-FCC624?style=flat-square&logo=linux&logoColor=black" />
  <img src="https://img.shields.io/badge/FRAMEWORK-.NET%2010-512BD4?style=flat-square&logo=dotnet&logoColor=white" />
  <img src="https://img.shields.io/badge/DISTRIBUTION-PRIVATE%20BUILD-CC3333?style=flat-square" />
</p>

*Un entorno integrado para el desarrollo, compilación y empaquetado de aplicaciones nativas en C#.*

<br/>

<img src="https://i.ibb.co/9kGKYxCd/Captura-de-pantalla-2026-11-09-223633.png" alt="SharpProspero Studio Interface" width="100%" />

<br/>

**PRIVATE SOFTWARE · WINDOWS ECOSYSTEM · NATIVE TOOLCHAIN**

---

</div>

## 01 — Overview

**SharpProspero Studio** es un entorno de desarrollo integrado que centraliza el ciclo de vida de aplicaciones nativas en C#, desde la gestión del SDK hasta la generación de los artefactos finales.

Esta edición privada se distribuye como un ejecutable autónomo para Windows, con los componentes esenciales del entorno integrados en un único paquete.

### What's included

| Component | Description |
|:--|:--|
| 🖥️ **Desktop Launcher** | Interfaz gráfica moderna, servidor local y recursos integrados. |
| 📚 **SharpProspero SDK** | Código fuente completo preparado para esta compilación. |
| 🧪 **Application Samples** | 17 proyectos de ejemplo listos para utilizar. |
| 🧩 **Private Modules** | Paquete local de módulos compatibles, incluyendo `libc.prx`. |
| ⚙️ **Build Pipeline** | Integración con WSL2, NativeAOT y herramientas de SharpProspero. |

> **Distribution Notice**
>
> El ejecutable no incluye WSL2, .NET 10 para Windows/Linux, herramientas propietarias de Sony ni el empaquetador redistribuible de `.pkg`.
>
> Studio genera estructuras de salida preparadas para su ejecución, pero las dependencias externas deben estar correctamente instaladas y configuradas en el sistema anfitrión.

---

## 02 — Build Architecture

El proceso de compilación delega las operaciones en el script `build\build-app.ps1` del SDK activo.

La arquitectura combina la compilación NativeAOT mediante WSL2 con el enlazado y procesamiento de los componentes específicos de SharpProspero.

### Compilation pipeline

```text
             C# APPLICATION
                    │
                    ▼
          WSL2 + NATIVEAOT
                    │
                    ▼
             NATIVE OBJECT
                    │
                    ▼
             LINKING STAGE
                    │
                    ▼
              eboot.bin
                    │
                    ▼
       sce_module / libc.prx
                    │
                    ▼
             OUTPUT DIRECTORY
```

**Build components**

- **NativeAOT:** generación de código nativo.
- **WSL2:** entorno de compilación Linux.
- **Linking:** integración de los artefactos generados.
- **Module Injection:** incorporación de módulos compatibles.
- **Output:** generación de la estructura final del proyecto.

---

## 03 — Installation

### Step 01 · Extract & Launch

Descarga y extrae el paquete de distribución:

`SharpProsperoStudio_Beta.rar` o `.zip`

La estructura del directorio debe contener el ejecutable principal y las dos carpetas de dependencias privadas:

```text
SharpProsperoStudio_Beta/
│
├── SharpProsperoStudio.exe
│
├── toolchains/
│   └── <TOOLCHAIN_HASH>/
│
└── private-modules/
    └── <MODULES_HASH>/
        └── libc.prx
```

Una vez extraído:

1. Ejecuta `SharpProsperoStudio.exe`.
2. El servidor local se iniciará automáticamente.
3. La interfaz web se abrirá en el navegador predeterminado.

---

### Step 02 · SDK Configuration

Antes de compilar, es necesario configurar las rutas de las dependencias locales.

Accede a:

**Settings → SharpProspero SDK**

En esta sección encontrarás dos campos de configuración.

#### ① SharpProspero Root Directory

<kbd>TOOLCHAIN PATH</kbd>

Selecciona la carpeta raíz del SDK ubicada dentro de `toolchains/`.

Ejemplo:

```text
C:\...\SharpProsperoStudio_Beta\toolchains\6EA3ECC25...
```

#### ② Compatible Modules Directory

<kbd>PRIVATE MODULES PATH</kbd>

Selecciona la carpeta que contiene los módulos compatibles, ubicada dentro de `private-modules/`.

Ejemplo:

```text
C:\...\SharpProsperoStudio_Beta\private-modules\42D4FD0...
```

> [!IMPORTANT]
> **Requisito de `libc.prx`**
>
> El archivo `libc.prx` debe encontrarse directamente en la raíz de la carpeta configurada en *Compatible Modules Directory*.
>
> No debe estar dentro de subdirectorios adicionales.

**Configuración esperada:**

```text
42D4FD0.../
│
├── libc.prx
└── ...
```

> [!WARNING]
> **Host Dependencies**
>
> El SDK proporciona las herramientas y el código fuente del compilador, pero los siguientes componentes deben estar instalados previamente:
>
> - .NET 10
> - WSL2
> - Entorno Linux compatible con el pipeline NativeAOT.

---

### Step 03 · Save & Build

Una vez configuradas las dependencias:

1. Pulsa **Save Paths** para guardar las rutas del SDK.
2. Selecciona la muestra o el proyecto que quieras compilar.
3. Pulsa **Build** para iniciar el proceso.
4. Espera a que finalice el pipeline de compilación y enlazado.

Los artefactos generados se almacenarán en el directorio correspondiente:

```text
<PROJECT>/
│
└── out/
    └── module/
        ├── eboot.bin
        ├── sce_module
        └── ...
```

<sub>La estructura y los archivos concretos dependerán del proyecto y de los módulos utilizados.</sub>

---

## 04 — System Requirements

| Dependency | Requirement |
|:--|:--|
| Operating System | Windows |
| Runtime | .NET 10 |
| Linux Environment | WSL2 |
| Compiler Pipeline | NativeAOT |
| SDK | SharpProspero |
| Private Modules | Compatible modules + `libc.prx` |
| Additional Tooling | Sony proprietary tools (where required) |

---

<div align="center">

## SharpProspero Studio


*Built for native development. Designed for streamlined workflows.*

<br/>

<sub>PRIVATE BUILD · NOT AN OFFICIAL SONY PRODUCT</sub>

</div>
