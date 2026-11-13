function h = host_name()
%HOST_NAME Return the local host name when it is available.

h = getenv('COMPUTERNAME');                 % Windows
if isempty(h), h = getenv('HOSTNAME'); end  % macOS / Linux
if isempty(h)
    try
        [st, out] = system('hostname');
        if st == 0, h = strtrim(out); end
    catch
        h = '';                             % 取得できないだけ。保存は止めない
    end
end
end
