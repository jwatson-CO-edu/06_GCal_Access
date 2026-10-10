# Building a Linux executable

The output is a self-contained, relocatable **bundle**: the `gcal_access`
executable plus the Flutter engine (`lib/`) and assets (`data/`) it needs.
Nothing needs to be installed on the target machine except the system GTK 3
runtime and a desktop session (see *Target machine*).

> Flutter does not produce a single static file. "Self-contained" here means one
> folder / one `.tar.gz` you can copy anywhere and run.

## 1. Prerequisites (build machine)

- Flutter SDK (stable, Dart 3.13+) on your `PATH`: <https://docs.flutter.dev/get-started/install/linux/desktop>
- Linux desktop toolchain and `make`. On Debian/Ubuntu/Mint:

  ```bash
  sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev make
  ```

- Verify: `flutter doctor` should show a green **Linux toolchain**.

## 2. Build

From the project root:

```bash
make dist
```

This runs `flutter pub get`, a release build (`flutter build linux --release`),
then assembles and archives the bundle. Results:

| Path | What |
| --- | --- |
| `build/linux/<arch>/release/bundle/` | Raw Flutter bundle |
| `dist/gcal_access-linux-<arch>/` | Bundle plus `keys/KEY.md` |
| `dist/gcal_access-linux-<arch>.tar.gz` | Archive of the above  |
| `dist/gcal_access-linux-<arch>.tar.gz.sha256` | Checksum |

`<arch>` is `x64` or `arm64`, matching the machine you build on (no cross-compiling).

Other targets (`make help` lists them):

| Command | Does |
| --- | --- |
| `make check` | `flutter analyze` + `flutter test` |
| `make build` | Release build only |
| `make run` | Run in debug mode |
| `make clean` | Remove `build/` and `dist/` |

## 3. Install and run

```bash
tar xzf gcal_access-linux-x64.tar.gz
cd gcal_access-linux-x64
./gcal_access
```

The folder can be moved anywhere. The archive deliberately contains **no
credentials**; add your own (next section).

### Credentials

Follow `keys/KEY.md` to create a Google OAuth *Desktop app* client and download
its JSON. Place it where the app can find it. It looks, in order, at:

1. `$GCAL_KEYS_DIR`
2. `keys/` in the current directory, or in the executable's folder or any parent
   (so `gcal_access-linux-x64/keys/credentials.json` works)
3. `~/.config/gcal_access/keys/` (use this if the app lives in a read-only location)

On first use a browser opens for Google sign-in; the refresh token is stored as
`token.json` in the same `keys/` folder. Keep these files private and never
commit them (`keys/*.json` is git-ignored).

## Target machine

- Same CPU architecture as the build machine, and a glibc at least as new as the
  build machine's (build on the oldest distro you need to support).
- GTK 3 runtime (`libgtk-3-0`, present on virtually every desktop Linux).
- `xdg-open` (or any default browser handler) for the Google sign-in step.
- A graphical session (X11 or Wayland).

## Troubleshooting

- **`flutter: command not found`**: add the SDK's `bin/` to `PATH`, or run `make FLUTTER=/path/to/flutter/bin/flutter dist`.
- **CMake/Ninja/GTK errors during build**: install the packages in step 1; run `flutter doctor -v`.
- **`error while loading shared libraries`**: run `ldd gcal_access lib/*.so | grep "not found"` on the target and install what is missing.
- **"keys/ directory not found"** at sign-in: see *Credentials* above.

---

# AppImage (optional, for later)

An AppImage is a single executable file that runs on most desktop Linux
distributions with no extraction step. It is built from the same release bundle
as `make dist`, wrapped in an `AppDir` folder and packed by `appimagetool`.

> Status: the AppDir assembly (steps 3-5) was tried on the build machine and the
> `AppRun` launcher starts the app. The final `appimagetool` packing step (6) and
> the `make appimage` target below have **not** been run yet; there is no
> `make appimage` in the Makefile today.

## A. Install the tools

You need `appimagetool` (one downloaded file) and FUSE 2. The Flutter prerequisites
from section 1 above are also required.

1. Install `appimagetool` into `~/.local/bin`:

   ```bash
   mkdir -p ~/.local/bin
   curl -L -o ~/.local/bin/appimagetool https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage
   ```

   ```bash
   chmod +x ~/.local/bin/appimagetool
   ```

   ```bash
   appimagetool --version
   ```

   - If the command is not found, add `~/.local/bin` to your `PATH`.
   - On an ARM machine, download `appimagetool-aarch64.AppImage` instead.

2. Install FUSE 2. AppImages mount themselves through it, and Ubuntu 24.04-based
   systems (including Linux Mint 22.x) do not ship it by default:

   ```bash
   sudo apt install libfuse2t64
   ```

   On older Ubuntu/Debian the package is `libfuse2`. To run an AppImage without
   FUSE, pass `--appimage-extract-and-run` (this works for `appimagetool` too). End
   users of your finished AppImage still need FUSE 2 unless they use that flag.

3. Optional: `desktop-file-utils` provides `desktop-file-validate` for checking the
   `.desktop` file (`sudo apt install desktop-file-utils`).

## B. Build the AppImage by hand

