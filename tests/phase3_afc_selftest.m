function ok = phase3_afc_selftest(varargin)
%PHASE3_AFC_SELFTEST Exercise stimulus generation, simulation and result saving without hardware.

p = inputParser;
p.addParameter('seed', 20260910);
% --- ノイズ検証 ---
p.addParameter('noise_s', 5);            % ノイズ試験の長さ [s]
p.addParameter('tol_rms_frac', 0.03);    % RMS 相対許容。帯域内の独立標本数は約 2*BW*T =
                                         % 2*9900*5 ≒ 1e5 で、RMS 推定の相対SDは 1/sqrt(2N)
                                         % ≒ 0.2 %。3 % は統計揺らぎの十数倍で、実際に効くのは
                                         % 「スケーリングが間違っている」場合だけ。
p.addParameter('tol_oob_db', 25);        % 帯域外減衰の下限 [dB]。butter 6次/エッジの理論値は
                                         % 1オクターブ外で約 36 dB。Welch の漏れと有限平均で
                                         % 実測は理論より浅く出るので 25 dB を下限にする。
                                         % 試しているのは「帯域制限が掛かっているか」であって
                                         % Butterworth の特性の dB 一致ではない。
p.addParameter('tol_stream', 1e-12);     % 分割生成と一括生成の一致 (同一演算なので本来は厳密)
p.addParameter('tol_ramp', 1e-12);       % ランプ形状の一致 (同上)
p.addParameter('tol_peak_sigma', 0.5);   % 実測ピークと期待超過数1の水準との差 [σ] (テスト17)。
                                         % 既定 seed の回帰検査として選んだ幅。誤検出率を保証する
                                         % 統計検定ではなく、別 seed では偶然に外れることもある。
% --- ステアケース検証 ---
p.addParameter('nrep', 120);             % 模擬ラン数。ラン内SDは約 2.4 dB なので SEM ≒ 0.21 dB
p.addParameter('psy_mu', -50);           % 心理測定関数の中点 [dB FS]
p.addParameter('psy_s', 3);              % 傾き [dB]。ロジスティックの 10-90 % 幅は 4.394*s なので
                                         % s=3 は 13 dB に相当し、検知課題の心理測定関数として
                                         % 妥当な範囲。⚠ ここを大きくしすぎない: s=8 とすると
                                         % 10-90 % が 35 dB に広がり、現実には存在しない緩さに
                                         % なる。その設定ではステアケースが遠い開始点から降り
                                         % きれず、実装ではなくモデルの非現実性が原因で
                                         % +4 dB のバイアスが出る。
p.addParameter('psy_lapse', 0.02);       % ラプス率 (高レベルでも稀に外す)
p.addParameter('tol_bias_db', 2.0);      % 収束先の許容バイアス [dB]。s=3 のとき 1-down-1-up が
                                         % 収束する 50 % 点は 70.7 % 点の 4.1 dB 下にあるので、
                                         % 2.0 dB はその取り違えを確実に検出する。⚠ 一方
                                         % 3-down-1-up の 79.4 % 点は 1.8 dB 上にしかなく、
                                         % 有限長ラン由来の残留バイアス(約1 dB)と同程度なので、
                                         % このテストでは分離できない。規則が 2-down-1-up
                                         % であること自体はテスト9が決定論的に確かめる。
p.addParameter('tol_sd_db', 4);          % ラン間SDの上限 [dB]。実測は約 2.4 dB。これを大きく
                                         % 超えるのは収束ではなく徘徊。
p.parse(varargin{:});
o = p.Results;

K = phase3_protocol_const();

% ---------------- 1) dB FS ↔ 振幅の往復 ----------------
amps = [1, 0.5, 0.1, 1e-3, 1e-5];
db   = phase3_level_map('amp2db', amps);
back = phase3_level_map('db2amp', db);
err1 = max(abs(back - amps) ./ amps);
assert(err1 < 1e-12, ...
    '1) dB FS 往復の相対誤差 %.3g が許容 %.3g を超えました。', err1, 1e-12);
assert(abs(phase3_level_map('amp2db', 0.5) + 6.0206) < 1e-3, ...
    '1) 振幅 0.5 が %.4f dB FS になりました (期待 -6.0206)。', ...
    phase3_level_map('amp2db', 0.5));
assert(isinf(phase3_level_map('amp2db', 0)), ...
    '1) 振幅 0 が -Inf dB FS になりません (無音の表現が壊れています)。');

fprintf('1) dB FS 往復 OK  最大相対誤差 %.2g\n', err1);

% ---------------- 4) 帯域制限後の RMS が指定値に一致 ----------------
fs   = K.fs_hz;
n    = round(o.noise_s * fs);
Lrms = 0.01;
x = phase3_noise_stim('n', n, 'level_rms', Lrms, 'fs', fs, 'band', K.noise_band_hz, ...
                      'ramp_ms', 0, 'ramp_edges', 'none', 'seed', o.seed);
frac = abs(rms(x) - Lrms) / Lrms;
assert(frac < o.tol_rms_frac, ...
    '4) 出力RMS %.6g が指定 %.6g から %.2f%% ずれています (許容 %.2f%%)。', ...
    rms(x), Lrms, 100*frac, 100*o.tol_rms_frac);

fprintf('4) 帯域制限後RMS OK  指定 %.4g / 実測 %.4g (%.2f%% ずれ)\n', Lrms, rms(x), 100*frac);

% ---------------- 5) 帯域外が落ちている ----------------
[pxx, f] = pwelch(x, hann(2^15), [], 2^15, fs);
inband  = mean(pxx(f >= 500  & f <= 5000));
below   = mean(pxx(f >= 45   & f <= 55));       % 100 Hz の1オクターブ下
above   = mean(pxx(f >= 19000 & f <= 21000));   % 10 kHz の1オクターブ上
att_lo  = 10*log10(inband/below);
att_hi  = 10*log10(inband/above);
assert(att_lo > o.tol_oob_db, ...
    '5) 50 Hz 付近の減衰が %.1f dB しかありません (下限 %.1f dB)。', att_lo, o.tol_oob_db);
assert(att_hi > o.tol_oob_db, ...
    '5) 20 kHz 付近の減衰が %.1f dB しかありません (下限 %.1f dB)。', att_hi, o.tol_oob_db);

fprintf('5) 帯域外減衰 OK  50 Hz %.0f dB / 20 kHz %.0f dB (下限 %.0f)\n', ...
        att_lo, att_hi, o.tol_oob_db);

% ---------------- 6) 状態継承した分割生成 == 一括生成 ----------------
% これが崩れると、30分の連続呈示にブロック周期の過渡が乗る。刺激同期ではないので加算平均で
% 消えず、σ_single を押し上げる形で効く。
nb = 4096;
whole = phase3_noise_stim('n', 3*nb, 'level_rms', Lrms, 'fs', fs, 'band', K.noise_band_hz, ...
                          'ramp_ms', 0, 'ramp_edges','none', 'seed', o.seed);
parts = zeros(3*nb, 1);
st = [];
for k = 1:3
    % seed は毎回渡すが効くのは st が空の初回だけ。2回目以降は state がストリームを持って
    % いるので無視される (省くと初回が 'shuffle' になり、一括生成と一致しなくなる)。
    [seg, st] = phase3_noise_stim('n', nb, 'level_rms', Lrms, 'state', st, 'fs', fs, ...
                                  'band', K.noise_band_hz, 'ramp_ms', 0, ...
                                  'ramp_edges','none', 'seed', o.seed);
    parts((k-1)*nb + (1:nb)) = seg;
end
err6 = max(abs(parts - whole)) / max(abs(whole));
assert(err6 < o.tol_stream, ...
    '6) 分割生成と一括生成の最大相対差 %.3g が許容 %.3g を超えました (境界で状態が切れています)。', ...
    err6, o.tol_stream);

