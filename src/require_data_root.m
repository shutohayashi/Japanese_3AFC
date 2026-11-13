function require_data_root(outdir, errid)
%REQUIRE_DATA_ROOT Check that the selected results directory already exists and is writable.

if ~exist(outdir, 'dir')
    error(errid, 'Create the results folder first or set outdir to an existing folder: %s', char(outdir));
end

% Probe write access before starting a trial so a bad path cannot lose a measurement.
[~, uniq] = fileparts(tempname);
probe = fullfile(char(outdir), ['.write_probe_' uniq '.tmp']);
fid = fopen(probe, 'w');
if fid < 0
    error(errid, 'Cannot write to the results folder: %s', char(outdir));
end
fclose(fid);
delete(probe);
end
