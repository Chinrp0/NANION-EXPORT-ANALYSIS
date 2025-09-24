function debug_data_extraction()
%DEBUG_DATA_EXTRACTION Detailed debugging for Phase 2 data extraction

fprintf('=== DEBUG DATA EXTRACTION ===\n\n');

% Select a single file for debugging
[filename, pathname] = uigetfile({'*.xlsx;*.xls', 'Excel Files'}, ...
    'Select ONE test file for debugging');

if isequal(filename, 0)
    fprintf('No file selected. Debug cancelled.\n');
    return;
end

filePath = fullfile(pathname, filename);

try
    % Initialize components
    config = NanionConfig();
    logger = NanionLogger(config);
    ioManager = NanionIOManager(config, logger);
    fileDetector = NanionFileDetector(logger);
    dataExtractor = NanionDataExtractor(config, logger);
    
    fprintf('=== STEP 1: PROTOCOL DETECTION ===\n');
    protocolInfo = fileDetector.detectProtocol(filePath);
    fprintf('Protocol: %s, IVs: %d\n', protocolInfo.type, protocolInfo.numIVs);
    
    fprintf('\n=== STEP 2: FILE READING ===\n');
    rawData = ioManager.readFile(filePath);
    fprintf('Raw data size: %dx%d\n', size(rawData));
    
    fprintf('\n=== STEP 3: DATA PARSING ===\n');
    parsedData = ioManager.parseData(rawData, protocolInfo);
    fprintf('Parsed table size: %dx%d\n', size(parsedData.dataTable));
    fprintf('Header rows: %d\n', parsedData.headerRows);
    
    fprintf('\n=== STEP 4: MEASUREMENT EXTRACTION (NEW) ===\n');
    extractedData = dataExtractor.extractMeasurements(parsedData);
    
    fprintf('Well IDs extracted: %d\n', length(extractedData.wellIDs));
    fprintf('First 5 Well IDs: ');
    for i = 1:min(5, length(extractedData.wellIDs))
        fprintf('%s ', extractedData.wellIDs(i));
    end
    fprintf('\n');
    
    % Check measurements structure
    ivFields = fieldnames(extractedData.measurements);
    fprintf('IVs found: %s\n', strjoin(ivFields, ', '));
    
    % Examine IV1 data
    if isfield(extractedData.measurements, 'iv1')
        iv1 = extractedData.measurements.iv1;
        paramFields = fieldnames(iv1);
        fprintf('IV1 parameters: %s\n', strjoin(paramFields, ', '));
        
        % Show sample values
        for i = 1:length(paramFields)
            param = paramFields{i};
            values = iv1.(param);
            fprintf('  %s: %.3f ± %.3f (n=%d)\n', param, ...
                mean(values, 'omitnan'), std(values, 'omitnan'), ...
                sum(~isnan(values)));
        end
    end
    
    fprintf('\n=== STEP 5: QUALITY FILTERING (NEW) ===\n');
    filteredData = dataExtractor.applyQualityFilters(extractedData);
    
    fprintf('Wells passed filtering: %d/%d (%.1f%%)\n', ...
        filteredData.numWellsPassed, filteredData.numWellsTotal, ...
        100 * filteredData.numWellsPassed / filteredData.numWellsTotal);
    
    % Show filter breakdown
    report = filteredData.filterReport;
    fprintf('Filter failures:\n');
    fprintf('  Series R: %d wells\n', report.seriesFailures.count);
    fprintf('  Seal R: %d wells\n', report.sealFailures.count);
    fprintf('  Capacitance: %d wells\n', report.capacitanceFailures.count);
    
    fprintf('\n✓ DEBUG COMPLETE - Data extraction working!\n');
    
    % Save debug results
    debugResults = struct('extractedData', extractedData, 'filteredData', filteredData);
    save(fullfile(pathname, 'debug_extraction_results.mat'), 'debugResults');
    fprintf('Debug results saved to: debug_extraction_results.mat\n');
    
catch ME
    fprintf('\n❌ DEBUG FAILED: %s\n', ME.message);
    fprintf('Stack: %s\n', getReport(ME));
end
end