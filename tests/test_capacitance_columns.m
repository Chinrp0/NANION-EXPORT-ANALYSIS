function test_capacitance_columns(testColumns)
    %TEST_CAPACITANCE_COLUMNS Test extraction with different capacitance column mappings
    %   testColumns - array of column indices to test (e.g., [7, 13, 19, 25])
    
    if nargin < 1
        % Default test columns based on common patterns
        testColumns = [7, 13, 19, 25; ...  % Try one column earlier
                       9, 15, 21, 27; ...  % Try one column later
                       5, 11, 17, 23];     % Try different pattern
    end
    
    fprintf('=== TESTING CAPACITANCE COLUMN MAPPINGS ===\n\n');
    
    testFile = "C:/Users/xdach/OneDrive - Johns Hopkins/Maher_Lab/Protocols/Matlab_scripts/Fede/Master files for CHIN 9_17_2025/18T22880 NGN2 ACT_IV raw.xlsx";
    
    if ~exist(testFile, 'file')
        fprintf('❌ Test file not found: %s\n', testFile);
        return;
    end
    
    addpath(genpath('SRC'));
    
    try
        % Read and parse data
        config = NanionConfig();
        logger = NanionLogger(config);
        ioManager = NanionIOManager(config, logger);
        fileDetector = NanionFileDetector(logger);
        
        protocolInfo = fileDetector.detectProtocol(testFile);
        rawData = ioManager.readFile(testFile);
        parsedData = ioManager.parseData(rawData, protocolInfo);
        
        dataTable = parsedData.dataTable;
        dataStartRow = parsedData.headerInfo.dataStartRow;
        dataRows = dataTable(dataStartRow:end, :);
        
        fprintf('Testing %d different column mapping patterns...\n\n', size(testColumns, 1));
        
        for pattern = 1:size(testColumns, 1)
            cols = testColumns(pattern, :);
            fprintf('=== PATTERN %d: Columns [%s] ===\n', pattern, num2str(cols));
            
            % Test each IV column
            for iv = 1:min(4, length(cols))  % Test first 4 IVs
                col = cols(iv);
                
                if col <= size(dataRows, 2)
                    % Extract data from this column
                    rawColumnData = dataRows{:, col};
                    
                    % Convert to numeric
                    numericData = [];
                    for i = 1:length(rawColumnData)
                        if isnumeric(rawColumnData{i})
                            numericData(end+1) = rawColumnData{i};
                        elseif ischar(rawColumnData{i}) || isstring(rawColumnData{i})
                            converted = str2double(rawColumnData{i});
                            if ~isnan(converted)
                                numericData(end+1) = converted;
                            end
                        end
                    end
                    
                    if ~isempty(numericData)
                        % Calculate statistics
                        nonZeroCount = sum(numericData ~= 0);
                        validCount = sum(~isnan(numericData));
                        
                        fprintf('  IV%d (Col %d): %d valid, %d non-zero (%.1f%%)\n', ...
                            iv, col, validCount, nonZeroCount, 100*nonZeroCount/validCount);
                        
                        if nonZeroCount > 0
                            fprintf('    Range: %.6g to %.6g, Median: %.6g\n', ...
                                min(numericData(numericData~=0)), max(numericData(numericData~=0)), ...
                                median(numericData(numericData~=0)));
                            
                            % Show a few sample values
                            nonZeroVals = numericData(numericData~=0);
                            sampleSize = min(5, length(nonZeroVals));
                            fprintf('    Samples: [');
                            for s = 1:sampleSize
                                fprintf('%.6g ', nonZeroVals(s));
                            end
                            fprintf(']\n');
                        end
                    else
                        fprintf('  IV%d (Col %d): No valid numeric data\n', iv, col);
                    end
                else
                    fprintf('  IV%d (Col %d): Column out of range\n', iv, col);
                end
            end
            fprintf('\n');
        end
        
        % Test with updated column mapping
        fprintf('=== TESTING BEST CANDIDATE ===\n');
        fprintf('Enter the column numbers that showed promising capacitance data:\n');
        fprintf('Format: [col1, col2, col3, col4] or press Enter to skip\n');
        userInput = input('Column numbers: ', 's');
        
        if ~isempty(userInput)
            try
                bestCols = str2num(userInput);
                if length(bestCols) >= 4
                    fprintf('\nTesting with columns: [%s]\n', num2str(bestCols));
                    
                    % Create a modified extractor to test these columns
                    fprintf('Creating test extraction with new column mapping...\n');
                    
                    % You would need to modify the NanionDataExtractor to use these columns
                    fprintf('To implement this, update the capacitancePattern in NanionFileDetector.getColumnMapping():\n');
                    fprintf('capacitancePattern: [%s]\n', num2str(bestCols));
                end
            catch
                fprintf('Invalid column format\n');
            end
        end
        
    catch ME
        fprintf('❌ Test failed: %s\n', ME.message);
    end
end