fprintf('6) ストリーム状態の継承 OK  最大相対差 %.2g\n', err6);

% ---------------- 7) cos^2 ランプ ----------------
nramp  = round(K.ramp_ms*1e-3*fs);
nburst = round(K.burst_ms*1e-3*fs);
flat = phase3_noise_stim('n', nburst, 'level_rms', Lrms, 'fs', fs, 'band', K.noise_band_hz, ...
                         'ramp_ms', 0, 'ramp_edges','none', 'seed', o.seed);
ramped = phase3_noise_stim('n', nburst, 'level_rms', Lrms, 'fs', fs, 'band', K.noise_band_hz, ...
                           'ramp_ms', K.ramp_ms, 'ramp_edges','both', 'seed', o.seed);
% 同一 seed なので白色系列も濾波結果も同一 → 差はランプ包絡そのもの
r_expect = sin(pi/2 * (0.5:nramp-0.5).'/nramp).^2;
sc = max(abs(flat));
e_in  = max(abs(ramped(1:nramp)         - flat(1:nramp).*r_expect))          / sc;
e_out = max(abs(ramped(end-nramp+1:end) - flat(end-nramp+1:end).*flipud(r_expect))) / sc;
e_mid = max(abs(ramped(nramp+1:end-nramp) - flat(nramp+1:end-nramp)))        / sc;
assert(e_in  < o.tol_ramp, '7) 立上りランプの相対誤差 %.3g が許容 %.3g を超えました。', e_in,  o.tol_ramp);
assert(e_out < o.tol_ramp, '7) 立下りランプの相対誤差 %.3g が許容 %.3g を超えました。', e_out, o.tol_ramp);
assert(e_mid < o.tol_ramp, '7) ランプが中央部 (無加工のはず) を %.3g 変えています。', e_mid);

% 片側ランプはブロックがランプ2本分より短くても掛けられる。'in'/'out' は連続ストリームの
% 先頭・末尾に使うものなので、短いブロックはむしろ普通に起こる。
short_n = nramp + round(0.5*nramp);
xs = phase3_noise_stim('n', short_n, 'level_rms', Lrms, 'fs', fs, 'band', K.noise_band_hz, ...
                       'ramp_ms', K.ramp_ms, 'ramp_edges','in', 'seed', o.seed);
assert(numel(xs) == short_n, ...
    '7) 片側ランプで長さ %d が返りました (期待 %d)。', numel(xs), short_n);

fprintf('7) cos^2 ランプ OK  立上り %.2g / 立下り %.2g / 中央 %.2g / 片側短ブロック OK\n', ...
        e_in, e_out, e_mid);

% ---------------- 7b) クリップ時はクランプして警告する ----------------
% ガウス雑音のピークは非有界なので、RMS がフルスケールに近いと必ず ±1 を超える。デバイスは
% どのみち固く切るので、ソフト側でも切って「保存した波形 = 鳴った音」を保つ。
ws = warning('off','phase3_noise_stim:clip');   restore_w = onCleanup(@() warning(ws));
lastwarn('');
xc = phase3_noise_stim('n', 200000, 'level_rms', 0.5, 'fs', fs, 'band', K.noise_band_hz, ...
                       'ramp_ms', 0, 'ramp_edges','none', 'seed', o.seed);
[wmsg, wid] = lastwarn;
assert(max(abs(xc)) <= 1, ...
    '7b) クリップ保護後の最大振幅が %.4f です (1 を超えています)。', max(abs(xc)));
assert(strcmp(wid, 'phase3_noise_stim:clip'), ...
    '7b) クリップ時の警告 identifier が ''%s'' でした (期待 phase3_noise_stim:clip)。', wid);
% ±2σ の既知の超過率から、表示値を production の換算とは独立に照合する。
expected_clips7b = 200000 * 0.0455002638963584;
assert(contains(wmsg, sprintf('期待超過サンプル数は %.3g', expected_clips7b)), ...
    '7b) 警告に指定 RMS に基づく期待超過サンプル数が表示されていません。');
assert(contains(wmsg, '許容判定ではありません') && contains(wmsg, '呈示は歪み'), ...
    '7b) 警告は期待値を許容判定と区別し、呈示の歪みを伝える必要があります。');
assert(contains(wmsg, sprintf('クレスト余裕は %g dB', K.crest_headroom_db.noise)), ...
    '7b) 警告にプロトコルのクレスト余裕が表示されていません。');
% 指定 RMS がゼロでも、直前の大振幅ブロックのフィルタ状態がクリップを起こし得る。
% 逆数が Inf になる最小正数も、定常モデルの期待値は0として既存の警告経路を保つ。
[~, tail_state7b] = phase3_noise_stim('n', 4096, 'level_rms', 100, ...
    'ramp_edges', 'none', 'seed', o.seed);
for tail_level7b = [0, realmin*eps]
    lastwarn('');
    tail7b = phase3_noise_stim('n', 256, 'level_rms', tail_level7b, ...
        'state', tail_state7b, 'ramp_edges', 'none');
    [tail_msg7b, tail_id7b] = lastwarn;
    assert(max(abs(tail7b)) == 1 && strcmp(tail_id7b, 'phase3_noise_stim:clip'), ...
        '7b) 微小/ゼロ RMS への継続でも過渡のクランプと警告が必要です。');
    assert(contains(tail_msg7b, '期待超過サンプル数は 0'), ...
        '7b) 微小/ゼロ RMS の定常モデル期待値は0である必要があります。');
end

fprintf('7b) クリップのクランプ+警告 OK  最大振幅 %.4f\n', max(abs(xc)));

% ---------------- 7c) 実現 seed が記録される ----------------
% 'shuffle' を要求したとき、文字列 'shuffle' を保存しても波形は再現できない。記録すべきは
% 解決後の数値 seed。
[~, st_sh] = phase3_noise_stim('n', 16, 'level_rms', Lrms, 'fs', fs, ...
                               'band', K.noise_band_hz, 'ramp_ms', 0, ...
                               'ramp_edges','none', 'seed', 'shuffle');
assert(isnumeric(st_sh.seed) && isscalar(st_sh.seed), ...
    '7c) shuffle 要求時の state.seed が %s です (数値スカラであるべき)。', class(st_sh.seed));
assert(strcmp(st_sh.seed_requested, 'shuffle'), ...
    '7c) seed_requested に要求内容が残っていません。');

fprintf('7c) 実現 seed の記録 OK  shuffle → %d\n', st_sh.seed);

% ---------------- 8) 2-down-1-up が 70.7 % 点へ収束する ----------------
% 心理測定関数を明示的に置き、その関数上で pc_target を与えるレベルを解析的に求めてから、
% 本番の phase3_afc_threshold を模擬観測者で駆動して推定値と突き合わせる。
g       = 1/3;                                  % 3AFC の推測率
L_true  = psy_level(K.pc_target, o.psy_mu, o.psy_s, o.psy_lapse, g);
rs      = RandStream('twister','Seed', o.seed);
est     = zeros(o.nrep,1);
for i = 1:o.nrep
    obs = @(lvl, tgt, ph) sim_observer(lvl, tgt, ph, o.psy_mu, o.psy_s, o.psy_lapse, g, ...
                                       L_true + 5, rs);
    T = phase3_afc_threshold('sim_observer', obs, 'max_level_dbfs', -20, ...
                             'n_practice', 0, 'n_runs', 1, 'n_runs_max', 1, ...
                             'max_trials', 400, 'save', false, 'verbose', false, ...
                             'seed', o.seed + i);
    est(i) = T.threshold_dbfs;
