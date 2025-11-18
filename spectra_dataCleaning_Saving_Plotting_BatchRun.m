close all;clear all;clc;
clearvars
% Tested in Matlab 2023a
% This code is to batch run dataCleaning and plot saving for a directory
% with folders for multiple sites (ex: GOM)
%% user defined parameters
region = 'GOM';
rootDir = 'F:\GOM_LSG_2025\';
ftype = '*HourlyAves.mat';
clean = 0; %Remove FIFO and tonnes (1)

%define color axis for LSG
cxMIN = 40;
cxMAX = 110;

% Specify which plots you want to generate
Seasonal  = false;   % seasonal spectra
Bands_hr  = false;   % hourly band time series
Bands_day = false;   % daily band time series
LSG       = true;   % long-term spectrogram (LSG)
%% Discover subfolders and run your script in a loop
d = dir(rootDir);
isSub = [d.isdir] & ~ismember({d.name},{'.','..'});
siteDirs = d(isSub);

fprintf('Found %d subfolders under %s\n', numel(siteDirs), rootDir);

for k = 1:numel(siteDirs)
    siteName = siteDirs(k).name;                 % fixed label for logs
    site     = siteName;                         % variable passed into worker
    fpath    = fullfile(rootDir, site, filesep);

    if isempty(dir(fullfile(fpath, ftype)))
        fprintf('(%2d/%2d) %-6s : no "%s" files — skipping.\n', ...
            k, numel(siteDirs), siteName, ftype);
        continue;
    end

    fprintf('(%2d/%2d) Processing %s ...\n', k, numel(siteDirs), siteName);
    try
        run('spectra_dataCleaning_Saving_Plotting_BatchRun_Function.m');
        fprintf('      ✓ Done: %s\n', siteName);
    catch ME
        fprintf('      ✗ Failed: %s\n      -> %s\n', siteName, ME.message);
    end
end

fprintf('All sites processed.\n');