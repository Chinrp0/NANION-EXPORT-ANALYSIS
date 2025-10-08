function plot_test_results()
    %PLOT_TEST_RESULTS Quick script to plot results from test_boltzmann_fitting
    %   Assumes you just ran test_boltzmann_fitting and results are in workspace
    
    fprintf('=== PLOTTING TEST RESULTS ===\n\n');
    
    % Check if results exist in workspace
    if ~evalin('base', 'exist(''results'', ''var'')')
        fprintf('No "results" variable found in workspace.\n');
        fprintf('Please run test_boltzmann_fitting first, or use plot_boltzmann_results() instead.\n');
        return;
    end
    
    % Load results from workspace
    results = evalin('base', 'results');
    
    if isempty(results)
        fprintf('Results variable is empty.\n');
        return;
    end
    
    % Initialize plotter
    config = NanionConfig();
    logger = NanionLogger(config);
    plotter = NanionBoltzmannPlotter(config, logger);
    
    % Get result
    result = results{1};
    
    if ~isfield(result, 'fittedData')
        fprintf('No fittedData found in results.\n');
        return;
    end
    
    fittedData = result.fittedData;
    
    % Create output directory
    if isfield(result, 'outputDir')
        plotDir = fullfile(result.outputDir, 'plots');
    else
        plotDir = fullfile(pwd, 'test_plots');
    end
    
    if ~exist(plotDir, 'dir')
        mkdir(plotDir);
    end
    
    fprintf('Generating plots for: %s\n', result.fileName);
    fprintf('Output directory: %s\n\n', plotDir);
    
    % Generate all plots
    plotter.plotAllResults(fittedData, plotDir, result.fileName);
    
    % Summary
    summary = fittedData.summary;
    fprintf('\n--- PLOTTING SUMMARY ---\n');
    fprintf('Total wells plotted: %d\n', length(fittedData.wells));
    fprintf('Good fits: %d (%.1f%%)\n', summary.fitResults.good, ...
        100 * summary.fitResults.good / length(fittedData.wells));
    fprintf('Acceptable fits: %d (%.1f%%)\n', summary.fitResults.acceptable, ...
        100 * summary.fitResults.acceptable / length(fittedData.wells));
    fprintf('Poor fits: %d (%.1f%%)\n', summary.fitResults.poor, ...
        100 * summary.fitResults.poor / length(fittedData.wells));
    
    if summary.fitResults.good + summary.fitResults.acceptable > 0
        fprintf('\nParameter Statistics (Good + Acceptable):\n');
        fprintf('  V½: %.2f ± %.2f mV\n', ...
            summary.parameterStats.V_mid_mean, summary.parameterStats.V_mid_std);
        fprintf('  k: %.2f ± %.2f mV\n', ...
            summary.parameterStats.k_mean, summary.parameterStats.k_std);
        fprintf('  R²: %.4f\n', summary.parameterStats.R2_mean);
    end
    
    fprintf('\n✓ All plots saved to: %s\n', plotDir);
    
    % Open output folder
    if ispc
        fprintf('\nOpening output folder...\n');
        winopen(plotDir);
    end
    
    fprintf('\n=== PLOTTING COMPLETE ===\n');
end
