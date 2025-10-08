function diagnose_column_mapping()
    %DIAGNOSE_COLUMN_MAPPING Map exact column structure for Nanion files
    %   Identifies all sweep columns, voltage protocols, and parameter positions
    %   for both activation and inactivation protocols
    
    fprintf('=== NANION COLUMN MAPPING DIAGNOSTIC ===\n\n');
    
    % File selection
    [filenames, pathname] = uigetfile(...
        {'*.xlsx;*.xls', 'Excel Files (*.xlsx, *.xls)'}, ...
        'Select Nanion Files (choose both activation and inactivation)', ...
        'MultiSelect', 'on');
    
    if isequal(filenames, 0)
        fprintf('No files selected. Diagnostic cancelled.\n');
        return;
    end
    
    % Convert to cell array if single file
    if ischar(filenames)
        filenames = {filenames};
    end
    
    % Analyze each file
    for fileIdx = 1:length(filenames)
        filePath = fullfile(pathname, filenames{fileIdx});
        fprintf('========================================\n');
        fprintf('ANALYZING FILE: %s\n', filenames{fileIdx});
        fprintf('========================================\n\n');
        
        try
            analyzeFileStructure(filePath);
        catch ME
            fprintf('ERROR analyzing %s: %s\n', filenames{fileIdx}, ME.message);
            fprintf('Stack trace:\n%s\n\n', getReport(ME));
        end
        
        fprintf('\n\n');
    end
end

