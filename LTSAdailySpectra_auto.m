function LTSAdailySpectra_auto(LTSAlist,outDir,NA,tres,harpDataSummaryCSV,TFsFolder)
% 141103 smw
% reworked from LTSAdailySpectra_midFreq.m which was from
% LTSAmonthlySpectra.m
% make mat file with daily spectra averages from LTSAs, including time (i.e. day)
% and number of tave bins used for average
%
% 160823 smw
% added filter for removing hydrophone strum
% first used for Palmyra Iceberg (ie Matsumoto) PAL 04, 05, 06
% use threshold/energy detector at 10 Hz
% also cleaned up some stuff...
%
% 170130 smw
% modified (removed low freq stuff) for non-decimated full bandwidth data
% goal to provide daily ave spectrograms to look for level changes in the
% sperm whale click band.
%

%clear variables
global PARAMS

% Load Harp data summary:
harpDataSummary = readtable(harpDataSummaryCSV);

% initial changable parameters:
rm_fifo = 0;%not used    % remove FIFO via interpolation on spectra. 0=no, 1=yes
fsflag = 1;%not used     % sample rate flag for FIFO removal 1=80kHz, 0=all other

% get LTSA file names and tf file name
if strcmp(LTSAlist(1).name,'.')
    LTSAlist(1:2) = [];
