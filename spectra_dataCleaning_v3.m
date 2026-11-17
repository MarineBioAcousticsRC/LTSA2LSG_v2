% spectra_dataCleaning_v3.m  (new version of spectra_dataCleaning_Saving_Plotting*.m; see README_old_vs_new.md)
%
% Second step after LSG_batch_Kait.m / GOM_runHourlyAves.m. Loads the
% *HourlyAves.mat files for a site, optionally cleans them, computes daily
% (median of hourly) spectra, band levels and seasonal spectra, saves
% <region>_<site>_Hourly/Daily_cleaned_<outTag>.mat/.csv and makes plots.
%
% inPath can be EITHER one site folder (contains *HourlyAves.mat) OR a root
% folder whose subfolders are sites (e.g. ...\GOM Ambient Noise\HourlyAves).
% The site name is the folder name.
%
% Cleaning, by region:
%   clean = 1  -> generic FIFO removal (all regions): if the FIFO frequency is
%                 > 1.4 dB above its neighbour, +/-2 bins around each FIFO
%                 harmonic are interpolated (50 Hz harmonics for 200 kHz data,
%                 80 Hz for 320 kHz). Deployments where this triggers are listed.
%                 SOCAL / CHNMS also get their site-specific FIFO, bad-day and
%                 tone removal (hand-tuned; see removeFIFO / removeBadHoursSOCAL).
%   trimDeckTest -> all regions: hours before each deployment's Data_Start in the
%                 HARP data summary (the deck test) are dropped.
%   threshold  -> SOCAL only by default: hours with 18-25 Hz band outside
%                 50-103 dB and days >= 82 dB are set to NaN (they used to be
%                 deleted). Off for GOM -- it removed good data there.
%
% Outputs
%   masterDFhour : [datenum Y M D H  bands]
%   masterDFday  : [datenum Y M D  bands  spectrum 0:1000 Hz]
%   Also saved: freq (Hz, for the spectrum columns), hourCols, dayCols, info.
%   Use dayCols / freq to find the spectrum columns (they start after the bands).
%   Bands depend on region (see getBands):
%     GOM   : octave bands 31.5, 63, 125, 500 Hz (MPL TM 678), band level in dB re 1 uPa^2,
%             then SPL40Hz = the 1 Hz bin at 40 Hz (dB re 1 uPa^2/Hz)
%     other : 18-25, 40-48, 56-71, 708-891 Hz (SOCAL), mean spectrum level in dB re 1 uPa^2/Hz
%
% Tested in MATLAB R2023a.

close all; clearvars; clc;

%% ------------------------- User settings --------------------------------
region  = 'GOM';     % 'GOM', 'SOCAL', 'CHNMS', ...
inPath  = 'L:\Shared drives\MBARC_GOM\GOM x SIO x NOAA\GOM Ambient Noise\HourlyAves\';
sites   = {};        % batch mode: subfolders to run, e.g. {'DT','GC'}; {} = all
ftype   = '*HourlyAves.mat';
outRoot = '';        % '' = save next to the inputs (each site folder)
outTag  = 'v3';      % output file version: <region>_<site>_Daily_cleaned_<outTag>.mat

minValidDate   = datetime(2004,1,1); % hours stamped earlier are bad timestamps -> dropped (and reported)
clean          = 1;  % 1 = FIFO removal (+ SOCAL/CHNMS site-specific cleaning); used for GOM v3
                     %     (44 of 127 GOM df100 deployments have FIFO at 50 Hz harmonics)
applyThreshold = []; % [] = region default (SOCAL on, others off); true/false to force
trimDeckTest   = true; % drop hours before each deployment's Data_Start in the HARP data summary
                       % (the deck test); deployments not in the summary: drop a <=3 h block at
                       % the start that is followed by a > 3 h gap
harpSummary    = 'C:\Users\nposd\Documents\GitHub\LTSA2LSG_v2\HARPDataSummary_20261016.xlsx';
writeReadme    = true; % write README.txt in each site folder (what each file is, which script made it)

% LSG colour axis
cxMIN = 40;
cxMAX = 110;

% Plots to make
Seasonal  = true;    % seasonal spectra
Bands_hr  = false;   % hourly band time series
Bands_day = false;   % daily band time series
LSG       = true;    % long-term spectrogram

%% ------------------------- Find sites -----------------------------------
cfg = struct('region', region, 'ftype', ftype, 'outRoot', outRoot, 'outTag', outTag, ...
    'clean', clean, 'minValidDate', minValidDate, 'cxMIN', cxMIN, 'cxMAX', cxMAX, 'Seasonal', Seasonal, ...
    'Bands_hr', Bands_hr, 'Bands_day', Bands_day, 'LSG', LSG);
if isempty(applyThreshold)
    cfg.applyThreshold = strcmpi(region, 'SOCAL');
else
    cfg.applyThreshold = logical(applyThreshold);
