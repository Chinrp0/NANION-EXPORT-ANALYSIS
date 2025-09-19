function run_pipeline_interactive()
    %RUN_PIPELINE_INTERACTIVE Run pipeline with file selection dialog
    
    fprintf('=== NANION ANALYSIS PIPELINE ===\n\n');
    
    % Create pipeline
    pipeline = NanionAnalysisPipeline();
    
    % Select files interactively
    [filenames, pathname] = uigetfile(...
        {'*.xlsx;*.xls', 'Excel Files (*.xlsx, *.xls)'}, ...
        'Select Nanion Excel Files for Analysis', ...
        'MultiSelect', 'on');
    
    if isequal(filenames, 0)
        fprintf('No files selected. Analysis cancelled.\n');
        return;
    end
    
    % Convert to cell array if single file
    if ischar(filenames)
        filenames = {filenames};
    end
    
    % Create full file paths
    filePaths = cellfun(@(f) fullfile(pathname, f), filenames, 'UniformOutput', false);
    
    % Select output directory
    outputDir = uigetdir(pathname, 'Select Output Directory');
    if isequal(outputDir, 0)
        outputDir = fullfile(pathname, 'nanion_analysis_output');
        fprintf('Using default output directory: %s\n', outputDir);
    end
    
    % Run the analysis
    fprintf('Starting analysis of %d files...\n', length(filePaths));
    results = pipeline.runAnalysis(filePaths, outputDir);
    
    % Display results summary
    fprintf('\n=== ANALYSIS COMPLETE ===\n');
    successCount = sum(cellfun(@(x) strcmp(x.status, 'success'), results));
    fprintf('Files processed: %d\n', length(results));
    fprintf('Successful: %d\n', successCount);
    fprintf('Failed: %d\n', length(results) - successCount);
    fprintf('Output directory: %s\n', outputDir);
    
    % Open output directory
    if isfolder(outputDir)
        if ispc
            winopen(outputDir);
        end
    end
end