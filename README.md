# Entrypoint feature switches for the LSC solar PTZ (3218152): review

Review-only branch with no upstream history. It documents a version of the toolkit's
`entrypoint_t23.sh` that declares every known camera feature switch as a
variable at the top of the script and applies them at boot, before `stone-main`
starts.

Tested on: LSC Smart Solar Outdoor PTZ, Action 3218152, firmware V1.0.0(6.2163.49), Ingenic T23ZN.

## Files

| File | Purpose |
| --- | --- |
| `files/entrypoint_t23.sh` | The new script. Installs to `custom/scripts/entrypoint_t23.sh` on the SD card. |
| `diffs/entrypoint_t23.sh.diff` | Unified diff against upstream. |

**Where upstream keeps it:** Niek's repo has no separate `entrypoint_t23.sh`
file. The script is the `T23_ENTRYPOINT` string inside
`tools/build_tuya_dat_overflow.py`, and `__STONE_LOW_POWER__` is filled in
at build time. The diff is against upstream `main` (3160dad) rendered with
`--no-low-power`. The camera's previous SD copy was **byte-identical** to that
rendering, so the SD copy did not differ from upstream. For a real PR, the
change would go into the `T23_ENTRYPOINT` string, keeping the
`__STONE_LOW_POWER__` placeholder.

## How the switches work

- Each `TUYA_*` variable maps to one file in `/config/tuya/` (stock Tuya settings).
- **Empty value (`VAR=`) = leave that file untouched.** Any other value is written to the file with `printf "%s\n"` at boot.
- The existing `configure_tuya_motion()` call (name kept for upstream call-site compatibility) now applies all of the switches.
- **A reboot is needed.** Stock `stone-main` reads these files at init. Writing a file while it runs does not call the internal setter (for tracking, the live gate uses a RAM global).
- **Origin:** *Niek* = already set by the upstream toolkit. *Custom* = added in this change. All files are stock Tuya firmware settings. Only the boot-time management of the custom ones is new.

## Switches

DP numbers come from the Tuya IPC SDK DP table, cross-checked against
firmware report and setter references. "—" = no DP identified. *(guess)*
marks values that are not confirmed.

