classdef audiostreamer < handle
    % Silent fake native queue; clock advances explicitly in transport tests.
    properties
        Mode='player'
        SampleRate=96000
        Driver='ASIO'
        Player='Test interface'
        DeviceBitFormat='int24'
        DeviceBufferSize=2048
        PlayerChannels=[1 2]
        Queued=0
        StartTime=0
        Running=false
    end
    properties (Dependent)
        NumPlayerSamples
    end
    methods
        function obj=audiostreamer(mode,fs)
            obj.Mode=mode; obj.SampleRate=fs;
        end
        function n=get.NumPlayerSamples(obj)
            played=0;
            if obj.Running
                s=phase3_stream_test_control('read');
                played=floor((s.now-obj.StartTime)*obj.SampleRate);
            end
            n=max(0,obj.Queued-played);
            if obj.Running&&n==0
                phase3_stream_test_control('event',struct('name','queue_empty','player',obj));
            end
        end
        function write(obj,x,~)
            obj.Queued=obj.Queued+size(x,1);
            phase3_stream_test_control('capture',x);
            phase3_stream_test_control('event',struct('name','write','player',obj,'samples',size(x,1)));
        end
        function start(obj)
            s=phase3_stream_test_control('read'); obj.StartTime=s.now; obj.Running=true;
            phase3_stream_test_control('event',struct('name','start','player',obj));
        end
        function yes=isPlaying(obj)
            s=phase3_stream_test_control('read');
            yes=obj.Running&&(obj.NumPlayerSamples>0||s.stall);
            if s.now-obj.StartTime>=s.premature, yes=false; end
        end
        function u=getUnderrunCount(obj)
            u=0;
            if obj.Running, u=phase3_stream_test_control('underrun',obj); end
        end
        function stop(obj)
            obj.Queued=0; obj.Running=false;
            phase3_stream_test_control('stop');
        end
        function release(obj)
            obj.Queued=0; obj.Running=false;
            phase3_stream_test_control('release');
        end
    end
    methods (Static)
        function names=getPlayerNames(~)
            names={'Test interface','Realtek test'};
        end
    end
end
