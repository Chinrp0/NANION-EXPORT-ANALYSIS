% SIMPLE_SYNTAX_CHECK - Find the syntax error in pipeline
fprintf('=== SIMPLE PIPELINE SYNTAX CHECK ===\n');

% Step 1: Try to get the exact error
fprintf('Step 1: Testing class loading...\n');
clear classes

try
    % Try to instantiate and see the exact error
    pipeline = NanionAnalysisPipeline();
    fprintf('✓ Pipeline created successfully\n');
    
    % Check properties
    props = properties(pipeline);
    fprintf('Properties found: %d\n', length(props));
    for i = 1:length(props)
        fprintf('  %s\n', props{i});
    end
    
catch ME
    fprintf('❌ Pipeline creation failed\n');
    fprintf('Error: %s\n', ME.message);
    fprintf('Location: %s (line %d)\n', ME.stack(1).file, ME.stack(1).line);
    
    % Show the error context
    if length(ME.stack) > 0
        errorFile = ME.stack(1).file;
        errorLine = ME.stack(1).line;
        
        if exist(errorFile, 'file')
            fprintf('\nError context around line %d:\n', errorLine);
            fid = fopen(errorFile, 'r');
            allLines = {};
            while ~feof(fid)
                allLines{end+1} = fgetl(fid);
            end
            fclose(fid);
            
            % Show lines around the error
            startLine = max(1, errorLine - 3);
            endLine = min(length(allLines), errorLine + 3);
            
            for i = startLine:endLine
                marker = '';
                if i == errorLine
                    marker = ' <<< ERROR';
                end
                fprintf('%3d: %s%s\n', i, allLines{i}, marker);
            end
        end
    end
end

% Step 2: Check dependencies
fprintf('\nStep 2: Checking dependencies...\n');
requiredClasses = {'NanionConfig', 'NanionLogger', 'NanionIOManager', ...
                   'NanionFileDetector', 'NanionDataExtractor'};

missingClasses = {};
for i = 1:length(requiredClasses)
    className = requiredClasses{i};
    try
        eval(['exist(''' className ''', ''class'')']);
        if exist(className, 'class')
            fprintf('✓ %s found\n', className);
        else
            fprintf('❌ %s NOT found\n', className);
            missingClasses{end+1} = className;
        end
    catch
        fprintf('❌ %s NOT found (error loading)\n', className);
        missingClasses{end+1} = className;
    end
end

if ~isempty(missingClasses)
    fprintf('\n🔧 MISSING CLASSES DETECTED!\n');
    fprintf('Missing: %s\n', strjoin(missingClasses, ', '));
    fprintf('Solution: Make sure all SRC subdirectories are on the path:\n');
    fprintf('  addpath(''analysis'')\n');
    fprintf('  addpath(''config'')\n');
    fprintf('  addpath(''io'')\n');
    fprintf('  addpath(''utils'')\n');
end

% Step 3: Check current directory and paths
fprintf('\nStep 3: Path diagnostics...\n');
fprintf('Current directory: %s\n', pwd);
fprintf('Pipeline file location: %s\n', which('NanionAnalysisPipeline'));

% Check if all required directories exist
requiredDirs = {'analysis', 'config', 'io', 'utils', 'pipeline'};
for i = 1:length(requiredDirs)
    dirName = requiredDirs{i};
    if exist(dirName, 'dir')
        fprintf('✓ Directory exists: %s\n', dirName);
    else
        fprintf('❌ Directory missing: %s\n', dirName);
    end
end