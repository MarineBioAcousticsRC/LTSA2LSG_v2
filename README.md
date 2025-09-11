# LTSA2LSG_v2

This repo contains two main MATLAB scripts for producing long-term spectrograms (LSGs) and (optionally) cleaning spectra for FIFO/tonal artifacts before plotting and export.

1. **`LSG_batch_Kait.m`** — **run this first**  
   Batch-builds hourly/daily spectra from LTSA folders and produces LSG plots.  
   _Does not remove FIFO artifacts or tones._

2. **`spectra_dataCleaning_save&plot.m`** — optional second pass  
   Loads the `*hourlyAves.mat` files created in step 1. Cleans FIFO/tones (generic + region/site-specific rules), recomputes bands & seasons, and produces/saves plots alongside cleaned `.mat`/`.csv` outputs.

---

## Requirements

- MATLAB **R2023a** (tested)
- Helper functions on MATLAB path:
  - `LTSAdailySpectra_auto.m`
  - `plotDailyLSG.m`
  - `plotDailyLSG_clean.m`
- Inputs:
  - Root **LTSA directory** with deployment subfolders (for step 1)
  - `HARPDataSummary_*.csv`
  - Transfer function (TF) folder (e.g., `MBARC_TFs`)

---

## Typical Workflow

### Step 1 — Build & plot LSGs (no cleaning)

Run **`LSG_batch_Kait.m`**. Set paths/params at the top:

```matlab
thisDisk = 'S:\CHNMS\NO\df100';  % root folder with deployments
NumAves  = 5;                    % spectra per raw file
timeResol = 2;                   % 0=month, 1=day, 2=hour
harpDataSummaryCSV = 'L:\...\HARPDataSummary_20240618.csv';
outDisk  = 'L:\...\df100\hourly';  % where *hourlyAves.mat are written
TFsFolder = 'L:\Shared drives\MBARC_TF';
