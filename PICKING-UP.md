# Picking up the DevTerm A04 image work

Handoff note for the next agent.  Everything below was learned the hard way in
November 2026; where a fact is surprising, say so out loud in a future commit
message so it does not get re-learned.

## State at handoff

- Repo: `jasonbot/devterm-a04-modernized`, branch `main`, HEAD `fd2aa47`,
  clean working tree.
- Recent commits (oldest first): `2d093ad` devterm-web kiosk-mode argument,
  `1e5632a` Ly battery + Wi-Fi labels, `9f10960` Ly LuaJIT low-memory fix,
  `02c1a47` starburst animation, `3bf6a98` starburst flickering tail,
  `c305924` WordGrinder + Microsoft Edit, `1440000` battery right-aligned with
  glyph, `fd2aa47` FM-1 udev rule.
- **The SD-card image in `artifacts/` is stale.**  Every Ly/app/udev change
  above is committed in `overlay/` and `scripts/` but has not been baked into
  `artifacts/devterm-a04.img` yet.  `make image` (or `./build.sh`) fixes that;
  `make verify` checks the result.
- The running DevTerm was updated live and verified manually, then it became
  unreachable over SSH at handoff time (most likely suspended by
  `devterm-idle-suspend`; press a key/power on the device to wake it).  Do not
  assume live-device state without re-checking.

## What this project is

A rootless-built Debian trixie (arm64) **live image** for the ClockworkPi
DevTerm A04 (Allwinner H6).  Console-first: kmscon on tty1 with **Ly** as the
login manager, tmux attached to console logins, no X/Wayland by default, the
vendor 5.10 kernel for panel/backlight/audio/printer support.

Read `README.md` (features), `BUILD.md` (how to build), `USAGE.md` (user-facing
behaviour), `docs/HARDWARE.md` (A04 hardware truths).

## Repo map

| Path | What it is |
|---|---|
| `scripts/fetch.sh` | downloads upstream tarballs/binaries into `artifacts/src`, verifies checksums, stages fonts |
| `scripts/build-{uboot,kmscon,ly,chawan,image,rootfs}.sh` | one stage each; `build-ly.sh` builds Ly in an arm64 Zig container |
| `scripts/customize-rootfs.sh` | runs inside mmdebstrap: copies `overlay/.` into the rootfs, stages `artifacts/*` into `/opt/devterm-payload` |
| `scripts/rootfs-install.sh` | runs in the chroot: installs payload binaries, fonts, services, config |
| `scripts/verify-image.sh` | mounts the ext4 image with `debugfs` and asserts files/strings exist |
| `overlay/` | the actual config: `etc/`, `usr/local/bin/devterm-*`, `usr/local/sbin/`, `usr/lib/systemd`, `boot/` |
| `patches/` | source patches applied at build time (`ly-lock-state.patch`, `ly-lua-lowmem.patch`, `kmscon-a04-pad.patch`) |
| `build/` | gitignored upstream working copies (Ly source with patches applied, kmscon, chawan, Zig toolchain) |
| `artifacts/` | gitignored outputs (`ly/ly`, `edit/edit`, the `.img`) |

`build/` is a *dirty* checkout: patches are already applied in place
(`git -C build/ly-src status` shows modified files).  Regenerate a patch with:

```sh
git -C build/ly-src add -N ly-core/src/lowmem.zig   # once, for the new file
git -C build/ly-src diff -- ly-core/src/root.zig ly-core/src/lowmem.zig \
    src/animations/Lua.zig > patches/ly-lua-lowmem.patch
```

## Talking to the device

- Host alias `devterm-a04`, user `devterm`, password `devterm` (also
  `root`/`devterm`; sudo is passwordless for `devterm`).
- Command style used throughout: `SSHPASS=devterm sshpass -e ssh
  devterm@devterm-a04 '...'`, and `sshpass -e scp` for files.
- The console runs a tmux session named `login`; `tmux capture-pane -p -S -400
  -t login` shows what the user was doing, which is very handy when they
  report an error you cannot reproduce.
- If SSH times out: the A04 likely suspended (idle suspend is enabled) or Wi-Fi
  dropped.  Wake it locally; do not rebuild anything.

## Hard-earned truths

### 1. Ly silently ignored `/etc/ly/config.lua` (LuaJIT 2^47)

- Symptom: config edits did nothing.  No errors anywhere.  Battery keyword,
  clock, corner layout, theme, custom labels all ignored; Ly used compiled-in
  defaults.
