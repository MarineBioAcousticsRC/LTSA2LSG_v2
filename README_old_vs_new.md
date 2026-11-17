# Old vs new ambient-noise scripts

This repo builds hourly/daily spectra from HARP LTSAs in two steps. Both steps now have
a newer version alongside the original. The original scripts are unchanged.

| Step | Old (still here, unchanged) | New |
|---|---|---|
| 1. LTSA → `*_HourlyAves.mat` | `LSG_batch_Kait.m` → `LTSAdailySpectra_auto.m` | `GOM_runHourlyAves.m` → `GOM_LTSAspectra.m` (+ `GOM_readSiteTable.m`) |
| 2. HourlyAves → cleaned daily/hourly tables + plots | `spectra_dataCleaning_Saving_Plotting.m`, `..._BatchRun.m`, `..._BatchRun_Function.m` | `spectra_dataCleaning_v3.m` |

---

## Step 1: making HourlyAves files

### Is the output different?
The averaging is unchanged. Both versions read 5 time slices (5 s spectral averages) per raw
file, average them (in dB) within each hour, and add the transfer function. Output files have
the same name (`<Data_ID>_df100_HourlyAves.mat`) and variables
(`ptime, mpwrtf, freq, nmave, tf_file, dBaseName, Ptf`).

One small difference: `ptime` for an hour that spans two LTSA files is now the first time in the
hour. The old code used the start of the second file.

