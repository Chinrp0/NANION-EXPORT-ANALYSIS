function test_all_fixes()
    %TEST_ALL_FIXES Comprehensive test of all Boltzmann fitting fixes
    %   Tests config, bounds, and fitting on your activation file
    
    fprintf('=== COMPREHENSIVE FIT TEST ===\n\n');
    
    %% Step 1: Verify Config
    fprintf('STEP 1: Verifying configuration...\n');
    config = NanionConfig();
    
    fprintf('✓ Temperature: %.1f°C\n', config.temperature);
    fprintf('✓ Nernst potential: %.1f mV\n', config.nernstPotential);
    fprintf('✓ Parallel processing: %s\n', mat2str(config.boltzmann.useParallel));
    fprintf('✓ Slope limits: [%.1f, %.1f] mV\n', ...
        config.boltzmann.slopeLimits(1), config.boltzmann.slopeLimits(2));
    fprintf('✓ Activation V_mid range: [%.1f, %.1f] mV\n\n', ...
        config.boltzmann.activationVmidRange(1), config.boltzmann.activationVmidRange(2));
    
    %% Step 2: Load and Process Data
    fprintf('STEP 2: Loading and processing data...\n');
    
    % Select file
    [filename, pathname] = uigetfile('*.xlsx', 'Select Activation File');
    if isequal(filename, 0)
        return;
    end
    filePath = fullfile(pathname, filename);
    
    % Initialize pipeline components
    logger = NanionLogger(config);
    detector = NanionFileDetector(logger);
    ioManager = NanionIOManager(config, logger);
    extractor = NanionDataExtractor(config, logger);
    
    % Process
    protocolInfo = detector.detectProtocol(filePath);
    rawData = ioManager.readFile(filePath);
    parsedData = ioManager.parseData(rawData, protocolInfo);
    extractedData = extractor.extractMeasurements(parsedData);
    filteredData = extractor.applyQualityFilters(extractedData);
    
    fprintf('✓ %d wells passed quality filtering\n\n', filteredData.numWellsPassed);
    
    if filteredData.numWellsPassed == 0
        fprintf('❌ No wells passed filtering. Cannot test fitting.\n');
        return;
    end
    
    %% Step 3: Test Bounds on First Well
    fprintf('STEP 3: Testing bounds generation...\n');
    
    wellIdx = 1;
    voltages = protocolInfo.voltages;
    conductance = filteredData.measurements.iv1.conductance(wellIdx, :);
    
    validIdx = ~isnan(conductance);
    V_valid = voltages(validIdx);
    G_valid = conductance(validIdx);
    
    fprintf('Well %s:\n', filteredData.wellIDs(wellIdx));
    fprintf('  Voltage range: [%.1f, %.1f] mV\n', min(V_valid), max(V_valid));
    fprintf('  Conductance range: [%.3e, %.3e] nS\n', min(G_valid), max(G_valid));
    
    % Get bounds
    [startPoints, lowerBounds, upperBounds] = BoltzmannModel.getInitialParams(...
        V_valid, G_valid, protocolInfo.type, config);
    
    fprintf('\n  Start points:\n');
    fprintf('    V_min = %.3e nS\n', startPoints(1));
    fprintf('    V_max = %.3e nS\n', startPoints(2));
    fprintf('    V_mid = %.2f mV\n', startPoints(3));
    fprintf('    k = %.2f mV\n', startPoints(4));
    
    fprintf('\n  Bounds check:\n');
    fprintf('    V_min: [%.3e, %.3e] nS\n', lowerBounds(1), upperBounds(1));
    fprintf('    V_max: [%.3e, %.3e] nS\n', lowerBounds(2), upperBounds(2));
    
    % CRITICAL CHECK
    if upperBounds(1) >= lowerBounds(2)
        fprintf('    ❌ BOUNDS OVERLAP! V_min_upper (%.3e) >= V_max_lower (%.3e)\n', ...
            upperBounds(1), lowerBounds(2));
        fprintf('       This will cause fitting to fail!\n\n');
        return;
    else
        fprintf('    ✓ NO OVERLAP: V_min_upper (%.3e) < V_max_lower (%.3e)\n', ...
            upperBounds(1), lowerBounds(2));
        fprintf('       Bounds are valid!\n\n');
    end
    
    %% Step 4: Attempt Single Well Fit
    fprintf('STEP 4: Attempting single well fit...\n');
    
    try
        ft = BoltzmannModel.createFitType(protocolInfo.type);
        
        [fitresult, gof] = fit(V_valid(:), G_valid(:), ft, ...
            'StartPoint', startPoints, ...
            'Lower', lowerBounds, ...
            'Upper', upperBounds);
        
        fprintf('✓✓✓ FIT SUCCEEDED! ✓✓✓\n\n');
        
        fprintf('Fit results:\n');
        fprintf('  V_min = %.3e nS\n', fitresult.V_min);
        fprintf('  V_max = %.3e nS\n', fitresult.V_max);
        fprintf('  V_mid = %.2f mV\n', fitresult.V_mid);
        fprintf('  k = %.2f mV\n', fitresult.k);
        fprintf('  R² = %.4f\n', gof.rsquare);
        
        z_a = BoltzmannModel.calculateGatingCharge(fitresult.k, config.temperature);
        fprintf('  z_a = %.3f (gating charge)\n', z_a);
        
        % Assess quality
        fitParams = struct('V_min', fitresult.V_min, 'V_max', fitresult.V_max, ...
            'V_mid', fitresult.V_mid, 'k', fitresult.k, 'converged', true);
        quality = FitQualityAssessor.assessQuality(fitParams, gof, protocolInfo.type, config);
        fprintf('  Quality: %s\n\n', quality);
        
        % Plot
        figure('Position', [100, 100, 800, 600]);
        plot(V_valid, G_valid, 'ko', 'MarkerSize', 10, 'MarkerFaceColor', 'blue');
        hold on;
        
        V_fit = linspace(min(V_valid), max(V_valid), 200);
        G_fit = BoltzmannModel.activation(V_fit, ...
            fitresult.V_min, fitresult.V_max, fitresult.V_mid, fitresult.k);
        plot(V_fit, G_fit, 'r-', 'LineWidth', 2);
        
        hold off;
        grid on;
        xlabel('Voltage (mV)', 'FontSize', 12);
        ylabel('Conductance (nS)', 'FontSize', 12);
        title(sprintf('SUCCESS: Well %s, V_{1/2}=%.1f mV, R²=%.3f', ...
            filteredData.wellIDs(wellIdx), fitresult.V_mid, gof.rsquare), ...
            'FontSize', 14, 'Interpreter', 'none');
        legend('Data', 'Boltzmann Fit', 'Location', 'best');
        
    catch ME
        fprintf('❌ FIT STILL FAILED!\n');
        fprintf('Error: %s\n', ME.message);
        fprintf('ID: %s\n\n', ME.identifier);
        
        fprintf('This means there is still a problem with:\n');
        fprintf('  1. Bounds generation logic\n');
        fprintf('  2. Data preparation\n');
        fprintf('  3. MATLAB fit() function configuration\n\n');
        
        fprintf('Full error:\n%s\n', getReport(ME));
        return;
    end
    
    %% Step 5: Run Full Pipeline
    fprintf('STEP 5: Running full pipeline on all wells...\n');
    
    fitter = NanionBoltzmannFitter(config, logger);
    fittedData = fitter.fitBoltzmann(filteredData);
    
    summary = fittedData.summary;
    fprintf('\n--- FINAL RESULTS ---\n');
    fprintf('Total wells: %d\n', fittedData.numWells);
    fprintf('Good fits: %d (%.1f%%)\n', summary.fitResults.good, ...
        100 * summary.fitResults.good / fittedData.numWells);
    fprintf('Acceptable fits: %d (%.1f%%)\n', summary.fitResults.acceptable, ...
        100 * summary.fitResults.acceptable / fittedData.numWells);
    fprintf('Poor fits: %d (%.1f%%)\n', summary.fitResults.poor, ...
        100 * summary.fitResults.poor / fittedData.numWells);
    fprintf('Failed fits: %d (%.1f%%)\n', summary.fitResults.failed, ...
        100 * summary.fitResults.failed / fittedData.numWells);
    
    successRate = 100 * (summary.fitResults.good + summary.fitResults.acceptable) / fittedData.numWells;
    
    if successRate >= 80
        fprintf('\n✓✓✓ EXCELLENT! %.1f%% success rate\n', successRate);
    elseif successRate >= 50
        fprintf('\n✓ GOOD: %.1f%% success rate\n', successRate);
    elseif successRate > 0
        fprintf('\n⚠ PARTIAL: %.1f%% success rate\n', successRate);
    else
        fprintf('\n❌ ALL FAILED: 0%% success rate\n');
    end
    
    if summary.fitResults.good + summary.fitResults.acceptable > 0
        fprintf('\nParameter statistics (Good + Acceptable):\n');
        fprintf('  V½: %.2f ± %.2f mV\n', ...
            summary.parameterStats.V_mid_mean, summary.parameterStats.V_mid_std);
        fprintf('  k: %.2f ± %.2f mV\n', ...
            summary.parameterStats.k_mean, summary.parameterStats.k_std);
        fprintf('  R²: %.4f (mean)\n', summary.parameterStats.R2_mean);
    end
    
    fprintf('\n=== TEST COMPLETE ===\n');
    
    % Show first few errors if any
    if summary.fitResults.failed > 0
        fprintf('\nFirst 3 fit errors:\n');
        errorCount = 0;
        for i = 1:length(fittedData.wells)
            if strcmp(fittedData.wells(i).fitQuality, 'Failed') && errorCount < 3
                fprintf('  %s: %s\n', fittedData.wells(i).wellID, fittedData.wells(i).fitError);
                errorCount = errorCount + 1;
            end
        end
    end
end
