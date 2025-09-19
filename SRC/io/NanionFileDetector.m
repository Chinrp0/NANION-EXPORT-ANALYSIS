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
        %DETECTPROTOCOL Simple protocol detection
        
        obj.logger.logInfo(sprintf('Detecting protocol for: %s', obj.getFileName(filePath)));
        
        try
            % Read header section
            headerData = readcell(filePath, 'Range', 'A1:ZZ15', 'UseExcel', false);
            
            % Search for protocol keywords
            protocolType = '';
            for row = 1:size(headerData, 1)
                rowText = strjoin(string(headerData(row, :)), ' ');
                
                if contains(rowText, 'Peak', 'IgnoreCase', true)
                    protocolType = 'activation';
                    break;
                elseif contains(rowText, 'Inact', 'IgnoreCase', true) && contains(rowText, 'Act', 'IgnoreCase', true)
                    protocolType = 'inactivation';
                    break;
                end
            end
            
            if isempty(protocolType)
                obj.logger.logWarning('No protocol keywords found');
                protocolInfo = [];
                return;
            end
            
            % Simple IV count and column mapping
            numIVs = obj.calculateNumIVs(headerData(1, :));
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
        function numIVs = calculateNumIVs(obj, headerRow1)
        %CALCULATENUMIVS Simple IV calculation based on column count
        
        numCols = length(headerRow1);
        
        % Direct calculation based on known column patterns
        % Activation: every 6 columns, Inactivation: every 7 columns
        % Use conservative estimate of 6 columns per IV
        numIVs = max(1, floor(numCols / 6));
        
        obj.logger.logInfo(sprintf('Estimated %d IVs from %d columns', numIVs, numCols));
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