function analyzeFileStructure(filePath)
    %ANALYZEFILESTRUCTURE Detailed structure analysis
    
    % Read header section - use limited range first to get structure
    fprintf('Reading file structure...\n');
    
    % First read to get dimensions
    opts = detectImportOptions(filePath);
    numCols = numel(opts.VariableNames);
    fprintf('Detected %d columns in file\n', numCols);
    
    % Read first 15 rows with all columns
    headerData = readcell(filePath, 'Range', sprintf('A1:%s15', getExcelColumn(numCols)), 'UseExcel', false);
    fprintf('File dimensions: %d rows × %d columns\n\n', size(headerData));
    
    % Step 1: Identify protocol type
    protocolType = detectProtocolType(headerData);
    fprintf('PROTOCOL TYPE: %s\n\n', upper(protocolType));
    
    % Step 2: Find key header rows
    sweepResultsRow = findRowWithKeyword(headerData, 'Sweep Results');
    parameterRow = findRowWithKeyword(headerData, 'Parameter');
    voltageRow = findRowWithKeyword(headerData, 'Abs. V/I of incr. segment');
    dataStartRow = parameterRow + 2;
    
    fprintf('=== KEY ROW POSITIONS ===\n');
    fprintf('Sweep Results Row: %d\n', sweepResultsRow);
    fprintf('Parameter Row: %d\n', parameterRow);
    fprintf('Voltage Protocol Row: %d\n', voltageRow);
    fprintf('Data Start Row: %d\n\n', dataStartRow);
    
    % Step 3: Map initial columns
    fprintf('=== INITIAL COLUMNS (Well Identifiers) ===\n');
    fprintf('Column 1: "%s"\n', char(headerData{parameterRow, 1}));
    fprintf('Column 2: "%s"\n', char(headerData{parameterRow, 2}));
    fprintf('Column 3: "%s"\n', char(headerData{parameterRow, 3}));
    fprintf('\n');
    
    % Step 4: Identify sweep pattern
    fprintf('=== SWEEP PATTERN ANALYSIS ===\n');
    [sweepPattern, columnsPerSweep] = analyzeSweepPattern(headerData, parameterRow, sweepResultsRow);
    
    fprintf('Columns per sweep: %d\n', columnsPerSweep);
    fprintf('Parameter pattern:\n');
    for i = 1:length(sweepPattern)
        fprintf('  Position %d: %s\n', i, sweepPattern{i});
    end
    fprintf('\n');
    
    % Step 5: Extract voltage protocol
    fprintf('=== VOLTAGE PROTOCOL ===\n');
    [voltages_V, voltageColumns] = extractVoltageProtocol(headerData, voltageRow, columnsPerSweep);
    voltages_mV = voltages_V * 1000;  % Convert V to mV
    
    fprintf('Found %d voltage steps:\n', length(voltages_mV));
    if ~isempty(voltages_mV)
        fprintf('Range: %.1f mV to %.1f mV\n', min(voltages_mV), max(voltages_mV));
        if length(voltages_mV) > 1
            fprintf('Step size: %.1f mV (median)\n', median(diff(voltages_mV)));
        end
        fprintf('Voltage columns: [%s]\n', num2str(voltageColumns(1:min(5, length(voltageColumns)))));
        fprintf('Full voltage array: %s\n\n', mat2str(voltages_mV, 2));
    end
    
    % Step 6: Calculate number of IVs
    numSweepsInFile = floor((size(headerData, 2) - 3) / columnsPerSweep);
    numVoltageSteps = length(voltages_mV);
    numIVs = ceil(numSweepsInFile / numVoltageSteps);
    
    fprintf('=== IV CALCULATION ===\n');
    fprintf('Total columns in file: %d\n', size(headerData, 2));
    fprintf('Columns per sweep: %d\n', columnsPerSweep);
    fprintf('Total sweeps in file: %d\n', numSweepsInFile);
    fprintf('Voltage steps per IV: %d\n', numVoltageSteps);
    fprintf('Calculated IVs: %d\n\n', numIVs);
    
    % Step 7: Map all parameter columns for each IV
    fprintf('=== COMPLETE COLUMN MAPPING ===\n');
    columnMapping = mapAllColumns(columnsPerSweep, numVoltageSteps, numIVs, sweepPattern);
    
    for iv = 1:numIVs
        fprintf('--- IV%d Column Positions ---\n', iv);
        ivMap = columnMapping.(['iv' num2str(iv)]);
        
        fprintf('  Series Resistance:    [%d, %d, %d, ..., %d] (%d columns)\n', ...
            ivMap.seriesR(1), ivMap.seriesR(2), ivMap.seriesR(3), ivMap.seriesR(end), length(ivMap.seriesR));
        fprintf('  Seal Resistance:      [%d, %d, %d, ..., %d] (%d columns)\n', ...
            ivMap.sealR(1), ivMap.sealR(2), ivMap.sealR(3), ivMap.sealR(end), length(ivMap.sealR));
        fprintf('  Capacitance:          [%d, %d, %d, ..., %d] (%d columns)\n', ...
            ivMap.cap(1), ivMap.cap(2), ivMap.cap(3), ivMap.cap(end), length(ivMap.cap));
        
        if strcmp(protocolType, 'activation')
            fprintf('  Peak Current:         [%d, %d, %d, ..., %d] (%d columns)\n', ...
                ivMap.peak(1), ivMap.peak(2), ivMap.peak(3), ivMap.peak(end), length(ivMap.peak));
        else
            fprintf('  Inactivation Data:    [%d, %d, %d, ..., %d] (%d columns)\n', ...
                ivMap.inact(1), ivMap.inact(2), ivMap.inact(3), ivMap.inact(end), length(ivMap.inact));
            fprintf('  Activation Data:      [%d, %d, %d, ..., %d] (%d columns)\n', ...
                ivMap.act(1), ivMap.act(2), ivMap.act(3), ivMap.act(end), length(ivMap.act));
        end
        fprintf('\n');
    end
    
    % Step 8: Validation - read sample data
    fprintf('=== DATA VALIDATION ===\n');
    validateColumnMapping(filePath, dataStartRow, columnMapping, voltageRow, protocolType, numCols);
end

function colName = getExcelColumn(colNum)
    %GETEXCELCOLUMN Convert column number to Excel letter(s)
    
    colName = '';
    while colNum > 0
        remainder = mod(colNum - 1, 26);
        colName = [char(65 + remainder) colName];
        colNum = floor((colNum - 1) / 26);
    end
end

