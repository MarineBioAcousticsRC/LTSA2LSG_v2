function info = GOM_LTSAspectra(ltsaFiles, outFile, NA, tres, tfFile, dBaseName)
% GOM_LTSAspectra  Mean TF-corrected spectra per time bin from a set of LTSAs.
%
%   info = GOM_LTSAspectra(ltsaFiles, outFile, NA, tres, tfFile, dBaseName)
%
%   ltsaFiles : cell array of full paths to the .ltsa files of ONE deployment
%               (all disks), in time order
%   outFile   : full path of the .mat file to write
%   NA        : number of time slices (5 s spectral averages) read per raw file
%   tres      : 0 = monthly, 1 = daily, 2 = hourly, 3 = minutely
%   tfFile    : full path of the transfer function (.tf) file to apply
%   dBaseName : deployment ID saved into the output (e.g. 'GOM_GC_18')
%
%   Saves ptime, mpwrtf, freq, nmave, tf_file, dBaseName, Ptf -- the same
%   variables and the same averaging as LTSAdailySpectra_auto.m, so outputs
%   are directly comparable with earlier HourlyAves files. Differences from
%   LTSAdailySpectra_auto: the deployment and TF are chosen by the caller
%   (see GOM_runHourlyAves.m) instead of fuzzy-matched here, errors are
%   thrown instead of silently returning, and unused FIFO/std code is removed.
%
%   Returns info struct: nBins, tStart, tEnd, nf, fs, elapsedSec.

global PARAMS

tic
mnum2secs = 24*60*60; %#ok<NASGU>
poff = datenum([2000 0 0 0 0 0]);   % LTSA times are days since 2000

% ---- transfer function ----
loadTF(tfFile);
[~, ia] = unique(PARAMS.tf.freq);
if numel(ia) ~= numel(PARAMS.tf.freq)
    warning('TF file %s has repeated frequencies; using first of each.', tfFile)
end
tf_freq = PARAMS.tf.freq(ia);
tf_uppc = PARAMS.tf.uppc(ia);
[~, tfName, tfExt] = fileparts(tfFile);
tf_file = [tfName tfExt];

nltsas = numel(ltsaFiles);

% ---- pass 1: count raw files, get freq axis ----
nrftot = 0;
for k = 1:nltsas
    setLTSA(ltsaFiles{k});
    read_ltsahead_nrf_only
    nrftot = nrftot + PARAMS.ltsa.nrftot;
    if k == 1
        nf   = PARAMS.ltsa.nf;
        nave = PARAMS.ltsa.nave(1);
        freq = PARAMS.ltsa.freq;
    end
end

% TF correction vector on the LTSA frequency axis
Ptf = interp1(tf_freq, tf_uppc, freq, 'linear', 'extrap');

% ---- pass 2: header matrix H = [file number, datenum, byte location] ----
H = zeros(nrftot, 3);
cnt1 = 1; cnt2 = 0;
fsAll = zeros(nltsas,1);
for k = 1:nltsas
    setLTSA(ltsaFiles{k});
    read_ltsahead
    nrf = PARAMS.ltsa.nrftot;
    fsAll(k) = PARAMS.ltsa.fs;
    if PARAMS.ltsa.nf ~= nf
        error('LTSA %s has %d freq bins, expected %d', ltsaFiles{k}, PARAMS.ltsa.nf, nf);
    end
    cnt2 = cnt2 + nrf;
    H(cnt1:cnt2,1) = k;
    H(cnt1:cnt2,2) = PARAMS.ltsa.dnumStart;
    H(cnt1:cnt2,3) = PARAMS.ltsa.byteloc;
    cnt1 = cnt2 + 1;
