% GOM_monthlyOctaveBands.m
% Monthly median octave band levels through each new deployment, to spot hydrophone
% sensitivity drop-off (all bands falling together, incl. 500 Hz weather band).
% Update the deployment list each year. Tested in MATLAB R2023a.
R = 'L:\Shared drives\MBARC_GOM\GOM x SIO x NOAA\GOM Ambient Noise\HourlyAves';
deps = {'GC','GOM_GC_18'; 'MC','GOM_MC_20'; 'MC','GOM_MC_19'; 'DT','GOM_DT_18_00'; 'DT','GOM_DT_17'; ...
        'LC','GOM_LC_06'; 'AC','GOM_AC_06'; 'DC','GOM_DC_18'; 'CE','GOM_CE_06'; 'MR','GOM_MR_06'; ...
        'TP','GOM_TP_01'; 'PCC','GOM_PCC_01'; 'Y6B','GOM_Y6B_01'; 'Y6C','GOM_Y6C_01'; 'Y6D','GOM_Y6D_01'};
fc = [31.5 63 125 500]; ed = [fc'/sqrt(2) fc'*sqrt(2)];
poff = datenum([2000 0 0 0 0 0]);
ds = readHarpDataStart('C:\Users\nposd\Documents\GitHub\LTSA2LSG_v2\HARPDataSummary_20261016.xlsx'); % deck test
out = {};
for i = 1:size(deps,1)
    h = load(fullfile(R, deps{i,1}, [deps{i,2} '_df100_HourlyAves.mat']), 'ptime', 'mpwrtf');
    P = h.mpwrtf(1:1001,:);
    if mean(P(101,:)) - mean(P(99,:)) > 1.4 || mean(P(151,:)) - mean(P(148,:)) > 1.4
        for c = 50*(1:20), P(max(c-2,1):min(c+2,1001),:) = NaN; end
        P = fillmissing(P, 'spline', 1);
    end
    t = h.ptime(:) + poff;
    ok = deckTestMask(t, deps{i,2}, ds);    % drop the deck test
    t = t(ok); P = P(:, ok);
    B = zeros(numel(t), 4);
    for b = 1:4, r = (ceil(ed(b,1)):floor(ed(b,2))) + 1; B(:,b) = 10*log10(sum(10.^(P(r,:)/10),1))'; end
    m = floor((t - t(1)) / 30.44);                  % deployment month 0,1,2,...
    fprintf('\n%s (start %s)   month: 31.5 / 63 / 125 / 500 Hz octave medians\n', deps{i,2}, datestr(t(1),'yyyy-mm-dd'));
    line500 = ''; line31 = '';
    for k = 0:max(m)
        q = median(B(m == k, :), 1);
        line31  = [line31  sprintf('%6.1f', q(1))]; %#ok<AGROW>
        line500 = [line500 sprintf('%6.1f', q(4))]; %#ok<AGROW>
        out(end+1,:) = {deps{i,1}, deps{i,2}, k, datestr(t(find(m==k,1)),'yyyy-mm'), q(1), q(2), q(3), q(4)}; %#ok<SAGROW>
    end
    fprintf('  31.5 Hz:%s\n   500 Hz:%s\n', line31, line500);
end
writetable(cell2table(out, 'VariableNames', {'Site','Deployment','Month','YearMonth','OB31_5','OB63','OB125','OB500'}), ...
    'H:\GOM_LSG_2026\GOM_new_deployments_monthly_octave_bands.csv');
