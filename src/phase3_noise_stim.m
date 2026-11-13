function [x, state] = phase3_noise_stim(varargin)
%PHASE3_NOISE_STIM Generate a band-limited noise burst at a specified expected RMS.
% Compute filter gain from the mean squared frequency response. Applying this
% gain before filtering preserves natural variation between bursts.
% Return the random stream and second-order section states for continuity.

K = phase3_protocol_const();

p = inputParser;
p.addParameter('n', []);                    % 生成サンプル数 (必須)
p.addParameter('level_rms', []);            % 出力RMS (フルスケール線形, 必須)
p.addParameter('state', []);                % 継続する場合は前回の state
p.addParameter('fs', K.fs_hz);              % [Hz]
p.addParameter('band', K.noise_band_hz);    % [lo hi] Hz
p.addParameter('ramp_ms', K.ramp_ms);       % cos^2 ランプ長 [ms] (0=ランプなし)
p.addParameter('ramp_edges', 'both');       % 'both'|'in'|'out'|'none'
p.addParameter('seed', 'shuffle');          % 新規ストリームの seed
p.parse(varargin{:});
o = p.Results;

% ---- 必須引数 (既定値で黙って通さない: どちらも間違うと無音か過大レベルになる) ----
if isempty(o.n)
    error('phase3_noise_stim:n', "'n' (生成サンプル数) は必須です。");
end
if ~isscalar(o.n) || ~isnumeric(o.n) || o.n < 1 || o.n ~= fix(o.n)
    error('phase3_noise_stim:n', "'n' は 1 以上の整数スカラである必要があります (指定: %s)。", mat2str(o.n));
end
if isempty(o.level_rms)
    error('phase3_noise_stim:level', ...
        "'level_rms' (出力RMS, フルスケール線形) は必須です。dB FS からは phase3_level_map('db2amp',.) で。");
end
if ~isscalar(o.level_rms) || ~isnumeric(o.level_rms) || ~isreal(o.level_rms) || o.level_rms < 0
    error('phase3_noise_stim:level', "'level_rms' は 0 以上の実数スカラである必要があります。");
end
edges = lower(char(o.ramp_edges));
if ~ismember(edges, {'both','in','out','none'})
    error('phase3_noise_stim:rampedges', ...
        "'ramp_edges' は 'both'|'in'|'out'|'none' です (指定: '%s')。", edges);
end

% ---- state の構築 or 継承 ----
if isempty(o.state)
    state = new_state(o.band, o.fs, o.seed);
else
    state = o.state;
    % 継承時にパラメータを黙って読み替えない: 途中で帯域やレートが変わった状態で流れ続けると、
    % 「閾値測定と本実験が同じノイズ」という前提が記録に残らないまま崩れる。
    if state.fs ~= o.fs || ~isequal(state.band, o.band)
        error('phase3_noise_stim:statemismatch', ...
            ['継承した state と引数が不一致です (state: fs=%g band=[%g %g] / ' ...
             '引数: fs=%g band=[%g %g])。同一ストリームは同一設定で継続してください。'], ...
            state.fs, state.band(1), state.band(2), o.fs, o.band(1), o.band(2));
    end
end

% ---- 白色雑音 → 帯域制限 ----
% 白色側を level_rms/g で割り当ててから通す (ヘッダの理由によりブロック毎正規化はしない)。
w = randn(state.stream, o.n, 1) * (o.level_rms / state.g);
[x, state.zf] = sos_filter_state(state.sos, w, state.zf);
state.n_done  = state.n_done + o.n;