end
bias = mean(est) - L_true;
sd   = std(est);
sem  = sd / sqrt(o.nrep);
% nrep が小さいと、このテストは実装の偏りではなく標本誤差を見ることになる。既定 120 での
% SEM は約 0.23 dB だが、nrep=12 では 0.7 dB を超え、許容 2.0 dB に対して無視できない。
% 「小さい nrep で偶然落ちる」のは実装の欠陥を示さないので、テストとして成立する最小の
% nrep を要求して止める (静かに緩めるのではなく、測れないことを言う)。
assert(o.nrep >= 60, ...
    ['8) nrep=%d では標本誤差 (SEM %.2f dB) が許容 %.2f dB に対して大きすぎ、' ...
     'このテストは実装の偏りを判定できません。nrep は 60 以上にしてください。'], ...
    o.nrep, sem, o.tol_bias_db);
assert(abs(bias) < o.tol_bias_db, ...
    ['8) 収束先が真の %.1f%% 点 (%.2f dB FS) から %.2f dB ずれています (許容 %.2f)。' ...
     '推定 %.2f ± %.2f dB, n=%d。'], ...
    100*K.pc_target, L_true, bias, o.tol_bias_db, mean(est), sd, o.nrep);
assert(sd < o.tol_sd_db, ...
    '8) ラン間SD %.2f dB が上限 %.2f dB を超えました (収束せず徘徊しています)。', sd, o.tol_sd_db);

fprintf(['8) 2-down-1-up 収束 OK  真値 %.2f / 推定 %.2f ± %.2f dB ' ...
         '(バイアス %+.2f, SEM %.2f, 許容 %.1f, n=%d)\n'], ...
        L_true, mean(est), sd, bias, sem, o.tol_bias_db, o.nrep);

% ---------------- 9) ステアケースの機構 ----------------
% 決定論的観測者 (L0 以上なら必ず正答、未満なら必ず誤答) で、乱数に依らず機構だけを見る。
L0  = -50;
det = @(lvl, tgt, ph) det_observer(lvl, tgt, ph, L0);
Td  = phase3_afc_threshold('sim_observer', det, 'max_level_dbfs', -20, ...
                           'n_practice', 0, 'n_runs', 1, 'n_runs_max', 1, ...
                           'save', false, 'verbose', false, 'seed', o.seed);
R1  = Td.runs(1);
assert(numel(R1.reversals_db) == K.n_reversals, ...
    '9) 反転数が %d です (期待 %d)。', numel(R1.reversals_db), K.n_reversals);
th_recomputed = mean(R1.reversals_db(end-K.n_reversals_avg+1:end));
assert(abs(R1.threshold_dbfs - th_recomputed) < 1e-12, ...
    '9) 閾値 %.6f が「末尾%d反転の平均」%.6f と一致しません。', ...
    R1.threshold_dbfs, K.n_reversals_avg, th_recomputed);
% ステップ幅の切替: step_change_at_rev 番目の反転より後の試行は step_final_db
steps = [R1.trials.step_db];
assert(steps(1) == K.step_start_db, ...
    '9) 初期ステップが %.1f dB です (期待 %.1f)。', steps(1), K.step_start_db);
assert(steps(end) == K.step_final_db, ...
    '9) 最終ステップが %.1f dB です (期待 %.1f)。', steps(end), K.step_final_db);
assert(all(ismember(steps, [K.step_start_db K.step_final_db])), ...
    '9) 仕様外のステップ幅が使われました: %s', mat2str(unique(steps)));
% 収束先が L0 を細ステップ幅の範囲で挟んでいること
assert(abs(R1.threshold_dbfs - L0) <= K.step_final_db + 0.5, ...
    '9) 決定論的観測者の切替点 %.1f に対し閾値が %.2f dB FS です (差 %.2f, 許容 %.2f)。', ...
    L0, R1.threshold_dbfs, abs(R1.threshold_dbfs - L0), K.step_final_db + 0.5);

% --- 規則が 2-down-1-up そのものであることの直接検証 ---
% テスト8は収束先の位置しか見ておらず、s が現実的な傾きのとき 79.4 % 点 (3-down-1-up の
% 収束先) は 1.8 dB しか離れていないので分離できない。ここで規則を決定論的に固定する。
lv   = [R1.trials.level_db];
corr = [R1.trials.correct];
for i = 2:numel(lv)
    d = lv(i) - lv(i-1);
    if d < 0            % 下降 = 直前2試行が連続正答 (2-down)
        assert(i >= 3, '9) 試行%d で下降しました。2-down なら3試行目以降でしか下降できません。', i);
        assert(corr(i-1) && corr(i-2), ...
            '9) 試行%d の下降の直前2試行が連続正答ではありません (correct = %d, %d)。', ...
            i, corr(i-2), corr(i-1));
    elseif d > 0        % 上昇 = 直前1試行が誤答 (1-up)
        assert(~corr(i-1), '9) 試行%d の上昇の直前試行が正答でした (1-up 違反)。', i);
    end
end
% 同一レベルで3連続正答は起こり得ない (2連続で必ず下降するため)。3-down-1-up ならここで落ちる。
for i = 3:numel(lv)
    same3 = (lv(i) == lv(i-1)) && (lv(i-1) == lv(i-2));
    assert(~(same3 && corr(i) && corr(i-1) && corr(i-2)), ...
        '9) 試行%d-%d が同一レベル %.1f で3連続正答です (2-down なら2連続で下降するはず)。', ...
        i-2, i, lv(i));
end

fprintf('9) ステアケース機構 OK  反転%d / 閾値 %.2f (切替点 %.1f) / ステップ %s / 2-down-1-up 検証済\n', ...
        numel(R1.reversals_db), R1.threshold_dbfs, L0, mat2str(unique(steps)));

% ---------------- 10) ラン合成の規則と追加ランの発火 ----------------
[th2, u2, ok2] = phase3_afc_combine([-50 -51], 4);
assert(abs(th2 + 50.5) < 1e-12 && isequal(u2, 1:2) && ok2, ...
    '10) 許容内2ランの合成が %.3f / used %s / ok %d になりました (期待 -50.5 / [1 2] / 1)。', ...
    th2, mat2str(u2), ok2);
[~, ~, ok_wide] = phase3_afc_combine([-50 -56], 4);
assert(~ok_wide, '10) 差 6 dB が許容 4 dB 内と判定されました。');
[th3, u3] = phase3_afc_combine([-50 -56 -49.5], 4);
assert(isequal(sort(u3), [1 3]) && abs(th3 + 49.75) < 1e-12, ...
    '10) 3ラン合成が %.3f / used %s になりました (期待 -49.75 / [1 3])。', th3, mat2str(u3));
% 追加ランが実際に走ること。run_tol_db を負にすると spread_ok が必ず偽になるので、
% 「ばらつき次第で発火したりしなかったり」ではなく確実に分岐を通る。
Ta = phase3_afc_threshold('sim_observer', det, 'max_level_dbfs', -20, 'n_practice', 0, ...
                          'run_tol_db', -1, 'save', false, 'verbose', false, 'seed', o.seed);
assert(Ta.n_runs_done == K.n_runs_max, ...
    '10) 追加ランが発火せず %d ランで終わりました (期待 %d)。', Ta.n_runs_done, K.n_runs_max);

fprintf('10) ラン合成規則 OK  追加ラン発火 %d ラン\n', Ta.n_runs_done);

