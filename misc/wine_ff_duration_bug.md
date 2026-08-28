# Wine XInput vibration stops after ~1 s (HID `cutoff_time_ms=1000` + change-gated report)

**Product:** Wine — `dlls/xinput1_3` + `dlls/winebus.sys`
(git master; line numbers against current `wine-mirror/master`, may drift —
function names are the stable anchors)

## Summary

Calling `XInputSetState()` with a *constant* motor speed every frame (the normal
pattern to *hold* rumble, e.g. analog/trigger rumble) makes the controller
vibrate for only ~1000 ms and then stop. On real Windows the motors are held at
the requested speed until the next `XInputSetState`. XInput has no duration
field, so "hold until next SetState" is the defined contract.

## Expected

A constant `XInputSetState(l, r)` keeps the motors at those speeds until a
subsequent call changes them (including to 0). No periodic re-call should be
required.

## Observed

Rumble plays ~1 s then ceases; it only resumes if the requested speed *value*
actually changes between calls.

## Root cause

The path is `XInputSetState → HID Simple-Haptics output report → winebus →
evdev FF_RUMBLE`. Two mechanisms combine:

### 1) XInput → HID: change-gated report emission

- `dlls/xinput1_3/main.c:832` `XInputSetState()` → `:847` `HID_set_state()`
- `dlls/xinput1_3/main.c:284` `HID_set_state()`:
  - `:296` `update_rumble = (controller->vibration.wLeftMotorSpeed != state->wLeftMotorSpeed);`
  - `:298` `update_buzz   = (controller->vibration.wRightMotorSpeed != state->wRightMotorSpeed);`
  - `:302` `if (!update_rumble && !update_buzz) return ERROR_SUCCESS;` ← no HID report emitted when speed is unchanged
  - Introduced by commit `57aaa274d9016420797d63250620aa228323d83f`
    *"xinput1_3: Only write haptics waveform reports when needed."*

### 2) HID → evdev: hardcoded 1000 ms cutoff + second change-gated dedup

- `dlls/winebus.sys/hid.c` — haptic waveforms initialized with a fixed cutoff:
  - `:460` `rumble.cutoff_time_ms = 1000;`  `:463` `buzz.cutoff_time_ms = 1000;`
  - `:466` `left.cutoff_time_ms = 1000;`  `:469` `right.cutoff_time_ms = 1000;`
- `dlls/winebus.sys/hid.c` — on each haptics output report:
  - `:1228-1230` `duration_ms = min(rumble/buzz/left/right cutoff_time_ms)` → **1000**
  - `:1231` `haptics_start(iface, duration_ms, ...)` ← passes 1000 ms to the backend
- `dlls/winebus.sys/bus_udev.c`:
  - `:796` `impl->haptics.type = FF_RUMBLE;`
  - `:797` `impl->haptics.replay.length = duration_ms;` ← **evdev `FF_RUMBLE` duration = 1000 ms**
  - `:714` haptics thread: `while (!memcmp(&effect, &impl->haptics, sizeof(effect))) wait;` ← effect only re-uploaded when its value changes

## Net effect

A constant `XInputSetState` produces at most one evdev `FF_RUMBLE` with
`replay.length = 1000`. After ~1 s the kernel effect expires; both layers dedup
identical values (`xinput1_3/main.c:302`, `bus_udev.c:714`), so the hold is
never refreshed. The 1000 ms figure is entirely Wine's invention — XInput
carries no duration. A correct implementation must hold the motors until the
next `SetState` (an `FF_RUMBLE` submitted with `replay.length = 0` is held by
the evdev/ff-memless stack until stopped).

## Scope note

This manifests specifically with **XInput** (contract = "hold until next
SetState", no duration). The 1000 ms cap lives in the *common* winebus HID
layer (`hid.c`), so any backend through it (udev/SDL) is affected; the extra
dedup at `bus_udev.c:714` is udev-specific. DirectInput/PID FF is a separate
path, out of scope.

## Suggested fix direction

- **Minimal correct fix:** for XInput-sourced haptics, use an open/infinite
  `replay.length` (0) instead of the HID `cutoff_time_ms`. Concretely, in
  `dlls/winebus.sys/hid.c` the XInput haptic waveform `cutoff_time_ms` should be
  0/infinite (so `duration_ms` at `:1228-1230` becomes 0 and `bus_udev.c:797`
  sets `replay.length = 0`). With this, the single uploaded effect holds until
  the next `SetState`; the change-gating at `xinput1_3/main.c:296-302` becomes a
  non-issue (it merely skips redundant re-emission of an already-holding
  effect).
- **Dropping only the change-gating is insufficient:** `replay.length` remains
  hardcoded to 1000, so a constant hold still decays after 1 s and still
  requires re-calling within each second — the API contract is not respected.
  The udev dedup at `bus_udev.c:714` would also still suppress re-uploads of
  identical values.

## Environment

Wine git master; Linux; evdev gamepad (xpad/xpadneo). Reproduced with a minimal
`XInputSetState(0, {60000,30000})` loop — rumble stays on *only* while the value
changes each call, confirming the dedup.
