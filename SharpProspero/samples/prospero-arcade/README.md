# Neon Arcade

Una aplicacion SharpProspero con tres minijuegos controlados con el mando:

- **Paddle Rush**: mantén la pelota en juego y aumenta la racha.
- **Meteor Run**: esquiva meteoritos moviendote por la pantalla.
- **Star Catcher**: recoge estrellas y evita bombas.

## Controles

- Cruceta arriba/abajo y Cross: elegir e iniciar un juego.
- Cruceta izquierda/derecha: mover la paleta, la nave o la cesta.
- Cruceta arriba/abajo: movimiento vertical en Meteor Run.
- Circle: volver al menu o regresar desde el fin de partida.
- Cross: volver a jugar tras perder.
- Options: salir.

## Requisitos para compilar

Este ejemplo necesita Git, el .NET 10 SDK y una instalacion oficial del SDK de Prospero. En Windows,
NativeAOT tambien necesita WSL2 con .NET 10, `clang` y `zlib1g-dev`; en Linux instala .NET 10,
PowerShell 7, `clang` y `zlib1g-dev`.

El programa de compilacion obtiene de `target/sce_module` el `libc.prx` requerido por el runtime. El
SDK oficial de Prospero debe estar instalado localmente y no se distribuye dentro de este repositorio.
Configura la raiz del SDK antes de compilar:

```powershell
$env:SCE_PROSPERO_SDK_DIR = 'C:\ruta\al\ProsperoSDK'
```

En Linux, usa la ruta de la instalacion local:

```bash
export SCE_PROSPERO_SDK_DIR="$HOME/ProsperoSDK"
```

## Compilar en formato carpeta

Desde la raiz del repositorio:

```powershell
pwsh .\build\build-app.ps1 -ProjectPath .\samples\prospero-arcade\Arcade.csproj -Output Folder
```

El pipeline tambien necesita que `SHARPPROSPERO_ROOT` apunte a la raiz de este checkout; puede
configurarse con `$env:SHARPPROSPERO_ROOT = (Get-Location).Path`. En Windows, el script ejecuta
NativeAOT dentro de WSL. La salida completa queda en `samples/prospero-arcade/out/module`, con
`eboot.bin`, `sce_sys` y `sce_module/libc.prx`. `-Output Folder` no genera ningun PKG.

El build vuelve a generar la salida desde el codigo fuente; las carpetas generadas no se incluyen en el
checkout ni en el ZIP de fuentes. `param.json` trae un Title ID de ejemplo: cambialo por uno propio
antes de instalarlo junto con otra copia del juego.