% ---------------- 11) ガードが正しい identifier で止まる ----------------
% 表駆動。ガードが「何かで落ちる」のではなく
% 「意図した理由で落ちる」ことを見る。
guards = {
  @() phase3_afc_threshold('sim_observer', det, 'save', false, 'verbose', false), ...
        'phase3_afc_threshold:maxlevel'
  @() phase3_afc_threshold('sim_observer', det, 'max_level_dbfs', 3, 'save', false, 'verbose', false), ...
        'phase3_afc_threshold:maxlevel'
  @() phase3_afc_threshold('sim_observer', det, 'max_level_dbfs', -20, ...
                           'min_level_dbfs', -10, 'save', false, 'verbose', false), ...
        'phase3_afc_threshold:levelrange'
  @() phase3_afc_threshold('sim_observer', det, 'max_level_dbfs', -20, ...
                           'n_reversals', 4, 'n_reversals_avg', 6, 'save', false, 'verbose', false), ...
        'phase3_afc_threshold:reversals'
  @() phase3_afc_threshold('sim_observer', 42, 'max_level_dbfs', -20, 'save', false, 'verbose', false), ...
        'phase3_afc_threshold:simobserver'
  @() phase3_afc_threshold('sim_observer', @never_hears, 'max_level_dbfs', -20, 'n_practice', 0, ...
                           'save', false, 'verbose', false), ...
        'phase3_afc_threshold:ascendceiling'
  % 上昇法の床で既に聞こえている場合。返せるのは探索範囲の床であって推定値ではないので、
  % 黙って下へ広げず操作者に下げさせる。
  @() phase3_afc_threshold('sim_observer', @always_hears, 'max_level_dbfs', -20, ...
                           'n_practice', 0, 'save', false, 'verbose', false), ...
        'phase3_afc_threshold:ascendfloor'
  @() phase3_afc_threshold('sim_observer', det, 'max_level_dbfs', -20, ...
                           'ascend_start_db', -200, 'save', false, 'verbose', false), ...
        'phase3_afc_threshold:ascendbelowfloor'
  @() phase3_afc_threshold('sim_observer', det, 'max_level_dbfs', -20, ...
                           'ascend_start_db', 0, 'save', false, 'verbose', false), ...
        'phase3_afc_threshold:ascendstart'
  @() phase3_afc_threshold('sim_observer', det, 'max_level_dbfs', -20, ...
                           'step_final_db', 0, 'save', false, 'verbose', false), ...
        'phase3_afc_threshold:step'
  % 収束しないまま延々続けない。収束しないこと自体が装着か課題理解の所見なので静かに続けない。
  @() phase3_afc_threshold('sim_observer', det, 'max_level_dbfs', -20, 'n_practice', 0, ...
                           'max_trials', 5, 'save', false, 'verbose', false), ...
        'phase3_afc_threshold:maxtrials'
  % sim_observer の契約違反 (1..3 以外) を黙って受け取らない
  @() phase3_afc_threshold('sim_observer', @(l,t,p) bad_sim(l,t,p), 'max_level_dbfs', -20, ...
                           'n_practice', 0, 'save', false, 'verbose', false), ...
        'phase3_afc_threshold:simreturn'
  % 保存経路の :ear / :meta はテスト13が同じ identifier に加えて「呈示前に落ちる」まで
  % 見ているので、ここには置かない (同じ id を2つの表で固定すると片方だけ古くなる)。
  @() phase3_noise_stim('level_rms', 0.01), ...
        'phase3_noise_stim:n'
  @() phase3_noise_stim('n', 100), ...
        'phase3_noise_stim:level'
  @() phase3_noise_stim('n', 100, 'level_rms', 0.01, 'fs', 8000, 'band', [100 10000]), ...
        'phase3_noise_stim:nyquist'
  @() phase3_noise_stim('n', 100, 'level_rms', 0.01, 'ramp_edges', 'sometimes'), ...
        'phase3_noise_stim:rampedges'
  % 上限は RMS 基準。ガウス雑音のピークはフルスケールからクレスト余裕
  % (phase3_protocol_const の crest_headroom_db.noise) より上だとクリップする。-6 dB FS は
  % どのクレスト設定でもノイズ上限より上なので、値は据え置いてよい。
  % 以前は「0 dB FS を超えなければ可」だった。
  @() phase3_afc_threshold('sim_observer', det, 'max_level_dbfs', -6, ...
                           'save', false, 'verbose', false), ...
        'phase3_afc_threshold:maxlevel'
  @() phase3_afc_threshold('sim_observer', det, 'max_level_dbfs', -20, ...
                           'n_reversals_avg', 0, 'save', false, 'verbose', false), ...
        'phase3_afc_threshold:reversals'
  @() phase3_afc_threshold('sim_observer', det, 'max_level_dbfs', -20, ...
                           'step_change_at_rev', 0, 'save', false, 'verbose', false), ...
        'phase3_afc_threshold:stepchange'
  @() phase3_afc_threshold('sim_observer', det, 'max_level_dbfs', -20, ...
                           'n_runs', 5, 'n_runs_max', 3, 'save', false, 'verbose', false), ...
        'phase3_afc_threshold:nruns'
  @() phase3_level_map('amp2dB_typo', 0.5), ...
        'phase3_level_map:op'
  @() phase3_level_map('amp2db', -0.5), ...
        'phase3_level_map:negamp'
  @() phase3_afc_combine([-50 -51]), ...
        'phase3_afc_combine:args'
  @() phase3_afc_combine([-50 NaN], 4), ...
        'phase3_afc_combine:th'
};
for i = 1:size(guards,1)
    got = '';
    try
        guards{i,1}();
    catch ME
        got = ME.identifier;
    end
    assert(strcmp(got, guards{i,2}), ...
        '11) ガード %d: identifier が ''%s'' でした (期待 ''%s'')。', i, got, guards{i,2});
end

fprintf('11) ガード %d 件 OK\n', size(guards,1));

% ---------------- 12) 中断時に完了済みランが部分保存される ----------------
% 中断は後のランで起きるほど失うものが大きい。3ラン目で集中が切れただけで完了済みの2ランを
% 捨てて全部やり直しになるのは割に合わないので、完了分は aborted 付きで残す。
% 試行数を数えて途中で 0(中断) を返す観測者で、実際に経路を通す。
outdir12 = fullfile(tempdir, 'afc_selftest_partial');
if exist(outdir12,'dir'), rmdir(outdir12,'s'); end
mkdir(outdir12);
cleanup12 = onCleanup(@() rmdir(outdir12,'s'));
ctr  = containers.Map({'n'}, {0});          % handle オブジェクトなのでクロージャから変更できる
quit_after = 20;                            % 1ラン(決定論的観測者で約15試行)を終えた後に中断させる
obs12 = @(lvl, tgt, ph) quitting_observer(lvl, tgt, ph, L0, ctr, quit_after);
threw12 = '';
try
    phase3_afc_threshold('sim_observer', obs12, 'max_level_dbfs', -20, 'n_practice', 0, ...
                         'verbose', false, 'seed', o.seed, 'outdir', outdir12, ...
                         'subject', 'PART', 'ear', 'R');
catch ME12
    threw12 = ME12.identifier;
end
assert(strcmp(threw12, 'phase3_afc_threshold:aborted'), ...
    '12) 中断が ''%s'' で送出されました (期待 phase3_afc_threshold:aborted)。', threw12);
saved = dir(fullfile(outdir12, 'PART', '*_aborted.mat'));
assert(isscalar(saved), ...
    '12) 部分保存ファイルが %d 個です (期待 1)。中断で完了済みランが失われています。', numel(saved));
S12 = load(fullfile(saved(1).folder, saved(1).name));
assert(S12.T.aborted && S12.T.n_runs_done >= 1, ...
    '12) 部分保存の中身が aborted=%d / n_runs_done=%d です。', S12.T.aborted, S12.T.n_runs_done);
assert(~isfield(S12.T, 'threshold_dbfs'), ...
    '12) 部分保存に threshold_dbfs が入っています。規定ラン数未達の推定値を確定値と同じ形で残すと、後日それが確定値として使われます。');

