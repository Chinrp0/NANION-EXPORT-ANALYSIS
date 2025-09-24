classdef NanionDataExtractor < handle
    %NANIONDATAEXTRACTOR Extract electrophysiology measurements from parsed data
    %   Converts Col_X tables back to meaningful parameter measurements
    %   Maintains Well_ID mapping throughout the extraction process
    %   NOW WITH PROPER UNIT CONVERSIONS AND ENHANCED FILTER REPORTING
    
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
            %APPLYQUALITYFILTERS Apply series R, seal R, and capacitance filters with IV2 fallback
            %   Input: extractedData from extractMeasurements()
            %   Output: filteredData with quality filter results and detailed reporting
            
            obj.logger.logInfo('Applying quality filters with IV2 fallback...');
            
            measurements = extractedData.measurements;
            filters = obj.config.filters;
            numWells = extractedData.numWells;
            
            % Initialize quality assessment arrays
            qualityMask = false(numWells, 1);
            ivUsedForFiltering = strings(numWells, 1);  % Track which IV was used
            
            % Get IV1 and IV2 data
            iv1Data = measurements.iv1;
            hasIV2 = isfield(measurements, 'iv2');
            if hasIV2
                iv2Data = measurements.iv2;
            end
            
            % Apply filtering with IV2 fallback logic
            for wellIdx = 1:numWells
                [passed, ivUsed] = obj.assessWellQuality(iv1Data, iv2Data, wellIdx, filters, hasIV2);
                qualityMask(wellIdx) = passed;
                ivUsedForFiltering(wellIdx) = ivUsed;
            end
            
            % Create enhanced filter report with IV fallback information
            filterReport = obj.createIVFallbackFilterReport(extractedData.wellIDs, measurements, ...
                qualityMask, ivUsedForFiltering, filters, hasIV2);
            
            % Apply mask to all measurements
            filteredMeasurements = obj.applyFilterMask(measurements, qualityMask);
            
            filteredData = struct(...
                'wellIDs', extractedData.wellIDs(qualityMask), ...
                'measurements', filteredMeasurements, ...
                'protocolInfo', extractedData.protocolInfo, ...
                'qualityMask', qualityMask, ...
                'ivUsedForFiltering', ivUsedForFiltering(qualityMask), ...  % Track IV source
                'filterReport', filterReport, ...
                'numWellsPassed', sum(qualityMask), ...
                'numWellsTotal', length(qualityMask));
            
            % Log detailed filtering results
            obj.logIVFallbackFilteringResults(filterReport, hasIV2);
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
        
        function [passed, ivUsed] = assessWellQuality(obj, iv1Data, iv2Data, wellIdx, filters, hasIV2)
            %ASSESSWELLQUALITY Assess well quality with IV2 fallback logic
            %   Returns: [passed, ivUsed] where ivUsed is 'iv1', 'iv2', or 'failed'
            
            % First try IV1
            iv1SeriesR = iv1Data.seriesResistance(wellIdx);
            iv1SealR = iv1Data.sealResistance(wellIdx);
            iv1Cap = iv1Data.capacitance(wellIdx);
            
            % Check if IV1 has all required parameters and passes thresholds
            iv1HasData = ~isnan(iv1SeriesR) && ~isnan(iv1SealR) && ~isnan(iv1Cap);
            if iv1HasData
                iv1PassesThresholds = (iv1SeriesR <= filters.maxSeriesResistance) && ...
                                     (iv1SealR <= filters.maxSealResistance) && ...
                                     (iv1Cap <= filters.maxCapacitance);
                if iv1PassesThresholds
                    passed = true;
                    ivUsed = 'iv1';
                    return;
                end
            end
            
            % If IV1 failed and IV2 is available, try IV2
            if hasIV2
                iv2SeriesR = iv2Data.seriesResistance(wellIdx);
                iv2SealR = iv2Data.sealResistance(wellIdx);
                iv2Cap = iv2Data.capacitance(wellIdx);
                
                % Check if IV2 has all required parameters and passes thresholds
                iv2HasData = ~isnan(iv2SeriesR) && ~isnan(iv2SealR) && ~isnan(iv2Cap);
                if iv2HasData
                    iv2PassesThresholds = (iv2SeriesR <= filters.maxSeriesResistance) && ...
                                         (iv2SealR <= filters.maxSealResistance) && ...
                                         (iv2Cap <= filters.maxCapacitance);
                    if iv2PassesThresholds
                        passed = true;
                        ivUsed = 'iv2';
                        return;
                    end
                end
            end
            
            % Both IVs failed or IV2 not available
            passed = false;
            if iv1HasData
                ivUsed = 'iv1_threshold_fail';
            elseif hasIV2 && ~isnan(iv2Data.seriesResistance(wellIdx))
                ivUsed = 'iv2_threshold_fail';  
            else
                ivUsed = 'nan_failure';
            end
        end
        
        function filterReport = createIVFallbackFilterReport(obj, wellIDs, measurements, qualityMask, ivUsedForFiltering, filters, hasIV2)
            %CREATEIVFALLBACKFILTERREPORT Generate filter report with IV fallback information
            
            numWells = length(wellIDs);
            iv1Data = measurements.iv1;
            
            % Count IV usage
            iv1Used = sum(ivUsedForFiltering == "iv1");
            if hasIV2
                iv2Used = sum(ivUsedForFiltering == "iv2");
            else
                iv2Used = 0;
            end
            
            % Count failure types across both IVs
            iv1SeriesRNaN = sum(isnan(iv1Data.seriesResistance));
            iv1SealRNaN = sum(isnan(iv1Data.sealResistance));
            iv1CapacitanceNaN = sum(isnan(iv1Data.capacitance));
            
            % Threshold failures (IV1 only for backward compatibility)
            iv1SeriesRThresholdFail = sum(~isnan(iv1Data.seriesResistance) & (iv1Data.seriesResistance > filters.maxSeriesResistance));
            iv1SealRThresholdFail = sum(~isnan(iv1Data.sealResistance) & (iv1Data.sealResistance > filters.maxSealResistance));
            iv1CapacitanceThresholdFail = sum(~isnan(iv1Data.capacitance) & (iv1Data.capacitance > filters.maxCapacitance));
            
            % Create comprehensive filter report
            filterReport = struct(...
                'totalWells', numWells, ...
                'passedWells', sum(qualityMask), ...
                'failedWells', sum(~qualityMask), ...
                'ivUsage', struct(...
                    'iv1Used', iv1Used, ...
                    'iv2Used', iv2Used, ...
                    'iv2Available', hasIV2), ...
                'nanFailures', struct(...
                    'seriesR', struct('count', iv1SeriesRNaN, 'wellIDs', wellIDs(isnan(iv1Data.seriesResistance))), ...
                    'sealR', struct('count', iv1SealRNaN, 'wellIDs', wellIDs(isnan(iv1Data.sealResistance))), ...
                    'capacitance', struct('count', iv1CapacitanceNaN, 'wellIDs', wellIDs(isnan(iv1Data.capacitance)))), ...
                'thresholdFailures', struct(...
                    'seriesR', struct('count', iv1SeriesRThresholdFail, 'threshold', filters.maxSeriesResistance), ...
                    'sealR', struct('count', iv1SealRThresholdFail, 'threshold', filters.maxSealResistance), ...
                    'capacitance', struct('count', iv1CapacitanceThresholdFail, 'threshold', filters.maxCapacitance)), ...
                'validDataCounts', struct(...
                    'seriesR', sum(~isnan(iv1Data.seriesResistance)), ...
                    'sealR', sum(~isnan(iv1Data.sealResistance)), ...
                    'capacitance', sum(~isnan(iv1Data.capacitance))));
        end
        
        function logIVFallbackFilteringResults(obj, filterReport, hasIV2)
            %LOGIVFALLBACKFILTERINGRESULTS Log detailed filtering results with IV fallback info
            
            obj.logger.logInfo(sprintf('✓ Quality filtering complete: %d/%d wells passed', ...
                filterReport.passedWells, filterReport.totalWells));
            
            % Log IV usage statistics
            if hasIV2
                obj.logger.logInfo('--- IV Usage for Quality Assessment ---');
                obj.logger.logInfo(sprintf('IV1 used: %d wells (%.1f%%)', ...
                    filterReport.ivUsage.iv1Used, ...
                    100 * filterReport.ivUsage.iv1Used / filterReport.totalWells));
                obj.logger.logInfo(sprintf('IV2 fallback used: %d wells (%.1f%%)', ...
                    filterReport.ivUsage.iv2Used, ...
                    100 * filterReport.ivUsage.iv2Used / filterReport.totalWells));
            end
            
            % Log NaN exclusions  
            obj.logger.logInfo('--- Missing Data Exclusions (IV1 reference) ---');
            obj.logger.logInfo(sprintf('Series R NaN: %d wells (%.1f%%)', ...
                filterReport.nanFailures.seriesR.count, ...
                100 * filterReport.nanFailures.seriesR.count / filterReport.totalWells));
            obj.logger.logInfo(sprintf('Seal R NaN: %d wells (%.1f%%)', ...
                filterReport.nanFailures.sealR.count, ...
                100 * filterReport.nanFailures.sealR.count / filterReport.totalWells));
            obj.logger.logInfo(sprintf('Capacitance NaN: %d wells (%.1f%%)', ...
                filterReport.nanFailures.capacitance.count, ...
                100 * filterReport.nanFailures.capacitance.count / filterReport.totalWells));
            
            % Log threshold exceedances
            obj.logger.logInfo('--- Threshold Exceedances (IV1 reference) ---');
            obj.logger.logInfo(sprintf('Series R > %.1f MΩ: %d/%d valid wells (%.1f%%)', ...
                filterReport.thresholdFailures.seriesR.threshold, ...
                filterReport.thresholdFailures.seriesR.count, ...
                filterReport.validDataCounts.seriesR, ...
                100 * filterReport.thresholdFailures.seriesR.count / max(1, filterReport.validDataCounts.seriesR)));
            obj.logger.logInfo(sprintf('Seal R > %.1f GΩ: %d/%d valid wells (%.1f%%)', ...
                filterReport.thresholdFailures.sealR.threshold, ...
                filterReport.thresholdFailures.sealR.count, ...
                filterReport.validDataCounts.sealR, ...
                100 * filterReport.thresholdFailures.sealR.count / max(1, filterReport.validDataCounts.sealR)));
            obj.logger.logInfo(sprintf('Capacitance > %.1f pF: %d/%d valid wells (%.1f%%)', ...
                filterReport.thresholdFailures.capacitance.threshold, ...
                filterReport.thresholdFailures.capacitance.count, ...
                filterReport.validDataCounts.capacitance, ...
                100 * filterReport.thresholdFailures.capacitance.count / max(1, filterReport.validDataCounts.capacitance)));
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