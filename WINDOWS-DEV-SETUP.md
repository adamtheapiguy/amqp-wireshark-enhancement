# Preparing a Windows Environment for Wireshark Development

A practical, tested walkthrough for setting up a Windows machine to build Wireshark
(4.7.x) from source with Visual Studio — including a custom installer. Follows the official
[Wireshark Developer's Guide](https://www.wireshark.org/docs/wsdg_html_chunked/ChSetupWindows.html),
with the real-world gotchas that guide glosses over called out inline.

Target: **64-bit only** (32-bit is no longer supported). Paths below assume a `C:\Development`
working root — adjust to taste, but keeping everything under one root simplifies the env vars.

---

## 0. What you'll install

| Tool | Purpose | Source |
|------|---------|--------|
| Visual Studio 2026 Community | C++ compiler, CMake tools, debugger | visualstudio.microsoft.com |
| Python 3 | Build scripts | python.org |
| Git | Source + version stamping | git-scm.com |
| Qt 6.10.3 (msvc2022_64) | The GUI toolkit | via `aqtinstall` |
| Chocolatey | Package manager for the rest | chocolatey.org |
| NSIS 3 | **Installer** target (optional but usually wanted) | nsis.sourceforge.net |
| xsltproc | **User's Guide** build — required by the installer | via Chocolatey |

CMake auto-downloads all other third-party libraries (glib, gcrypt, etc.) — you don't install
those manually.

---

## 1. Visual Studio 2026 Community

Download [Visual Studio 2026 Community](https://visualstudio.microsoft.com/) (free). In the
installer, check **"Desktop development with C++"**. Keep at least:

- MSVC Build Tools for x64/x86 (Latest)
- Windows 11 SDK
- C++ CMake tools for Windows

> 💡 2022 or 2019 also work — adjust the CMake generator name later (`Visual Studio 17 2022`, etc.).

## 2. Python 3

Install from [python.org](https://python.org/download/). Accept the "Add to PATH" option.

## 3. Git

Install from [git-scm.com](https://git-scm.com/download/win). Recommended installer choices:

- PATH: *Git from the command line and also from 3rd-party software*
- Line endings: *Checkout Windows-style, commit Unix-style*
- HTTPS backend: *native Windows Secure Channel*

## 4. Qt 6.10.3 (via aqtinstall — no Qt account needed)

The official Qt installer requires an account; `aqtinstall` sidesteps that.

```powershell
mkdir C:\Development\Qt
cd C:\Development\Qt
curl.exe -LOJ https://github.com/miurahr/aqtinstall/releases/download/v3.3.0/aqt_x64.exe
.\aqt_x64.exe install-qt windows desktop 6.10.3 win64_msvc2022_64 -m qt5compat debug_info qtmultimedia
```

> 💡 Match the Qt version to the one in the official Wireshark release you're targeting (6.10.3 for
> the current line). Mismatched Qt is a common source of odd build/runtime failures.

## 5. Chocolatey (package manager)

Makes installing xsltproc (and later, GitHub CLI) one-liners. From an **elevated** PowerShell:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; `
[System.Net.ServicePointManager]::SecurityProtocol = 3072; `
iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
```

> ⚠️ After install, **close and reopen** the shell before `choco` is on PATH. This "reopen the
> shell after installing a tool" pattern recurs throughout — Windows doesn't refresh PATH in
> already-open shells.

## 6. NSIS 3 and xsltproc (needed for the installer)

Skip this section if you only want to build `Wireshark.exe` and not a distributable installer.
But if you want the installer, **install both of these *before* you run CMake in step 8** — see
the gotcha box.

**NSIS 3** — from [nsis.sourceforge.net](https://nsis.sourceforge.net) (the 32-bit build is fine
for 64-bit Wireshark). Default install path `C:\Program Files (x86)\NSIS`. It does **not** add
itself to PATH; either add that folder to PATH or pass its location to CMake later.

**xsltproc** — builds the User's Guide, which the installer bundles:

```powershell
choco install -y xsltproc
```

> ⚠️ **The #1 Windows installer-build trap.** CMake decides whether the installer targets
> (`wireshark_nsis_prep` / `wireshark_nsis`) even *exist* by looking for `makensis.exe` **at
> configure time**. If NSIS isn't installed (or not on PATH) when you run CMake, those targets are
> silently never created, and the only "installer" you can build is CPack's broken generic one.
> Likewise, if xsltproc is missing, `wireshark_nsis` fails partway through with a
> `File ... no files found` error on the User's Guide. **Install both first**, then configure.

---

## 7. Environment variables

Two are required; a third is optional for branding. Set them **globally** (Windows → "Edit the
System Environment Variables") so every new shell inherits them:

| Variable | Value (example) | Purpose |
|----------|-----------------|---------|
| `WIRESHARK_BASE_DIR` | `C:\Development\wireshark-third-party` | Where CMake downloads 3rd-party libs |
| `CMAKE_PREFIX_PATH` | `C:\Development\Qt\6.10.3\msvc2022_64` | Points CMake at your Qt |
| `WIRESHARK_VERSION_EXTRA` | `-YourTag` | Optional: custom suffix in the version/About string |

> ⚠️ **Shell-staleness trap.** If you set these per-session (`$env:WIRESHARK_VERSION_EXTRA="..."`)
> instead of globally, a **fresh shell drops them** — and CMake will silently produce a *vanilla*
> build with no custom version string. Setting them globally (or via `setx`, which affects future
> shells only) avoids re-doing it every terminal. After any global change, open a new shell.

---

## 8. Get the source, configure, and build

Open **"Developer PowerShell for VS 18"** (Windows Terminal dropdown) so `cl.exe` / `msbuild` are
on PATH. Then:

```powershell
# Source (pristine tree)
cd C:\Development
git clone https://gitlab.com/wireshark/wireshark.git

# Out-of-tree build directory
mkdir C:\Development\wsbuild64
cd C:\Development\wsbuild64

# Generate build files (first time only; later builds regenerate automatically)
cmake -G "Visual Studio 18 2026" -A x64 ..\wireshark
```

A clean configure ends with:

```
-- Configuring done
-- Generating done
-- Build files have been written to: C:/Development/wsbuild64
```

Anything else means an environment problem — recheck the env vars and the generator name.

**Build the application:**

```powershell
cmake --build . --config RelWithDebInfo --target wireshark
```

Run it to confirm:

```powershell
.\run\RelWithDebInfo\Wireshark.exe
```

Help → About should show your version (with `WIRESHARK_VERSION_EXTRA` appended if you set it).

> 💡 **Inner dev loop.** After editing a dissector, rebuild just what you need —
> `cmake --build . --config RelWithDebInfo --target wireshark` (or `--target tshark` for CLI
> testing) — then run the binary straight from `run\RelWithDebInfo\`. No install step needed.

---

## 9. Optional: build a custom installer

Assumes step 6 (NSIS + xsltproc) is done and CMake was configured *after* installing them.

```powershell
# Build the User's Guide (needed by the installer)
cmake --build . --config RelWithDebInfo --target all_guides

# Stage, then package
cmake --build . --config RelWithDebInfo --target wireshark_nsis_prep
cmake --build . --config RelWithDebInfo --target wireshark_nsis
```

The installer lands in `packaging\nsis\` as `Wireshark-<version>-x64.exe` (note the real script
adds the `-x64` suffix — the broken CPack `package` target does not, which is a quick way to tell
them apart).

> 💡 **Code signing** (optional) slots *between* the two steps above: put a `sign-wireshark.bat`
> on PATH and configure with `-DENABLE_SIGNED_NSIS=On`. The `_prep` step also fetches the bundled
> Npcap/USBPcap installers — if that step errors, it's usually a network/download issue, not NSIS.

### Or: one command — `build-installer.ps1`

This repo includes **`build-installer.ps1`**, which runs steps 8–9 (configure → guides → prep →
NSIS) plus optional code signing and SHA-256 hashing in a single command, and re-sets the
environment variables every run so the shell-staleness trap can't bite:

```powershell
# build + hash only
.\build-installer.ps1

# build, sign with a self-signed cert (minted on first run), trust it locally, hash
.\build-installer.ps1 -CreateSelfSigned -TrustLocally
```

Edit the parameter defaults at the top of the script (build dir, Qt prefix, third-party dir,
version tag) for your machine — all are also overridable on the command line.

---

## Gotcha quick-reference

Hard-won from real builds; none of these are obvious from the tool output alone.

| Symptom | Cause | Fix |
|---------|-------|-----|
| `MSB1009: Project file does not exist: wireshark_nsis_prep.vcxproj` | NSIS wasn't found at configure time, so the target was never generated | Install NSIS, then **re-run** `cmake .` in the build dir |
| Installer build dies with `File "...\wsug_html_chunked\*.*" -> no files found` | xsltproc missing, so the User's Guide never built | `choco install -y xsltproc`, reconfigure, `all_guides`, re-package |
| Version/About string is vanilla despite setting `WIRESHARK_VERSION_EXTRA` | Set per-session in a shell that was later replaced | Set it globally (or `setx`), open a fresh shell, reconfigure |
| A `git diff`/`git show > file.patch` renders as garbage / "binary" | PowerShell's `>` writes **UTF-16** | Use `cmd /c "git diff ... > file"` for UTF-8 output |
| `.\script.ps1 ... cannot be loaded because running scripts is disabled` | Execution policy | `Set-ExecutionPolicy Bypass -Scope Process -Force` (session) or `RemoteSigned -Scope CurrentUser` (persistent) |
| Just-installed `choco`/`makensis`/tool "not recognized" | PATH not refreshed in the open shell | Close and reopen the shell |
| CMake finds a tool but you still get NOTFOUND in cache | CMake cached the negative result | Reconfigure, or pass it explicitly, e.g. `-DMAKENSIS_EXECUTABLE="C:/Program Files (x86)/NSIS/makensis.exe"` |

---

## References

- [Wireshark Developer's Guide — Windows setup](https://www.wireshark.org/docs/wsdg_html_chunked/ChSetupWindows.html)
- [Wireshark Developer's Guide — full](https://www.wireshark.org/docs/wsdg_html_chunked/)
- [aqtinstall (unofficial Qt CLI installer)](https://github.com/miurahr/aqtinstall)
