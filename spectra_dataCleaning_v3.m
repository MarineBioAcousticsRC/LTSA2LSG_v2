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
%   threshold  -> SOCAL only by default: hours with 18-25 Hz band outside
%                 50-103 dB and days >= 82 dB are set to NaN (they used to be
%                 deleted). Off for GOM -- it removed good data there.
%
% Outputs
%   masterDFhour : [datenum Y M D H  SPL18-25 SPL40-48 SPL56-71 SPL708-891]
%   masterDFday  : [datenum Y M D  SPL18-25 SPL40-48 SPL56-71 SPL708-891  spectrum 0:1000 Hz]
%   Also saved: freq (Hz, for the spectrum columns), hourCols, dayCols, info.
%   Band levels are dB re 1 uPa^2/Hz (mean spectrum level in the band).
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

% LSG colour axis
cxMIN = 40;
cxMAX = 110;

% Plots to make
Seasonal  = false;   % seasonal spectra
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

if ~isempty(dir(fullfile(inPath, ftype)))          % single site folder
    [~, siteName] = fileparts(regexprep(inPath, '[\\/]+$', ''));
    siteList = {siteName};
    sitePaths = {inPath};
else                                               % root folder of sites
    d = dir(inPath);
    d = d([d.isdir] & ~ismember({d.name}, {'.','..'}));
    if ~isempty(sites)
        d = d(ismember({d.name}, sites));
    end
    siteList = {d.name};
    sitePaths = fullfile(inPath, siteList);
end
fprintf('%d site folder(s) under %s\n', numel(siteList), inPath);

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

%% Load files (+ FIFO removal)
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
    SPL = [SPL lsg.mpwrtf(1:1001, :)]; %#ok<AGROW>
    datnum = [datnum; lsg.ptime(:) + poff]; %#ok<AGROW>
end

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
bands = {18:25, 40:48, 56:71, 708:891};
bandLvl  = @(X, b) 10*log10(sum(10.^(X(b+1, :)/10))) - 10*log10(numel(b));
hrBand  = cellfun(@(b) bandLvl(SPL, b),       bands, 'UniformOutput', false);
dayBand = cellfun(@(b) bandLvl(dailySPL2, b), bands, 'UniformOutput', false);

%% Seasons
[YY, MM, DD, HH] = datevec(datnum);
[YYd, MMd, DDd]  = datevec(dailydatnum);
season = {MMd <= 3, MMd >= 4 & MMd <= 6, MMd >= 7 & MMd <= 9, MMd >= 10};
seasonSPL = cellfun(@(i) median(dailySPL2(:, i), 2, 'omitnan'), season, 'UniformOutput', false);

%% Tables
masterDFhour = [datnum YY MM DD HH hrBand{1}' hrBand{2}' hrBand{3}' hrBand{4}'];
masterDFday  = [dailydatnum YYd MMd DDd dayBand{1}' dayBand{2}' dayBand{3}' dayBand{4}' dailySPL2'];
hourCols = {'datenum','year','month','day','hour','SPL_18_25Hz','SPL_40_48Hz','SPL_56_71Hz','SPL_708_891Hz'};
dayCols  = [hourCols([1:4 6:9]), arrayfun(@(x) sprintf('%dHz', x), freq', 'UniformOutput', false)];

%% Amplitude threshold (18-25 Hz band) -> NaN
nHrFlag = 0; nDayFlag = 0;
if cfg.applyThreshold
    x = masterDFhour(:, 6);
    badHr = ~(x < 103 & x > 50) & ~isnan(x);
    masterDFhour(badHr, 6:end) = NaN;
    for b = 1:4, hrBand{b}(badHr) = NaN; end
    x = masterDFday(:, 5);
    badDay = ~(x < 82) & ~isnan(x);
    masterDFday(badDay, 5:end) = NaN;
    dailySPL2(:, badDay) = NaN;
    for b = 1:4, dayBand{b}(badDay) = NaN; end
    nHrFlag = sum(badHr); nDayFlag = sum(badDay);
end

%% Save
info = struct('region', region, 'site', site, 'clean', cfg.clean, ...
    'applyThreshold', cfg.applyThreshold, 'nHoursThresholded', nHrFlag, ...
    'nDaysThresholded', nDayFlag, 'nBadTimestampsDropped', nBadTime, 'fifoRemovedFrom', {fifoHit}, ...
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
bandTitles = {'Fin Whale (18 - 25 Hz)', 'Blue Whale (40 - 48 Hz)', 'Ship Noise (56 - 71 Hz)', 'Wind Noise (708 - 891 Hz)'};

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
    saveFig(plotBands(datnum, hrBand, bandTitles, startDate, endDate), [plotBase '_Bands_Hourly']);
end
if cfg.Bands_day
    saveFig(plotBands(dailydatnum, dayBand, bandTitles, startDate, endDate), [plotBase '_Bands_Daily']);
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
if cfg.clean == 1
    if isempty(fifoHit), fifoStr = 'none'; else, fifoStr = strjoin(fifoHit, ', '); end
    msg = sprintf('%s; FIFO removed in: %s', msg, fifoStr);
end
end

%% ========================================================================
function fig = plotBands(t, band, titles, startDate, endDate)
fig = figure;
for b = 1:4
    subplot(4, 1, b)
    plot(t, band{b}, 'Color', [0 0.4470 0.7410], 'Marker', 'o', 'LineStyle', 'none')
    xlim([startDate endDate]); datetick('x', 'mm yyyy', 'keeplimits')
    ylabel('dB re 1\muPa^2/Hz'); title(titles{b})
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
