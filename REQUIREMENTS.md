[English](#english)

# 動作要件

- **無音テスト**はMATLAB R2026a（検証済み）とSignal Processing Toolboxを使用します。
- **実機での測定**には、`audiostreamer`を使用するためAudio Toolboxも必要です。2チャンネル出力の機器（オーディオインターフェース、USBオーディオ、PCのヘッドホン出力など）と、ヘッドホンまたは挿入型イヤホンを用意します。サンプリング周波数は48 kHzの整数倍（既定は96 kHz）を使用します。Windowsの既定ドライバーはASIOで、ASIO非対応の機器ではWASAPIを指定します。
- 測定前に、実際の出力経路と、その構成で使用する刺激ごとの呈示上限を確認します。

## English

- **Silent self-test:** MATLAB R2026a (verified) and Signal Processing Toolbox.
- **Live playback:** Add Audio Toolbox for `audiostreamer`. Use a two-channel output (audio interface, USB audio device or computer headphone output) with headphones or insert earphones. Use a sample rate that is an integer multiple of 48 kHz (96 kHz by default). On Windows the default driver is ASIO; select WASAPI for devices without ASIO.
- Verify the output route and establish a stimulus-specific ceiling for the configured audio chain before measuring.
