# sd_pen_windows (Phase 6, not yet implemented)

C++ native pen plugin for Windows. Exposes `PenSample` via EventChannel and
a capability/config MethodChannel, per `sigmadraw-implementation-prompt.md` §7.

Primary path: verify Flutter's own WM_POINTER stylus delivery (pressure +
rotation reach `PointerEvent`; requires Wacom "Use Windows Ink" = ON). If
insufficient, implement WM_POINTER directly (`EnableMouseInPointer`,
`WM_POINTERDOWN/UPDATE/UP`, `GetPointerType`/`GetPointerPenInfo`).

Secondary path: WinTab (`Wintab32.dll`, `WTOpen`/`WTPacket`) for tilt/twist/
buttons/eraser and for users with Ink turned off — hook the FlutterView HWND
via `RegisterTopLevelWindowProcDelegate`. Let the user choose Ink vs WinTab.

Scaffold with `flutter create --template=plugin --platforms=windows` when
this phase starts.
