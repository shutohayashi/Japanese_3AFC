function dev = resolve_audio_device(io_obj, dev_id)
%RESOLVE_AUDIO_DEVICE Select an explicit output, or the only output the driver lists.
% With several outputs, require dev_id so a measurement never falls back to an
% unintended device such as the built-in speaker.

    if isa(io_obj,'audiostreamer')
        devs = audiostreamer.getPlayerNames(io_obj.Driver);
    else
        devs = getAudioDevices(io_obj);          % デバイス名の一覧
    end
    if ~iscell(devs), devs = cellstr(devs); end  % string配列で返る版にも対応

    % --- 数値IDの指定を弾く（名前で指定する） ---
    if isnumeric(dev_id) && ~isempty(dev_id)
        error('resolve_audio_device:devid', ...
            ['dev_id は数値IDではなく出力機器名の文字列です。' ...
             '利用可能: %s'], join_devices(devs));
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

    % --- 自動選択: 出力機器が1台だけのときに限る ---
    if isempty(devs)
        error('resolve_audio_device:nodevice', ...
            ['出力機器が見つかりません。接続と driver の指定を確認してください' ...
             '（Windows の既定は ASIO。ASIO 非対応の機器では driver に WASAPI を指定）。']);
    elseif numel(devs) > 1
        error('resolve_audio_device:ambiguous', ...
            '出力機器が複数あります。dev_id に名前を指定してください: %s', join_devices(devs));
    end
    dev = devs{1};
    fprintf('resolve_audio_device: 出力機器を自動選択 = "%s"\n', dev);
end

%% ---- ローカル関数: デバイス名一覧を読みやすい文字列にする ----
function s = join_devices(devs)
    if isempty(devs), s = '(なし)'; return; end
    quoted = cellfun(@(d) ['"' d '"'], cellstr(devs), 'UniformOutput', false);
    s = strjoin(quoted, ', ');
end
