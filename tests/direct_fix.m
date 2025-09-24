% DIRECT_FIX - Find and fix the exact LENGTH table error
fprintf('=== DIRECT LENGTH TABLE FIX ===\n');

% The error says "Undefined function 'LENGTH'" - this is happening in the DataExtractor
% Let's look at the specific lines that could cause this

extractorFile = fullfile('analysis', 'NanionDataExtractor.m');

if ~exist(extractorFile, 'file')
    fprintf('❌ File not found: %s\n', extractorFile);
    fprintf('Current directory: %s\n', pwd);
    fprintf('Looking for alternative locations...\n');
    
    alternatives = {
        'NanionDataExtractor.m',
        fullfile('SRC', 'analysis', 'NanionDataExtractor.m'),
        fullfile('..', 'SRC', 'analysis', 'NanionDataExtractor.m')
    };
    
    for i = 1:length(alternatives)
        if exist(alternatives{i}, 'file')
            extractorFile = alternatives{i};
            fprintf('✅ Found at: %s\n', extractorFile);
            break;
        end
    end
    
    if ~exist(extractorFile, 'file')
        fprintf('❌ Cannot find NanionDataExtractor.m\n');
        return;
    end
end

fprintf('Reading file: %s\n', extractorFile);

% Read the entire file
fid = fopen(extractorFile, 'r');
fileContent = fread(fid, '*char')';
fclose(fid);

% Split into lines
lines = strsplit(fileContent, '\n');

% Find the problematic lines - the error occurs in measurement extraction
% Look for length() calls that could be getting table inputs

fprintf('\n=== ANALYZING LENGTH CALLS ===\n');

problematic_patterns = {
    'length(wellIDs)',        % wellIDs might be table column
    'length(qualityMask)',    % qualityMask might be table  
    'length(rawData)',        % rawData might be table
    'length(dataRows)',       % dataRows is definitely a table
    'length(ivFields)',       % ivFields might be table
    'length(paramFields)'     % paramFields might be table
};

fixes_to_apply = {};

for i = 1:length(lines)
    line = lines{i};
    
    % Skip comment lines
    if startsWith(strtrim(line), '%')
        continue;
    end
    
    % Check each problematic pattern
    for j = 1:length(problematic_patterns)
        pattern = problematic_patterns{j};
        
        if contains(line, pattern)
            fprintf('Line %d: %s\n', i, strtrim(line));
            
            % Determine the appropriate fix based on the variable
            if contains(pattern, 'wellIDs') || contains(pattern, 'qualityMask')
                % These should be arrays, use length()
                % But make sure they're extracted as arrays, not table columns
                suggested_fix = line; % Keep as is, but ensure proper extraction
                fprintf('  → Keeping length(), but ensure %s is array not table\n', pattern);
                
            elseif contains(pattern, 'dataRows') || contains(pattern, 'rawData')
                % These are tables, use height()
                suggested_fix = strrep(line, pattern, strrep(pattern, 'length(', 'height('));
                fprintf('  → Fix: %s\n', strtrim(suggested_fix));
                fixes_to_apply{end+1} = struct('lineNum', i, 'original', line, 'fixed', suggested_fix);
                
            elseif contains(pattern, 'Fields')
                % fieldnames() returns cell array, length() is correct
                fprintf('  → Keeping length() for cell array\n');
            end
        end
    end
end

% Also check for the specific extraction methods that might be causing issues
fprintf('\n=== CHECKING EXTRACTION METHODS ===\n');

% The error happens during "Extracting measurements" - let's look at those specific functions
key_methods = {'extractByProtocol', 'extractActivationMeasurements', 'extractInactivationMeasurements', 'convertToNumeric'};

for i = 1:length(key_methods)
    method_name = key_methods{i};
    fprintf('\nAnalyzing method: %s\n', method_name);
    
    % Find the method
    in_method = false;
    method_start = 0;
    
    for j = 1:length(lines)
        line = lines{j};
        
        if contains(line, ['function ' method_name]) || contains(line, ['function obj = ' method_name])
            in_method = true;
            method_start = j;
            fprintf('  Found at line %d\n', j);
            continue;
        end
        
        if in_method && contains(strtrim(line), 'end') && ~contains(line, '%')
            % Check if this is the end of our method (rough heuristic)
            indent_level = length(line) - length(ltrim(line));
            if indent_level <= 8  % Assuming method ends with minimal indentation
                fprintf('  Method ends around line %d\n', j);
                break;
            end
        end
        
        if in_method && contains(line, 'length(')
            fprintf('  Line %d: %s\n', j, strtrim(line));
        end
    end
end

% Apply fixes
if ~isempty(fixes_to_apply)
    fprintf('\n=== APPLYING FIXES ===\n');
    
    % Create backup
    timestamp = datestr(now, 'yyyymmdd_HHMMSS');
    backupFile = strrep(extractorFile, '.m', ['_backup_' timestamp '.m']);
    copyfile(extractorFile, backupFile);
    fprintf('✅ Backup created: %s\n', backupFile);
    
    % Apply fixes
    modified_lines = lines;
    for i = 1:length(fixes_to_apply)
        fix = fixes_to_apply{i};
        modified_lines{fix.lineNum} = fix.fixed;
        fprintf('Applied fix to line %d\n', fix.lineNum);
    end
    
    % Write fixed file
    fid = fopen(extractorFile, 'w');
    for i = 1:length(modified_lines)
        fprintf(fid, '%s\n', modified_lines{i});
    end
    fclose(fid);
    
    fprintf('✅ Applied %d fixes\n', length(fixes_to_apply));
    
else
    fprintf('\n⚠️  No automatic fixes identified\n');
    fprintf('The issue might be more subtle - table columns being treated as tables\n');
    
    % Show specific suggestions
    fprintf('\n🔧 MANUAL FIX REQUIRED:\n');
    fprintf('The error occurs during measurement extraction.\n');
    fprintf('Look for these specific lines in extractByProtocol():\n\n');
    
    fprintf('1. Find: numDataRows = size(dataRows, 1);\n');
    fprintf('   Replace: numDataRows = height(dataRows);\n\n');
    
    fprintf('2. Find: for i = 1:length(rawData)\n');  
    fprintf('   Replace: for i = 1:height(rawData)\n\n');
    
    fprintf('3. Check wellIDs extraction - ensure it returns string array, not table column\n');
    
end

fprintf('\n🔧 After applying fixes, test with:\n');
fprintf('clear classes; correct_phase2_test\n');