% GOM_plotLSGupdate.m
%
% Long-term spectrograms (LSGs) of the full record at each GOM site, for
% presenting the newest deployments. For every site it makes:
%   1. HourlyAves LSG  (hourly TF-corrected spectra, no cleaning)
%   2. v3 daily LSG    (daily median spectra from *_Daily_cleaned_v3.mat)
%   3./4. the same two with a dashed line where the newest deployment starts
%         (only for sites that also have older deployments)
% Titles and file names list the deployments and dates included.
% 1-2 are saved in each site folder (plainDir = ''), 3-4 and a CSV of
% median band levels per deployment in outDir.
%
% A deployment counts as "new" if its first HourlyAves time is after
% newSince. Run after GOM_runHourlyAves.m and spectra_dataCleaning_v3.m.
% Tested in MATLAB R2023a.

clearvars; close all;

%% ------------------- Settings (update each year) -------------------------
root     = 'L:\Shared drives\MBARC_GOM\GOM x SIO x NOAA\GOM Ambient Noise\HourlyAves';
plainDir = '';                  % plain LSGs: '' = each site folder under root
outDir   = 'H:\GOM_LSG_2026';  % dashed-line LSGs, band-level table (and the slide deck)
newSince = datetime(2025,5,1);   % deployments starting after this are "new"
sites    = {};                   % {} = every site with a new deployment
v3tag    = 'v3';
cLim     = [40 110];             % colour axis (dB re 1 uPa^2/Hz)
fLim     = [10 1000];            % frequency range (Hz)
nF       = 300;                  % log-spaced frequency rows for the hourly plot
minValid = datetime(2004,1,1);   % drop hours stamped before this (bad timestamps)
doFull   = true;                 % full-record LSGs (plain + dashed line)
doZoom   = true;                 % v3 daily LSG of just the newest deployment (in outDir)

%% ------------------- Sites ----------------------------------------------
if ~isfolder(outDir), mkdir(outDir); end
if isempty(sites)
    d = dir(root);
    d = d([d.isdir] & ~ismember({d.name}, {'.','..'}));
    sites = {d.name};
end
poff = datenum([2000 0 0 0 0 0]);
fIdx = unique(round(logspace(log10(fLim(1)), log10(fLim(2)), nF))) + 1;  % row = Hz + 1
fHz  = fIdx - 1;