fprintf('12) 中断時の部分保存 OK  完了 %d ラン を %s に保存\n', S12.T.n_runs_done, saved(1).name);

% ---------------- 13) 保存の不備は「呈示が始まる前」に落ちる ----------------
% Validate output settings before the simulated observer is called.
early = {
  {'outdir', fullfile(tempdir,'no_such_root_afc_selftest'), 'ear','R'}, 'phase3_afc_threshold:noroot'
  {'outdir', tempdir, 'ear', ''},                                       'phase3_afc_threshold:meta'
  {'outdir', tempdir, 'ear', 'X'},                                      'phase3_afc_threshold:ear'
};
for i = 1:size(early,1)
    cnt13 = containers.Map({'n'}, {0});
    obs13 = @(lvl, tgt, ph) counting_observer(lvl, tgt, ph, L0, cnt13);
    got13 = '';
    try
        phase3_afc_threshold('sim_observer', obs13, 'max_level_dbfs', -20, ...
                             'n_practice', 0, 'verbose', false, 'subject', 'EARLY', ...
                             early{i,1}{:});
    catch ME13
        got13 = ME13.identifier;
    end
    assert(strcmp(got13, early{i,2}), ...
        '13) ケース%d: identifier が ''%s'' でした (期待 ''%s'')。', i, got13, early{i,2});
    assert(cnt13('n') == 0, ...
        ['13) ケース%d: 落ちる前に %d 回呈示していました。保存の不備は呈示が' ...
         '始まる前に検出しなければ、測定時間ごと失われます。'], i, cnt13('n'));
end

% dry_run は保存しないので、被験者情報を要求してはいけない。音を出さない組立確認の
% 呼び出しは subject/ear を渡さないので、ここで要求すると確認の操作が落ちる。
Tdry = phase3_afc_threshold('dry_run', true, 'max_level_dbfs', -40, 'verbose', false);
assert(isstruct(Tdry) && isfield(Tdry,'dry_run') && Tdry.dry_run, ...
    '13) dry_run が被験者情報なしで通りませんでした。');

fprintf('13) 保存不備は呈示前に検出 OK  %d ケースとも呈示回数 0 / dry_run は無関係\n', size(early,1));

% ---------------- 14) 保存に失敗しても完成した測定は返る ----------------
% 事前検査を通っても、ディスク満杯・権限・同期フォルダのロックで保存は失敗しうる。そのとき
% 例外を送出すると完成した測定ごと失われるので、警告に落として T を返す。
% 被験者名と同じ名前の「ファイル」を置くと、被験者サブフォルダが作れず save が失敗する。
outdir14 = fullfile(tempdir, 'afc_selftest_savefail');
if exist(outdir14,'dir'), rmdir(outdir14,'s'); end
mkdir(outdir14);
cleanup14 = onCleanup(@() rmdir(outdir14,'s'));
fid14 = fopen(fullfile(outdir14, 'BLOCKED'), 'w'); fclose(fid14);   % 同名ファイルで塞ぐ
ws14 = warning('off','all');  restore14 = onCleanup(@() warning(ws14));
lastwarn('');
T14 = phase3_afc_threshold('sim_observer', det, 'max_level_dbfs', -20, 'n_practice', 0, ...
                           'verbose', false, 'seed', o.seed, 'outdir', outdir14, ...
                           'subject', 'BLOCKED', 'ear', 'R');
[~, wid14] = lastwarn;
assert(isstruct(T14) && isfield(T14,'threshold_dbfs') && isfinite(T14.threshold_dbfs), ...
    '14) 保存失敗時に測定結果が返りませんでした。');
assert(isfield(T14,'outfile') && isempty(T14.outfile), ...
    '14) 保存失敗なのに outfile が ''%s'' になっています。', T14.outfile);
assert(strcmp(wid14, 'phase3_afc_threshold:savefailed'), ...
    '14) 警告 identifier が ''%s'' でした (期待 phase3_afc_threshold:savefailed)。', wid14);

fprintf('14) 保存失敗でも測定は返る OK  閾値 %.2f dB FS を保持\n', T14.threshold_dbfs);

% ---------------- 15) レベル範囲の下端も上端と対称に fail-loud ----------------
% ⚠ ここが本テストの中で最も重い一件。下限を無音でクランプしていた頃は、閾値が範囲の下に
% ある機材でステアケースが下限に貼り付き、被験者が推測水準に落ち、クランプ周辺で反転が
% 量産され、min_level_dbfs がそのまま「収束した閾値」として無警告で返っていた ── 手動上昇法で
% 直したのと同じ欠陥が、ステアケースの中で再現していた。上端と同じ identifier で落ちること、
% そして「それらしい閾値」を返さないことを確かめる。
edge = { ...
  % 何を聞かせても聞こえない被験者 → ステアケースは上へ張り付く
  @(lvl,tgt,ph) deaf_but_responds(lvl,tgt,ph), -60, -20
  % 何を聞かせても当てる被験者 → 下へ張り付く (上昇法は別ガードなので min から外して回避)
  @(lvl,tgt,ph) sharp_ears(lvl,tgt,ph),        -60, -20
};
for i = 1:size(edge,1)
    got15 = ''; res15 = [];
    try
        res15 = phase3_afc_threshold('sim_observer', edge{i,1}, ...
                                     'min_level_dbfs', edge{i,2}, 'max_level_dbfs', edge{i,3}, ...
                                     'ascend_start_db', -59, 'n_practice', 0, ...
                                     'save', false, 'verbose', false, 'seed', o.seed);
    catch ME15
        got15 = ME15.identifier;
    end
    assert(strcmp(got15, 'phase3_afc_threshold:levelrangeexhausted'), ...
        ['15) ケース%d: identifier が ''%s'' でした (期待 levelrangeexhausted)。' ...
         '範囲の端に貼り付いたまま「閾値」を返すと、それは測定値ではなく範囲の端です。'], ...
        i, got15);
    assert(isempty(res15), '15) ケース%d: 範囲を使い切ったのに結果が返りました。', i);
end

fprintf('15) レベル範囲の上下端が対称に fail-loud OK  %d ケース\n', size(edge,1));

% ---------------- 16) クリック刺激経路 ----------------
% ノイズ用の測定器をクリックにも使えるようにしたので、変わったのは「区間の中身」だけである
% ことを確かめる。特にレベルの単位が RMS からピークに変わる点と、それに伴いクレスト余裕が
% ノイズの値から 0 dB になる点は、間違えれば呈示できないか歪むかのどちらかになる。
[xc, ci] = phase3_click_stim('level', 0.25, 'fs', K.fs_hz);
assert(ci.n_epochs == K.click_burst_epochs, ...
    '16) クリック列が %d エポックです (期待 %d)。', ci.n_epochs, K.click_burst_epochs);
rate_ref = 1e3 / K.click_iti_ms;
assert(abs(ci.rate_hz - rate_ref) < 1e-9, ...
    ['16) クリック列のレートが %.4f/s です (本番 %.4f/s と一致すべき ── レートが違えば' ...
     '時間積分が変わり、測った閾値が nHL の基準にならない)。'], ci.rate_hz, rate_ref);
assert(abs(max(abs(xc)) - 0.25) < 1e-12, ...
    '16) クリックのピークが %.6f です (レベルはピークそのもののはず)。', max(abs(xc)));
% ランプが掛かっていないこと: 掛かっていれば非ゼロ標本に中間値が現れる。
nz16 = xc(xc ~= 0);
assert(all(abs(abs(nz16) - 0.25) < 1e-12), ...
    '16) クリックの %d サンプルが中間値です (ランプが掛かっています)。', ...
    nnz(abs(abs(nz16) - 0.25) >= 1e-12));

