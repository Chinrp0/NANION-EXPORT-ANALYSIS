function diagnose_nanion_file_structure()
    %DIAGNOSE_NANION_FILE_STRUCTURE Examine actual Nanion file structure
    %   Run this to understand why protocol detection is failing
    
    fprintf('=== NANION FILE STRUCTURE DIAGNOSTIC ===\n\n');
    
    % File selection
    [filename, pathname] = uigetfile(...
        {'*.xlsx;*.xls', 'Excel Files (*.xlsx, *.xls)'}, ...
        'Select ONE Nanion File for Structure Analysis');
    
    if isequal(filename, 0)
        fprintf('No file selected. Diagnostic cancelled.\n');
        return;
    end
    
    filePath = fullfile(pathname, filename);
    fprintf('Analyzing file: %s\n\n', filename);
    
    try
        % Read first 15 rows to examine structure
        fprintf('Reading first 15 rows...\n');
        headerData = readcell(filePath, 'Range', 'A1:ZZ15', 'UseExcel', false);
        
        fprintf('File dimensions: %dx%d\n\n', size(headerData));
        
        % Examine column 1 in detail
        fprintf('=== COLUMN 1 ANALYSIS ===\n');
        col1 = headerData(:, 1);
        
        for i = 1:min(15, length(col1))
            cellValue = col1{i};
            
            % Analyze each cell
            if isempty(cellValue)
                fprintf('Row %2d: [EMPTY] (isempty=true)\n', i);
            elseif isnumeric(cellValue) && isnan(cellValue)
                fprintf('Row %2d: [NaN] (numeric NaN)\n', i);
            elseif ismissing(cellValue)
                fprintf('Row %2d: [MISSING] (ismissing=true)\n', i);
            elseif ischar(cellValue)
                if isempty(strtrim(cellValue))
                    fprintf('Row %2d: [EMPTY STRING] "%s"\n', i, cellValue);
                else
                    fprintf('Row %2d: [CHAR] "%s"\n', i, cellValue);
                end
            elseif isstring(cellValue)
                if ismissing(cellValue) || strtrim(cellValue) == ""
                    fprintf('Row %2d: [EMPTY STRING] "%s"\n', i, cellValue);
                else
                    fprintf('Row %2d: [STRING] "%s"\n', i, cellValue);
                end
            elseif isnumeric(cellValue)
                fprintf('Row %2d: [NUMERIC] %.6g\n', i, cellValue);
            else
                fprintf('Row %2d: [OTHER] %s - %s\n', i, class(cellValue), mat2str(cellValue));
            end
        end
        
        % Look for potential header patterns
        fprintf('\n=== HEADER PATTERN SEARCH ===\n');
        
        % Search for common header keywords
        headerKeywords = {'Well', 'Sweep', 'Series', 'Seal', 'Cap', 'Peak', 'Inact', 'Act'};
        
        for row = 1:min(15, size(headerData, 1))
            rowData = headerData(row, :);
            keywordCount = 0;
            foundKeywords = {};
            
            for col = 1:min(20, size(rowData, 2))
                cellValue = rowData{col};
                if ischar(cellValue) || isstring(cellValue)
                    cellStr = char(cellValue);
                    for k = 1:length(headerKeywords)
                        if contains(cellStr, headerKeywords{k}, 'IgnoreCase', true)
                            keywordCount = keywordCount + 1;
                            foundKeywords{end+1} = headerKeywords{k};
                        end
                    end
                end
            end
            
            if keywordCount > 0
                fprintf('Row %2d: Found %d header keywords: %s\n', row, keywordCount, strjoin(foundKeywords, ', '));
            end
        end
        
        % Show first few rows of multiple columns for pattern recognition
        fprintf('\n=== MULTI-COLUMN PREVIEW (First 5 rows, 10 columns) ===\n');
        fprintf('%-4s', 'Row');
        for col = 1:min(10, size(headerData, 2))
            fprintf('%-15s', sprintf('Col%d', col));
        end
        fprintf('\n');
        
        for row = 1:min(5, size(headerData, 1))
            fprintf('%-4d', row);
            for col = 1:min(10, size(headerData, 2))
                cellValue = headerData{row, col};
                if isempty(cellValue) || (isnumeric(cellValue) && isnan(cellValue)) || ismissing(cellValue)
                    fprintf('%-15s', '[EMPTY]');
                elseif ischar(cellValue) || isstring(cellValue)
                    cellStr = char(cellValue);
                    if length(cellStr) > 12
                        fprintf('%-15s', [cellStr(1:12) '...']);
                    else
                        fprintf('%-15s', cellStr);
                    end
                elseif isnumeric(cellValue)
                    fprintf('%-15s', sprintf('%.2g', cellValue));
                else
                    fprintf('%-15s', '[OTHER]');
                end
            end
            fprintf('\n');
        end
        
        % Summary and recommendations
        fprintf('\n=== DIAGNOSTIC SUMMARY ===\n');
        
        % Check if any row looks like headers
        fprintf('Recommendations:\n');
        
        emptyRows = [];
        for i = 1:min(15, length(col1))
            cellValue = col1{i};
            if isempty(cellValue) || (isnumeric(cellValue) && isnan(cellValue)) || ismissing(cellValue) || ...
               (ischar(cellValue) && isempty(strtrim(cellValue))) || ...
               (isstring(cellValue) && (ismissing(cellValue) || strtrim(cellValue) == ""))
                emptyRows(end+1) = i;
            end
        end
        
        if isempty(emptyRows)
            fprintf('• No empty cells found in column 1 - file may not have expected header structure\n');
            fprintf('• Headers may start at row 1 instead of after an empty row\n');
        else
            fprintf('• Empty cells in column 1 at rows: %s\n', mat2str(emptyRows));
            fprintf('• Check if headers start after any of these empty rows\n');
        end
        
        fprintf('• Look for header keywords in the multi-column preview above\n');
        fprintf('• Compare with your working v56 version to see structure differences\n');
        
    catch ME
        fprintf('Error analyzing file: %s\n', ME.message);
        fprintf('Stack trace:\n%s\n', getReport(ME));
    end
end