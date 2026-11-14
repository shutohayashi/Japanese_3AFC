function T = phase3_afc_threshold(varargin)
%PHASE3_AFC_THRESHOLD Measure detection thresholds for click trains or band-limited noise.
% Set max_level_dbfs for the configured audio chain. Use dry_run to inspect a
% trial or sim_observer for a silent simulation. With save enabled, provide
% subject, ear and an existing outdir. See README.md for setup and controls.
silence_system_beep();   % 理由は silence_system_beep.m（エラー音が参加者の耳に届く）

K = phase3_protocol_const();

p = inputParser;
% --- 同定・保存 ---
p.addParameter('subject', '');            % 被験者ID (保存時は必須)
p.addParameter('ear', '');                % 'L'|'R' 記録耳 (保存時は必須)
p.addParameter('operator', '');
p.addParameter('notes', '');
p.addParameter('outdir', 'data');
p.addParameter('test', false);
p.addParameter('save', true);             % false で成功結果を保存しない
p.addParameter('abort_outdir', '');   % Optional directory for incomplete results.
% --- 安全 ---
p.addParameter('max_level_dbfs', []);     % 必須。既定値なし (理由は check_limits のエラー文)
p.addParameter('min_level_dbfs', K.min_level_dbfs);
p.addParameter('on_range_limit', 'error'); % 'record': return diagnostic, never a threshold
p.addParameter('on_interrupt', 'error'); % 'record': known cancellation/audio failures only
% --- 課題パラメータ (既定はすべて phase3_protocol_const) ---
p.addParameter('n_practice',        K.n_practice);
p.addParameter('n_runs',            K.n_runs);
p.addParameter('n_runs_max',        K.n_runs_max);
p.addParameter('run_tol_db',        K.run_tol_db);
p.addParameter('n_reversals',       K.n_reversals);
p.addParameter('n_reversals_avg',   K.n_reversals_avg);
p.addParameter('step_start_db',     K.step_start_db);
p.addParameter('step_final_db',     K.step_final_db);
p.addParameter('step_change_at_rev',K.step_change_at_rev);
p.addParameter('ascend_start_db',   []);   % []=min_level_dbfs (下の解決を参照)
p.addParameter('ascend_step_db',    K.ascend_step_db);
p.addParameter('start_headroom_db', K.start_headroom_db);
p.addParameter('max_trials',        200); % 暴走ガード (run_staircase の理由参照)
% --- 刺激 ---
p.addParameter('stimulus', 'noise');      % 'noise' | 'click'
p.addParameter('fs',       K.fs_hz);
p.addParameter('band',     K.noise_band_hz);   % noise のみ
p.addParameter('burst_ms', K.burst_ms);        % noise のみ (click は列長が区間長を決める)
p.addParameter('isi_ms',   K.isi_ms);
p.addParameter('ramp_ms',  K.ramp_ms);         % noise のみ (click にランプは掛けない)
p.addParameter('n_epochs', K.click_burst_epochs);  % click のみ
p.addParameter('seed', 'shuffle');        % 標的区間とノイズの乱数種
% --- 実行モード ---
p.addParameter('dry_run', false);
p.addParameter('sim_observer', []);
p.addParameter('verbose', true);      % false で進行表示を止める (selftest が多数回駆動するため)
% --- オーディオ ---
p.addParameter('driver', 'ASIO');         % Windows専用 ('ASIO'|'DirectSound'|'WASAPI')
p.addParameter('dev_id', '');             % ''=出力機器が1台だけなら自動選択
p.addParameter('nbuf', K.audio_frame_samples);
p.addParameter('warmup_frames', K.audio_prime_frames); % 無音中の連続した欠落ゼロ確認数
p.addParameter('feedback_ms', 700);       % 正誤フィードバックを表示したまま止める時間 [ms]。
                                          % 試行間間隔も兼ねる (present_human 末尾の理由)
p.parse(varargin{:});
o = p.Results; o.test=phase3_test_flag(o.test);
o.audio=struct('device','','backend','audiostreamer','driver',char(o.driver),'frame_samples',o.nbuf, ...
    'cancel_source','', ...
    'asio_buffer_samples',[],'asio_buffer_source','manual confirmation required', ...
    'retry_count',0,'underrun_samples',0,'prime_underrun_samples',0,'attempts',{{}});
validateattributes(o.nbuf,{'numeric'},{'scalar','integer','positive','finite'});
validateattributes(o.warmup_frames,{'numeric'},{'scalar','integer','positive','<=',K.audio_prime_max_frames});
if ~ismember(char(o.on_interrupt),{'error','record'})
    error('phase3_afc_threshold:interruptpolicy','on_interrupt must be error or record.');
end
if ~ismember(char(o.on_range_limit),{'error','record'})
    error('phase3_afc_threshold:rangepolicy','on_range_limit must be error or record.');
end

sim = o.sim_observer;
if ~isempty(sim) && ~isa(sim,'function_handle')
    error('phase3_afc_threshold:simobserver', ...
        "'sim_observer' は関数ハンドルである必要があります (指定: %s)。", class(sim));
end

% Begin at the search floor unless a starting level was supplied.
if isempty(o.ascend_start_db), o.ascend_start_db = o.min_level_dbfs; end

% 刺激種の解決。以降の測定ロジックは「1区間を作る関数」と「その長さ」しか知らない ──
% ノイズとクリックの違いはここ1箇所に閉じる。pstate と同じ流儀で、分岐を端に寄せておけば
% selftest が駆動する制御フローが本番と同一のままになる。
stim = resolve_stimulus(o, K);

check_limits(o, stim);

fs     = o.fs;
% 区間長は stim が権威で、以降の関数へは stim ごと渡す (ここで控えを持たない)。
nisi   = round(o.isi_ms  *1e-3*fs);

% ---- 乱数: 標的区間とノイズで別ストリーム ----
% 同じストリームから引くと、標的区間の抽選がノイズ生成のサンプル消費量に依存してしまい、
% seed を固定しても刺激設計が再現しなくなる。
if ischar(o.seed) || isstring(o.seed)
    rs_target  = RandStream('twister','Seed',char(o.seed));
    noise_seed = 'shuffle';
else
    rs_target  = RandStream('twister','Seed', o.seed);
    noise_seed = o.seed + 1;
end

vb = o.verbose;
vprintf(vb, '=== 3AFC 閾値測定 (%s) ===\n', stim.kind);
vprintf(vb, ' %s / 区間 %.0f ms / 区間間 %g ms / fs %g Hz\n', ...
        stim.describe, stim.nburst/fs*1e3, o.isi_ms, fs);
