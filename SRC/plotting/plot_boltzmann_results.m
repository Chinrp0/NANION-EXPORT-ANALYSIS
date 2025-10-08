function plot_boltzmann_results()
    %PLOT_BOLTZMANN_RESULTS Interactive script to visualize Boltzmann fitting results
    %   Can plot from existing pipeline results or run fresh analysis
    
    fprintf('=== BOLTZMANN RESULTS PLOTTER ===\n\n');
    
    % Ask user for input method
    choice = questdlg('Choose data source:', ...
        'Boltzmann Plotter', ...
        'Run New Analysis', 'Load Existing Results', 'Run New Analysis');
    
    switch choice
        case 'Run New Analysis'
            results = runNewAnalysis();
        case 'Load Existing Results'
            results = loadExistingResults();
        otherwise
            fprintf('Cancelled.\n');
            return;
    end
    
    if isempty(results)
        fprintf('No results to plot.\n');
        return;
    end
    
    % Generate plots
    generatePlots(results);
    
    fprintf('\n=== PLOTTING COMPLETE ===\n');
end

function results = runNewAnalysis()
    %RUNNEWANALYSIS Run complete pipeline and return results
    
    fprintf('Running new analysis...\n\n');
    
    % Initialize pipeline
    pipeline = NanionAnalysisPipeline();
    
    % Select input file(s)
    [filenames, pathname] = uigetfile(...
        {'*.xlsx;*.xls', 'Excel Files (*.xlsx, *.xls)'}, ...
        'Select Nanion Files', ...
        'MultiSelect', 'on');
    
    if isequal(filenames, 0)
        results = [];
        return;
    end
    
    if ischar(filenames)
        filenames = {filenames};
    end
    
    filePaths = cellfun(@(f) fullfile(pathname, f), filenames, 'UniformOutput', false);
    
    % Select output directory
    outputDir = uigetdir(pathname, 'Select Output Directory');
    if isequal(outputDir, 0)
        outputDir = fullfile(pathname, 'boltzmann_output');
    end
    
    % Run analysis
    fprintf('Processing %d files...\n', length(filePaths));
    results = pipeline.runAnalysis(filePaths, outputDir);
    
    fprintf('Analysis complete!\n\n');
end

function results = loadExistingResults()
    %LOADEXISTINGRESULTS Load results from workspace or .mat file
    
    fprintf('Loading existing results...\n\n');
    
    % Check if results exist in workspace
    if evalin('base', 'exist(''results'', ''var'')')
        answer = questdlg('Found "results" variable in workspace. Use it?', ...
            'Load Results', 'Yes', 'Load from file', 'Yes');
        
        if strcmp(answer, 'Yes')
            results = evalin('base', 'results');
            fprintf('Loaded results from workspace.\n\n');
            return;
        end
    end
    
    % Load from .mat file
    [filename, pathname] = uigetfile('*.mat', 'Select Results MAT File');
    if isequal(filename, 0)
        results = [];
        return;
    end
    
    loadedData = load(fullfile(pathname, filename));
    
    % Find results variable
    if isfield(loadedData, 'results')
        results = loadedData.results;
    else
        % Try to find first cell array that looks like results
        fields = fieldnames(loadedData);
        for i = 1:length(fields)
            if iscell(loadedData.(fields{i}))
                results = loadedData.(fields{i});
                break;
            end
        end
    end
    
    if isempty(results)
        fprintf('No valid results found in file.\n');
    else
        fprintf('Loaded results from file.\n\n');
    end
end

function generatePlots(results)
    %GENERATEPLOTS Create all visualization plots
    
    fprintf('Generating plots...\n\n');
    
    % Initialize plotter
    config = NanionConfig();
    logger = NanionLogger(config);
    plotter = NanionBoltzmannPlotter(config, logger);
    
    % Process each file
    numFiles = length(results);
    
    for i = 1:numFiles
        result = results{i};
        
        % Check if result is valid
        if ~isstruct(result) || ~isfield(result, 'fittedData')
            fprintf('Skipping result %d (no fittedData)\n', i);
            continue;
        end
        
        % Check if result succeeded
        if isfield(result, 'status') && strcmp(result.status, 'failed')
            fprintf('Skipping result %d (failed analysis)\n', i);
            continue;
        end
        
        fittedData = result.fittedData;
        
        % Verify we have fitted wells
        if isempty(fittedData.wells)
            fprintf('Skipping result %d (no fitted wells)\n', i);
            continue;
        end
        
        % Create plots output directory
        if isfield(result, 'outputDir')
            plotDir = fullfile(result.outputDir, 'plots');
        else
            plotDir = fullfile(pwd, 'boltzmann_plots', result.fileName);
        end
        
        if ~exist(plotDir, 'dir')
            mkdir(plotDir);
        end
        
        fprintf('Plotting file %d/%d: %s\n', i, numFiles, result.fileName);
        fprintf('  Output: %s\n', plotDir);
        
        % Generate all plots
        try
            plotter.plotAllResults(fittedData, plotDir, result.fileName);
            
            fprintf('  ✓ Generated %d plot types\n', 4);
            
            % Display summary
            summary = fittedData.summary;
            fprintf('  Wells: %d Good, %d Acceptable, %d Poor, %d Failed\n', ...
                summary.fitResults.good, summary.fitResults.acceptable, ...
                summary.fitResults.poor, summary.fitResults.failed);
            
            if summary.fitResults.good + summary.fitResults.acceptable > 0
                fprintf('  Mean V½: %.2f ± %.2f mV\n', ...
                    summary.parameterStats.V_mid_mean, ...
                    summary.parameterStats.V_mid_std);
            end
            
        catch ME
            fprintf('  ✗ Plotting failed: %s\n', ME.message);
        end
        
        fprintf('\n');
    end
    
    fprintf('All plots generated successfully!\n');
    
    % Offer to open output directory
    if numFiles == 1 && exist('plotDir', 'var')
        answer = questdlg('Open output folder?', 'Plotting Complete', 'Yes', 'No', 'Yes');
        if strcmp(answer, 'Yes') && ispc
            winopen(plotDir);
        end
    end
end
