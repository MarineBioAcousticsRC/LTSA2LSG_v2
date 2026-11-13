% GOM_octaveBandLevels.m
% Median hourly-average octave band levels (31.5, 63, 125, 500 Hz; dB re 1 uPa^2) per deployment
% and per site for the MPL TM 678 period (Aug 2020 - Jul 2025), from the HourlyAves files with
% FIFO interpolated out as in spectra_dataCleaning_v3. Used by GOM_makeSlides.ps1.
% Update the site list, report period and output folder each year. Tested in MATLAB R2023a.
R = 'L:\Shared drives\MBARC_GOM\GOM x SIO x NOAA\GOM Ambient Noise\HourlyAves';
sites = {'GC','MC','DT','LC','AC','DC','CE','MR','TP','PCC','Y6B','Y6C','Y6D'};
fc = [31.5 63 125 500];
edges = [fc' / sqrt(2), fc' * sqrt(2)];
poff = datenum([2000 0 0 0 0 0]);
t0rep = datenum(2020,8,1); t1rep = datenum(2025,8,1);   % report period (Aug 2020 - Jul 2025)
rows = {}; per = {};
for s = sites
    L = dir(fullfile(R, s{1}, '*_df100_HourlyAves.mat'));
    allT = []; allB = [];
    for k = 1:numel(L)
        h = load(fullfile(L(k).folder, L(k).name), 'ptime', 'mpwrtf', 'freq');
        P = h.mpwrtf(1:1001, :);
        % generic FIFO removal (same rule as spectra_dataCleaning_v3, 200 kHz data)
        if mean(P(101,:)) - mean(P(99,:)) > 1.4 || mean(P(151,:)) - mean(P(148,:)) > 1.4
            for c = 50*(1:20), P(max(c-2,1):min(c+2,1001), :) = NaN; end
            P = fillmissing(P, 'spline', 1);
        end
        t = h.ptime(:) + poff;
        ok = t > datenum(2004,1,1);
        B = zeros(sum(ok), 4);
        for b = 1:4
            r = (ceil(edges(b,1)):floor(edges(b,2))) + 1;
            B(:, b) = 10*log10(sum(10.^(P(r, ok)/10), 1))';
        end
        t = t(ok);
        id = erase(L(k).name, '_df100_HourlyAves.mat');
        med = median(B, 1, 'omitnan');
        rows(end+1, :) = {s{1}, id, datestr(min(t),'yyyy-mm-dd'), datestr(max(t),'yyyy-mm-dd'), ...
            min(t) >= datenum(2025,5,1), numel(t), med(1), med(2), med(3), med(4)}; %#ok<SAGROW>
        if med(1) > 60, allT = [allT; t]; allB = [allB; B]; end  % skip broken deployments (e.g. GC_15) %#ok<AGROW>
    end
    inRep = allT >= t0rep & allT < t1rep;
    m = median(allB(inRep, :), 1, 'omitnan');
    per(end+1, :) = {s{1}, sum(inRep), m(1), m(2), m(3), m(4)}; %#ok<SAGROW>
end
T = cell2table(rows, 'VariableNames', {'Site','Deployment','Start','End','IsNew','nHours','OB31_5','OB63','OB125','OB500'});
P = cell2table(per,  'VariableNames', {'Site','nHours2020_2025','OB31_5','OB63','OB125','OB500'});
writetable(T, 'H:\GOM_LSG_2026\GOM_deployment_octave_bands.csv');
writetable(P, 'H:\GOM_LSG_2026\GOM_site_octave_bands_2020-2025.csv');
disp(P); disp(T(T.IsNew == 1, :))
