# PTZ support for the LSC solar PTZ camera (3218152): review

Review-only branch with no upstream history. It explains the PTZ changes proposed
for [Niek/lsc-solar-ip-camera](https://github.com/Niek/lsc-solar-ip-camera). The
integrated version is on branch `lsc-solar-ptz-3218152`: upstream `main` plus
one commit.

Tested on: LSC Smart Solar Outdoor PTZ, Action article 3218152, firmware
V1.0.0(6.2163.49), Ingenic T23ZN, SC3332 sensor.

## Hardware background

The pan/tilt steppers are driven by an MS32008 (Ruimeng MS32008N) motor chip on
`/dev/i2c-1`, address `0x10`. Channel A is tilt and channel B is pan. Stock
`stone-main` writes 9 registers to start a move and 7 to stop it, and the chip
keeps a signed step counter. Speed register = 15 MHz / (16 × pps); stock speed
is 1500 pps. The camera has no end-stop sensors (stock firmware also homes
blind), so position is tracked in software.

## Files

| File in this branch | Goes to (repo) | Installed on SD | Purpose |
| --- | --- | --- | --- |
| `files/tools/src/ms32008v2.c` | `tools/src/ms32008v2.c` (new) | `custom/bin/ms32008v2` | Small static I2C helper. `--go start <pan\|tilt> <dir> <q> [pps]`, `--go stop`, `--go count`. Without `--go` it only prints (dry run). Touches only i2c-1 / 0x10. |
| `files/tools/ptz/ptz2.sh` | `tools/ptz/ptz2.sh` (new) | `custom/scripts/ptz2.sh` | ONVIF hook script called by `onvif_simple_server`. Tracks position in `custom/ptz_pos`, stores presets in `custom/ptz_presets`, logs to `logs/ptz2.log`. |
| `diffs/compile.sh.diff` | `tools/compile.sh` | n/a | Builds `ms32008v2` with the same flags as the other helpers. |
| `diffs/build_tuya_dat_overflow.py.diff` | `tools/build_tuya_dat_overflow.py` | n/a | Adds an opt-in `--ptz` flag. It switches `ptz=0` to `ptz=1`, adds the PTZ hooks to `onvif_simple_server.conf`, and copies the helper and script. Without `--ptz`, output is unchanged. |
| `diffs/README.md.diff` | `README.md` | n/a | New "PTZ (solar PTZ model 3218152)" section plus a repository-layout line. |

## Usage

```sh
./tools/compile.sh
./tools/build_tuya_dat_overflow.py --no-trigger --ptz /tmp/lsc-solar-payload
```

## Supported ONVIF PTZ operations

| Operation | Units / behaviour |
| --- | --- |
| ContinuousMove / Stop | velocity `-1..1` (maps to 300..1500 pps); runs to the soft limit until Stop |
| RelativeMove | TranslationGenericSpace `-1..1` = fraction of full travel (x>0 right, y>0 up). A half-view tap is about pan 0.13 and tilt 0.30. |
| AbsoluteMove, GetStatus | PositionGenericSpace `0..1` (0 = left / bottom stop) |
| GetPresets, SetPreset, GotoPreset, RemovePreset | `PresetToken_1`..`PresetToken_7` |
| SetHomePosition, GotoHomePosition | default home is the centre |
| Zoom | not available (no zoom hardware) |
| Preset tours | not implemented (not in onvif_simple_server) |

Internal range: pan 0..8000 and tilt 0..2300 quarter-steps, with a 50-step soft
margin. Moves are rounded to whole steps (multiples of 4).

## Calibrate (preset 8)

`PresetToken_8` (`Calibrate`) is reserved and cannot be overwritten. It moves
gently (400 pps) into the left and bottom stops, zeroes the position, then
returns home. Run it once after install, or whenever the position drifts.

Emergency stop from telnet: `/tmp/mnt/sdcard/custom/bin/ms32008v2 --go stop`

## Undo

Rebuild the payload without `--ptz`, or set `ptz=0` in
`custom/onvif/onvif_simple_server.conf`, then restart. Optionally delete
`custom/bin/ms32008v2`, `custom/scripts/ptz2.sh`, `custom/ptz_pos` and
`custom/ptz_presets`.

## Diffs

### compile.sh

````diff
diff --git a/tools/compile.sh b/tools/compile.sh
index aa11a8b..4b4536d 100755
--- a/tools/compile.sh
+++ b/tools/compile.sh
@@ -85,6 +85,12 @@ docker "${run_args[@]}" "$IMAGE" sh -eu -c '
     -o build/mipsel/bin/patch_stone_main \
     tools/src/patch_stone_main.c
 
+  mipsel-linux-gnu-gcc \
+    -mips32r2 -mabi=32 -static -Os -s \
+    -Wall -Wextra -Werror \
+    -o build/mipsel/bin/ms32008v2 \
+    tools/src/ms32008v2.c
+
   onvif_src=build/third_party/onvif_simple_server
   onvif_build=build/mipsel/onvif_simple_server
   rm -rf "$onvif_build"
@@ -130,6 +136,7 @@ docker "${run_args[@]}" "$IMAGE" sh -eu -c '
   file build/mipsel/bin/stone_dump_relay
   file build/mipsel/bin/onvif_cgi_httpd
   file build/mipsel/bin/patch_stone_main
+  file build/mipsel/bin/ms32008v2
   file build/mipsel/bin/onvif_simple_server
   file build/mipsel/bin/onvif_notify_server
   file build/mipsel/bin/wsd_simple_server
````

### build_tuya_dat_overflow.py

````diff
diff --git a/tools/build_tuya_dat_overflow.py b/tools/build_tuya_dat_overflow.py
index 4b9548d..b61aa53 100755
--- a/tools/build_tuya_dat_overflow.py
+++ b/tools/build_tuya_dat_overflow.py
@@ -567,6 +567,31 @@ done
 """
 
 
+PTZ_CONFIG = """ptz=1
+min_step_x=0
+max_step_x=1
+min_step_y=0
+max_step_y=1
+min_step_z=0
+max_step_z=0
+move_left=/tmp/mnt/sdcard/custom/scripts/ptz2.sh left %f
+move_right=/tmp/mnt/sdcard/custom/scripts/ptz2.sh right %f
+move_up=/tmp/mnt/sdcard/custom/scripts/ptz2.sh up %f
+move_down=/tmp/mnt/sdcard/custom/scripts/ptz2.sh down %f
+move_stop=/tmp/mnt/sdcard/custom/scripts/ptz2.sh stop
+jump_to_rel=/tmp/mnt/sdcard/custom/scripts/ptz2.sh rel %f %f %f
+jump_to_abs=/tmp/mnt/sdcard/custom/scripts/ptz2.sh abs %f %f %f
+get_position=/tmp/mnt/sdcard/custom/scripts/ptz2.sh getpos
+is_moving=/tmp/mnt/sdcard/custom/scripts/ptz2.sh moving
+get_presets=/tmp/mnt/sdcard/custom/scripts/ptz2.sh presets
+move_preset=/tmp/mnt/sdcard/custom/scripts/ptz2.sh preset %d
+set_preset=/tmp/mnt/sdcard/custom/scripts/ptz2.sh setpreset %d %s
+remove_preset=/tmp/mnt/sdcard/custom/scripts/ptz2.sh rmpreset %d
+set_home_position=/tmp/mnt/sdcard/custom/scripts/ptz2.sh sethome
+goto_home_position=/tmp/mnt/sdcard/custom/scripts/ptz2.sh gohome
+"""
+
+
 ONVIF_CONFIG = """model=LSC Outdoor Camera
 manufacturer=LSC
 firmware_ver=LSC-T23-stock-plus-local
@@ -761,7 +786,20 @@ def copy_patch_helper(mount: Path) -> None:
     chmod_exec(dst)
 
 
-def copy_onvif_files(mount: Path) -> None:
+def copy_ptz_files(mount: Path) -> None:
+    root = Path(__file__).resolve().parents[1]
+    src = root / "build" / "mipsel" / "bin" / "ms32008v2"
+    if not src.is_file():
+        raise SystemExit(f"missing {src}; run ./tools/compile.sh first")
+    dst = mount / "custom" / "bin" / "ms32008v2"
+    shutil.copy2(src, dst)
+    chmod_exec(dst)
+    script = mount / "custom" / "scripts" / "ptz2.sh"
+    shutil.copy2(root / "tools" / "ptz" / "ptz2.sh", script)
+    chmod_exec(script)
+
+
+def copy_onvif_files(mount: Path, *, ptz: bool = False) -> None:
     root = Path(__file__).resolve().parents[1]
     bin_dir = root / "build" / "mipsel" / "bin"
     onvif_src = root / "build" / "third_party" / "onvif_simple_server"
@@ -792,7 +830,8 @@ def copy_onvif_files(mount: Path) -> None:
 
     dst_root = mount / "custom" / "onvif"
     dst_root.mkdir(parents=True, exist_ok=True)
-    (dst_root / "onvif_simple_server.conf").write_text(ONVIF_CONFIG, encoding="ascii")
+    config = ONVIF_CONFIG.replace("ptz=0\n", PTZ_CONFIG) if ptz else ONVIF_CONFIG
+    (dst_root / "onvif_simple_server.conf").write_text(config, encoding="ascii")
 
     for name in asset_dirs:
         src = onvif_src / name
@@ -823,7 +862,7 @@ def script_with_options(script: str, *, stone_low_power: bool) -> str:
     return script.replace("__STONE_LOW_POWER__", "1" if stone_low_power else "0")
 
 
-def write_mount(mount: Path, payload: bytes | None, *, stone_low_power: bool) -> None:
+def write_mount(mount: Path, payload: bytes | None, *, stone_low_power: bool, ptz: bool = False) -> None:
     if not mount.is_dir():
         raise SystemExit(f"mountpoint is not a directory: {mount}")
 
@@ -853,7 +892,9 @@ def write_mount(mount: Path, payload: bytes | None, *, stone_low_power: bool) ->
     copy_aic_filter(mount)
     copy_stream_relay(mount)
     copy_patch_helper(mount)
-    copy_onvif_files(mount)
+    copy_onvif_files(mount, ptz=ptz)
+    if ptz:
+        copy_ptz_files(mount)
 
 
 def main() -> int:
@@ -880,6 +921,8 @@ def main() -> int:
         action="store_true",
         help="build an update-only payload and ensure tuya.dat is absent",
     )
