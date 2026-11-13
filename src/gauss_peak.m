%% GAUSS_PEAK  convert between a Gaussian level and an expected exceeding-sample count
% For zero-mean Gaussian samples with the same marginal RMS, the two-sided tail probability
% at s times RMS is erfc(s/sqrt(2)). Linearity of expectation gives N times that probability
% for N actual samples, even when they are correlated. This counts exceeding samples, not
% independent clipping events; it does not predict the maximum or the chance a block clips.
% The stationary model does not include ramps or filter transients.
%
% Used by the crest-headroom derivation, the noise clip warning, and their selftest so both
% directions use the same relationship. The protocol keeps its readable 16 dB literal and
% checks it against this conversion in phase3_afc_selftest.
%
%   s = gauss_peak('sigma', N, k)  % level in RMS units with k expected exceeding samples
%   k = gauss_peak('cross', N, s)  % expected samples exceeding either +s or -s RMS
%
% Inputs are finite real numeric scalars: N is a positive integer, 0 < k <= N, and s >= 0.
% Fractional expectations are valid. k = 0 and infinite levels are outside this interface.
% Operation names are case-insensitive.
%
% Usage:
%   s = gauss_peak('sigma', 1800*96000, 1);  % 5.823 RMS units -> 15.30 dB
%   k = gauss_peak('cross', 200000, 2);      % about 9100 exceeding samples
% ============================================================
function out = gauss_peak(op, n_samples, x)

if nargin ~= 3
    error('gauss_peak:args', 'Use gauss_peak(op, n_samples, value).');
end
if ~((ischar(op) && isrow(op)) || (isstring(op) && isscalar(op))) || ...
        ~any(strcmpi(op, {'sigma','cross'}))
    error('gauss_peak:op', 'op must be sigma or cross.');
end
if ~isnumeric(n_samples) || ~isreal(n_samples) || ~isscalar(n_samples) || ...
        ~isfinite(n_samples) || n_samples <= 0 || fix(n_samples) ~= n_samples
    error('gauss_peak:samples', 'n_samples must be a finite positive integer scalar.');
end
if ~isnumeric(x) || ~isreal(x) || ~isscalar(x) || ~isfinite(x)
    error('gauss_peak:value', 'value must be a finite real numeric scalar.');
end
% Convert integer and single inputs before division; counts may have fractional expectations.
n_samples = double(n_samples);
x = double(x);
switch lower(char(op))
    case 'sigma'
        if x <= 0 || x > n_samples
            error('gauss_peak:value', 'Expected exceeding samples must satisfy 0 < k <= N.');
        end
        out = sqrt(2) * erfcinv(x / n_samples);
    case 'cross'
        if x < 0
            error('gauss_peak:value', 'The level in RMS units must be nonnegative.');
        end
        out = n_samples * erfc(x / sqrt(2));
end
end
