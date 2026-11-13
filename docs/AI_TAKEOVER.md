# Full AI Takeover + Intelligent Spectator Camera (prototype)

This release turns the **local player's faction** into an AI-run army as soon as a mission starts. The human player watches the fight through an automatic, smoothly panning camera rather than issuing orders.

## Install on Windows (one click)

1. Clone or download the `main` branch of `MattKoRn/ArmyMen`.
2. Double-click **`INSTALL_AI_TAKEOVER.cmd`** at the repository root. It calls `scripts/Build-Install-ArmyMen.ps1` using the included Windows PowerShell.
3. The installer searches for an existing Visual Studio C++ build environment using Microsoft's `vswhere` and activates its x86 Developer Command Prompt. If NMAKE/Visual C++ tools are missing, it downloads the **official Microsoft Visual Studio 2022 Build Tools bootstrapper** from `https://aka.ms/vs/17/release/vs_buildtools.exe` and attempts to install the C++ workload and MFC components. Expect internet traffic, several GB of disk use, and a possible administrator permission prompt. This first-time setup may require a reboot.
4. The script runs the legacy NMAKE **Win32 Release executable target** directly, avoiding the obsolete `bscmake` browser target. The compiler output is saved as `AI_TAKEOVER_BUILD.log` in the repo root.
5. **Only if a patched executable is successfully compiled:** The script backs up the original `src/RunTime/Armymen.exe` as `Armymen.exe.before-ai-takeover`, installs the new binary, then launches ArmyMen. If tool installation, compilation or copying fails, the existing game executable is preserved.

**Important limitation:** The original game was built with Visual C++ 4.2 and a late-1990s DirectX SDK. Modern MSVC and Windows SDK installations provide NMAKE and a Win32 compiler, but may still fail to compile historic APIs, MFC usages, build flags or linkage. Fixing the *missing-NMAKE* failure does not mean a full modern-port build has been verified. Never substitute the checked-in historical EXE for a newly compiled AI-patched binary.

Optional advanced flags (from PowerShell): `-NoPull` builds without a git update, `-SkipToolInstall` refuses automatic Build Tools installation, and `-NoLaunch` builds/installs without starting the game. The command file passes through these flags, for example `INSTALL_AI_TAKEOVER.cmd -NoPull -NoLaunch`.

The script only uses `git pull --ff-only origin main` when already on `main`, and never force-resets local edits. You can restore the pre-mod executable from the `.before-ai-takeover` backup.

## Features and integration points

- **Immediate handover:** `BeginMission` calls `AutoAIStartMission`. Player units, available vehicles and Sarge switch to the original game's NPC/script AI control.
- **Continuous autonomous planning:** `AICommander` calls `AutoAIThink` approximately every 4 seconds; the existing unit AI keeps responsibility for individual trooper firing, pathing and formation.
- **Adaptive tactics:** local threats are prioritised; weakened squads fall back to the commander; healthy forces advance toward a shared target or scout the map centre. Capture-the-flag matches pursue a known opposing flag location.
- **Vehicle/commander control:** the existing Sarge and vehicle AI receives destination and attack/defend orders.
- **Controlled reserves:** in multiplayer, already-prepared units/vehicles with valid mission deployment coordinates can enter play, at most one every 20 seconds. Single-player scripted reinforcement events are preserved.
- **Automatic camera:** `UI_ProcessScreen` gives the spectator camera control of the viewport. The camera looks for ongoing squad combat, moving vehicles and Sarge, holds an interesting subject before switching, and pans using the game's existing scroll helper.
- **Input isolation:** during active gameplay, the AI spectator gets only the Escape/menu key and mouse command handlers refuse unit orders. Mission/setup menus remain available.

## Architecture and limitations

This is a first playable **source-level prototype**, not a tested standalone mod, binary patch, or rewritten game AI. The repository is the *Army Men (1998)* source code, not a base-building RTS. It has mission-specified reserves and air-support resources but does **not** provide a general economy, buildings-to-construct, harvesting, research or unit factory gameplay loop. Therefore “all production/resources” currently means the AI operates available forces and mission-prepared reserves—not an invented construction/economy system.

The strategic AI shares enemy knowledge through `ItemVisible` rather than inspecting the entire map. Without visible targets or flag objectives it scouts the map centre. The director uses existing routing; unreachable goals may fail. Scripted single-player objectives and mission completion should be regression-tested; scripted arrival-event orders should take precedence. Local-multiplayer authority, networking, camera visibility/fog, and bootcamp/campaign edge cases require playtesting before considering all modes production-ready.

## Manual test checklist

- [ ] Build patched EXE using the historical VC++ toolchain.
- [ ] Start a new single-player mission and confirm Sarge and all starting squads move without keyboard or mouse input.
- [ ] Verify mouse clicks and combat keys do not issue orders while Escape opens the pause/menu screen.
- [ ] Observe camera staying on an engagement, following moving units, and panning smoothly when focus changes.
- [ ] Confirm a weakened squad regroups; other squads continue advancing.
- [ ] Confirm targets outside the army's visible range aren't directly chased.
- [ ] Confirm scripted mission objectives and victory/failure conditions still fire.
- [ ] Test capture-the-flag, a hosted multiplayer session, and a remote client; inspect AI ownership and synchronization.
- [ ] Confirm prepared reserves deploy only at legal assigned points and resource counts are not fabricated.
- [ ] Check save/restore and transition into a second mission; verify AI state resets correctly.

## Files changed

`src/AutoAITakeover.inc` contains the AI director and camera; it is included from `src/aix.cpp` because the legacy NMAKE project lists every object explicitly. `src/Aix.h`, `src/GameFlow.cpp`, `src/ui.cpp`, and `src/Unit.cpp` provide the integration hooks and input isolation. `INSTALL_AI_TAKEOVER.cmd` performs build/install/launch where the historical tools are available.
