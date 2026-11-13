function report=phase3_afc_stream(varargin)
% Delegate to the actual production helper with a deterministic test clock.
s=phase3_stream_test_control('read');
clock=struct('now',@now,'wait',@(dt) phase3_stream_test_control('wait',dt), ...
    'prime_wait',@(dt) phase3_stream_test_control('prime_wait',dt));
report=s.real_stream(varargin{:},clock);
end
function t=now
s=phase3_stream_test_control('read'); t=s.now;
end
