# Requirements

[日本語](#日本語)

- **Silent self-test:** MATLAB R2026a (verified) and Signal Processing Toolbox.
- **Live playback:** Add Audio Toolbox for `audiostreamer`. Use an audio interface with two output channels that supports the selected sample rate (96 kHz by default), a compatible headphone or insert earphone, and the corresponding audio driver (ASIO by default on Windows).
- Verify the output route and establish a stimulus-specific ceiling for the configured audio chain before measuring.

## 日本語

- **無音テスト**はMATLAB R2026a（検証済み）とSignal Processing Toolboxを使用します。
- **実機での測定**には、`audiostreamer`を使用するためAudio Toolboxも必要です。設定したサンプリング周波数（既定は96 kHz）と2出力チャンネルに対応するオーディオインターフェース、対応するヘッドホンまたは挿入型イヤホン、オーディオドライバー（Windowsの既定はASIO）を用意します。
- 測定前に、実際の出力経路と、その構成で使用する刺激ごとの呈示上限を確認します。
