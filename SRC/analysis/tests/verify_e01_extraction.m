function verify_e01_extraction()
    %VERIFY_E01_EXTRACTION Confirm E01 is properly extracted with data
    
    fprintf('=== VERIFYING E01 EXTRACTION ===\n\n');
    
    % Initialize pipeline
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
    
    fprintf('--- Extraction Summary ---\n');
    fprintf('Total wells extracted: %d\n', extractedData.numWells);
    fprintf('Expected wells: 384 (16 rows × 24 columns)\n\n');
    
    % Check first 10 wells
    fprintf('--- First 10 Wells ---\n');
    for i = 1:min(10, length(extractedData.wellIDs))
        fprintf('  [%d] %s\n', i, extractedData.wellIDs(i));
    end
    fprintf('\n');
    
    % Find E01
    e01Index = find(strcmpi(extractedData.wellIDs, "E01"), 1);
    
    if isempty(e01Index)
        fprintf('❌ E01 NOT FOUND in extracted data!\n');
        return;
    end
    
    fprintf('✓ E01 FOUND at index %d\n\n', e01Index);
    
    % Extract E01 data
    fprintf('--- E01 Data Summary (IV1) ---\n');
    iv1 = extractedData.measurements.iv1;
    
    % Series Resistance
    e01_seriesR = iv1.seriesResistance(e01Index, :);
    validSR = ~isnan(e01_seriesR);
    fprintf('Series Resistance:\n');
    fprintf('  Valid sweeps: %d/23\n', sum(validSR));
    fprintf('  Range: %.2f to %.2f MΩ\n', min(e01_seriesR(validSR)), max(e01_seriesR(validSR)));
    fprintf('  Median: %.2f MΩ\n', median(e01_seriesR, 'omitnan'));
    
    % Seal Resistance
    e01_sealR = iv1.sealResistance(e01Index, :);
    validSealR = ~isnan(e01_sealR);
    fprintf('\nSeal Resistance:\n');
    fprintf('  Valid sweeps: %d/23\n', sum(validSealR));
    fprintf('  Range: %.2f to %.2f GΩ\n', min(e01_sealR(validSealR)), max(e01_sealR(validSealR)));
    fprintf('  Median: %.2f GΩ\n', median(e01_sealR, 'omitnan'));
    
    % Capacitance
    e01_cap = iv1.capacitance(e01Index, :);
    validCap = ~isnan(e01_cap);
    fprintf('\nCapacitance:\n');
    fprintf('  Valid sweeps: %d/23\n', sum(validCap));
    fprintf('  Range: %.2f to %.2f pF\n', min(e01_cap(validCap)), max(e01_cap(validCap)));
    fprintf('  Median: %.2f pF\n', median(e01_cap, 'omitnan'));
    
    % Peak Current (if activation protocol)
    if isfield(iv1, 'peakCurrent')
        e01_current = iv1.peakCurrent(e01Index, :);
        validCurrent = ~isnan(e01_current);
        fprintf('\nPeak Current:\n');
        fprintf('  Valid sweeps: %d/23\n', sum(validCurrent));
        fprintf('  Range: %.2f to %.2f pA\n', min(e01_current(validCurrent)), max(e01_current(validCurrent)));
        
        % Show I-V relationship (first 5 points)
        fprintf('\n  Voltage vs Current (first 5 points):\n');
        for i = 1:min(5, length(protocolInfo.voltages))
            if validCurrent(i)
                fprintf('    %.1f mV → %.2f pA\n', protocolInfo.voltages(i), e01_current(i));
            end
        end
    end
    
    % Conductance (if available)
    if isfield(iv1, 'conductance')
        e01_conductance = iv1.conductance(e01Index, :);
        validG = ~isnan(e01_conductance);
        fprintf('\nConductance:\n');
        fprintf('  Valid sweeps: %d/23\n', sum(validG));
        fprintf('  Range: %.2f to %.2f nS\n', min(e01_conductance(validG)), max(e01_conductance(validG)));
    end
    
    % Quality check
    fprintf('\n--- Quality Assessment ---\n');
    medianSeriesR = median(e01_seriesR, 'omitnan');
    medianSealR = median(e01_sealR, 'omitnan');
    medianCap = median(e01_cap, 'omitnan');
    
    thresholds = config.filters;
    
    fprintf('Series R: %.2f MΩ (threshold: %.2f) ', medianSeriesR, thresholds.maxSeriesResistance);
    if medianSeriesR <= thresholds.maxSeriesResistance
        fprintf('✓ PASS\n');
    else
        fprintf('✗ FAIL\n');
    end
    
    fprintf('Seal R: %.2f GΩ (threshold: %.2f) ', medianSealR, thresholds.maxSealResistance);
    if medianSealR <= thresholds.maxSealResistance
        fprintf('✓ PASS\n');
    else
        fprintf('✗ FAIL\n');
    end
    
    fprintf('Capacitance: %.2f pF (threshold: %.2f) ', medianCap, thresholds.maxCapacitance);
    if medianCap <= thresholds.maxCapacitance
        fprintf('✓ PASS\n');
    else
        fprintf('✗ FAIL\n');
    end
    
    fprintf('\n=== VERIFICATION COMPLETE ===\n');
end