function K = phase3_protocol_const()
%PHASE3_PROTOCOL_CONST Defaults for the click and noise detection tasks.
% The noise crest allowance uses the Gaussian sample-count model in gauss_peak.
% The 70.7% convergence point follows the 2-down/1-up rule (Levitt, 1971).
K = struct();

K.noise_band_hz = [100 10000];
K.crest_headroom_db = struct( ...
    'noise', 16, ...
    'click',  0);
K.crest_basis = struct( ...
    'ref_seconds',        1800, ...
    'max_expected_clips', 1);
K.fs_hz = 96000;
K.audio_frame_samples = 2048;
K.audio_prime_frames = 4;
K.audio_prime_max_frames = 16;
K.afc_cue_lead_s = 0.250;
K.afc_max_replays = 2;
K.min_level_dbfs = -130;
K.click_width_us = 5/48000*1e6;
K.n_intervals   = 3;
K.burst_ms      = 500;
K.isi_ms        = 500;
K.ramp_ms       = 20;
K.click_burst_epochs = 6;
K.rule                 = '2-down-1-up';
K.pc_target            = sqrt(0.5);
K.step_start_db        = 4;
K.step_final_db        = 2;
K.step_change_at_rev   = 2;
K.n_reversals          = 8;
K.n_reversals_avg      = 6;
K.n_practice           = 6;
K.n_runs         = 2;
K.n_runs_max     = 3;
K.run_tol_db     = 4;
K.ascend_step_db  = 5;
K.start_headroom_db = 10;
K.click_iti_ms = 90;
end
