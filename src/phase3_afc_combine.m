%% PHASE 3  3AFC のラン間ばらつき判定と閾値の合成
% 「2ラン実施し、差が tol_db を超えたら3ラン目を追加して、近い2つの平均を採る」という
% 事前の決定を、そのままコードにしたもの。
%
% なぜ事前に決めてあるのか: 本実験のノイズレベルはこの1つの数字に乗る。ばらついた結果を見て
% から「どちらを採るか」を判断すると、レベル決定が事後的になり、結果を見て選んだことになる。
% 規則を先に固定しておけば、ばらつきは「規則がどう動いたか」として記録に残る。
%
% なぜ独立ファイルなのか: phase3_afc_threshold.m のローカル関数のままだと外から呼べず、
% この判定規則そのものを検証できない。規則の検証を「実際に3ラン走らせてみる」でしか
% できない状態にすると、テストが乱数と課題モデルに依存してしまう。
%
% ⚠ 呼び出し側の責務: この関数は追加ランを走らせない。ok=false を見て走らせるかどうかは
%   phase3_afc_threshold が決める (走らせられるラン数の上限を知っているのはあちら)。
%
%   th_all : 各ランの閾値 [dB FS]
%   tol_db : ラン間差の許容 [dB]
% 返り値:
%   th   : 採用する閾値 [dB FS]
%   used : 平均に使ったランの添字
%   ok   : ばらつきが許容内か (false なら呼び出し側が追加ランを検討する)
%
% Usage:
%   [th, used, ok] = phase3_afc_combine([th1 th2], tol_db);
% ============================================================
function [th, used, ok] = phase3_afc_combine(th_all, tol_db)

if nargin < 2
    error('phase3_afc_combine:args', 'th_all と tol_db の2引数が必要です。');
end
if ~isnumeric(th_all) || isempty(th_all) || ~isvector(th_all) || ~all(isfinite(th_all))
    error('phase3_afc_combine:th', 'th_all は有限の数値ベクトルである必要があります。');
end
if ~isscalar(tol_db) || ~isnumeric(tol_db) || ~isreal(tol_db) || ~isfinite(tol_db)
    error('phase3_afc_combine:tol', 'tol_db は有限の実数スカラである必要があります。');
end

ok = (max(th_all) - min(th_all)) <= tol_db;

if numel(th_all) <= 2 || ok
    % 2ラン以下、またはばらつきが許容内: 全ランの平均。
    used = 1:numel(th_all);
else
    % 近い2つ = 全ペアのうち差が最小の組。3ラン目を足したのは2ランが離れていたからなので、
    % 「3つの平均」ではなく「近い2つ」を採る (離れた1つは、集中の切れや課題の取り違えと
    % いった、閾値以外の要因を含んでいる可能性が高い)。
    n = numel(th_all); best = inf; used = [1 2];
    for i = 1:n-1
        for j = i+1:n
            d = abs(th_all(i) - th_all(j));
            if d < best, best = d; used = [i j]; end
        end
    end
end

th = mean(th_all(used));
end
