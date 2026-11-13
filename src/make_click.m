function [stim, trig, fs, info] = make_click(varargin)
%MAKE_CLICK Generate a monophasic rectangular pulse and its aligned trigger.

p = inputParser;
K = phase3_protocol_const();
p.addParameter('fs',192000);
p.addParameter('width_us',K.click_width_us);
p.addParameter('polarity','condensation');
p.addParameter('level',0.5);
p.addParameter('iti_ms',90);
p.addParameter('ici_ms',[]);
p.addParameter('pre_ms',5);
p.addParameter('trig_ms',1);
p.addParameter('trig_lvl',0.9);
p.parse(varargin{:});
o = p.Results;
fs = o.fs;

% --- 各長さをサンプルに換算 ---
wN   = round(o.width_us*1e-6*fs);          % クリック幅[サンプル]
preN = round(o.pre_ms*1e-3*fs);
itiN = round(o.iti_ms*1e-3*fs);
trN  = round(o.trig_ms*1e-3*fs);

% 極性: condensation=正方向, rarefaction=負方向(極性反転でCM除去)
switch lower(o.polarity)
    case 'condensation', s =  o.level; pol_sign =  1;
    case 'rarefaction',  s = -o.level; pol_sign = -1;
    otherwise, error('polarity は condensation か rarefaction');
end

stim = zeros(itiN,1);
trig = zeros(itiN,1);

% 1発目のクリック
on1 = preN+1;
stim(on1:on1+wN-1) = s;
% 2発目(paired時)
if ~isempty(o.ici_ms)
    iciN = round(o.ici_ms*1e-3*fs);
    if iciN > 0 && iciN < wN                       % ICI=0 は単一クリック(意図通り)。0<ICI<幅 は重なりで幅広化
        warning('make_click:iciOverlap', ...
            'ICI(%.3fms=%dsample) がクリック幅(%dsample)未満です。2発が重なり単一の幅広パルスになります。', ...
            o.ici_ms, iciN, wN);
    end
    on2 = on1 + iciN;
    if on2+wN-1 <= itiN
        stim(on2:on2+wN-1) = s;
    else
        warning('ICIがITIに収まりません。iti_ms を増やしてください。');
    end
end

% Align the trigger with the first pulse and encode polarity in its sign.
trig(on1:min(on1+trN-1,itiN)) = pol_sign * o.trig_lvl;

info.fs = fs;
info.width_samples = wN;
info.width_us_actual = wN/fs*1e6;     % 量子化後の実幅
info.epoch_samples = itiN;
info.click1_onset_sample = on1;
end
