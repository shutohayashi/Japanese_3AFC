function sos = bp_sos(band, fs, order)
%BP_SOS Design a Butterworth band-pass in numerically stable second-order sections.
if nargin < 3 || isempty(order), order = 6; end
[zz,pp,kk] = butter(order, band/(fs/2), 'bandpass');
sos = zp2sos(zz, pp, kk);
end
