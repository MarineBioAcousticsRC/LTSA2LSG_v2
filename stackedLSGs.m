% plot_all_sites_from_hourly_chunked.m
% Stacks daily-averaged LSGs from *HourlyAves.mat in 3 figures:
% sites 1–9, 10–18, and 19–end.

close all; clc;

%% ---- USER INPUTS ----
region   = 'GOM';
rootDir  = 'L:\Shared drives\MBARC_GOM\GOM x SIO x NOAA\GOM Ambient Noise\HourlyAves\';
ftype    = '*HourlyAves.mat';

clean    = 0;        % 1 = apply FIFO/tones cleaning blocks (optional)
cxMIN    = 40;       % color axis
cxMAX    = 110;

% date window
plotStart         = datenum(2020,6,20);  % default start (groups 1 & 3)
plotStart_group2  = datenum(2024,7,20);  % <-- group 2 custom start
plotEnd           = datenum(2025,7,1);

% frequency range to show
freq  = (0:1000).';   % Hz bins in mpwrtf
fmin  = 10;  fmax = 1000;

%% ---- discover site folders ----
d = dir(rootDir);
isSub = [d.isdir] & ~ismember({d.name},{'.','..'});
siteDirs = d(isSub);

sites = {}; sitePaths = {};
for k = 1:numel(siteDirs)
    sf = siteDirs(k).name;
    p  = fullfile(rootDir,sf,filesep);
    if ~isempty(dir(fullfile(p, ftype)))
        sites{end+1}    = sf; %#ok<AGROW>
        sitePaths{end+1}= p;  %#ok<AGROW>
    end
end
nSites = numel(sites);
if nSites==0
    error('No "%s" files found under %s', ftype, rootDir);
end

% frequency mask (constant across figures)
fmask = freq>=fmin & freq<=fmax;
F     = freq(fmask);

% Desired order (by site name) for the FIRST group
desiredOrder = {'AC','GC','MC','DC','DT','LC','CE','MR','GA','SL'};

% Map desired names to indices in 'sites'
g1Idx = [];
for k = 1:numel(desiredOrder)
    j = find(strcmp(sites, desiredOrder{k}));
    if ~isempty(j)
        g1Idx(end+1) = j; %#ok<AGROW>
    end
end

% Ensure max 10 in first group even if more somehow match
if numel(g1Idx) > 10
    g1Idx = g1Idx(1:10);
end

% Remaining sites keep their discovery order
remaining = setdiff(1:nSites, g1Idx, 'stable');

groups = {};

% Group 1: custom ordered list (AC, GC, MC, DC, DT, LC, CE, MR, GA, SL)
if ~isempty(g1Idx)
    groups{end+1} = g1Idx;
end

% Group 2: up to 9 of the remaining sites
if ~isempty(remaining)
    g2 = remaining(1:min(9, numel(remaining)));
    if ~isempty(g2)
        groups{end+1} = g2;
    end

    % Group 3: everything after those 9
    if numel(remaining) > numel(g2)
        g3 = remaining(numel(g2)+1:end);
        if ~isempty(g3)
            groups{end+1} = g3;
        end
    end
end

%% ---- make one figure per group ----
for g = 1:numel(groups)
    idxList = groups{g};

    % group-specific plotStart
    thisPlotStart = plotStart;
    if g == 2, thisPlotStart = plotStart_group2; end

    % per-group time grid
    allDays = (floor(thisPlotStart):floor(plotEnd)).';

    makeStackedFigure(idxList, sites, sitePaths, ...
        allDays, F, fmask, thisPlotStart, plotEnd, cxMIN, cxMAX, ...
        ftype, clean);

    % optional save
    base = sprintf('%s_LSG_stack_%02d', region, g);
    exportgraphics(gcf, fullfile(rootDir,[base '.png']), 'Resolution', 300);
    savefig(gcf, fullfile(rootDir,[base '.fig']));
end

