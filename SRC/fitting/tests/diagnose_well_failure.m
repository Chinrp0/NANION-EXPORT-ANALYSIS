function diagnose_well_failure()
    %DIAGNOSE_WELL_FAILURE Check why specific wells failed quality filtering
    
    fprintf('=== WELL QUALITY DIAGNOSTIC ===\n\n');
    
    % Initialize
    config = NanionConfig();
    logger = NanionLogger(config);
    detector = NanionFileDetector(logger);
    ioManager = NanionIOManager(config, logger);
    extractor = NanionDataExtractor(config, logger);
    
    % Load file
    [filename, pathname] = uigetfile('*.xlsx', 'Select File');
    if isequal(filename, 0)
        return;
    end
    filePath = fullfile(pathname, filename);
    
    % Process
    protocolInfo = detector.detectProtocol(filePath);
    rawData = ioManager.readFile(filePath);
    parsedData = ioManager.parseData(rawData, protocolInfo);
    extractedData = extractor.extractMeasurements(parsedData);
    
    % Get UNFILTERED data
    fprintf('Total wells extracted: %d\n\n', extractedData.numWells);
    
    % Ask which well to diagnose
    targetWell = input('Enter well ID to diagnose (e.g., E01): ', 's');
    
    % Find well in UNFILTERED data
    wellIdx = find(strcmp(extractedData.wellIDs, targetWell), 1);
    
    if isempty(wellIdx)
        fprintf('❌ Well %s not found in extracted data\n', targetWell);
        return;
    end
    
    fprintf('\n--- DIAGNOSTIC FOR WELL %s ---\n\n', targetWell);
    
    % Get quality thresholds
    filters = config.filters;
    
    fprintf('Quality Filter Thresholds:\n');
    fprintf('  Max Series R: %.1f MΩ\n', filters.maxSeriesResistance);
    fprintf('  Max Seal R: %.1f GΩ\n', filters.maxSealResistance);
    fprintf('  Max Capacitance: %.1f pF\n', filters.maxCapacitance);
    fprintf('  Min Valid Sweeps: %d/23\n', filters.minValidSweeps);
    fprintf('  Outlier Threshold: %.1fx median\n\n', filters.outlierThreshold);
    
    % Check IV1
    fprintf('--- IV1 Analysis ---\n');
    checkIV(extractedData.measurements.iv1, wellIdx, filters, 'IV1');
    
    % Check IV2 if exists
    if isfield(extractedData.measurements, 'iv2')
        fprintf('\n--- IV2 Analysis ---\n');
        checkIV(extractedData.measurements.iv2, wellIdx, filters, 'IV2');
    end
    
    fprintf('\n=== DIAGNOSTIC COMPLETE ===\n');
end

function checkIV(ivData, wellIdx, filters, ivName)
    %CHECKIV Check quality metrics for one IV
    
    % Extract data for this well
    seriesR = ivData.seriesResistance(wellIdx, :);
    sealR = ivData.sealResistance(wellIdx, :);
    cap = ivData.capacitance(wellIdx, :);
    
    % Count valid sweeps
    seriesR_valid = sum(~isnan(seriesR));
    sealR_valid = sum(~isnan(sealR));
    cap_valid = sum(~isnan(cap));
    
    fprintf('%s Data Completeness:\n', ivName);
    fprintf('  Series R: %d/23 valid sweeps', seriesR_valid);
    if seriesR_valid < filters.minValidSweeps
        fprintf(' ❌ (< %d required)\n', filters.minValidSweeps);
    else
        fprintf(' ✓\n');
    end
    
    fprintf('  Seal R: %d/23 valid sweeps', sealR_valid);
    if sealR_valid < filters.minValidSweeps
        fprintf(' ❌ (< %d required)\n', filters.minValidSweeps);
    else
        fprintf(' ✓\n');
    end
    
    fprintf('  Capacitance: %d/23 valid sweeps', cap_valid);
    if cap_valid < filters.minValidSweeps
        fprintf(' ❌ (< %d required)\n', filters.minValidSweeps);
    else
        fprintf(' ✓\n');
    end
    
    % If insufficient data, skip further checks
    if seriesR_valid < filters.minValidSweeps || ...
       sealR_valid < filters.minValidSweeps || ...
       cap_valid < filters.minValidSweeps
        fprintf('\n%s FAILS: Insufficient valid data\n', ivName);
        return;
    end
    
    % Calculate statistics
    seriesR_median = median(seriesR, 'omitnan');
    seriesR_max = max(seriesR, [], 'omitnan');
    sealR_median = median(sealR, 'omitnan');
    sealR_max = max(sealR, [], 'omitnan');
    cap_median = median(cap, 'omitnan');
    cap_max = max(cap, [], 'omitnan');
    
    fprintf('\n%s Median Values:\n', ivName);
    
    % Series R check
    fprintf('  Series R median: %.2f MΩ', seriesR_median);
    if seriesR_median > filters.maxSeriesResistance
        fprintf(' ❌ (> %.1f MΩ)\n', filters.maxSeriesResistance);
    else
        fprintf(' ✓\n');
    end
    
    % Seal R check
    fprintf('  Seal R median: %.2f GΩ', sealR_median);
    if sealR_median > filters.maxSealResistance
        fprintf(' ❌ (> %.1f GΩ)\n', filters.maxSealResistance);
    else
        fprintf(' ✓\n');
    end
    
    % Capacitance check
    fprintf('  Capacitance median: %.2f pF', cap_median);
    if cap_median > filters.maxCapacitance
        fprintf(' ❌ (> %.1f pF)\n', filters.maxCapacitance);
    else
        fprintf(' ✓\n');
    end
    
    % Outlier checks
    fprintf('\n%s Outlier Checks:\n', ivName);
    
    seriesR_outlier = seriesR_max > seriesR_median * filters.outlierThreshold;
    fprintf('  Series R max/median: %.2f', seriesR_max / seriesR_median);
    if seriesR_outlier
        fprintf(' ❌ (> %.1fx threshold)\n', filters.outlierThreshold);
    else
        fprintf(' ✓\n');
    end
    
    sealR_outlier = sealR_max > sealR_median * filters.outlierThreshold;
    fprintf('  Seal R max/median: %.2f', sealR_max / sealR_median);
    if sealR_outlier
        fprintf(' ❌ (> %.1fx threshold)\n', filters.outlierThreshold);
    else
        fprintf(' ✓\n');
    end
    
    cap_outlier = cap_max > cap_median * filters.outlierThreshold;
    fprintf('  Capacitance max/median: %.2f', cap_max / cap_median);
    if cap_outlier
        fprintf(' ❌ (> %.1fx threshold)\n', filters.outlierThreshold);
    else
        fprintf(' ✓\n');
    end
    
    % Overall pass/fail
    medianPass = (seriesR_median <= filters.maxSeriesResistance) && ...
                 (sealR_median <= filters.maxSealResistance) && ...
                 (cap_median <= filters.maxCapacitance);
    
    outlierPass = ~seriesR_outlier && ~sealR_outlier && ~cap_outlier;
    
    fprintf('\n%s Overall: ', ivName);
    if medianPass && outlierPass
        fprintf('✓ PASSES all checks\n');
    else
        fprintf('❌ FAILS\n');
        if ~medianPass
            fprintf('  Reason: Median exceeds threshold\n');
        end
        if ~outlierPass
            fprintf('  Reason: Outlier detected (max >> median)\n');
        end
    end
end
