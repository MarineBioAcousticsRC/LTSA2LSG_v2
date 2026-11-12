% GOM_runHourlyAves.m
%
% Yearly GOM update: build *_df100_HourlyAves.mat files (TF-corrected mean
% spectra per hour, same method as LSG_batch_Kait.m / LTSAdailySpectra_auto.m)
% for every deployment recovered on the latest GOM cruise.
%
% What it does
%   1. Reads the cruise activity table (.docx) and keeps rows whose Activity
%      contains "Recover". Rows marked lost ("*" in the duration column) are
%      skipped.
%   2. For each site code, finds deployment folders on the decimated-data
%      drives (e.g. \\frosty\GofMX_Decimated_12\GOM_GC_18) whose data start
%      after minDataStart.
%   3. Looks up the deployment's preamp in the HARP data summary (exact
%      Data_ID match) and picks that preamp's TF (rev B, else rev A -- the
%      same rule earlier runs used).
%   4. Averages all *_df100.ltsa files from every disk of the deployment and
%      saves <outRoot>\<SITE>\<Data_ID>_df100_HourlyAves.mat. New sites get a
%      new folder. Existing outputs are never overwritten unless overwrite=true.
%   5. Prints a summary and saves it as a CSV log in outRoot.
%
% Every year: update the settings in the first section, run once with
% dryRun = true to check what will be processed, then run with dryRun = false.
%
% Needs on the path: GOM_LTSAspectra.m, GOM_readSiteTable.m, loadTF.m,
% read_ltsahead.m, read_ltsahead_nrf_only.m. Tested in MATLAB R2023a.

clearvars; close all;
global PARAMS %#ok<GVMIS,NUSED>

%% ------------------- Settings (update each year) -------------------------
siteTableDocx  = 'C:\Users\nposd\Documents\GitHub\LTSA2LSG_v2\GOM_2026_sites.docx';
harpSummary    = 'C:\Users\nposd\Documents\GitHub\LTSA2LSG_v2\HARPDataSummary_20261016.xlsx';
decimatedRoots = {'\\frosty.ucsd.edu\GofMX_Decimated_11', ...
                  '\\frosty.ucsd.edu\GofMX_Decimated_12'};
outRoot        = 'L:\Shared drives\MBARC_GOM\GOM x SIO x NOAA\GOM Ambient Noise\HourlyAves';
TFsFolder      = 'L:\Shared drives\MBARC_TF';

minDataStart   = datetime(2025,5,1);  % only deployments whose data start after this
dfWhat         = '100';               % decimation factor folder/LTSA to use
NumAves        = 5;                   % time slices read per raw file
timeResList    = 2;                   % 2 = hourly; use [2 1] to also make dailyAves

% Preamp numbers for deployments that are missing from the HARP summary,
% e.g. preampOverride('GOM_GC_18') = 999;
% (Better: add the missing deployment to the HARP summary spreadsheet.)
preampOverride = containers.Map('KeyType','char','ValueType','double');

overwrite      = false;   % true = recompute even if the output file exists
dryRun         = false;   % true = only report what would be processed

%% ------------------- Load inputs ----------------------------------------
sites = GOM_readSiteTable(siteTableDocx);
sites = sites(sites.Recover, :);
fprintf('%d sites to recover in %s\n', height(sites), siteTableDocx);

S = readtable(harpSummary, 'TextType', 'string');
S.key = lower(strrep(S.Data_ID, '-', ''));

tfList = dir(fullfile(TFsFolder, '**', '*_HARP.tf'));
tfTok  = regexp({tfList.name}, '^(\d+)_\d+_([A-Za-z])_HARP\.tf$', 'tokens', 'once');

depFolders = {};
for r = 1:numel(decimatedRoots)
    d = dir(decimatedRoots{r});
    d = d([d.isdir] & startsWith({d.name}, 'GOM_'));
    depFolders = [depFolders; fullfile({d.folder}', {d.name}')]; %#ok<AGROW>