### What changed
| | Old (`LSG_batch_Kait.m`) | New (`GOM_runHourlyAves.m`) |
|---|---|---|
| Which deployments | You point it at one folder | Reads the cruise activity table (`GOM_YYYY_sites.docx`), keeps rows whose Activity says "Recover", skips rows marked lost (`*`), and finds the deployment folders on the decimated drives |
| New vs already processed | Manual | Only deployments whose data start after `minDataStart`. Never overwrites an existing output unless `overwrite = true` |
| Multi-disk deployments | One LTSA folder at a time | Collects the `*_df100.ltsa` from every `diskNN_df100` folder of a deployment into one output file |
| Deployment → preamp | Fuzzy match of the LTSA name against the HARP summary (first partial match wins) | Exact `Data_ID` match. `preampOverride` sets the preamp for deployments not yet in the summary |
| Preamp → TF | First file whose first 4 characters contain the preamp number; rev B, else rev A | Exact preamp number; **always the latest revision** (highest letter, e.g. C over B over A). The old code never used rev C or later |
| Failures | Returns with only a console warning if no deployment or TF match (no output file, easy to miss in a batch) | Each deployment gets DONE / SKIPPED / FAILED with a reason |
| Output folder | One folder for everything | `<outRoot>\<SITE>\`, new site folders created as needed. 4-channel codes like `DT_18_01` get their own folder so they are not mixed into the single-channel time series |
| Log | none | Summary table printed and saved as `GOM_HourlyAves_log_<date>.csv` in `outRoot` |
| Dry run | no | `dryRun = true` lists what would run without reading any data |

### Running it each year
1. Put the new cruise table (`GOM_YYYY_sites.docx`) and the latest HARP data summary in the repo.
2. In `GOM_runHourlyAves.m`, update `siteTableDocx`, `harpSummary`, `decimatedRoots` and `minDataStart`.
3. Run with `dryRun = true`. Check the table, especially FAILED rows (usually a deployment
   missing from the HARP summary; add its preamp to `preampOverride` or to the summary).
4. Run with `dryRun = false`. Each deployment takes roughly 10–15 min over the network.

To (re)build a site that isn't in this year's cruise table, set `manualSites = {'TUX'}` and an early
`minDataStart` (e.g. `datetime(2004,1,1)`). Only deployments with `*_df100` LTSAs can be processed
(e.g. GOM_TUX_01 was recorded at 20 kHz and has no df100 LTSA).

---

## Step 2: cleaning, tables and plots

### What the old script does
1. **FIFO removal** (`clean = 1` only). Generic for all regions (50 Hz harmonics for 200 kHz data,
   80 Hz for 320 kHz), plus SoCal sites C/N/B and CHNMS-specific harmonics. Also adds +13 dB to
   `CINMS_B_45`.
2. **Bad days and tones** (`clean = 1`, SoCal only). Hand-picked date ranges and per-hour
   single-frequency limits for sites SN, C, N, B, E and H.
3. **Daily spectra** = median of the hourly spectra; band levels; seasonal medians.
4. **Amplitude threshold, always applied, whatever `clean` is set to.** Hours whose 18–25 Hz
   band is outside 50–103 dB, and days at or above 82 dB, are **deleted** from `masterDFhour` /
   `masterDFday`. These limits were tuned for SoCal. The LSG figure is drawn *before* this
   step, so it doesn't show the loss.

### Why the threshold matters for GOM
The GOM is much louder at low frequency (seismic surveys, ships), so the 18–25 Hz band
routinely goes above 82 dB. Example, GOM Y5A (Aug 2024 – Jun 2025):

| | Days | Hours |
|---|---|---|
| In the HourlyAves input | 316 | 7,557 |
| Kept in existing `GOM_Y5A_*_cleaned_v2.mat` | **21** | **4,860** |
| Kept in `v3` (GOM default) | 316 | 7,557 |

The rows that v2 kept are identical in v3 (difference 0). The only change is the data that v2
dropped. **Anything built from the GOM `*_cleaned_v2.mat` / `*_cleaned.csv` files should be
checked.** The `*_HourlyAves.mat` files themselves were never thresholded.

### What changed in `spectra_dataCleaning_v3.m`
| | Old | New (v3) |
|---|---|---|
| Files | 3 copies (single site, batch wrapper, batch body) | One script. `inPath` can be a single site folder or a folder of site folders (`sites = {}` = all, or a list) |
| Threshold | Always on; rows deleted | `applyThreshold = []` means on for SOCAL, off for every other region; `true`/`false` overrides it. Flagged rows are **set to NaN, not deleted**, and the count is reported |
| FIFO removal | Same logic, but the GOM runs used `clean = 0`, so **no GOM v2 file had FIFO removed** | Same logic, **on for GOM v3** (`clean = 1`). Only deployments where the 100 or 150 Hz bin is > 1.4 dB above its neighbour are changed (44 of 127 GOM df100 deployments, e.g. most DC and RW ones). Which deployments were changed is saved in `info.fifoRemovedFrom` |
| SoCal/CHNMS site rules | Inline | Same rules, moved into `removeFIFO` / `removeBadHoursSOCAL` functions and only used for those regions |
| Bad timestamps | Kept (e.g. one `GofMX_DC05` hour stamped 2000-01-11 stretched the DC plots back to 2000) | Hours stamped before `minValidDate` (2004-01-01) are dropped and reported |
| Frequency axis | Assumed 1 Hz bins (`freq = 0:1:1000`) | Checks the HourlyAves `freq` and stops with an error if it isn't 1 Hz bins from 0 Hz |
| Output names | `<region>_<site>_Daily_cleaned_v2.mat`, `..._cleaned.csv` | `<region>_<site>_Daily_cleaned_<outTag>.mat/.csv` (`outTag = 'v3'`), so v2 files are not overwritten. `outRoot` can redirect output elsewhere |
| Deck test | Kept (the 1–3 h recorded on deck before deployment, 10–30 dB louder at 500 Hz, was in every table) | Hours before each deployment's `Data_Start_Date` + `Data_Start_Time` in the HARP data summary are dropped (`trimDeckTest = true`). Deployments not in the summary: a ≤ 3 h block at the start followed by a > 3 h gap is dropped. Per deployment in `info.deckTest` |
| Bands (GOM) | SoCal bands: fin whale 18–25, blue whale 40–48, ship 56–71, wind 708–891 Hz | Octave bands from MPL TM 678 (sec. 4.4.1): **31.5 Hz** (airguns), **63 / 125 Hz** (shipping; 125 Hz also Rice's whale), **500 Hz** (weather). Edges fc/√2–fc·√2, summed band level in dB re 1 µPa² (same as `GOM_octaveBandLevels.m` and report Fig. 125), plus `SPL40Hz`, the single 1 Hz bin at 40 Hz (dB re 1 µPa²/Hz). Other regions keep the SoCal bands |
| Self-describing outputs | none | Adds `freq`, `hourCols`/`dayCols` (column names) and `info` (settings, input files, counts) to the .mat; CSVs have header rows |
| Site README | none | `README.txt` in each site folder: every file, which repo script made it, HourlyAves pipeline and TF per deployment, deck-test hours dropped, FIFO removal, band definitions |
| Errors in batch mode | One failure is printed, then it continues | Same, plus a summary table at the end |

For SOCAL, v3 gives the same values as the old script. The only difference is that thresholded
hours/days are NaN rows instead of missing rows.

### Output columns
- `masterDFhour`: `datenum, year, month, day, hour`, then the band columns
- `masterDFday`: `datenum, year, month, day`, the same band columns, then the daily median
  spectrum for **0–1000 Hz in 1 Hz bins**
- GOM v3 bands (5): `OB31_5Hz, OB63Hz, OB125Hz, OB500Hz` (octave band levels, dB re 1 µPa²) and
  `SPL40Hz` (40 Hz bin, dB re 1 µPa²/Hz). The daily spectrum is in columns 10–1010 (column 10 = 0 Hz).
- v2 and non-GOM bands (4): `SPL_18_25Hz, SPL_40_48Hz, SPL_56_71Hz, SPL_708_891Hz`, mean spectrum
  level in the band, dB re 1 µPa²/Hz. The daily spectrum is in columns 9–1009.
- Find the spectrum by name (`dayCols` = `'0Hz'`) rather than by column number.

---

## Step 3: figures and slides for the yearly update (GOM)

| Script | What it makes |
|---|---|
| `GOM_plotLSGupdate.m` | Full-record v3 daily LSG per site (plain, and with a dashed line at the newest deployment) and a zoom of the newest deployment |
| `GOM_octaveBandLevels.m` | Median hourly-average octave band levels (31.5, 63, 125, 500 Hz) per deployment and per site for the report period, as in MPL TM 678 sec. 4.4.1 |
| `GOM_monthlyOctaveBands.m` | Monthly octave band medians through each new deployment, to spot hydrophone sensitivity drop-off |
| `GOM_makeSlides.ps1` | PowerPoint deck from the figures, the octave band tables and a `site_observations.txt` file (one line of notes per site) |

Run them in that order. Octave bands: 31.5 Hz = airguns, 63/125 Hz = shipping (125 Hz also Rice's whale calls), 500 Hz = weather.
