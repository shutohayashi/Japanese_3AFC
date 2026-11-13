function P = provenance_meta()
%PROVENANCE_META Record one timestamp and the software provenance for a saved result.

tnow = datetime('now');
[commit, dirty] = code_version();

P = struct();
P.timestamp   = char(tnow, 'yyyy-MM-dd HH:mm:ss');
P.stamp       = char(tnow, 'yyyyMMdd_HHmmss');
P.code_commit = commit;
P.code_dirty  = dirty;
P.matlab_ver  = version;
P.host        = host_name();
end
