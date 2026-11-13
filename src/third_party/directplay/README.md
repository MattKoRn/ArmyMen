# Legacy DirectPlay header compatibility for modern MSVC

The original **Army Men (1998)** Windows game uses DirectPlay 3/4 COM
interfaces for networking and multiplayer lobby integration. Modern Windows
SDKs do not ship `dplay.h` or `dplobby.h`, and **June 2010 DirectX SDK
does not supply them either**. Microsoft's last DirectX SDK release
containing DirectPlay headers was **August 2007**.

To keep the original game networking code available, this directory contains:

- `include/dplay.h`
- `include/dplobby.h`

These headers are sourced from the upstream **MinGW-w64** project,
`https://github.com/mingw-w64/mingw-w64`:

- `mingw-w64-headers/include/dplay.h`, upstream blob
  `7539536f643347be4851a1ec0daab384bff2e1d9`
- `mingw-w64-headers/include/dplobby.h`, upstream blob
  `891d9fdb0170f64b63c236dacaf5b2de3ea5c4c6`

The only modification to `dplobby.h` is to remove the MinGW-only
`_mingw_unicode.h` include and replace its `__MINGW_NAME_AW` alias
for `DirectPlayLobbyCreate` with standard `#ifdef UNICODE` selection.
The copyright and license notices in the original header files are kept.

**License:** These two headers are licensed under the GNU Lesser General
Public License version **2.1 or later** by their original contributors
(the Wine project and named authors). See their file headers and
`https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html` for the
full license terms. The bundled headers do **not** relicense the rest of
ArmyMen. See MinGW-w64's license description at
`https://github.com/mingw-w64/mingw-w64/blob/master/COPYING.MinGW-w64/COPYING.MinGW-w64.txt`.

The one-click `scripts/Build-Install-ArmyMen.ps1` build helper checks
these headers and prepends this directory to the **x86 MSVC INCLUDE path**
*after* running VsDevCmd. It does not replace Windows system headers or
silently disable multiplayer.

**Limitations:** These are compile-time declarations, **not a DirectPlay
runtime**. The target Windows machine still needs compatible runtime
services and networking behavior, and the 1998 source may have further
MSVC/Windows API compatibility issues. No multiplayer runtime test is
claimed. If later linker errors mention `CLSID_DirectPlay`,
`IID_IDirectPlay*`, or `DPSPGUID_*`, the project's GUID-linking setup
must be corrected rather than changing those published identifiers.