- Cause: Ly 1.6.0 built with zlua `lang = .luajit`; LuaJIT's GC64 stores GC
  pointers in **47 bits**, but this kernel gives a 48-bit user address space
  and mmap returned addresses above `2^47` (e.g. `0xffff9a96b020`).
  `lua_newstate()` discarded its allocation and returned NULL, which Ly
  reported as `OutOfMemory` and swallowed (the parser fell back to defaults).
- Diagnosis that mattered: a diagnostic build printed
  `LYCFG: parseLua failed: OutOfMemory`; `--validate-config` accepted even a
  syntax error (load errors were not recorded at all); an **INI** config
  (`/etc/ly/config.ini`) *did* apply, which proved the file/loader plumbing was
  fine and only the Lua path was broken.
- Fix: `patches/ly-lua-lowmem.patch` adds `ly-core/src/lowmem.zig`, which
  mmaps 64 MiB at `0x4000_0000_0000` (2^46) and serves Lua's allocations from a
  `FixedBufferAllocator` over it (fallback to the normal allocator on non-arm64
  or if the mapping fails).  `LuaParser.parseLua` and the Lua *animation* state
  use it, and parse failures now set `maybe_load_error` (so
  `ly --validate-config` finally reports `LuaError`).
- Verify config is live:

  ```sh
  # on the device: a broken file must now be rejected
  printf 'ly = = {\n' > /tmp/bad.lua; sudo ly --validate-config /tmp/bad.lua
  # => error: failed to load config file: LuaError

  # or prove the file is read: set waylandsessions to a bogus path, restart
  # ly-kmsconvt@tty1, and look for that path in /var/log/ly.log
  ```

- Rebuilding Ly after touching the patch (arm64 under qemu, 25-45 min; the
  `.zig-cache` in `build/ly-src` makes reruns faster):

  ```sh
  podman run --rm --arch arm64 --userns=keep-id --user "$(id -u):$(id -g)" \
    --network=host -e HOME=/tmp \
    -v "$PWD/build/ly-src:/src" -v "$PWD/build/zig-aarch64-linux-0.17.0:/opt/zig:ro" \
    -w /src devterm-ly-builder bash -c '
      /opt/zig/zig build -Denable_x11_support=false -Doptimize=ReleaseSafe \
        -Dcpu=cortex_a53 -Ddefault_tty=1 -Dfallback_tty=1 &&
      cp zig-out/bin/ly /src/ly.built'
  llvm-strip --strip-all build/ly-src/ly.built
  scp build/ly-src/ly.built devterm@devterm-a04:/tmp/ly-new
  # on the device
  sudo install -m 755 /tmp/ly-new /usr/bin/ly && sudo systemctl restart ly-kmsconvt@tty1
  ```

  `scripts/build-ly.sh` applies both Ly patches automatically (guarded by
  greps); `FORCE_LY=1` forces a rebuild.

### 2. Ly config semantics (non-obvious)

- Corners: `corner_top_left/right`, `corner_bottom_left/right`.  Tokens are
  separated by **spaces** for stacked rows, or **commas** for one horizontal
  run.  In a right corner the **first** token sits at the right edge, so
  `"lbl:battery,lbl:wifi,clock"` renders `[clock][wifi][battery]`.
- `labels` places every custom label that no `lbl:name` has already placed;
  `positioned.labels[i]` prevents duplicates.  With explicit `lbl:` entries in
  a corner, `corner_bottom_right = "labels"` becomes a no-op.
- Custom labels (`custom_labels`) run `cmd` through `/bin/sh -c` **as root**
  (Ly runs as root) and refresh every `refresh` *ticks*; 600 ≈ 10 s in
  practice.  Output is the label text; do not print more than a short line.
- Watch for duplicate keys: Lua executes in order and the **later assignment
  wins**.  `lua_animation_file` existed twice in the shipped config and bit us.
- `--validate-config` was a no-op before the lowmem patch.  After it, it is
  trustworthy.
- `battery_id` drives the built-in `battery` corner keyword, which only prints
  `BAT: n%`.  We now use `battery_id = nil` and a custom label instead.
- The login screen is currently configured as:
  corner_top_left = F-key hints; corner_top_right = battery, Wi-Fi, clock
  (`devterm-battery` and `devterm-wifi status`); `animation = "lua"`,
  `lua_animation_file = "/etc/ly/starburst.lua"`, `animation_frame_delay = 40`
  (25 fps), `animation_timeout_sec = 0`, `bg = 0x00241F31`.

### 3. Ly Lua animations

- Contract (`/etc/ly/example.lua`): global `draw()` is called every frame with
  `ly.width`, `ly.height`, `ly.clock()` (microseconds), `ly.putCell(byte, fg,
  bg, x, y)`, `ly.putLabel`, `ly.putRect`.  Libraries: base, bit, math, string,
  table (no `io`, no `debug`).
