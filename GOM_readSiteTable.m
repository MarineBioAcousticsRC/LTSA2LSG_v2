function T = GOM_readSiteTable(docxPath)
% GOM_readSiteTable  Read the GOM cruise activity table(s) from a .docx.
%
%   T = GOM_readSiteTable('GOM_2026_sites.docx')
%
%   Returns a table with columns SiteName, SiteCode, Activity, Duration,
%   Configuration, Recover (true if Activity contains "recover") and
%   Lost (true if the duration cell contains "*", which the cruise table
%   uses to mark lost deployments).
%
%   Works while the document is open in Word (reads a temporary copy).

tmp = tempname;
mkdir(tmp);
cleanup = onCleanup(@() rmdir(tmp, 's'));
copyfile(docxPath, fullfile(tmp, 'sites.zip'));
unzip(fullfile(tmp, 'sites.zip'), tmp);
xml = fileread(fullfile(tmp, 'word', 'document.xml'));

rows = {};
tbls = regexp(xml, '<w:tbl>.*?</w:tbl>', 'match');
for t = 1:numel(tbls)
    trs = regexp(tbls{t}, '<w:tr[ >].*?</w:tr>', 'match');
    hdr = [];
    for r = 1:numel(trs)
        tcs = regexp(trs{r}, '<w:tc>.*?</w:tc>', 'match');
        cells = cellfun(@cellText, tcs, 'UniformOutput', false);
        if isempty(hdr)
            hdr = cells;
            iName = find(strcmpi(hdr, 'Site Name'), 1);
            iCode = find(strcmpi(hdr, 'Site Code'), 1);
            iAct  = find(strcmpi(hdr, 'Activity'), 1);
            iDur  = find(startsWith(lower(hdr), 'duration'), 1);
            iCfg  = find(strcmpi(hdr, 'Configuration'), 1);
            if isempty(iCode) || isempty(iAct)
                error('Table %d in %s has no "Site Code"/"Activity" header', t, docxPath);
            end
            continue
        end
        if numel(cells) < max([iCode iAct])
            continue
        end
        rows(end+1, :) = {getc(cells,iName), getc(cells,iCode), getc(cells,iAct), ...
                          getc(cells,iDur), getc(cells,iCfg)}; %#ok<AGROW>
    end
end

T = cell2table(rows, 'VariableNames', {'SiteName','SiteCode','Activity','Duration','Configuration'});
T = T(~cellfun(@isempty, T.SiteCode), :);
T.Recover = contains(lower(T.Activity), 'recover');
T.Lost    = contains(T.Duration, '*');
end

function s = cellText(tc)
parts = regexp(tc, '<w:t(?: [^>]*)?>([^<]*)</w:t>', 'tokens');
s = strtrim(strjoin(cellfun(@(c) c{1}, parts, 'UniformOutput', false), ''));
s = regexprep(s, '\s+', ' ');
s = strrep(strrep(strrep(strrep(s, '&lt;', '<'), '&gt;', '>'), '&quot;', '"'), '&amp;', '&');
end

function v = getc(cells, i)
if isempty(i) || i > numel(cells), v = ''; else, v = cells{i}; end
end
