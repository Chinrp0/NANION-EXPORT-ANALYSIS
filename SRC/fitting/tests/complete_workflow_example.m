%% COMPLETE WORKFLOW EXAMPLE
% This script demonstrates the complete Boltzmann fitting and plotting workflow
% From raw data → analysis → fitting → visualization

%% STEP 1: Initialize Pipeline
fprintf('=== NANION BOLTZMANN ANALYSIS WORKFLOW ===\n\n');

% Create pipeline with default config
pipeline = NanionAnalysisPipeline();

fprintf('✓ Pipeline initialized\n\n');

%% STEP 2: Configure Analysis (Optional)
% Uncomment to customize parameters

% config = NanionConfig();
% config.updateParameter('boltzmann', 'minValidPoints', 19);
% config.updateParameter('boltzmann', 'corrThreshold', 0.95);
% pipeline = NanionAnalysisPipeline();  % Reinitialize with new config

%% STEP 3: Select Input Files
[filenames, pathname] = uigetfile(...
    {'*.xlsx;*.xls', 'Excel Files (*.xlsx, *.xls)'}, ...
    'Select Nanion Files for Analysis', ...
    'MultiSelect', 'on');

if isequal(filenames, 0)
    fprintf('No files selected. Workflow cancelled.\n');
    return;
end

if ischar(filenames)
    filenames = {filenames};
end

filePaths = cellfun(@(f) fullfile(pathname, f), filenames, 'UniformOutput', false);

fprintf('Selected %d file(s) for analysis:\n', length(filePaths));
for i = 1:length(filePaths)
    [~, fname, ext] = fileparts(filePaths{i});
    fprintf('  %d. %s%s\n', i, fname, ext);
end
fprintf('\n');

%% STEP 4: Select Output Directory
outputDir = uigetdir(pathname, 'Select Output Directory');
if isequal(outputDir, 0)
    outputDir = fullfile(pathname, 'nanion_analysis_output');
    fprintf('Using default output: %s\n\n', outputDir);
end

%% STEP 5: Run Complete Analysis Pipeline
fprintf('--- RUNNING ANALYSIS PIPELINE ---\n');
fprintf('This includes:\n');
fprintf('  1. Protocol detection\n');
fprintf('  2. Data extraction\n');
fprintf('  3. Quality filtering\n');
fprintf('  4. Boltzmann curve fitting\n\n');

tic;
results = pipeline.runAnalysis(filePaths, outputDir);
analysisTime = toc;

fprintf('\n✓ Analysis complete in %.1f seconds\n\n', analysisTime);

%% STEP 6: Display Analysis Summary
fprintf('--- ANALYSIS SUMMARY ---\n');
successCount = sum(cellfun(@(x) strcmp(x.status, 'success'), results));
fprintf('Files processed: %d/%d\n', successCount, length(results));

for i = 1:length(results)
    result = results{i};
    
    if strcmp(result.status, 'success')
        fittedData = result.fittedData;
        summary = fittedData.summary;
        
        fprintf('\n%s:\n', result.fileName);
        fprintf('  Wells analyzed: %d\n', fittedData.numWells);
        fprintf('  Good fits: %d (%.1f%%)\n', summary.fitResults.good, ...
            100 * summary.fitResults.good / fittedData.numWells);
        fprintf('  Acceptable fits: %d (%.1f%%)\n', summary.fitResults.acceptable, ...
            100 * summary.fitResults.acceptable / fittedData.numWells);
        fprintf('  Poor fits: %d (%.1f%%)\n', summary.fitResults.poor, ...
            100 * summary.fitResults.poor / fittedData.numWells);
        fprintf('  Failed fits: %d (%.1f%%)\n', summary.fitResults.failed, ...
            100 * summary.fitResults.failed / fittedData.numWells);
        
        if summary.fitResults.good + summary.fitResults.acceptable > 0
            fprintf('  Mean V½: %.2f ± %.2f mV\n', ...
                summary.parameterStats.V_mid_mean, summary.parameterStats.V_mid_std);
            fprintf('  Mean k: %.2f ± %.2f mV\n', ...
                summary.parameterStats.k_mean, summary.parameterStats.k_std);
            fprintf('  Mean R²: %.4f\n', summary.parameterStats.R2_mean);
        end
    else
        fprintf('\n%s: FAILED\n', result.fileName);
    end