% Octave bands as in MPL TM 678 and spectra_dataCleaning_v3 (31.5 airguns, 63/125 shipping, 500 weather)
fc = [31.5 63 125 500];
bands = arrayfun(@(f) ceil(f/sqrt(2)):floor(f*sqrt(2)), fc, 'UniformOutput', false);
ds = readHarpDataStart('C:\Users\nposd\Documents\GitHub\LTSA2LSG_v2\HARPDataSummary_20261016.xlsx'); % deck test
bandRows = cell(0, 11);
summary = cell(0, 3);
for s = 1:numel(sites)
    site = sites{s};
    L = dir(fullfile(root, site, '*_df100_HourlyAves.mat'));
    if isempty(L), continue, end
    siteDir = fullfile(root, site);
    if ~isempty(plainDir), siteDir = plainDir; end

    % ---- deployments ----
    dep = struct('id', {}, 't0', {}, 't1', {}, 'file', {});
    for k = 1:numel(L)
        m = matfile(fullfile(L(k).folder, L(k).name));
        pt = m.ptime + poff;
        pt = pt(pt >= datenum(minValid));
        if isempty(pt), continue, end
        dep(end+1) = struct('id', erase(L(k).name, '_df100_HourlyAves.mat'), ...
            't0', min(pt), 't1', max(pt), 'file', fullfile(L(k).folder, L(k).name)); %#ok<SAGROW>
    end
    [~, o] = sort([dep.t0]); dep = dep(o);
    isNew = [dep.t0] >= datenum(newSince);
    if ~any(isNew)
        continue
    end
    hasOld = any(~isNew);
    newDep = dep(isNew);

    depStr = sprintf('%d deployment%s: %s', numel(dep), plural(numel(dep)), dep(1).id);
    if numel(dep) > 1, depStr = [depStr ' to ' dep(end).id]; end
    span = sprintf('%s to %s', datestr(dep(1).t0, 'mmm yyyy'), datestr(dep(end).t1, 'mmm yyyy'));
    newStr = sprintf('New: %s (%s to %s)', strjoin({newDep.id}, ', '), ...
        datestr(min([newDep.t0]), 'mmm yyyy'), datestr(max([newDep.t1]), 'mmm yyyy'));
    fileTag = sprintf('%s-%s_%s', datestr(dep(1).t0, 'yyyy'), datestr(dep(end).t1, 'yyyy'), dep(end).id);

    % ---- 1. HourlyAves on an hourly grid ----
    tStart = floor(dep(1).t0 * 24) / 24;
    tEnd   = floor(dep(end).t1 * 24) / 24;
    nT = round((tEnd - tStart) * 24) + 1;
    Z = NaN(numel(fIdx), nT, 'single');
    for k = 1:numel(dep)
        h = load(dep(k).file, 'ptime', 'mpwrtf', 'tf_file');
        t = h.ptime(:) + poff;
        ok = t >= datenum(minValid);
        col = round((floor(t(ok) * 24) / 24 - tStart) * 24) + 1;
        Z(:, col) = single(h.mpwrtf(fIdx, ok));
        % median octave band levels for this deployment (deck test excluded; FIFO not removed)
        okB = ok & deckTestMask(t, dep(k).id, ds);
        bl = cellfun(@(b) median(10*log10(sum(10.^(h.mpwrtf(b+1, okB)/10), 1)), 'omitnan'), bands);
        bandRows(end+1, :) = {site, dep(k).id, datestr(dep(k).t0, 'yyyy-mm-dd'), ...
            datestr(dep(k).t1, 'yyyy-mm-dd'), sum(okB), h.tf_file, isNew(k), bl(1), bl(2), bl(3), bl(4)}; %#ok<SAGROW>
    end
    tH = tStart + (0:nT-1) / 24;

    % ---- 2. v3 daily ----
    v3file = fullfile(root, site, sprintf('GOM_%s_Daily_cleaned_%s.mat', site, v3tag));
    haveV3 = isfile(v3file);
    if haveV3
        v = load(v3file, 'masterDFday');
        tD = v.masterDFday(:, 1)';
        D = v.masterDFday(:, 9:end)';      % 0..1000 Hz
        D = D(fIdx, :);
    end

    % ---- plots ----
    variants = {false};
    if hasOld, variants{end+1} = true; end
    if ~doFull, variants = {}; end
    if doZoom && haveV3
        z0 = floor(min([newDep.t0])); z1 = ceil(max([newDep.t1]));
        iz = tD >= z0 & tD <= z1;
        zSpan = sprintf('%s to %s', datestr(z0, 'mmm yyyy'), datestr(z1, 'mmm yyyy'));
        tz = sprintf('GOM %s  |  Daily median spectra (%s)  |  %s', site, v3tag, zSpan);
        lsgFigure(tD(iz), fHz, D(:, iz), cLim, fLim, {tz, sprintf('Newest deployment: %s', strjoin({newDep.id}, ', '))}, ...
            false, newDep, newStr, fullfile(outDir, sprintf('GOM_%s_LSG_Daily%s_%s_latestDeployment', site, upper(v3tag), newDep(end).id)));
    end
    for hv = variants
        highlight = hv{1};
        sfx = ''; if highlight, sfx = '_newDeploymentMarked'; end
        t1 = sprintf('GOM %s  |  Hourly spectra (HourlyAves, no cleaning)  |  %s', site, span);
        figDir = outDir; if ~highlight, figDir = siteDir; end
        lsgFigure(tH, fHz, Z, cLim, fLim, {t1, depStr}, highlight, newDep, newStr, ...
            fullfile(figDir, sprintf('GOM_%s_LSG_HourlyAves_%s%s', site, fileTag, sfx)));
        if haveV3
            t2 = sprintf('GOM %s  |  Daily median spectra (cleaned %s: FIFO and deck test removed)  |  %s', site, v3tag, span);
            lsgFigure(tD, fHz, D, cLim, fLim, {t2, depStr}, highlight, newDep, newStr, ...
                fullfile(figDir, sprintf('GOM_%s_LSG_Daily%s_%s%s', site, upper(v3tag), fileTag, sfx)));
        end
    end
    msg = sprintf('%s; %s', depStr, newStr);
    if ~haveV3, msg = [msg '; NO v3 daily file yet']; end
    summary(end+1, :) = {site, numel(variants) * (1 + haveV3), msg}; %#ok<SAGROW>
    fprintf('%-4s: %s\n', site, msg);
