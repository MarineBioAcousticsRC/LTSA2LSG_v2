clear all;close all;clc;
% This script loads the output from spectra_dataCleaning_Saving for plotting
% The daily and hourly tables contain the following information:
% masterDFhour = [datnum YY MM DD HH SPL20' SPL44' SPL56' SPL800' ];
% masterDFday = [dailydatnum YYd MMd DDd SPL20daily' SPL44daily' SPL56daily' SPL800daily' dailySPL2'];
%% User defined parameters
region = 'CHNMS';
site = 'NO';
fpath = 'L:\Shared drives\MBARC_Reports\CADEMO\Ambient Soundscape\df100\';
freq = 0:1:1000;
%% Load workspace
load([fpath,region,'_',site,'_Daily_cleaned_v2.mat']);
load([fpath,region,'_',site,'_Hourly_cleaned_v2.mat']);
%% Regenerate variables from cleaned mat files
% getting month associated with datenum for hourly
[YY,MM,DD, HH]=datevec(masterDFhour(:,1));

% getting month associated with datenum for daily
[YYd,MMd,DDd]=datevec(masterDFday(:,1));

%get start and end date of data
startDate = masterDFday(1,1);
endDate = masterDFday(end,1);
%% Seasonal indexing and plots
wintIdx = find(MMd > 0 & MMd < 4);
springIdx = find(MMd > 3 & MMd < 7);
summIdx = find(MMd > 6 & MMd < 10);
fallIdx = find(MMd > 9 & MMd < 13);

SPLwinter = nanmedian(dailySPL2(:, wintIdx), 2);
SPLspring = nanmedian(dailySPL2(:, springIdx), 2);
SPLsummer = nanmedian(dailySPL2(:, summIdx), 2);
SPLfall = nanmedian(dailySPL2(:, fallIdx), 2);

%plotting seasonal median spectrum level
figure(2)
semilogx(freq, SPLwinter', 'Color', [0 0.4470 0.7410], 'LineWidth', 2)
grid on
hold on
semilogx(freq, SPLspring', 'Color', [0.8500 0.3250 0.0980], 'LineWidth', 2)
semilogx(freq, SPLsummer', 'Color', [0.9290 0.6940 0.1250], 'LineWidth', 2)
semilogx(freq, SPLfall', 'Color', [0.4940 0.1840 0.5560], 'LineWidth', 2)
legend('Winter (JFM)', 'Spring (AMJ)', 'Summer (JAS)', 'Fall (OND)')
xlim([10 800])
ax = gca;
ax.XTick = [10 20 50 100 250 500];
ylabel('dB re 1uPa^2')
xlabel('Hz')
title(['Seasonal Spectra ',region,' ',site])
%% SPL Bands of interest over time
% bands of interest
f63 = 56:71; % ship noise
f20 = 18:25; % fin whale 
f44 = 40:48; % blue whale
f800 = 708:891; % wind

% summed linearly, adjusted for bandwidth
SPL20 = 10*log10(sum(10.^(SPL(f20+1, :)/10)))- 10*log10(length(f20));
SPL56 = 10*log10(sum(10.^(SPL(f63+1, :)/10)))- 10*log10(length(f63));
SPL44 = 10*log10(sum(10.^(SPL(f44+1, :)/10)))- 10*log10(length(f44));
SPL800 = 10*log10(sum(10.^(SPL(f800+1, :)/10)))- 10*log10(length(f800));

SPL20daily = 10*log10(sum(10.^(dailySPL2(f20+1, :)/10)))- 10*log10(length(f20));
SPL56daily = 10*log10(sum(10.^(dailySPL2(f63+1, :)/10)))- 10*log10(length(f63));
SPL44daily = 10*log10(sum(10.^(dailySPL2(f44+1, :)/10)))- 10*log10(length(f44));
SPL800daily = 10*log10(sum(10.^(dailySPL2(f800+1, :)/10)))- 10*log10(length(f800));

%Hourly
figure(500)
subplot(4, 1, 1)
plot(datnum, SPL20, 'LineWidth', 2, 'Color', [0 0.4470 0.7410], 'Marker', 'o', 'LineStyle', 'none')
datetick
xlim([startDate endDate])
datetick('x','mm yyyy','keeplimits')
ylabel('dB re 1uPa^2')
xlim([startDate endDate])
title('Fin Whale (18 - 22 Hz)')
subplot(4, 1, 2)
plot(datnum, SPL44, 'LineWidth', 2, 'Color', [0 0.4470 0.7410], 'Marker', 'o', 'LineStyle', 'none')
datetick
xlim([startDate endDate])
datetick('x','mm yyyy','keeplimits')
ylabel('dB re 1uPa^2')
title('Blue Whale (42 - 46 Hz)')
subplot(4, 1, 3)
plot(datnum, SPL56, 'LineWidth', 2, 'Color', [0 0.4470 0.7410], 'Marker', 'o', 'LineStyle', 'none')
datetick
xlim([startDate endDate])
datetick('x','mm yyyy','keeplimits')
ylabel('dB re 1uPa^2')
title('Ship Noise (56 - 71 Hz)')
subplot(4, 1, 4)
plot(datnum, SPL800, 'LineWidth', 2, 'Color', [0 0.4470 0.7410], 'Marker', 'o', 'LineStyle', 'none')
datetick
xlim([startDate endDate])
datetick('x','mm yyyy','keeplimits')
ylabel('dB re 1uPa^2')
title('Wind Noise (708 - 891 Hz)')

%Daily
figure(501)
subplot(4, 1, 1)
plot(dailydatnum, SPL20daily, 'LineWidth', 2, 'Color', [0 0.4470 0.7410], 'Marker', 'o', 'LineStyle', 'none')
datetick
xlim([startDate endDate])
datetick('x','mm yyyy','keeplimits')
ylabel('dB re 1uPa^2')
title('Fin Whale (18 - 22 Hz)')
subplot(4, 1, 2)
plot(dailydatnum, SPL44daily, 'LineWidth', 2, 'Color', [0 0.4470 0.7410], 'Marker', 'o', 'LineStyle', 'none')
datetick
xlim([startDate endDate])
datetick('x','mm yyyy','keeplimits')
ylabel('dB re 1uPa^2')
title('Blue Whale (42 - 46 Hz)')
subplot(4, 1, 3)
plot(dailydatnum, SPL56daily, 'LineWidth', 2, 'Color', [0 0.4470 0.7410], 'Marker', 'o', 'LineStyle', 'none')
datetick
xlim([startDate endDate])
datetick('x','mm yyyy','keeplimits')
ylabel('dB re 1uPa^2')
title('Ship Noise (56 - 71 Hz)')
subplot(4, 1, 4)
plot(dailydatnum, SPL800daily, 'LineWidth', 2, 'Color', [0 0.4470 0.7410], 'Marker', 'o', 'LineStyle', 'none')
datetick
xlim([startDate endDate])
datetick('x','mm yyyy','keeplimits')
ylabel('dB re 1uPa^2')
title('Wind Noise (708 - 891 Hz)')
%% LSG
figure
surf(dailydatnum,freq,dailySPL2, 'Linestyle','none');
view([0 90])
set(gca,'yscale','log')
xlim([startDate endDate])
ylim([15 2000/2])
% make ticks out
set(gca,'TickDir','out')
lsg.T = dailydatnum;
% month ticks
d=datevec(dailydatnum);
[~,idxm]=unique(d(:,1:2),'rows');
ax = get(gca);
ax.XAxis.MinorTick = 'on';
ax.XAxis.MinorTickValues =dailydatnum(idxm);
% year ticks
[~,idxy]=unique(d(:,1),'rows');
set(gca,'xtick',lsg.T(idxy))
% display year
datetick('x','mmm yyyy','keeplimits')
% Color
colormap jet
% limits
caxis([40 80])
% colorbar
cb=colorbar;
ylabel(cb,'Spectrum Level (dB re 1\muPa^2/Hz)')
ylabel('Frequency (Hz)')
set(groot,'DefaultFigureGraphicsSmoothing','on')
title([region,' ', site, ' LSG'])
