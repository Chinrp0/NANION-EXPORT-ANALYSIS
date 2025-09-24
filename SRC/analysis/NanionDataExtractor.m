classdef NanionDataExtractor < handle
    %NANIONDATAEXTRACTOR Extract electrophysiology measurements from parsed data
    %   Converts Col_X tables back to meaningful parameter measurements
    %   Maintains Well_ID mapping throughout the extraction process
    %   NOW WITH PROPER UNIT CONVERSIONS
    
    properties (Access = private)
        config
        logger
    end
    
    methods
        function obj = NanionDataExtractor(config, logger)
            %NANIONDATAEXTRACTOR Constructor
            obj.config = config;
            obj.logger = logger;
        end
        
        function extractedData = extractMeasurements(obj, parsedData)
            %EXTRACTMEASUREMENTS Extract parameter measurements from parsed table
            %   Input: parsedData struct from NanionIOManager.parseData()
            %   Output: extractedData struct with measurements organized by IV and parameter
            
            dataTable = parsedData.dataTable;
            protocolInfo = parsedData.protocolInfo;
            dataStartRow = parsedData.headerInfo.dataStartRow;
            
            obj.logger.logInfo('Extracting measurements from parsed data...');
            
            try
                % Extract Well IDs from first column, starting at data row
                wellIDs = obj.extractWellIDs(dataTable, dataStartRow);
                
                % Extract measurements based on protocol type
                measurements = obj.extractByProtocol(dataTable, protocolInfo, dataStartRow);
                
                % Package extracted data with Well ID mapping
                extractedData = struct(...
                    'wellIDs', wellIDs, ...
                    'measurements', measurements, ...
                    'protocolInfo', protocolInfo, ...
                    'numWells', length(wellIDs), ...
                    'numIVs', protocolInfo.numIVs);
                
                obj.logger.logInfo(sprintf('✓ Extracted measurements: %d wells, %d IVs', ...
                    extractedData.numWells, extractedData.numIVs));
                
            catch ME
                obj.logger.logError(sprintf('Measurement extraction failed: %s', ME.message));
                rethrow(ME);
            end
        end
        
        function filteredData = applyQualityFilters(obj, extractedData)
            %APPLYQUALITYFILTERS Apply series R, seal R, and capacitance filters
            %   Input: extractedData from extractMeasurements()
            %   Output: filteredData with quality filter results
            
            obj.logger.logInfo('Applying quality filters...');
            
            measurements = extractedData.measurements;
            filters = obj.config.filters;
            
            % Apply filters to IV1 only (as specified in requirements)
            iv1Data = measurements.iv1;
            
            % Series Resistance filter (≤ maxSeriesResistance MΩ)
            seriesRValid = iv1Data.seriesResistance <= filters.maxSeriesResistance;
            
            % Seal Resistance filter (≤ maxSealResistance GΩ)  
            sealRValid = iv1Data.sealResistance <= filters.maxSealResistance;
            
            % Capacitance filter (≤ maxCapacitance pF)
            capacitanceValid = iv1Data.capacitance <= filters.maxCapacitance;
            
            % Combined filter: all criteria must pass
            qualityMask = seriesRValid & sealRValid & capacitanceValid;
            
            % Create filter report
            filterReport = obj.createFilterReport(extractedData.wellIDs, iv1Data, qualityMask, filters);
            
            % Apply mask to all measurements
            filteredMeasurements = obj.applyFilterMask(measurements, qualityMask);
            
            filteredData = struct(...
                'wellIDs', extractedData.wellIDs(qualityMask), ...
                'measurements', filteredMeasurements, ...
                'protocolInfo', extractedData.protocolInfo, ...
                'qualityMask', qualityMask, ...
                'filterReport', filterReport, ...
                'numWellsPassed', sum(qualityMask), ...
                'numWellsTotal', length(qualityMask));
            
            obj.logger.logInfo(sprintf('✓ Quality filtering complete: %d/%d wells passed', ...
                filteredData.numWellsPassed, filteredData.numWellsTotal));
        end
    end
    
    methods (Access = private)
        function wellIDs = extractWellIDs(obj, dataTable, dataStartRow)
            %EXTRACTWELLIDS Extract Well_ID values from first column
            
            % Well IDs are in first column, starting at dataStartRow
            % Skip header rows to get to actual well data
            wellColumn = dataTable{dataStartRow:end, 1};
            
            % Convert to string array for consistency
            wellIDs = string(wellColumn);
            
            % Remove any empty or invalid entries
            validMask = ~ismissing(wellIDs) & wellIDs ~= "";
            wellIDs = wellIDs(validMask);
            
            obj.logger.logInfo(sprintf('Extracted %d well IDs (first: %s, last: %s)', ...
                length(wellIDs), wellIDs(1), wellIDs(end)));
        end
        
        function measurements = extractByProtocol(obj, dataTable, protocolInfo, dataStartRow)
            %EXTRACTBYPROTOCOL Extract measurements using protocol-specific column patterns
            
            dataRows = dataTable(dataStartRow:end, :);
            numDataRows = height(dataRows);
            
            switch protocolInfo.type
                case 'activation'
                    measurements = obj.extractActivationMeasurements(dataRows, protocolInfo);
                case 'inactivation'
                    measurements = obj.extractInactivationMeasurements(dataRows, protocolInfo);
                otherwise
                    error('NanionDataExtractor:UnknownProtocol', ...
                        'Unknown protocol type: %s', protocolInfo.type);
            end
            
            obj.logger.logInfo(sprintf('Extracted %s protocol measurements for %d wells', ...
                protocolInfo.type, numDataRows));
        end
        
        function measurements = extractActivationMeasurements(obj, dataRows, protocolInfo)
            %EXTRACTACTIVATIONMEASUREMENTS Extract activation protocol data
            %   Column pattern: every 6 columns
            %   Series R: 6, 12, 18...  |  Peak Current: 9, 15, 21...
            
            columnMapping = protocolInfo.columnMapping;
            numIVs = protocolInfo.numIVs;
            
            measurements = struct();
            
            for iv = 1:numIVs
                ivName = sprintf('iv%d', iv);
                
                % Calculate column indices for this IV
                baseCol = (iv - 1) * columnMapping.columnPattern;
                
                seriesCol = baseCol + columnMapping.seriesResistancePattern(1);
                sealCol = baseCol + columnMapping.sealResistancePattern(1);
                capCol = baseCol + columnMapping.capacitancePattern(1);
                peakCol = baseCol + columnMapping.peakCurrentPattern(1);
                
                % Extract measurements with proper unit conversions
                measurements.(ivName) = struct(...
                    'seriesResistance', obj.extractAndConvert(dataRows, seriesCol, 'seriesR'), ...
                    'sealResistance', obj.extractAndConvert(dataRows, sealCol, 'sealR'), ...
                    'capacitance', obj.extractAndConvert(dataRows, capCol, 'capacitance'), ...
                    'peakCurrent', obj.extractAndConvert(dataRows, peakCol, 'current'));
            end
        end
        
        function measurements = extractInactivationMeasurements(obj, dataRows, protocolInfo)
            %EXTRACTINACTIVATIONMEASUREMENTS Extract inactivation protocol data
            %   Column pattern: every 7 columns
            %   Series R: 6, 13, 20...  |  Inact Data: 9, 16, 23...
            
            columnMapping = protocolInfo.columnMapping;
            numIVs = protocolInfo.numIVs;
            
            measurements = struct();
            
            for iv = 1:numIVs
                ivName = sprintf('iv%d', iv);
                
                baseCol = (iv - 1) * columnMapping.columnPattern;
                
                seriesCol = baseCol + columnMapping.seriesResistancePattern(1);
                sealCol = baseCol + columnMapping.sealResistancePattern(1);
                capCol = baseCol + columnMapping.capacitancePattern(1);
                inactCol = baseCol + columnMapping.inactivationDataPattern(1);
                actCol = baseCol + columnMapping.activationDataPattern(1);
                
                % Extract measurements with proper unit conversions
                measurements.(ivName) = struct(...
                    'seriesResistance', obj.extractAndConvert(dataRows, seriesCol, 'seriesR'), ...
                    'sealResistance', obj.extractAndConvert(dataRows, sealCol, 'sealR'), ...
                    'capacitance', obj.extractAndConvert(dataRows, capCol, 'capacitance'), ...
                    'inactivationData', obj.extractAndConvert(dataRows, inactCol, 'current'), ...
                    'activationData', obj.extractAndConvert(dataRows, actCol, 'current'));
            end
        end
        
        function values = extractAndConvert(obj, dataRows, columnIndex, paramType)
            %EXTRACTANDCONVERT Extract column data and convert to proper scientific units
            
            % Check if column exists
            if columnIndex > size(dataRows, 2)
                obj.logger.logWarning(sprintf('Column %d not found, using NaN', columnIndex));
                values = NaN(height(dataRows), 1);
                return;
            end
            
            % Extract column data
            rawData = dataRows{:, columnIndex};
            
            % Convert to numeric (handle cell arrays, strings, etc.)
            numericData = obj.convertToNumeric(rawData);
            
            % Apply unit conversions based on parameter type
            values = obj.applyUnitConversion(numericData, paramType);
        end
        
        function convertedData = applyUnitConversion(obj, rawData, paramType)
            %APPLYUNITCONVERSION Convert raw instrument values to scientific units
            
            switch lower(paramType)
                case 'seriesr'
                    % Convert from ohms to MΩ (divide by 1,000,000)
                    convertedData = rawData / 1e6;
                    
                case 'sealr'
                    % Convert from ohms to GΩ (divide by 1,000,000,000)
                    convertedData = rawData / 1e9;
                    
                case 'capacitance'
                    % First, try different column locations for capacitance
                    % Capacitance might be stored in different units or locations
                    if all(rawData == 0) || all(isnan(rawData))
                        obj.logger.logWarning('Capacitance values all zero - may need different column mapping');
                        % Keep raw values for now - will need to investigate
                        convertedData = rawData;
                    else
                        % Convert from farads to pF (multiply by 1e12)
                        % OR from other units - will need to analyze actual data
                        convertedData = rawData * 1e12; % Assuming farads to pF
                    end
                    
                case 'current'
                    % Convert from amperes to pA (multiply by 1e12)
                    convertedData = rawData * 1e12;
                    
                otherwise
                    % No conversion for unknown parameter types
                    convertedData = rawData;
            end
            
            % Log conversion statistics for debugging
            if ~all(isnan(convertedData))
                obj.logger.logDebug(sprintf('%s conversion: min=%.2f, max=%.2f, median=%.2f', ...
                    paramType, min(convertedData), max(convertedData), median(convertedData)));
            end
        end
        
        function numericData = convertToNumeric(obj, rawData)
            %CONVERTTONUMERIC Convert cell array data to numeric values
            
            if isnumeric(rawData)
                numericData = rawData;
                return;
            end
            
            % Handle cell array conversion
            numericData = NaN(size(rawData));
            
            for i = 1:height(rawData)
                if isnumeric(rawData{i})
                    numericData(i) = rawData{i};
                elseif ischar(rawData{i}) || isstring(rawData{i})
                    converted = str2double(rawData{i});
                    if ~isnan(converted)
                        numericData(i) = converted;
                    end
                end
            end
        end
        
        function filterReport = createFilterReport(obj, wellIDs, iv1Data, qualityMask, filters)
            %CREATEFILTERREPORT Generate detailed filter report
            
            % Find wells that failed each filter
            seriesFailures = find(iv1Data.seriesResistance > filters.maxSeriesResistance);
            sealFailures = find(iv1Data.sealResistance > filters.maxSealResistance);
            capacitanceFailures = find(iv1Data.capacitance > filters.maxCapacitance);
            
            filterReport = struct(...
                'totalWells', length(wellIDs), ...
                'passedWells', sum(qualityMask), ...
                'failedWells', sum(~qualityMask), ...
                'seriesFailures', struct('count', length(seriesFailures), 'wellIDs', wellIDs(seriesFailures)), ...
                'sealFailures', struct('count', length(sealFailures), 'wellIDs', wellIDs(sealFailures)), ...
                'capacitanceFailures', struct('count', length(capacitanceFailures), 'wellIDs', wellIDs(capacitanceFailures)));
        end
        
        function filteredMeasurements = applyFilterMask(obj, measurements, qualityMask)
            %APPLYFILTERMASK Apply quality mask to all measurement IVs
            
            filteredMeasurements = struct();
            ivFields = fieldnames(measurements);
            
            for i = 1:length(ivFields)
                ivName = ivFields{i};
                ivData = measurements.(ivName);
                
                % Apply mask to all parameters in this IV
                paramFields = fieldnames(ivData);
                for j = 1:length(paramFields)
                    paramName = paramFields{j};
                    filteredMeasurements.(ivName).(paramName) = ivData.(paramName)(qualityMask);
                end
            end
        end
    end
end