# Guía de uso de SharpProspero Studio

## 1. Iniciar el programa

Haz doble clic en `SharpProsperoStudio.exe`. El lanzador inicia el servicio local, extrae la interfaz y el código fuente del SDK al perfil de Windows y abre Studio en el navegador. Mantén abierta la ventana del lanzador mientras uses la interfaz. El servicio solo escucha en `127.0.0.1`; no lo expongas a la red.

La primera vez, Windows puede mostrar un aviso de editor desconocido porque el ejecutable no está firmado digitalmente.

## 2. Comprobar los requisitos

En «Entorno de compilación» puedes comprobar el estado de .NET, WSL y los módulos. Para compilar en Windows se necesita:

- .NET 10 SDK en Windows.
- WSL2 con una distribución Linux, .NET 10, `clang` y `zlib1g-dev`.
- Los módulos compatibles que requiera la aplicación, como `libc.prx`.

El EXE incluye el código fuente del SDK, pero no instala .NET ni WSL. Las dependencias externas deben configurarse en cada equipo.

## 3. Configurar las carpetas

Abre el botón de ajustes (⚙). Hay dos campos distintos:

1. **Campo superior — raíz del SDK:** la carpeta que contiene `build\build-app.ps1` y `samples`. Normalmente se usa el SDK incluido y extraído en `%LOCALAPPDATA%\SharpProsperoStudio\toolchains`.
2. **Campo inferior — carpeta de módulos:** selecciona la carpeta que contiene `libc.prx` directamente. No selecciones el archivo `libc.prx` ni la carpeta raíz del SDK. Pulsa «Guardar rutas» para aplicar la configuración.

En la edición privada de pruebas, el módulo incluido se extrae a `%LOCALAPPDATA%\SharpProsperoStudio\private-modules` y se selecciona automáticamente si no hay otra ruta válida configurada. La edición pública no incluye `libc.prx`; debes proporcionar una copia compatible que tengas autorización para usar.

## 4. Compilar una aplicación

1. En «Proyecto de aplicación», elige una muestra, por ejemplo `prospero-arcade` o `prospero-app`.
2. Opcionalmente, escribe la ruta completa a tu propio `.csproj` de aplicación SharpProspero. Al hacerlo, se compila ese proyecto en lugar de la muestra.
3. Selecciona «Carpeta» como formato de salida si el empaquetador `.pkg` no está disponible.
4. Pulsa «Compilar proyecto» y revisa el «Registro de compilación» para ver el progreso y los errores.

Para proyectos con `sce_sys\param.json`, Studio asigna un Title ID `PPSA` nuevo por compilación. En la plantilla `prospero-app`, también sustituye los placeholders del Title ID y del Content ID en los metadatos de salida, sin cambiar los archivos fuente del proyecto.

## 5. Encontrar los archivos generados

La salida se guarda en la carpeta `out` junto al proyecto seleccionado:

- La aplicación compilada queda en `out\module`.
- El archivo de inicio de la aplicación es `out\module\eboot.bin`.
- Los módulos que la aplicación necesita quedan en `out\module\sce_module`.
- Los metadatos están en `out\module\sce_sys`.

Si compilas una muestra incluida, la salida queda bajo la carpeta de esa muestra dentro del SDK extraído. La ruta exacta aparece al terminar la compilación, en el registro y en el panel.

## 6. Cerrar Studio

Cierra la ventana del lanzador con «Cerrar Studio». Si hay una compilación en curso, espera a que termine antes de cerrar. La interfaz del navegador se puede cerrar por separado.

## Ediciones

- **EXE privado de pruebas** (`dist-private\SharpProsperoStudio.exe`): incluye el módulo local autorizado usado para las pruebas. No lo compartas ni lo distribuyas.
- **EXE público** (`dist\SharpProsperoStudio.exe`): no incluye módulos privados. Configura tus propios módulos compatibles cuando sean necesarios.

Ninguna de estas ediciones incluye el empaquetador `.pkg` redistribuible. La salida en carpeta es el formato disponible en la distribución.

## Solución de problemas

- **`libc.prx: MISSING`:** el campo inferior no apunta a una carpeta que tenga `libc.prx` directamente en su raíz.
- **Falta .NET o WSL:** instala los requisitos indicados en «Entorno de compilación» y vuelve a iniciar Studio.
- **La compilación falla:** consulta las últimas líneas del registro; suelen identificar el paso que falló y el requisito pendiente.
- **La ruta de SDK no es válida:** verifica que el campo superior contiene `build\build-app.ps1` y `samples`. El EXE puede volver a seleccionar automáticamente el SDK incluido si la ruta guardada no soporta la plantilla `prospero-app`.
- **El servicio no abre:** cierra cualquier instancia anterior de SharpProspero Studio e inicia el EXE otra vez.

La extracción y los ajustes del lanzador se guardan bajo `%LOCALAPPDATA%\SharpProsperoStudio`.
