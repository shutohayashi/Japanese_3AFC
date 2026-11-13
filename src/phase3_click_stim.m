function [x, info] = phase3_click_stim(varargin)
%PHASE3_CLICK_STIM Build an alternating-polarity train at a specified peak amplitude.
% The click pulses themselves are the stimulus and have no onset ramp.

K = phase3_protocol_const();

p = inputParser;
p.addParameter('level', []);                      % ピーク振幅 0..1 (必須)
p.addParameter('n_epochs', K.click_burst_epochs);
p.addParameter('fs', K.fs_hz);
p.addParameter('iti_ms', K.click_iti_ms);
p.addParameter('width_us', K.click_width_us);
p.parse(varargin{:});
o = p.Results;

% level に既定値を置かない理由は phase3_noise_stim の level_rms と同じ: 間違えると無音か
% 過大レベルになり、どちらも「測れていない」ことに測定中は気づけない。
if isempty(o.level)
    error('phase3_click_stim:level', ...
        "'level' (ピーク振幅 0..1) は必須です。dB FS からは phase3_level_map('db2amp',.) で。");
end
if ~isscalar(o.level) || ~isnumeric(o.level) || ~isreal(o.level) || o.level < 0 || o.level > 1
    error('phase3_click_stim:level', ...
        "'level' は 0..1 の実数スカラです (指定: %s)。", mat2str(o.level));
end
if ~isscalar(o.n_epochs) || o.n_epochs < 1 || o.n_epochs ~= fix(o.n_epochs)
    error('phase3_click_stim:nepochs', ...
        "'n_epochs' は 1 以上の整数スカラです (指定: %s)。", mat2str(o.n_epochs));
end

Q = phase3_click_width(o.fs, o.width_us, 'phase3_click_stim:clickwidth');

% Alternate polarity and start with condensation for reproducible trials.
argc = {'fs',o.fs,'width_us',o.width_us,'iti_ms',o.iti_ms,'level',o.level};
e = {make_click(argc{:}, 'polarity','condensation'), ...
     make_click(argc{:}, 'polarity','rarefaction')};

epochN = numel(e{1});
x      = zeros(epochN*o.n_epochs, 1);
for i = 1:o.n_epochs
    x((i-1)*epochN + (1:epochN)) = e{mod(i-1,2)+1};
end

info = struct('n_epochs', o.n_epochs, 'epoch_samples', epochN, ...
              'n_samples', numel(x), 'duration_ms', numel(x)/o.fs*1e3, ...
              'fs', o.fs, 'iti_ms', o.iti_ms, 'width_us', o.width_us, ...
              'width_samples',Q.samples,'width_us_actual',Q.actual_us, ...
              'rate_hz', 1e3/o.iti_ms, 'level_peak', o.level, ...
              'first_polarity', 'condensation');
end
