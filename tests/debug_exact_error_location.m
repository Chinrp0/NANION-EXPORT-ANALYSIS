function debug_exact_error_location()
    %DEBUG_EXACT_ERROR_LOCATION Find exactly where the logical operator error occurs
    
    fprintf('=== DEBUGGING EXACT ERROR LOCATION ===\n\n');
    
    % Get the test file
    [filename, pathname] = uigetfile(...
        {'*.xlsx;*.xls', 'Excel Files (*.xlsx, *.xls)'}, ...
        'Select the file that fails detection');
    
    if isequal(filename, 0)
        fprintf('No file selected.\n');
        return;
    end
    
    filePath = fullfile(pathname, filename);
    
    % Create logger and detector
    config = NanionConfig();
    logger = NanionLogger(config);
    fileDetector = NanionFileDetector(logger);
    
    fprintf('Testing file: %s\n\n', filename);
    
    try
        % Step 1: Test the file reading part
        fprintf('Step 1: Testing file reading...\n');
        headerData = readcell(filePath, 'Range', 'A1:ZZ15', 'UseExcel', false);
        fprintf('✓ File reading successful: %dx%d\n\n', size(headerData));
        
        % Step 2: Test basic string operations
        fprintf('Step 2: Testing basic string operations...\n');
        testRow = headerData(1, :);
        
        % Test the exact logic from the fixed detectProtocol
        searchStr = '';
        for col = 1:length(testRow)
            cell_val = testRow{col};
            if ~isempty(cell_val) && ~ismissing(cell_val)
                if ischar(cell_val) || isstring(cell_val)
                    searchStr = [searchStr, ' ', char(cell_val)];
                elseif isnumeric(cell_val) && ~isnan(cell_val)
                    searchStr = [searchStr, ' ', num2str(cell_val)];
                end
            end
        end
        fprintf('✓ String building successful\n');
        
        % Test contains function
        hasPeak = contains(searchStr, 'Peak', 'IgnoreCase', true);
        fprintf('✓ Peak search successful: %s\n', mat2str(hasPeak));
        
        hasInact = contains(searchStr, 'Inact', 'IgnoreCase', true);
        hasAct = contains(searchStr, 'Act', 'IgnoreCase', true);
        fprintf('✓ Inact/Act search successful: %s, %s\n', mat2str(hasInact), mat2str(hasAct));
        
        % Test the logical AND that was causing problems
        fprintf('Testing logical AND: hasInact && hasAct = ');
        testLogical = hasInact && hasAct;
        fprintf('%s\n\n', mat2str(testLogical));
        
        % Step 3: Test the actual detectProtocol method
        fprintf('Step 3: Testing actual detectProtocol method...\n');
        protocolInfo = fileDetector.detectProtocol(filePath);
        
        if isempty(protocolInfo)
            fprintf('✓ Method ran but found no protocol\n');
        else
            fprintf('✓ Method successful: %s protocol\n', protocolInfo.type);
        end
        
    catch ME
        fprintf('❌ ERROR CAUGHT:\n');
        fprintf('Message: %s\n', ME.message);
        fprintf('Stack trace:\n');
        
        for i = 1:length(ME.stack)
            fprintf('  File: %s\n', ME.stack(i).file);
            fprintf('  Function: %s\n', ME.stack(i).name);
            fprintf('  Line: %d\n\n', ME.stack(i).line);
        end
        
        % Show the specific line that failed if possible
        if ~isempty(ME.stack)
            errorFile = ME.stack(1).file;
            errorLine = ME.stack(1).line;
            
            fprintf('PROBLEMATIC CODE:\n');
            try
                fid = fopen(errorFile, 'r');
                if fid > 0
                    lines = {};
                    while ~feof(fid)
                        lines{end+1} = fgetl(fid);
                    end
                    fclose(fid);
                    
                    if errorLine <= length(lines)
                        fprintf('Line %d: %s\n', errorLine, lines{errorLine});
                        
                        % Show context
                        for context = max(1, errorLine-2):min(length(lines), errorLine+2)
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