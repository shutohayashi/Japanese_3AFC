function report=phase3_afc_stream(player,frames,stable_frames,max_prime_frames,fs,onsets,lead,cue,clock)
%PHASE3_AFC_STREAM Prequeue each complete trial; native audio survives UI work.
% Cue times are conservative scheduled times, never claimed as DAC timestamps.
% Counter reads reset the API count: accumulate before stopping/releasing output.
if nargin<9
    timer=tic;
    clock=struct('now',@() toc(timer),'wait',@(dt) pause(dt), ...
        'prime_wait',@wait_without_render);
elseif ~isfield(clock,'prime_wait')
    clock.prime_wait=clock.wait; % explicit deterministic clocks used by callers/tests
end
period=size(frames,1)/fs;
pre_frames=max_prime_frames+stable_frames;
flat=reshape(permute(frames,[1 3 2]),[],2);
report=struct('ok',false,'identifier','phase3_afc_threshold:primingunderrun', ...
    'backend','audiostreamer','prime_frames',0,'prime_underrun_samples',0, ...
    'trial_frames',0,'underrun_samples',0,'drain_frames',0,'queue_samples',0,'prime_checks',[], ...
    'cue_late',false,'interval_onset_s',pre_frames*period+onsets, ...
    'cue_planned_s',[0 pre_frames*period+onsets(2:end)-lead], ...
    'cue_actual_s',nan(size(onsets)),'append_time_s',NaN,'elapsed_s',0);
guard=onCleanup(@() stop(player));
write(player,zeros(pre_frames*size(frames,1),2),'non-blocking');
report.queue_samples=player.NumPlayerSamples;
if report.queue_samples~=pre_frames*size(frames,1)
    report.identifier='phase3_afc_threshold:queuefailure'; return
end
if cue(1)
    report.identifier='phase3_afc_threshold:aborted'; return
end
report.cue_actual_s(1)=0;
getUnderrunCount(player); % discard only stale, pre-start state
origin=clock.now(); % before start: startup latency makes cues earlier, never later
start(player);
prime_origin=clock.now(); % start-call time cannot fabricate clean prime checks
report.start_call_s=prime_origin-origin;
stable=0; primed=false; last_check=0;
while report.prime_frames<max_prime_frames
    elapsed=clock.now()-prime_origin;
    if elapsed>max_prime_frames*period+1e-8
        report.prime_frames=max_prime_frames; break
    end
    remaining=last_check+period-elapsed;
    if remaining>1e-8
        clock.prime_wait(min(0.005,remaining)); continue
    end
    u=getUnderrunCount(player);
    elapsed=clock.now()-prime_origin;
    report.prime_frames=min(max_prime_frames,ceil(elapsed/period-1e-8));
    report.prime_underrun_samples=report.prime_underrun_samples+u;
    if u>0, stable=0; else, stable=stable+1; end
    report.prime_checks(end+1,:)=[elapsed u stable];
    last_check=elapsed;
    if stable>=stable_frames && elapsed<=max_prime_frames*period+1e-8
        primed=clock.now()-origin<pre_frames*period;
        break
    end
end
report.qualification_elapsed_s=clock.now()-prime_origin;
report.prime_observations=size(report.prime_checks,1);
canceled=cue(0); % service/honor sticky abort before adding any stimulus
report.pre_append_time_s=clock.now()-origin;
primed=primed&&clock.now()-origin<pre_frames*period;
if primed && ~canceled
    % No synthesis/GUI between these samples: gaps and noise are fixed beforehand.
    write(player,[flat;zeros(stable_frames*size(frames,1),2)],'non-blocking');
    report.trial_frames=size(frames,3); report.drain_frames=stable_frames;
    report.append_time_s=clock.now()-origin;
    if report.append_time_s>=pre_frames*period
        report.cue_late=true; report.identifier='phase3_afc_threshold:cuelate';
    else
        report.identifier='';
    end
end
next_cue=2;
limit=pre_frames*period+(size(flat,1)/fs+stable_frames*period)*(report.trial_frames>0)+5;
while isPlaying(player)
    elapsed=clock.now()-origin;
    if elapsed>limit
        report.identifier='phase3_afc_threshold:streamtimeout'; break
    end
    if report.trial_frames>0
        while next_cue<=numel(onsets)&&elapsed>=report.cue_planned_s(next_cue)
            canceled=cue(next_cue)||canceled;
            report.cue_actual_s(next_cue)=clock.now()-origin;
            if report.cue_actual_s(next_cue)>report.interval_onset_s(next_cue)
                report.cue_late=true;
            end
            next_cue=next_cue+1; elapsed=clock.now()-origin;
        end
    end
    canceled=cue(0)||canceled;
    report.underrun_samples=report.underrun_samples+getUnderrunCount(player);
    clock.wait(0.005);
end
report.elapsed_s=clock.now()-origin;
report.expected_end_s=pre_frames*period+ ...
    (size(flat,1)/fs+stable_frames*period)*(report.trial_frames>0);
report.queue_remaining_samples=player.NumPlayerSamples;
% The queue getter yields native events. Read counters LAST, before stop clears them.
report.underrun_samples=report.underrun_samples+getUnderrunCount(player);
if canceled
    report.identifier='phase3_afc_threshold:aborted';
elseif strcmp(report.identifier,'phase3_afc_threshold:streamtimeout')
    % Timeout remains a failure even if the last counter read was zero.
elseif report.trial_frames==0
    report.identifier='phase3_afc_threshold:primingunderrun';
elseif report.underrun_samples>0
    report.identifier='phase3_afc_threshold:underrun';
elseif report.elapsed_s+1e-8<report.expected_end_s||report.queue_remaining_samples>0
    report.identifier='phase3_afc_threshold:streamincomplete';
elseif report.cue_late||any(isnan(report.cue_actual_s))
    report.identifier='phase3_afc_threshold:cuelate';
end
report.ok=isempty(report.identifier);
end

function wait_without_render(seconds)
% At most 5 ms per slice, within a <=16-frame qualification budget.
% pause would render/process GUI work and can overrun this short observation window.
timer=tic;
while toc(timer)<seconds
end
end
