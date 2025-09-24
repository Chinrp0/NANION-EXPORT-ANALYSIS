function debug_class_cache()
%DEBUG_CLASS_CACHE Diagnose MATLAB class caching issues

fprintf('=== MATLAB CLASS CACHE DIAGNOSTIC ===\n\n');

% Step 1: Clear everything
fprintf('Step 1: Clearing class cache...\n');
clear classes
clear all
rehash toolboxcache
fprintf('✓ Cache cleared\n');

% Step 2: Check file modification times
fprintf('\nStep 2: File modification check...\n');
pipelineFile = 'pipeline/NanionAnalysisPipeline.m';
if exist(pipelineFile, 'file')
    fileInfo = dir(pipelineFile);
    fprintf('Pipeline file: %s\n', pipelineFile);
    fprintf('Last modified: %s\n', datestr(fileInfo.datenum));
else
    fprintf('❌ Pipeline file not found at: %s\n', pipelineFile);
end

% Step 3: Force reload and inspect
fprintf('\nStep 3: Force class reload...\n');
try
    % Force instantiation to reload class definition
    config = NanionConfig();
    logger = NanionLogger(config);
    
    % This should force reload of NanionAnalysisPipeline
    pipeline = NanionAnalysisPipeline();
    
    % Get current properties
    props = properties(pipeline);
    fprintf('Properties found: %s\n', strjoin(props, ', '));
    
    % Check specifically for dataExtractor
    if ismember('dataExtractor', props)
        fprintf('✓ dataExtractor property found!\n');
        
        % Try to access it
        if ~isempty(pipeline.dataExtractor)
            fprintf('✓ dataExtractor is initialized\n');
        else
            fprintf('⚠️  dataExtractor property exists but is empty\n');
        end
    else
        fprintf('❌ dataExtractor property still missing\n');
        fprintf('This indicates the file changes are not being loaded\n');
    end
    
catch ME
    fprintf('❌ Class instantiation failed: %s\n', ME.message);
end

% Step 4: Direct file content check
fprintf('\nStep 4: Direct file inspection...\n');
try
    fid = fopen('pipeline/NanionAnalysisPipeline.m', 'r');
    if fid > 0
        content = fread(fid, '*char')';
        fclose(fid);
        
        if contains(content, 'dataExtractor')
            fprintf('✓ File contains "dataExtractor" text\n');
            
            % Count occurrences
            occurrences = length(strfind(content, 'dataExtractor'));
            fprintf('Found %d occurrences of "dataExtractor"\n', occurrences);
        else
            fprintf('❌ File does NOT contain "dataExtractor" text\n');
            fprintf('The file modifications were not saved!\n');
        end
    else
        fprintf('❌ Could not open pipeline file\n');
    end
catch
    fprintf('❌ File inspection failed\n');
end

fprintf('\n=== RECOMMENDATION ===\n');
fprintf('If dataExtractor is missing after cache clear:\n');
fprintf('1. Open NanionAnalysisPipeline.m in editor\n');
fprintf('2. Verify the dataExtractor property and initialization are there\n');
fprintf('3. Save the file again (Ctrl+S)\n');
fprintf('4. Run: clear classes; clear all\n');
fprintf('5. Test again\n');

end