end
cfg.trimDeckTest = trimDeckTest;
cfg.writeReadme  = writeReadme;
cfg.dataStart    = containers.Map('KeyType', 'char', 'ValueType', 'double');
if trimDeckTest
    cfg.dataStart = readHarpDataStart(harpSummary);
    [~, hsName, hsExt] = fileparts(harpSummary);
    cfg.harpSummaryName = [hsName hsExt];
else
    cfg.harpSummaryName = '';
end

if ~isempty(dir(fullfile(inPath, ftype)))          % single site folder
    [~, siteName] = fileparts(regexprep(inPath, '[\\/]+$', ''));
    siteList = {siteName};
    sitePaths = {inPath};
    logDir = fileparts(regexprep(inPath, '[\\/]+$', ''));
else                                               % root folder of sites
    logDir = inPath;
    d = dir(inPath);
    d = d([d.isdir] & ~ismember({d.name}, {'.','..'}));
    if ~isempty(sites)
        d = d(ismember({d.name}, sites));
    end
    siteList = {d.name};
    sitePaths = fullfile(inPath, siteList);
end
fprintf('%d site folder(s) under %s\n', numel(siteList), inPath);
cfg.newPipelineFiles = readHourlyAvesLogs(logDir);   % HourlyAves made by GOM_runHourlyAves.m

%% ------------------------- Run ------------------------------------------
summary = cell(0, 3);
for k = 1:numel(siteList)
    site = siteList{k};
    if isempty(dir(fullfile(sitePaths{k}, ftype)))
        fprintf('(%2d/%2d) %-6s: no %s files - skipped\n', k, numel(siteList), site, ftype);
        summary(end+1, :) = {site, 'SKIPPED', 'no HourlyAves files'}; %#ok<SAGROW>
        continue
    end
    fprintf('(%2d/%2d) %-6s: processing ...\n', k, numel(siteList), site);
    try
        msg = processSite(cfg, site, fullfile(sitePaths{k}, filesep));
        summary(end+1, :) = {site, 'DONE', msg}; %#ok<SAGROW>
        fprintf('         %s\n', msg);
    catch ME
        summary(end+1, :) = {site, 'FAILED', ME.message}; %#ok<SAGROW>
        fprintf(2, '         FAILED: %s\n', ME.message);
    end
end
disp(cell2table(summary, 'VariableNames', {'Site', 'Status', 'Detail'}))


%% ========================================================================
function msg = processSite(cfg, site, fpath)
region = cfg.region;
listing = dir(fullfile(fpath, cfg.ftype));
outDir = fpath;
if ~isempty(cfg.outRoot)
    outDir = fullfile(cfg.outRoot, site, filesep);
end
if ~isfolder(outDir), mkdir(outDir); end

freq = (0:1000)';
SPL = [];
datnum = [];
poff = datenum([2000 0 0 0 0 0]);
fifoHit = {};
deck = cell(numel(listing), 6);   % deployment, method, hours dropped, first hour kept, TF file, made by

