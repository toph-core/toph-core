# Kiosk TLS Handshake Fix (Windows) — `CERTIFICATE_VERIFY_FAILED`

**Date:** 2026-07-09
**Area:** Networking / TLS trust (Flutter Windows kiosk)
**Status:** Fixed in app code, verified. Pending rebuild + redeploy to kiosk.

---

## TL;DR

A freshly installed Windows kiosk (wired ethernet, internet working) failed **every**
HTTPS API call with:

```
DioException [unknown]: null
Error: HandshakeException: Handshake error in client (OS Error:
 CERTIFICATE_VERIFY_FAILED: unable to get local issuer certificate
 (../../../flutter/third_party/boringssl/src/ssl/handshake.cc:298))
```

Root cause: that machine's **Windows system root store was stale** and missing
Let's Encrypt's new **ISRG Root X1/X2** certificates. Flutter/Dart on Windows
validates TLS against the Windows system store, so the handshake failed — while
browsers (which ship their own root store) kept working, masking the problem.

Fix: **bundle the ISRG roots inside the app** and add them to Dio's
`SecurityContext` (on top of platform roots), so the app trusts the backend
regardless of any single machine's system store — **without disabling
certificate verification.**

---

## S — Situation

- One Windows kiosk, wired ethernet (no Wi-Fi). General internet worked fine
  (browser loaded pages, connectivity OK).
- As soon as the app issued an HTTPS request to `https://api.maryai.uz`, Dio
  threw `HandshakeException … CERTIFICATE_VERIFY_FAILED: unable to get local
  issuer certificate`.
- The error appeared **only on this machine** — other installs were fine.
- The wrapped error surfaced to the app as an opaque `DioException [unknown]: null`.

The exact string `unable to get local issuer certificate` is specific: it means
the TLS client **could not find the issuer (a CA certificate)** needed to build a
trusted chain from the server's certificate up to a trusted root. It is *not* an
expiry/clock error and *not* a DNS/routing error.

## T — Task

Make the kiosk able to complete HTTPS requests to the backend, such that:

1. The fix is **secure** — no disabling of certificate verification (this is a
   POS/kiosk handling business data).
2. The fix is **durable for the whole fleet** — one build should work on every
   current and future kiosk, not require hand-touching each machine.
3. The root cause is actually understood, not papered over.

## A — Action

### 1. Confirmed the server is NOT the problem

Inspected what `api.maryai.uz` actually presents (read-only, from a dev machine):

```bash
echo | openssl s_client -connect api.maryai.uz:443 -servername api.maryai.uz 2>/dev/null \
  | grep -E "Verify return code|Verification"
# -> Verification: OK  /  Verify return code: 0 (ok)
```

The server sends a **complete, valid Let's Encrypt chain** and verifies cleanly
against an up-to-date trust store. So the failure was client/machine-side.

### 2. Found the trust anchor the client needs

Full chain presented by the server:

```
[1] api.maryai.uz      <- issued by  YE2
[2] YE2                <- issued by  ISRG Root YE
[3] ISRG Root YE       <- issued by  ISRG Root X2
[4] ISRG Root X2       <- issued by  ISRG Root X1   <- trust anchor the client needs
```

This is Let's Encrypt's **new 2024–2025 hierarchy** (Root YE / YE2 / ISRG Root
X2). To validate it, the client must trust **ISRG Root X1** (the widely
distributed RSA root, via cross-sign) or **ISRG Root X2**.

### 3. Explained why only one machine failed (and why the browser didn't)

- On **Windows**, Flutter/Dart's default TLS validation reads the **Windows
  system root store** (via CryptoAPI).
- Modern **Chrome/Edge/Firefox ship their own bundled root store**, so browsing
  worked even though the OS store was stale.
- This kiosk's Windows root store was old / locked-down (kiosk images often have
  automatic root update via `ctldl.windowsupdate.com` firewalled), so it lacked
  the newer ISRG roots. Result: the app failed, the browser didn't.

> **Caveat considered:** the same error can also come from a network TLS-intercepting
> proxy/firewall with a private CA. Distinguish by running on the kiosk:
> `openssl s_client -connect api.maryai.uz:443 -servername api.maryai.uz | grep issuer`
> — issuer `Let's Encrypt / YE2` ⇒ stale root store (this fix); a corporate CA
> name ⇒ interception (bundle that proxy CA instead, same code path).

### 4. Chose the durable, secure fix

Options weighed:

| Option | Verdict |
| --- | --- |
| Disable cert verification (`badCertificateCallback => true`) | **Rejected** — insecure for a POS. |
| Per-machine: install ISRG roots into Windows store (`certutil -addstore Root …`) | Valid quick relief, but must be repeated per device and per future root. |
| **App-level: bundle ISRG roots + add to `SecurityContext`** | **Chosen** — one build fixes the whole fleet, keeps verification on. |

### 5. Implemented it

- Downloaded ISRG Root X1 & X2 from `letsencrypt.org` and **verified their
  SHA-256 fingerprints** against the canonical values before bundling.
- Kept `withTrustedRoots: true` so all other hosts still validate via platform
  roots; the bundled ISRG roots are added **on top**.
- Wired the context into Dio via `IOHttpClientAdapter`.

## R — Result

### Files changed

| File | Change |
| --- | --- |
| `assets/certs/isrg_roots.pem` | **New** — bundled ISRG Root X1 + X2 (fingerprints verified authentic). |
| `pubspec.yaml` | Registered `assets/certs/` under `flutter: assets:`. |
| `lib/core/api/app_security_context.dart` | **New** — `buildAppSecurityContext()`: platform roots **+** bundled ISRG roots; never weakens verification. |
| `lib/core/api/dio_client.dart` | Added optional `securityContext` param; sets `IOHttpClientAdapter` with the trust context. |
| `lib/di.dart` | Builds the context (async DI) and injects it into `DioClient`. |

### Verification performed

- `flutter analyze` on the three changed Dart files → **No issues found.**
- **End-to-end TLS proof:** built a `SecurityContext(withTrustedRoots: false)`
  (the harshest simulation of a machine with an empty root store) trusting **only**
  the bundled `isrg_roots.pem`, then made a real request to `https://api.maryai.uz`.
  Handshake **succeeded** (HTTP 404 = server responded, TLS validated). This proves
  the bundled roots alone are sufficient to trust the backend — exactly the kiosk
  scenario.

### Next steps

1. **Rebuild and redeploy** the Windows build (`flutter build windows`) to the
   kiosk. The fix ships in the binary — no per-machine setup.
2. Optional immediate relief for the one kiosk before a new build lands:
   `certutil -addstore -f Root isrgrootx1.crt` + `… isrg-root-x2.crt` (Admin).
3. Run the kiosk-side `openssl` issuer check to rule out TLS interception.

### Known gap / follow-up

- `lib/core/service/minio/minio_service.dart` has a **separate** `Dio`
  (`_externalHttp`) for direct external image downloads that does **not** go
  through `DioClient`. If media is served from the same new Let's Encrypt
  hierarchy, image loading on the stale kiosk will fail the same way. Extend the
  fix by reusing the same `SecurityContext` there.

---

## Appendix — Why this is safe

- Verification is **never disabled**. We only **add** well-known, fingerprint-verified
  public CA roots to the trust set.
- `withTrustedRoots: true` is preserved, so every other host continues to validate
  against the platform's normal trust store.
- If the bundled roots can't be added (e.g. already present, or asset unreadable),
  the code falls back to platform-only behavior — worst case is the original
  behavior, never a weaker one.
