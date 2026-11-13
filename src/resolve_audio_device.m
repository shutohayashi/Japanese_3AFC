function dev = resolve_audio_device(io_obj, dev_id)
%RESOLVE_AUDIO_DEVICE Select an explicit output or a uniquely identified RME device.

    if isa(io_obj,'audiostreamer')
        devs = audiostreamer.getPlayerNames(io_obj.Driver);
    else
        devs = getAudioDevices(io_obj);          % デバイス名の一覧
    end
    if ~iscell(devs), devs = cellstr(devs); end  % string配列で返る版にも対応

    % --- 旧 PsychPortAudio 流の数値ID誤用を弾く ---
    if isnumeric(dev_id) && ~isempty(dev_id)
        error('resolve_audio_device:devid', ...
            ['dev_id は数値IDではなくデバイス名の文字列です。' ...
             'getAudioDevices(...) で名前を確認してください。']);
    end

    % --- dev_id 明示指定: 存在チェックのうえ採用 ---
    if ~isempty(dev_id)
        dev_id = char(dev_id);
        if ~ismember(dev_id, devs)
            error('resolve_audio_device:notfound', ...
                'dev_id="%s" は見つかりません。利用可能: %s', dev_id, join_devices(devs));
        end
        dev = dev_id;
        return;
    end

    % --- 自動検出: Babyface/Fireface/RME を名前マッチ ---
    key   = {'babyface','fireface','rme'};
    hit   = contains(lower(devs), key);          % いずれかのキーを含む要素が true
    match = devs(hit);
    if isempty(match)
        error('resolve_audio_device:norme', ...
            ['Babyface/RME デバイスが見つかりません。接続と Audio MIDI設定/TotalMix を確認し、' ...
             'dev_id に名前を明示してください。利用可能: %s'], join_devices(devs));
    elseif numel(match) > 1
        error('resolve_audio_device:ambiguous', ...
            'Babyface/RME 候補が複数あります。dev_id で明示してください: %s', join_devices(match));
    end
    dev = match{1};
    fprintf('resolve_audio_device: 出力デバイス自動選択 = "%s"\n', dev);
end

%% ---- ローカル関数: デバイス名一覧を読みやすい文字列にする ----
function s = join_devices(devs)
    if isempty(devs), s = '(なし)'; return; end
    quoted = cellfun(@(d) ['"' d '"'], cellstr(devs), 'UniformOutput', false);
    s = strjoin(quoted, ', ');
end