% 刺激ごとのクレスト上限。上限は定数から引く ── リテラルで書くと、クレスト余裕を動かした
% ときにこのテストだけが古い上限を検査し続け、「定数の変更を止めるべきテストが、定数の
% 変更に追従できない」状態になる (実際 -12 と書いてあり、16 dB 化で FAIL した)。
Tdc = phase3_afc_threshold('dry_run', true, 'stimulus','click', 'max_level_dbfs', -10, 'verbose', false);
assert(strcmp(Tdc.stimulus,'click') && abs(Tdc.nburst/Tdc.fs*1e3 - ci.duration_ms) < 1e-9, ...
    '16) dry_run の区間長が %.3f ms です (期待 %.3f)。', Tdc.nburst/Tdc.fs*1e3, ci.duration_ms);
click_ceil = -K.crest_headroom_db.click;
noise_ceil = -K.crest_headroom_db.noise;
ceil_cases = { 'click', click_ceil + 5, true      % 上限超過 → 例外
               'click', click_ceil,     false     % 上限ちょうど → 通る
               'noise', noise_ceil + 6, true
               'noise', noise_ceil,     false };
for i = 1:size(ceil_cases,1)
    threw16 = false;
    try
        phase3_afc_threshold('dry_run', true, 'stimulus', ceil_cases{i,1}, ...
                             'max_level_dbfs', ceil_cases{i,2}, 'verbose', false);
    catch ME
        threw16 = strcmp(ME.identifier, 'phase3_afc_threshold:maxlevel');
    end
    assert(threw16 == ceil_cases{i,3}, ...
        ['16) %s / 上限 %g dB FS が期待と逆の挙動でした。クレスト余裕が刺激ごとに' ...
         'なっていません (ノイズのクレスト余裕は %g dB)。'], ...
        ceil_cases{i,1}, ceil_cases{i,2}, K.crest_headroom_db.noise);
end

% 本番のステアケースがクリック経路でも収束すること。刺激を差し替えても測定ロジックは同じ1本
% であるべきなので、テスト9と同じ決定論的観測者で駆動して機構だけを見る。
L16   = -30;
det16 = @(lvl, tgt, ph) det_observer(lvl, tgt, ph, L16);
T16 = phase3_afc_threshold('sim_observer', det16, 'stimulus','click', 'max_level_dbfs', -5, ...
                           'min_level_dbfs', -90, 'n_practice', 0, 'n_runs', 1, 'n_runs_max', 1, ...
                           'save', false, 'verbose', false);
assert(strcmp(T16.stimulus, 'click'), '16) T.stimulus が ''%s'' です。', T16.stimulus);
assert(abs(T16.threshold_dbfs - L16) <= K.step_final_db + 0.5, ...
    '16) クリック経路の閾値が %.2f dB FS でした (真値 %.1f の ±%.1f dB 内に来るべき)。', ...
    T16.threshold_dbfs, L16, K.step_final_db + 0.5);
assert(strcmp(T16.stim_params.kind,'click') && ...
       T16.stim_params.detail.n_epochs == K.click_burst_epochs && ...
       T16.stim_params.detail.width_samples == round(K.click_width_us*1e-6*K.fs_hz) && ...
       abs(T16.stim_params.detail.width_us_actual-K.click_width_us) < 1e-9, ...
    '16) 保存される刺激パラメータがクリックのものになっていません。');

fprintf('16) クリック刺激経路 OK  区間 %.0f ms / %.2f/s / 閾値 %.2f dB FS\n', ...
        ci.duration_ms, ci.rate_hz, T16.threshold_dbfs);

% ---------------- 17) クレスト余裕が基準から導かれていること ----------------
% 往復だけでは順逆に共通する誤りを見逃す。標準正規分布の ±1σ 超過率を既知値として使う。
p17 = 0.317310507862914;
assert(abs(gauss_peak('CrOsS', 1, 1) - p17) < 1e-14, ...
    '17) ±1σ の超過率が既知値と一致しません。');
assert(abs(gauss_peak("SIGMA", 1, p17) - 1) < 1e-13, ...
    '17) 小数の期待超過数から ±1σ に戻りません。');
assert(abs(gauss_peak('cross', 100, 1) - 100*p17) < 1e-12, ...
    '17) 期待超過サンプル数が N に比例していません。');
assert(gauss_peak('sigma', 10, 10) == 0 && gauss_peak('cross', 10, 0) == 10, ...
    '17) 水準0と期待超過数Nの境界が一致しません。');

bad17 = {
    @() gauss_peak(),                   'gauss_peak:args'
    @() gauss_peak('sigma'),            'gauss_peak:args'
    @() gauss_peak('sigma', 10),        'gauss_peak:args'
    @() gauss_peak('typo', 10, 1),      'gauss_peak:op'
    @() gauss_peak(1, 10, 1),           'gauss_peak:op'
    @() gauss_peak(["sigma","cross"], 10, 1), 'gauss_peak:op'
    @() gauss_peak('sigma', 10, 0),     'gauss_peak:value'
    @() gauss_peak('sigma', 10, -1),    'gauss_peak:value'
    @() gauss_peak('sigma', 10, 11),    'gauss_peak:value'
    @() gauss_peak('cross', 10, -1),    'gauss_peak:value'
};
invalid_n17 = {0, -1, 1.5, NaN, Inf, 1i, [1 2], [], '10'};
for j17 = 1:numel(invalid_n17)
    v17 = invalid_n17{j17};
    bad17(end+1,:) = {@() gauss_peak('cross', v17, 1), 'gauss_peak:samples'}; %#ok<AGROW>
end
invalid_x17 = {NaN, Inf, 1i, [1 2], [], '1'};
for op17 = {'sigma','cross'}
    for j17 = 1:numel(invalid_x17)
        v17 = invalid_x17{j17};
        operation17 = op17{1};
        bad17(end+1,:) = {@() gauss_peak(operation17, 10, v17), 'gauss_peak:value'}; %#ok<AGROW>
    end
end
for j17 = 1:size(bad17,1)
    caught17 = '';
    try
        bad17{j17,1}();
    catch ME17
        caught17 = ME17.identifier;
    end
    assert(strcmp(caught17, bad17{j17,2}), ...
        '17) 不正入力ケース%d: identifier %s (期待 %s)。', j17, caught17, bad17{j17,2});
end

% crest_headroom_db.noise は「呈示1ブロックでクリップ期待値 < 1」という基準から導いた値で
% あって、選んだ数字ではない。ここで再計算することで、定数と基準がズレたまま実験に入るのを
% 止める。以前ここに検査が無かったとき、定数は「ピークは約 4σ」という N を含まない根拠で
% 置かれており、実測 (500 ms バースト 4.20σ / 30分 5.70σ) のどちらにも足りていなかった。
N17  = K.crest_basis.ref_seconds * K.fs_hz;
s17  = gauss_peak('sigma', N17, K.crest_basis.max_expected_clips);
db17 = ceil(20*log10(s17));
assert(K.crest_headroom_db.noise == db17, ...
    ['17) crest_headroom_db.noise が %g dB ですが、crest_basis (%g 秒 / 期待クリップ %g) ' ...
     'からの導出値は %g dB (%.3f σ) です。定数と根拠がズレています。'], ...
    K.crest_headroom_db.noise, K.crest_basis.ref_seconds, ...
    K.crest_basis.max_expected_clips, db17, s17);

