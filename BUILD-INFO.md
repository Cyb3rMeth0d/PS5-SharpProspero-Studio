# Source package build information

- Private executable: `dist-private\SharpProsperoStudio.exe`
- SDK application samples included: 17
- Private module: `libc.prx` (not included in this source package)
- SHA-256 of the local module used for the private build: `E6FF45D16ADF687855CC3B33B0C8A4132B6504360B221E0A34C7E99FB3BA0036`

This archive contains the Studio source and the SharpProspero source tree embedded in the executable. It intentionally excludes compiled outputs, the private `libc.prx` binary, other proprietary SDK binaries and package-builder dependencies. To reproduce the private executable, provide a module folder you are authorized to use and follow `Studio\README-PRIVADO.md`.