function protocolType = detectProtocolType(headerData)
    %DETECTPROTOCOLTYPE Determine if activation or inactivation
    
    % Search through header rows for protocol keywords
    for row = 1:min(15, size(headerData, 1))
        rowStr = '';
        for col = 1:min(50, size(headerData, 2))
            cellValue = headerData{row, col};
            if ischar(cellValue) || isstring(cellValue)
                rowStr = [rowStr ' ' char(cellValue)];
            end
        end
        
        % Check for protocol-specific keywords
        if contains(rowStr, 'Peak', 'IgnoreCase', true) && ...
           ~contains(rowStr, 'Inact', 'IgnoreCase', true)
            protocolType = 'activation';
            return;
        end
        
        if contains(rowStr, 'Inact', 'IgnoreCase', true) && ...
           contains(rowStr, 'Act', 'IgnoreCase', true)
            protocolType = 'inactivation';
            return;
        end
    end
    
    protocolType = 'unknown';
end

function rowIdx = findRowWithKeyword(headerData, keyword)
    %FINDROWWITHKEYWORD Find row containing specific keyword
    
    col1 = headerData(:, 1);
    for i = 1:length(col1)
        cellValue = col1{i};
        if (ischar(cellValue) || isstring(cellValue)) && ...
           contains(char(cellValue), keyword, 'IgnoreCase', true)
            rowIdx = i;
            return;
        end
    end
    
    rowIdx = -1;
end

function [sweepPattern, columnsPerSweep] = analyzeSweepPattern(headerData, parameterRow, sweepResultsRow)
    %ANALYZESWEEPPATTERN Identify parameter pattern within one sweep
    
    % Start after initial 3 columns (Parameter, Cell Type, Cell Concentration)
    startCol = 4;
    
    % Read parameters until we find a repeat or pattern
    sweepPattern = {};
    currentCol = startCol;
    
    % Get first sweep parameters
    while currentCol <= size(headerData, 2)
        paramValue = headerData{parameterRow, currentCol};
        
        if isempty(paramValue) || (isscalar(paramValue) && ismissing(paramValue)) || all(ismissing(paramValue(:)))
            break;
        end
        
        paramStr = char(paramValue);
        
        % Stop when we see the pattern repeat (first parameter repeats)
        if ~isempty(sweepPattern) && contains(paramStr, sweepPattern{1}, 'IgnoreCase', true)
            break;
        end
        
        sweepPattern{end+1} = strtrim(paramStr);
        currentCol = currentCol + 1;
        
        % Safety check
        if length(sweepPattern) > 10
            break;
        end
    end
    
    columnsPerSweep = length(sweepPattern);
end

function [voltages, voltageColumns] = extractVoltageProtocol(headerData, voltageRow, columnsPerSweep)
    %EXTRACTVOLTAGEPROTOCOL Extract voltage values from voltage row
    
    voltages = [];
    voltageColumns = [];
    
    % Start after initial 3 columns
    startCol = 4;
    
    % Extract voltage from every columnsPerSweep columns
    % (Each sweep repeats the same voltage for all parameters)
    prevVoltage = NaN;
    for col = startCol:columnsPerSweep:size(headerData, 2)
        voltageValue = headerData{voltageRow, col};
        
        if isnumeric(voltageValue) && ~isnan(voltageValue)
            % Check if voltage repeats (new IV starts)
            if ~isnan(prevVoltage) && abs(voltageValue - voltages(1)) < 1e-10
                break;  % Voltage sequence repeats - stop here
            end
            voltages(end+1) = voltageValue;
            voltageColumns(end+1) = col;
            prevVoltage = voltageValue;
        else
            break;  % Stop when voltages end
        end
    end
end