vprintf(vb, ' 上限 %.1f dB FS  規則 %s  反転%d(末尾%d平均)\n', ...
        o.max_level_dbfs, K.rule, o.n_reversals, o.n_reversals_avg);

% ---- dry_run: 1試行分を組み立てて寸法を検証し、音を出さずに返す ----
if o.dry_run
    T = verify_trial_build(nisi, o, K, stim, noise_seed); T.test=o.test;
    return;
end

% ---- 保存先とメタの検査は「呈示を始める前」に ----
% 落ちるなら 0 秒目で落ちるべき (理由は check_save_dest 側)。dry_run の後ろに置いてあるのは、
% dry_run が保存を行わないため ── そこで subject/ear を要求すると、音を出さない組立確認に
% 被験者情報を強いることになる。
if o.save
    check_save_dest(o);
end
if ~isempty(o.abort_outdir)
    if ~isfolder(o.abort_outdir) || isempty(o.subject) || ~ismember(upper(char(o.ear)),{'L','R'})
        error('phase3_afc_threshold:abortdest', ...
            '中断記録の保存先・参加者コード・測定耳を呈示前に確認してください。');
    end
end

% ---- 呈示手段を1つのハンドルに畳む (以降のロジックは人か模擬かを知らない) ----
if isempty(sim)
    [adw, ui] = open_hardware(o, fs);
    guard   = onCleanup(@() release_all(adw, ui));   % 例外時も解放
    o.audio.device=char(adw.Player);
    o.audio.cancel_source=ui.fig.UserData.cancel_source;
    ui.fig.UserData.audio=o.audio;
    pstate  = stim.init(noise_seed);
    present = @(ps, lvl, target, phase) present_human(ui, adw, ps, lvl, target, phase, ...
                                                      nisi, o, K, stim);
else
    pstate  = [];
    present = @(ps, lvl, target, phase) present_sim(sim, ps, lvl, target, phase);
end

% 呈示開始後のどの段階で止まっても、完了分と失敗ランを記録する。
runs = struct('threshold_dbfs',{},'reversals_db',{},'trials',{},'n_trials',{},'edge_events',{});
r = 0;
failed_run = [];
heard_db = [];
start_db = [];
n_prac_ok = 0;
abort_phase = 'ascend';
try
    % ---- 1. 手動上昇法 ----
    [heard_db, pstate] = ascend(present, pstate, o);
    start_db = min(heard_db + o.start_headroom_db, o.max_level_dbfs);
    vprintf(vb, '  手動上昇: 聞こえた点 %.1f dB FS → 開始 %.1f dB FS\n', heard_db, start_db);

    % ---- 2. 練習 (閾値には算入しない) ----
    abort_phase = 'practice';
    for i = 1:o.n_practice
        target = randi(rs_target, K.n_intervals);
        [resp, pstate] = present(pstate, start_db, target, 'practice');
        n_prac_ok = n_prac_ok + (resp == target);
    end
    vprintf(vb, '  練習 %d 試行 正答 %d\n', o.n_practice, n_prac_ok);

    % ---- 3. 本ラン ----
    % 中断時は初回ラン中でも記録済みの試行を aborted 付きで保存してから送出する。
    % 規定ラン数に達していない値は確定させない。
    abort_phase = 'staircase';
    while true
        r = r + 1;
        vprintf(vb, '  --- ラン %d ---\n', r);
        [th, rev, trials, pstate, edge_events, failure] = run_staircase(present, pstate, rs_target, start_db, o, K);
        if ~isempty(failure)
            failed_run = struct('run_index',r,'trials',trials,'reversals_db',rev, ...
                'edge_events',edge_events,'n_trials',numel(trials));
            rethrow(failure);
        end
        runs(r) = struct('threshold_dbfs', th, 'reversals_db', rev, ...
                         'trials', trials, 'n_trials', numel(trials), 'edge_events', edge_events);
        vprintf(vb, '  ラン %d 閾値 %.2f dB FS (%d 試行, 反転 %s)\n', ...
                r, th, numel(trials), mat2str(round(rev,1)));
        if r < o.n_runs, continue; end
        if r >= o.n_runs_max, break; end
        [~, ~, spread_ok] = phase3_afc_combine([runs.threshold_dbfs], o.run_tol_db);
        if spread_ok, break; end
        vprintf(vb, '  ラン間差が %.1f dB を超過 → 追加ランを実施\n', o.run_tol_db);
    end
catch ME
    if isempty(sim)&&isgraphics(ui.fig), o.audio=ui.fig.UserData.audio; end
    if strcmp(o.on_interrupt,'record')&&phase3_afc_interruption(ME.identifier)
        T=partial_result(runs,failed_run,heard_db,start_db,n_prac_ok,abort_phase,ME,o,K);
        T.status='interrupted'; T.outfile='';
        if o.save||~isempty(o.abort_outdir)
            T.outfile=save_partial(T,o);
        end
        return
    end
    range_ids={'phase3_afc_threshold:ascendfloor','phase3_afc_threshold:ascendbelowfloor', ...
        'phase3_afc_threshold:ascendceiling','phase3_afc_threshold:levelrangeexhausted'};
    if strcmp(o.on_range_limit,'record')&&ismember(ME.identifier,range_ids)
        T=partial_result(runs,failed_run,heard_db,start_db,n_prac_ok,abort_phase,ME,o,K);
        T.aborted=false; T.status='range_limited'; T.boundary='lower';
        if strcmp(ME.identifier,'phase3_afc_threshold:ascendceiling')
            T.boundary='upper';
        elseif strcmp(ME.identifier,'phase3_afc_threshold:levelrangeexhausted')&& ...
                ~isempty(failed_run)&&~isempty(failed_run.edge_events)
            if strcmp(failed_run.edge_events(end).edge,'ceiling'), T.boundary='upper'; end
        end
        if strcmp(T.boundary,'lower'), T.boundary_dbfs=o.min_level_dbfs;
        else, T.boundary_dbfs=o.max_level_dbfs; end
        T.outfile='';
        if o.save, T.outfile=save_result(T,o,'_range_limited',o.abort_outdir); end
        return
    end
    if o.save || ~isempty(o.abort_outdir)
        try
            P=partial_result(runs,failed_run,heard_db,start_db,n_prac_ok,abort_phase,ME,o,K);
            save_partial(P,o);
        catch saveErr
            warning('phase3_afc_threshold:partialsavefatal', ...
                '中断記録の作成にも失敗しました (%s)。元の測定エラーを再送出します。', saveErr.message);
        end
    end
    rethrow(ME);
