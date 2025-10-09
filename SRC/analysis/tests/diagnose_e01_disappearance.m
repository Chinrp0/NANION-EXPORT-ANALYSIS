function diagnose_e01_disappearance()
    %DIAGNOSE_E01_DISAPPEARANCE Find why E01 is missing from extracted data
    %   Inspects raw Excel file to trace E01 through extraction pipeline
    
    fprintf('=== DIAGNOSING E01 DISAPPEARANCE ===\n\n');
    
    % Initialize
    config = NanionConfig();
    logger = NanionLogger(config);
    detector = NanionFileDetector(logger);
    ioManager = NanionIOManager(config, logger);
    
    % Select file
    [filename, pathname] = uigetfile('*.xlsx', 'Select Nanion File');
    if isequal(filename, 0)
        return;
    end
    filePath = fullfile(pathname, filename);
    
    fprintf('File: %s\n\n', filename);
    
    %% STEP 1: Read raw Excel file directly
    fprintf('--- STEP 1: Raw Excel Inspection ---\n');
    rawData = readcell(filePath);
    fprintf('Total rows in file: %d\n', size(rawData, 1));
    fprintf('Total columns in file: %d\n\n', size(rawData, 2));
    
    % Check absolute row 15
    fprintf('Absolute Row 15 Contents:\n');
    fprintf('  Column 1: "%s" (class: %s)\n', string(rawData{15, 1}), class(rawData{15, 1}));
    if size(rawData, 2) >= 2
        fprintf('  Column 2: "%s"\n', string(rawData{15, 2}));
    end
    if size(rawData, 2) >= 3
        fprintf('  Column 3: "%s"\n', string(rawData{15, 3}));
    end
    fprintf('\n');
    
    % Search for E01 in the file
    fprintf('Searching for "E01" in entire file...\n');
    e01Locations = [];
    for row = 1:size(rawData, 1)
        for col = 1:min(10, size(rawData, 2))  % Check first 10 columns
            cellValue = rawData{row, col};
            if ischar(cellValue) || isstring(cellValue)
                if strcmpi(string(cellValue), "E01")
                    e01Locations = [e01Locations; row, col];
                    fprintf('  Found "E01" at row %d, column %d\n', row, col);
                end
            end
        end
    end
    
    if isempty(e01Locations)
        fprintf('  ❌ E01 not found anywhere in file!\n');
        return;
    end
    fprintf('\n');
    
    %% STEP 2: Protocol detection (sets header structure)
    fprintf('--- STEP 2: Protocol Detection ---\n');
    protocolInfo = detector.detectProtocol(filePath);
    fprintf('Protocol type: %s\n', protocolInfo.type);
    fprintf('Number of IVs: %d\n', protocolInfo.numIVs);
    fprintf('Sweeps per IV: %d\n\n', protocolInfo.numSweeps);
    
    %% STEP 3: Data parsing (sets dataStartRow)
    fprintf('--- STEP 3: Data Parsing ---\n');
    parsedData = ioManager.parseData(rawData, protocolInfo);
    dataStartRow = parsedData.headerInfo.dataStartRow;
    
    fprintf('dataStartRow = %d\n', dataStartRow);
    fprintf('This means extraction starts at absolute row %d\n\n', dataStartRow);
    
    % Critical check: Is E01 before dataStartRow?
    e01Row = e01Locations(1, 1);  % First occurrence
    if e01Row < dataStartRow
        fprintf('❌ PROBLEM FOUND!\n');
        fprintf('   E01 is at row %d\n', e01Row);
        fprintf('   But extraction starts at row %d\n', dataStartRow);
        fprintf('   E01 is being SKIPPED during extraction!\n\n');
        fprintf('   Solution: Check how dataStartRow is calculated in NanionIOManager.parseData()\n');
        return;
    else
        fprintf('✓ E01 row (%d) is after dataStartRow (%d)\n\n', e01Row, dataStartRow);
    end
    
    %% STEP 4: Well ID extraction
    fprintf('--- STEP 4: Well ID Extraction ---\n');
    dataTable = parsedData.dataTable;
    
    % Manually replicate extractWellIDs logic
    wellColumn = dataTable{dataStartRow:end, 1};
    fprintf('Number of rows from dataStartRow to end: %d\n', length(wellColumn));
    
    wellIDs_raw = string(wellColumn);
    fprintf('After string conversion: %d entries\n', length(wellIDs_raw));
    
    % Show first 10 entries
    fprintf('\nFirst 10 well IDs (raw):\n');
    for i = 1:min(10, length(wellIDs_raw))
        fprintf('  [%d] "%s" (missing: %d, empty: %d)\n', ...
            i, wellIDs_raw(i), ismissing(wellIDs_raw(i)), wellIDs_raw(i) == "");
    end
    
    % Apply the filter
    validMask = ~ismissing(wellIDs_raw) & wellIDs_raw ~= "";
    fprintf('\nAfter validMask filter:\n');
    fprintf('  Valid entries: %d\n', sum(validMask));
    fprintf('  Filtered out: %d\n', sum(~validMask));
    
    wellIDs_filtered = wellIDs_raw(validMask);
    
    % Check if E01 survived
    if any(strcmpi(wellIDs_filtered, "E01"))
        fprintf('  ✓ E01 is present in filtered wellIDs\n');
        e01Index = find(strcmpi(wellIDs_filtered, "E01"), 1);
        fprintf('  E01 is at index %d in filtered array\n', e01Index);
    else
        fprintf('  ❌ E01 was FILTERED OUT!\n\n');
        
        % Find out why
        e01IndexRaw = find(strcmpi(wellIDs_raw, "E01"), 1);
        if isempty(e01IndexRaw)
            fprintf('  Reason: E01 not in wellIDs_raw (wrong column?)\n');
        else
            fprintf('  E01 was at index %d in raw wellIDs\n', e01IndexRaw);
            fprintf('  E01 value: "%s"\n', wellIDs_raw(e01IndexRaw));
            fprintf('  ismissing: %d\n', ismissing(wellIDs_raw(e01IndexRaw)));
            fprintf('  equals "": %d\n', wellIDs_raw(e01IndexRaw) == "");
            
            if wellIDs_raw(e01IndexRaw) == ""
                fprintf('  Reason: E01 was converted to empty string!\n');
            elseif ismissing(wellIDs_raw(e01IndexRaw))
                fprintf('  Reason: E01 was marked as missing!\n');
            end
        end
    end
    
    %% STEP 5: Full extraction
    fprintf('\n--- STEP 5: Full Extraction ---\n');
    extractor = NanionDataExtractor(config, logger);
    extractedData = extractor.extractMeasurements(parsedData);
    
    fprintf('Extracted wells: %d\n', extractedData.numWells);
    
    if any(strcmpi(extractedData.wellIDs, "E01"))
        fprintf('✓ E01 is in extractedData.wellIDs\n');
    else
        fprintf('❌ E01 is NOT in extractedData.wellIDs\n');
    end
    
    fprintf('\n=== DIAGNOSIS COMPLETE ===\n');
end
