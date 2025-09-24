% DEBUG_PIPELINE_PROPERTIES - Check what's wrong with the pipeline class
fprintf('=== PIPELINE CLASS DIAGNOSTIC ===\n');

% Check if file exists and inspect its first few lines
pipelineFile = 'pipeline/NanionAnalysisPipeline.m';

if exist(pipelineFile, 'file')
    fprintf('✓ Pipeline file found: %s\n', which(pipelineFile));
    
    % Read first 30 lines to check class definition
    fid = fopen(pipelineFile, 'r');
    fprintf('\nFirst 30 lines of pipeline file:\n');
    fprintf('=' * 50 + "\n");
    
    for i = 1:30
        line = fgetl(fid);
        if line == -1
            break;
        end
        fprintf('%2d: %s\n', i, line);
    end
    fclose(fid);
    
else
    fprintf('❌ Pipeline file not found at: %s\n', pipelineFile);
    fprintf('Current directory: %s\n', pwd);
    fprintf('Files in pipeline/ directory:\n');
    if exist('pipeline', 'dir')
        files = dir('pipeline/*.m');
        for i = 1:length(files)
            fprintf('  %s\n', files(i).name);
        end
    else
        fprintf('  pipeline/ directory not found\n');
    end
end

% Try to clear and reload
fprintf('\n=== RELOAD TEST ===\n');
clear classes
try
    pipeline = NanionAnalysisPipeline();
    props = properties(pipeline);
    if isempty(props)
        fprintf('❌ Pipeline loaded but has no properties (syntax error?)\n');
    else
        fprintf('✓ Pipeline properties:\n');
        for i = 1:length(props)
            fprintf('  %s\n', props{i});
        end
    end
catch ME
    fprintf('❌ Pipeline failed to load: %s\n', ME.message);
    fprintf('Full error:\n%s\n', getReport(ME));
end