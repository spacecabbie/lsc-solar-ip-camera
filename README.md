# Low-power re-arm fix — internal review (LSC solar PTZ 3218152)

**Status:** review only. Not on the PR branch `lsc-solar-ptz-3218152`. Not installed on the SD card.

## Problem
On 2026-10-21 a `tuya.dat` firstboot re-arm rebuilt `factory/stone-main.bin` with low-power **kept** (`stone-main.bin.mode=1`).
`STONE_LOW_POWER=0` was requested, but on that boot neither `/stone/main` nor `/stone/.lsc-stock-main` existed.
`prepare_stone_main()` then took the "stock Tuya executable not found; using SD copy" branch and returned
straight away, so it launched the SD copy unchanged with low-power still on. It had to be fixed by hand
(the copy was re-patched and `.mode` set from 1 to 0).

## Change (only file: `custom/scripts/entrypoint_t23.sh`)
1. New helper `ensure_sd_stone_mode()`:
   - copies `stone-main.bin` to `stone-main.bin.tmp` and runs `patch_stone` on it (no `--keep-low-power` when `STONE_LOW_POWER=0`).
     `patch_stone_main` rewrites the low-power word in place on an already-patched binary and validates the layout.
   - If the result differs, it atomically `mv`s it over `stone-main.bin` and logs `re-patched SD Tuya executable to low power=0 (was mode=1)`.
   - It writes `stone-main.bin.mode` = requested mode, then `sync`, and logs `SD Tuya executable verified at low power=…`.
   - If the patch fails or validation fails, it deletes the tmp, leaves the binary untouched and logs a `WARNING:` line.
     It never leaves a half-written executable.
2. The SD-copy branch of `prepare_stone_main()` now calls `ensure_sd_stone_mode` instead of returning immediately.
   It returns 1 only if no SD copy exists at all (same as before).
3. The stock-present path is unchanged. It already rebuilds when the saved mode differs from the requested one.

Unchanged: `STONE_LOW_POWER=0`, `TUYA_TRACK_ENABLE=1`, `TUYA_HUM_ON_OFF=1`, and all other switches.
The patch is idempotent: on a normal boot it only re-validates the binary, with no write.

## Known limit
If a stock binary exists but copying or patching it fails, the script still falls back to the *unmodified stock*
binary (existing behaviour, logged). That binary has stock low-power behaviour.

## Verify
- `sh -n entrypoint_t23.sh` passes. A box simulation with a fake patcher, SD copy only and mode=1 ended with the binary at LP=0
  and mode=0. The second run made no rewrite.
- On the camera after install + reboot: `grep -E "SD Tuya executable|low power" /tmp/mnt/sdcard/<logdir>/main.log`,
  `cat /tmp/mnt/sdcard/factory/stone-main.bin.mode` → `0`,
  `/tmp/mnt/sdcard/custom/bin/patch_stone_main --check /tmp/mnt/sdcard/factory/stone-main.bin` → low-power branch disabled.

## Files
- `files/custom/scripts/entrypoint_t23.sh`: proposed (md5 8dedf46c71757df415e28116d181d9a2)
- `diffs/entrypoint_t23.sh.before`: current live SD version (md5 cb6d40540b1a96cd38d16184edac9250)
- `diffs/entrypoint_t23.sh.diff`: unified diff

## Install (not done; needs approval)
Back up the live file as `entrypoint_t23.sh.bak-prelp`, copy the new one, check the md5 and `sync`. It takes effect on the next boot.
No immediate reboot is needed, because the live camera is already at mode=0 (fixed by hand).
