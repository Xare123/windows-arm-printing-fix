# Color instrumentation — can native Windows match the bridge's color?

The WSL/CUPS bridge prints noticeably **richer color** than printing to the same printer through Windows' native IPP driver — even at the same Best/600 setting, same paper. This documents **why**, and a controlled way to test whether native Windows can be tuned to match (which would let you retire the bridge and use the native printer, with every option already in the standard print dialog).

## Why CUPS looks better (the short version)

Both paths render the page with the **same Windows GDI engine** — the bridge just captures the result as a PDF first (*Microsoft Print to PDF*), which poppler then rasterizes. So the pixels start out identical. The real difference is **color management**:

- **CUPS path:** no color‑management daemon (`colord`) runs in WSL, so CUPS hands the printer the document's **exact sRGB** values and lets the *printer* do the device‑color conversion — the same as AirPrint / macOS.
- **Native path:** Windows' ICM/WCS (and/or the app, e.g. Acrobat) applies a color transform **before** sending, which desaturates.

So CUPS doesn't *add* richness — it avoids *subtracting* it.

## Instrument: `COLORTARGET.pdf`

`bridge/COLORTARGET.pdf` is a US‑Letter chart of 18 known‑sRGB patches (primaries, secondaries, "pop" colors, skin/earth tones) plus smooth gradient bars for banding. Regenerate with `bridge/backend/makecolortarget.sh`.

## CUPS reference — captured 2026‑06‑22

Rendering `COLORTARGET.pdf` through the CUPS renderer (poppler; no `colord` ⇒ sRGB passthrough) and sampling each patch's center pixel — reproduce with `bridge/backend/extract-cups-colors.sh COLORTARGET.pdf`:

| patch | input sRGB | CUPS sends | Δ |
|---|---|---|---|
| R | 255,0,0 | 255,0,0 | 0 |
| G | 0,255,0 | 0,255,0 | 0 |
| B | 0,0,255 | 0,0,255 | 0 |
| C | 0,255,255 | 0,255,255 | 0 |
| M | 255,0,255 | 255,0,255 | 0 |
| Y | 255,255,0 | 255,255,0 | 0 |
| orange | 255,128,0 | 255,128,0 | 0 |
| teal | 0,161,161 | 0,161,161 | 0 |
| purple | 128,0,199 | 128,0,199 | 0 |
| crimson | 219,20,61 | 219,20,61 | 0 |
| sky | 0,153,255 | 0,153,255 | 0 |
| grass | 41,179,41 | 41,178,41 | 1 |
| skin 1 | 240,199,171 | 240,199,171 | 0 |
| skin 2 | 199,150,120 | 199,150,120 | 0 |
| skin 3 | 150,99,79 | 150,99,79 | 0 |
| brown | 140,69,18 | 140,69,18 | 0 |
| olive | 128,128,0 | 128,128,0 | 0 |
| navy | 0,0,128 | 0,0,128 | 0 |
| | | **total Δ = 1** | (one rounding bit on green) |

**CUPS reproduces every color byte‑for‑byte.** This is the "correct" target the native path should match. It also confirms the diagnosis: the flatness is **not** introduced by the printer or by CUPS — it's introduced on the **native Windows** side, before the job is sent.

## Native A/B test — do this with the printer on your LAN

1. Print `COLORTARGET.pdf` to the **native** "Brother …" printer **and** to the **"Full Quality (1200)"** bridge.
2. Lay the two prints side by side. On a color chart the desaturation is obvious — note which patches go pale on the native one (likely the saturated ones: crimson, teal, sky, purple).
3. Toggle the fixes below (re‑printing the native chart each time) until it matches the bridge print:
   - **Acrobat → Print → Advanced → "Let printer determine colors"** — the usual culprit.
   - **Printer → Printer properties → Color Management → Advanced →** set the profile to **sRGB** and intent to Perceptual/Saturation, or "let printer manage color."
   - Re‑add the printer over a clean **IPP** connection (not WSD).
   - Control: print from **Edge/Word** to isolate whether it's the app or Windows.
4. *(Advanced, for exact numbers)* capture the bytes the native driver actually sends — e.g. point the printer at a logging IPP target — and compare per‑patch values against the reference table above.

If native matches CUPS, **native printing replaces the bridge** (all options already in the dialog, no WSL). If it gets close but not equal, keep the bridge for color‑critical work.

## Status
- ✅ **2026-06-26 RESOLVED (printer on the LAN): native is NOT fixable; the bridge is the answer.** Associating an sRGB ICC profile with the printer (per-user, via the Windows Color System API) AND forcing Best quality both still printed flat: the driverless IPP path ignores the OS profile (vendor color needs a Print Support App, which the J4335DW lacks). Meanwhile the bridge's own capture stage was proven color-faithful (its `Microsoft Print To PDF` capture, rendered by poppler, matched the original sRGB exactly), so routing through CUPS is precisely what delivers the vivid color. Use the bridge for color-critical work.
- ✅ **CUPS reference captured** (table above) — byte‑perfect sRGB.
- ⏳ **Native capture + tuning** — needs the printer (do it when home).