%% Load files (+ FIFO removal, deck test removal)
for f = 1:numel(listing)
    lsg = load(fullfile(listing(f).folder, listing(f).name));
    fq = lsg.freq(:);
    if numel(fq) < 1001 || any(abs(fq(1:1001) - (0:1000)') > 1e-6)
        error('%s: expected 1 Hz bins from 0 Hz (got %d bins, df = %g)', ...
            listing(f).name, numel(lsg.freq), lsg.freq(2) - lsg.freq(1));
    end
    if cfg.clean == 1
        [lsg, hit] = removeFIFO(lsg, region, site);
        if hit, fifoHit{end+1} = lsg.dBaseName; end %#ok<AGROW>
    end
    t = lsg.ptime(:) + poff;
    depID = regexprep(listing(f).name, '(_df\d+)?_?HourlyAves\.mat$', '');
    if cfg.trimDeckTest
        [keep, method] = deckTestMask(t, depID, cfg.dataStart);
    else
        keep = true(size(t)); method = 'not trimmed (trimDeckTest = false)';
    end
    firstKept = '';
    if any(keep), firstKept = datestr(min(t(keep)), 'yyyy-mm-dd HH:MM'); end
    tfName = '';
    if isfield(lsg, 'tf_file'), [~, tfName, tfExt] = fileparts(char(lsg.tf_file)); tfName = [tfName tfExt]; end
    if ismember(listing(f).name, cfg.newPipelineFiles), madeBy = 'GOM_runHourlyAves.m'; else, madeBy = 'LSG_batch_Kait.m'; end
    deck(f, :) = {depID, method, sum(~keep), firstKept, tfName, madeBy};
    SPL = [SPL lsg.mpwrtf(1:1001, keep)]; %#ok<AGROW>
    datnum = [datnum; t(keep)]; %#ok<AGROW>
end
deckTbl = cell2table(deck, 'VariableNames', {'Deployment', 'DeckTestMethod', 'HoursDropped', 'FirstHourKept', 'TF', 'HourlyAvesMadeBy'});
nDeck = sum(deckTbl.HoursDropped);

%% Drop bad timestamps, sort, round to the hour
badTime = datnum < datenum(cfg.minValidDate);
nBadTime = sum(badTime);
if nBadTime > 0
    fprintf('         dropped %d hour(s) stamped before %s: %s\n', nBadTime, ...
        string(cfg.minValidDate, 'yyyy-MM-dd'), strjoin(cellstr(datestr(datnum(badTime), 'yyyy-mm-dd HH:MM'))', ', '));
end
datnum = datnum(~badTime);
SPL = SPL(:, ~badTime);
[datnum, fOrder] = sort(datnum);
SPL = SPL(:, fOrder);
datnum = datenum(dateshift(datetime(datnum, 'ConvertFrom', 'datenum'), 'start', 'hour'));

%% Site-specific bad days / tones (SOCAL only)
if cfg.clean == 1 && strcmpi(region, 'SOCAL')
    SPL = removeBadHoursSOCAL(SPL, datnum, site);
end
SPL(SPL == 0) = NaN;   % masks above insert zeros

%% Daily = median of hourly
TT = retime(timetable(datetime(datnum, 'ConvertFrom', 'datenum'), SPL'), 'daily', 'median');
dailySPL2 = TT.Var1';
dailydatnum = datenum(TT.Time);

% Deployment-specific daily removals (SOCAL only, kept from original code)
if strcmpi(region, 'SOCAL')
    if strcmp(site, 'C')
        rm = [220, 569, 862, 630, 52, 749, 2955, 3657, 5026, 5025, 568, 65, 863, 1106];
    elseif strcmp(site, 'B')
        rm = [487, 198, 1754, 1077, 1193, 2863, 4874, 5194, 4099, 5429, 3192, 796];
    else
        rm = [];
    end
    rm = rm(rm <= numel(dailydatnum));
    dailySPL2(:, rm) = [];
    dailydatnum(rm) = [];
end

%% Band levels (freq index = Hz + 1)
[bands, bandNames, bandTitles, bandUnits, perHz] = getBands(region);
% perHz(b) true : mean spectrum level in the band (dB re 1 uPa^2/Hz)
%          false: band level, summed over the band (dB re 1 uPa^2)
bandLvl = @(X, b, ph) 10*log10(sum(10.^(X(b+1, :)/10), 1)) - ph*10*log10(numel(b));
nB = numel(bands);
hrBand = cell(1, nB); dayBand = cell(1, nB);
for b = 1:nB
    hrBand{b}  = bandLvl(SPL,       bands{b}, perHz(b));
    dayBand{b} = bandLvl(dailySPL2, bands{b}, perHz(b));
end

%% Seasons
[YY, MM, DD, HH] = datevec(datnum);
[YYd, MMd, DDd]  = datevec(dailydatnum);
season = {MMd <= 3, MMd >= 4 & MMd <= 6, MMd >= 7 & MMd <= 9, MMd >= 10};
seasonSPL = cellfun(@(i) median(dailySPL2(:, i), 2, 'omitnan'), season, 'UniformOutput', false);

%% Tables
colv = @(c) cell2mat(cellfun(@(x) x(:), c, 'UniformOutput', false));
masterDFhour = [datnum YY MM DD HH colv(hrBand)];
masterDFday  = [dailydatnum YYd MMd DDd colv(dayBand) dailySPL2'];
hourCols = [{'datenum','year','month','day','hour'}, bandNames];
dayCols  = [{'datenum','year','month','day'}, bandNames, arrayfun(@(x) sprintf('%dHz', x), freq', 'UniformOutput', false)];

%% Amplitude threshold (18-25 Hz band) -> NaN
nHrFlag = 0; nDayFlag = 0;
if cfg.applyThreshold
    if ~isequal(bands{1}, 18:25)
        error('The amplitude threshold is defined on the 18-25 Hz band, which region %s does not use', region);
    end
    x = masterDFhour(:, 6);
    badHr = ~(x < 103 & x > 50) & ~isnan(x);
    masterDFhour(badHr, 6:end) = NaN;
    for b = 1:nB, hrBand{b}(badHr) = NaN; end
    x = masterDFday(:, 5);
    badDay = ~(x < 82) & ~isnan(x);
    masterDFday(badDay, 5:end) = NaN;
    dailySPL2(:, badDay) = NaN;
    for b = 1:nB, dayBand{b}(badDay) = NaN; end
    nHrFlag = sum(badHr); nDayFlag = sum(badDay);
end

%% Save
info = struct('region', region, 'site', site, 'clean', cfg.clean, ...
    'applyThreshold', cfg.applyThreshold, 'bandNames', {bandNames}, 'bandHz', {bands}, 'bandUnits', {bandUnits}, ...
    'nHoursThresholded', nHrFlag, ...
    'nDaysThresholded', nDayFlag, 'nBadTimestampsDropped', nBadTime, 'fifoRemovedFrom', {fifoHit}, ...
    'trimDeckTest', cfg.trimDeckTest, 'harpSummary', cfg.harpSummaryName, ...
    'nDeckTestHoursDropped', nDeck, 'deckTest', deckTbl, ...
    'inputFiles', {{listing.name}}, 'created', datetime('now'));
base = fullfile(outDir, [region '_' site]);
save([base '_Hourly_cleaned_' cfg.outTag '.mat'], 'masterDFhour', 'hourCols', 'info')
save([base '_Daily_cleaned_'  cfg.outTag '.mat'], 'masterDFday', 'dayCols', 'freq', 'info')
writetable(array2table(masterDFhour, 'VariableNames', hourCols), [base '_Hourly_cleaned_' cfg.outTag '.csv'])
writetable(array2table(masterDFday,  'VariableNames', dayCols),  [base '_Daily_cleaned_'  cfg.outTag '.csv'])

%% Plots
startDate = min([datnum; dailydatnum]);
endDate   = max([datnum; dailydatnum]);
plotBase  = fullfile(outDir, sprintf('%s_%s', region, site));

if cfg.Seasonal
    fig = figure;
    cols = [0 0.4470 0.7410; 0.8500 0.3250 0.0980; 0.9290 0.6940 0.1250; 0.4940 0.1840 0.5560];
    for s = 1:4
        semilogx(freq, seasonSPL{s}, 'Color', cols(s,:), 'LineWidth', 2); hold on
    end
    grid on
    legend('Winter (JFM)', 'Spring (AMJ)', 'Summer (JAS)', 'Fall (OND)')
    xlim([10 800]); set(gca, 'XTick', [10 20 50 100 250 500])
    ylabel('Spectrum Level (dB re 1\muPa^2/Hz)'); xlabel('Frequency (Hz)')
    title(['Seasonal Spectra ', region, ' ', site])
    saveFig(fig, [plotBase '_SeasonalSpectra']);
end
if cfg.Bands_hr
    saveFig(plotBands(datnum, hrBand, bandTitles, bandUnits, startDate, endDate), [plotBase '_Bands_Hourly']);
end
if cfg.Bands_day
    saveFig(plotBands(dailydatnum, dayBand, bandTitles, bandUnits, startDate, endDate), [plotBase '_Bands_Daily']);
end
if cfg.LSG
    fig = figure;
    surf(dailydatnum, freq, dailySPL2, 'LineStyle', 'none');
    view([0 90]); set(gca, 'YScale', 'log', 'TickDir', 'out')
    xlim([startDate endDate]); ylim([15 1000])
    d = datevec(dailydatnum);
    [~, idxm] = unique(d(:, 1:2), 'rows');
    [~, idxy] = unique(d(:, 1), 'rows');
    ax = gca; ax.XAxis.MinorTick = 'on'; ax.XAxis.MinorTickValues = dailydatnum(idxm);
    set(gca, 'XTick', dailydatnum(idxy))
    datetick('x', 'mmm yyyy', 'keeplimits')
    colormap jet; caxis([cfg.cxMIN cfg.cxMAX])
    cb = colorbar; ylabel(cb, 'Spectrum Level (dB re 1\muPa^2/Hz)')
    ylabel('Frequency (Hz)'); title([region, ' ', site, ' LSG'])
    set(gcf, 'Position', [688 481 965 163])
    saveFig(fig, [plotBase '_LSG']);
end

msg = sprintf('%d files, %d hours, %d days, %s to %s', numel(listing), numel(datnum), ...
    numel(dailydatnum), datestr(startDate, 'yyyy-mm-dd'), datestr(endDate, 'yyyy-mm-dd'));
if cfg.applyThreshold
    msg = sprintf('%s; threshold NaN''d %d hours, %d days', msg, nHrFlag, nDayFlag);
end
if nBadTime > 0
    msg = sprintf('%s; dropped %d bad timestamp(s)', msg, nBadTime);
end
if cfg.trimDeckTest
    msg = sprintf('%s; deck test: %d hour(s) dropped from %d of %d deployments', msg, nDeck, ...
        sum(deckTbl.HoursDropped > 0), height(deckTbl));
    noSum = deckTbl.Deployment(~startsWith(deckTbl.DeckTestMethod, 'HARP'));
    if ~isempty(noSum)
        msg = sprintf('%s (not in HARP summary: %s)', msg, strjoin(noSum, ', '));
    end
end
if cfg.clean == 1
    if isempty(fifoHit), fifoStr = 'none'; else, fifoStr = strjoin(fifoHit, ', '); end
    msg = sprintf('%s; FIFO removed in: %s', msg, fifoStr);
end
if cfg.writeReadme
    writeSiteReadme(outDir, cfg, site, info, bandNames, bandUnits, bands, ...
        sprintf('%s to %s', datestr(startDate, 'yyyy-mm-dd'), datestr(endDate, 'yyyy-mm-dd')), ...
        numel(datnum), numel(dailydatnum));
end
end

%% ========================================================================
% Deck test helpers are separate files: readHarpDataStart.m, deckTestMask.m
function files = readHourlyAvesLogs(logDir)
% HourlyAves files written (Status DONE) by GOM_runHourlyAves.m, from its CSV logs.
files = {};
L = dir(fullfile(logDir, '*HourlyAves_log_*.csv'));
for k = 1:numel(L)
    T = readtable(fullfile(L(k).folder, L(k).name), 'Delimiter', ',', 'TextType', 'char');
    if ~all(ismember({'Status', 'Output'}, T.Properties.VariableNames)), continue, end
    out = T.Output(strcmp(T.Status, 'DONE'));
    [~, n, e] = cellfun(@fileparts, out, 'UniformOutput', false);
    files = [files; strcat(n, e)]; %#ok<AGROW>
end
files = unique(files);
end

function writeSiteReadme(outDir, cfg, site, info, bandNames, bandUnits, bands, span, nHr, nDay)
% README.txt for a site folder: what every file is and which repo script made it.
region = cfg.region; tag = cfg.outTag; pre = [region '_' site];
repo = 'https://github.com/MarineBioAcousticsRC/LTSA2LSG_v2';
fid = fopen(fullfile(outDir, 'README.txt'), 'w');
c = onCleanup(@() fclose(fid));
p = @(varargin) fprintf(fid, [varargin{1} '\r\n'], varargin{2:end});
p('%s %s AMBIENT NOISE - what is in this folder', region, site);
p('Written by spectra_dataCleaning_v3.m on %s. Rerunning it rewrites this file.', datestr(now, 'yyyy-mm-dd'));
p('Code: %s  (old vs new scripts: README_old_vs_new.md)', repo);
p('');
p('PROCESSING CHAIN');
p('  1. HARP LTSA (*_df100.ltsa)  ->  <deployment>_df100_HourlyAves.mat     (one per deployment)');
p('  2. all HourlyAves            ->  %s_Hourly/Daily_cleaned_%s.mat/.csv + LSG/seasonal plots', pre, tag);
p('                                   (spectra_dataCleaning_v3.m)');
p('  3. HourlyAves + Daily %s     ->  %s_LSG_HourlyAves_*.png, %s_LSG_Daily%s_*.png/.fig', tag, pre, pre, upper(tag));
p('                                   (GOM_plotLSGupdate.m; run after step 2)');
p('');
p('-------------------------------------------------------------------------------');
p('1. <deployment>_df100_HourlyAves.mat  (inputs; never modified by later steps)');
p('   Hourly mean spectra, 1 Hz bins 0-1000 Hz, transfer function (TF) applied, dB re 1 uPa^2/Hz.');
p('   Variables: ptime (datenum = ptime + datenum([2000 0 0 0 0 0])), mpwrtf (freq x hour), freq,');
p('   nmave, tf_file, dBaseName, Ptf. Not cleaned: FIFO noise and the deck test are still in them.');
p('   Made by:');
p('     GOM_runHourlyAves.m -> GOM_LTSAspectra.m   (2026 onwards; latest TF revision, logged in');
p('                                                  ..\\GOM_HourlyAves_log_*.csv)');
p('     LSG_batch_Kait.m -> LTSAdailySpectra_auto.m (older files)');
p('');
p('   %-24s %-34s %-24s %-6s %s', 'Deployment', 'Made by', 'TF', 'Deck h', 'First hour kept in cleaned files');
D = info.deckTest;
for i = 1:height(D)
    p('   %-24s %-34s %-24s %6d %s', D.Deployment{i}, D.HourlyAvesMadeBy{i}, D.TF{i}, D.HoursDropped(i), D.FirstHourKept{i});
end
p('   ("Deck h" = deck-test hours dropped from the cleaned files; method per deployment in info.deckTest)');
p('');
p('-------------------------------------------------------------------------------');
p('2. %s_Hourly_cleaned_%s.mat / .csv  and  %s_Daily_cleaned_%s.mat / .csv', pre, tag, pre, tag);
p('   Made by spectra_dataCleaning_v3.m (region = ''%s'', outTag = ''%s'') on %s.', region, tag, datestr(info.created, 'yyyy-mm-dd'));
p('   Covers %s: %d hours, %d days.', span, nHr, nDay);
p('');
p('   Cleaning applied:');
if cfg.trimDeckTest
    p('   - Deck test removed: hours before each deployment''s Data_Start in %s', cfg.harpSummaryName);
    p('     are dropped (%d hours in total; per deployment in the table above).', info.nDeckTestHoursDropped);
    p('     Deployments not in the summary: a <= 3 h block at the start followed by a > 3 h gap is dropped.');
else
    p('   - Deck test NOT removed (trimDeckTest = false).');
end
if info.clean == 1
    if isempty(info.fifoRemovedFrom), s = 'none'; else, s = strjoin(info.fifoRemovedFrom, ', '); end
    p('   - FIFO noise (50 Hz harmonics, +/-2 Hz) interpolated out where the 100 or 150 Hz bin is');
    p('     > 1.4 dB above its neighbour. Removed from: %s', s);
else
    p('   - FIFO noise NOT removed (clean = 0).');
end
p('   - Hours stamped before %s dropped: %d.', datestr(cfg.minValidDate, 'yyyy-mm-dd'), info.nBadTimestampsDropped);
if info.applyThreshold
    p('   - Amplitude threshold applied: %d hours, %d days set to NaN.', info.nHoursThresholded, info.nDaysThresholded);
else
    p('   - No amplitude threshold (that SOCAL rule removed good data in the GOM; see Old files\\README.txt).');
end
p('');
p('   Hourly table (masterDFhour; .csv has the same columns with a header row):');
p('     %s', strjoin([{'datenum','year','month','day','hour'}, bandNames], ', '));
p('   Daily table (masterDFday): datenum, year, month, day, %s,', strjoin(bandNames, ', '));
c0 = 5 + numel(bands);
p('     then the daily median spectrum, 0-1000 Hz in 1 Hz bins (columns %d-%d; column %d = 0 Hz).', c0, c0 + 1000, c0);
p('   Daily spectrum = median of that day''s hourly spectra, in dB re 1 uPa^2/Hz.');
p('   Band columns:');
for b = 1:numel(bands)
    if numel(bands{b}) == 1, hz = sprintf('%d Hz', bands{b}); else, hz = sprintf('%d-%d Hz', bands{b}(1), bands{b}(end)); end
    p('     %-14s %-12s %s', bandNames{b}, hz, strrep(bandUnits{b}, '\mu', 'u'));
end
if strcmpi(region, 'GOM')
    p('     OB* = octave bands from MPL TM 678 (sec. 4.4.1): 31.5 Hz = airguns, 63 and 125 Hz =');
    p('     shipping (125 Hz also Rice''s whale calls), 500 Hz = weather. Band level = sum over the');
    p('     1 Hz bins. SPL40Hz = spectrum level of the single 1 Hz bin at 40 Hz.');
    p('     Hourly values: from each hourly spectrum. Daily values: from the daily median spectrum.');
end
p('   The .mat files also hold hourCols / dayCols (column names), freq (Hz of the spectrum columns)');
p('   and info (settings, input files, FIFO and deck-test details).');
p('');
p('-------------------------------------------------------------------------------');
p('FIGURES');
p('   %s_LSG.png/.fig              spectra_dataCleaning_v3.m  daily median spectra (cleaned %s)', pre, tag);
p('   %s_SeasonalSpectra.png/.fig  spectra_dataCleaning_v3.m  median daily spectrum per season', pre);
p('   %s_Bands_Hourly/Daily.*      spectra_dataCleaning_v3.m  band levels over time (if made)', pre);
p('   %s_LSG_HourlyAves_<years>_<newest deployment>.png', pre);
p('                                  GOM_plotLSGupdate.m  hourly spectra from HourlyAves (NOT cleaned)');
p('   %s_LSG_Daily%s_<years>_<newest deployment>.png/.fig', pre, upper(tag));
p('                                  GOM_plotLSGupdate.m  from the Daily_cleaned_%s file', tag);
p('   Note: GOM_plotLSGupdate.m figures are only as new as its last run. Rerun it after');
p('   spectra_dataCleaning_v3.m to pick up changes to the cleaned files.');
sub = dir(outDir);
sub = sub([sub.isdir] & ~ismember({sub.name}, {'.', '..'}));
if ~isempty(sub)
    p('');
    p('-------------------------------------------------------------------------------');
    p('SUBFOLDERS');
    for k = 1:numel(sub)
        if strcmp(sub(k).name, 'Old files')
            p('   Old files\\  v2 outputs (spectra_dataCleaning_Saving_Plotting.m). Do not use; see the README there.');
        else
            p('   %s\\  not used by spectra_dataCleaning_v3.m, which only reads the *%s files in this', sub(k).name, cfg.ftype(2:end));
            p('   %s   folder (1 Hz bins, 0-1000 Hz). Deployments that exist only in here are not in the', repmat(' ', 1, numel(sub(k).name)));
            p('   %s   cleaned files above.', repmat(' ', 1, numel(sub(k).name)));
        end
    end
end
end

%% ========================================================================
function fig = plotBands(t, band, titles, units, startDate, endDate)
fig = figure;
for b = 1:numel(band)
    subplot(numel(band), 1, b)
    plot(t, band{b}, 'Color', [0 0.4470 0.7410], 'Marker', 'o', 'LineStyle', 'none')
    xlim([startDate endDate]); datetick('x', 'mm yyyy', 'keeplimits')
    ylabel(units{b}); title(titles{b})
end
end

%% ========================================================================
function [bands, names, titles, units, perHz] = getBands(region)
% Bands of interest per region. units: one string per band; perHz(b) true = mean
% spectrum level in the band (dB re 1 uPa^2/Hz), false = summed band level (dB re 1 uPa^2).
if strcmpi(region, 'GOM')
    % Octave bands from MPL TM 678 (LISTEN GoMex 2020-2025, sec. 4.4.1, Fig. 125):
    % 31.5 Hz = airguns, 63 and 125 Hz = shipping (125 Hz also Rice's whale calls),
    % 500 Hz = weather. Edges fc/sqrt(2) to fc*sqrt(2), whole 1 Hz bins inside them,
    % summed band level (same as GOM_octaveBandLevels.m). No fin/blue whales in the GOM.
    % Plus the single 1 Hz bin at 40 Hz (spectrum level), added last so the octave
    % band columns keep their positions.
    fc = [31.5 63 125 500];
    bands = [arrayfun(@(f) ceil(f/sqrt(2)):floor(f*sqrt(2)), fc, 'UniformOutput', false), {40}];
    names  = {'OB31_5Hz', 'OB63Hz', 'OB125Hz', 'OB500Hz', 'SPL40Hz'};
    titles = {'Airguns (31.5 Hz octave)', 'Shipping (63 Hz octave)', ...
              'Shipping / Rice''s whale (125 Hz octave)', 'Weather (500 Hz octave)', '40 Hz (1 Hz bin)'};
    units = [repmat({'dB re 1\muPa^2'}, 1, 4), {'dB re 1\muPa^2/Hz'}];
    perHz = [false false false false true];
else
    % Original SOCAL bands (mean spectrum level in the band)
    bands  = {18:25, 40:48, 56:71, 708:891};
    names  = {'SPL_18_25Hz', 'SPL_40_48Hz', 'SPL_56_71Hz', 'SPL_708_891Hz'};
    titles = {'Fin Whale (18 - 25 Hz)', 'Blue Whale (40 - 48 Hz)', 'Ship Noise (56 - 71 Hz)', 'Wind Noise (708 - 891 Hz)'};
    units = repmat({'dB re 1\muPa^2/Hz'}, 1, 4);
    perHz = true(1, 4);
end
end

function saveFig(fig, base)
exportgraphics(fig, [base '.png'], 'Resolution', 300);
savefig(fig, [base '.fig']);
close(fig);
end

%% ========================================================================
function [lsg, hit] = removeFIFO(lsg, region, site)
% Generic FIFO removal for all regions + SOCAL/CHNMS site-specific extras.
% Logic unchanged from the original spectra_dataCleaning script.
hit = false;
P = lsg.mpwrtf;
if numel(lsg.freq) > 1001
    % 320 kHz: 80 Hz harmonics
    if mean(P(81,:)) - mean(P(78,:)) > 1.4 || mean(P(161,:)) - mean(P(158,:)) > 1.4
        hit = true;
        for c = 80*(1:12), P(c-2:c+2, :) = NaN; end
        P = fillmissing(P(1:1001, :), 'spline', 1);
    end
    if strcmpi(region, 'SOCAL') && strcmp(site, 'C')
        if mean(P(361,:)) - mean(P(365,:)) > 1.4 || mean(P(181,:)) - mean(P(185,:)) > 1.4
            hit = true;
            for c = 30*(2:33), P(c-3:c+3, :) = NaN; end
            P = fillmissing(P(1:1001, :), 'spline', 1);
        end
    end
    if strcmpi(region, 'CHNMS')
        k_extra = [160,236,240,400,472,480,560,708,720,800];
        k_test = k_extra(k_extra-2 >= 1 & k_extra+1 <= size(P,1));
        if any(arrayfun(@(c) mean(P(c+1,:)) - mean(P(c-2,:)) > 1.4, k_test))
            hit = true;
            k_mask = k_extra(k_extra-2 >= 1 & k_extra+2 <= size(P,1));
            for c = k_mask, P(c-2:c+2, :) = NaN; end
            P = fillmissing(P, 'spline', 1);
        end
    end
elseif numel(lsg.freq) == 1001
    % 200 kHz: 50 Hz harmonics
    if mean(P(101,:)) - mean(P(99,:)) > 1.4 || mean(P(151,:)) - mean(P(148,:)) > 1.4
        hit = true;
        for c = 50*(1:20), P(c-2:c+2, :) = NaN; end
        P = fillmissing(P(1:1001, :), 'spline', 1);
    end
    if strcmpi(region, 'SOCAL')
        if any(strcmp(site, {'C','N','B'}))
            if mean(P(376,:)) - mean(P(370,:)) > 1.4 || mean(P(876,:)) - mean(P(886,:)) > 1.4
                hit = true;
                for c = 25*(1:40), P(c-2:c+2, :) = NaN; end
                P = fillmissing(P(1:1001, :), 'spline', 1);
            end
            if mean(P(361,:)) - mean(P(365,:)) > 1.4 || mean(P(181,:)) - mean(P(185,:)) > 1.4
                hit = true;
                for c = 30*(2:33), P(c-2:c+2, :) = NaN; end
                P = fillmissing(P(1:1001, :), 'spline', 1);
            end
        end
        if strcmp(site, 'B')
            % [test bin, reference bin, harmonic spacing or single bin, n harmonics]
            rules = [21 24 20 50; 31 35 30 50; 48 44 48 20; 16 11 16 66; ...
                     46 2 46 1; 76 72 76 1; 106 102 106 1; 196 192 196 1; 136 132 136 1];
            for r = 1:size(rules, 1)
                if mean(P(rules(r,1),:)) - mean(P(rules(r,2),:)) > 1.4
                    hit = true;
                    for c = rules(r,3)*(1:rules(r,4))
                        P(max(c-2,1):min(c+2,size(P,1)), :) = NaN;
                    end
                end
            end
            if strcmp(lsg.dBaseName, 'CINMS_B_45')
                P = P + 13;   % calibration correction for this deployment
            end
            P = fillmissing(P(1:1001, :), 'spline', 1);
        end
    end
end
lsg.mpwrtf = P;
end

%% ========================================================================
function SPL = removeBadHoursSOCAL(SPL, datnum, site)
% Hand-identified bad periods and per-hour tone thresholds for SOCAL sites.
% Unchanged from the original script; flagged hours are zeroed (-> NaN later).
switch site
    case 'SN'
        bad = datnum > 734050 & datnum < 734054 | datnum > 734222 & datnum < 734244;
        SPL(:, bad) = 0;
        tones = SPL(end,:) > 80 | SPL(end,:) < 20 | SPL(50,:) > 105 | SPL(201,:) > 79 | SPL(207,:) < 40;
    case 'C'
        bad = datnum > 733516 & datnum < 733613 | datnum > 733613 & datnum < 733670 | datnum > 734019 & datnum < 734074 | ...
            datnum > 736242 & datnum < 736316 | datnum > 738092 & datnum < 738205 | datnum > 738678 & datnum < 738783 | ...
            datnum > 733670 & datnum < 733689 | datnum > 739022 & datnum < 739103 | datnum > 734370 & datnum < 734458 | ...
            datnum > 734556 & datnum < 734562;
        SPL(:, bad) = 0;
        tones = SPL(901,:) > 78 | SPL(end,:) < 20 | SPL(55,:) < 62 | SPL(300,:) > 105 | SPL(21,:) > 112 | ...
            SPL(21,:) < 67 | SPL(101,:) > 96 | SPL(501,:) > 85 | SPL(501,:) < 44 | SPL(901,:) < 38 | ...
            SPL(151,:) > 92 | SPL(71,:) > 99 | SPL(91,:) > 96 | SPL(90,:) > 94 | SPL(206,:) > 81 | ...
            SPL(135,:) > 88 | SPL(997,:) > 76 | SPL(998,:) > 76 | SPL(412,:) > 86;
    case 'N'
        bad = datnum > 736014 & datnum < 736116 | datnum > 736289 & datnum < 736438 | datnum > 737506 & datnum < 737513;
        SPL(:, bad) = 0;
        tones = SPL(901,:) > 80 | SPL(901,:) < 30 | SPL(61,:) < 55 | SPL(61,:) > 99 | SPL(23,:) > 100;
    case 'B'
        bad = datnum > 733452 & datnum < 733507 | datnum > 734314 & datnum < 734400 | datnum > 736242 & datnum < 736256 | ...
            datnum > 736643 & datnum < 736713 | datnum > 737391 & datnum < 737530 | datnum > 733984 & datnum < 734017 | ...
            datnum < 732000 | datnum > 736127 & datnum < 736145 | datnum > 737112 & datnum < 737209 | ...
            datnum > 737239 & datnum < 737252;
        SPL(:, bad) = 0;
        tones = SPL(901,:) > 77 | SPL(901,:) < 40 | SPL(21,:) > 116 | SPL(61,:) > 99 | SPL(23,:) > 122 | ...
            SPL(890,:) < 40 | SPL(501,:) < 40 | SPL(701,:) > 79 | SPL(18,:) < 49;
    case 'E'
        tones = SPL(901,:) > 73.5 | SPL(901,:) < 33.5 | SPL(409,:) > 90 | SPL(18,:) > 120 | ...
            SPL(426,:) > 86 | SPL(101,:) > 94 | SPL(101,:) < 48;
    case 'H'
        bad = datnum > 734953 & datnum < 735071 | datnum > 735355 & datnum < 735484 | datnum > 736240 & datnum < 736289 | ...
            datnum > 737002 & datnum < 737095 | datnum > 737095 & datnum < 737250;
        SPL(:, bad) = 0;
        tones = SPL(901,:) > 77 | SPL(901,:) < 40 | SPL(21,:) > 107 | SPL(101,:) > 93 | SPL(501,:) > 79 | ...
            SPL(801,:) > 78 | SPL(41,:) > 103 | SPL(23,:) > 104 | SPL(63,:) > 97;
    otherwise
        tones = false(1, size(SPL, 2));
end
SPL(:, tones) = 0;
end