% 既定 seed で生成するノイズのピークを回帰検査する。期待超過数1の水準は最大値の期待値では
% なく、単一系列がこの近傍に収まることもガウス分布の証明にはならない。フィルタやスケールの
% 変更によるピークの変化を検出する補助検査とし、換算の正しさは上の既知値検査で確認する。
% 実験前ゲートなので 1e6 サンプル (約10秒分・生成は1秒未満) に留め、30分の実測は行わない。
n17    = 1e6;
lvl17  = 0.01;
x17    = phase3_noise_stim('n', n17, 'level_rms', lvl17, 'seed', o.seed, 'ramp_edges', 'none');
pk17   = max(abs(x17)) / lvl17;                    % σ 単位のピーク
pred17 = gauss_peak('sigma', n17, 1);             % 期待超過数=1 となる水準
d17 = abs(pk17 - pred17);
assert(d17 < o.tol_peak_sigma, ...
    ['17) %g サンプルのピークが %.2f σ で、期待超過数1の水準 %.2f σ から %.2f σ ' ...
     '離れています (回帰許容差 %.2f)。seed・フィルタ・level_rms の変更を確認してください。'], ...
    n17, pk17, pred17, d17, o.tol_peak_sigma);

fprintf('17) クレスト余裕の導出 OK  %g dB (%.3f σ, N=%.4g) / 実測ピーク %.2f σ (期待超過数1の水準 %.2f)\n', ...
        db17, s17, N17, pk17, pred17);

% ---------------- 19) 2026クリック幅は 5/48 kHz を正確に再現する ----------------
want_width19 = 5/48000*1e6;
assert(abs(K.click_width_us-want_width19) < 1e-9, ...
    '19) protocol click width %.12g us (期待 %.12g us)。', K.click_width_us, want_width19);
[~,i48_19] = phase3_click_stim('level',0.01,'n_epochs',1,'fs',48000);
[~,i96_19] = phase3_click_stim('level',0.01,'n_epochs',1,'fs',96000);
[~,i192_19] = phase3_click_stim('level',0.01,'n_epochs',1,'fs',192000);
assert(i48_19.width_samples==5 && i96_19.width_samples==10 && i192_19.width_samples==20, ...
    '19) 48/96/192 kHz の幅が %d/%d/%d samples です。', ...
    i48_19.width_samples, i96_19.width_samples, i192_19.width_samples);
assert(abs(i48_19.width_us_actual-want_width19)<1e-9 && ...
       abs(i96_19.width_us_actual-want_width19)<1e-9, ...
    '19) 量子化後の実幅がプロトコル幅と一致しません。');
assert_throws(@() phase3_click_stim('level',0.01,'n_epochs',1,'fs',44100), ...
    'phase3_click_stim:clickwidth', '19) 表現不能な3AFCクリック幅');
assert_throws(@() phase3_click_stim('level',0.01,'n_epochs',1,'fs',96000,'width_us',125), ...
    'phase3_click_stim:clickwidth', '19) プロトコル外の3AFCクリック幅');
fprintf('19) 104.1667 us クリック幅 OK  48/96/192 kHz = 5/10/20 samples\n');


% ---------------- 23) 離れた下限到達は「連続3回」ではない ----------------
% 下限で2正答して行き過ぎ、次の誤答でいったん上がることを繰り返す。
% 旧実装は離れた3回を累計して停止した。新実装では完了し、到達履歴を残す。
floor23 = containers.Map({'n'}, {0});
obs23 = @(lvl,tgt,ph) floor_cycle_observer(lvl,tgt,ph,floor23);
T23 = phase3_afc_threshold('sim_observer',obs23,'min_level_dbfs',-60, ...
    'max_level_dbfs',-20,'ascend_start_db',-60,'start_headroom_db',1, ...
    'step_start_db',2,'step_final_db',2,'step_change_at_rev',4, ...
    'n_reversals',8,'n_reversals_avg',2,'n_runs',1,'n_runs_max',1, ...
    'n_practice',0,'save',false,'verbose',false,'seed',o.seed);
assert(T23.completed && numel(T23.runs(1).edge_events)>=3, ...
    '23) 離れた下限到達で停止したか、到達履歴が残っていません。');
ceiling23=containers.Map({'n'},{0});
obs23u=@(lvl,tgt,ph) ceiling_cycle_observer(lvl,tgt,ph,ceiling23);
T23u=phase3_afc_threshold('sim_observer',obs23u,'min_level_dbfs',-60, ...
    'max_level_dbfs',-20,'ascend_start_db',-60,'start_headroom_db',10, ...
    'step_start_db',10,'step_final_db',10,'step_change_at_rev',4, ...
    'n_reversals',8,'n_reversals_avg',2,'n_runs',1,'n_runs_max',1, ...
    'n_practice',0,'save',false,'verbose',false,'seed',o.seed);
assert(T23u.completed && numel(T23u.runs(1).edge_events)>=3, ...
    '23) 離れた上限到達で停止したか、到達履歴が残っていません。');
fprintf('23) 離れた上下端到達を累計しない OK\n');

% ---------------- 24) 初回ランの下限停止でも試行履歴を保存 ----------------
outdir24 = tempname;
mkdir(outdir24);
cleanup24=onCleanup(@() rmdir(outdir24,'s'));
got24='';
try
    phase3_afc_threshold('sim_observer',@sharp_ears,'min_level_dbfs',-60, ...
        'max_level_dbfs',-20,'ascend_start_db',-59,'n_practice',0, ...
        'subject','ABORT24','ear','R','outdir',outdir24, ...
        'verbose',false,'seed',o.seed);
catch ME24
    got24=ME24.identifier;
end
saved24=dir(fullfile(outdir24,'ABORT24','*_aborted.mat'));
assert(strcmp(got24,'phase3_afc_threshold:levelrangeexhausted') && isscalar(saved24), ...
    '24) 初回ラン停止が記録されませんでした。');
S24=load(fullfile(saved24(1).folder,saved24(1).name),'T','meta');
assert(S24.T.aborted && S24.T.n_runs_done==0 && ...
    numel(S24.T.failed_run.trials)>0 && numel(S24.T.failed_run.edge_events)==3 && ...
    S24.T.failed_run.edge_events(end).consecutive_hits==3 && ...
    S24.T.limits.min_level_dbfs==-60 && ~isfield(S24.T,'threshold_dbfs'), ...
    '24) 失敗ランの試行・反転・端点履歴、下限、未確定状態が不完全です。');
fprintf('24) 初回ラン中断の試行履歴保存 OK\n');

% ---------------- 25) 通常測定の練習はクリック・ノイズ共通で6試行 ----------------
for kind25={'click','noise'}
    practice25=containers.Map({'n'},{0});
    obs25=@(lvl,tgt,ph) count_practice_observer(lvl,tgt,ph,practice25);
    T25=phase3_afc_threshold('sim_observer',obs25,'stimulus',kind25{1}, ...
        'max_level_dbfs',-20,'n_runs',1,'n_runs_max',1, ...
        'save',false,'verbose',false,'seed',o.seed);
    assert(practice25('n')==6 && T25.practice_correct==6, ...
        '25) %s の既定練習は %d 試行でした (期待6)。',kind25{1},practice25('n'));
end
fprintf('25) クリック・ノイズとも練習6試行 OK\n');

