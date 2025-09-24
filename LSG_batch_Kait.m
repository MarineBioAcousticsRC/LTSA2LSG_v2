
clear all; close all;

% autoRun_LTSA_daily_spectra
thisDisk = 'W:\GofMX\MC\df100\GOM_MC_19_df100'; %can be a subfolder with multiple deployments or just a single deployment folder
NumAves = 5;     % number of time slices (spectral averages) to read per raw file
timeResol = 2;   % time bin resolution 0 = month, 1 = days, 2 = hours
harpDataSummaryCSV = 'C:\Users\nposd\Documents\GitHub\LTSA2LSG_v2\HARPDataSummary_20250917.csv';
outDisk = 'F:\GOM_LSG_2025\MC';
TFsFolder = 'L:\Shared drives\MBARC_TF';
mkdir(outDisk)
dirList = dir(thisDisk);
nDirs = length(dirList);

% --- Case 1: thisDisk itself has LTSA files ---
LTSAlist = dir(fullfile(thisDisk,'*.ltsa'));
if ~isempty(LTSAlist)
    [~, outName] = fileparts(thisDisk);
    outDir = outDisk;
    LTSAdailySpectra_auto(LTSAlist, outDir, NumAves, timeResol, harpDataSummaryCSV, TFsFolder);
else
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
end
%% PLOT LSG
% plotDailyLSG('L:\Shared drives\MBARC_DAM\Current Reports\CADEMO\Ambient Soundscape\df100',...
%     'CHNMS','CHNMS',1,1,'MBARC_TFs','L:\Shared drives\MBARC_TF')
% 
% plotDailyLSG_clean('L:\Shared drives\MBARC_DAM\Current Reports\CADEMO\Ambient Soundscape\df100',...
%     'CHNMS','CHNMS',1,1,'MBARC_TFs','L:\Shared drives\MBARC_TF')