function s = safe_name(v)
%SAFE_NAME Replace whitespace in participant codes used for result filenames.
s = regexprep(char(v), '\s', '_');
end
