function diagnose_capacitance()
    %DIAGNOSE_CAPACITANCE Find where capacitance data is actually stored
    
    fprintf('=== DIAGNOSING CAPACITANCE COLUMN MAPPING ===\n\n');
    
    testFile = "C:/Users/xdach/OneDrive - Johns Hopkins/Maher_Lab/Protocols/Matlab_scripts/Fede/Master files for CHIN 9_17_2025/18T22880 NGN2 ACT_IV raw.xlsx";
    
    if ~exist(testFile, 'file')
        fprintf('❌ Test file not found: %s\n', testFile);
        return;
    end
    
    try
        % Read raw data
        fprintf('Reading raw data...\n');
        rawData = readcell(testFile, 'UseExcel', false);
        
        % Look at header rows to understand structure
        fprintf('\n=== HEADER ANALYSIS ===\n');
        fprintf('Examining rows 1-15, columns 1-50...\n\n');
        
        for row = 1:15
            fprintf('Row %2d: ', row);
            for col = 1:min(50, size(rawData, 2))
                cellVal = rawData{row, col};
                if ~isempty(cellVal) && ~(isnumeric(cellVal) && isnan(cellVal))
                    if ischar(cellVal) || isstring(cellVal)
                        cellStr = char(cellVal);
                        if length(cellStr) > 15
                            cellStr = [cellStr(1:12), '...'];
                        end
                        fprintf('[%s] ', cellStr);
                    else
                        fprintf('[%.2g] ', cellVal);
                    end
                end
                
                % Stop after finding a few non-empty cells to avoid clutter
                if col > 30
                    break;
                end
            end
            fprintf('\n');
        end
        
        % Look for capacitance keywords
        fprintf('\n=== SEARCHING FOR CAPACITANCE KEYWORDS ===\n');
        capacitanceFound = false;
        
        for row = 1:20
            for col = 1:min(100, size(rawData, 2))
                cellVal = rawData{row, col};
                if ~isempty(cellVal) && (ischar(cellVal) || isstring(cellVal))
                    cellStr = lower(char(cellVal));
                    if contains(cellStr, 'cap') || contains(cellStr, 'capacitance')
                        fprintf('Found capacitance keyword at Row %d, Col %d: "%s"\n', row, col, cellVal);
                        capacitanceFound = true;
                    end
                end
            end
        end
        
        if ~capacitanceFound
            fprintf('No capacitance keywords found in first 20 rows\n');
        end
        
        % Analyze data columns around expected capacitance locations
        fprintf('\n=== ANALYZING EXPECTED CAPACITANCE COLUMNS ===\n');
        
        % Based on activation protocol: columns 8, 14, 20, 26 should have capacitance
        expectedCols = [8, 14, 20, 26, 32];
        dataStartRow = 11; % From your logs
        
        fprintf('Expected capacitance columns for activation protocol:\n');
        for i = 1:length(expectedCols)
            col = expectedCols(i);
            if col <= size(rawData, 2)
                % Get sample of data from this column
                dataRange = dataStartRow:(dataStartRow+9); % First 10 data rows
                fprintf('\nColumn %d (IV%d capacitance):\n', col, i);
                
                for row = dataRange
                    if row <= size(rawData, 1)
                        cellVal = rawData{row, col};
                        if ~isempty(cellVal)
                            if isnumeric(cellVal)
                                fprintf('  Row %d: %.6g\n', row, cellVal);
                            else
                                fprintf('  Row %d: %s\n', row, char(cellVal));
                            end
                        else
                            fprintf('  Row %d: [empty]\n', row);
                        end
                    end
                end
                
                % Calculate statistics for this column
                dataValues = [];
                for row = dataStartRow:min(dataStartRow+100, size(rawData, 1))
                    cellVal = rawData{row, col};
                    if isnumeric(cellVal) && ~isnan(cellVal)
                        dataValues(end+1) = cellVal;
                    end
                end
                
                if ~isempty(dataValues)
                    fprintf('  Statistics: min=%.6g, max=%.6g, median=%.6g, std=%.6g\n', ...
                        min(dataValues), max(dataValues), median(dataValues), std(dataValues));
                    fprintf('  Non-zero count: %d/%d\n', sum(dataValues ~= 0), length(dataValues));
                else
                    fprintf('  No numeric data found\n');
                end
            else
                fprintf('Column %d: Beyond data range\n', col);
            end
        end
        
        % Look for non-zero columns in the vicinity
        fprintf('\n=== SEARCHING FOR NON-ZERO COLUMNS NEAR EXPECTED LOCATIONS ===\n');
        searchCols = 5:35;  % Search around expected range
        
        for col = searchCols
            if col <= size(rawData, 2)
                % Count non-zero numeric values
                nonZeroCount = 0;
                totalCount = 0;
                sampleValues = [];
                
                for row = dataStartRow:min(dataStartRow+50, size(rawData, 1))
                    cellVal = rawData{row, col};
                    if isnumeric(cellVal) && ~isnan(cellVal)
                        totalCount = totalCount + 1;
                        if cellVal ~= 0
                            nonZeroCount = nonZeroCount + 1;
                            if length(sampleValues) < 5
                                sampleValues(end+1) = cellVal;
                            end
                        end
                    end
                end
                
                % Report columns with significant non-zero content
                if nonZeroCount > 10 && nonZeroCount/totalCount > 0.1  % >10% non-zero
                    fprintf('Column %d: %d/%d non-zero (%.1f%%), samples: [', ...
                        col, nonZeroCount, totalCount, 100*nonZeroCount/totalCount);
                    fprintf('%.3g ', sampleValues);
                    fprintf(']\n');
                end
            end
        end
        
    catch ME
        fprintf('❌ Diagnosis failed: %s\n', ME.message);
    end
end