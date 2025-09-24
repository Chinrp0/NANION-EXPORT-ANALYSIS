% TARGETED_FIX - Fix the specific table size() issues in DataExtractor
fprintf('=== TARGETED DATAEXTRACTOR FIX ===\n');

% Fix the correct file path
extractorFile = fullfile('analysis', 'NanionDataExtractor.m');

if ~exist(extractorFile, 'file')
    fprintf('❌ File not found: %s\n', extractorFile);
    fprintf('Current directory: %s\n', pwd);
    return;
end

fprintf('Fixing file: %s\n', extractorFile);

% Read the file
fid = fopen(extractorFile, 'r');
if fid < 0
    fprintf('❌ Cannot open file for reading\n');
    return;
end

lines = {};
while ~feof(fid)
    lines{end+1} = fgetl(fid);
end
fclose(fid);

% Apply specific fixes for MATLAB 2025a table compatibility
fixes = {
    % Pattern to find -> Replacement
    'numDataRows = size(dataRows, 1);', 'numDataRows = height(dataRows);';
    'values = NaN(size(dataRows, 1), 1);', 'values = NaN(height(dataRows), 1);';
    'size(dataRows, 1)', 'height(dataRows)';
    'size(dataTable, 1)', 'height(dataTable)';
};

corrected_lines = lines;
fixes_applied = 0;

for i = 1:length(corrected_lines)
    line = corrected_lines{i};
    if ischar(line)
        original_line = line;
        
        % Apply each fix pattern
        for j = 1:size(fixes, 1)
            pattern = fixes{j, 1};
            replacement = fixes{j, 2};
            
            if contains(line, pattern)
                line = strrep(line, pattern, replacement);
                fixes_applied = fixes_applied + 1;
                fprintf('Fix %d - Line %d:\n', fixes_applied, i);
                fprintf('  Before: %s\n', strtrim(original_line));
                fprintf('  After:  %s\n', strtrim(line));
            end
        end
        
        corrected_lines{i} = line;
    end
end

if fixes_applied > 0
    % Create backup with timestamp
    [path, name, ext] = fileparts(extractorFile);
    timestamp = datestr(now, 'yyyymmdd_HHMMSS');
    backupFile = fullfile(path, sprintf('%s_backup_%s%s', name, timestamp, ext));
    
    % Create backup
    try
        copyfile(extractorFile, backupFile);
        fprintf('✅ Backup created: %s\n', backupFile);
    catch ME
        fprintf('⚠️  Backup failed: %s\n', ME.message);
    end
    
    % Write corrected file
    fid = fopen(extractorFile, 'w');
    if fid < 0
        fprintf('❌ Cannot open file for writing\n');
        return;
    end
    
    for i = 1:length(corrected_lines)
        if ischar(corrected_lines{i})
            fprintf(fid, '%s\n', corrected_lines{i});
        end
    end
    fclose(fid);
    
    fprintf('✅ Applied %d fixes to NanionDataExtractor.m\n', fixes_applied);
    fprintf('\n🚀 READY TO TEST!\n');
    fprintf('Run: clear classes; correct_phase2_test\n');
    
else
    fprintf('⚠️  No fixes needed or patterns not found\n');
    fprintf('The error might be elsewhere. Let me check the exact error location.\n');
    
    % Show lines around potential issues
    fprintf('\nChecking lines mentioned in diagnostic:\n');
    problem_lines = [121, 203];
    
    for i = 1:length(problem_lines)
        line_num = problem_lines(i);
        if line_num <= length(lines) && ischar(lines{line_num})
            fprintf('Line %d: %s\n', line_num, lines{line_num});
        end
    end
end

% Additional check for the specific error pattern
fprintf('\n=== SEARCHING FOR TABLE SIZE USAGE ===\n');
for i = 1:length(lines)
    line = lines{i};
    if ischar(line) && contains(line, 'size(') && contains(line, ', 1)')
        fprintf('Line %d: %s\n', i, strtrim(line));
    end
end