end
disp(cell2table(summary, 'VariableNames', {'Site', 'nFigures', 'Detail'}))

% Per-deployment median octave band levels (dB re 1 uPa^2, from HourlyAves, deck test excluded)
B = cell2table(bandRows, 'VariableNames', {'Site','Deployment','Start','End','nHours','TF','IsNew', ...
    'Median_OB31_5Hz','Median_OB63Hz','Median_OB125Hz','Median_OB500Hz'});
writetable(B, fullfile(outDir, 'GOM_deployment_median_band_levels.csv'));
fprintf('Band levels saved to %s\n', fullfile(outDir, 'GOM_deployment_median_band_levels.csv'));


%% ========================================================================
function lsgFigure(t, fHz, Z, cLim, fLim, ttl, highlight, newDep, newStr, base)
fig = figure('Units', 'inches', 'Position', [0.5 0.5 13.33 3.6], 'Color', 'w', 'Visible', 'off');
ax = axes(fig, 'Units', 'normalized', 'Position', [0.06 0.16 0.84 0.66]);
y = log10(fHz);
im = imagesc(ax, t, y, Z);
im.AlphaData = ~isnan(Z);              % gaps show as white, not as low levels
set(ax, 'YDir', 'normal', 'Color', 'w', 'TickDir', 'out', 'Box', 'off', 'Layer', 'top')
colormap(ax, jet); clim(ax, cLim)
yt = [10 20 50 100 200 500 1000];
yt = yt(yt >= fLim(1) & yt <= fLim(2));
set(ax, 'YTick', log10(yt), 'YTickLabel', string(yt))
ylim(ax, log10(fLim)); ylabel(ax, 'Frequency (Hz)')
xlim(ax, [t(1) t(end)])
spanYears = (t(end) - t(1)) / 365.25;
if spanYears > 4
    xt = datenum(year(datetime(t(1), 'ConvertFrom', 'datenum')):year(datetime(t(end), 'ConvertFrom', 'datenum')) + 1, 1, 1);
    set(ax, 'XTick', xt); datetick(ax, 'x', 'yyyy', 'keepticks', 'keeplimits')
elseif spanYears < 1.6
    dv = datevec(t(1)); xt = datenum(dv(1), dv(2) + (1:20), 1);
    xt = xt(xt <= t(end));
    set(ax, 'XTick', xt); datetick(ax, 'x', 'mmm yyyy', 'keepticks', 'keeplimits')
else
    datetick(ax, 'x', 'mmm yyyy', 'keeplimits')
end
cb = colorbar(ax, 'Position', [0.915 0.16 0.012 0.66]);
ylabel(cb, {'Spectrum level', '(dB re 1 \muPa^2/Hz)'})
title(ax, ttl, 'FontWeight', 'normal', 'Interpreter', 'none')
if highlight
    x0 = min([newDep.t0]);
    hold(ax, 'on')
    plot(ax, [x0 x0], log10(fLim), '-', 'Color', 'w', 'LineWidth', 3.5)
    plot(ax, [x0 x0], log10(fLim), '--', 'Color', 'k', 'LineWidth', 2)
    text(ax, x0, log10(fLim(2)) - 0.04, [newStr ' '], 'VerticalAlignment', 'top', ...
        'HorizontalAlignment', 'right', 'FontSize', 9, 'FontWeight', 'bold', ...
        'BackgroundColor', 'w', 'Margin', 1, 'Interpreter', 'none')
end
exportgraphics(fig, [base '.png'], 'Resolution', 200);
if numel(Z) < 5e6            % .fig only for daily plots; hourly ones would be ~100+ MB
    fig.Visible = 'on';
    savefig(fig, [base '.fig']);
end
close(fig);
end

function s = plural(n)
if n == 1, s = ''; else, s = 's'; end
end
