# AMQP Dissector Enhancement

Custom enhancements to the Wireshark **AMQP 0-9-1** dissector (`epan/dissectors/packet-amqp.c`),
built against Wireshark 4.7.2.

The easiest way to try it is **[Option 1 — the pre-built installer](#option-1--full-installer-easiest)**:
download, install, done. It is a complete Wireshark 4.7.2 with the dissector already built in — no
existing Wireshark required, no version to match.

Modified packets carry a generated `amqp.build` field that points back to this repository, so a
capture analysed with this build is self-identifying.

> 🛠️ Building it yourself? See **[WINDOWS-DEV-SETUP.md](WINDOWS-DEV-SETUP.md)** for a full Windows
> development-environment guide, and **[`build-installer.ps1`](build-installer.ps1)** for a
> one-command build/sign/package script.

---

## What it does

| # | Feature | Detail |
|---|---------|--------|
| 1 | **Connection.Update-Secret** | Dissects AMQP 0-9-1 methods `70` (Update-Secret) and `71` (Update-Secret-Ok), used to rotate credentials on a live connection. |
| 2 | **JWT introspection** | When a SASL `Connection.Start-Ok` response carries a JWT, it is split into header / payload / signature, base64url-decoded, JSON pretty-printed, and individual claims (e.g. `scope`, and epoch timestamps like `exp`) are surfaced as readable tree items. |
| 3 | **Payload text decoding** | Content-body frames with printable payloads gain a `Payload Text` field (with base64 / JSON / JWT detection) alongside the existing hex view. |

A generated **`amqp.build`** marker is attached to exactly the dissections above
(Start-Ok, Update-Secret, Update-Secret-Ok, and content bodies) — not to every AMQP packet.

---

## How to use it

Three ways, easiest first. Pick one.

### Option 1 — Full installer (easiest)

A complete, self-contained Wireshark 4.7.2 installer with the modified dissector already built in.
**Just download and install** — no existing Wireshark needed, no version to match, nothing to copy
by hand.

1. Download `Wireshark-4.7.2-...-x64.exe` and its `.sha256` from the
   [latest Release](../../releases/latest).
2. Verify the download:
   ```powershell
   Get-FileHash .\Wireshark-4.7.2-*-x64.exe -Algorithm SHA256
   # compare against the .sha256 file in the Release
   ```
3. Run the installer.

> ⚠️ **Self-signed.** The code signature is **not** backed by a public CA, so Windows SmartScreen
> shows an "unknown publisher" warning. **Verify the SHA-256 hash** (step 2) — that is the
> recommended check and needs no trust setup.
>
> ⚠️ **Npcap.** The installer bundles the Npcap capture driver, whose free licence restricts
> redistribution. If you did not receive this directly from the author under appropriate terms,
> install Npcap yourself from https://npcap.com.

#### Optional — validate the code signature

The public signing certificate (`adamTheApiGuy-public.cer`) is included in this repo so you can
validate the Authenticode signature if you wish. It contains **no private key** and cannot sign
anything. To make Windows trust the signature, import it into your Current-User Trusted Root store,
then verify:

```powershell
Import-Certificate -FilePath .\adamTheApiGuy-public.cer -CertStoreLocation Cert:\CurrentUser\Root
Get-AuthenticodeSignature .\Wireshark-4.7.2-*-x64.exe | Format-List Status, SignerCertificate
```

`Status : Valid` confirms the file was signed by this certificate and is unmodified.

> ⚠️ Importing a certificate into Trusted Root tells Windows to trust **anything** signed by it,
> now and in future — only do this if you trust the source. The SHA-256 hash check above verifies
> file integrity **without** importing anything, and is the recommended default.

### Option 2 — Drop-in library (advanced; ABI must match)

Replace the dissector library in an existing install.

1. Download `libwireshark.dll` from the [latest Release](../../releases/latest).
2. Back up the existing `libwireshark.dll` in your Wireshark program folder (next to
   `Wireshark.exe`), then replace it with the downloaded one.

> ⚠️ **ABI-specific — read this first.** This DLL was compiled from a particular Wireshark 4.7.2
> source checkout, and only works when dropped into a Wireshark whose library ABI matches that
> exact build. In practice that means **a Wireshark you built yourself from the same 4.7.2 source**
> (see Option 3).
>
> It is **not** enough to download "Wireshark 4.7.2" — the 4.7.x line is a rolling development
> series with no stable installer (only automated per-commit builds like `4.7.2rc0-NNN-gHASH`), and
> any official build is a *different commit* whose ABI is unlikely to match this DLL. If you just
> want it working, use **Option 1** — that installer already is a complete, matching 4.7.2.

### Option 3 — Build from source (inspect or modify the code)

Apply the patch to a Wireshark checkout and build it yourself.

```bash
# 1. Clone Wireshark
git clone https://gitlab.com/wireshark/wireshark.git
cd wireshark

# 2. Apply the patch from this repo
git apply /path/to/packet-amqp.patch
#   (or: patch -p1 < /path/to/packet-amqp.patch)

# 3. Build per the Wireshark Developer's Guide for your platform:
#    https://www.wireshark.org/docs/wsdg_html_chunked/ChSetupWindows.html
```

> 🛠️ **On Windows?** [WINDOWS-DEV-SETUP.md](WINDOWS-DEV-SETUP.md) is a complete, tested setup guide
> (Visual Studio, Qt, NSIS, xsltproc, environment variables) with a gotcha quick-reference. Once
> set up, [`build-installer.ps1`](build-installer.ps1) does configure → build → sign → hash in one
> command.
>
> ℹ️ **Where to get Wireshark itself:** the stable downloads at
> <https://www.wireshark.org/download.html> are the 4.x stable line, suitable for normal use and as
> a base for building. Note they are *not* the 4.7.2 development build this enhancement targets — to
> match this work exactly, build from the 4.7.2 source as above.

---

## Display filters

Once installed, these isolate the enhanced dissections:

| Filter | Shows |
|--------|-------|
| `amqp.build` | Only the packets this enhancement affects |
| `amqp.jwt.payload.scope` | JWT `scope` claim from a Start-Ok |
| `amqp.method.arguments.new_secret` | Update-Secret payload |
| `amqp.payload_text` | Decoded content-body text |

---

## Repository contents

| File | Purpose |
|------|---------|
| `packet-amqp.c` | The full modified dissector source. |
| `packet-amqp.patch` | Unified diff against upstream Wireshark. |
| `adamTheApiGuy-public.cer` | Public signing certificate (no private key) for optional signature validation. |
| [`WINDOWS-DEV-SETUP.md`](WINDOWS-DEV-SETUP.md) | Windows development-environment setup guide. |
| [`build-installer.ps1`](build-installer.ps1) | One-command build / sign / package script. |

---

## License

Wireshark is licensed under the **GNU GPL v2** (`SPDX-License-Identifier: GPL-2.0-or-later`).
These modifications are distributed under the same licence; the corresponding source is this
repository.
