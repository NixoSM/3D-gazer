# Android

Nothing in the game code is iOS-specific, so an Android build is mostly
packaging. Platform calls (haptics, keeping the screen on) go through
`src/platform/platform_services.gd`; input (accelerometer, touch) uses
Godot's cross-platform APIs.

## Steps

1. Install the Android SDK/JDK as described in Godot's docs ("Exporting for Android") and set the paths in Editor Settings.
2. Install export templates, open **Project → Export → Android** (preset already present).
3. Change `package/unique_name` from `com.example.gazer`, create a release keystore, export the APK/AAB.

## Expect to tune

- **Tilt sign**: Android and iOS report accelerometer axes differently in
  some Godot versions. Check the direction first (pause → invert tilt), then
  fix the default per platform in `TiltReader` with `OS.get_name()`.
- **Haptics**: Android motors vary a lot. Durations/amplitudes are in
  `PlatformServices.HAPTIC_PATTERNS`; the `VIBRATE` permission is enabled in the preset.
- **Performance**: low-end GPUs may need the Compatibility renderer
  (`rendering/renderer/rendering_method.mobile="gl_compatibility"`). The
  shaders are unshaded and render identically on both.
- **Back button**: map it to pause in `Main._unhandled_input` (`ui_cancel`).