end

% ---- 4. 閾値の確定 ----
[threshold_db, used] = phase3_afc_combine([runs.threshold_dbfs], o.run_tol_db);

vprintf(vb, '\n%s 閾値 %.2f dB FS (ラン %s の平均)\n', stim.kind, threshold_db, mat2str(used));
T = struct(); T.test=o.test;
T.subject          = char(o.subject);
T.ear              = upper(char(o.ear));
T.stimulus         = stim.kind;
T.threshold_dbfs   = threshold_db;
T.runs_used        = used;
T.runs             = runs;
T.n_runs_done      = numel(runs);
T.ascend_heard_db  = heard_db;
T.start_db         = start_db;
T.practice_correct = n_prac_ok;
T.practice_trials  = o.n_practice;
T.rule             = K.rule;
T.pc_target        = K.pc_target;
% 記録するのは「実際に使われた seed」。o.seed が 'shuffle' のとき、その文字列を保存しても
% ノイズも標的区間列も二度と再現できない ── 再現性の記録のつもりで再現できないことを記録
% している状態になる。RandStream.Seed は解決後の数値。
if isstruct(pstate) && isfield(pstate,'seed'), noise_seed_used = pstate.seed;
else,                                          noise_seed_used = []; end   % 模擬経路は音を出さない
T.stim_params      = struct('kind',stim.kind,'detail',stim.params, ...
                            'fs_hz',fs,'interval_ms',stim.nburst/fs*1e3, ...
                            'isi_ms',o.isi_ms,'n_intervals',K.n_intervals, ...
                            'seed_requested',o.seed, ...
                            'seed_target',rs_target.Seed, ...
                            'seed_noise',noise_seed_used, ...
                            'inverse_filter','none (ER-3C transfer function not compensated)');
T.limits           = struct('max_level_dbfs',o.max_level_dbfs,'min_level_dbfs',o.min_level_dbfs);
% Record the starting point so the search can be reproduced.
T.ascend_params    = struct('ascend_start_db',o.ascend_start_db, ...
                            'ascend_step_db',o.ascend_step_db, ...
                            'start_headroom_db',o.start_headroom_db);
T.simulated        = ~isempty(sim);
T.completed        = true;
T.status           = 'complete';
if isempty(sim), o.audio=ui.fig.UserData.audio; end
T.audio            = o.audio;

% 保存先は測定開始前に検査してあるが、ディスク満杯・権限・同期フォルダのロックなど、そこを
% 通っても保存が失敗することはある。そのときに例外を送出すると、完成した測定ごと失われる
% (返り値が返らない)。出所メモを残せなかったという理由で測定データを捨てるのは取り違えなので、
% 警告に落として T は返す。呼び出し側は返った T を手で save できる。
% code_version.m / host_name.m が例外を投げないのと同じ判断。
T.outfile = '';
if o.save
    try
        T.outfile = save_result(T, o);
    catch saveErr
        % 「返り値に入っています」では足りない: nargout==0 で呼ばれると下で T は clear される。
        % 測定を失わせない確実な方法は、必ず書ける場所へ落として場所を名前で伝えること。
        rescue = rescue_save(T, 'result');
        warning('phase3_afc_threshold:savefailed', ...
            ['測定は完了しましたが保存に失敗しました (%s: %s)。\n' ...
             '結果を退避しました: %s\n' ...
             '保存先を直したうえで、このファイルを本来の場所へ移してください。'], ...
            saveErr.identifier, saveErr.message, rescue);
    end
end
if nargout==0, clear T; end
end

%% ---- 保存先と被験者メタの検査 ----
% Check before presentation and again before writing the result.
function check_save_dest(o)
if isempty(o.subject) || isempty(o.ear)
    error('phase3_afc_threshold:meta', ...
        'Saving requires a subject code and ear (L or R).');
end
if ~ismember(upper(char(o.ear)), {'L','R'})
    error('phase3_afc_threshold:ear', "ear は 'L' か 'R' です (指定: '%s')。", char(o.ear));
end
require_data_root(o.outdir, 'phase3_afc_threshold:noroot');
end

%% ---- 引数の相互矛盾を測定開始前に潰す ----
function check_limits(o, stim)
% 安全上限に既定値を置かない: 既定値があると「上限を指定し忘れたまま走る」経路ができ、
% しかもそれが最も起きやすい失敗。呈示レベルの上限は測定条件そのものなので毎回明示させる。
if isempty(o.max_level_dbfs)
    error('phase3_afc_threshold:maxlevel', ...
        ['''max_level_dbfs'' (呈示レベル上限 [dB FS]) は必須です。既定値はありません。\n' ...
         '音響較正が未取得のためコードは dB FS と実 SPL の対応を知り得ず、上限は' ...
         '実機で安全を確認した値を毎回渡す必要があります。']);
end
if ~isscalar(o.max_level_dbfs) || ~isnumeric(o.max_level_dbfs) || ...
   ~isreal(o.max_level_dbfs)   || ~isfinite(o.max_level_dbfs)
    error('phase3_afc_threshold:maxlevel', "'max_level_dbfs' は有限の実数スカラです。");
end
% Noise levels are RMS-referenced, so leave headroom for peaks. Click levels
% are peak-referenced and can be compared directly with digital full scale.
ceil_dbfs = -stim.crest_db;
if o.max_level_dbfs > ceil_dbfs
    error('phase3_afc_threshold:maxlevel', ...
        ['''max_level_dbfs'' が %.1f dB FS ですが、刺激 ''%s'' の上限は %.1f dB FS です' ...
         '(クレスト余裕 %.0f dB)。これを超えるとピークがフルスケールを越えてクリップし、' ...
         '歪んだ刺激に対する閾値を測ることになります。'], ...
        o.max_level_dbfs, stim.kind, ceil_dbfs, stim.crest_db);
end
if o.min_level_dbfs >= o.max_level_dbfs
    error('phase3_afc_threshold:levelrange', ...
        'min_level_dbfs (%.1f) が max_level_dbfs (%.1f) 以上です。', ...
        o.min_level_dbfs, o.max_level_dbfs);
