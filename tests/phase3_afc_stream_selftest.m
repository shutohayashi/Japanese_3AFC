function phase3_afc_stream_selftest()
% Exercise native prequeueing, cues and fault rejection without sound.
root=fileparts(fileparts(mfilename('fullpath')));
production=@phase3_afc_stream; functions(production); % bind before shadow fixture
fixture=fullfile(root,'tests','fixtures','audio_streamer');
addpath(fixture,'-begin'); cleanup=onCleanup(@() rmpath(fixture));
phase3_stream_test_control('reset'); phase3_stream_test_control('real',production);
w=audiostreamer('player',96000); nbuf=2048;
wave=[ones(5191,1);zeros(48000,1);2*ones(5191,1);zeros(48000,1);3*ones(5191,1)];
frames=phase3_afc_frames(wave,nbuf);
flat=reshape(permute(frames,[1 3 2]),[],2);
assert(isequal(flat(1:numel(wave),1),wave)&&all(flat(:,2)==0));
assert(all(flat(numel(wave)+1:end,1)==0)&&size(flat,1)-numel(wave)<nbuf);
onsets=[0 53191 106382]/96000; cues=[]; late=false;
r=phase3_afc_stream(w,frames,4,16,96000,onsets,0.25,@cue);
assert(r.ok&&r.prime_frames==4&&r.trial_frames==size(frames,3));
s=phase3_stream_test_control('read');
assert(s.prime_waits>0,'Qualification must avoid the UI-rendering playback wait.');
assert(size(s.frames{1},1)==20*nbuf&&all(s.frames{1}(:)==0));
assert(isequal(s.frames{2}(1:size(flat,1),:),flat));
assert(isequal(cues,[1 2 3])&&all(r.cue_actual_s<=r.interval_onset_s));
assert(all(abs(r.cue_planned_s(2:3)-(r.interval_onset_s(2:3)-0.25))<1e-12));
for mode={'prime_reset','prime_last','prime_exhaust','underrun','late','stall','skip','jitter','premature','delayed'}
    phase3_stream_test_control('reset'); phase3_stream_test_control('real',production);
    w=audiostreamer('player',96000); cues=[]; late=strcmp(mode{1},'late'); empty_checks=0;
    switch mode{1}
        case 'prime_reset', phase3_stream_test_control('script',[0 0 9 zeros(1,4)]);
        case 'prime_last', phase3_stream_test_control('script',[ones(1,12) zeros(1,4)]);
        case 'prime_exhaust', phase3_stream_test_control('script',ones(1,16));
        case 'underrun', phase3_stream_test_control('script',[zeros(1,4) 1024]);
        case 'stall', phase3_stream_test_control('stall',true);
        case 'skip', phase3_stream_test_control('hook',@skip);
        case 'jitter', phase3_stream_test_control('hook',@jitter);
        case 'premature', phase3_stream_test_control('premature',1.40);
        case 'delayed', phase3_stream_test_control('hook',@delayed);
    end
    r=phase3_afc_stream(w,frames,4,16,96000,onsets,0.25,@cue);
    switch mode{1}
        case 'prime_reset', assert(r.ok&&r.prime_frames==7&&r.prime_underrun_samples==9);
        case 'prime_last', assert(r.ok&&r.prime_frames==16);
        case 'prime_exhaust'
            assert(~r.ok&&r.prime_frames==16&&r.trial_frames==0);
            assert(strcmp(r.identifier,'phase3_afc_threshold:primingunderrun'));
        case 'underrun', assert(~r.ok&&r.underrun_samples==1024);
        case 'late', assert(~r.ok&&r.cue_late&&strcmp(r.identifier,'phase3_afc_threshold:cuelate'));
        case 'stall', assert(~r.ok&&strcmp(r.identifier,'phase3_afc_threshold:streamtimeout'));
        case 'skip', assert(~r.ok&&r.prime_frames<=16&&r.trial_frames==0);
        case 'jitter'
            assert(r.ok&&size(r.prime_checks,1)==4,'Four real zero observations may span more than four frames.');
            assert(all(diff([0;r.prime_checks(:,1)])>=2048/96000));
        case 'premature'
            assert(~r.ok&&strcmp(r.identifier,'phase3_afc_threshold:streamincomplete'), ...
                'An idle device with an incomplete trial cannot produce a threshold.');
        case 'delayed'
            assert(~r.ok&&r.underrun_samples==17,'The final queue query must not erase a late underrun.');
    end
    assert(phase3_stream_test_control('read').stops>=1);
end
assert(phase3_protocol_const().audio_frame_samples==2048);
phase3_stream_test_control('hook',[]); % break callback/cleanup workspace cycle
fprintf('phase3_afc_stream_selftest: PASS\n');
    function abort=cue(k)
        abort=false;
        if k>0, cues(end+1)=k; end
        if late&&k==2, phase3_stream_test_control('advance',0.30); end
    end
    function skip(event)
        if strcmp(event.name,'read'), phase3_stream_test_control('advance',0.10); end
    end
    function jitter(event)
        if strcmp(event.name,'read'), phase3_stream_test_control('advance',0.03); end
    end
    function delayed(event)
        if strcmp(event.name,'queue_empty')
            empty_checks=empty_checks+1;
            if empty_checks==2
                s=phase3_stream_test_control('read'); u=zeros(1,s.reads+1); u(end)=17;
                phase3_stream_test_control('script',u);
            end
        end
    end
end
