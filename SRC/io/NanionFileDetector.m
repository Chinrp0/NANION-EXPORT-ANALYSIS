classdef NanionFileDetector < handle
    %NANIONFILEDETECTOR Protocol detection for Nanion Excel files
    %   Distinguishes between activation and inactivation protocols
    %   Based on column patterns and header keywords
    
    properties (Access = private)
        logger
    end
    
    methods
        function obj = NanionFileDetector(logger)
            %NANIONFILEDETECTOR Constructor
            obj.logger = logger;
        end
        
        function protocolInfo = detectProtocol(obj, filePath)
            %DETECTPROTOCOL Bulletproof protocol detection
            
            obj.logger.logInfo(sprintf('Detecting protocol for: %s', obj.getFileName(filePath)));
            
            try
                % Read header section
                headerData = readcell(filePath, 'Range', 'A1:ZZ15', 'UseExcel', false);
                
                % Search for protocol keywords - completely bulletproof approach
                protocolType = '';
                
                for row = 1:size(headerData, 1)
                    % Convert entire row to one big string for searching
                    rowCells = headerData(row, :);
                    
                    % Build search string from all cells - ultra safe approach
                    searchStr = '';
                    for col = 1:length(rowCells)
                        cell_val = rowCells{col};
                        
                        % Ultra safe cell checking - avoid all logical operator issues
                        try
                            if isempty(cell_val)
                                continue;
                            end
                            
                            % Check for missing values safely
                            if isnumeric(cell_val) && any(isnan(cell_val(:)))
                                continue;
                            end
                            
                            % Try to extract string content
                            if ischar(cell_val)
                                searchStr = [searchStr, ' ', cell_val];
                            elseif isstring(cell_val) && ~ismissing(cell_val)
                                searchStr = [searchStr, ' ', char(cell_val)];
                            elseif isnumeric(cell_val) && ~any(isnan(cell_val(:)))
                                searchStr = [searchStr, ' ', num2str(cell_val(1))]; % Just use first element
                            end
                        catch
                            % If anything goes wrong with this cell, just skip it
                            continue;
                        end
                    end
                    
                    % Simple keyword search on the combined string
                    if contains(searchStr, 'Peak', 'IgnoreCase', true)
                        protocolType = 'activation';
                        obj.logger.logInfo(sprintf('Found activation keywords in row %d', row));
                        break;
                    end
                    
                    % Check for inactivation - separate checks to avoid logical issues
                    hasInact = contains(searchStr, 'Inact', 'IgnoreCase', true);
                    hasAct = contains(searchStr, 'Act', 'IgnoreCase', true);
                    
                    if hasInact && hasAct
                        protocolType = 'inactivation';
                        obj.logger.logInfo(sprintf('Found inactivation keywords in row %d', row));
                        break;
                    end
                end
                
                if isempty(protocolType)
                    obj.logger.logWarning('No protocol keywords found');
                    protocolInfo = [];
                    return;
                end
                
                % Simple IV count and column mapping
                numIVs = obj.calculateNumIVs(headerData);
                columnMapping = obj.getColumnMapping(protocolType);
                
                protocolInfo = struct(...
                    'type', protocolType, ...
                    'numIVs', numIVs, ...
                    'columnMapping', columnMapping);
                
                obj.logger.logInfo(sprintf('✓ Detected %s protocol with %d IVs', protocolType, numIVs));
                
            catch ME
                obj.logger.logError(sprintf('Protocol detection failed: %s', ME.message));
                protocolInfo = [];
            end
        end
        end
        
        methods (Access = private)        
            function numIVs = calculateNumIVs(obj, headerData)
                %CALCULATENUMIVS Get total sweeps from Row 2, Col 2
                
                try
                    % The total number of sweeps is in Row 2, Column 2
                    totalSweeps = headerData{2, 2};
                    
                    if isempty(totalSweeps) || ismissing(totalSweeps)
                        error('Row 2, Col 2 is empty or missing');
                    end
                    
                    % Convert to number if it's text
                    if ischar(totalSweeps) || isstring(totalSweeps)
                        totalSweeps = str2double(totalSweeps);
                    end
                    
                    if isnan(totalSweeps)
                        error('Could not convert sweep count to number: %s', mat2str(headerData{2, 2}));
                    end
                    
                    % Calculate IVs: ceil(total_sweeps / 23)
                    numDataPoints = 23;
                    numIVs = ceil(totalSweeps / numDataPoints);
                    
                    obj.logger.logInfo(sprintf('Found %d total sweeps in Row 2, Col 2', totalSweeps));
                    obj.logger.logInfo(sprintf('Calculated %d IVs: ceil(%d sweeps / %d points per IV)', ...
                        numIVs, totalSweeps, numDataPoints));
                    
                catch ME
                    obj.logger.logError(sprintf('IV calculation failed: %s', ME.message));
                    
                    % Fallback to column-based estimate
                    numCols = size(headerData, 2);
                    numIVs = max(1, floor(numCols / 23));
                    obj.logger.logWarning(sprintf('Using fallback: estimated %d IVs from %d columns / 23', numIVs, numCols));
                end
            end
        function columnMapping = getColumnMapping(obj, protocolType)
            %GETCOLUMNMAPPING Get column patterns for protocol type
            
            switch protocolType
                case 'activation'
                    columnMapping = struct(...
                        'columnPattern', 6, ...
                        'seriesResistancePattern', [6, 12, 18, 24, 30], ...
                        'sealResistancePattern', [7, 13, 19, 25, 31], ...
                        'capacitancePattern', [8, 14, 20, 26, 32], ...
                        'peakCurrentPattern', [9, 15, 21, 27, 33]);
                    
                case 'inactivation'
                    columnMapping = struct(...
                        'columnPattern', 7, ...
                        'seriesResistancePattern', [6, 13, 20, 27, 34], ...
                        'sealResistancePattern', [7, 14, 21, 28, 35], ...
                        'capacitancePattern', [8, 15, 22, 29, 36], ...
                        'inactivationDataPattern', [9, 16, 23, 30, 37], ...
                        'activationDataPattern', [10, 17, 24, 31, 38]);
                    
                otherwise
                    error('NanionFileDetector:UnknownProtocol', 'Unknown protocol type: %s', protocolType);
            end
        end        
        
        function isEmpty = isEmptyCell(obj, cellValue)
            %ISEMPTYCELL Check if cell is empty
            isEmpty = isempty(cellValue) || ...
                      (isnumeric(cellValue) && isnan(cellValue)) || ...
                      (ischar(cellValue) && isempty(strtrim(cellValue))) || ...
                      (isstring(cellValue) && (ismissing(cellValue) || strtrim(cellValue) == ""));
        end
        
        function fileName = getFileName(obj, filePath)
            %GETFILENAME Extract filename from path
            [~, fileName, ext] = fileparts(filePath);
            fileName = [fileName, ext];
        end
    end
end