end
if o.ascend_start_db > o.max_level_dbfs
    error('phase3_afc_threshold:ascendstart', ...
        '手動上昇の開始 %.1f dB FS が上限 %.1f dB FS を超えています。', ...
        o.ascend_start_db, o.max_level_dbfs);
end
% 下限より下から始めると、ステアケースが降りられない領域から探索することになる。
if o.ascend_start_db < o.min_level_dbfs
    error('phase3_afc_threshold:ascendbelowfloor', ...
        '手動上昇の開始 %.1f dB FS が下限 %.1f dB FS を下回っています。', ...
        o.ascend_start_db, o.min_level_dbfs);
end
% 反転数は上下どちらの端も検査する。下端を放置すると n_reversals_avg=0 で
% rev(end-0+1:end) が空になり、mean([]) = NaN が phase3_afc_combine まで流れてから
% 「有限の数値ベクトルが必要」と別モジュール名で落ちる ── 操作者が見る先が間違う。
if o.n_reversals_avg < 1 || o.n_reversals < 1
    error('phase3_afc_threshold:reversals', ...
        '反転数は 1 以上です (n_reversals=%d, n_reversals_avg=%d)。', ...
        o.n_reversals, o.n_reversals_avg);
end
if o.n_reversals_avg > o.n_reversals
    error('phase3_afc_threshold:reversals', ...
        '平均に使う反転数 %d が総反転数 %d を超えています。', o.n_reversals_avg, o.n_reversals);
end
% 0 だとステップ幅の切替が黙って無効化され、粗いステップのまま最後まで走る。
if o.step_change_at_rev < 1 || o.step_change_at_rev > o.n_reversals
    error('phase3_afc_threshold:stepchange', ...
        'step_change_at_rev は 1..n_reversals (=%d) の範囲です (指定 %d)。', ...
        o.n_reversals, o.step_change_at_rev);
end
if o.ascend_step_db <= 0 || o.step_start_db <= 0 || o.step_final_db <= 0
    error('phase3_afc_threshold:step', 'ステップ幅は正である必要があります。');
end
% n_runs は「最低実施ラン数」、n_runs_max は「上限」。ラン増加の判定は n_runs の充足が
% 先に来るので、n_runs > n_runs_max だと上限を素通りして n_runs 回まで走ってしまう。
if o.n_runs < 1 || o.n_runs > o.n_runs_max
    error('phase3_afc_threshold:nruns', ...
        'n_runs は 1..n_runs_max (=%d) の範囲です (指定 %d)。', o.n_runs_max, o.n_runs);
end
end

%% ======================= 測定ロジック (呈示手段に依存しない) =======================

%% ---- 手動上昇法: 十分低いレベルから上げ、聞こえた点を返す ----
% 開始レベルを被験者ごとに実測することが、大音量呈示を構造的に防ぐ唯一の手段。固定値から
% 下降させる方式だと、外耳道容積・挿入深さの個人差(数 dB)がそのまま「最初の一発が想定より
% 大きい」に化ける。
function [heard_db, pstate] = ascend(present, pstate, o)
lvl   = o.ascend_start_db;
first = true;                 % 浮動小数の等値比較ではなく明示フラグで「一発目」を表す
while true
    [heard, pstate] = present(pstate, lvl, [], 'ascend');
    if heard
        % A hit on the first step does not bracket the onset of audibility.
        if first
            error('phase3_afc_threshold:ascendfloor', ...
                ['手動上昇の開始レベル %.1f dB FS が既に聞こえています。「聞こえない」' ...
                 'レベルを観測できていないので、これは聞こえ始める点の推定になりません。\n' ...
                '閾値が呈示範囲 (%.1f〜%.1f dB FS) の下端より下かは、この結果だけでは' ...
                '確定できません。装着・出力経路と刺激の可聴性を実機で確認してください。' ...
                '測定範囲や出力設定を変える前に、その設定での物理出力を検証してください。'], ...
                o.ascend_start_db, o.min_level_dbfs, o.max_level_dbfs);
        end
        heard_db = lvl;
        return;
    end
    first = false;
    lvl = lvl + o.ascend_step_db;
    if lvl > o.max_level_dbfs
        error('phase3_afc_threshold:ascendceiling', ...
            ['上限 %.1f dB FS まで上げても聞こえの合図がありません。装着・配線・出力経路' ...
             '(TotalMix のミュート/フェーダ、デバイス選択) を確認してください。' ...
             '上限自体を上げる場合は実機で安全を確認してから。'], o.max_level_dbfs);
    end
end
end

%% ---- 2-down-1-up ステアケース (1ラン) ----
function [th, rev, trials, pstate, edge_events, failure] = run_staircase(present, pstate, rs_target, start_db, o, K)
lvl       = start_db;
step      = o.step_start_db;
n_correct = 0;          % 連続正答数 (2で下降)
last_dir  = 0;          % 直前の移動方向 (+1 上昇 / -1 下降 / 0 未移動)
rev       = [];
trials    = struct('level_db',{},'target',{},'response',{},'correct',{},'step_db',{});
edge_events = struct('trial_index',{},'edge',{},'level_db',{},'attempted_db',{},'step_db',{},'consecutive_hits',{});
n_ceiling = 0;          % 上限に貼り付いた回数
n_floor   = 0;          % 下限に貼り付いた回数 (上限と対称に扱う)
failure   = [];

