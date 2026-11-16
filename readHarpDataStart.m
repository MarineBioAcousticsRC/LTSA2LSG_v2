function M = readHarpDataStart(xlsFile)
% M = readHarpDataStart(xlsFile)
% Data_ID -> datenum of Data_Start_Date + Data_Start_Time from the HARP data summary
% (e.g. HARPDataSummary_20261016.xlsx). Used with deckTestMask.m to drop the deck test.
% Tested in MATLAB R2023a.
M = containers.Map('KeyType', 'char', 'ValueType', 'double');
H = readtable(xlsFile, 'VariableNamingRule', 'preserve');
for i = 1:height(H)
    id = H.Data_ID(i); if iscell(id), id = id{1}; end
    id = strtrim(char(string(id)));
    d = H.Data_Start_Date(i); tm = H.Data_Start_Time(i);
    if iscell(d), d = d{1}; end
    if iscell(tm), tm = str2double(tm{1}); end
    if isempty(id) || ismissing(string(d)), continue, end
    if isduration(tm), tm = days(tm); elseif isdatetime(tm), tm = days(timeofday(tm)); end
    if isnan(tm), tm = 0; end
    M(id) = datenum(dateshift(datetime(d), 'start', 'day')) + tm;
end
end
