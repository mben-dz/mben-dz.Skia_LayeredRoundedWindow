## RoundedWinApiForm - Delphi 13 Florence Skia 2D Layered Window

OVERVIEW:
This production-grade Delphi project demonstrates how to build a modern, high-performance,
hardware-accelerated round-corner layered window using Skia 2D without requiring visual
VCL or FMX form files. The application runs from a headless Console backend ({$APPTYPE CONSOLE}),
allocates a 32-bit ARGB DIBSection, wraps it inside an Skia 2D surface (TSkSurface.MakeRasterDirect),
and presents smooth anti-aliased rounded corners, drop shadows, glassmorphism cards, and interactive
buttons to Windows using the Win32 UpdateLayeredWindow API.

![](https://github.com/mben-dz/mben-dz.Skia_LayeredRoundedWindow/blob/main/snapshot.jpg)

FEATURES:
1. Zero-Copy Skia Raster Pipeline:
   - Skia draws directly into the DIBSection memory buffer used by UpdateLayeredWindow.
2. Anti-Aliased Rounded Corners & Soft Drop Shadow:
   - Uses Skia's TSkRoundRect and TSkMaskFilter.MakeBlur for realistic, soft translucent shadows.
3. Interactive Win32 Controls:
   - Close [X], Minimize [-], Action Button ("Dispatch Console Ping"), and Native Window Dragging.
4. Dynamic Animation Engine:
   - High-precision 60 FPS heartbeat with pulsating glow indicators and real-time FPS counter.
5. Robust Command-Line Parser:
   - Configure window geometry, corner radius, alpha transparency, and custom hex themes on the fly.

COMPATIBILITY:
- Delphi Target: RAD Studio 13 Florence / RAD Studio 12 Athens
- Operating System: Windows 10 / Windows 11 (64-bit and 32-bit)
- Skia Requirement: Skia is included natively in RAD Studio 12+. Ensure Skia is enabled in Project Options.

HOW TO BUILD & RUN:
1. Open Delphi (RAD Studio Florence 13 / Athens 12).
2. Open "RoundedWinApiForm.dpr" from the project root.
3. Ensure Skia is enabled:
   - Right-click the project in Project Manager -> "Enable Skia" (or ensure Skia unit is in search path).
4. Set Target Platform to "Windows 64-bit" (or "Windows 32-bit").
5. Build and Run (F9 or Shift+F9).

COMMAND LINE USAGE EXAMPLES:
- Run with default settings:
    RoundedWinApiForm.exe

- Custom size and extra smooth corner radius:
    RoundedWinApiForm.exe -w 900 -h 550 -r 40

- Custom colors and title:
    RoundedWinApiForm.exe -t "My Cloud Monitor" --color-accent #10B981 --alpha 245

- Disable shadow for compact borderless look:
    RoundedWinApiForm.exe --no-shadow -r 16

- View CLI help:
    RoundedWinApiForm.exe --help

[snapshot Help](https://github.com/mben-dz/mben-dz.Skia_LayeredRoundedWindow/blob/main/snapshot2.jpg)

INTERACTION:
- Move: Click and drag anywhere on the window background.
- Test Action: Click "Dispatch Console Ping" to log real-time messages to the attached console.
- Exit: Click the [X] button or press the [ESC] key.

![Snapshot Vcl](https://github.com/mben-dz/mben-dz.Skia_LayeredRoundedWindow/blob/main/VCL/snapshot.jpg)

ARCHITECTURE:
- RoundedWinApiForm.dpr   : Console entry point & message loop executor.
- API.Types.pas            : Data structures, UI states, and interface definitions.
- API.CommandLine.pas      : Robust CLI arguments parser.
- API.SkiaRenderer.pas     : Skia 2D canvas, round rect, shadow, and UI rendering logic.
- API.LayeredWindow.pas    : Win32 Layered Window lifecycle, DIBSection management, and input dispatching.