try
while numel(rev) < o.n_reversals
    if numel(trials) >= o.max_trials
        % 収束しないまま延々続けない。被験者の拘束時間が読めなくなるうえ、収束しないこと
        % 自体が「装着か課題理解に問題がある」という所見なので、静かに続けるより止める。
        error('phase3_afc_threshold:maxtrials', ...
            ['%d 試行で反転 %d/%d にしか到達していません。課題の理解、装着、' ...
             'レベル範囲 (%.1f〜%.1f dB FS) を確認してください。'], ...
            numel(trials), numel(rev), o.n_reversals, o.min_level_dbfs, o.max_level_dbfs);
    end

    target = randi(rs_target, K.n_intervals);
    [resp, pstate] = present(pstate, lvl, target, 'staircase');
    ok = (resp == target);
    trials(end+1) = struct('level_db',lvl,'target',target,'response',resp, ...
                           'correct',ok,'step_db',step);  %#ok<AGROW>

    % 2-down-1-up: 2連続正答で下降、1誤答で上昇
    if ok
        n_correct = n_correct + 1;
        if n_correct >= 2, dir = -1; n_correct = 0; else, dir = 0; end
    else
        dir = +1; n_correct = 0;
    end

    if dir ~= 0
        % 反転は「向きが変わった時点のレベル」で記録する (移動前の値)。これが慣用の
        % turnaround point で、末尾平均が閾値推定になるのはこの定義においてである。
        if last_dir ~= 0 && dir ~= last_dir
            rev(end+1) = lvl;  %#ok<AGROW>
            if numel(rev) == o.step_change_at_rev, step = o.step_final_db; end
        end
        last_dir = dir;
        % Stop after repeated boundary hits to avoid reporting the floor or ceiling as convergence.
        attempted = lvl + dir*step;
        new_lvl = attempted;
        if attempted > o.max_level_dbfs
            new_lvl   = o.max_level_dbfs;
            n_ceiling = n_ceiling + 1;
            n_floor = 0;
            edge_events(end+1) = struct('trial_index',numel(trials),'edge','ceiling', ...
                'level_db',lvl,'attempted_db',attempted,'step_db',step, ...
                'consecutive_hits',n_ceiling); %#ok<AGROW>
            edge_fail(n_ceiling, '上限', o.max_level_dbfs, o);
        elseif attempted < o.min_level_dbfs
            new_lvl = o.min_level_dbfs;
            n_floor = n_floor + 1;
            n_ceiling = 0;
            edge_events(end+1) = struct('trial_index',numel(trials),'edge','floor', ...
                'level_db',lvl,'attempted_db',attempted,'step_db',step, ...
                'consecutive_hits',n_floor); %#ok<AGROW>
            edge_fail(n_floor, '下限', o.min_level_dbfs, o);
        else
            n_ceiling = 0;
            n_floor = 0;
        end
        lvl = new_lvl;
    end
end
catch ME
    failure = ME;
    th = [];
    return;
end

th = mean(rev(end-o.n_reversals_avg+1:end));
end

%% ---- レベル範囲の端に貼り付いたら止める (上限・下限で共通) ----
% 端を離れず3回続けて越えようとしたら停止する。分散した行き過ぎを累計しない。
function edge_fail(n_hit, edge_name, edge_db, o)
if n_hit < 3, return; end
error('phase3_afc_threshold:levelrangeexhausted', ...
    ['%s %.1f dB FS を連続3回越えようとしたため、このランを停止しました。' ...
     '今回の試行だけでは閾値が範囲 (%.1f〜%.1f dB FS) の外と断定できません。\n' ...
     '中断記録がある場合は応答・反転・端点イベントを確認し、装着、出力経路、刺激の可聴性を' ...
     '実機で点検してから再測定してください。'], ...
    edge_name, edge_db, o.min_level_dbfs, o.max_level_dbfs);
end

% ラン間のばらつき判定と閾値の合成は phase3_afc_combine.m へ切り出した
% (判定規則そのものを、乱数と課題モデルに依存せず単体で検証できるようにするため)。

%% ======================= 刺激の組立 =======================

%% ---- 1試行分のセグメント列 (区間 n_int 個 + 区間間 n_int-1 個) ----
% 標的区間にだけノイズを置き、他は同じ長さの無音。dry_run と実機経路の両方がこれを使う
% (2つ書くと、片方だけ直したときに検証したものと呈示するものがずれる)。
function [segs, nstate] = build_trial(target, lvl, n_int, nisi, o, nstate, stim)
% 安全上限の最終防衛線。上限は手動上昇・練習・ステアケースの3経路で個別に守られているが、
% 「音になる直前」で1度だけ確かめておけば、将来どの経路が増えても上限を回り込めない。
% ここを通らずに音が出る経路は存在しない (dry_run も実機呈示もこの関数を通る)。
if lvl > o.max_level_dbfs
    error('phase3_afc_threshold:overceiling', ...
        ['呈示レベル %.2f dB FS が上限 %.2f dB FS を超えました。測定ロジックの' ...
         'どこかが上限を回り込んでいます (これは本来到達しない防衛的検査です)。'], ...
        lvl, o.max_level_dbfs);
end
amp    = phase3_level_map('db2amp', lvl);
nburst = stim.nburst;      % 呼び出し側と二重に持たない: 長さの権威は刺激そのもの
segs   = cell(1, 2*n_int - 1);
for k = 1:n_int
    if k == target
        [b, nstate] = stim.make(amp, nstate);
        if numel(b) ~= nburst
            % 呈示器が約束と違う長さを返すと、区間長と区間間隔が静かにずれる。
            error('phase3_afc_threshold:burstlen', ...
                '刺激 ''%s'' が %d サンプルを返しました (期待 %d)。', stim.kind, numel(b), nburst);
        end
    else
        b = zeros(nburst, 1);
    end
    segs{2*k-1} = b;
    if k < n_int, segs{2*k} = zeros(nisi, 1); end
end
end

