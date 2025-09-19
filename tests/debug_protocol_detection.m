function debug_protocol_detection()
    %DEBUG_PROTOCOL_DETECTION Examine why protocol detection failed
    
    fprintf('=== PROTOCOL DETECTION DEBUG ===\n\n');
    
    % Get the same file that failed
    [filename, pathname] = uigetfile(...
        {'*.xlsx;*.xls', 'Excel Files (*.xlsx, *.xls)'}, ...
        'Select the SAME file that failed protocol detection');
    
    if isequal(filename, 0)
        fprintf('No file selected.\n');
        return;
    end
    
    filePath = fullfile(pathname, filename);
    fprintf('Debugging: %s\n\n', filename);
    
    try
        % Read the header section that protocol detection examines
        fprintf('Reading first 15 rows...\n');
        headerData = readcell(filePath, 'Range', 'A1:ZZ15', 'UseExcel', false);
        
        fprintf('Found %dx%d data\n\n', size(headerData));
        
        % Show what we're actually searching through
        fprintf('=== ROW-BY-ROW CONTENT ANALYSIS ===\n');
        
        foundKeywords = false;
        
        for row = 1:min(15, size(headerData, 1))
            rowData = headerData(row, :);
            
            % Convert row to string - fix the array issue
            rowStrings = string(rowData);
            rowStrings(ismissing(rowStrings)) = "";
            rowText = strjoin(rowStrings, ' ');
            
            % Check for keywords - ensure scalar results
            hasPeak = any(contains(rowText, 'Peak', 'IgnoreCase', true));
            hasInact = any(contains(rowText, 'Inact', 'IgnoreCase', true));
            hasAct = any(contains(rowText, 'Act', 'IgnoreCase', true));
            
            if hasPeak || hasInact || hasAct
                foundKeywords = true;
                fprintf('Row %2d: *** KEYWORDS FOUND *** ', row);
                if hasPeak, fprintf('[Peak] '); end
                if hasInact, fprintf('[Inact] '); end
                if hasAct, fprintf('[Act] '); end
                fprintf('\n');
                
                % Show first 10 non-empty cells from this row
                fprintf('       Content: ');
                cellCount = 0;
                for col = 1:min(size(rowData, 2), 20)
                    cell_val = rowData{col};
                    if ~isempty(cell_val) && ~ismissing(cell_val)
                        if cellCount < 10
                            if ischar(cell_val) || isstring(cell_val)
                                fprintf('"%s" ', char(cell_val));
                            else
                                fprintf('%.3g ', cell_val);
                            end
                            cellCount = cellCount + 1;
                        end
                    end
                end
                fprintf('\n');
            else
                % Show summary of non-empty cells for rows without keywords
                nonEmptyCount = sum(~cellfun(@(x) isempty(x) || ismissing(x), rowData));
                if nonEmptyCount > 0
                    fprintf('Row %2d: %d non-empty cells (no keywords)\n', row, nonEmptyCount);
                else
                    fprintf('Row %2d: Empty row\n', row);
                end
            end
        end
        
        fprintf('\n=== SUMMARY ===\n');
        if foundKeywords
            fprintf('✓ Keywords WERE found in the file!\n');
            fprintf('Issue might be in the simplified detection logic.\n');
            
            % Test the actual simplified logic
            fprintf('\nTesting simplified detection logic...\n');
            protocolType = '';
            for row = 1:size(headerData, 1)
                rowStrings = string(headerData(row, :));
                rowStrings(ismissing(rowStrings)) = "";
                rowText = strjoin(rowStrings, ' ');
                
                if any(contains(rowText, 'Peak', 'IgnoreCase', true))
                    protocolType = 'activation';
                    fprintf('Logic found activation at row %d\n', row);
                    break;
                elseif any(contains(rowText, 'Inact', 'IgnoreCase', true)) && any(contains(rowText, 'Act', 'IgnoreCase', true))
                    protocolType = 'inactivation';
                    fprintf('Logic found inactivation at row %d\n', row);
                    break;
                end
            end
            
            if isempty(protocolType)
                fprintf('❌ Simplified logic failed to detect - needs debugging\n');
            else
                fprintf('✓ Simplified logic detected: %s\n', protocolType);
            end
            
        else
            fprintf('❌ No protocol keywords found in first 15 rows\n');
            fprintf('This file may not be a standard Nanion file format\n');
            fprintf('Expected keywords: "Peak" (activation) or "Inact"+"Act" (inactivation)\n');
        end
        
    catch ME
        fprintf('Error reading file: %s\n', ME.message);
    end
end