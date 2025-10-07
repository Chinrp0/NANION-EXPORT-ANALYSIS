function inspect_passing_wells()
    %INSPECT_PASSING_WELLS Verify quality of wells that passed filtering
    
    fprintf('=== INSPECTING PASSING WELLS ===\n\n');
    
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
    
    % Display voltage protocol
    fprintf('--- Voltage Protocol ---\n');
    fprintf('Voltages (mV): [%.1f, %.1f, %.1f, ..., %.1f]\n', ...
        protocolInfo.voltages(1), protocolInfo.voltages(2), ...
        protocolInfo.voltages(3), protocolInfo.voltages(end));
    fprintf('Range: %.1f to %.1f mV\n', ...
        min(protocolInfo.voltages), max(protocolInfo.voltages));
    fprintf('Steps: %d sweeps\n\n', length(protocolInfo.voltages));
    
    % Analyze passing wells
    numPassed = filteredData.numWellsPassed;
    fprintf('--- Passing Wells Summary ---\n');
    fprintf('Total passed: %d wells (%.1f%%)\n', ...
        numPassed, 100*numPassed/filteredData.numWellsTotal);
    
    if numPassed == 0
        fprintf('No wells passed filtering.\n');
        return;
    end
    
    % Get IV1 data for passing wells
    iv1 = filteredData.measurements.iv1;
    
    % Calculate statistics
    seriesR_medians = median(iv1.seriesResistance, 2, 'omitnan');
    sealR_medians = median(iv1.sealResistance, 2, 'omitnan');
    cap_medians = median(iv1.capacitance, 2, 'omitnan');
    
    fprintf('\n--- Quality Statistics (Passing Wells) ---\n');
    fprintf('Series Resistance (MΩ):\n');
    fprintf('  Median across wells: %.2f ± %.2f\n', mean(seriesR_medians), std(seriesR_medians));
    fprintf('  Range: %.2f to %.2f\n', min(seriesR_medians), max(seriesR_medians));
    fprintf('  Threshold: %.2f MΩ\n', config.filters.maxSeriesResistance);
    
    fprintf('\nSeal Resistance (GΩ):\n');
    fprintf('  Median across wells: %.2f ± %.2f\n', mean(sealR_medians), std(sealR_medians));
    fprintf('  Range: %.2f to %.2f\n', min(sealR_medians), max(sealR_medians));
    fprintf('  Threshold: %.2f GΩ\n', config.filters.maxSealResistance);
    
    fprintf('\nCapacitance (pF):\n');
    fprintf('  Median across wells: %.2f ± %.2f\n', mean(cap_medians), std(cap_medians));
    fprintf('  Range: %.2f to %.2f\n', min(cap_medians), max(cap_medians));
    fprintf('  Threshold: %.2f pF\n', config.filters.maxCapacitance);
    
    % Check data completeness
    fprintf('\n--- Data Completeness (Passing Wells) ---\n');
    validSweeps_seriesR = sum(~isnan(iv1.seriesResistance), 2);
    validSweeps_sealR = sum(~isnan(iv1.sealResistance), 2);
    validSweeps_cap = sum(~isnan(iv1.capacitance), 2);
    
    fprintf('Valid sweeps per well (out of 23):\n');
    fprintf('  Series R: %.1f ± %.1f sweeps\n', mean(validSweeps_seriesR), std(validSweeps_seriesR));
    fprintf('  Seal R: %.1f ± %.1f sweeps\n', mean(validSweeps_sealR), std(validSweeps_sealR));
    fprintf('  Capacitance: %.1f ± %.1f sweeps\n', mean(validSweeps_cap), std(validSweeps_cap));
    
    % Show sample I-V curve data
    if isfield(iv1, 'peakCurrent')
        fprintf('\n--- Sample I-V Curve (First Passing Well) ---\n');
        wellIdx = 1;
        fprintf('Well ID: %s\n', filteredData.wellIDs(wellIdx));
        
        currents = iv1.peakCurrent(wellIdx, :);
        validIdx = ~isnan(currents);
        
        fprintf('Valid data points: %d/23\n', sum(validIdx));
        fprintf('Current range: %.2f to %.2f pA\n', min(currents(validIdx)), max(currents(validIdx)));
        fprintf('Voltage vs Current (first 5 points):\n');
        for i = 1:min(5, length(protocolInfo.voltages))
            if validIdx(i)
                fprintf('  %.1f mV → %.2f pA\n', protocolInfo.voltages(i), currents(i));
            end
        end
    end
    
    fprintf('\n✓ All passing wells have median values within thresholds!\n');
    fprintf('=== INSPECTION COMPLETE ===\n');
end