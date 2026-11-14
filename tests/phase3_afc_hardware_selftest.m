function phase3_afc_hardware_selftest(mode)
% Production UI/staircase, with silent native queue and accelerated test clock.
if nargin<1, mode='all'; end
root=fileparts(fileparts(mfilename('fullpath')));
production=@phase3_afc_stream; functions(production);
fixture=fullfile(root,'tests','fixtures','audio_streamer');
writerfixture=fullfile(root,'tests','fixtures','audio_writer');
addpath(writerfixture,'-begin'); addpath(fixture,'-begin');
cleanup=onCleanup(@() finish(fixture,writerfixture));
visibility=get(groot,'DefaultFigureVisible'); set(groot,'DefaultFigureVisible','off');
restore=onCleanup(@() set(groot,'DefaultFigureVisible',visibility));
if ~strcmp(mode,'cancel')
for stimulus={'click','noise'}
    baseline=run_case(stimulus{1},'normal',production);
    if strcmp(stimulus{1},'click'), click_baseline=baseline; end
    retried=run_case(stimulus{1},'retry',production);
    assert(baseline.completed&&retried.completed,'Incomplete %s: baseline=%s retry=%s', ...
        stimulus{1},baseline.status,retried.status);
    assert(isequal(baseline.runs,retried.runs)&&baseline.threshold_dbfs==retried.threshold_dbfs);
    assert(retried.audio.retry_count==1&&retried.audio.underrun_samples==1024);
    assert(retried.audio.prime_underrun_samples==0&&isempty(retried.audio.asio_buffer_samples));
    s=phase3_stream_test_control('read'); reports=retried.audio.attempts;
    idx=find(cellfun(@(a) ~a.ok,reports),1);
    assert(isequal(s.frames{2*idx},s.frames{2*(idx+1)}),'Replay must retain noise/gaps/target/level.');
    assert(all(cellfun(@(a) a.ok||strcmp(a.identifier,'phase3_afc_threshold:underrun'),reports)));
end
late=run_case('click','retry_cue',production);
assert(late.completed&&late.audio.retry_count==1&&late.audio.underrun_samples==0);
assert(isequal(click_baseline.runs,late.runs),'Late cues must not advance the staircase.');
assert(sum(cellfun(@(a) a.cue_late,late.audio.attempts))==1);
end
for scenario={'keyboard_x','escape','close','close_then_escape','escape_then_close', ...
        'keyboard_x_then_escape','exhaust','prime_exhaust','incomplete_exhaust'}
    T=run_case('click',scenario{1},production);
    assert(~T.completed&&strcmp(T.status,'interrupted')&&~isfield(T,'threshold_dbfs'));
    assert(T.n_runs_done==0&&isempty(T.failed_run));
    s=phase3_stream_test_control('read');
    assert(s.releases>=1&&isempty(findall(groot,'Type','figure','Name','3AFC 閾値測定')));
    if ismember(scenario{1},{'keyboard_x','escape','close','close_then_escape', ...
            'escape_then_close','keyboard_x_then_escape'})
        assert(strcmp(T.abort_identifier,'phase3_afc_threshold:aborted'));
        expected='keyboard_x';
        if startsWith(scenario{1},'escape'), expected='escape'; end
        if startsWith(scenario{1},'close'), expected='window_close'; end
        assert(isfield(T,'abort_source')&&strcmp(T.abort_source,expected), ...
            'The first cancellation source must be recorded accurately.');
        assert(strcmp(T.audio.cancel_source,expected));
        assert(T.audio.attempts{1}.trial_frames>0&&s.now>0.9,'Finish the already queued trial after cancel.');
    else
        assert(T.audio.retry_count==2&&numel(T.audio.attempts)==3);
        if strcmp(scenario{1},'prime_exhaust')
            assert(all(cellfun(@(a) a.prime_frames==16&&a.trial_frames==0,T.audio.attempts)));
        elseif strcmp(scenario{1},'incomplete_exhaust')
            assert(strcmp(T.abort_identifier,'phase3_afc_threshold:streamincomplete'));
            assert(T.audio.underrun_samples==0);
        else
            assert(T.audio.underrun_samples==3*1024);
        end
    end
end
try
    run_case('click','fault',production); error('phase3_test:expected','Expected native fault.');
catch ME
    assert(strcmp(ME.identifier,'phase3_test:writerfault'));
end
s=phase3_stream_test_control('read');
assert(s.releases>=1&&isempty(findall(groot,'Type','figure','Name','3AFC 閾値測定')));
% An explicit absent device must never silently select the internal speaker.
try
    phase3_afc_threshold('stimulus','click','max_level_dbfs',-2, ...
        'dev_id','absent device','save',false,'verbose',false);
    error('phase3_test:expected','Expected absent-device error.');
catch ME
    assert(strcmp(ME.identifier,'resolve_audio_device:notfound'),'Unexpected %s',ME.identifier);
