classdef NanionFileDetector < handle
    %NANIONFILEDETECTOR Protocol detection for Nanion Excel files
    %   Distinguishes between activation and inactivation protocols
    %   Extracts voltage protocols from data files
    
    properties (Access = private)
        logger
    end
    
    methods
        function obj = NanionFileDetector(logger)
            %NANIONFILEDETECTOR Constructor
            obj.logger = logger;
        end
        
        function protocolInfo = detectProtocol(obj, filePath)
            %DETECTPROTOCOL Detect protocol type and extract voltage information
            
            obj.logger.logInfo(sprintf('Detecting protocol for: %s', obj.getFileName(filePath)));
            
            try
                % Read extended header section to include voltage data (Row 10)
                headerData = readcell(filePath, 'Range', 'A1:ZZ15', 'UseExcel', false);
                
                % Detect protocol type
                protocolType = obj.detectProtocolType(headerData);
                
                if isempty(protocolType)
                    obj.logger.logWarning('No protocol keywords found');
                    protocolInfo = [];
                    return;
                end
                
                % Calculate number of IVs
                numIVs = obj.calculateNumIVs(headerData);
                
                % Extract voltage protocol from Row 10
                % Uses same column positions as peak current/data columns
                voltages = obj.extractVoltageProtocol(headerData, protocolType);
                
                % Get column mapping
                columnMapping = obj.getColumnMapping(protocolType);
                
                % Package protocol information
                protocolInfo = struct(...
                    'type', protocolType, ...
                    'numIVs', numIVs, ...
                    'voltages', voltages, ...
                    'numSweeps', length(voltages), ...
                    'columnMapping', columnMapping);
                
                obj.logger.logInfo(sprintf('✓ Detected %s protocol: %d IVs, %d sweeps per IV', ...
                    protocolType, numIVs, length(voltages)));
                obj.logger.logInfo(sprintf('  Voltage range: %.1f to %.1f mV', ...
                    min(voltages), max(voltages)));
                
            catch ME
                obj.logger.logError(sprintf('Protocol detection failed: %s', ME.message));
                protocolInfo = [];
            end
        end
    end
    
    methods (Access = private)
        function protocolType = detectProtocolType(obj, headerData)
            %DETECTPROTOCOLTYPE Detect activation vs inactivation protocol
            %   Fallback chain (most robust first):
            %     1. 'Protocol Name' cell (row 1): NaIV -> activation, SSI -> inactivation
            %     2. Columns-per-sweep: 6 -> activation, 7 -> inactivation
            %     3. Legacy header keyword scan (Peak / Inact+Act)
            %   Protocol-name values are inconsistent across exports (seen
            %   'NaIV_LIBD', blank, 'SSI'), so the column pattern is the trusted
            %   fallback whenever the name is missing or unrecognized.

            protocolType = '';

            % --- 1. Protocol name string ---
            protocolName = obj.getProtocolName(headerData);
            if ~isempty(protocolName)
                if contains(protocolName, 'NaIV', 'IgnoreCase', true)
                    protocolType = 'activation';
                    obj.logger.logInfo(sprintf('Protocol name "%s" -> activation', protocolName));
                    return;
                elseif contains(protocolName, 'SSI', 'IgnoreCase', true)
                    protocolType = 'inactivation';
                    obj.logger.logInfo(sprintf('Protocol name "%s" -> inactivation', protocolName));
                    return;
                else
                    obj.logger.logWarning(sprintf(...
                        'Unrecognized protocol name "%s"; falling back to column pattern', protocolName));
                end
            else
                obj.logger.logInfo('Protocol name cell empty; using column-pattern detection');
            end

            % --- 2. Columns per sweep (content-based, survives renamed files) ---
            colsPerSweep = obj.countColumnsPerSweep(headerData);
            switch colsPerSweep
                case 6
                    protocolType = 'activation';
                    obj.logger.logInfo('Column pattern (6 cols/sweep) -> activation');
                    return;
                case 7
                    protocolType = 'inactivation';
                    obj.logger.logInfo('Column pattern (7 cols/sweep) -> inactivation');
                    return;
                otherwise
                    if colsPerSweep > 0
                        obj.logger.logWarning(sprintf(...
                            'Ambiguous column pattern (%d cols/sweep); trying keyword scan', colsPerSweep));
                    end
            end

            % --- 3. Legacy keyword scan (last resort) ---
            protocolType = obj.detectProtocolTypeByKeywords(headerData);
            if ~isempty(protocolType)
                obj.logger.logWarning(sprintf('Detected %s via legacy keyword scan', protocolType));
            end
        end

        function protocolName = getProtocolName(obj, headerData)
            %GETPROTOCOLNAME Value of the cell to the right of the 'Protocol Name' label
            protocolName = '';
            maxRow = min(3, size(headerData, 1));
            for row = 1:maxRow
                for col = 1:size(headerData, 2)
                    label = obj.cellToStr(headerData{row, col});
                    if contains(label, 'Protocol Name', 'IgnoreCase', true)
                        for c2 = col+1:size(headerData, 2)
                            val = strtrim(obj.cellToStr(headerData{row, c2}));
                            if ~isempty(val)
                                protocolName = val;
                                return;
                            end
                        end
                    end
                end
            end
        end

        function colsPerSweep = countColumnsPerSweep(obj, headerData)
            %COUNTCOLUMNSPERSWEEP Stride between the first 'Sweep 001' and 'Sweep 002'
            %   columns in the sweep header row. 6 = activation, 7 = inactivation.
            colsPerSweep = 0;
            for row = 1:size(headerData, 1)
                firstCol001 = 0;
                firstCol002 = 0;
                for col = 1:size(headerData, 2)
                    s = obj.cellToStr(headerData{row, col});
                    if firstCol001 == 0 && contains(s, 'Sweep 001', 'IgnoreCase', true)
                        firstCol001 = col;
                    elseif firstCol002 == 0 && contains(s, 'Sweep 002', 'IgnoreCase', true)
                        firstCol002 = col;
                    end
                end
                if firstCol001 > 0 && firstCol002 > firstCol001
                    colsPerSweep = firstCol002 - firstCol001;
                    return;
                end
            end
        end

        function protocolType = detectProtocolTypeByKeywords(obj, headerData)
            %DETECTPROTOCOLTYPEBYKEYWORDS Legacy scan for Peak / Inact+Act markers

            protocolType = '';

            for row = 1:size(headerData, 1)
                rowCells = headerData(row, :);
                searchStr = '';

                for col = 1:length(rowCells)
                    searchStr = [searchStr, ' ', obj.cellToStr(rowCells{col})]; %#ok<AGROW>
                end

                % Check for activation protocol
                if contains(searchStr, 'Peak', 'IgnoreCase', true)
                    protocolType = 'activation';
                    obj.logger.logInfo(sprintf('Found activation keywords in row %d', row));
                    break;
                end

                % Check for inactivation protocol
                hasInact = contains(searchStr, 'Inact', 'IgnoreCase', true);
                hasAct = contains(searchStr, 'Act', 'IgnoreCase', true);

                if hasInact && hasAct
                    protocolType = 'inactivation';
                    obj.logger.logInfo(sprintf('Found inactivation keywords in row %d', row));
                    break;
                end
            end
        end

        function s = cellToStr(~, v)
            %CELLTOSTR Convert a cell value to char ('' for empty/missing/NaN)
            s = '';
            if isempty(v)
                return;
            end
            if ischar(v)
                s = v;
            elseif isstring(v)
                if ~ismissing(v)
                    s = char(v);
                end
            elseif isnumeric(v) && ~any(isnan(v(:)))
                s = num2str(v(1));
            end
        end
        
        function voltages = extractVoltageProtocol(obj, headerData, protocolType)
            %EXTRACTVOLTAGEPROTOCOL Extract voltage steps from Row 10
            %   Row 10, Column 1 label: "Abs. V/I of incr. segment"
            %   Voltage values at same column positions as peak current/data columns
            
            try
                % Row 10 is the voltage protocol row (index 10)
                voltageRow = headerData(10, :);
                
                % Column structure:
                % Cols 1-3: Metadata (Parameter, Cell Type, Cell Concentration)
                % Cols 4-9: First sweep (Compound, Concentration, SeriesR, SealR, Cap, Peak/Data)
                % Cols 10-15: Second sweep (repeats every 6 or 7 columns)
                
                % Determine parameters based on protocol type
                if strcmp(protocolType, 'activation')
                    colStride = 6;      % Every 6th column for activation
                    dataCol = 9;        % Peak current column (same position as voltage data)
                elseif strcmp(protocolType, 'inactivation')
                    colStride = 7;      % Every 7th column for inactivation
                    dataCol = 9;        % Inact data column (same position as voltage data)
                else
                    error('Unknown protocol type: %s', protocolType);
                end
                
                % Extract voltage values from Row 10 at data column positions
                % Expected: 23 sweeps from -80 to +30 mV (5 mV steps)
                expectedSweeps = 23;
                voltages = zeros(1, expectedSweeps);
                
                for sweepIdx = 1:expectedSweeps
                    % Calculate column index: starts at dataCol, repeats every colStride
                    % For activation: [9, 15, 21, 27, 33, ...]
                    % For inactivation: [9, 16, 23, 30, 37, ...]
                    colIdx = dataCol + (sweepIdx - 1) * colStride;
                    
                    if colIdx <= length(voltageRow)
                        voltageCellValue = voltageRow{colIdx};
                        
                        % Convert to numeric and to mV
                        if isnumeric(voltageCellValue)
                            voltages(sweepIdx) = voltageCellValue * 1000;  % Convert V → mV
                        elseif ischar(voltageCellValue) || isstring(voltageCellValue)
                            voltages(sweepIdx) = str2double(voltageCellValue) * 1000;  % Convert V → mV
                        else
                            voltages(sweepIdx) = NaN;
                        end
                    else
                        voltages(sweepIdx) = NaN;
                    end
                end
                
                % Validate voltage extraction
                numValidVoltages = sum(~isnan(voltages));
                if numValidVoltages < 20
                    obj.logger.logWarning(sprintf('Only extracted %d/%d valid voltages', ...
                        numValidVoltages, expectedSweeps));
                end
                
                obj.logger.logInfo(sprintf('Extracted %d voltage steps from Row 10, columns [%d:%d:%d]', ...
                    numValidVoltages, dataCol, colStride, dataCol + (expectedSweeps-1)*colStride));
                
            catch ME
                obj.logger.logError(sprintf('Voltage extraction failed: %s', ME.message));
                % Fallback to default voltage range
                obj.logger.logWarning('Using default voltage range: -80 to +30 mV (5 mV steps)');
                voltages = -80:5:30;  % Default: 23 steps from -80 to +30 mV
            end
        end
        
        function numIVs = calculateNumIVs(obj, headerData)
            %CALCULATENUMIVS Get total sweeps from Row 2, Col 2
            
            try
                totalSweeps = headerData{2, 2};
                
                if isempty(totalSweeps) || ismissing(totalSweeps)
                    error('Row 2, Col 2 is empty or missing');
                end
                
                if ischar(totalSweeps) || isstring(totalSweeps)
                    totalSweeps = str2double(totalSweeps);
                end
                
                if isnan(totalSweeps)
                    error('Could not convert sweep count to number');
                end
                
                numDataPoints = 23;
                numIVs = ceil(totalSweeps / numDataPoints);
                
                obj.logger.logInfo(sprintf('Found %d total sweeps → %d IVs', totalSweeps, numIVs));
                
            catch ME
                obj.logger.logError(sprintf('IV calculation failed: %s', ME.message));
                
                % Fallback to column-based estimate
                numCols = size(headerData, 2);
                numIVs = max(1, floor(numCols / 23));
                obj.logger.logWarning(sprintf('Using fallback: estimated %d IVs from column count', numIVs));
            end
        end
        
        function columnMapping = getColumnMapping(obj, protocolType)
            %GETCOLUMNMAPPING Get column patterns for protocol type
            %   Column structure (after metadata cols 1-3):
            %   Activation: 6 cols/sweep [Compound, Conc, SeriesR, SealR, Cap, Peak]
            %   Inactivation: 7 cols/sweep [Compound, Conc, SeriesR, SealR, Cap, Inact, Act]
            
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
        
        function fileName = getFileName(obj, filePath)
            %GETFILENAME Extract filename from path
            [~, fileName, ext] = fileparts(filePath);
            fileName = [fileName, ext];
        end
    end
end
