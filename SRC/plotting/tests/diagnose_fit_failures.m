function diagnose_fit_failures()
    %DIAGNOSE_FIT_FAILURES Debug why Boltzmann fits are failing
    
    fprintf('=== DIAGNOSING BOLTZMANN FIT FAILURES ===\n\n');
    
    % Initialize
    config = NanionConfig();
    logger = NanionLogger(config);
    detector = NanionFileDetector(logger);
    ioManager = NanionIOManager(config, logger);
    extractor = NanionDataExtractor(config, logger);
    fitter = NanionBoltzmannFitter(config, logger);
    
    % Select file
    [filename, pathname] = uigetfile('*.xlsx', 'Select Nanion File');
    if isequal(filename, 0)
        return;
    end
    filePath = fullfile(pathname, filename);
    
    % Process data
    fprintf('Processing: %s\n\n', filename);
    protocolInfo = detector.detectProtocol(filePath);
    rawData = ioManager.readFile(filePath);
    parsedData = ioManager.parseData(rawData, protocolInfo);
    extractedData = extractor.extractMeasurements(parsedData);
    filteredData = extractor.applyQualityFilters(extractedData);
    
    if filteredData.numWellsPassed == 0
        fprintf('No wells passed filtering.\n');
        return;
    end
    
    % Test first passing well
    wellIdx = 1;
    wellID = filteredData.wellIDs(wellIdx);
    
    fprintf('--- Testing Well %s (First Passing Well) ---\n\n', wellID);
    
    % Extract IV1 conductance
    iv1_conductance = filteredData.measurements.iv1.conductance(wellIdx, :);
    voltages = protocolInfo.voltages;
    
    fprintf('IV1 Data:\n');
    fprintf('  Voltages: [%.1f ... %.1f] mV (%d points)\n', ...
        voltages(1), voltages(end), length(voltages));
    fprintf('  Conductance range: %.2f to %.2f nS\n', ...
        min(iv1_conductance), max(iv1_conductance));
    fprintf('  Valid points: %d/%d\n', sum(~isnan(iv1_conductance)), length(iv1_conductance));
    
    % Check for problematic data
    fprintf('\n--- Data Quality Checks ---\n');
    
    if all(isnan(iv1_conductance))
        fprintf('  ❌ All conductance values are NaN!\n');
        return;
    end
    
    if sum(~isnan(iv1_conductance)) < 10
        fprintf('  ⚠ Very few valid points (%d)\n', sum(~isnan(iv1_conductance)));
    end
    
    if all(iv1_conductance(~isnan(iv1_conductance)) <= 0)
        fprintf('  ⚠ All conductance values are negative or zero\n');
        fprintf('     This suggests the data may not be suitable for activation fitting\n');
    end
    
    if max(iv1_conductance) - min(iv1_conductance) < 0.1
        fprintf('  ⚠ Very small conductance range (%.3f nS)\n', ...
            max(iv1_conductance) - min(iv1_conductance));
        fprintf('     Boltzmann fit may fail with flat data\n');
    end
    
    % Display data points
    fprintf('\n--- Voltage vs Conductance ---\n');
    for i = 1:length(voltages)
        if ~isnan(iv1_conductance(i))
            fprintf('  %.1f mV → %.3f nS\n', voltages(i), iv1_conductance(i));
        else
            fprintf('  %.1f mV → NaN\n', voltages(i));
        end
    end
    
    % Attempt fit with full error reporting
    fprintf('\n--- Attempting Boltzmann Fit ---\n');
    try
        fitResult = fitter.fitBoltzmannCurve(voltages, iv1_conductance, 'activation');
        fprintf('✓ Fit succeeded!\n');
        fprintf('  V_mid = %.2f mV\n', fitResult.params.V_mid);
        fprintf('  k = %.2f mV\n', fitResult.params.k);
        fprintf('  R² = %.4f\n', fitResult.quality.rsquared);
    catch ME
        fprintf('❌ Fit failed with error:\n');
        fprintf('   %s\n\n', ME.message);
        fprintf('Stack trace:\n');
        fprintf('%s\n', getReport(ME, 'extended'));
    end
    
    fprintf('\n=== DIAGNOSIS COMPLETE ===\n');
end
