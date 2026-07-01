#Requires -Version 5.1
<#
.SYNOPSIS
  One-shot Wireshark custom installer build: configure -> guides -> NSIS -> (sign) -> hash.

.DESCRIPTION
  Collapses the full custom-installer flow into a single command and eliminates the stale-shell
  environment problems (WIRESHARK_VERSION_EXTRA / base dir / Qt prefix are set here every run).

  From: https://github.com/adamtheapiguy/amqp-wireshark-enhancement
  Prerequisites: see WINDOWS-DEV-SETUP.md (Visual Studio, Qt, NSIS, xsltproc, env vars).

  >>> EDIT THE PARAM DEFAULTS BELOW <<< for your machine (build dir, Qt prefix, third-party dir,
  version tag, NSIS path). Every one is also overridable on the command line.

  Run from a "Developer PowerShell for VS" so cl.exe / msbuild are on PATH. Examples:
    .\build-installer.ps1                                  # build + hash, no signing
    .\build-installer.ps1 -CreateSelfSigned                # mint/reuse a self-signed cert, sign, hash
    .\build-installer.ps1 -CreateSelfSigned -TrustLocally  # + trust it on THIS machine (verify/SmartScreen pass)
    .\build-installer.ps1 -CertThumbprint 1A2B...          # use a real CA cert already in your store

  Signing is OPTIONAL. With no cert switch, the installer is still hashed. Order is enforced:
  sign first, hash second, so the .sha256 covers the signed bytes.

.NOTES
  Self-signed certs are valid Authenticode but only trusted where the cert is in Trusted Root.
  -TrustLocally imports it into CurrentUser\Root for this machine only; other machines still warn.
  Fine for a bench build, useless for distribution (for that, use a CA cert).
#>

[CmdletBinding()]
param(
    # --- EDIT THESE DEFAULTS for your environment ---------------------------
    [string]$BuildDir     = 'C:\Development\wsbuild64',
    [string]$ThirdParty   = 'C:\Development\wireshark-third-party',
    [string]$QtPrefix     = 'C:\Development\Qt\6.10.3\msvc2022_64',
    [string]$VersionExtra = '-WithAMQPEnhancementByAdamTheApiGuy',
    [string]$Config       = 'RelWithDebInfo',
    [string]$NsisDir      = 'C:\Program Files (x86)\NSIS',

    # --- signing (optional) -------------------------------------------------
    [string]$CertThumbprint   = '',                              # explicit cert (real CA); wins over -CreateSelfSigned
    [switch]$CreateSelfSigned,                                   # mint/reuse a self-signed code-signing cert
    [string]$SelfSignedSubject = 'CN=adamTheApiGuy',             # becomes the Windows publisher string
    [switch]$TrustLocally,                                       # import self-signed cert into CurrentUser\Root
    [string]$TimestampUrl     = 'http://timestamp.digicert.com', # RFC3161 TSA
    [switch]$SignInternals                                       # also sign bundled exe/dll
)

$ErrorActionPreference = 'Stop'
function Step($m){ Write-Host "`n=== $m ===" -ForegroundColor Cyan }
function Fail($m){ Write-Host "FAIL: $m" -ForegroundColor Red; Pop-Location -ErrorAction SilentlyContinue; exit 1 }
function Ok($m)  { Write-Host "  ok: $m" -ForegroundColor Green }

# ----------------------------------------------------------------------------
# 0. environment - set every run so a fresh shell never drops these
# ----------------------------------------------------------------------------
Step 'Environment'
$env:WIRESHARK_BASE_DIR      = $ThirdParty
$env:CMAKE_PREFIX_PATH       = $QtPrefix
$env:WIRESHARK_VERSION_EXTRA = $VersionExtra
if ((Test-Path $NsisDir) -and ($env:PATH -notlike "*$NsisDir*")) { $env:PATH += ";$NsisDir" }
Ok "WIRESHARK_VERSION_EXTRA = $VersionExtra"

# ----------------------------------------------------------------------------
# 1. resolve signing cert (self-signed path) - sets $CertThumbprint
#    explicit -CertThumbprint always wins; -CreateSelfSigned only fills a blank
# ----------------------------------------------------------------------------
if ($CreateSelfSigned -and -not $CertThumbprint) {
    Step 'Self-signed code-signing cert'
    $existing = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert -ErrorAction SilentlyContinue |
                Where-Object { $_.Subject -eq $SelfSignedSubject -and $_.NotAfter -gt (Get-Date) } |
                Sort-Object NotAfter -Descending | Select-Object -First 1
    if ($existing) {
        $CertThumbprint = $existing.Thumbprint
        Ok "reusing existing cert (expires $($existing.NotAfter.ToString('yyyy-MM-dd')))"
    } else {
        $new = New-SelfSignedCertificate -Type CodeSigningCert -Subject $SelfSignedSubject `
               -CertStoreLocation Cert:\CurrentUser\My -KeyAlgorithm RSA -KeyLength 2048 `
               -NotAfter (Get-Date).AddYears(5)
        $CertThumbprint = $new.Thumbprint
        Ok "minted $SelfSignedSubject (5yr)"
    }
    Write-Host "  thumbprint: $CertThumbprint" -ForegroundColor DarkGray

    if ($TrustLocally) {
        # may pop a one-time confirmation dialog; no admin needed for CurrentUser\Root
        $cer = Join-Path $env:TEMP 'ws-selfsign.cer'
        Export-Certificate -Cert "Cert:\CurrentUser\My\$CertThumbprint" -FilePath $cer | Out-Null
        Import-Certificate -FilePath $cer -CertStoreLocation Cert:\CurrentUser\Root | Out-Null
        Remove-Item $cer -ErrorAction SilentlyContinue
        Ok 'imported to CurrentUser\Root (trusted on this machine only)'
    }
}