%% ===== helper (local function at end of script) =====
function makeStackedFigure(idxList, sites, sitePaths, ...
    allDays, F, fmask, plotStart, plotEnd, cxMIN, cxMAX, ...
    ftype, clean)

    nSites = numel(idxList);
    tl = tiledlayout(nSites,1, ...
    'TileSpacing','none', ...
    'Padding','none');
    set(gcf,'Color','w','Position',[160 60 1120 920]);

    nDays   = numel(allDays);
    wantTicks = [10 100 1000];
    wantTicks = wantTicks(wantTicks>=min(F) & wantTicks<=max(F));

    for ii = 1:nSites
        i     = idxList(ii);
        site  = sites{i};
        fpath = sitePaths{i};

        % ---- load all HourlyAves for this site ----
        L = dir(fullfile(fpath, ftype));
        SPL = []; datnm = []; poff = datenum([2000 0 0 0 0 0]);

        for j = 1:numel(L)
            S = load(fullfile(L(j).folder, L(j).name));

            % OPTIONAL: minimal generic FIFO cleaning (keep your detailed blocks if needed)
            if clean==1
                if numel(S.freq) > 1001
                    if mean(S.mpwrtf(81,:))-mean(S.mpwrtf(78,:))>1.4 || ...
                       mean(S.mpwrtf(161,:))-mean(S.mpwrtf(158,:))>1.4
                        integers = 80*(1:12);
                        for ii2=1:numel(integers)
                            S.mpwrtf(integers(ii2)-2:integers(ii2)+2,:) = NaN;
                        end
                        S.mpwrtf = S.mpwrtf(1:1001,:);
                        S.mpwrtf = fillmissing(S.mpwrtf,'spline',1);
                    end
                elseif numel(S.freq)==1001
                    if mean(S.mpwrtf(101,:))-mean(S.mpwrtf(99,:))>1.4 || ...
                       mean(S.mpwrtf(151,:))-mean(S.mpwrtf(148,:))>1.4
                        integers = 50*(1:20);
                        for ii2=1:numel(integers)
                            S.mpwrtf(integers(ii2)-2:integers(ii2)+2,:) = NaN;
                        end
                        S.mpwrtf = S.mpwrtf(1:1001,:);
                        S.mpwrtf = fillmissing(S.mpwrtf,'spline',1);
                    end
                end
            end

            SPL   = [SPL,   S.mpwrtf(1:1001,:)]; %#ok<AGROW>
            datnm = [datnm; S.ptime + poff];     %#ok<AGROW>
        end

        % ---- hourly -> daily median ----
        ax = nexttile(tl);
        set(ax,'Color',[0.85 0.85 0.85]); hold(ax,'on');

        if ~isempty(SPL)
            [~,ord] = sort(datnm);
            datnm = datnm(ord);  SPL = SPL(:,ord);
            datnm = datenum(dateshift(datetime(datestr(datnm)),'start','hour'));
            SPL(SPL==0) = NaN;

            TT  = timetable(datetime(datestr(datnm)), SPL');
            TTD = retime(TT,'daily','median');       % days x freq
            dailySPL2 = TTD.Var1.';                  % freq x days
            dailydays = floor(datenum(TTD.Time));

            Z = dailySPL2(fmask,:);
            Zfull = nan(numel(F), nDays);
            [tf,loc] = ismember(dailydays, allDays);
            Zfull(:, loc(tf)) = Z(:, tf);

            if nnz(~isnan(Zfull)) > 0
                % Use surf + view(2), like single-site LSG
                h = surf(ax, allDays, F, Zfull, 'LineStyle','none');
                view(ax, [0 90]);
                set(h, 'AlphaData', ~isnan(Zfull), ...
                       'AlphaDataMapping','none');
            end
        else
            Zfull = [];
        end

        % ---- axes styling ----
        set(ax,'YDir','normal','YScale','log','TickDir','out','Box','off','Layer','top');
        xlim(ax,[plotStart plotEnd]); ylim(ax,[min(F) max(F)]);
        colormap(ax, jet); caxis(ax,[cxMIN cxMAX]);

        % Only 10, 100, 1000 ticks (bigger font)
        set(ax,'YTick',wantTicks,'YTickLabel',string(wantTicks),'FontSize',12);

        % site label INSIDE top-left
        text(plotStart, max(F), site, 'FontWeight','bold', ...
             'VerticalAlignment','top','HorizontalAlignment','left', ...
             'Margin',1,'Parent',ax);

        % only bottom axis shows x labels
        if ii < nSites
            set(ax,'XTickLabel',[]);
        else
            datetick(ax,'x','yyyy','keeplimits');
        end

        % no per-axis ylabel
        ylabel(ax,[]);
    end

    % shared y-label and colorbar (no title)
    ylabel(tl,'Frequency (Hz)');
    cb = colorbar; cb.Layout.Tile = 'east';
    cb.Label.String = 'Amplitude (dB re 1\muPa^2/Hz)';
    set(gcf,'Position',[710    73   822   920])
end
