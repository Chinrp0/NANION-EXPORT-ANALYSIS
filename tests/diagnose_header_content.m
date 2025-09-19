function diagnose_header_content()
    %DIAGNOSE_HEADER_CONTENT Examine actual header content to find sweep info
    
    fprintf('=== HEADER CONTENT DIAGNOSTIC ===\n\n');
    
    % Get the test file
    [filename, pathname] = uigetfile(...
        {'*.xlsx;*.xls', 'Excel Files (*.xlsx, *.xls)'}, ...
        'Select the file to examine headers');
    
    if isequal(filename, 0)
        fprintf('No file selected.\n');
        return;
    end
    
    filePath = fullfile(pathname, filename);
    fprintf('Examining: %s\n\n', filename);
    
    try
        % Read first few rows to see header structure
        headerData = readcell(filePath, 'Range', 'A1:ZZ15', 'UseExcel', false);
        
        fprintf('File dimensions: %dx%d\n\n', size(headerData));
        
        % Focus on first row (where sweep info should be)
        fprintf('=== FIRST ROW ANALYSIS ===\n');
        headerRow1 = headerData(1, :);
        
        fprintf('Total cells in row 1: %d\n', length(headerRow1));
        
        % Check last 20 cells for any sweep-related content
        fprintf('\nLast 20 cells in row 1:\n');
        startCol = max(1, length(headerRow1) - 19);
        
        for i = startCol:length(headerRow1)
            cell_val = headerRow1{i};
            
            if isempty(cell_val)
                fprintf('Col %3d: [EMPTY]\n', i);
            elseif ismissing(cell_val)
                fprintf('Col %3d: [MISSING]\n', i);
            elseif isnumeric(cell_val) && isnan(cell_val)
                fprintf('Col %3d: [NaN]\n', i);
            elseif ischar(cell_val) || isstring(cell_val)
                cellText = char(cell_val);
                if contains(cellText, 'Sweep', 'IgnoreCase', true)
                    fprintf('Col %3d: "%s" *** SWEEP FOUND ***\n', i, cellText);
                else
                    fprintf('Col %3d: "%s"\n', i, cellText);
                end
            elseif isnumeric(cell_val)
                fprintf('Col %3d: %.6g (numeric)\n', i, cell_val);
            else
                fprintf('Col %3d: %s (class: %s)\n', i, mat2str(cell_val), class(cell_val));
            end
        end
        
        % Search entire first row for any sweep-related content
        fprintf('\n=== SWEEP SEARCH IN ENTIRE ROW 1 ===\n');
        sweepCells = [];
        
        for i = 1:length(headerRow1)
            cell_val = headerRow1{i};
            
            if ischar(cell_val) || isstring(cell_val)
                cellText = char(cell_val);
                if contains(cellText, 'Sweep', 'IgnoreCase', true)
                    sweepCells(end+1) = i;
                    fprintf('Found "Sweep" in column %d: "%s"\n', i, cellText);
                end
            end
        end
        
        if isempty(sweepCells)
            fprintf('No "Sweep" text found in entire first row\n');
        end
        
        % Check if sweep info might be in other rows
        fprintf('\n=== SEARCHING OTHER ROWS FOR SWEEP INFO ===\n');
        
        for row = 2:min(10, size(headerData, 1))
            hasSeep = false;
            for col = 1:min(50, size(headerData, 2))
                cell_val = headerData{row, col};
                if ischar(cell_val) || isstring(cell_val)
                    cellText = char(cell_val);
                    if contains(cellText, 'Sweep', 'IgnoreCase', true)
                        fprintf('Row %d, Col %d: "%s"\n', row, col, cellText);
                        hasSeep = true;
                    end
                end
            end
            if hasSeep
                fprintf('Found sweep info in row %d\n', row);
            end
        end
        
        % Look for numeric patterns that might indicate data points
        fprintf('\n=== NUMERIC PATTERN ANALYSIS ===\n');
        
        % Count numeric cells in first row
        numericCount = 0;
        maxNumeric = -inf;
        
        for i = 1:length(headerRow1)
            cell_val = headerRow1{i};
            if isnumeric(cell_val) && ~isnan(cell_val) && ~isempty(cell_val)
                numericCount = numericCount + 1;
                maxNumeric = max(maxNumeric, cell_val);
            end
        end
        
        fprintf('Numeric cells in row 1: %d\n', numericCount);
        if maxNumeric > -inf
            fprintf('Largest numeric value: %.0f\n', maxNumeric);
            
            % If we found a large number, it might be related to data points
            if maxNumeric > 50
                possibleIVs = ceil(maxNumeric / 23);
                fprintf('If %.0f represents total data points: %d IVs (%.0f/23)\n', ...
                    maxNumeric, possibleIVs, maxNumeric);
            end
        end
        
    catch ME
        fprintf('Error examining file: %s\n', ME.message);
    end
end