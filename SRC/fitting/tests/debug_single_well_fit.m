function debug_single_well_fit()
    %DEBUG_SINGLE_WELL_FIT Detailed debugging of a single well's Boltzmann fit
    %   This script helps diagnose why fits are failing
    
    fprintf('=== SINGLE WELL FIT DEBUGGER ===\n\n');
    
    % Initialize
    config = NanionConfig();
    logger = NanionLogger(config);
    detector = NanionFileDetector(logger);
    ioManager = NanionIOManager(config, logger);
    extractor = NanionDataExtractor(config, logger);
    
    % Select file
    [filename, pathname] = uigetfile('*.xlsx', 'Select Nanion File');
    if isequal(filename, 0)
        return;
    end
    filePath = fullfile(pathname, filename);
    
    % Process file
    fprintf('Processing: %s\n\n', filename);
    protocolInfo = detector.detectProtocol(filePath);
    rawData = ioManager.readFile(filePath);
    parsedData = ioManager.parseData(rawData, protocolInfo);
    extractedData = extractor.extractMeasurements(parsedData);
    filteredData = extractor.applyQualityFilters(extractedData);
    
    if filteredData.numWellsPassed == 0
        fprintf('❌ No wells passed quality filtering!\n');
        return;
    end
    
    fprintf('✓ %d wells passed quality filtering\n\n', filteredData.numWellsPassed);
    
    % Select well to debug
    fprintf('Available wells:\n');
    for i = 1:min(10, length(filteredData.wellIDs))
        fprintf('  %d: %s\n', i, filteredData.wellIDs(i));
    end
    
    wellChoice = input(sprintf('\nEnter well number (1-%d) [default=1]: ', ...
        filteredData.numWellsPassed));
    if isempty(wellChoice)
        wellChoice = 1;
    end
    
    wellIdx = wellChoice;
    wellID = filteredData.wellIDs(wellIdx);
    
    fprintf('\n--- DEBUGGING WELL: %s ---\n\n', wellID);
    
    % Get data
    voltages = protocolInfo.voltages;
    
    if strcmp(protocolInfo.type, 'activation')
        if ~isfield(filteredData.measurements.iv1, 'conductance')
            fprintf('❌ Conductance not calculated!\n');
            return;
        end
        data = filteredData.measurements.iv1.conductance(wellIdx, :);
        dataType = 'conductance';
        dataUnits = 'nS';
    else
        data = filteredData.measurements.iv1.inactivationData(wellIdx, :);
        dataType = 'current';
        dataUnits = 'pA';
    end
    
    % Data inspection
    fprintf('--- DATA INSPECTION ---\n');
    fprintf('Protocol: %s\n', protocolInfo.type);
    fprintf('Data type: %s (%s)\n', dataType, dataUnits);
    fprintf('Total data points: %d\n', length(data));
    
    validIdx = ~isnan(data);
    numValid = sum(validIdx);
    fprintf('Valid data points: %d (%.1f%%)\n', numValid, 100*numValid/length(data));
    
    if numValid == 0
        fprintf('❌ No valid data points!\n');
        return;
    end
    
    V_valid = voltages(validIdx);
    D_valid = data(validIdx);
    
    fprintf('\nData range:\n');
    fprintf('  Voltage: [%.1f to %.1f] mV\n', min(V_valid), max(V_valid));
    fprintf('  %s: [%.3e to %.3e] %s\n', dataType, min(D_valid), max(D_valid), dataUnits);
    fprintf('  Mean: %.3e %s\n', mean(D_valid), dataUnits);
    fprintf('  Std: %.3e %s\n', std(D_valid), dataUnits);
    
    % Check for data issues
    fprintf('\n--- DATA QUALITY CHECKS ---\n');
    
    if all(D_valid == D_valid(1))
        fprintf('⚠ WARNING: All data values are identical (%.3e)\n', D_valid(1));
    end
    
    if all(D_valid <= 0)
        fprintf('⚠ WARNING: All data values are non-positive\n');
    end
    
    if max(abs(D_valid)) < 1e-10
        fprintf('⚠ WARNING: Data values extremely small (max = %.3e)\n', max(abs(D_valid)));
    end
    
    dataSpan = max(D_valid) - min(D_valid);
    if dataSpan < 1e-10
        fprintf('⚠ WARNING: Data span very small (%.3e), curve may be flat\n', dataSpan);
    end
    
    % Get fitting parameters
    fprintf('\n--- FITTING PARAMETERS ---\n');
    
    % FIXED: Line 157 - corrected variable name
    [startPoints, lowerBounds, upperBounds] = BoltzmannModel.getInitialParams(...
        V_valid, D_valid, protocolInfo.type, config);
    
    fprintf('Start points:\n');
    fprintf('  V_min = %.3e %s\n', startPoints(1), dataUnits);
    fprintf('  V_max = %.3e %s\n', startPoints(2), dataUnits);
    fprintf('  V_mid = %.2f mV\n', startPoints(3));
    fprintf('  k = %.2f mV\n', startPoints(4));
    
    fprintf('\nLower bounds:\n');
    fprintf('  V_min = %.3e %s\n', lowerBounds(1), dataUnits);
    fprintf('  V_max = %.3e %s\n', lowerBounds(2), dataUnits);
    fprintf('  V_mid = %.2f mV\n', lowerBounds(3));
    fprintf('  k = %.2f mV\n', lowerBounds(4));
    
    fprintf('\nUpper bounds:\n');
    fprintf('  V_min = %.3e %s\n', upperBounds(1), dataUnits);
    fprintf('  V_max = %.3e %s\n', upperBounds(2), dataUnits);
    fprintf('  V_mid = %.2f mV\n', upperBounds(3));
    fprintf('  k = %.2f mV\n', upperBounds(4));
    
    % Check if temperature exists in config
    fprintf('\n--- CONFIG VERIFICATION ---\n');
    temp = config.temperature;  % Uses public getter
    fprintf('✓ Temperature: %.1f°C\n', temp);
    
    % Attempt fit
    fprintf('\n--- ATTEMPTING FIT ---\n');
    
    try
        ft = BoltzmannModel.createFitType(protocolInfo.type);
        fprintf('✓ Fittype created successfully\n');
        
        fprintf('Running fit...\n');
        [fitresult, gof] = fit(V_valid(:), D_valid(:), ft, ...
            'StartPoint', startPoints, ...
            'Lower', lowerBounds, ...
            'Upper', upperBounds);
        
        fprintf('✓ FIT SUCCEEDED!\n\n');
        
        fprintf('--- FIT RESULTS ---\n');
        fprintf('V_min = %.3e %s\n', fitresult.V_min, dataUnits);
        fprintf('V_max = %.3e %s\n', fitresult.V_max, dataUnits);
        fprintf('V_mid = %.2f mV\n', fitresult.V_mid);
        fprintf('k = %.2f mV\n', fitresult.k);
        fprintf('R² = %.4f\n', gof.rsquare);
        fprintf('RMSE = %.3e\n', gof.rmse);
        
        % Get temperature for gating charge
        temp = config.temperature;
        z_a = BoltzmannModel.calculateGatingCharge(fitresult.k, temp);
        fprintf('z_a (gating charge) = %.3f\n', z_a);
        
        % Assess quality
        fitParams = struct('V_min', fitresult.V_min, 'V_max', fitresult.V_max, ...
            'V_mid', fitresult.V_mid, 'k', fitresult.k, 'converged', true);
        quality = FitQualityAssessor.assessQuality(fitParams, gof, protocolInfo.type, config);
        fprintf('\nFit Quality: %s\n', quality);
        
        % Plot result
        fprintf('\n--- GENERATING PLOT ---\n');
        figure('Position', [100, 100, 800, 600]);
        
        % Plot data
        plot(V_valid, D_valid, 'ko', 'MarkerSize', 10, 'MarkerFaceColor', 'blue');
        hold on;
        
        % Plot fit
        V_fit = linspace(min(V_valid), max(V_valid), 200);
        if strcmp(protocolInfo.type, 'activation')
            D_fit = BoltzmannModel.activation(V_fit, ...
                fitresult.V_min, fitresult.V_max, fitresult.V_mid, fitresult.k);
        else
            D_fit = BoltzmannModel.inactivation(V_fit, ...
                fitresult.V_min, fitresult.V_max, fitresult.V_mid, fitresult.k);
        end
        plot(V_fit, D_fit, 'r-', 'LineWidth', 2);
        
        hold off;
        grid on;
        xlabel('Voltage (mV)', 'FontSize', 12);
        ylabel(sprintf('%s (%s)', dataType, dataUnits), 'FontSize', 12);
        title(sprintf('Well %s: V_{1/2}=%.1f mV, k=%.1f mV, R²=%.3f', ...
            wellID, fitresult.V_mid, fitresult.k, gof.rsquare), ...
            'FontSize', 14, 'Interpreter', 'none');
        legend('Data', 'Boltzmann Fit', 'Location', 'best');
        
        fprintf('✓ Plot generated\n');
        
    catch ME
        fprintf('❌ FIT FAILED!\n\n');
        fprintf('--- ERROR DETAILS ---\n');
        fprintf('Error ID: %s\n', ME.identifier);
        fprintf('Message: %s\n', ME.message);
        
        if ~isempty(ME.stack)
            fprintf('\nStack trace:\n');
            for i = 1:min(3, length(ME.stack))
                fprintf('  %s (line %d)\n', ME.stack(i).name, ME.stack(i).line);
            end
        end
        
        fprintf('\n--- TROUBLESHOOTING SUGGESTIONS ---\n');
        
        % Diagnose likely causes
        if contains(ME.message, 'bound', 'IgnoreCase', true)
            fprintf('1. Check if bounds are too restrictive\n');
            fprintf('2. Try widening V_mid range or k limits\n');
        end
        
        if contains(ME.message, 'matrix', 'IgnoreCase', true) || ...
           contains(ME.message, 'dimension', 'IgnoreCase', true)
            fprintf('1. Check data dimensions\n');
            fprintf('2. Ensure V_valid and D_valid are column vectors\n');
        end
        
        if dataSpan < 1e-6
            fprintf('1. Data appears flat - sigmoid shape may not exist\n');
            fprintf('2. Check if correct data type being used\n');
            fprintf('3. For inactivation, verify normalization is correct\n');
        end
        
        fprintf('\n--- FULL ERROR REPORT ---\n');
        fprintf('%s\n', getReport(ME));
    end
    
    fprintf('\n=== DEBUG COMPLETE ===\n');
end
