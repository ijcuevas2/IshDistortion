# sd_pen_linux (Phase 6, not yet implemented)

C/GTK native pen plugin for Linux. Uses GDK device + axis handling and
libinput tablet-tool events. X11 reads tilt/pressure via XInput2 valuators;
Wayland's `tablet_v2` protocol is not exposed by the desktop embedder by
default (flutter/flutter#63209) — detect and degrade gracefully to
mouse/touch + pressure inference on Wayland until that's addressed upstream.

Scaffold with `flutter create --template=plugin --platforms=linux` when this
phase starts.
