# Xprinter XP-K200L — Setup, Troubleshooting, and ESC/POS Capabilities

Machine: `DESKTOP-HBTJ9JP`. Printer connects via USB.

## What this printer actually is

- Model: **Xprinter XP-K200L** — a thermal label/receipt-class printer, physical print
  width tops out around 3" (80mm class).
- It **cannot print real bank checks**. Standard checks are 6"–8.5" wide; this
  printer's head only spans ~3". This is a fixed hardware limit, not a driver or
  settings issue.
- It has a real motorized **auto-cutter** (confirmed — it audibly cuts).
- Intended use here: printing payment/receipt confirmations, not negotiable checks.

## How it's connected

- USB, shows up in Windows Device Manager as `PrinterPOS-80`
  (`USBPRINT\PRINTERPOS-80\...`), bound to **printer port `USB001`**.
- Two Windows print queues exist for it:
  | Queue name | Driver | Port | Purpose |
  |---|---|---|---|
  | `XP-80` | XP-80 (GDI/vendor driver) | USB001 | Normal Windows printing (Notepad, `Out-Printer`, apps that print "pages") |
  | `XP80-Raw` | Generic / Text Only (built-in Windows driver) | USB001 | Accepts **RAW** byte streams — required for ESC/POS commands (cut, bold, buzzer, barcode, etc.) |

There is also a stale/unrelated queue `XP-80C` and one named `кухня` ("kitchen")
pointed at `192.168.123.101` — those are leftovers from a different/previous
setup (possibly this same printer over network mode, or a different device) and
were not used in this setup.

## Problems found and fixed (in the order discovered)

1. **Wrong port.** The `XP-80` queue was bound to `USB002`, but the physical
   device was actually on `USB001`. Jobs went to a port nothing was listening on.
   Fixed with `Set-Printer -Name "XP-80" -PortName "USB001"`.