Run from the project root. The Flutter executable finds its `lib/` and `data/`
folders next to itself, so the whole bundle is kept together in one folder inside
the AppDir; `AppRun` launches it from there.

**Step 1.** Build the release bundle:

```bash
make build
```

**Step 2.** Create a clean AppDir and copy the bundle in (use `arm64` in place of `x64` on ARM):

```bash
rm -rf build/AppDir
mkdir -p build/AppDir/usr/lib/gcal_access
cp -a build/linux/x64/release/bundle/. build/AppDir/usr/lib/gcal_access/
```

**Step 3.** Add the `AppRun` launcher (required, must be executable):

```bash
cat > build/AppDir/AppRun <<'APPRUN'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
exec "$HERE/usr/lib/gcal_access/gcal_access" "$@"
APPRUN
chmod +x build/AppDir/AppRun
```

**Step 4.** Add the desktop entry (required, at the AppDir root; `Icon` must match the PNG name below):

```bash
cat > build/AppDir/gcal_access.desktop <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=GCal Access
Comment=Schedule Markdown tasks in Google Calendar
Exec=gcal_access
Icon=gcal_access
Categories=Office;Calendar;
Terminal=false
DESKTOP
desktop-file-validate build/AppDir/gcal_access.desktop
```

**Step 5.** Add an icon: a PNG named `gcal_access.png` at the AppDir root, ideally 256x256 or
512x512. Use your own artwork if you have it:

```bash
cp path/to/your-icon.png build/AppDir/gcal_access.png
```

Otherwise generate a plain placeholder (solid indigo square):

```bash
python3 - <<'PY'
import zlib, struct
w = h = 256
raw = b''.join(b'\x00' + bytes([63, 81, 181, 255]) * w for _ in range(h))
def chunk(t, d):
    c = struct.pack('>I', len(d)) + t + d
    return c + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
png = (b'\x89PNG\r\n\x1a\n'
       + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0))
       + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))
open('build/AppDir/gcal_access.png', 'wb').write(png)
PY
```

**Step 6.** Smoke-test the AppDir before packing (a window should open; close it):

```bash
build/AppDir/AppRun
```

**Step 7.** Pack it (the `ARCH` variable names the target architecture; `x86_64` or `aarch64`):

```bash
mkdir -p dist
ARCH=x86_64 appimagetool build/AppDir dist/GCal_Access-x86_64.AppImage
```

If FUSE is not installed, use `appimagetool --appimage-extract-and-run build/AppDir dist/...` instead.

**Step 8.** Test the result from a different directory:

```bash
cd /tmp && ~/path/to/project/dist/GCal_Access-x86_64.AppImage
```

## C. Credentials with an AppImage

An AppImage runs from a read-only mount, so credentials **cannot** live next to the
executable. The app looks in `$GCAL_KEYS_DIR`, then in `keys/` under the current
directory, then in `~/.config/gcal_access/keys/`. For AppImage users, the last is
the simplest:

```bash
mkdir -p ~/.config/gcal_access/keys
cp credentials.json ~/.config/gcal_access/keys/
```

The sign-in token is saved there too as `token.json`. Never bundle your own
credentials into an AppImage you distribute; each user creates their own (see `keys/KEY.md`).

## D. Shipping the AppImage

1. **Build on the oldest distro you want to support.** The bundle links against the
   build machine's glibc and GTK; it runs on that glibc version or newer, never
   older. Building in an older Ubuntu LTS container or VM gives the widest reach.
2. **One AppImage per architecture.** x86_64 and aarch64 are separate builds, each
   made on its own architecture (Flutter does not cross-compile for Linux desktop).
3. **Checksum and verify** before publishing:

   ```bash
   cd dist
   sha256sum GCal_Access-x86_64.AppImage > GCal_Access-x86_64.AppImage.sha256
   sha256sum -c GCal_Access-x86_64.AppImage.sha256
   ```

4. **Publish** the `.AppImage` and its `.sha256` file where users can download them,
   for example as assets on a GitHub release (`gh release create vX.Y.Z dist/*.AppImage dist/*.sha256`).
   Give the version in the release name; the filename can carry it too
   (`GCal_Access-1.0.0-x86_64.AppImage`).
5. **Tell users** to:

   ```bash
   chmod +x GCal_Access-x86_64.AppImage
   ./GCal_Access-x86_64.AppImage
   ```

   plus the FUSE 2 requirement (section A, step 2), the credentials location
   (section C), and that they need `xdg-open` and a desktop session. They can move
   the file anywhere, e.g. `~/Applications/`.
6. **Desktop menu integration** is optional. Tools such as AppImageLauncher offer to
   integrate the file when it is first run; otherwise users can run it directly.
7. **Updates:** a new release is a new file; users replace the old one. Automatic
   update support (zsync) needs `appimagetool --updateinformation` and hosting the
   `.zsync` file; not set up here.
8. Bump `version:` in `pubspec.yaml` before each release build.

## E. Possible `make appimage` target

When you are ready to automate it, a Makefile target can run steps B.2-B.7 and depend
on `build`. Keep the `AppRun` and `.desktop` file as checked-in files (for example in
a `packaging/` folder) rather than echoing them from the Makefile, so they are easy
to edit and review. Ask Claude to add it once `appimagetool` is installed so it can be tested.