end
fs0 = fsAll(1);
if any(fsAll ~= fs0)
    error('LTSAs in this deployment have different sample rates: %s', mat2str(unique(fsAll)'));
end

dvec = datevec(H(:,2));
switch tres
    case 0, mnum = dvec(:,1).*12 + dvec(:,2);          tString = 'monthly'; %#ok<NASGU>
    case 1, mnum = floor(datenum(dvec));               tString = 'daily';   %#ok<NASGU>
    case 2, mnum = floor(datenum(dvec) * 24);          tString = 'Hourly';  %#ok<NASGU>
    case 3, mnum = floor(datenum(dvec) * 24*60);       tString = 'minutely';%#ok<NASGU>
    otherwise, error('Unknown time resolution %d', tres);
end

dur = unique(mnum);
nm  = numel(dur);

% first time slice to read in each raw file (same rule as LTSAdailySpectra_auto)
if ismember(fs0, [2000 10000 20000 200000])
    IA = (nave + NA)*nf;
elseif ismember(fs0, [3200 320000])
    IA = (nave + NA - 1)*nf;
else
    error('Unknown LTSA sample rate fs0 = %g', fs0);
end
prcsn = [num2str(NA*nf), '*int8'];
skip  = nf*(nave - NA);

ptime  = zeros(nm,1);
nmave  = zeros(nm,2);
mpwrtf = ones(nf,nm);

fids = -ones(nltsas,1);
try
for m = 1:nm
    I = find(mnum == dur(m));
    fnum = unique(H(I,1));
    pwrM = zeros(nf, NA*numel(I));
    NBO = 0;
    for f = 1:numel(fnum)
        if fids(fnum(f)) < 0
            fids(fnum(f)) = fopen(ltsaFiles{fnum(f)}, 'r');
            if fids(fnum(f)) < 0
                error('Could not open %s', ltsaFiles{fnum(f)});
            end
        end
        fid = fids(fnum(f));
        J = find(H(I,1) == fnum(f));
        nrfRead = numel(J);
        if f == 1
            ptime(m) = H(I(J(1)),2);   % first time of this bin
        end
        fseek(fid, H(I(J(1)),3), -1);  % first byteloc for this bin
        fseek(fid, IA, 0);
        NB = NA * nrfRead;
        [pwrF, count] = fread(fid, [nf, NB], prcsn, skip);
        if count ~= nf*NB
            NB = floor(count/nf);
            pwrF = pwrF(:,1:NB);
            fprintf('   short read in bin %d: NB = %d\n', m, NB);
        end
        pwrM(:, NBO+1:NBO+NB) = pwrF;
        NBO = NBO + NB;
    end
    pwrM = pwrM(:,1:NBO);
    nmave(m,1) = NBO;
    mpwrtf(:,m) = mean(pwrM,2) + Ptf';   % mean (dB) + transfer function
    if mod(m, 500) == 0
        fprintf('   %d / %d bins (%s)\n', m, nm, datestr(ptime(m)+poff, 'yyyy-mm-dd HH:MM'));
    end
end
catch ME
    closeAll(fids);
    rethrow(ME);
end
closeAll(fids);

% NOTE: ptime is kept as days since 2000 (same as the original code), and
% "ptime(m)" was previously overwritten by the last file in a bin; it is now
% the first time in the bin, which only differs for bins spanning two LTSAs.

outDir = fileparts(outFile);
if ~isfolder(outDir), mkdir(outDir); end
save(outFile, 'ptime', 'mpwrtf', 'freq', 'nmave', 'tf_file', 'dBaseName', 'Ptf')

info.nBins = nm;
info.tStart = datetime(min(ptime)+poff, 'ConvertFrom', 'datenum');
info.tEnd   = datetime(max(ptime)+poff, 'ConvertFrom', 'datenum');
info.nf = nf;
info.fs = fs0;
info.nEmptyBins = sum(nmave(:,1) == 0);
info.elapsedSec = toc;
end

% ------------------------------------------------------------------------
function setLTSA(fullPath)
global PARAMS
PARAMS.ltsa = [];
PARAMS.ltsa.ftype = 1;
[PARAMS.ltsa.inpath, nm, ext] = fileparts(fullPath);
PARAMS.ltsa.infile = [nm ext];
end

function closeAll(fids)
for k = 1:numel(fids)
    if fids(k) > 0
        try fclose(fids(k)); catch, end
    end
end
end
