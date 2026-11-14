classdef audioDeviceWriter < handle
    % Test-only writer: capture fixed frames without opening an audio device.
    properties
        SampleRate = 96000
        BitDepth = '24-bit integer'
        Driver = 'ASIO'
        Device = 'Test writer'
        SupportVariableSizeInput = false
        BufferSize = 4096
    end
    methods
        function obj = audioDeviceWriter(varargin)
            for i = 1:2:numel(varargin)
                obj.(varargin{i}) = varargin{i+1};
            end
        end
        function devices = getAudioDevices(~)
            devices = {'Test writer'};
        end
        function release(~)
            audioDeviceWriter.control('release');
        end
        function varargout = subsref(obj, indexing)
            if strcmp(indexing(1).type, '()')
                audioDeviceWriter.capture('append',indexing(1).subs{1});
                varargout{1} = audioDeviceWriter.control('write');
            else
                [varargout{1:nargout}] = builtin('subsref', obj, indexing);
            end
        end
    end
    methods (Static)
        function result = capture(action,frame)
            persistent frames
            if isempty(frames), frames = {}; end
            switch action
                case 'reset', frames = {};
                case 'append', frames{end+1} = frame;
                case 'read'
                otherwise, error('phase3_test:writer','Unknown capture action.');
            end
            result = frames;
        end
        function result = control(action,value)
            persistent state
            if isempty(state)
                state=struct('underruns',[],'calls',0,'releases',0,'hook',[]);
            end
            switch action
                case 'reset'
                    state=struct('underruns',[],'calls',0,'releases',0,'hook',[]);
                case 'script', state.underruns=value;
                case 'hook', state.hook=value;
                case 'release', state.releases=state.releases+1;
                case 'write'
                    state.calls=state.calls+1;
                    result=0;
                    if state.calls<=numel(state.underruns), result=state.underruns(state.calls); end
                    if ~isempty(state.hook), state.hook(state.calls); end
                    return
                case 'read'
                otherwise, error('phase3_test:writer','Unknown control action.');
            end
            result=state;
        end
    end
end
