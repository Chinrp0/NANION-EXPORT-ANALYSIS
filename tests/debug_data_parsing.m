function debug_data_parsing()
    %DEBUG_DATA_PARSING Find exactly where "Too many input arguments" occurs
    
    fprintf('=== DEBUGGING DATA PARSING ERROR ===\n\n');
    
    % Get the test file
    [filename, pathname] = uigetfile(...
        {'*.xlsx;*.xls', 'Excel Files (*.xlsx, *.xls)'}, ...
        'Select the file that fails parsing');
    
    if isequal(filename, 0)
        fprintf('No file selected.\n');
        return;
    end
    
    filePath = fullfile(pathname, filename);
    
    % Create components
    config = NanionConfig();
    logger = NanionLogger(config);
    ioManager = NanionIOManager(config, logger);
    fileDetector = NanionFileDetector(logger);
    
    fprintf('Debugging parsing for: %s\n\n', filename);
    
    try
        % Step 1: Protocol detection (we know this works)
        fprintf('Step 1: Protocol detection...\n');
        protocolInfo = fileDetector.detectProtocol(filePath);
        fprintf('✓ Protocol: %s with %d IVs\n\n', protocolInfo.type, protocolInfo.numIVs);
        
        % Step 2: File reading (we know this works)
        fprintf('Step 2: File reading...\n');
        rawData = ioManager.readFile(filePath);
        fprintf('✓ Raw data: %dx%d\n\n', size(rawData));
        
        % Step 3: Break down the parsing step by step
        fprintf('Step 3: Header structure detection...\n');
        headerInfo = ioManager.findHeaderStructure(rawData);
        fprintf('✓ Headers: Sweep=%d, Param=%d, Data=%d\n\n', ...
            headerInfo.headerRow1Idx, headerInfo.headerRow2Idx, headerInfo.dataStartRow);
        
        % Step 4: Header extraction
        fprintf('Step 4: Header extraction...\n');
        headers = ioManager.extractHeaders(rawData, headerInfo);
        fprintf('✓ Generated %d headers\n', length(headers.combined));
        fprintf('First 5 headers: %s\n\n', strjoin(headers.combined(1:5), ', '));
        
        % Step 5: Data extraction (before table creation)
        fprintf('Step 5: Data extraction...\n');
        dataRows = rawData(headerInfo.dataStartRow:end, :);
        fprintf('✓ Data rows extracted: %dx%d\n', size(dataRows));
        
        % Step 6: Column matching
        fprintf('Step 6: Column matching...\n');
        numDataCols = size(dataRows, 2);
        numHeaderCols = length(headers.combined);
        fprintf('Data columns: %d, Header columns: %d\n', numDataCols, numHeaderCols);
        
        if numDataCols ~= numHeaderCols
            minCols = min(numDataCols, numHeaderCols);
            dataRows = dataRows(:, 1:minCols);
            headers.combined = headers.combined(1:minCols);
            fprintf('✓ Adjusted to %d columns\n', minCols);
        end
        
        % Step 7: Test table creation components
        fprintf('\nStep 7: Testing table creation components...\n');
        
        % Check variable names
        fprintf('Testing variable names...\n');
        for i = 1:min(5, length(headers.combined))
            varName = headers.combined{i};
            fprintf('  Header %d: "%s" (valid: %s)\n', i, varName, mat2str(isvarname(varName)));
        end
        
        % Check data types in first few columns
        fprintf('Testing data types...\n');
        for col = 1:min(3, size(dataRows, 2))
            colData = dataRows(:, col);
            fprintf('  Column %d: %s\n', col, class(colData));
            
            % Check for any problematic values
            if iscell(colData)
                uniqueTypes = cellfun(@class, colData(1:min(10, end)), 'UniformOutput', false);
                fprintf('    Cell types: %s\n', strjoin(unique(uniqueTypes), ', '));
            end
        end
        
        % Step 8: Attempt table creation with minimal data
        fprintf('\nStep 8: Testing table creation with small subset...\n');
        
        % Try with just first 3 columns and 3 rows
        testData = dataRows(1:min(3, size(dataRows, 1)), 1:min(3, size(dataRows, 2)));
        testHeaders = headers.combined(1:size(testData, 2));
        
        fprintf('Test data size: %dx%d\n', size(testData));
        fprintf('Test headers: %s\n', strjoin(testHeaders, ', '));
        
        % Try the actual array2table call
        fprintf('Attempting array2table...\n');
        testTable = array2table(testData, 'VariableNames', testHeaders);
        fprintf('✓ Small table created successfully: %dx%d\n', size(testTable));
        
        % Step 9: Try with full data
        fprintf('\nStep 9: Testing full table creation...\n');
        fullTable = array2table(dataRows, 'VariableNames', headers.combined);
        fprintf('✓ Full table created successfully: %dx%d\n', size(fullTable));
        
        fprintf('\n🎉 DATA PARSING SUCCESSFUL!\n');
        fprintf('The issue might be in how the method is called, not the logic itself.\n');
        
    catch ME
        fprintf('\n❌ ERROR CAUGHT:\n');
        fprintf('Message: %s\n', ME.message);
        fprintf('Stack trace:\n');
        
        for i = 1:length(ME.stack)
            fprintf('  File: %s\n', ME.stack(i).file);
            fprintf('  Function: %s\n', ME.stack(i).name);
            fprintf('  Line: %d\n', ME.stack(i).line);
        end
        
        % Show the problematic code if possible
        if ~isempty(ME.stack)
            errorFile = ME.stack(1).file;
            errorLine = ME.stack(1).line;
            
            fprintf('\nPROBLEMATIC CODE:\n');
            try
                fid = fopen(errorFile, 'r');
                if fid > 0
                    lines = {};
                    while ~feof(fid)
                        lines{end+1} = fgetl(fid);
                    end
                    fclose(fid);
                    
                    if errorLine <= length(lines)
                        % Show context around the error
                        for context = max(1, errorLine-3):min(length(lines), errorLine+3)
                            if context == errorLine
                                fprintf('>>> %3d: %s\n', context, lines{context});
                            else
                                fprintf('    %3d: %s\n', context, lines{context});
                            end
                        end
                    end
                end
            catch
                fprintf('Could not read error file\n');
            end
        end
    end
end