[日本語の説明は下部にあります](#日本語)

# Auditory 3AFC

Measure detection thresholds for click trains and band-limited noise in MATLAB. In each three-alternative forced-choice (3AFC) trial, the listener selects the interval containing the sound. The adaptive procedure uses a 2-down/1-up rule.

## Set up and run a silent test

See [Requirements](REQUIREMENTS.md) for the MATLAB version, toolboxes and audio setup. Open this folder as the MATLAB Current Folder, then run:

```matlab
addpath('src', 'tests');
phase3_afc_selftest
rmpath('tests');
```

The test finishes with `phase3_afc_selftest PASS`. It uses simulated responses and plays no sound. Add only `src` during measurements. The test fixtures replace the audio backend and must stay off the measurement path.

## Run a measurement

1. Connect and verify the audio interface, transducer and output routing. Use an output that supports the configured sample rate and two output channels. The default is 96 kHz with ASIO on Windows. Confirm the acoustic output and the ceiling for your setup before attaching the transducer to a listener. Keep system audio off the measurement output.
2. If exactly one RME device is detected, the program selects it automatically. Set `dev_id` to the exact output name to choose a device explicitly. Run the following for one stimulus. Enter the ceiling in dB FS verified for that stimulus and audio chain. Repeat with `'noise'` and its own ceiling to measure noise detection.

```matlab
addpath('src');
if ~isfolder('results'), mkdir('results'); end
ceiling = input('Verified ceiling for the click train (dB FS): ');
T = phase3_afc_threshold('stimulus', 'click', ...
    'max_level_dbfs', ceiling, 'subject', 'P001', ...
    'ear', 'R', 'outdir', 'results');
```

3. In the task window, press `y` when you hear the sound during the initial ascending search and `n` when you do not. During practice and measurement, press `1`, `2` or `3` for the interval containing the sound. Press Esc or `x` to stop.

For a completed measurement, `T.threshold_dbfs` gives the threshold and `T.outfile` points to the MAT file under `results/P001/`. The file contains the result `T` and metadata `meta`. Use a coded subject identifier. An interrupted or range-limited run has no confirmed threshold. Click levels are peak-referenced and noise levels are RMS-referenced. dB FS describes digital level relative to full scale. Reporting sound pressure requires acoustic calibration.

## Citation

If you use this software in research, please cite the software, authored by Shuto Hayashi, in your paper, thesis, or presentation. Include the version or Git commit you used and its URL or DOI when available.

> Hayashi, S. (Release year). *Auditory 3AFC* (version or Git commit used) [Computer software].

## 日本語

クリック列と帯域制限ノイズの検知閾値をMATLABで測定します。3肢強制選択法（3AFC）では、3つの区間のうち音が入っていた区間を選びます。刺激レベルは2-down/1-up法で調整します。

### 準備と無音テスト

MATLABのバージョン、Toolbox、音響機器は[動作要件](REQUIREMENTS.md#日本語)を確認してください。このフォルダーをMATLABの現在のフォルダーに設定し、次を実行します。

```matlab
addpath('src', 'tests');
phase3_afc_selftest
rmpath('tests');
```

`phase3_afc_selftest PASS`が表示されれば成功です。模擬応答を使うため、音は出ません。測定時に追加するのは`src`だけです。テスト用の模擬音声処理が測定時のMATLABパスに入らないようにします。

### 測定

1. オーディオインターフェースと変換器を接続し、出力先を確認します。設定したサンプリング周波数と2出力チャンネルに対応する機器を使用します。既定は96 kHzで、WindowsではASIOを使用します。参加者に変換器を装着する前に、その構成での音響出力と呈示上限を確認し、システム音が測定用出力に流れないようにします。
2. RME機器が1台だけ検出された場合は自動選択します。機器を指定する場合は`dev_id`に出力機器の正確な名前を渡します。次のコマンドを実行し、確認済みの呈示上限をdB FSで入力します。ノイズを測る場合は`'click'`を`'noise'`に変更し、ノイズ用に確認した上限を入力します。

```matlab
addpath('src');
if ~isfolder('results'), mkdir('results'); end
ceiling = input('確認済みのクリック列呈示上限（dB FS）: ');
T = phase3_afc_threshold('stimulus', 'click', ...
    'max_level_dbfs', ceiling, 'subject', 'P001', ...
    'ear', 'R', 'outdir', 'results');
```

3. 最初の上昇法では、聞こえたら`y`、聞こえなければ`n`を押します。練習と測定では、音が入っていた区間を`1`、`2`、`3`で回答します。Escまたは`x`で中止できます。

完了した測定では、`T.threshold_dbfs`に閾値、`T.outfile`に`results/P001/`内のMATファイルのパスが入ります。MATファイルには結果`T`とメタデータ`meta`が入ります。参加者は符号化したIDで記録します。中断時や測定範囲外では閾値は確定しません。クリックはピーク、ノイズはRMSを基準とし、dB FSはデジタルのフルスケールに対するレベルを表します。音圧の報告には音響校正が必要です。

### 引用

本ソフトウェアを研究に使用した場合は、論文、学位論文、学会発表などで、林秀斗を著者として本ソフトウェアを引用してください。使用したバージョンまたはGitコミットを明記し、URLやDOIがある場合は併記してください。

> 林秀斗（公開年）。Auditory 3AFC（使用したバージョンまたはGitコミット）［ソフトウェア］。
