function test=phase3_test_flag(value)
%PHASE3_TEST_FLAG Missing legacy flags mean formal; malformed flags never do.
if isstruct(value)
    if ~isscalar(value), error('phase3_test_flag:value','Expected one record.'); end
    if ~isfield(value,'test'), test=false; return, end
    value=value.test;
end
if ~(islogical(value)||isnumeric(value))||~isscalar(value)||~isreal(value)|| ...
        ~isfinite(value)||~ismember(double(value),[0 1])
    error('phase3_test_flag:value','test must be a logical scalar.');
end
test=logical(value);
end
