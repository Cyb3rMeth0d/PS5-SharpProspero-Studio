# SharpProspero Studio — EXE privado de pruebas

> **Uso exclusivamente privado para pruebas. No compartir, publicar ni redistribuir este ejecutable ni el módulo que lleva integrado.**

Este documento describe cómo funciona `dist-private\SharpProsperoStudio.exe`, qué incluye y dónde deja sus archivos al iniciarse.

## Qué incluye

El EXE privado es un único ejecutable de Windows. Lleva integrados:

- El lanzador de escritorio, el servidor local y los recursos de la interfaz.
- El código fuente SharpProspero incluido para esta build y 17 muestras de aplicaciones.
- Un ZIP de módulos locales, entre ellos `libc.prx`, proporcionado mediante `-PrivateModulesPath` al generar la build privada.

No incluye WSL ni .NET 10 para Windows/Linux; tampoco incluye un SDK propietario de Sony ni el empaquetador redistribuible de `.pkg`. Por ello, genera carpetas compiladas y sigue necesitando las dependencias de compilación instaladas en el equipo.

## Qué ocurre al abrirlo

1. El lanzador extrae la interfaz a `%LOCALAPPDATA%\SharpProsperoStudio\app`.
2. Extrae el código fuente del compilador a `%LOCALAPPDATA%\SharpProsperoStudio\toolchains\<huella-del-paquete>`. La huella identifica la versión del bundle.
3. Extrae los módulos privados a `%LOCALAPPDATA%\SharpProsperoStudio\private-modules\<huella-del-paquete>`.
4. Si no hay una carpeta de módulos configurada que contenga `libc.prx`, selecciona automáticamente esa carpeta privada. Guarda las rutas del lanzador en `%LOCALAPPDATA%\SharpProsperoStudio\settings.json`.
5. Inicia el servidor en una dirección local `127.0.0.1` y abre la interfaz en el navegador. La ventana del lanzador debe permanecer abierta mientras se usa Studio.

Los archivos extraídos permanecen en `%LOCALAPPDATA%` después de cerrar Studio para que no tenga que desempaquetarlos en cada inicio.

## Cómo compila

Al solicitar una build, Studio ejecuta el `build\build-app.ps1` del SDK seleccionado. En Windows, el pipeline usa WSL2 para la fase NativeAOT y después ejecuta las herramientas SharpProspero que enlazan y preparan la aplicación:

1. Compila el proyecto C# para producir el objeto nativo.
2. Enlaza el objeto y genera `eboot.bin`.
3. Reúne metadatos, recursos y los módulos que la aplicación necesita.
4. Asigna un Title ID `PPSA` nuevo por build y actualiza los metadatos de salida. En `prospero-app`, sustituye también los placeholders de Title ID y Content ID.
5. Genera la salida en carpeta. La distribución no genera `.pkg`.

El `libc.prx` privado se usa como recurso local cuando el pipeline necesita reunir el módulo en `sce_module`. El paso de comprobación notifica la dependencia faltante en vez de producir una salida incompleta.

## Dónde están los resultados

Las compilaciones de las muestras incluidas se guardan bajo la carpeta del SDK extraído, por ejemplo:

```text
%LOCALAPPDATA%\SharpProsperoStudio\toolchains\<huella-del-paquete>\samples\prospero-arcade\out\module
```

La ruta exacta se muestra en Studio al terminar. Dentro de `out\module` se encuentran `eboot.bin`, los metadatos de `sce_sys` y, cuando se necesita, el módulo en `sce_module`.

## Requisitos

- Windows con .NET 10 SDK.
- WSL2 con una distribución Linux configurada, .NET 10, `clang` y `zlib1g-dev`.

El lanzador comprueba y muestra el estado de .NET y WSL, pero no instala estos componentes.

## Cómo se generó esta build privada

Desde PowerShell, en el directorio `build\visual-preview`, se puede regenerar indicando una carpeta cuyo `libc.prx` esté directamente en la raíz:

```powershell
.\build-distribution.ps1 -PrivateModulesPath "C:\ruta\SharpProspero\samples\prospero-arcade\sce_module"
```

El ejecutable se crea en `dist-private\SharpProsperoStudio.exe`, separado de la edición pública `dist\SharpProsperoStudio.exe`. Sin `-PrivateModulesPath`, el script no incrusta módulos privados y genera la edición pública.

## Límites y precauciones

- Esta es una build de pruebas, no una distribución pública. El ejecutable incrusta un módulo binario local y debe permanecer en el entorno privado autorizado.
- `libc.prx` debe ser compatible con la aplicación y el entorno de ejecución; incluirlo no garantiza que cualquier muestra o proyecto funcione en todas las consolas.
- No distribuye el SDK oficial de Sony ni instala dependencias externas.
- La salida es una carpeta compilada, no un `.pkg`.
- El servicio solo debe usarse en `127.0.0.1`; no lo expongas a la red.
- No cierres el lanzador mientras una compilación siga activa.
