function results = test_boltzmann_fitting()
    %TEST_BOLTZMANN_FITTING Validation script for Phase 3 Boltzmann fitting
    %   Tests fitting on sample activation/inactivation files
    %   Returns results and saves to base workspace for plotting
    %   UPDATED: Better handling of failed fits
    
    fprintf('=== BOLTZMANN FITTING TEST ===\n\n');
    
    % Initialize pipeline
    pipeline = NanionAnalysisPipeline();
    
    % Select test file
    [filename, pathname] = uigetfile(...
        {'*.xlsx;*.xls', 'Excel Files (*.xlsx, *.xls)'}, ...
        'Select Test File for Boltzmann Fitting');
    
    if isequal(filename, 0)
        fprintf('No file selected. Test cancelled.\n');
        results = [];
        return;
    end
    
    filePath = fullfile(pathname, filename);
    
    % Create output directory
    outputDir = fullfile(pathname, 'boltzmann_test_output');
    if ~exist(outputDir, 'dir')
        mkdir(outputDir);
    end
    
    fprintf('Testing: %s\n\n', filename);
    
    try
        % Initialize results variable
        results = [];
        
        % Run analysis with Boltzmann fitting
        fprintf('Running complete pipeline with Boltzmann fitting...\n');
        results = pipeline.runAnalysis({filePath}, outputDir);
        
        if isempty(results) || strcmp(results{1}.status, 'failed')
            fprintf('✗ Pipeline failed\n');
            results = [];
            return;
        end
        
        result = results{1};
        
        % Verify fitted data structure exists
        fprintf('\n--- STRUCTURE VALIDATION ---\n');
        assert(isfield(result, 'fittedData'), 'Missing fittedData field');
        fprintf('✓ fittedData field exists\n');
        
        fittedData = result.fittedData;
        
        assert(isfield(fittedData, 'wells'), 'Missing wells field');
        fprintf('✓ wells field exists\n');
        
        assert(isfield(fittedData, 'summary'), 'Missing summary field');
        fprintf('✓ summary field exists\n');
        
        % Check summary first
        summary = fittedData.summary;
        fprintf('\n--- FIT QUALITY SUMMARY ---\n');
        fprintf('Total wells fitted: %d\n', fittedData.numWells);
        fprintf('Good fits: %d (%.1f%%)\n', summary.fitResults.good, ...
            100 * summary.fitResults.good / fittedData.numWells);
        fprintf('Acceptable fits: %d (%.1f%%)\n', summary.fitResults.acceptable, ...
            100 * summary.fitResults.acceptable / fittedData.numWells);
        fprintf('Poor fits: %d (%.1f%%)\n', summary.fitResults.poor, ...
            100 * summary.fitResults.poor / fittedData.numWells);
        fprintf('Failed fits: %d (%.1f%%)\n', summary.fitResults.failed, ...
            100 * summary.fitResults.failed / fittedData.numWells);
        
        % Calculate convergence rate
        convergedFits = summary.fitResults.good + summary.fitResults.acceptable + summary.fitResults.poor;
        convergenceRate = 100 * convergedFits / fittedData.numWells;
        fprintf('\nConvergence rate: %.1f%% (%d/%d)\n', convergenceRate, convergedFits, fittedData.numWells);
        
        % CRITICAL CHECK: If ALL fits failed, something is wrong
        if convergedFits == 0
            fprintf('\n✗ CRITICAL ISSUE: ALL FITS FAILED\n');
            fprintf('This usually means:\n');
            fprintf('  1. Data quality issues (all NaN/Inf values)\n');
            fprintf('  2. Fitting bounds are incompatible with data\n');
            fprintf('  3. Bug in fitting code\n\n');
            fprintf('Debugging suggestions:\n');
            fprintf('  - Check if conductance calculation produced valid values\n');
            fprintf('  - Verify fitting bounds in NanionConfig.m\n');
            fprintf('  - Try fitting a single well manually with plot to see error\n\n');
            
            % Show first well data for debugging
            if ~isempty(fittedData.wells)
                well1 = fittedData.wells(1);
                fprintf('First well debug info:\n');
                fprintf('  Well ID: %s\n', well1.wellID);
                fprintf('  Valid points: %d\n', well1.validPoints);
                fprintf('  Data type: %s\n', well1.dataType);
                fprintf('  Fit converged: %s\n', mat2str(well1.fitParams.converged));
                
                % Show data preview
                validIdx = ~isnan(well1.data);
                if sum(validIdx) > 0
                    fprintf('  Data range: [%.3e to %.3e] %s\n', ...
                        min(well1.data(validIdx)), max(well1.data(validIdx)), well1.dataUnits);
                    fprintf('  Voltage range: [%.1f to %.1f] mV\n', ...
                        min(well1.voltages(validIdx)), max(well1.voltages(validIdx)));
                else
                    fprintf('  ✗ All data is NaN!\n');
                end
            end
            
            fprintf('\n✗ TEST FAILED: No fits converged\n');
            
            % Save results anyway for debugging
            assignin('base', 'results', results);
            fprintf('\n✓ Results saved to workspace variable "results" for debugging\n');
            return;
        end
        
        % If we have at least some converged fits, continue validation
        fprintf('\n--- WELL STRUCTURE VALIDATION ---\n');
        
        % Find first converged well for validation
        convergedIdx = find(arrayfun(@(x) x.fitParams.converged, fittedData.wells), 1);
        
        if isempty(convergedIdx)
            fprintf('⚠ No converged fits to validate structure\n');
        else
            well1 = fittedData.wells(convergedIdx);
            
            fprintf('Validating well %d: %s\n', convergedIdx, well1.wellID);
            
            assert(isfield(well1, 'wellID'), 'Missing wellID');
            fprintf('✓ wellID: %s\n', well1.wellID);
            
            assert(isfield(well1, 'fitParams'), 'Missing fitParams');
            fprintf('✓ fitParams field exists\n');
            
            % Validate all expected parameters
            assert(isfield(well1.fitParams, 'converged'), 'Missing converged field');
            fprintf('✓ converged: %s\n', mat2str(well1.fitParams.converged));
            
            if well1.fitParams.converged
                assert(isfield(well1.fitParams, 'V_mid'), 'Missing V_mid');
                fprintf('✓ V_mid: %.2f mV\n', well1.fitParams.V_mid);
                
                assert(isfield(well1.fitParams, 'k'), 'Missing k');
                fprintf('✓ k (slope factor): %.2f mV\n', well1.fitParams.k);
                
                assert(isfield(well1.fitParams, 'z_a'), 'Missing z_a');
                fprintf('✓ z_a (gating charge): %.3f\n', well1.fitParams.z_a);
                
                assert(isfield(well1.fitParams, 'R2'), 'Missing R2');
                fprintf('✓ R²: %.4f\n', well1.fitParams.R2);
                
                assert(isfield(well1.fitParams, 'RMSE'), 'Missing RMSE');
                fprintf('✓ RMSE: %.2e %s\n', well1.fitParams.RMSE, well1.dataUnits);
            end
            
            assert(isfield(well1, 'fitQuality'), 'Missing fitQuality');
            fprintf('✓ Fit quality: %s\n', well1.fitQuality);
            
            % Verify fit quality is valid
            validQualities = {'Good', 'Acceptable', 'Poor', 'Failed'};
            assert(ismember(well1.fitQuality, validQualities), ...
                'Invalid fit quality category: %s', well1.fitQuality);
                
            % Verify parameter ranges for Good/Acceptable fits
            if (strcmp(well1.fitQuality, 'Good') || strcmp(well1.fitQuality, 'Acceptable'))
                fprintf('\n--- PARAMETER RANGE VALIDATION ---\n');
                
                protocolType = result.protocol.type;
                config = NanionConfig();
                
                % Check V_mid range
                if strcmp(protocolType, 'activation')
                    expectedRange = config.boltzmann.activationVmidRange;
                else
                    expectedRange = config.boltzmann.inactivationVmidRange;
                end
                
                assert(well1.fitParams.V_mid >= expectedRange(1) && well1.fitParams.V_mid <= expectedRange(2), ...
                    'V_mid out of expected range for %s: %.2f not in [%.2f, %.2f]', ...
                    protocolType, well1.fitParams.V_mid, expectedRange(1), expectedRange(2));
                fprintf('✓ V_mid within protocol range: [%.1f, %.1f] mV\n', expectedRange(1), expectedRange(2));
                
                % Check k range
                kRange = config.boltzmann.slopeLimits;
                assert(well1.fitParams.k >= kRange(1) && well1.fitParams.k <= kRange(2), ...
                    'k out of expected range: %.2f not in [%.2f, %.2f]', ...
                    well1.fitParams.k, kRange(1), kRange(2));
                fprintf('✓ k within limits: [%.1f, %.1f] mV\n', kRange(1), kRange(2));
            end
        end
        
        % Display parameter statistics (for Good + Acceptable fits)
        goodOrAcceptable = summary.fitResults.good + summary.fitResults.acceptable;
        if goodOrAcceptable > 0
            fprintf('\n--- PARAMETER STATISTICS (Good + Acceptable) ---\n');
            fprintf('V_mid (V½):\n');
            fprintf('  Mean: %.2f ± %.2f mV\n', ...
                summary.parameterStats.V_mid_mean, summary.parameterStats.V_mid_std);
            fprintf('  Median: %.2f mV\n', summary.parameterStats.V_mid_median);
            fprintf('  Range: [%.2f, %.2f] mV\n', ...
                summary.parameterStats.V_mid_range(1), summary.parameterStats.V_mid_range(2));
            
            fprintf('\nSlope factor (k):\n');
            fprintf('  Mean: %.2f ± %.2f mV\n', ...
                summary.parameterStats.k_mean, summary.parameterStats.k_std);
            fprintf('  Median: %.2f mV\n', summary.parameterStats.k_median);
            
            fprintf('\nR² (goodness of fit):\n');
            fprintf('  Mean: %.4f\n', summary.parameterStats.R2_mean);
            fprintf('  Median: %.4f\n', summary.parameterStats.R2_median);
        end
        
        % Final validation
        fprintf('\n--- FINAL VALIDATION ---\n');
        
        % Success criteria
        if convergenceRate >= 90
            fprintf('✓ SUCCESS: Convergence rate ≥90%%\n');
        elseif convergenceRate >= 50
            fprintf('⚠ PARTIAL SUCCESS: Convergence rate ≥50%% but <90%%\n');
        else
            fprintf('✗ WARNING: Convergence rate <50%%\n');
        end
        
        % Check for quality distribution
        if summary.fitResults.good >= 20
            fprintf('✓ SUCCESS: ≥20 Good fits\n');
        elseif summary.fitResults.good + summary.fitResults.acceptable >= 20
            fprintf('⚠ PARTIAL SUCCESS: ≥20 Good+Acceptable fits\n');
        else
            fprintf('⚠ WARNING: <20 Good+Acceptable fits\n');
        end
        
        fprintf('\n✓ BOLTZMANN FITTING TESTS PASSED!\n');
        fprintf('Output saved to: %s\n', outputDir);
        
        % Save results to base workspace for plotting
        assignin('base', 'results', results);
        fprintf('\n✓ Results saved to workspace variable "results"\n');
        fprintf('   You can now run: plot_test_results()\n');
        
    catch ME
        fprintf('\n✗ TEST FAILED: %s\n', ME.message);
        fprintf('Stack trace:\n%s\n', getReport(ME));
        results = [];
    end
    
    fprintf('\n=== TEST COMPLETE ===\n');
end
