function result=phase3_stream_test_control(action,value)
% Own the deterministic native/test clock without production UI test options.
persistent s
if isempty(s)||strcmp(action,'reset')
    s=struct('now',0,'reads',0,'waits',0,'prime_waits',0,'script',[],'frames',{{}},'hook',[], ...
        'releases',0,'stops',0,'stall',false,'premature',Inf,'real_stream',[]);
end
switch action
    case {'reset','read'}
    case 'advance', s.now=s.now+value;
    case 'wait', s.waits=s.waits+1; s.now=s.now+value;
    case 'prime_wait', s.prime_waits=s.prime_waits+1; s.now=s.now+value;
    case 'script', s.script=value;
    case 'stall', s.stall=value;
    case 'premature', s.premature=value;
    case 'hook', s.hook=value;
    case 'real', s.real_stream=value;
    case 'capture', s.frames{end+1}=value;
    case 'release', s.releases=s.releases+1;
    case 'stop', s.stops=s.stops+1;
    case 'event'
        if ~isempty(s.hook), s.hook(value); end
    case 'underrun'
        s.reads=s.reads+1;
        if ~isempty(s.hook), s.hook(struct('name','read','player',value,'read',s.reads)); end
        result=0;
        if s.reads<=numel(s.script), result=s.script(s.reads); end
        return
    otherwise, error('phase3_test:streamcontrol','Unknown control action.');
end
result=s;
end