%% ---- 刺激種の解決: 「1区間を作る関数」と「その長さ」に畳む ----
% 測定ロジック (ascend / run_staircase / do_trial / build_trial) は刺激の中身を知らない。
% ノイズとクリックの違いは stim.make の中だけにあり、レベルの単位の違い (RMS か ピークか)
% と、それに伴うクレスト余裕の違いも、ここで一緒に決まる。
function stim = resolve_stimulus(o, K)
switch lower(char(o.stimulus))
    case 'noise'
        nb   = round(o.burst_ms*1e-3*o.fs);
        stim          = struct();
        stim.kind     = 'noise';
        stim.nburst   = nb;
        stim.crest_db = K.crest_headroom_db.noise;    % レベルは RMS、ピークはその分だけ上
        stim.label    = 'ノイズ';
        stim.describe = sprintf('帯域 %g-%g Hz / ランプ %g ms', o.band(1), o.band(2), o.ramp_ms);
        stim.params   = struct('band_hz',o.band,'burst_ms',o.burst_ms,'ramp_ms',o.ramp_ms);
        % ストリームは1本を引き継ぐ。試行ごとに作り直すと sos と白色雑音ゲインの算出
        % (65536点 freqz) を毎回やり直すことになる。500 ms 離れたバースト同士は、同じ
        % ストリームから引いても独立標本である。
        stim.init     = @(seed) phase3_noise_stim_init(o, seed);
        stim.make     = @(amp, st) phase3_noise_stim('n', nb, 'level_rms', amp, 'state', st, ...
                                        'fs', o.fs, 'band', o.band, ...
                                        'ramp_ms', o.ramp_ms, 'ramp_edges','both');
    case 'click'
        [~, ci] = phase3_click_stim('level', 0, 'n_epochs', o.n_epochs, 'fs', o.fs);
        stim          = struct();
        stim.kind     = 'click';
        stim.nburst   = ci.n_samples;
        stim.crest_db = K.crest_headroom_db.click;    % レベル = ピーク。取る余裕は無い
        stim.label    = 'クリック音';
        stim.describe = sprintf('%dエポック列 %.1f/s / ランプなし', ci.n_epochs, ci.rate_hz);
        % ci は寸法を知るための level=0 の試作から来るので、level_peak をそのまま残すと
        % 「標的区間は無音だった」と読める記録になる。そもそもレベルは試行ごとに動くので、
        % 刺激パラメータとして保存すべき値ではない。ノイズ側と同じく明示的に組み直す。
        stim.params   = struct('n_epochs',ci.n_epochs,'epoch_samples',ci.epoch_samples, ...
                               'n_samples',ci.n_samples,'duration_ms',ci.duration_ms, ...
                               'iti_ms',ci.iti_ms,'width_us',ci.width_us, ...
                               'width_samples',ci.width_samples, ...
                               'width_us_actual',ci.width_us_actual, ...
                               'rate_hz',ci.rate_hz,'first_polarity',ci.first_polarity);
        % クリックは決定論的なので状態を持たない。state は素通しする (測定ロジックが
        % pstate を「中身を見ずに持ち回す」契約をここでも守る)。
        stim.init     = @(~) [];
        stim.make     = @(amp, st) deal(phase3_click_stim('level', amp, ...
                                        'n_epochs', o.n_epochs, 'fs', o.fs), st);
    otherwise
        error('phase3_afc_threshold:stimulus', ...
            "'stimulus' は 'noise' か 'click' です (指定: '%s')。", char(o.stimulus));
end
end

%% ---- ノイズストリームを1本作る ----
function nstate = phase3_noise_stim_init(o, noise_seed)
[~, nstate] = phase3_noise_stim('n', 1, 'level_rms', 1e-6, 'fs', o.fs, 'band', o.band, ...
                                'ramp_ms', 0, 'ramp_edges','none', 'seed', noise_seed);
end

%% ---- dry_run: 組立と寸法だけ検証する ----
function T = verify_trial_build(nisi, o, K, stim, noise_seed)
nstate = stim.init(noise_seed);
segs   = build_trial(2, o.max_level_dbfs, K.n_intervals, nisi, o, nstate, stim);
nburst = stim.nburst;
ntot   = sum(cellfun(@numel, segs));
assert(numel(segs) == 2*K.n_intervals - 1, ...
    'dry_run: セグメント数が %d です (期待 %d = 区間%d + 区間間%d)。', ...
    numel(segs), 2*K.n_intervals-1, K.n_intervals, K.n_intervals-1);
assert(ntot == K.n_intervals*nburst + (K.n_intervals-1)*nisi, ...
    'dry_run: 総サンプル数が %d です (期待 %d)。', ...
    ntot, K.n_intervals*nburst + (K.n_intervals-1)*nisi);
vprintf(o.verbose, ['dry_run: 1試行の組立を検証 (音は出しません)。%d セグメント・計 %d サンプル ' ...
         '(%.2f 秒)、%d サンプル/フレームで約 %.0f フレーム\n'], ...
        numel(segs), ntot, ntot/o.fs, o.nbuf, ceil(ntot/o.nbuf));
T = struct('dry_run', true, 'stimulus', stim.kind, ...
           'n_segments', numel(segs), 'n_samples', ntot, ...
           'trial_s', ntot/o.fs, 'fs', o.fs, 'nburst', nburst, 'nisi', nisi);
end

%% ======================= 呈示手段 =======================

%% ---- 模擬観測者 (pstate は素通し) ----
function [resp, pstate] = present_sim(sim, pstate, lvl, target, phase)
resp = sim(lvl, target, phase);
if strcmp(phase, 'ascend')
    if ~(islogical(resp) || (isnumeric(resp) && isscalar(resp)))
        error('phase3_afc_threshold:simreturn', ...
            "sim_observer は phase 'ascend' で logical を返す必要があります (返り値: %s)。", ...
            class(resp));
    end
    resp = logical(resp);
else
    if ~(isnumeric(resp) && isscalar(resp)) || ~ismember(resp, 0:3)
        error('phase3_afc_threshold:simreturn', ...
            "sim_observer は phase '%s' で 1..3 (中断は0) を返す必要があります (返り値: %s)。", ...
            phase, mat2str(resp));
    end
    if resp == 0
        error('phase3_afc_threshold:aborted', 'sim_observer が中断(0)を返しました。');
    end
end
end

%% ---- 実機: native queue + figure + キーボード ----
function [adw, ui] = open_hardware(o, fs)
adw = [];
try
    adw = audiostreamer('player', fs);
    if ispc, adw.Driver = o.driver; end
    adw.Player = resolve_audio_device(adw, o.dev_id);
    adw.DeviceBitFormat = 'int24';
    adw.DeviceBufferSize = o.nbuf; % requested value, not physical ASIO readback
    adw.PlayerChannels = [1 2];
    ui = build_ui();
catch ME
    if ~isempty(adw), release(adw); end
    rethrow(ME);
end
end

function ui = build_ui()
ui.fig = figure('Name','3AFC 閾値測定','NumberTitle','off','Color','w', ...
                'MenuBar','none','ToolBar','none','Units','normalized', ...
                'Position',[0.2 0.3 0.6 0.4],'KeyPressFcn',@on_key, ...
                'CloseRequestFcn',@(fig,~) request_abort(fig,'window_close'));
ui.fig.UserData = struct('resp', [], 'abort', false, 'cancel_source','', ...
    'ascending', false, 'accepting',false);
ui.ax = axes(ui.fig,'Position',[0.05 0.30 0.90 0.45]);
hold(ui.ax,'on');
% Explicit colors keep interval cues readable in both light and dark themes.
ui.box = gobjects(1,3);
for k = 1:3
    ui.box(k) = rectangle(ui.ax,'Position',[k-0.9 0 0.8 1], ...
                          'FaceColor',[0.90 0.90 0.90],'EdgeColor',[0.20 0.20 0.20], ...
                          'LineWidth',1.5);
    text(ui.ax, k-0.5, 0.5, sprintf('%d',k),'HorizontalAlignment','center', ...
         'FontSize',36,'FontWeight','bold','Color',[0.15 0.15 0.15]);
