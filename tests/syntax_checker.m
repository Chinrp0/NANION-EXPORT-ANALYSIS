% SYNTAX_CHECKER - Find syntax errors in NanionAnalysisPipeline
fprintf('=== MATLAB SYNTAX ERROR DETECTOR ===\n');

pipelineFile = 'pipeline/NanionAnalysisPipeline.m';

if ~exist(pipelineFile, 'file')
    pipelineFile = 'NanionAnalysisPipeline.m'; % If running from tests directory
end

fprintf('Checking file: %s\n', which(pipelineFile));

% Method 1: Try to parse with mlint (if available)
try
    if exist('mlint', 'file')
        fprintf('\n=== MLINT ANALYSIS ===\n');
        mlinttxt = mlint(pipelineFile);
        if isempty(mlinttxt)
            fprintf('✓ No mlint warnings found\n');
        else
            fprintf('⚠️  MLint warnings:\n%s\n', mlinttxt);
        end
    end
catch
    fprintf('MLint not available\n');
end

% Method 2: Check for common syntax issues
fprintf('\n=== COMMON SYNTAX CHECKS ===\n');

fid = fopen(pipelineFile, 'r');
if fid < 0
    fprintf('❌ Cannot open file\n');
    return;
end

lines = {};
while ~feof(fid)
    lines{end+1} = fgetl(fid);
end
fclose(fid);

% Check for unmatched brackets/parens
openParens = 0;
openBrackets = 0;
openBraces = 0;
inString = false;
stringChar = '';

for i = 1:length(lines)
    line = lines{i};
    if ischar(line)
        for j = 1:length(line)
            char = line(j);
            
            % Handle strings
            if (char == '"' || char == '''') && ~inString
                inString = true;
                stringChar = char;
            elseif char == stringChar && inString
                inString = false;
                stringChar = '';
            elseif ~inString
                switch char
                    case '('
                        openParens = openParens + 1;
                    case ')'
                        openParens = openParens - 1;
                    case '['
                        openBrackets = openBrackets + 1;
                    case ']'
                        openBrackets = openBrackets - 1;
                    case '{'
                        openBraces = openBraces + 1;
                    case '}'
                        openBraces = openBraces - 1;
                end
                
                % Check for negative counts (closing without opening)
                if openParens < 0
                    fprintf('❌ Line %d: Extra closing parenthesis\n', i);
                    fprintf('   %s\n', line);
                end
                if openBrackets < 0
                    fprintf('❌ Line %d: Extra closing bracket\n', i);
                    fprintf('   %s\n', line);
                end
                if openBraces < 0
                    fprintf('❌ Line %d: Extra closing brace\n', i);
                    fprintf('   %s\n', line);
                end
            end
        end
    end
end

% Final bracket counts
if openParens ~= 0
    fprintf('❌ Unmatched parentheses: %d open\n', openParens);
end
if openBrackets ~= 0
    fprintf('❌ Unmatched brackets: %d open\n', openBrackets);
end
if openBraces ~= 0
    fprintf('❌ Unmatched braces: %d open\n', openBraces);
end

if openParens == 0 && openBrackets == 0 && openBraces == 0
    fprintf('✓ All brackets/parentheses matched\n');
end

% Check for method/end matching
fprintf('\n=== METHOD/END MATCHING ===\n');
methodCount = 0;
endCount = 0;
classDef = false;

for i = 1:length(lines)
    line = strtrim(lines{i});
    if ischar(line)
        % Skip comments and empty lines
        if isempty(line) || startsWith(line, '%')
            continue;
        end
        
        if startsWith(line, 'classdef')
            classDef = true;
            fprintf('Line %d: Found classdef\n', i);
        elseif contains(line, 'function ') && ~contains(line, '%')
            methodCount = methodCount + 1;
            fprintf('Line %d: Method %d found\n', i, methodCount);
        elseif strcmp(line, 'end') || endsWith(line, 'end')
            endCount = endCount + 1;
        end
    end
end

fprintf('Methods found: %d\n', methodCount);
fprintf('End statements: %d\n', endCount);

if ~classDef
    fprintf('❌ No classdef found!\n');
else
    fprintf('✓ Classdef found\n');
end

% Method 3: Try to check dependencies
fprintf('\n=== DEPENDENCY CHECK ===\n');
requiredClasses = {'NanionConfig', 'NanionLogger', 'NanionIOManager', ...
                   'NanionFileDetector', 'NanionDataExtractor'};

for i = 1:length(requiredClasses)
    className = requiredClasses{i};
    if exist(className, 'class')
        fprintf('✓ %s found\n', className);
    else
        fprintf('❌ %s NOT found\n', className);
    end
end

% Method 4: Try to evaluate just the class header
fprintf('\n=== SIMPLE LOAD TEST ===\n');
try
    % Clear everything
    clear classes
    
    % Try to load the specific class
    meta = ?NanionAnalysisPipeline;
    fprintf('✓ Class loaded successfully\n');
    fprintf('Properties found: %d\n', length(meta.PropertyList));
    for i = 1:length(meta.PropertyList)
        fprintf('  %s\n', meta.PropertyList(i).Name);
    end
    
catch ME
    fprintf('❌ Class loading failed:\n');
    fprintf('Error: %s\n', ME.message);
    fprintf('Identifier: %s\n', ME.identifier);
    if ~isempty(ME.cause)
        for i = 1:length(ME.cause)
            fprintf('Cause %d: %s\n', i, ME.cause{i}.message);
        end
    end
end