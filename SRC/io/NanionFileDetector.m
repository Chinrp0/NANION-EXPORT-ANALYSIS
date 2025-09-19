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
            %DETECTPROTOCOL Determine file protocol type and structure
            %   Returns protocol information or empty if detection fails
            
            obj.logger.logInfo(sprintf('Detecting protocol for: %s', obj.getFileName(filePath)));
            
            try
                % Quick read of headers only (first ~10 rows)
                headerData = readcell(filePath, 'Range', 'A1:ZZ10', 'UseExcel', false);
                
                % Find header structure
                headerInfo = obj.findQuickHeaderStructure(headerData);
                
                if isempty(headerInfo)
                    obj.logger.logWarning('Cannot find header structure for protocol detection');
                    protocolInfo = [];
                    return;
                end
                
                % Extract header rows
                headerRow2 = headerData(headerInfo.headerRow2Idx, :);
                headerRow1 = headerData(headerInfo.headerRow1Idx, :);
                
                % Detect protocol type
                protocolType = obj.detectProtocolType(headerRow2);
                
                if isempty(protocolType)
                    obj.logger.logWarning('Cannot determine protocol type');
                    protocolInfo = [];
                    return;
                end
                
                % Calculate number of IVs
                numIVs = obj.calculateNumIVs(headerRow1);
                
                % Get column mapping
                columnMapping = obj.getColumnMapping(protocolType);
                
                protocolInfo = struct(...
                    'type', protocolType, ...
                    'numIVs', numIVs, ...
                    'columnMapping', columnMapping, ...
                    'headerInfo', headerInfo);
                
                obj.logger.logInfo(sprintf('✓ Detected %s protocol with %d IVs', ...
                    protocolType, numIVs));
                
            catch ME
                obj.logger.logError(sprintf('Protocol detection failed: %s', ME.message));
                protocolInfo = [];
            end
        end
        
        function isValid = validateProtocol(obj, protocolInfo, fullHeaderData)
            %VALIDATEPROTOCOL Validate detected protocol against full data
            %   More thorough validation using complete file headers
            
            isValid = false;
            
            try
                if isempty(protocolInfo)
                    return;
                end
                
                % Validate column pattern consistency
                expectedPattern = protocolInfo.columnMapping.columnPattern;
                actualColumns = size(fullHeaderData, 2);
                expectedColumns = protocolInfo.numIVs * expectedPattern;
                
                % Allow some tolerance for extra columns
                if actualColumns < expectedColumns * 0.8
                    obj.logger.logWarning(sprintf('Column count mismatch: expected ~%d, got %d', ...
                        expectedColumns, actualColumns));
                    return;
                end
                
                % Validate that key columns exist and have expected content
                isValid = obj.validateKeyColumns(protocolInfo, fullHeaderData);
                
                if isValid
                    obj.logger.logInfo('Protocol validation passed');
                else
                    obj.logger.logWarning('Protocol validation failed');
                end
                
            catch ME
                obj.logger.logError(sprintf('Protocol validation error: %s', ME.message));
            end
        end
    end
    
    methods (Access = private)
        function headerInfo = findQuickHeaderStructure(obj, headerData)
            %FINDQUICKHEADERSTRUCTURE Find headers in limited data
            
            if size(headerData, 1) < 3
                headerInfo = [];
                return;
            end
            
            col1 = headerData(:, 1);
            
            % Look for empty cell pattern
            emptyIdx = [];
            for i = 1:length(col1)
                if obj.isEmptyCell(col1{i})
                    emptyIdx = i;
                    break;
                end
            end
            
            if isempty(emptyIdx) || emptyIdx + 2 > size(headerData, 1)
                headerInfo = [];
                return;
            end
            
            headerInfo = struct(...
                'emptyRowIdx', emptyIdx, ...
                'headerRow1Idx', emptyIdx + 1, ...
                'headerRow2Idx', emptyIdx + 2);
        end
        
        function protocolType = detectProtocolType(obj, headerRow2)
            %DETECTPROTOCOLTYPE Determine protocol from header keywords
            
            protocolType = '';
            
            % Convert headers to string array for analysis
            headerStrings = obj.convertToStringArray(headerRow2);
            
            % Check for activation markers
            activationMarkers = {'Peak'};
            hasActivation = any(contains(headerStrings, activationMarkers, 'IgnoreCase', true));
            
            % Check for inactivation markers
            inactivationMarkers = {'Inact', 'Act'};
            hasInactivation = any(contains(headerStrings, inactivationMarkers, 'IgnoreCase', true));
            
            if hasActivation && ~hasInactivation
                protocolType = 'activation';
            elseif hasInactivation
                % Inactivation files can have both 'Inact' and 'Act' columns
                protocolType = 'inactivation';
            else
                obj.logger.logWarning('No clear protocol markers found in headers');
            end
        end
        
        function numIVs = calculateNumIVs(obj, headerRow1)
            %CALCULATENUMIVS Calculate number of IV groups
            
            numIVs = 0;
            
            try
                % Look for sweep numbers in first header row
                headerStrings = obj.convertToStringArray(headerRow1);
                
                sweepNumbers = [];
                for i = 1:length(headerStrings)
                    str = headerStrings{i};
                    if contains(str, 'Sweep', 'IgnoreCase', true)
                        % Extract number from "Sweep XXX" format
                        matches = regexp(str, 'Sweep\s*(\d+)', 'tokens', 'ignorecase');
                        if ~isempty(matches)
                            sweepNumbers(end+1) = str2double(matches{1}{1});
                        end
                    end
                end
                
                if ~isempty(sweepNumbers)
                    maxSweep = max(sweepNumbers);
                    % Assume 23 data points per IV (from config)
                    numIVs = ceil(maxSweep / 23);
                else
                    obj.logger.logWarning('Could not find sweep information, estimating IVs from column count');
                    % Fallback: estimate from column count
                    numCols = length(headerRow1);
                    numIVs = max(1, floor(numCols / 6)); % Conservative estimate
                end
                
            catch ME
                obj.logger.logWarning(sprintf('IV calculation failed: %s', ME.message));
                numIVs = 1; % Safe fallback
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
        
        function isValid = validateKeyColumns(obj, protocolInfo, fullHeaderData)
            %VALIDATEKEYCOLUMNS Check that key columns exist with expected content
            
            isValid = false;
            
            try
                headerRow2 = fullHeaderData(protocolInfo.headerInfo.headerRow2Idx, :);
                headerStrings = obj.convertToStringArray(headerRow2);
                
                mapping = protocolInfo.columnMapping;
                
                % Check first few expected columns exist
                maxColToCheck = min(mapping.columnPattern * 3, length(headerStrings));
                
                if maxColToCheck < mapping.columnPattern * 2
                    obj.logger.logWarning('Not enough columns for thorough validation');
                    return;
                end
                
                % Basic validation: check that we have some data-like headers
                % in expected positions
                dataColumnCount = 0;
                for col = 1:min(maxColToCheck, length(headerStrings))
                    headerContent = headerStrings{col};
                    if ~isempty(headerContent) && ~contains(headerContent, 'Well', 'IgnoreCase', true)
                        dataColumnCount = dataColumnCount + 1;
                    end
                end
                
                % Should have reasonable number of data columns
                expectedDataCols = mapping.columnPattern * protocolInfo.numIVs * 0.6;
                isValid = dataColumnCount >= expectedDataCols;
                
            catch ME
                obj.logger.logWarning(sprintf('Column validation error: %s', ME.message));
            end
        end
        
        function stringArray = convertToStringArray(obj, cellArray)
            %CONVERTTOSTRINGARRAY Convert cell array to clean string array
            
            stringArray = cell(size(cellArray));
            
            for i = 1:length(cellArray)
                cell_val = cellArray{i};
                
                if obj.isEmptyCell(cell_val)
                    stringArray{i} = '';
                elseif isnumeric(cell_val)
                    stringArray{i} = num2str(cell_val);
                elseif ischar(cell_val) || isstring(cell_val)
                    stringArray{i} = char(strtrim(string(cell_val)));
                else
                    stringArray{i} = '';
                end
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