end
xlim(ui.ax,[0 3]); ylim(ui.ax,[0 1]); axis(ui.ax,'off');
ui.msg = annotation(ui.fig,'textbox',[0.05 0.80 0.90 0.15],'String','', ...
                    'HorizontalAlignment','center','VerticalAlignment','middle', ...
                    'FontSize',16,'EdgeColor','none','Color',[0.15 0.15 0.15]);
ui.fb  = annotation(ui.fig,'textbox',[0.05 0.05 0.90 0.18],'String','', ...
                    'HorizontalAlignment','center','VerticalAlignment','middle', ...
                    'FontSize',20,'FontWeight','bold','EdgeColor','none', ...
                    'Color',[0.15 0.15 0.15]);
drawnow;
end

function on_key(fig, ev)
% 受け付けるキーを phase で絞る。手動上昇法の最中に 1/2/3 を押されたときそれを「いいえ」と
% 解釈すると、出力が ascend_step_db だけ上がる ── 上限までの間、押し間違いが音量を上げる
% 方向にしか効かない。上昇法は大音量呈示を構造的に防ぐための局面な
% ので、上昇法では y/n と中断(x/Esc)だけを受け付ける。本試行では y/n を無視する。
key = lower(ev.Key);
if strcmp(key,'escape')||strcmp(key,'x')
    source='escape'; if strcmp(key,'x'), source='keyboard_x'; end
    request_abort(fig,source); return;
end
if fig.UserData.abort||~fig.UserData.accepting||~isempty(fig.UserData.resp), return, end
if fig.UserData.ascending
    switch key
        case 'y', fig.UserData.resp = 1;    % 聞こえた
        case 'n', fig.UserData.resp = 2;    % 聞こえない
        otherwise, return;
    end
else
    switch key
        case {'1','numpad1'}, fig.UserData.resp = 1;
        case {'2','numpad2'}, fig.UserData.resp = 2;
        case {'3','numpad3'}, fig.UserData.resp = 3;
        otherwise, return;
    end
end
uiresume(fig);
end

function request_abort(fig,source)
if ~fig.UserData.abort
    fig.UserData.cancel_source=source;
    if isfield(fig.UserData,'audio'), fig.UserData.audio.cancel_source=source; end
end
fig.UserData.abort=true; fig.UserData.resp=-1;
uiresume(fig);
end

function [resp, nstate] = present_human(ui, adw, nstate, lvl, target, phase, ...
                                        nisi, o, K, stim)
if ~isgraphics(ui.fig)
    error('phase3_afc_threshold:uiclosed','測定ウィンドウが閉じられました。');
end
if ui.fig.UserData.abort
    error('phase3_afc_threshold:aborted','測定を中断しました。');
end
ui.fig.UserData.ascending=strcmp(phase,'ascend');
if strcmp(phase,'ascend')
    ui.msg.String=sprintf('【手動上昇】音が聞こえたら y、聞こえなければ n   (%.1f dB FS)',lvl);
    n_int=1; target_eff=1;
else
    ui.msg.String=sprintf('どの区間に%sがありましたか？  1 / 2 / 3 で回答  [%s]',stim.label,phase);
    n_int=K.n_intervals; target_eff=target;
end
ui.fb.String='';
[segs,nstate]=build_trial(target_eff,lvl,n_int,nisi,o,nstate,stim);
frames=phase3_afc_frames(vertcat(segs{:}),o.nbuf);
onsets=(0:n_int-1)*(stim.nburst+nisi)/o.fs;
lead=min(K.afc_cue_lead_s,nisi/o.fs/2);
% Generate once per logical trial. Replays retain target, level and noise samples.
for attempt=1:K.afc_max_replays+1
    ui.fig.UserData.active_trial=struct('phase',phase,'level_dbfs',lvl, ...
        'target',target_eff,'attempt',attempt);
    ui.fig.UserData.resp=[];
    ui.fig.UserData.accepting=true;
    drawnow;
    if ui.fig.UserData.abort
        error('phase3_afc_threshold:aborted','測定を中断しました。');
    end
    report=phase3_afc_stream(adw,frames,o.warmup_frames,K.audio_prime_max_frames, ...
        o.fs,onsets,lead,@(k) service_ui(ui,k));
    report.attempt=attempt; report.phase=phase; report.level_dbfs=lvl;
    report.target=target_eff;
    a=ui.fig.UserData.audio;
    a.attempts{end+1}=report;
    a.underrun_samples=a.underrun_samples+report.underrun_samples;
    a.prime_underrun_samples=a.prime_underrun_samples+report.prime_underrun_samples;
    a.retry_count=a.retry_count+(attempt>1);
    ui.fig.UserData.audio=a;
    service_ui(ui,-1); % all intervals finished; keep the first early answer
    if ~isgraphics(ui.fig)
        error('phase3_afc_threshold:uiclosed','測定ウィンドウが閉じられました。');
    end
    if ui.fig.UserData.abort
        error('phase3_afc_threshold:aborted','測定を中断しました。');
    end
    if report.ok, break, end
    ui.fig.UserData.accepting=false;
    ui.fig.UserData.resp=[];
    release(adw); % Next write reinitializes the same selected output.
    if attempt>K.afc_max_replays
        error(report.identifier,'音声送出・区間表示を確認できません。再提示2回で測定を終了しました（欠落 %d samples）。', ...
            a.underrun_samples+a.prime_underrun_samples);
    end
    ui.fb.String=sprintf('音声送出・区間表示を確認できないため再提示します (%d/2)',attempt);
end
% Early responses are retained. A pre-uiwait uiresume alone would otherwise be lost.
if isempty(ui.fig.UserData.resp)&&~ui.fig.UserData.abort, uiwait(ui.fig); end
if ~isgraphics(ui.fig)
    error('phase3_afc_threshold:uiclosed','測定ウィンドウが閉じられました。');
end
r=ui.fig.UserData.resp;
ui.fig.UserData.accepting=false;
if ui.fig.UserData.abort||isempty(r)||r<0
    error('phase3_afc_threshold:aborted','測定を中断しました。');
end
if strcmp(phase,'ascend')
    resp=r==1;
else
    resp=r;
    if resp==target
        ui.fb.String='正解'; ui.fb.Color=[0.05 0.45 0.15];
    else
        ui.fb.String=sprintf('不正解 (正しくは %d)',target); ui.fb.Color=[0.70 0.15 0.10];
    end
    drawnow;
    pause(o.feedback_ms*1e-3);