2. **Printer set to "Work Offline" in Windows.** This was the real root cause of
   total silence — over 50 jobs going back weeks (including the user's own prior
   test attempts) were stuck in the queue with `PagesPrinted: 0`, forever, because
   Windows was configured to never actually send anything to the device. This is
   invisible in the GUI unless you check the printer's context menu. Detected via:
   ```powershell
   Get-CimInstance -ClassName Win32_Printer -Filter "Name='XP-80'" | Select WorkOffline
   ```
   Fixed by clearing the `PRINTER_ATTRIBUTE_WORK_OFFLINE` (`1024`) bit directly:
   ```powershell
   $p = Get-CimInstance -ClassName Win32_Printer -Filter "Name='XP-80'"
   $newAttr = $p.Attributes -band (-bnot 1024)
   Set-CimInstance -InputObject $p -Property @{ Attributes = $newAttr }
   ```
   (The normal GUI checkbox is Control Panel → Devices and Printers → right-click
   the printer → untick "Use Printer Offline". The WMI method was used here because
   it's scriptable and verifiable.)

3. **Printer went into a hardware error state** (blinking red LED) at some point,
   most likely from an earlier jam at the cutter. No job will print in this state
   regardless of software config. Fixed by a physical power cycle + confirming the
   paper roll was seated correctly and the cover fully latched.

4. **The `XP-80` GDI queue rejects RAW print jobs** (`Win32 error 1804`,
   `ERROR_INVALID_DATATYPE`). Vendor GDI drivers render "pages" and often don't
   accept raw ESC/POS byte streams at all — this is why the printer would print
   plain text fine but never execute a cut command sent as raw bytes through that
   queue. Fixed by adding a **second queue** on the same port using Windows'
   built-in **"Generic / Text Only"** driver, which does accept `RAW` datatype:
   ```powershell
   Add-PrinterDriver -Name "Generic / Text Only"
   Add-Printer -Name "XP80-Raw" -DriverName "Generic / Text Only" -PortName "USB001"
   ```

5. **P/Invoke marshaling bug** when sending raw bytes via `winspool.drv`. The
   `DOCINFOA` struct's string fields were declared `[MarshalAs(UnmanagedType.LPStr)]`
   (force-ANSI) while the `StartDocPrinter` P/Invoke declaration used
   `CharSet = CharSet.Auto`, which resolved to the **Unicode** (`StartDocPrinterW`)
   entry point on this system. Mixing forced-ANSI struct fields with a
   Unicode-resolved API call corrupts the data on the unmanaged side, which
   surfaced as the same `ERROR_INVALID_DATATYPE` (1804) even against the RAW-capable
   queue. Fixed by changing the marshaling attribute to
   `[MarshalAs(UnmanagedType.LPTStr)]`, which follows the struct's own
   `CharSet.Auto` and stays consistent with whichever `StartDocPrinter` variant
   actually gets bound. See `raw_print.ps1` for the corrected version.

## Printing to it going forward

- **For normal Windows/app printing** (Notepad, `Out-Printer`, QuickBooks-style
  page output): use the **`XP-80`** queue.
- **For anything that needs the cutter, buzzer, bold text, or a barcode**: you
  must send raw ESC/POS bytes to the **`XP80-Raw`** queue. Regular Windows text
  printing through a GDI driver will never trigger these — the driver just
  renders a page image and never forwards command bytes.
- Reusable sender: `printer/raw_print.ps1` in this repo.
  ```powershell
  ./printer/raw_print.ps1 -PrinterName "XP80-Raw" -Bytes $byteArray
  ```

## ESC/POS command support — tested and confirmed on this exact unit

All commands below were sent as raw bytes through `XP80-Raw` and physically verified.

| Feature | Command (hex) | Result |
|---|---|---|
| Initialize | `ESC @` (`1B 40`) | Works |
| Full cut | `GS V 66 0` (`1D 56 42 00`) | **Cuts** |
| Partial cut | `GS V 66 1` (`1D 56 42 01`) | **Cuts — identical to full cut.** This unit does not implement a distinct partial cut; both modes fully separate the paper. Don't rely on partial cut leaving a tear-tab. |
| Bold | `ESC E 1` / `ESC E 0` (`1B 45 01` / `1B 45 00`) | **Works** — visibly bolder |
| Double width/height | `GS ! 0x11` (`1D 21 11`) | **Not supported** — prints as normal-size text. Firmware ignores this command. |
| Center alignment | `ESC a 1` (`1B 61 01`) | **Not supported** — prints flush-left regardless. Firmware ignores this command. |
| Buzzer | `ESC B n t` (`1B 42 03 03`) | **Works** — audible beep. Vendor-specific command, not standard ESC/POS, but this clone implements it. |
| Barcode (CODE39) | `GS k 4 <data> NUL` (`1D 6B 04 ...00`) | **Works** — prints a real scannable-looking barcode |

### Practical implications for anything you print on this device

- **Line width is 32 characters** at default font (confirmed via a 1–60 ruler
  test — it wraps right after column 32). Any receipt/label template must wrap
  or truncate text to 32 chars per line.
- **No hardware centering or big-text emphasis.** Since `GS !` and `ESC a` are
  both no-ops on this firmware, any "centered" or "large" text has to be faked
  in software:
  - Centering: left-pad the string with spaces, computed as
    `(32 - len(text)) / 2`, before sending it.
  - Emphasis: bold (`ESC E 1`) is the only reliable emphasis available. You can
    also fake size by manually spacing out characters (e.g. `"T O T A L"`), but
    there's no real double-height font.
- **Partial cut is not a usable feature** — always just use full cut (`GS V 66 0`);
  sending the "partial" variant buys nothing.
- **Buzzer is available** as a genuine UI signal (e.g., "job done" cue) if useful
  for a receipt-printing tool.
- **Barcode support is real**, so a receipt template can encode a reference/
  transaction number as a scannable CODE39 barcode.

## Files in this folder

- `raw_print.ps1` — sends an arbitrary raw byte array to a given Windows printer
  queue via `winspool.drv` (`OpenPrinter` → `StartDocPrinter` → `WritePrinter`).
  Fixed for the marshaling bug described above. Defaults to printer name
  `XP80-Raw`.
