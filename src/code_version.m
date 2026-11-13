function [commit, dirty] = code_version()
%CODE_VERSION Read Git provenance without blocking result saving.

repodir = fileparts(fileparts(mfilename('fullpath')));
commit = 'unknown'; dirty = false;
if ~isfolder(fullfile(repodir,'.git')) && ~isfile(fullfile(repodir,'.git')), return; end
try
    [st, out] = system(sprintf('git -C "%s" rev-parse HEAD', repodir));
    if st==0, commit = strtrim(out); end
    [st2, out2] = system(sprintf('git -C "%s" status --porcelain', repodir));
    if st2==0, dirty = ~isempty(strtrim(out2)); end
catch
    % git 不在等は再現性メモが 'unknown' になるだけ (保存は止めない)
end
end