end
if ui.fig.UserData.abort
    error('phase3_afc_threshold:aborted','測定を中断しました。');
end
end

function abort=service_ui(ui,k)
% Audio is already queued natively: rendering cannot starve a MATLAB write loop.
if ~isgraphics(ui.fig), abort=true; return, end
if k~=0
    for j=1:3
        color=[0.90 0.90 0.90];
        if j==k, color=[0.30 0.70 1.00]; end
        ui.box(j).FaceColor=color;
    end
    ui.fig.UserData.active_interval=k;
end
if k==0, drawnow limitrate; else, drawnow; end
abort=~isgraphics(ui.fig)||ui.fig.UserData.abort;
end

%% ---- 後始末 (例外時も必ずデバイスと図を解放する) ----
function release_all(adw, ui)
if ~isempty(adw)
    try release(adw); catch; end
end
if ~isempty(ui) && isstruct(ui) && isfield(ui,'fig') && isvalid(ui.fig)
    try delete(ui.fig); catch; end
end
end

%% ======================= 保存 =======================

%% ---- 中断時の部分保存 ----
% 完了ランと失敗ランを aborted 付きで残す。threshold_dbfs は入れない: 規定ラン数に達していない
% 推定値を確定値と同じ形で保存すると、後日この .mat を読んだ人が確定値として使ってしまう。
% 保存自体が失敗しても、送出したいのは元の中断理由のほうなので警告に落とす。
function f=save_partial(P,o)
try
    f = save_result(P, o, '_aborted', o.abort_outdir);
    vprintf(o.verbose, '  中断記録: %s\n', f);
catch saveErr
    rescue = rescue_save(P, 'aborted');
    f=rescue;
    warning('phase3_afc_threshold:partialsave', ...
        '中断時の保存に失敗しました (%s)。診断履歴を退避しました: %s', ...
        saveErr.message, rescue);
end
end

function P=partial_result(runs, failed_run, heard_db, start_db, n_prac_ok, abort_phase, ME, o, K)
P = struct(); P.test=o.test;
P.aborted             = true;
P.completed           = false;
P.abort_identifier    = ME.identifier;
P.abort_message       = ME.message;
P.abort_phase         = abort_phase;
P.abort_timestamp     = char(datetime('now','Format','yyyy-MM-dd HH:mm:ss.SSS'));
P.subject             = char(o.subject);      % 氏名ではなく参加者コードのみ
P.ear                 = upper(char(o.ear));
P.runs                = runs;
P.failed_run          = failed_run;
P.n_runs_done         = numel(runs);
P.runs_threshold_dbfs = [runs.threshold_dbfs];   % 参考値。確定閾値ではない
P.ascend_heard_db     = heard_db;
P.start_db            = start_db;
P.practice_correct    = n_prac_ok;
P.practice_trials     = o.n_practice;
P.rule                = K.rule;
P.pc_target           = K.pc_target;
P.stimulus            = lower(char(o.stimulus));
P.limits    = struct('max_level_dbfs',o.max_level_dbfs,'min_level_dbfs',o.min_level_dbfs);
P.simulated = ~isempty(o.sim_observer);
P.audio=o.audio;
P.abort_source=o.audio.cancel_source;
end

function outfile = save_result(T, o, suffix, destination)
if nargin < 3, suffix = ''; end
if nargin < 4, destination = ''; end

if isempty(destination)
    check_save_dest(o);   % 測定前にも同じ検査を通しているが、その後に環境が変わることはある
elseif ~isfolder(destination) || isempty(o.subject) || isempty(o.ear)
    error('phase3_afc_threshold:abortdest','中断記録の保存先または参加者コードが無効です。');
end

P = provenance_meta();     % 時刻・コード版・MATLAB版・ホストを1箇所で組む (共有ヘルパ)

T.test=o.test;
meta = struct(); meta.test=o.test;
meta.subject     = o.subject;
meta.ear         = upper(char(o.ear));
meta.stimulus    = T.stimulus;
meta.condition   = ['afc_threshold' suffix];
meta.timestamp   = P.timestamp;
meta.operator    = o.operator;
meta.notes       = o.notes;
meta.simulated   = T.simulated;
meta.code_commit = P.code_commit;
meta.code_dirty  = P.code_dirty;
meta.matlab_ver  = P.matlab_ver;
meta.host        = P.host;

subj_safe = safe_name(o.subject);
if isempty(destination)
    outdir = fullfile(o.outdir, subj_safe);
    if ~exist(outdir,'dir'), mkdir(outdir); end
else
    outdir = destination;
end
if strcmp(suffix,'_aborted')
    stamp = char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'));
    base = sprintf('phase3_%s_%s_afc_%s%s', subj_safe, char(T.stimulus), stamp, suffix);
    outfile = fullfile(outdir,[base '.mat']);
    serial = 1;
    while isfile(outfile)
        outfile = fullfile(outdir,sprintf('%s_%d.mat',base,serial));
        serial = serial+1;
    end
else
    outfile = fullfile(outdir, sprintf('phase3_%s_afc_%s%s.mat', subj_safe, P.stamp, suffix));
end

save(outfile, 'T', 'meta', '-v7.3');
vprintf(o.verbose, '=== 保存 ===\n  → %s\n', outfile);
end

%% ---- 最後の砦: 必ず書ける場所へ落とす ----
% 保存先の不備は測定前に検査しているが、それでも保存が失敗したときに「返り値に入っている」
% だけでは足りない ── nargout==0 で呼ばれれば T は clear されるし、中断経路には返り値が無い。
% tempdir は必ず書けるので、そこへ落として場所を名前で伝える。ここまで失敗したら打つ手が
% 無いので、警告を出して目印の文字列を返す (送出したいのは元の失敗のほうなので投げない)。
function outfile = rescue_save(T, tag)
try
    outfile = [tempname(tempdir) '_phase3_afc_rescue_' tag '.mat'];
    % 変数名は正規の保存と同じ 'T'。退避ファイルを読み戻す人は save_result が書いたものと
    % 同じ形を期待するので、ここだけ別名にすると load した後に中身を探すことになる。
    save(outfile, 'T', '-v7.3');
catch
    warning('phase3_afc_threshold:rescuefailed', ...
        '退避保存にも失敗しました。測定結果を残せません。');
    outfile = '(退避不可)';
end
end

%% ---- local: verbose ゲート付き fprintf ----
function vprintf(on, varargin)
if on, fprintf(varargin{:}); end
end
