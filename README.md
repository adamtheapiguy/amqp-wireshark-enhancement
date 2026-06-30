# AMQP Dissector Enhancement

Custom enhancements to the Wireshark **AMQP 0-9-1** dissector (`epan/dissectors/packet-amqp.c`),
built against Wireshark 4.7.2.

The easiest way to try it is the **[pre-built installer](#pre-built-binaries)** — download, install,
done. No need to already have Wireshark or match a specific version.

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

## Pre-built binaries

Attached to the [latest Release](../../releases/latest).

### Full installer — easiest, start here

**`Wireshark-4.7.2-...-x64.exe`** — a complete, self-contained Wireshark installer with the
modified AMQP dissector already built in. **Just download and install.** You do **not** need to
already have Wireshark, and you do **not** need to match a specific version or copy any files by
hand. This is the recommended way to try the enhancement.

Verify the download against the attached `.sha256`:

```powershell
Get-FileHash .\Wireshark-4.7.2-*-x64.exe -Algorithm SHA256
# compare against the .sha256 file in the Release
```

> ⚠️ **Self-signed.** The installer's code signature is **not** backed by a public CA, so Windows
> SmartScreen shows an "unknown publisher" warning. **Verify the SHA-256 hash**, not the signature.
>
> ⚠️ **Npcap.** The installer bundles the Npcap capture driver, whose free licence restricts
> redistribution. If you did not receive this directly from the author under appropriate terms,
> install Npcap yourself from https://npcap.com.

### Drop-in DLL — advanced

**`libwireshark.dll`** — replaces the library in an existing Wireshark install.

> ⚠️ **ABI-specific.** The library ABI is version-locked, so this only works dropped into a
> **matching Wireshark 4.7.2** install. If you are not already on that exact version, use the full
> installer above, or build from source.

---

## Build from source

For a from-source build (e.g. to inspect or modify the code yourself), apply the patch to a
Wireshark checkout:

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

### Display filters

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