# locate signtool only if we're signing (Windows SDK; newest version wins)
$signtool = $null
if ($CertThumbprint) {
    $signtool = Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\bin\*\x64\signtool.exe' -ErrorAction SilentlyContinue |
                Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
    if (-not $signtool) { $signtool = (Get-Command signtool.exe -ErrorAction SilentlyContinue).Source }
    if (-not $signtool) { Fail 'signing requested but signtool.exe not found - install the Windows SDK' }
    Ok "signtool: $signtool"
}

if (-not (Test-Path $BuildDir)) { Fail "build dir not found: $BuildDir" }
Push-Location $BuildDir

# ----------------------------------------------------------------------------
# 2. (optional) drop sign-wireshark.bat for internal-binary signing, on PATH
# ----------------------------------------------------------------------------
$configureExtra = @()
if ($SignInternals) {
    if (-not $CertThumbprint) { Fail '-SignInternals requires a cert (-CreateSelfSigned or -CertThumbprint)' }
    Step 'Stage sign-wireshark.bat (internal signing)'
    $batDir = Join-Path $BuildDir 'signtools'
    New-Item -ItemType Directory -Force -Path $batDir | Out-Null
    $bat = Join-Path $batDir 'sign-wireshark.bat'
    @"
@echo off
rem Auto-generated by build-installer.ps1 - signs a single file passed as %~1
"$signtool" sign /sha1 $CertThumbprint /fd sha256 /tr $TimestampUrl /td sha256 %~1
"@ | Set-Content -Path $bat -Encoding ascii
    if ($env:PATH -notlike "*$batDir*") { $env:PATH += ";$batDir" }
    $configureExtra += '-DENABLE_SIGNED_NSIS=On'
    Ok "sign-wireshark.bat -> $bat"
}

# ----------------------------------------------------------------------------
# 3. configure - verify NSIS + version-extra actually took
# ----------------------------------------------------------------------------
Step 'Configure (cmake .)'
cmake . @configureExtra 2>&1 | Tee-Object -Variable cfg | Out-Host
if ($LASTEXITCODE) { Fail 'cmake configure failed' }

if (-not (Select-String -Path "$BuildDir\CMakeCache.txt" `
          -Pattern 'MAKENSIS_EXECUTABLE:FILEPATH=.*makensis\.exe' -Quiet)) {
    Fail 'NSIS not found in CMakeCache - install NSIS 3 and re-run'
}
Ok 'makensis cached'
if (($cfg -join "`n") -notmatch [regex]::Escape("EV: $VersionExtra")) {
    Fail "version-extra not applied (expected 'EV: $VersionExtra') - check the -VersionExtra param"
}
Ok 'version-extra applied'

# ----------------------------------------------------------------------------
# 4. guides - the chunked User's Guide is what the installer doc-glob needs
# ----------------------------------------------------------------------------
Step 'Build all_guides'
cmake --build . --config $Config --target all_guides
if ($LASTEXITCODE) { Fail 'all_guides failed' }
if (-not (Test-Path "$BuildDir\doc\wsug_html_chunked\index.html")) {
    Fail "wsug_html_chunked\index.html missing - xsltproc not producing the User's Guide"
}
Ok "User's Guide chunked HTML present"

# ----------------------------------------------------------------------------
# 5. installer (prep then nsis - prep fetches Npcap/USBPcap + stages license)
# ----------------------------------------------------------------------------
Step 'Build wireshark_nsis_prep'
cmake --build . --config $Config --target wireshark_nsis_prep
if ($LASTEXITCODE) { Fail 'wireshark_nsis_prep failed (network fetch of Npcap/USBPcap?)' }

Step 'Build wireshark_nsis'
cmake --build . --config $Config --target wireshark_nsis
if ($LASTEXITCODE) { Fail 'wireshark_nsis failed' }

$installer = Get-ChildItem "$BuildDir\packaging\nsis\Wireshark-*-x64.exe" -ErrorAction SilentlyContinue |
             Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $installer) { Fail 'installer .exe not produced in packaging\nsis' }
Ok "installer: $($installer.Name)  ($([math]::Round($installer.Length/1MB,1)) MB)"

# ----------------------------------------------------------------------------
# 6. sign the final installer  (BEFORE hashing)
# ----------------------------------------------------------------------------
if ($CertThumbprint) {
    Step 'Sign installer'
    & $signtool sign /sha1 $CertThumbprint /fd sha256 /tr $TimestampUrl /td sha256 /d 'Wireshark' $installer.FullName
    if ($LASTEXITCODE) { Fail 'signtool sign failed' }
    & $signtool verify /pa $installer.FullName
    if ($LASTEXITCODE) {
        Write-Host "  WARN: verify /pa failed - expected for an untrusted self-signed cert (use -TrustLocally to clear locally)" -ForegroundColor Yellow
    } else { Ok 'signature verified' }
} else {
    Write-Host "`n(skipping signing - no cert)" -ForegroundColor DarkGray
}

# ----------------------------------------------------------------------------
# 7. hash  (covers signed bytes when signing ran)
# ----------------------------------------------------------------------------
Step 'SHA-256'
$hash = (Get-FileHash $installer.FullName -Algorithm SHA256).Hash.ToLower()
$line = "$hash  $($installer.Name)"          # sha256sum -c compatible (two spaces)
$line | Out-File "$($installer.FullName).sha256" -Encoding ascii
Ok "$($installer.Name).sha256 written"
Write-Host "  $line"

Pop-Location
Step 'Done'
Write-Host $installer.FullName -ForegroundColor Green