end
% Several outputs without dev_id must stop instead of guessing one.
try
    phase3_afc_threshold('stimulus','click','max_level_dbfs',-2, ...
        'save',false,'verbose',false);
    error('phase3_test:expected','Expected ambiguous-device error.');
catch ME
    assert(strcmp(ME.identifier,'resolve_audio_device:ambiguous'),'Unexpected %s',ME.identifier);
end
fprintf('phase3_afc_hardware_selftest: PASS\n');
end
function T=run_case(kind,mode,production)
phase3_stream_test_control('reset'); phase3_stream_test_control('real',production);
injected=false; starts=0; seen=[];
phase3_stream_test_control('hook',@respond);
if strcmp(mode,'prime_exhaust'), phase3_stream_test_control('script',ones(1,200)); end
if strcmp(mode,'incomplete_exhaust'), phase3_stream_test_control('premature',0.65); end
watchdog=timer('StartDelay',120,'TimerFcn',@(~,~) cancel_ui());
start(watchdog); guard=onCleanup(@() stop_timer(watchdog));
maxlevel=-2; if strcmp(kind,'noise'), maxlevel=-20; end
T=phase3_afc_threshold('stimulus',kind,'max_level_dbfs',maxlevel,'save',false, ...
    'verbose',false,'seed',33,'n_practice',1,'n_runs',1,'n_runs_max',1, ...
    'n_reversals',4,'n_reversals_avg',2,'step_change_at_rev',2, ...
    'feedback_ms',0,'on_interrupt','record','dev_id','Test interface');
phase3_stream_test_control('hook',[]);
if ismember(mode,{'normal','retry','retry_cue'}), assert(all(ismember(1:3,seen))); end
    function respond(event)
        fig=findall(groot,'Type','figure','Name','3AFC 閾値測定');
        assert(isscalar(fig)); t=fig.UserData.active_trial;
        if isfield(fig.UserData,'active_interval')&&fig.UserData.active_interval>0
            k=fig.UserData.active_interval; boxes=findall(fig,'Type','rectangle');
            blue=arrayfun(@(b) isequal(b.FaceColor,[0.30 0.70 1.00]),boxes);
            assert(sum(blue)==1&&abs(boxes(blue).Position(1)-(k-0.9))<1e-12);
            seen(end+1)=k;
        end
        if strcmp(event.name,'start')
            starts=starts+1; s=phase3_stream_test_control('read');
            if strcmp(mode,'fault'), error('phase3_test:writerfault','Deliberate unknown native fault.'); end
            if strcmp(mode,'exhaust')||(strcmp(mode,'retry')&&strcmp(t.phase,'staircase')&&~injected)
                u=zeros(1,s.reads+5); u(end)=1024;
                phase3_stream_test_control('script',u); injected=true;
            end
            if strcmp(t.phase,'ascend')
                key='n'; if t.level_dbfs>=-80, key='y'; end
                other='y'; if strcmp(key,'y'), other='n'; end
            else
                choice=t.target; if t.level_dbfs<-80, choice=mod(choice,3)+1; end
                key=num2str(choice); other=num2str(mod(choice,3)+1);
            end
            fig.KeyPressFcn(fig,struct('Key',key)); saved=fig.UserData.resp;
            fig.KeyPressFcn(fig,struct('Key',other));
            assert(isequal(fig.UserData.resp,saved),'Retain the first early response.');
        elseif strcmp(event.name,'write')&&starts>0&&ismember(mode, ...
                {'keyboard_x','escape','close','close_then_escape','escape_then_close','keyboard_x_then_escape'})
            if startsWith(mode,'close')
                close(fig);
            elseif startsWith(mode,'escape')
                fig.KeyPressFcn(fig,struct('Key','escape'));
            else
                fig.KeyPressFcn(fig,struct('Key','X'));
            end
            assert(isgraphics(fig)&&fig.UserData.abort,'The requested cancellation key/button did not work.');
            if endsWith(mode,'then_escape'), fig.KeyPressFcn(fig,struct('Key','escape')); end
            if endsWith(mode,'then_close'), close(fig); end
        elseif strcmp(event.name,'read')&&strcmp(mode,'retry_cue') ...
                &&strcmp(t.phase,'staircase')&&~injected
            s=phase3_stream_test_control('read');
            if s.now-event.player.StartTime>1.21&&fig.UserData.active_interval==1
                phase3_stream_test_control('advance',0.30); injected=true;
            end
        end
    end
end
function cancel_ui
fig=findall(groot,'Type','figure','Name','3AFC 閾値測定');
if ~isempty(fig), close(fig); end
end
function stop_timer(t)
stop(t); delete(t);
end
function finish(fixture,writerfixture)
phase3_stream_test_control('reset');
fig=findall(groot,'Type','figure','Name','3AFC 閾値測定'); delete(fig);
rmpath(fixture); rmpath(writerfixture);
end
