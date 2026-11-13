# Army Men [1998] Source Code & Tools

These files contain the source code to the first Army Men game released in 1998 by The 3DO Company. They also contain the level, scenario, animation editor along with some of the uncompressed 2D art assets.

Originally discovered by:
- _Z3N_

Special Thanks:
- Trapexit
- The 3DO Company
- Army Men fans

## Autonomous AI spectator mode

The current `main` source includes an AI takeover prototype that controls the local player's army and pans the spectator camera. On Windows, double-click [`INSTALL_AI_TAKEOVER.cmd`](INSTALL_AI_TAKEOVER.cmd) from a checkout of `main`. It automatically detects the installed Visual Studio C++ environment; when NMAKE/MSVC is missing, it can download and launch **Microsoft's official Visual Studio 2022 Build Tools installer** (admin approval, internet and several GB of disk space may be required). It then attempts a Win32 build, backs up the existing executable, installs a successfully built replacement, and launches the game. Build logs go to `AI_TAKEOVER_BUILD.log`. **This fixes the missing-NMAKE setup step, but does not guarantee that the original 1998 makefile will compile with a modern compiler/DirectX SDK.** If compilation fails, the original game is not replaced.

See [`docs/AI_TAKEOVER.md`](docs/AI_TAKEOVER.md) for supported behaviours, limitations, and the manual test checklist. This code is a prototype and has not been verified by a full Windows build or gameplay test.
