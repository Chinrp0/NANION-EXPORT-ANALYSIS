function plot_boltzmann_results()
    %PLOT_BOLTZMANN_RESULTS Interactive script to visualize Boltzmann fitting results
    %   Generates Figure 1 (Representative Wells) and Figure 2 (Cell Type Averages)
    
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
    
    % Initialize components
    config = NanionConfig();
    logger = NanionLogger(config);
    summaryFigure = NanionSummaryFigure(config, logger);
    
    % Process each file
    numFiles = length(results);
    
    for i = 1:numFiles
        result = results{i};
        
        % Validate result structure
        if ~isstruct(result) || ~isfield(result, 'fittedData')
            fprintf('Skipping result %d (no fittedData)\n', i);
            continue;
        end
        
        % Check if analysis succeeded
        if isfield(result, 'status') && strcmp(result.status, 'failed')
            fprintf('Skipping result %d (failed analysis)\n', i);
            continue;
        end
        
        % Check for required fields
        if ~isfield(result, 'filteredData') || ~isfield(result, 'summaryTable')
            fprintf('Skipping result %d (missing required data)\n', i);
            continue;
        end
        
        filteredData = result.filteredData;
        fittedData = result.fittedData;
        summaryTable = result.summaryTable;
        
        % Verify we have fitted wells
        if isempty(fittedData.wells)
            fprintf('Skipping result %d (no fitted wells)\n', i);
            continue;
        end
        
        % Create output directory
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
        
        % Generate both summary figures
        try
            [fig1, fig2] = summaryFigure.createSummaryFigures(...
                filteredData, fittedData, summaryTable, plotDir);
            
            fprintf('  ✓ Generated Figure 1: Representative Wells\n');
            fprintf('  ✓ Generated Figure 2: Cell Type Averages\n');
            
            % Display summary statistics
            summary = fittedData.summary;
            fprintf('  Wells: %d Good, %d Acceptable, %d Poor, %d Failed\n', ...
                summary.fitResults.good, summary.fitResults.acceptable, ...
                summary.fitResults.poor, summary.fitResults.failed);
            
            if summary.fitResults.good + summary.fitResults.acceptable > 0
                fprintf('  Mean V½: %.2f ± %.2f mV\n', ...
                    summary.parameterStats.V_mid_mean, ...
                    summary.parameterStats.V_mid_std);
            end
            
            % Get compound group info
            passingMask = strcmp(summaryTable.Fit_Quality, 'Good') | ...
                          strcmp(summaryTable.Fit_Quality, 'Acceptable');
            passingTable = summaryTable(passingMask, :);
            
            if height(passingTable) > 0
                numCellTypes = length(unique(passingTable.Cell_Type));
                numCompounds = length(unique(passingTable.Compound));
                numGroups = height(unique(passingTable(:, {'Cell_Type', 'Compound'})));
                
                fprintf('  Cell Types: %d | Compounds: %d | Groups: %d\n', ...
                    numCellTypes, numCompounds, numGroups);
            end
            
        catch ME
            fprintf('  ✗ Plotting failed: %s\n', ME.message);
            fprintf('     %s\n', ME.stack(1).name);
        end
        
        fprintf('\n');
    end
    
    fprintf('All plots generated successfully!\n');
    
    % Offer to open output directory
    if numFiles == 1 && exist('plotDir', 'var')
        answer = questdlg('Open output folder?', 'Plotting Complete', 'Yes', 'No', 'Yes');
        if strcmp(answer, 'Yes')
            if ispc
                winopen(plotDir);
            elseif ismac
                system(['open "' plotDir '"']);
            else
                system(['xdg-open "' plotDir '"']);
            end
        end
    end
end