% ---- cos^2 ランプ ----
% ゲート由来の広帯域クリックを出さないため。これが無いと被験者はノイズではなくクリックを
% 検出でき、3AFC が測っている量が変わってしまう。
nr = round(o.ramp_ms*1e-3*o.fs);
if nr > 0 && ~strcmp(edges,'none')
    % 必要な長さは掛けるランプの本数分だけ。'in'/'out' は連続ストリームの先頭・末尾に使う
    % ものなので、ランプ2本分より短いブロックはむしろ普通に起こる。両側のときだけ 2倍要る。
    n_edges  = 1 + strcmp(edges,'both');
    need     = n_edges * nr;
    if need > o.n
        error('phase3_noise_stim:ramptoolong', ...
            'ランプ %.1f ms × %d (=%d サンプル) がブロック長 %d サンプルを超えます。', ...
            o.ramp_ms, n_edges, need, o.n);
    end
    r = sin(pi/2 * (0.5:nr-0.5).'/nr).^2;        % cos^2 (= sin^2 の立上り) 、端点で 0/1 に達しない
    if any(strcmp(edges, {'both','in'}))
        x(1:nr)         = x(1:nr)         .* r;
    end
    if any(strcmp(edges, {'both','out'}))
        x(end-nr+1:end) = x(end-nr+1:end) .* flipud(r);
    end
end

% ---- クリップ検査 ----
% Gaussian noise can exceed full scale even when its RMS is below full scale.
npk = nnz(abs(x) > 1);
if npk > 0
    % Clamp to match the full-scale limit of the playback path.
    x = max(min(x, 1), -1);
    % 指定 RMS の定常ガウスモデルによる超過サンプル数の期待値を参考情報として並記する。
    % ランプやフィルタ過渡を含む実波形の厳密な予測でも、呈示を許容する判定基準でもない。
    % 発火条件は変えない。閾値を置くと「黙ってクランプした」経路ができる。
    clip_sigma = 1/o.level_rms;
    if isinf(clip_sigma)
        % ゼロ/微小 RMS でも継承したフィルタ過渡はクリップし得る。定常モデルの期待値は0。
        % 有限入力のみを受けるヘルパに Inf を渡して、既存の警告経路をエラーに変えない。
        n_exp = 0;
    else
        n_exp = gauss_peak('cross', o.n, clip_sigma);
    end
    warning('phase3_noise_stim:clip', ...
        ['ノイズが ±1 を %d サンプル (%.3f%%) で超えたのでクランプしました。呈示は歪み、' ...
         'レベル較正が崩れます (現在 %.4g = %.1f dB FS)。\n' ...
         '指定 RMS の定常ガウスモデルでの期待超過サンプル数は %.3g です。' ...
         'ランプやフィルタ過渡は含まない参考値であり、呈示の許容判定ではありません。\n' ...
         '本プロトコルのクレスト余裕は %g dB です ' ...
         '(phase3_protocol_const の crest_headroom_db.noise)。'], ...
        npk, 100*npk/o.n, o.level_rms, 20*log10(max(o.level_rms, realmin)), ...
        n_exp, K.crest_headroom_db.noise);
end
end

%% ---- local: 新規ストリームの state ----
% sos と白色雑音ゲイン g はストリーム内で不変なので、毎ブロック作り直さず state に持つ。
function state = new_state(band, fs, seed)

if numel(band) ~= 2 || ~all(isfinite(band)) || band(1) <= 0 || band(2) <= band(1)
    error('phase3_noise_stim:band', ...
        'band は [lo hi] (0 < lo < hi) である必要があります (指定: %s)。', mat2str(band));
end
if band(2) >= fs/2
    % Reject cutoffs outside the range allowed by the sample rate.
    error('phase3_noise_stim:nyquist', ...
        '帯域上限 %g Hz が Nyquist %g Hz 以上です (fs=%g)。', band(2), fs/2, fs);
end

sos = bp_sos(band, fs);                       % 解析側と同じ実現形 (bp_sos.m の理由による)

% 白色雑音ゲイン g = sqrt(mean(|H|^2))。Parseval により sum(h^2) に等しい。
% 65536 点 = 0..Nyquist を約 0.73 Hz 刻み (fs=96 kHz) で、100 Hz のエッジも分解できる。
% freqz の 'whole' を使わないのは、実係数フィルタでは [0, pi] だけで平均が決まるため。
nfft = 65536;
H    = freqz(sos, nfft);
g    = sqrt(mean(abs(H).^2));

% seed: 既定は 'shuffle'。掃引ごとに独立なノイズが要る (反復すると加算でノイズが信号化する)
% ので、再現性より独立性を既定にする。再現が要る場面 (selftest) は明示的に数値を渡す。
if ischar(seed) || isstring(seed)
    stream = RandStream('twister', 'Seed', char(seed));
else
    stream = RandStream('twister', 'Seed', seed);
end

% 記録するのは要求した seed ではなく「実際に使われた seed」。'shuffle' を要求した場合、
% 文字列 'shuffle' を保存しても波形は二度と再現できない ── 再現性の記録のつもりが、
% 再現できないことを記録している状態になる。stream.Seed は解決後の数値。
state = struct('sos', sos, 'g', g, 'zf', zeros(2, size(sos,1)), ...
               'fs', fs, 'band', band, 'stream', stream, ...
               'seed', stream.Seed, 'seed_requested', seed, 'n_done', 0);
end

%% ---- local: sos を1セクションずつ状態付きで通す ----
% sosfilt が状態を取らず DSP System Toolbox も前提にできないため。各セクションは2次なので
% [b,a] 形でも良条件で、bp_sos.m が警告する一括 [b,a] 化の問題は起きない。
function [y, zf] = sos_filter_state(sos, x, zi)
y  = x;
zf = zi;
for k = 1:size(sos,1)
    [y, zf(:,k)] = filter(sos(k,1:3), sos(k,4:6), y, zi(:,k));
end
end
