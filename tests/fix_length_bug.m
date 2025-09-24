% FIX_LENGTH_BUG - Find and fix the LENGTH() bug in NanionDataExtractor
fprintf('=== FINDING LENGTH BUG ===\n');

% Search for LENGTH usage in the file
extractorFile = 'analysis/NanionDataExtractor.m';

if ~exist(extractorFile, 'file')
    fprintf('❌ File not found: %s\n', extractorFile);
    return;
end

fprintf('Searching for LENGTH usage in: %s\n', extractorFile);

% Read file and search for LENGTH
fid = fopen(extractorFile, 'r');
lines = {};
while ~feof(fid)
    lines{end+1} = fgetl(fid);
end
fclose(fid);

% Search for LENGTH calls
length_lines = {};
for i = 1:length(lines)
    line = lines{i};
    if ischar(line)
        % Look for LENGTH (case insensitive)
        if contains(upper(line), 'LENGTH(') && ~contains(line, '%') % Skip comments
            length_lines{end+1} = struct('lineNum', i, 'content', line);
            fprintf('Line %d: %s\n', i, strtrim(line));
        end
    end
end

if isempty(length_lines)
    fprintf('⚠️  No explicit LENGTH() calls found in NanionDataExtractor.m\n');
    fprintf('The error might be in a called function or indirect usage.\n\n');
    
    % Check for other potential issues
    fprintf('Checking for other table-related functions that might cause issues:\n');
    
    potential_issues = {'length', 'LENGTH', 'size', 'numel'};
    for i = 1:length(potential_issues)
        func_name = potential_issues{i};
        found_lines = {};
        
        for j = 1:length(lines)
            line = lines{j};
            if ischar(line) && contains(line, func_name) && ~startsWith(strtrim(line), '%')
                found_lines{end+1} = struct('lineNum', j, 'content', line);
            end
        end
        
        if ~isempty(found_lines)
            fprintf('\n%s usage:\n', func_name);
            for j = 1:length(found_lines)
                fprintf('  Line %d: %s\n', found_lines{j}.lineNum, strtrim(found_lines{j}.content));
            end
        end
    end
    
else
    fprintf('\nFound %d LENGTH() calls that need fixing:\n', length(length_lines));
    
    % Show recommended fixes
    fprintf('\n🔧 RECOMMENDED FIXES:\n');
    for i = 1:length(length_lines)
        line_info = length_lines{i};
        line_content = strtrim(line_info.content);
        
        fprintf('Line %d: %s\n', line_info.lineNum, line_content);
        
        % Suggest replacement
        if contains(line_content, 'length(') || contains(line_content, 'LENGTH(')
            % For tables, suggest height() or size()
            suggested = strrep(strrep(line_content, 'LENGTH(', 'height('), 'length(', 'height(');
            fprintf('  Fix: %s\n', suggested);
        end
        fprintf('\n');
    end
end

% Create corrected version
fprintf('=== CREATING CORRECTED VERSION ===\n');

% Common fixes for MATLAB 2025a table compatibility
corrected_lines = lines;
fixes_made = 0;

for i = 1:length(corrected_lines)
    line = corrected_lines{i};
    if ischar(line)
        original_line = line;
        
        % Fix LENGTH() calls on tables
        if contains(upper(line), 'LENGTH(') && ~startsWith(strtrim(line), '%')
            % Replace LENGTH with size or height depending on context
            if contains(line, 'dataRows') || contains(line, 'table') || contains(line, 'Table')
                line = regexprep(line, '\bLENGTH\(', 'height(', 'ignorecase');
                line = regexprep(line, '\blength\(', 'height(', 'ignorecase');
            else
                line = regexprep(line, '\bLENGTH\(', 'length(', 'ignorecase');
            end
        end
        
        % Fix other potential table issues
        if contains(line, 'size(') && contains(line, 'dataRows') && contains(line, ', 1)')
            % size(dataRows, 1) should become height(dataRows) for tables
            line = regexprep(line, 'size\(([^,]+),\s*1\)', 'height($1)');
        end
        
        if ~strcmp(original_line, line)
            corrected_lines{i} = line;
            fixes_made = fixes_made + 1;
            fprintf('Fixed line %d:\n', i);
            fprintf('  Before: %s\n', strtrim(original_line));
            fprintf('  After:  %s\n', strtrim(line));
        end
    end
end

if fixes_made > 0
    fprintf('\n✅ Made %d fixes\n', fixes_made);
    
    % Write corrected file
    backup_file = 'analysis/NanionDataExtractor_backup.m';
    corrected_file = 'analysis/NanionDataExtractor_fixed.m';
    
    % Create backup
    copyfile(extractorFile, backup_file);
    fprintf('✅ Backup created: %s\n', backup_file);
    
    % Write corrected version
    fid = fopen(corrected_file, 'w');
    for i = 1:length(corrected_lines)
        if ischar(corrected_lines{i})
            fprintf(fid, '%s\n', corrected_lines{i});
        end
    end
    fclose(fid);
    
    fprintf('✅ Corrected version created: %s\n', corrected_file);
    fprintf('\n🔧 To apply fix:\n');
    fprintf('   1. Check the corrected version: edit(''%s'')\n', corrected_file);
    fprintf('   2. If it looks good, replace original:\n');
    fprintf('      copyfile(''%s'', ''%s'')\n', corrected_file, extractorFile);
    fprintf('   3. Clear classes and test again:\n');
    fprintf('      clear classes; correct_phase2_test\n');
    
else
    fprintf('⚠️  No obvious LENGTH() fixes found in the file\n');
    fprintf('The error might be coming from a different source.\n\n');
    
    fprintf('🔍 DEBUG SUGGESTIONS:\n');
    fprintf('1. The error might be in a called function\n');
    fprintf('2. Try adding debug output to pinpoint the exact location\n');
    fprintf('3. Check if the issue is in convertToNumeric or extractAndConvert methods\n');
end