- The screen buffer is **persistent**: an animation that draws nothing leaves
  the previous frame on screen.  `/etc/ly/starburst.lua` keeps a list of the
  cells it painted and erases them (with the theme `bg`) before each draw.
- The animation state also needed the lowmem patch; without it the animation
  could not start at all on this kernel.
- Its allocator is a **no-free** 64 MiB fixed buffer, so keep `draw()`
  allocation-free (numbers and table field updates are fine; avoid string
  concatenation, tables created per frame, `table.insert` growth).  The
  starburst follows that rule.
- Upstream quirk: `main.zig` declares the animation struct in a `switch` branch
  and stores `&branch_local` in the widget.  It works because the stack slot is
  never reused, but it is technically a dangling pointer — do not reshuffle that
  code expecting the animation to be heap-allocated.
- Timing knobs live at the top of `starburst.lua`: `BURST_US` (3 s),
  `PERIOD_US` (45 s), `FIRST_US` (1 s), `TAIL_US` (1.4 s flicker-out),
  `EMIT_PER_SEC`, `MAX_PART`, and `BG` which must equal the config `bg`.

### 4. kmscon / console

- `devterm-ly-console` runs `kmscon --term=xterm-256color --no-hwaccel
  --vt=tty1 --login -- ly --use-kmscon-vt`, logs to
  `/var/log/kmscon-tty1.log` (truncated on each start), and falls back to
  fbcon + agetty only if kmscon exits non-zero within 10 s.
- The A04 panel is 480x1280 rotated; kmscon's guard band drops one text row, so
  Ly sees **160x29** cells at the default 8x16 font.
- `drm_shared: /dev/dri/card1 doesn't support universal planes` and
  `video_drm2d: driver does not support dumb buffers` in the log are expected
  noise: kmscon tries the panfrost card first and falls back to card0.
- **Restarting `ly-kmsconvt@tty1` repeatedly can leave the panel blank** (no
  fresh modeset).  The processes are healthy (`systemctl is-active`, SSH works).
  One restart brings it back; do not go hunting for a hardware fault.  Make one
  restart per change, not a loop.

### 5. Testing without eyes on the console

There is **no screenshot path**: kmscon holds DRM master and
`/sys/kernel/debug/dri/0/framebuffer` only prints metadata.  Use these instead:

- **pty harness** (used all session): `pty.openpty()`, `TIOCSWINSZ` 160x29,
  child `preexec` does `setsid()` + `ioctl(0, TIOCSCTTY, 0)` (without the
  controlling TTY, Ly/termbox fail with `TermboxInitFailed`), `TERM=xterm-256color`,
  then feed the bytes to `pyte.Screen(160, 29)` on the host.  For animations,
  record chunks with timestamps (`>QI` ms+len records) and snapshot at times.
- **TUIs that query the terminal hang on a bare pty.**  Microsoft Edit writes
  `ESC[c` (DA1), `ESC[6n` (DSR), `OSC 4/10/11` colour queries and waits for
  replies; reply with `\e[?1;2c` / `\e[<y>;<x>R` or it never draws.  kmscon's
  libtsm v4.8.0 answers DA1 (`csi_dev_attr`) and DSR 5/6 (`csi_dsr`), and
  ignores the OSC colour queries, which Edit tolerates.
- **tmux as a terminal emulator**: `tmux -L sock new-session -d -x 100 -y 24
  'program'`, `tmux -L sock send-keys -t t C-s`, `tmux -L sock capture-pane -p`
  — this is how Edit's save/quit was verified.  `/tmp/` harness scripts from
  this session are gone; recreate them from the above recipe.
- For sending control keys through a raw pty, disable `IXON`/`IXOFF` first,
  otherwise `Ctrl+S` (0x13) just stops output.

### 6. Shell-script truths

- **sudo drops the environment** (`env_reset`).  Settings passed as env vars
  from `devterm-web` never reached `devterm-kms`: `--kiosk` silently ran GNOME
  Web.  Modes now travel as arguments (`devterm-web-session --kiosk`), and
  `devterm-kms` deliberately does not try to forward env vars.
- `devterm-web-session` must terminate cage itself: closing the GNOME Web
  window exits with non-zero, and under `set -e` a plain `wait` aborted the
  script *before* the cleanup.  It is now `wait || rc=$?`, then `pkill -TERM -x
  cage`, and `devterm-kms` uses `systemd-run --wait` with a
  `/run/devterm-kms.lock` flock.
- Helpers follow one-line `status` subcommands for the status bars:
  `devterm-wifi status`, `devterm-tailscale-status`, `devterm-battery`
  (no argument).  `/etc/tmux.conf` `status-right` calls exactly those and
  `status-interval 5`.