end
[~, depNames] = cellfun(@fileparts, depFolders, 'UniformOutput', false);

%% ------------------- Process each site ----------------------------------
runLog = cell(0, 8);   % SiteCode, Deployment, Status, Detail, PreAmp, TF, DataStart, Output

for s = 1:height(sites)
    code = strtrim(sites.SiteCode{s});
    if sites.Lost(s)
        runLog(end+1,:) = {code, '', 'SKIPPED', 'Marked lost (*) in site table', NaN, '', '', ''}; %#ok<SAGROW>
        continue
    end

    % Site codes with a deployment suffix (e.g. DT_18_01, a 4-channel HARP)
    % match that deployment exactly and get their own folder so they are not
    % mixed into the single-channel site time series.
    if contains(code, '_')
        pat = ['^GOM_' regexptranslate('escape', code) '(_C4)?$'];
        siteFolder = code;
    else
        pat = ['^GOM_' code '_\d+(_00)?$'];
        siteFolder = code;
    end
    hit = find(~cellfun(@isempty, regexpi(depNames, pat, 'once')));
    if isempty(hit)
        runLog(end+1,:) = {code, '', 'SKIPPED', 'No deployment folder found on the decimated drives', NaN, '', '', ''}; %#ok<SAGROW>
        continue
    end

    nNew = 0; older = {};
    for h = hit'
        depFolder = depFolders{h};
        depID = depNames{h};

        % data start from the first x.wav of the first disk
        diskDirs = dir(fullfile(depFolder, ['*_df' dfWhat]));
        diskDirs = diskDirs([diskDirs.isdir]);
        if isempty(diskDirs)
            runLog(end+1,:) = {code, depID, 'FAILED', ['No *_df' dfWhat ' disk folders'], NaN, '', '', ''}; %#ok<SAGROW>
            nNew = nNew + 1;
            continue
        end
        [~, ord] = sort({diskDirs.name}); diskDirs = diskDirs(ord);
        xw = dir(fullfile(diskDirs(1).folder, diskDirs(1).name, '*.x.wav'));
        tok = regexp({xw.name}, '_(\d{6}_\d{6})_df\d+\.x\.wav$', 'tokens', 'once');
        tok = tok(~cellfun(@isempty, tok));
        if isempty(tok)
            dataStart = NaT;
        else
            dataStart = min(datetime(cellfun(@(c) c{1}, tok, 'UniformOutput', false), ...
                'InputFormat', 'yyMMdd_HHmmss'));
        end
        if ~isnat(dataStart) && dataStart < minDataStart
            older{end+1} = depID; %#ok<SAGROW>
            continue
        end
        nNew = nNew + 1;
        startStr = char(string(dataStart, 'yyyy-MM-dd'));

        % preamp from HARP summary (or manual override)
        if isKey(preampOverride, depID)
            preamp = preampOverride(depID);
        else
            iS = find(S.key == lower(strrep(depID, '-', '')), 1);
            if isempty(iS) || ismissing(S.PreAmp(iS))
                runLog(end+1,:) = {code, depID, 'FAILED', ...
                    'Deployment not in HARP data summary (no preamp) - add it or set preampOverride', ...
                    NaN, '', startStr, ''}; %#ok<SAGROW>
                continue
            end
            preamp = double(S.PreAmp(iS));
        end

        % TF: rev B, else rev A (same rule as earlier runs); note other revisions
        isPre = cellfun(@(t) ~isempty(t) && str2double(t{1}) == preamp, tfTok);
        revs  = cellfun(@(t) upper(t{2}), tfTok(isPre), 'UniformOutput', false);
        cand  = tfList(isPre);
        iTF = find(strcmp(revs, 'B'), 1);
        if isempty(iTF), iTF = find(strcmp(revs, 'A'), 1); end
        if isempty(iTF)
            runLog(end+1,:) = {code, depID, 'FAILED', sprintf('No rev A/B TF for preamp %d in %s', preamp, TFsFolder), ...
                preamp, '', startStr, ''}; %#ok<SAGROW>
            continue
        end
        tfPath = fullfile(cand(iTF).folder, cand(iTF).name);
        note = '';
        otherRevs = setdiff(revs, {'A','B'});
        if ~isempty(otherRevs)
            note = sprintf('Note: preamp %d also has rev %s TF (not used). ', preamp, strjoin(otherRevs, ','));
        end

        % LTSAs from all disks
        ltsa = dir(fullfile(depFolder, ['*_df' dfWhat], ['*_df' dfWhat '.ltsa']));
        if isempty(ltsa)
            runLog(end+1,:) = {code, depID, 'FAILED', ['No *_df' dfWhat '.ltsa files'], preamp, cand(iTF).name, startStr, ''}; %#ok<SAGROW>
            continue
        end
        ltsaFiles = sort(fullfile({ltsa.folder}, {ltsa.name}))';
        if numel(ltsa) ~= numel(diskDirs)
            note = [note sprintf('%d LTSAs for %d disk folders. ', numel(ltsa), numel(diskDirs))]; %#ok<AGROW>
        end

        for tres = timeResList
            tString = {'monthly','daily','Hourly','minutely'};
            outFile = fullfile(outRoot, siteFolder, sprintf('%s_df%s_%sAves.mat', depID, dfWhat, tString{tres+1}));
            if isfile(outFile) && ~overwrite
                runLog(end+1,:) = {code, depID, 'SKIPPED', [note 'Output already exists'], preamp, cand(iTF).name, startStr, outFile}; %#ok<SAGROW>
                continue
            end
            if dryRun
                runLog(end+1,:) = {code, depID, 'PLANNED', sprintf('%s%d LTSAs', note, numel(ltsaFiles)), ...
                    preamp, cand(iTF).name, startStr, outFile}; %#ok<SAGROW>
                continue
            end
            fprintf('\n=== %s (%s): %d LTSAs, TF %s ===\n', depID, tString{tres+1}, numel(ltsaFiles), cand(iTF).name);
            try
                info = GOM_LTSAspectra(ltsaFiles, outFile, NumAves, tres, tfPath, depID);
                detail = sprintf('%s%d bins, %s to %s, %d empty bins, %.0f min', note, info.nBins, ...
                    string(info.tStart,'yyyy-MM-dd'), string(info.tEnd,'yyyy-MM-dd'), info.nEmptyBins, info.elapsedSec/60);
                runLog(end+1,:) = {code, depID, 'DONE', detail, preamp, cand(iTF).name, startStr, outFile}; %#ok<SAGROW>
                fprintf('    done: %s\n', detail);
            catch ME
                runLog(end+1,:) = {code, depID, 'FAILED', [note ME.message], preamp, cand(iTF).name, startStr, ''}; %#ok<SAGROW>
                fprintf(2, '    FAILED: %s\n', ME.message);
            end
        end
    end
    if nNew == 0
        runLog(end+1,:) = {code, '', 'SKIPPED', sprintf('No deployment starting after %s (older: %s)', ...
            string(minDataStart,'yyyy-MM-dd'), strjoin(older, ', ')), NaN, '', '', ''}; %#ok<SAGROW>
    end
end

%% ------------------- Summary ---------------------------------------------
L = cell2table(runLog, 'VariableNames', {'SiteCode','Deployment','Status','Detail','PreAmp','TF','DataStart','Output'});
disp(L(:, 1:7))
if ~dryRun
    logFile = fullfile(outRoot, sprintf('GOM_HourlyAves_log_%s.csv', string(datetime('now'), 'yyyyMMdd_HHmm')));
    writetable(L, logFile);
    fprintf('Log saved to %s\n', logFile);
end
