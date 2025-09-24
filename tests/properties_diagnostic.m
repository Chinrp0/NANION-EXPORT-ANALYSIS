% PROPERTIES_DIAGNOSTIC - Find why properties aren't recognized
fprintf('=== PROPERTIES BLOCK DIAGNOSTIC ===\n');

% Step 1: Use metaclass to get detailed info
try
    mc = ?NanionAnalysisPipeline;
    fprintf('✓ Metaclass loaded\n');
    fprintf('Class name: %s\n', mc.Name);
    fprintf('Properties found: %d\n', length(mc.PropertyList));
    fprintf('Methods found: %d\n', length(mc.MethodList));
    
    if length(mc.PropertyList) > 0
        fprintf('Property names:\n');
        for i = 1:length(mc.PropertyList)
            prop = mc.PropertyList(i);
            fprintf('  %s (Access: %s)\n', prop.Name, prop.GetAccess);
        end
    else
        fprintf('❌ No properties found in metaclass either!\n');
    end
    
catch ME
    fprintf('❌ Metaclass failed: %s\n', ME.message);
end

% Step 2: Read the file and check properties block specifically
fprintf('\nStep 2: Analyzing properties block in file...\n');
pipelineFile = 'pipeline/NanionAnalysisPipeline.m';

fid = fopen(pipelineFile, 'r');
if fid < 0
    fprintf('❌ Cannot open file\n');
    return;
end

lineNum = 0;
inPropertiesBlock = false;
propertiesFound = {};
indentLevel = 0;

while ~feof(fid)
    lineNum = lineNum + 1;
    line = fgetl(fid);
    
    if ~ischar(line)
        break;
    end
    
    trimmedLine = strtrim(line);
    
    % Skip comments and empty lines for analysis
    if isempty(trimmedLine) || startsWith(trimmedLine, '%')
        if lineNum <= 50  % Show first 50 lines for context
            fprintf('%3d: %s\n', lineNum, line);
        end
        continue;
    end
    
    % Look for properties block
    if contains(trimmedLine, 'properties')
        inPropertiesBlock = true;
        fprintf('%3d: %s ← PROPERTIES BLOCK START\n', lineNum, line);
        continue;
    end
    
    % Look for end of properties block
    if inPropertiesBlock && strcmp(trimmedLine, 'end')
        inPropertiesBlock = false;
        fprintf('%3d: %s ← PROPERTIES BLOCK END\n', lineNum, line);
        continue;
    end
    
    % Collect property names
    if inPropertiesBlock
        % Remove comments from the line to get property name
        propLine = trimmedLine;
        commentIndex = strfind(propLine, '%');
        if ~isempty(commentIndex)
            propLine = strtrim(propLine(1:commentIndex(1)-1));
        end
        
        if ~isempty(propLine)
            propertiesFound{end+1} = propLine;
            fprintf('%3d: %s ← PROPERTY\n', lineNum, line);
        end
    elseif lineNum <= 50
        fprintf('%3d: %s\n', lineNum, line);
    end
end

fclose(fid);

fprintf('\nProperties found in file: %d\n', length(propertiesFound));
for i = 1:length(propertiesFound)
    fprintf('  %d: %s\n', i, propertiesFound{i});
end

% Step 3: Check for common syntax errors around properties
fprintf('\nStep 3: Checking for syntax errors...\n');

% Re-read file to check syntax around properties block
fid = fopen(pipelineFile, 'r');
allLines = {};
while ~feof(fid)
    allLines{end+1} = fgetl(fid);
end
fclose(fid);

% Look for the properties line and check surrounding syntax
for i = 1:length(allLines)
    line = allLines{i};
    if ~ischar(line)
        continue;
    end
    
    if contains(line, 'properties')
        fprintf('Found properties block at line %d\n', i);
        
        % Check lines before and after
        startCheck = max(1, i-5);
        endCheck = min(length(allLines), i+15);
        
        fprintf('Context around properties block:\n');
        for j = startCheck:endCheck
            marker = '';
            if j == i
                marker = ' ← PROPERTIES';
            end
            
            contextLine = allLines{j};
            if ~ischar(contextLine)
                contextLine = '[end of file]';
            end
            
            fprintf('%3d: %s%s\n', j, contextLine, marker);
        end
        break;
    end
end

% Step 4: Try a minimal test
fprintf('\nStep 4: Minimal class test...\n');

% Create a minimal test file to see if the issue is syntax-related
testClassContent = {
    'classdef TestMinimal < handle'
    '    properties (Access = private)'
    '        config'
    '        logger'
    '    end'
    '    methods'
    '        function obj = TestMinimal()'
    '            obj.config = [];'
    '        end'
    '    end'
    'end'
};

% Write test file
testFile = 'TestMinimal.m';
fid = fopen(testFile, 'w');
for i = 1:length(testClassContent)
    fprintf(fid, '%s\n', testClassContent{i});
end
fclose(fid);

try
    clear classes
    test = TestMinimal();
    props = properties(test);
    fprintf('✓ Minimal test class works: %d properties\n', length(props));
    for i = 1:length(props)
        fprintf('  %s\n', props{i});
    end
    
    % Clean up
    delete(testFile);
    
catch ME
    fprintf('❌ Even minimal test failed: %s\n', ME.message);
    if exist(testFile, 'file')
        delete(testFile);
    end
end