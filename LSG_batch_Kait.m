
clear all; close all;

% autoRun_LTSA_daily_spectra
thisDisk = 'S:\CHNMS\NO\df100'; %can't be a subfolder, needs to be the main folder with all deployments
NumAves = 5;     % number of time slices (spectral averages) to read per raw file
timeResol = 2;   % time bin resolution 0 = month, 1 = days, 2 = hours
harpDataSummaryCSV = 'L:\Shared drives\MBARC_DAM\Current Reports\CADEMO\Ambient Soundscape\HARPDataSummary_20240618.csv';
outDisk = 'L:\Shared drives\MBARC_DAM\Current Reports\CADEMO\Ambient Soundscape\df100\hourly';
TFsFolder = 'L:\Shared drives\MBARC_TF';
mkdir(outDisk)
dirList = dir(thisDisk);
nDirs = length(dirList);

for iDir = 3:nDirs
    thisDir = fullfile(dirList(iDir).folder,dirList(iDir).name);
    % check if contains .ltsa files
   LTSAlist = dir(fullfile(thisDir));
    if ~isempty(LTSAlist)
        [~,outName,~] = fileparts(LTSAlist(1).folder);
        outDir = outDisk;
        if ~contains(dirList(iDir).name,'.')...
                &&~contains(dirList(iDir).name,'$')
            if ~isdir(outDir)
                mkdir(outDir)
            end
            LTSAdailySpectra_auto(LTSAlist,outDir,NumAves,timeResol,harpDataSummaryCSV,TFsFolder)

        end
    end
end