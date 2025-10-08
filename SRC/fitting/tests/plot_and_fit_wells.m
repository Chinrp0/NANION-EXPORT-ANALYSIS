function plot_and_fit_wells()
    %PLOT_AND_FIT_WELLS Plot and fit specific wells (IV1 only) for debugging
    %   Replicates your previous analysis with detailed diagnostics
    
    fprintf('=== WELL-BY-WELL FIT DEBUGGER ===\n\n');
    
    % Initialize
    config = NanionConfig();
    logger = NanionLogger(config);
    detector = NanionFileDetector(logger);
    ioManager = NanionIOManager(config, logger);
    extractor = NanionDataExtractor(config, logger);
    
    % Load file
    [filename, pathname] = uigetfile('*.xlsx', 'Select Activation File');
    if isequal(filename, 0)
        return;
    end
    filePath = fullfile(pathname, filename);
    
    % Process
    fprintf('Loading: %s\n\n', filename);
    protocolInfo = detector.detectProtocol(filePath);
    rawData = ioManager.readFile(filePath);
    parsedData = ioManager.parseData(rawData, protocolInfo);
    extractedData = extractor.extractMeasurements(parsedData);
    filteredData = extractor.applyQualityFilters(extractedData);
    
    fprintf('✓ %d wells passed quality filtering\n\n', filteredData.numWellsPassed);
    
    % Select wells to plot
    targetWells = {'E01', 'F02', 'G02'};
    voltages = protocolInfo.voltages;
    
    % Create figure
    figure('Position', [100, 100, 1400, 400]);
    
    for plotIdx = 1:length(targetWells)
        targetWell = targetWells{plotIdx};
        
        % Find well in filtered data
        wellIdx = find(strcmp(filteredData.wellIDs, targetWell), 1);
        
        if isempty(wellIdx)
            fprintf('⚠ Well %s not found in filtered data (likely failed quality filters)\n', targetWell);
            
            % Try to find in UNFILTERED data
            unfilteredIdx = find(strcmp(extractedData.wellIDs, targetWell), 1);
            
            if isempty(unfilteredIdx)
                fprintf('  ✗ Well %s not found in raw data either\n', targetWell);
                continue;
            end
            
            fprintf('  → Plotting UNFILTERED data for %s (for visualization only)\n\n', targetWell);
            
            % Extract from unfiltered data
            G_iv1 = extractedData.measurements.iv1.conductance(unfilteredIdx, :);
            validIdx = ~isnan(G_iv1);
            V_valid = voltages(validIdx);
            G_valid = G_iv1(validIdx);
            
            % Plot without fitting
            subplot(1, 3, plotIdx);
            plot(V_valid, G_valid, 'ro', 'MarkerSize', 10, 'MarkerFaceColor', 'red');
            grid on;
            xlabel('Voltage (mV)', 'FontSize', 11);
            ylabel('Conductance (nS)', 'FontSize', 11);
            title(sprintf('Well %s\n❌ FAILED QUALITY FILTERS', targetWell), ...
                'FontSize', 12, 'Interpreter', 'none', 'Color', 'red');
            legend('IV1 Data (unfiltered)', 'Location', 'northwest', 'FontSize', 9);
            
            continue;
        end
        
        % Extract IV1 conductance
        G_iv1 = filteredData.measurements.iv1.conductance(wellIdx, :);
        validIdx = ~isnan(G_iv1);
        V_valid = voltages(validIdx);
        G_valid = G_iv1(validIdx);
        
        fprintf('--- Well %s (IV1 only) ---\n', targetWell);
        fprintf('Valid points: %d/%d\n', sum(validIdx), length(G_iv1));
        fprintf('Voltage range: [%.1f, %.1f] mV\n', min(V_valid), max(V_valid));
        fprintf('Conductance range: [%.3e, %.3e] nS\n', min(G_valid), max(G_valid));
        
        % Get bounds
        [startPoints, lowerBounds, upperBounds] = BoltzmannModel.getInitialParams(...
            V_valid, G_valid, protocolInfo.type, config);
        
        fprintf('Bounds:\n');
        fprintf('  V_min: [%.3e, %.3e] nS\n', lowerBounds(1), upperBounds(1));
        fprintf('  V_max: [%.3e, %.3e] nS\n', lowerBounds(2), upperBounds(2));
        fprintf('  V_mid: [%.1f, %.1f] mV\n', lowerBounds(3), upperBounds(3));
        fprintf('  k: [%.1f, %.1f] mV\n', lowerBounds(4), upperBounds(4));
        
        % Check overlap
        if upperBounds(1) >= lowerBounds(2)
            fprintf('  ❌ OVERLAP! V_min_upper (%.3e) >= V_max_lower (%.3e)\n\n', ...
                upperBounds(1), lowerBounds(2));
            continue;
        else
            fprintf('  ✓ No overlap: V_min_upper (%.3e) < V_max_lower (%.3e)\n', ...
                upperBounds(1), lowerBounds(2));
        end
        
        % Attempt fit
        try
            ft = BoltzmannModel.createFitType(protocolInfo.type);
            
            [fitresult, gof] = fit(V_valid(:), G_valid(:), ft, ...
                'StartPoint', startPoints, ...
                'Lower', lowerBounds, ...
                'Upper', upperBounds);
            
            fprintf('✓ Fit succeeded:\n');
            fprintf('  V_min = %.6f nS (Gmin)\n', fitresult.V_min);
            fprintf('  V_max = %.6f nS (Gmax)\n', fitresult.V_max);
            fprintf('  V_mid = %.2f mV\n', fitresult.V_mid);
            fprintf('  k = %.2f mV\n', fitresult.k);
            fprintf('  R² = %.6f\n', gof.rsquare);
            
            z_a = BoltzmannModel.calculateGatingCharge(fitresult.k, config.temperature);
            fprintf('  z_a = %.3f\n', z_a);
            
            % Quality assessment
            fitParams = struct('V_min', fitresult.V_min, 'V_max', fitresult.V_max, ...
                'V_mid', fitresult.V_mid, 'k', fitresult.k, 'converged', true);
            quality = FitQualityAssessor.assessQuality(fitParams, gof, protocolInfo.type, config);
            fprintf('  Quality: %s\n\n', quality);
            
            % Plot
            subplot(1, 3, plotIdx);
            
            % Data points
            plot(V_valid, G_valid, 'ko', 'MarkerSize', 10, 'MarkerFaceColor', 'blue');
            hold on;
            
            % Fit curve
            V_fit = linspace(min(V_valid), max(V_valid), 200);
            G_fit = BoltzmannModel.activation(V_fit, ...
                fitresult.V_min, fitresult.V_max, fitresult.V_mid, fitresult.k);
            plot(V_fit, G_fit, 'r-', 'LineWidth', 2);
            
            hold off;
            grid on;
            xlabel('Voltage (mV)', 'FontSize', 11);
            ylabel('Conductance (nS)', 'FontSize', 11);
            title(sprintf('Well %s\nV_{1/2}=%.1f mV, k=%.1f mV, R²=%.3f', ...
                targetWell, fitresult.V_mid, fitresult.k, gof.rsquare), ...
                'FontSize', 12, 'Interpreter', 'none');
            legend('IV1 Data', 'Boltzmann Fit', 'Location', 'northwest', 'FontSize', 9);
            
        catch ME
            fprintf('❌ Fit failed: %s\n', ME.message);
            fprintf('   Error ID: %s\n\n', ME.identifier);
            
            % Plot data only
            subplot(1, 3, plotIdx);
            plot(V_valid, G_valid, 'ko', 'MarkerSize', 10, 'MarkerFaceColor', 'red');
            grid on;
            xlabel('Voltage (mV)', 'FontSize', 11);
            ylabel('Conductance (nS)', 'FontSize', 11);
            title(sprintf('Well %s\nFIT FAILED', targetWell), ...
                'FontSize', 12, 'Interpreter', 'none', 'Color', 'red');
        end
    end
    
    sgtitle('IV1 Conductance Fits (Activation Protocol)', 'FontSize', 14, 'FontWeight', 'bold');
    
    fprintf('=== COMPLETE ===\n');
    fprintf('Compare these results to your previous analysis\n');
    fprintf('Expected for F02: V_mid ≈ -35.5 mV, Gmax ≈ 25.5 nS, Gmin ≈ 0.146 nS\n');
end
