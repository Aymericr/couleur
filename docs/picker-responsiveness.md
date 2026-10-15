# Picker focus and responsiveness

Build 9 applies the first part of the [Multi research](multi-macos-research.md). The focus contract follows [Multi's activation article](https://multi.app/blog/nailing-the-activation-behavior-of-a-spotlight-raycast-like-command-palette): borrowing keyboard focus for a utility should not require activating its owning app.

## Behavior

- The custom magnifier is a nonactivating `NSPanel` and no longer calls `NSApp.activate`. Dismissing it orders out its panels without activating a previously recorded application. A deliberate switch to a different app is respected.
- The compact picker and magnifier opt into `canJoinAllApplications`, alongside their existing Space and full-screen auxiliary behavior. The expanded library keeps its normal window behavior.
- Escape, right-click, application activation changes, and display changes finish the custom session and clean up its event monitors, frozen images, panels, and hidden cursor. Workspace activation is observed because an already-inactive Couleur cannot receive another resign-active notification.
- Shift continues the same session. Every selection is saved before it is reported as saved and copied. Website lookup remains asynchronous and follows the original source window.
- The built-in AppKit fallback retains its existing presentation timing. Its callback bridge discards values delivered after task cancellation. There is no new Accessibility or Input Monitoring permission.

## Local measurements

`PickPerformance` uses OS signposts and unified logging in subsystem `com.aymeric.couleur`, category `Picking`. These are local diagnostics; no colors, application names, window titles, or URLs are logged.

| Marker | Boundary |
| --- | --- |
| `PickSession` | Invocation through cleanup; includes the user's choosing time. |
| `PickToLoupeDraw` | Invocation through the first completed magnifier draw. A cancelled or fallback session ends with an explicit “ended before drawing” annotation. This is an AppKit draw, not a measurement of physical screen presentation. |
| `SourceWindows` | Snapshot of provenance window information. |
| `KeepPickedColor` | A delivered sample through the synchronous save and optional copy. Does not include earlier capture preparation or waiting for input. |
| `SavePickedColor` | Store commit, including validation, backup, atomic disk write, and publishing the saved library. |
| `CopyPickedColor` | Clipboard write and copy feedback state. Inspect the app's error state separately; interval completion alone is not proof of a successful clipboard write. |
| `NativeSamplerRequested` | Request to AppKit; its private UI supplies no first-draw callback. |

Observe with Instruments' signpost instrument, or stream the local log:

```sh
/usr/bin/log stream --style compact --level info \
  --predicate 'subsystem == "com.aymeric.couleur" AND category == "Picking"'
```

The finish log records only whether the foreground process stayed the same and whether Couleur reports itself active. These are diagnostic observations, not a substitute for checking real keyboard focus and app switching.

## Reproduce storage measurements

```sh
mkdir -p build
swiftc -O -parse-as-library Sources/CouleurCore/*.swift \
  scripts/benchmark-library.swift -o build/benchmark-library
build/benchmark-library
```

The benchmark creates synthetic libraries in a unique temporary directory, warms up five saves, and measures 30 more writes per size, including the prior-version backup. It never opens the real library. Results on the development Mac on October 15, 2026:

| Colors | p50 | p95 |
| ---: | ---: | ---: |
| 100 | 1.70 ms | 2.01 ms |
| 1,000 | 13.56 ms | 15.61 ms |
| 10,000 | 135.69 ms | 139.70 ms |

These are optimized storage-only measurements with modest synthetic metadata, not end-to-end picker timings or guarantees for every Mac. At 10,000 colors, synchronous persistence is worth a separate investigation into serialized background writes and failure recovery. This pass retains the existing durable-save contract.

## Validation

- 67 automated tests, including native-sampler cancellation after a late callback, exact sRGB conversion, and cancellation before loupe preparation completes.
- Isolated native preview: Escape restores the compact window without adding a color; Shift-Return retains the loupe, the final Return closes it, and both picks appear in recent history. Pasting the final color into TextEdit confirms the RGB clipboard value.
- Compact rendering inspected in light and dark appearances. Existing direct Pick color, Capture area, and Open image actions remain visible.
- Signed release build 9 installed and relaunched. The real screen magnifier opened from the expanded library and Escape returned to that library without adding a color; a single cold invocation reached its first draw in 241 ms. Compact/library morphing still worked. The saved library remained byte-for-byte unchanged: 83 colors, 3 captures, and 1 collection.
- Three fixture-preview invocations recorded first draws at 41–81 ms; two saves took 13–14 ms in the debug app and clipboard updates took 0.3–0.6 ms. These are smoke observations, not a representative performance distribution, and exclude real screen-capture preparation.
- Automation sends app-targeted input. It could not exercise the system-wide hotkey or reliably switch the foreground application. The built-in system sampler also exposes no usable window to this automation; that preview was closed through Activity Monitor. Its existing presentation delay was retained. Global hotkey return focus, Cmd-Tab cancellation, full-screen Spaces, Stage Manager, and multiple displays remain manual validation cases.

Preview commands (separate data and preferences):

```sh
scripts/preview.sh light --loupe /path/to/fixture.png
scripts/preview.sh dark --loupe /path/to/fixture.png
# Exercise the AppKit fallback without changing Screen Recording settings:
COULEUR_PREVIEW_NATIVE_SAMPLER=1 scripts/preview.sh dark
```

For a manual focus check, begin in another app's editable document, invoke the installed picker with Control-Option-C, then pick or cancel and immediately type or paste. Repeat from the compact window and the expanded library; opening the library intentionally activates Couleur. During picking, Cmd-Tab to another app and confirm the loupe disappears without pulling focus back. Test Shift picks, a quick drag release, right-click, screen-edge pixels, and display removal separately. Keep test colors in the preview whenever possible.
