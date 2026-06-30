# AMQP Dissector Enhancement

Custom enhancements to the Wireshark **AMQP 0-9-1** dissector (`epan/dissectors/packet-amqp.c`),
built against Wireshark 4.7.2.

The easiest way to try it is **[Option 1 — the pre-built installer](#option-1--full-installer-easiest)**:
download, install, done. No existing Wireshark required, no version to match.

Modified packets carry a generated `amqp.build` field that points back to this repository, so a
capture analysed with this build is self-identifying.

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

A complete, self-contained Wireshark installer with the modified dissector already built in.
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
> shows an "unknown publisher" warning. **Verify the SHA-256 hash**, not the signature.
>
> ⚠️ **Npcap.** The installer bundles the Npcap capture driver, whose free licence restricts
> redistribution. If you did not receive this directly from the author under appropriate terms,
> install Npcap yourself from https://npcap.com.

### Option 2 — Drop-in library (if you already run Wireshark 4.7.2)

Replace the dissector library in an existing install.

1. Download `libwireshark.dll` from the [latest Release](../../releases/latest).
2. Back up the existing `libwireshark.dll` in your Wireshark program folder, then replace it with
   the downloaded one.

> ⚠️ **ABI-specific.** The library ABI is version-locked — this only works dropped into a
> **matching Wireshark 4.7.2** install. On any other version, use Option 1 or Option 3.

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

---

## License

Wireshark is licensed under the **GNU GPL v2** (`SPDX-License-Identifier: GPL-2.0-or-later`).
These modifications are distributed under the same licence; the corresponding source is this
repository.