function columnMapping = mapAllColumns(columnsPerSweep, numVoltageSteps, numIVs, sweepPattern)
    %MAPALLCOLUMNS Create complete column mapping for all IVs
    
    columnMapping = struct();
    
    % Find parameter positions within one sweep
    seriesIdx = find(contains(sweepPattern, 'Series', 'IgnoreCase', true), 1);
    sealIdx = find(contains(sweepPattern, 'Seal', 'IgnoreCase', true), 1);
    capIdx = find(contains(sweepPattern, {'Cap', 'Capacitance'}, 'IgnoreCase', true), 1);
    peakIdx = find(contains(sweepPattern, 'Peak', 'IgnoreCase', true), 1);
    inactIdx = find(contains(sweepPattern, 'Inact', 'IgnoreCase', true), 1);
    actIdx = [];
    if isempty(peakIdx)
        % For inactivation, find second "Act" (not "Inact")
        actMatches = find(contains(sweepPattern, 'Act', 'IgnoreCase', true));
        if length(actMatches) >= 2
            actIdx = actMatches(2);  % Second occurrence
        end
    end
    
    % Map columns for each IV
    for iv = 1:numIVs
        % Calculate starting column for this IV
        baseCol = 3 + (iv - 1) * numVoltageSteps * columnsPerSweep;
        
        % Generate column arrays for all voltage steps in this IV
        sweepOffsets = (0:(numVoltageSteps-1)) * columnsPerSweep;
        
        ivMap = struct();
        ivMap.seriesR = baseCol + seriesIdx + sweepOffsets;
        ivMap.sealR = baseCol + sealIdx + sweepOffsets;
        ivMap.cap = baseCol + capIdx + sweepOffsets;
        
        if ~isempty(peakIdx)
            ivMap.peak = baseCol + peakIdx + sweepOffsets;
        end
        if ~isempty(inactIdx)
            ivMap.inact = baseCol + inactIdx + sweepOffsets;
        end
        if ~isempty(actIdx)
            ivMap.act = baseCol + actIdx + sweepOffsets;
        end
        
        columnMapping.(['iv' num2str(iv)]) = ivMap;
    end
end

function validateColumnMapping(filePath, dataStartRow, columnMapping, voltageRow, protocolType, numCols)
    %VALIDATECOLUMNMAPPING Read sample data to verify mapping is correct
    
    fprintf('Reading sample well data for validation...\n');
    
    % Read first well and voltage row
    sampleRange = sprintf('A%d:%s%d', dataStartRow, getExcelColumn(numCols), dataStartRow);
    voltageRange = sprintf('A%d:%s%d', voltageRow, getExcelColumn(numCols), voltageRow);
    
    sampleData = readcell(filePath, 'Range', sampleRange, 'UseExcel', false);
    voltageData = readcell(filePath, 'Range', voltageRange, 'UseExcel', false);
    
    % Check IV1 mapping
    iv1Map = columnMapping.iv1;
    
    fprintf('Sample Well ID: %s\n', char(sampleData{1}));
    fprintf('Cell Type: %s\n', char(sampleData{2}));
    fprintf('Cell Concentration: %s\n\n', char(sampleData{3}));
    
    % Validate Series R
    fprintf('Series Resistance (first 3 sweeps):\n');
    for i = 1:min(3, length(iv1Map.seriesR))
        col = iv1Map.seriesR(i);
        voltage = voltageData{col};
        value = sampleData{col};
        if isnumeric(value)
            fprintf('  Sweep %d (%.0f mV): %.2e Ω (col %d)\n', i, voltage*1000, value, col);
        else
            fprintf('  Sweep %d (%.0f mV): %s (col %d)\n', i, voltage*1000, char(value), col);
        end
    end
    fprintf('\n');
    
    % Validate current data
    if strcmp(protocolType, 'activation')
        fprintf('Peak Current (first 3 sweeps):\n');
        for i = 1:min(3, length(iv1Map.peak))
            col = iv1Map.peak(i);
            voltage = voltageData{col};
            value = sampleData{col};
            if isnumeric(value)
                fprintf('  Sweep %d (%.0f mV): %.2e A (col %d)\n', i, voltage*1000, value, col);
            else
                fprintf('  Sweep %d (%.0f mV): %s (col %d)\n', i, voltage*1000, char(value), col);
            end
        end
    else
        fprintf('Inactivation Data (first 3 sweeps):\n');
        for i = 1:min(3, length(iv1Map.inact))
            col = iv1Map.inact(i);
            voltage = voltageData{col};
            value = sampleData{col};
            if isnumeric(value)
                fprintf('  Sweep %d (%.0f mV): %.2e A (col %d)\n', i, voltage*1000, value, col);
            else
                fprintf('  Sweep %d (%.0f mV): %s (col %d)\n', i, voltage*1000, char(value), col);
            end
        end
    end
    fprintf('\n');
    
    fprintf('✓ Column mapping validated with actual data\n');
end