- `devterm-battery` prints Font Awesome battery glyphs by charge
  (full/¾/half/quarter/empty) plus a bolt while charging; it reads the first
  `type=Battery` entry of `/sys/class/power_supply` (on the A04:
  `axp20x-battery`, with `charge_*`/`energy_*` fallbacks).  `POWER_SUPPLY_DIR`
  overrides the sysfs root for tests.  Ly's battery label calls the same
  helper — keep the formats aligned with tmux.

### 7. Hardware / kernel facts that bite

- AXP221 PMIC; battery is `axp20x-battery` (capacity + status).  Values seen:
  4 % while charging and 100 %; nothing in between during short sessions.
- Backlight is a PWM/GPIO (`backlight@0`, 0..9 scale, 5 in use); F5/F6 change
  it from Ly.
- micro-HDMI is disabled in the vendor DT; `devterm-hdmi on` applies an
  overlay and reboots.  Without it kmscon stays at 160x29.
- Power button suspends (long press powers off); idle suspend is enabled, so a
  quiet DevTerm drops off the network.

### 8. Apps added this session

- **WordGrinder**: `wordgrinder-ncurses` (trixie, 0.8-1+b2) →
  `/usr/bin/wordgrinder`; `overlay/usr/local/bin/devterm-word` wraps it.
- **Microsoft Edit** 2.0.0: no Debian package; `fetch.sh` pins
  `edit-2.0.0-aarch64-linux-gnu.tar.gz` with
  `sha256 b39f0b128d29d4c00f32a416c515f2c7758e0ec8d7457ee10b948e7b76636da4`,
  `customize-rootfs.sh` stages it, `rootfs-install.sh` installs
  `/usr/local/bin/edit`.  The release binary has no dynamic ICU dependency
  (`ldd` shows only libc/libm), so it runs standalone (`edit --version`).
- **FM-1 udev rule**: `overlay/etc/udev/rules.d/70-mvave-fm1.rules` matches USB
  vendor `4c4a` (M-VAVE FM-1 / WL80 bootloader) and sets `GROUP="plugdev",
  MODE="0660", TAG+="uaccess"` on both `scsi_generic` and `sd*` block nodes;
  `/dev/sg0` and `/dev/sda` were `root:disk` before.  `devterm` is already in
  `plugdev`.  The `fm1-tty`/`fm1-grid` tools themselves live in
  `/home/devterm/bin` and are **not** part of the image.

## Verification playbook

Run on the device unless noted.

```sh
# console up and Ly running
systemctl is-active ly-kmsconvt@tty1; ps -o pid,etime,args -C ly

# config actually parsed (see above); labels are owned by Ly's root process
printf 'ly = = {\n' >/tmp/bad.lua; sudo ly --validate-config /tmp/bad.lua   # must fail

# battery label helper output (what the login screen shows)
/usr/local/bin/devterm-battery; /usr/local/bin/devterm-wifi status

# real login screen, without touching the panel: render Ly in a pty on the host
# (pty harness above); expect row 0: hints ... clock, wifi, battery glyph

# udev rule
ls -l /dev/sg* /dev/sd*    # root:plugdev 0660 with an ACL

# apps
wordgrinder --version 2>/dev/null || true; edit --version; command -v devterm-word

# Ly animation sanity (timings from the harness): burst ~3 s every 45 s, quiet
# between, tail flickers out over ~1.5 s
```

Image checks: `make verify` (runs `scripts/verify-image.sh`), or grep the
checks added to `build-rootfs.sh`/`verify-image.sh` for the files each feature
needs (Ly config, `devterm-word`, `edit`, `starburst.lua`, udev rule).

## Open items / risks

1. **Rebuild the image** (`make image`) so the SD-card artifact matches the
   repo; then `make verify` and re-flash when convenient.
2. If Ly is ever bumped to a newer commit, rebase `patches/ly-lua-lowmem.patch`
   (the file layout moved once already: `ly-core/src/root.zig`), and re-check
   that `lua_animation_file` is not duplicated in the config.
3. The animation allocator never frees; keep `draw()` allocation-free or swap
   `LowMem` for a real allocator over the low mapping.
4. Ly's `animation` struct lifetime is an upstream bug (stack local address
   stored in a widget).  It works today; do not "fix" it casually.
5. Do not `systemctl restart` the console in a loop — see the blank-panel note.
6. Edit's palette-colour queries are unanswered by libtsm; colours fall back to
   its defaults.  Cosmetic only.
7. `devterm-idle-suspend` will make the device disappear from SSH when idle.