% ---------------- 26) 現行下限で開始し、旧下限未満でも閾値を確定できる ----------------
for kind26={'click','noise'}
    kind=kind26{1};
    maxlevel=-20; if strcmp(kind,'click'), maxlevel=-2; end
    first=containers.Map({'level'},{NaN});
    observer=@(lvl,tgt,ph) low_level_observer(lvl,tgt,ph,first);
    args={'stimulus',kind,'max_level_dbfs',maxlevel,'save',false, ...
        'verbose',false,'seed',o.seed,'on_range_limit','record'};
    low=phase3_afc_threshold(args{:},'sim_observer',observer);
    assert(first('level')==-130 && low.ascend_params.ascend_start_db==-130);
    assert(low.completed && low.threshold_dbfs < -115 && low.threshold_dbfs > -130);
    assert(low.limits.min_level_dbfs==-130 && low.limits.max_level_dbfs==maxlevel);
    at_floor=phase3_afc_threshold(args{:},'sim_observer',@always_hears);
    assert(strcmp(at_floor.status,'range_limited') && strcmp(at_floor.boundary,'lower'));
    assert(at_floor.boundary_dbfs==-130 && ~at_floor.completed && ~isfield(at_floor,'threshold_dbfs'));
    descending=phase3_afc_threshold(args{:},'sim_observer',@low_floor_observer);
    assert(strcmp(descending.status,'range_limited') && strcmp(descending.boundary,'lower'));
    assert(descending.boundary_dbfs==-130 && ~isfield(descending,'threshold_dbfs'));
    assert(strcmp(descending.abort_identifier,'phase3_afc_threshold:levelrangeexhausted'));
    unheard=phase3_afc_threshold(args{:},'sim_observer',@never_hears);
    assert(strcmp(unheard.status,'range_limited') && strcmp(unheard.boundary,'upper'));
    assert(unheard.boundary_dbfs==maxlevel && ~isfield(unheard,'threshold_dbfs'));
end
fprintf('26) 両刺激とも -130開始・旧下限未満の収束・上下限の記録 OK\n');

fprintf('\nphase3_afc_selftest PASS\n');
ok = true;
if nargout==0, clear ok; end
end

%% ---- local: 心理測定関数と、その上で所与の正答率を与えるレベル ----
% 3AFC の推測率 g とラプス率 lam を挟んだロジスティック。
%   P(L) = g + (1-g-lam) * 1/(1+exp(-(L-mu)/s))
% 逆を解いて「正答率 pc を与えるレベル」を返す。テスト8の真値はここから来るので、
% ステアケース側の実装とは独立に決まる (実装で実装を検証しない)。
function L = psy_level(pc, mu, s, lam, g)
F = (pc - g) / (1 - g - lam);
if F <= 0 || F >= 1
    error('phase3_afc_selftest:psy', ...
        '正答率 %.4f はこの心理測定関数の到達範囲 (%.4f..%.4f) の外です。', pc, g, 1-lam);
end
L = mu + s*log(F/(1-F));
end

function p = psy_pc(L, mu, s, lam, g)
p = g + (1 - g - lam) ./ (1 + exp(-(L - mu)/s));
end

%% ---- local: 確率的な模擬観測者 ----
% 正答なら標的区間を、誤答なら残り2区間から一様に選ぶ。3AFC の推測構造そのもの。
function resp = sim_observer(lvl, target, phase, mu, s, lam, g, audible_db, rs)
if strcmp(phase, 'ascend')
    resp = (lvl >= audible_db);
    return;
end
if rand(rs) < psy_pc(lvl, mu, s, lam, g)
    resp = target;
else
    others = setdiff(1:3, target);
    resp   = others(randi(rs, 2));
end
end

%% ---- local: 決定論的な模擬観測者 ----
% L0 以上なら必ず正答、未満なら必ず誤答。乱数に依らずステアケースの機構だけを見るため。
function resp = low_level_observer(lvl,target,phase,first)
if isnan(first('level')), first('level')=lvl; end %#ok<NASGU> containers.Map is a shared handle.
resp=det_observer(lvl,target,phase,-120);
end

function resp = low_floor_observer(lvl,target,phase)
if strcmp(phase,'ascend'), resp=lvl>=-120; else, resp=target; end
end

function resp = det_observer(lvl, target, phase, L0)
if strcmp(phase, 'ascend')
    resp = (lvl >= L0);
    return;
end
if lvl >= L0
    resp = target;
else
    others = setdiff(1:3, target);
    resp   = others(1);
end
end

%% ---- local: 途中で中断する観測者 (部分保存の検証用) ----
% 試行数を数え、quit_after を超えたら 0(中断) を返す。カウンタは containers.Map ── handle
% オブジェクトなので、MATLAB のクロージャからでも中身を書き換えられる。
function resp = quitting_observer(lvl, target, phase, L0, ctr, quit_after)
if strcmp(phase, 'ascend'), resp = (lvl >= L0); return; end
ctr('n') = ctr('n') + 1;
if ctr('n') > quit_after, resp = 0; return; end
resp = det_observer(lvl, target, phase, L0);
end

%% ---- local: 呈示回数を数える観測者 (「呈示前に落ちる」ことの検証用) ----
% 数えるだけで、応答自体は決定論的観測者に委ねる。
function resp = counting_observer(lvl, target, phase, L0, ctr)
ctr('n') = ctr('n') + 1;
resp = det_observer(lvl, target, phase, L0);
end

%% ---- local: 常に聞こえる観測者 (上昇法の床ガードの検証用) ----
% 上昇法の一発目から聞こえてしまう状態を作る。
function resp = always_hears(~, target, phase)
if strcmp(phase, 'ascend'), resp = true; else, resp = target; end
end

%% ---- local: 上昇法では聞こえるが本試行では全て外す観測者 (上端ガードの検証用) ----
% 上昇法を通過させてからステアケースを上へ張り付かせるため、phase だけで振る舞いを変える。
function resp = deaf_but_responds(lvl, target, phase)
if strcmp(phase, 'ascend'), resp = (lvl >= -50); return; end   % 上昇法は通す
others = setdiff(1:3, target);
resp   = others(1);                     % 本試行は常に誤答 → 常に上昇
end

%% ---- local: どんなに低くても当てる観測者 (下端ガードの検証用) ----
function resp = sharp_ears(lvl, target, phase)
if strcmp(phase, 'ascend'), resp = (lvl >= -50); return; end   % 上昇法は通す
resp = target;                          % 本試行は常に正答 → 常に下降
end

function resp = floor_cycle_observer(lvl, target, phase, ctr)
if strcmp(phase,'ascend'), resp = (lvl>=-59); return; end
if strcmp(phase,'practice') || lvl>-60, resp=target; return; end
ctr('n')=ctr('n')+1;
if mod(ctr('n'),3)==0, resp=mod(target,3)+1;
else, resp=target;
end
end

function resp = count_practice_observer(lvl,target,phase,ctr)
if strcmp(phase,'ascend'), resp=(lvl>=-50); return; end
if strcmp(phase,'practice'), ctr('n')=ctr('n')+1; end
resp=det_observer(lvl,target,phase,-50);
end

function resp = ceiling_cycle_observer(lvl,target,phase,ctr)
if strcmp(phase,'ascend'), resp=(lvl>=-50); return; end
if strcmp(phase,'practice'), resp=target; return; end
if lvl>=-20
    ctr('n')=ctr('n')+1;
    if mod(ctr('n'),3)~=1, resp=target; return; end
end
resp=mod(target,3)+1;
end

%% ---- local: 契約違反の応答を返す観測者 (sim_observer 契約の検証用) ----
% 1..3 でも 0 でもない値。黙って受け取ると、ステアケースが「正答でも誤答でもない」応答で
% 進んでしまう。
function resp = bad_sim(lvl, ~, phase)
if strcmp(phase, 'ascend'), resp = (lvl >= -50); return; end   % 上昇法は通す
resp = 99;                                                     % 本試行で契約違反
end

%% ---- local: 決して聞こえない観測者 (上限到達ガードの検証用) ----
function resp = never_hears(~, target, phase)
if strcmp(phase, 'ascend'), resp = false; else, resp = mod(target, 3) + 1; end
end

function assert_throws(action, expectedId, description)
try
    action();
catch exception
    assert(strcmp(exception.identifier, expectedId), ...
        '%s: expected %s, got %s.', description, expectedId, exception.identifier);
    return
end
error('phase3_afc_selftest:missingError', '%s: expected %s.', description, expectedId);
end