+    parser.add_argument("--ptz", action="store_true",
+                        help="enable ONVIF PTZ for the solar PTZ model (3218152, MS32008 motor driver)")
     parser.add_argument("mountpoint", nargs="?", help="SD card mountpoint to write")
     args = parser.parse_args()
 
@@ -897,7 +940,7 @@ def main() -> int:
         parser.error("provide a mountpoint")
 
     mount = Path(args.mountpoint)
-    write_mount(mount, payload, stone_low_power=args.stone_low_power)
+    write_mount(mount, payload, stone_low_power=args.stone_low_power, ptz=args.ptz)
 
     if payload is None:
         print(f"no trigger: ensured {mount / 'tuya.dat'} is absent")
````

### README.md

````diff
diff --git a/README.md b/README.md
index 089d45b..14761e6 100644
--- a/README.md
+++ b/README.md
@@ -222,6 +222,39 @@ Default ONVIF credentials:
 admin / admin
 ```
 
+## PTZ (solar PTZ model 3218152)
+
+The solar PTZ model drives its pan/tilt steppers with an MS32008 motor chip on
+`/dev/i2c-1` (address `0x10`). `tools/src/ms32008v2.c` replays the stock
+start/stop register bursts and reads the step counter; `tools/ptz/ptz2.sh`
+maps ONVIF PTZ hooks onto it. Build the payload with `--ptz` to enable it:
+
+```sh
+./tools/build_tuya_dat_overflow.py --no-trigger --ptz /tmp/lsc-solar-payload
+```
+
+This sets `ptz=1` plus the `move_*`, `jump_to_*`, preset and home hooks in
+`custom/onvif/onvif_simple_server.conf`, and installs `custom/bin/ms32008v2`
+and `custom/scripts/ptz2.sh`. Supported ONVIF operations:
+
+| Operation | Units |
+| --- | --- |
+| ContinuousMove / Stop | velocity `-1..1`; runs to the soft limit until Stop |
+| RelativeMove | TranslationGenericSpace `-1..1` = fraction of full travel (x>0 right, y>0 up) |
+| AbsoluteMove, GetStatus | PositionGenericSpace `0..1` (0 = left / bottom stop) |
+| GetPresets, SetPreset, GotoPreset, RemovePreset | `PresetToken_1`..`PresetToken_7` |
+| SetHomePosition, GotoHomePosition | default home is the centre |
+
+Zoom is not available (no zoom hardware). The camera has no end-stop
+sensors, so position is tracked in `custom/ptz_pos`. Preset 8 (`Calibrate`)
+is reserved: it gently bumps into the left and bottom stops, zeroes the
+position and returns home. Run it once after first install or if the
+position drifts. Emergency stop from telnet:
+`/tmp/mnt/sdcard/custom/bin/ms32008v2 --go stop`.
+
+To undo, rebuild the payload without `--ptz` (or set `ptz=0` in
+`custom/onvif/onvif_simple_server.conf`) and restart.
+
 ## Live update over the network
 
 After telnet is working, you can update the SD-card files without physically
@@ -295,6 +328,7 @@ tools/fetch_tuya_ota.py               Smart Life login and OTA downloader
 tools/wake_tuya_camera.py             Smart Life wake and preview keep-awake helper
 tools/push_camera_live.py             live network updater
 tools/compile.sh                      Docker based MIPS build
+tools/ptz/ptz2.sh                     ONVIF PTZ hooks for the solar PTZ model
 tools/src/                            small camera-side helpers
 tools/patches/                        ONVIF server portability patch
 ```
````