end
fprintf('\n');

%% STEP 7: Generate Visualizations
fprintf('--- GENERATING PLOTS ---\n');

% Initialize plotter
config = NanionConfig();
logger = NanionLogger(config);
plotter = NanionBoltzmannPlotter(config, logger);

tic;
for i = 1:length(results)
    result = results{i};
    
    if strcmp(result.status, 'success') && ~isempty(result.fittedData.wells)
        fprintf('Plotting file %d/%d: %s\n', i, length(results), result.fileName);
        
        % Create plots directory
        plotDir = fullfile(result.outputDir, 'plots');
        if ~exist(plotDir, 'dir')
            mkdir(plotDir);
        end
        
        % Generate all plots
        plotter.plotAllResults(result.fittedData, plotDir, result.fileName);
        
        fprintf('  ✓ Saved 4 plot types to: %s\n', plotDir);
    end
end
plottingTime = toc;

fprintf('\n✓ Plotting complete in %.1f seconds\n\n', plottingTime);

%% STEP 8: Summary Report
fprintf('=== WORKFLOW COMPLETE ===\n');
fprintf('Total time: %.1f seconds\n', analysisTime + plottingTime);
fprintf('Output directory: %s\n', outputDir);
fprintf('\nGenerated files:\n');
fprintf('  - Analysis summary (TXT)\n');
fprintf('  - I-V curve plots (PNG)\n');
fprintf('  - Parameter distributions (PNG)\n');
fprintf('  - Fit quality summary (PNG)\n');
fprintf('  - V½ vs R² scatter plot (PNG)\n');

%% STEP 9: Save Results (Optional)
saveResults = questdlg('Save results to .mat file?', 'Save Results', 'Yes', 'No', 'Yes');

if strcmp(saveResults, 'Yes')
    resultsFile = fullfile(outputDir, 'analysis_results.mat');
    save(resultsFile, 'results', '-v7.3');
    fprintf('\n✓ Results saved to: %s\n', resultsFile);
end

%% STEP 10: Open Output Folder
if ispc
    answer = questdlg('Open output folder?', 'Workflow Complete', 'Yes', 'No', 'Yes');
    if strcmp(answer, 'Yes')
        winopen(outputDir);
    end
end

fprintf('\n=== END OF WORKFLOW ===\n');

%% BONUS: Quick Data Export to CSV
% Uncomment to export fitted parameters to CSV

% fprintf('\n--- EXPORTING PARAMETERS TO CSV ---\n');
% for i = 1:length(results)
%     result = results{i};
%     
%     if strcmp(result.status, 'success')
%         wells = result.fittedData.wells;
%         
%         % Create table
%         wellIDs = {wells.wellID}';
%         V_mids = arrayfun(@(x) x.fitParams.V_mid, wells)';
%         ks = arrayfun(@(x) x.fitParams.k, wells)';
%         z_as = arrayfun(@(x) x.fitParams.z_a, wells)';
%         R2s = arrayfun(@(x) x.fitParams.R2, wells)';
%         qualities = {wells.fitQuality}';
%         
%         T = table(wellIDs, V_mids, ks, z_as, R2s, qualities, ...
%             'VariableNames', {'WellID', 'V_half_mV', 'k_mV', 'z_a', 'R_squared', 'Quality'});
%         
%         % Save CSV
%         csvFile = fullfile(result.outputDir, sprintf('%s_parameters.csv', result.fileName));
%         writetable(T, csvFile);
%         
%         fprintf('✓ Exported %s\n', csvFile);
%     end
% end