end
fn_files = char({(LTSAlist.name)}');
fn_pathname = vertcat(LTSAlist.folder);

% sort if multiple files selected
if size(fn_files,1)>1
    [fn_files,IX] = sortrows(fn_files);
    fn_pathname =fn_pathname(IX,:);
end

% from LTSA name, determine deployment and PreAmp number
deplMatch = [];
iFile = 1;
if iscell(fn_files)
    fnFileForTF = fn_files{1};
else
    fnFileForTF = fn_files(1,:);
end
while isempty(deplMatch) && iFile<=size(harpDataSummary,1)
    dBaseName = strrep(harpDataSummary.Data_ID{iFile},'-','');
    deplMatch = strfind(lower(fnFileForTF),lower(dBaseName));
    iFile = iFile+1;
end
if isempty(deplMatch)
    warning('Error, no matching deployment in HARP database)')
    return
    tfNum = [];
else
    deplMatchIdx = iFile-1;
    tfNum = harpDataSummary.PreAmp(deplMatchIdx);
end

% Search TFs folder for the appropriate preamp
tfList = dir(fullfile(TFsFolder,'\**\*B_HARP.tf'));
tfMatch = [];
iTF = 1;

while isempty(tfMatch) && iTF<=size(tfList,1)
    tfMatch = strfind(tfList(iTF).name(1:4),num2str(tfNum));
    iTF = iTF+1;
end

if isempty(tfMatch)
    warning('No matching B TF in TFs folder')
    warning('Trying rev A')
    tfList = dir(fullfile(TFsFolder,'\**\*A_HARP.tf'));
    tfMatch = [];
    iTF = 1;
    while isempty(tfMatch) && iTF<=size(tfList,1)
        tfMatch = strfind(tfList(iTF).name(1:4),num2str(tfNum));
        iTF = iTF+1;
    end
end   

if isempty(tfMatch)
    suggestedTFPath = [];
    return
else
    tfMatchIdx = iTF-1;
    tf_file = tfList(tfMatchIdx).name;
    tf_pathname = tfList(tfMatchIdx).folder;
end

tic
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
disp([ 'Transfer function: ' tf_file  ]);
tf = fullfile(tf_pathname, tf_file);
loadTF(tf); % open and read Transfer function file:

disp('Calculating Averages for:')
if iscell(fn_files) % then it's a cell full of filenames
    fn = cell(length(fn_files),1);
    for k = 1:length(fn_files)
        fn{k} = fullfile(fn_pathname, fn_files{k});
        disp(fn{k});
    end
elseif ischar(fn_files)
    fn = cell(size(fn_files,1),1);
    for k = 1:size(fn_files,1)
        fn{k} = fullfile(fn_pathname(k,:), fn_files(k,:));
        disp(fn{k});
    end
else % it's just one file, but put into cell
    fn = cell(1,1);
    fn{1} = fullfile(fn_pathname,fn_files);
    disp(fn);
end

nltsas = length(fn);    % number of LTSA files
mnum2secs = 24*60*60;

% read ltsa headers and sum the total number of raw files for
% pre-allocating vectors/matrices
nrftot = 0;
for k = 1:nltsas    % loop over files
    PARAMS.ltsa = [];   % clear
    PARAMS.ltsa.ftype = 1;
    [PARAMS.ltsa.inpath,infile,ext] = fileparts(fn{k});
    PARAMS.ltsa.infile = [infile,ext];
    read_ltsahead_nrf_only % better would be to just read nrftot instead of whole header
    nrf = PARAMS.ltsa.nrftot;
    nrftot = nrftot + nrf;
    if k == 1 % read and set some useful parameters that should be the same across all ltsas
        nf = PARAMS.ltsa.nf;
        nave = PARAMS.ltsa.nave(1);
        freq = PARAMS.ltsa.freq;
    end
end

% correct TF for more than one measurement at a specific frequency
[C,ia,ic] = unique(PARAMS.tf.freq);
if length(ia) ~= length(ic)
    disp(['Error: TF file ',tf,' is not monotonically increasing'])
end
tf_freq = PARAMS.tf.freq(ia);
tf_uppc = PARAMS.tf.uppc(ia);

% Transfer function correction vector
Ptf = interp1(tf_freq,tf_uppc,freq,'linear','extrap');
Ptf2 = Ptf'*ones(1,3);  % to add to

% fill up header matrix H
H = zeros(nrftot,3);    % 3 columns: filenumber, datenumber, byteloc in filenumber
cnt1 = 1;
cnt2 = 0;
for k = 1:nltsas    % loop over files
    PARAMS.ltsa = [];   % clear
    PARAMS.ltsa.ftype = 1;
    [PARAMS.ltsa.inpath,infile,ext] = fileparts(fn{k});
    PARAMS.ltsa.infile = [infile,ext];
    read_ltsahead  % better would be to just read nrftot instead of whole header
    nrf = PARAMS.ltsa.nrftot;
    fs0 = PARAMS.ltsa.fs;
    knave = PARAMS.ltsa.nave;
    cnt2 = cnt2 + nrf;
    H(cnt1:cnt2,1) = k.*ones(nrf,1);
    H(cnt1:cnt2,2) = PARAMS.ltsa.dnumStart;
    H(cnt1:cnt2,3) = PARAMS.ltsa.byteloc;
    cnt1 = cnt2 + 1;
end

dvec = datevec(H(:,2));

if tres == 0
    mnum = dvec(:,1).*12 + dvec(:,2);   % month number where 1 = Jan 2000
    tString = 'monthly';
elseif tres == 1
    mnum = floor(datenum(dvec));   % day number where 1 = Jan 2000
    tString = 'daily';
elseif tres == 2
    mnum = floor(datenum(dvec) * 24);   % hour
    tString = 'Hourly';
elseif tres == 3
    mnum = floor(datenum(dvec) * 24*60);   % hour
    tString = 'minutely';
else
    disp(['Error: unknown time resolution = ',num2str(tres)])
end

mnumMin = min(mnum);
mnumMax = max(mnum);

dur = unique(mnum);   % unique averaging time bins
nm = length(dur); % number of ave time bins

cnt1 = 1;
cnt2 = 0;
ptime = zeros(nm,1);      % start time of bin average
nmave = zeros(nm,2);    % number of averages possible and used(ie not filtered out) for each bin
mpwr = ones(nf,nm);     % mean power over time period
mpwrtf = ones(nf,nm);   % mean power with TF applied
mpwrTF = ones(nf,nm);   % mean power with FIFO interp & TF applied

for m = 1:nm    % loop over time average bins
    if tres == 0
        disp(['Month = ',num2str(dur(m))])
    elseif tres == 1
        disp(['Day = ',num2str(dur(m))])
    elseif tres == 2
        disp(['Hour = ',num2str(dur(m))])
    end
    
    I = [];
    I = find(mnum == dur(m));
    nrfM = length(I);
    pwrM = [];
    pwrM = zeros(nf,NA*nrfM);
    fnum = [];
    fnum = unique(H(I,1));
    nfiles = length(fnum);
    NBO = 0;    % number of averages (taves) read for mean spectra
    for f = 1:nfiles    % loop over files with same month (probably only 2 max)
        % open ltsa file
        fid = fopen(fn{fnum(f)},'r');
        % samples to skip over in ltsa file
        J = [];
        J = find(H(I,1) == fnum(f));
        nrfRead = length(J);
        skip = H(I(J(1)),3);    % get first byteloc of file for that month
        fseek(fid,skip,-1);    % skip over header + other data
        
        ptime(m) = H(I(J(1)),2);     % save 1st time of this time unit
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        
        % number of time slices to use for calcs
        % need to set 'xxxx*int8' value
        prcsn = [num2str(NA*nf),'*int8'];
        
        % allocate memory
        pwrF = [];
        NB = NA * nrfRead;
        pwrF = zeros(nf,NB);
        
        % number of time slices to skip on each read
        SA = nave - NA;
        skip = nf*(SA);
        % initial time slice to start at
        if fs0 == 2000 || fs0 == 200000 || fs0 == 10000
            IA = (nave + NA)*nf;  % this should work better for 320kHz vs commented 200kHz hardwired above
        elseif fs0 == 3200 || fs0 == 320000
            IA = (nave + NA-1)*nf;
        else
            disp('Error: unknown sample rate')
            disp(['fs0 = ',num2str(fs0)])
        end
        fseek(fid,IA,-0);
        
        % read data into File power
        [pwrF,count] = fread(fid,[nf,NB],prcsn,skip);
        if count ~= nf*NB
            disp('error = did not read enough data')
            %             NBO = NB;
            NB = floor(count/nf);
            %             disp(['NBO = ',num2str(NBO)])
            disp(['NB = ',num2str(NB)])
        end
        
        % fill up Month power
        if nfiles == 1
            pwrM = pwrF;
            NBO = NB;
        else
            if f == 1
                pwrM(1:nf,1:NB) = pwrF;
                NBO = NB;
            else
                pwrM(1:nf,NBO+1:NBO+NB) = pwrF;
                NBO = NBO+NB;
            end
        end
        disp(['Number of 5s time bins in this Average Time Bin = ',num2str(NBO)])
        fclose(fid);
    end  % end for f
    
    nmave(m,1) = NBO;
    cnt2 = cnt2 + size(pwrM,2);
    cnt1 = cnt2 + 1;
    
    % mean - these are smooth (floating point pwr values)
    mpwr(1:nf,m) = mean(pwrM,2);
    mpwrtf(1:nf,m) = mpwr(1:nf,m) + Ptf';   % add transfer function
    
    % running average to remove FIFO spikes
        ws = 5; % window size: number of samples
        mfpwr(1:nf,m) = filter(ones(1,ws)/ws,1,mpwr(1:nf,m));
        mf(1:nf,m) = mfpwr(1:nf,m) + Ptf'; % add transfer function
    
    %standard deviation
    spwr(1:nf,m) = std(pwrM,1,2);
    sfpwr(1:nf,m) = filter(ones(1,ws)/ws,1,spwr(1:nf,m));
    sf1(1:nf,m) = mfpwr(1:nf,m) + sfpwr(1:nf,m) + Ptf';
    sf2(1:nf,m) = mfpwr(1:nf,m) - sfpwr(1:nf,m) + Ptf';
    
    % Remove FIFO via inperpolation on spectra
    if rm_fifo
        if fs0 == 2000
            if fsflag
                fund = 20; % original fs=80kHz
            else
                fund = 50;
            end
        elseif fs0 == 3200
            fund = 80;
        else
            fprintf('Unknown sample rate %d encountered during rmFIFO\nExiting!\n', ...
                fs0);
        end
        nomult = 19;
        for mult = 1:nomult %going up to 1000 Hz
            ind2 = [];
            ind2 = find(abs(pwrN(mult*fund+1,:)-pwrN(mult*fund-1,:))>.8);
            if ~isempty(ind2)
                %diference to add to each increment for interpolation
                dff(ind2) = (pwrN(mult*fund+3,ind2)-pwrN(mult*fund-1,ind2))/4;
                pwrN(mult*fund,ind2) = pwrN(mult*fund-1,ind2)+dff(ind2);
                pwrN(mult*fund+1,ind2) = pwrN(mult*fund-1,ind2)+dff(ind2)*2;
                pwrN(mult*fund+2,ind2) = pwrN(mult*fund-1,ind2)+dff(ind2)*3;
            end
        end
        % mean - these are smooth
        pwrN = bsxfun(@plus, pwrN, Ptf'); % add in transfer function!
        mpwrTF(1:nf,m) = mean(pwrN,2);
    end
end

% save results
if 1
    outFile = fullfile(outDir,[dBaseName,'_df100_',tString,'Aves.mat']);
    save(outFile,'ptime','mpwrtf','freq','nmave', 'tf_file','dBaseName',...
    'Ptf')
end

t = toc;
disp(' ')
disp(['Time Elapsed: Spectra from LTSA ', num2str(t),' secs'])






