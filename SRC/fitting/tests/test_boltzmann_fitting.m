function test_boltzmann_fitting()
    %TEST_BOLTZMANN_FITTING Validation script for Phase 3 Boltzmann fitting
    %   Tests fitting on sample activation/inactivation files
    
    fprintf('=== BOLTZMANN FITTING TEST ===\n\n');
    
    % Initialize pipeline
    pipeline = NanionAnalysisPipeline();
    
    % Select test file
    [filename, pathname] = uigetfile(...
        {'*.xlsx;*.xls', 'Excel Files (*.xlsx, *.xls)'}, ...
        'Select Test File for Boltzmann Fitting');
    
    if isequal(filename, 0)
        fprintf('No file selected. Test cancelled.\n');
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
        % Run analysis with Boltzmann fitting
        fprintf('Running complete pipeline with Boltzmann fitting...\n');
        results = pipeline.runAnalysis({filePath}, outputDir);
        
        if isempty(results) || strcmp(results{1}.status, 'failed')
            fprintf('✗ Pipeline failed\n');
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
        
        % Check first well structure
        if ~isempty(fittedData.wells)
            fprintf('\n--- WELL STRUCTURE VALIDATION ---\n');
            well1 = fittedData.wells(1);
            
            assert(isfield(well1, 'wellID'), 'Missing wellID');
            fprintf('✓ wellID: %s\n', well1.wellID);
            
            assert(isfield(well1, 'fitParams'), 'Missing fitParams');
            fprintf('✓ fitParams field exists\n');
            
            assert(isfield(well1.fitParams, 'V_mid'), 'Missing V_mid');
            fprintf('✓ V_mid: %.2f mV\n', well1.fitParams.V_mid);
            
            assert(isfield(well1.fitParams, 'k'), 'Missing k');
            fprintf('✓ k (slope factor): %.2f mV\n', well1.fitParams.k);
            
            assert(isfield(well1.fitParams, 'z_a'), 'Missing z_a');
            fprintf('✓ z_a (gating charge): %.3f\n', well1.fitParams.z_a);
            
            assert(isfield(well1.fitParams, 'R2'), 'Missing R2');
            fprintf('✓ R²: %.4f\n', well1.fitParams.R2);
            
            assert(isfield(well1.fitParams, 'RMSE'), 'Missing RMSE');
            fprintf('✓ RMSE: %.2f pA\n', well1.fitParams.RMSE);
            
            assert(isfield(well1, 'fitQuality'), 'Missing fitQuality');
            fprintf('✓ Fit quality: %s\n', well1.fitQuality);
            
            % Verify fit quality is valid
            validQualities = {'Good', 'Acceptable', 'Poor', 'Failed'};
            assert(ismember(well1.fitQuality, validQualities), ...
                'Invalid fit quality category: %s', well1.fitQuality);
        end
        
        % Verify parameter ranges
        fprintf('\n--- PARAMETER RANGE VALIDATION ---\n');
        
        protocolType = result.protocol.type;
        config = NanionConfig();  % Create config instance for validation
        
        if well1.fitParams.converged
            % Check V_mid range
            if strcmp(protocolType, 'activation')
                expectedRange = config.boltzmann.activationVmidRange;
            else
                expectedRange = config.boltzmann.inactivationVmidRange;
            end
            
            if strcmp(well1.fitQuality, 'Good') || strcmp(well1.fitQuality, 'Acceptable')
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
        
        % Check summary statistics
        fprintf('\n--- SUMMARY STATISTICS VALIDATION ---\n');
        summary = fittedData.summary;
        
        assert(isfield(summary, 'fitResults'), 'Missing fitResults');
        fprintf('✓ Fit results structure exists\n');
        
        totalFits = summary.fitResults.good + summary.fitResults.acceptable + ...
                    summary.fitResults.poor + summary.fitResults.failed;
        assert(totalFits == fittedData.numWells, ...
            'Fit count mismatch: %d fits, %d wells', totalFits, fittedData.numWells);
        fprintf('✓ Fit count matches well count: %d\n', totalFits);
        
        % Display summary
        fprintf('\n--- FIT QUALITY SUMMARY ---\n');
        fprintf('Total wells fitted: %d\n', fittedData.numWells);
        fprintf('Good fits: %d (%.1f%%)\n', summary.fitResults.good, ...
            100 * summary.fitResults.good / totalFits);
        fprintf('Acceptable fits: %d (%.1f%%)\n', summary.fitResults.acceptable, ...
            100 * summary.fitResults.acceptable / totalFits);
        fprintf('Poor fits: %d (%.1f%%)\n', summary.fitResults.poor, ...
            100 * summary.fitResults.poor / totalFits);
        fprintf('Failed fits: %d (%.1f%%)\n', summary.fitResults.failed, ...
            100 * summary.fitResults.failed / totalFits);
        
        % Check convergence rate
        convergedFits = summary.fitResults.good + summary.fitResults.acceptable + summary.fitResults.poor;
        convergenceRate = 100 * convergedFits / totalFits;
        fprintf('\nConvergence rate: %.1f%% (%d/%d)\n', convergenceRate, convergedFits, totalFits);
        
        if convergenceRate >= 90
            fprintf('✓ SUCCESS: Convergence rate ≥90%%\n');
        else
            fprintf('⚠ WARNING: Convergence rate <90%%\n');
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
        
        % Check that at least some fits succeeded
        if convergedFits == 0
            fprintf('✗ FAILED: No fits converged\n');
            return;
        end
        
        % All tests passed
        fprintf('\n✓ ALL BOLTZMANN FITTING TESTS PASSED!\n');
        fprintf('Output saved to: %s\n', outputDir);
        
    catch ME
        fprintf('\n✗ TEST FAILED: %s\n', ME.message);
        fprintf('Stack trace:\n%s\n', getReport(ME));
    end
    
    fprintf('\n=== TEST COMPLETE ===\n');
end
