function [keep, method] = deckTestMask(t, depID, dataStart)
% [keep, method] = deckTestMask(t, depID, dataStart)
% Marks the deck test (hours recorded before the deployment's data start) as false.
%   t         : datenum of each hour (HourlyAves ptime + datenum([2000 0 0 0 0 0]))
%   depID     : deployment ID, e.g. 'GOM_DC_18' (4-channel files like GOM_MC_15_01_C4 also match)
%   dataStart : map from readHarpDataStart.m
% Deployments not in the HARP summary: a <= 3 h block at the start that is followed by a
% > 3 h gap (within the first 10 days) is dropped.
% Tested in MATLAB R2023a.
key = '';
base = regexprep(depID, '_C\d+$', '');
for c = {depID, base, regexprep(base, '_\d{2}$', '')}
    if isKey(dataStart, c{1}), key = c{1}; break, end
end
if ~isempty(key)
    keep = t >= dataStart(key) - 59/1440;              % ptime = first time in the hour
    method = sprintf('HARP summary Data_Start (%s, %s)', key, datestr(dataStart(key), 'yyyy-mm-dd HH:MM'));
    return
end
ts = sort(t(t > datenum(2004,1,1)));
keep = true(size(t));
g = find(diff(ts)*24 > 3 & ts(1:end-1) < ts(1) + 10, 1);
if ~isempty(g) && g <= 3
    keep = t > ts(g);
    method = 'not in HARP summary: leading block before first gap > 3 h';
else
    method = 'not in HARP summary: no deck test found';
end
end