| Variable | Default here (upstream) | Values | Config file | Tuya DP | Origin | Effect / notes |
| --- | --- | --- | --- | --- | --- | --- |
| `STONE_LOW_POWER` | `0` (build flag; default build = 1) | 1 / 0 | (`factory/stone-main.bin.mode`) | — | Niek | Patcher mode for the SD copy of `stone-main`. `1` keeps Tuya's low-power (PIR wake) path; `0` is the high-power patch that keeps Linux awake and uses RTSP byte-motion. **Not a battery on/off switch.** |
| `TUYA_TRACK_ENABLE` | `1` (not set) | 0 / 1 | `tuya_track_enable` | 161 | Custom | Person tracking: the PTZ follows PersonDet boxes. Needs `TUYA_HUM_ON_OFF=1` to be useful. **Battery gate:** firmware forces tracking off (and rewrites the file to 0) when `/config/common/adc_percent` < 30, so it needs ≥ 30 %. |
| `TUYA_HUM_ON_OFF` | `1` (`0`) | 0 / 1 | `tuya_hum_on_off` | 170 | Niek | Human (person) detection (Ingenic PersonDet); feeds alarms and tracking. Upstream forced it off on every boot. |
| `TUYA_MOTION_SWITCH` | empty | 0 / 1 | `tuya_motion_switch` | 134 | Custom | Motion detection switch. The file is usually absent (firmware default; how a missing file is read is unconfirmed). |
| `TUYA_SIREN_ONOFF` | `0` | 0 / 1 | `tuya_siren_onoff` | 159 | Custom | Siren. |
| `TUYA_IPC_AUTO_SIREN` | empty | 0 / 1 | `ipc_auto_siren` | 234 | Custom | Siren on alarm events. Whether the file path is used is unconfirmed *(guess)*. |
| `TUYA_LIGHT_ONOFF` | `1` | 0 / 1 | `tuya_light_onoff` | 101 | Custom | White/flood light. |
| `TUYA_WHITE_LIGHT_MODE` | empty | enum | `tuya_white_light_mode` | — | Custom | White-light mode; enum values not mapped. |
| `TUYA_BLUB_ON_OFF` | empty | 0 / 1 | `tuya_blub_on_off` | 138 | Custom | Indicator LED (name-only in firmware). |
| `TUYA_SLEEP_MODE` | `0` | 0 / 1 | `tuya_sleep_mode` | 105 | Custom | Privacy / sleep mode (lens park). |
| `TUYA_PIR_ON_OFF` | `1` (`1`) | 0 / 1 | `tuya_pir_on_off` | — | Niek | PIR wake. |
| `TUYA_PIR_SENS` | `1` (`1`) | typically 0–2 | `tuya_pir_sens` | — | Niek | PIR sensitivity. |
| `TUYA_RECORD_TIME` | `2` (`2`) | number | `tuya_record_time` | — | Niek | SD event record duration. No matching string in the .49 binary, so it may be unused *(guess)*. |
| `TUYA_FLIP_ONOFF` | `0` (`0`) | 0 / 1 | `tuya_flip_onoff` | 103 | Niek | Image flip. |
| `TUYA_WATERMARK_ONOFF` | `0` (`0`) | 0 / 1 | `tuya_watermark_onoff` | 104 | Niek | OSD watermark. |
| `TUYA_NIGHT_MODE` | `1` | enum | `tuya_night_mode` | — | Custom | Night-vision mode (current value 1). |
| `TUYA_ALARM_LINKAGE` | `3` | 0–3 | `tuya_alarm_linkage` | — | Custom | Alarm linkage enum (current value 3). |
| `TUYA_ANTI_FLICK` | `1` | enum | `tuya_anti_flick` | — | Custom | Anti-flicker (current value 1). |
| `TUYA_VIDEO_LIVE_CLARITY` | `0` | number | `tuya_video_live_clarity` | — | Custom | Live stream clarity. No binary string, so it may be unused *(guess)*. |
| `TUYA_MOTION_SD_RECORD` | empty | 0 / 1 | `tuya_motion_sd_record` | 239 | Custom | Record to SD on motion. |
| `TUYA_HUMAN_SD_RECORD` | empty | 0 / 1 | `tuya_human_sd_record` | 241 | Custom | Record to SD on human detection (combined with the track/hum flag). |
| `TUYA_SD_RECORD_ON_OFF` | empty | 0 / 1 | `tuya_sd_record_on_off` | 150 | Custom | Continuous SD recording. |
| `TUYA_DEV_VOLUME` | empty | number | `tuya_dev_volume` | 160 | Custom | Speaker volume. |
| `TUYA_LOW_POWER_VALUE` | empty | number | `low_power_value` | — | Custom | Tuya low-power threshold file. Exact semantics unconfirmed *(guess)*. **Not a battery master switch.** |

Defaults with "current value" are the values read live from the camera on 2026-10-20.

Non-switch toolkit settings (`TELNET_PORT`, `ONVIF_PORT`, `AIC_FILTER_SECONDS`,
`LOW_POWER_MOTION_*`, `LOG_*`) are unchanged upstream values; they were moved
under the switch block.

### Battery

**No battery on/off switch exists**, neither in stock firmware nor in the
toolkit. Battery percentage is read-only (`/config/common/adc_percent`). The
only related settings are `STONE_LOW_POWER` (patch mode) and
`low_power_value` (threshold, semantics unconfirmed).

## Apply / undo

Apply: copy `files/entrypoint_t23.sh` to
`/tmp/mnt/sdcard/custom/scripts/entrypoint_t23.sh` (keep a backup of the old
file first, e.g. `entrypoint_t23.sh.bak-orig`), `sync`, edit variables as
wanted, then **reboot** the camera.

Undo: copy the backup back over `entrypoint_t23.sh`, `sync`, reboot. Files
written to `/config/tuya/` keep their last values. To revert a setting, set it
explicitly (e.g. `TUYA_TRACK_ENABLE=0`, `TUYA_HUM_ON_OFF=0`) for one boot, or
write the file by hand.
