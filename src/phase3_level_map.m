function out = phase3_level_map(op, x)
%PHASE3_LEVEL_MAP Convert between amplitude magnitude and dB FS.

ops = {'amp2db','db2amp'};
if nargin < 1 || ~(ischar(op) || isstring(op))
    error('phase3_level_map:op', 'op は文字列で指定してください (%s)。', strjoin(ops,' | '));
end
op = char(op);
if ~ismember(lower(op), ops)
    % 未知の op を既定動作に落とさない: 綴り違いが黙って別の換算になるのを防ぐ
    error('phase3_level_map:op', "op '%s' は未知です。使えるのは: %s", op, strjoin(ops,' | '));
end
if nargin < 2
    error('phase3_level_map:novalue', "op '%s' には変換する値が必要です。", op);
end

if ~isnumeric(x) || ~isreal(x)
    error('phase3_level_map:value', '変換する値は実数の数値配列である必要があります。');
end

switch lower(op)

    case 'amp2db'
        % 振幅は大きさなので負値は入力ミス。0 は無音 = -Inf dB FS で正しいので通す。
        if any(x(:) < 0)
            error('phase3_level_map:negamp', ...
                '振幅に負値があります (最小 %.6g)。振幅は大きさなので 0 以上です。', min(x(:)));
        end
        out = 20*log10(x);

    case 'db2amp'
        out = 10.^(x/20);

end
end
