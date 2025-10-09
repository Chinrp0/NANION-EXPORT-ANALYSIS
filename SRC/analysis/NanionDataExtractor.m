classdef NanionDataExtractor < handle
    %NANIONDATAEXTRACTOR Extract electrophysiology measurements from parsed data
    %   REFACTORED: Extracts ALL sweeps per IV (23 sweeps → [wells × 23] arrays)
    %   Quality filtering uses MEDIAN-based approach (robust to outliers)
    
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
            %EXTRACTMEASUREMENTS Extract ALL sweep measurements from parsed table
            %   NOW EXTRACTS: [numWells × numSweeps] arrays instead of [numWells × 1]
            %   CALCULATES: Conductance for activation protocols
            
            dataTable = parsedData.dataTable;
            protocolInfo = parsedData.protocolInfo;
            dataStartRow = parsedData.headerInfo.dataStartRow;
            
            obj.logger.logInfo('Extracting ALL sweeps from parsed data...');
            
            try
                % Extract Well IDs
                wellIDs = obj.extractWellIDs(dataTable, dataStartRow);
                
                % Extract measurements (ALL sweeps per IV)
                measurements = obj.extractByProtocol(dataTable, protocolInfo, dataStartRow);
                
                % Package extracted data
                extractedData = struct(...
                    'wellIDs', wellIDs, ...
                    'measurements', measurements, ...
                    'protocolInfo', protocolInfo, ...
                    'numWells', length(wellIDs), ...
                    'numIVs', protocolInfo.numIVs, ...
                    'numSweeps', protocolInfo.numSweeps);
                
                obj.logger.logInfo(sprintf('✓ Extracted: %d wells × %d sweeps × %d IVs', ...
                    extractedData.numWells, extractedData.numSweeps, extractedData.numIVs));
                
                % Calculate conductance for activation protocols
                if strcmp(protocolInfo.type, 'activation')
                    extractedData = obj.calculateConductance(extractedData);
                    extractedData = obj.normalizeConductance(extractedData);  % NEW: Add this line
                end
                
            catch ME
                obj.logger.logError(sprintf('Measurement extraction failed: %s', ME.message));
                rethrow(ME);
            end
        end

                function extractedData = calculateConductance(obj, extractedData)
            %CALCULATECONDUCTANCE Calculate conductance for activation protocols
            %   G = I / (V - V_rev) in nanoSiemens (nS)
            %   Only applies to activation protocols
            
            if ~strcmp(extractedData.protocolInfo.type, 'activation')
                % Not activation - no conductance needed
                return;
            end
            
            obj.logger.logInfo('Calculating conductance (G = I / (V - E_rev))...');
            
            voltages = extractedData.protocolInfo.voltages;  % [1 × 23] mV
            V_rev = obj.config.nernstPotential;  % mV (typically 68 mV for Na+)
            
            % Calculate driving force for each voltage step
            drivingForce = voltages - V_rev;  % [1 × 23] mV
            
            % Process each IV
            measurements = extractedData.measurements;
            ivFields = fieldnames(measurements);
            
            for i = 1:length(ivFields)
                ivName = ivFields{i};
                
                % Get peak current [numWells × 23] in pA
                peakCurrent = measurements.(ivName).peakCurrent;
                
                % Calculate conductance: G = I / (V - V_rev)
                % Units: pA / mV = nS (nanoSiemens)
                conductance = peakCurrent ./ drivingForce;  % [numWells × 23]
                
                % Handle division by zero (if any voltage equals V_rev)
                conductance(isinf(conductance)) = NaN;
                
                % Store conductance alongside current
                measurements.(ivName).conductance = conductance;  % nS
                
                obj.logger.logDebug(sprintf('%s: Calculated conductance (G = I/(V-%.1f))', ...
                    ivName, V_rev));
            end
            
            % Update extracted data
            extractedData.measurements = measurements;
            
            obj.logger.logInfo(sprintf('✓ Conductance calculated for %d wells', ...
                extractedData.numWells));
        end

        function extractedData = normalizeConductance(obj, extractedData)
            %NORMALIZECONDUCTANCE Normalize conductance to 0-1 range per well per IV
            %   G_norm = (G - G_min) / (G_max - G_min)
            %   Only applies to activation protocols
            %   Stores both raw and normalized conductance
            
            if ~strcmp(extractedData.protocolInfo.type, 'activation')
                return;  % Only for activation protocols
            end
            
            obj.logger.logInfo('Normalizing conductance to 0-1 range per well...');
            
            measurements = extractedData.measurements;
            ivFields = fieldnames(measurements);
            
            for i = 1:length(ivFields)
                ivName = ivFields{i};
                
                % Get raw conductance [numWells × 23] in nS
                conductance_raw = measurements.(ivName).conductance;
                numWells = size(conductance_raw, 1);
                
                % Normalize each well independently
                conductance_normalized = zeros(size(conductance_raw));
                
                for wellIdx = 1:numWells
                    G = conductance_raw(wellIdx, :);
                    G_min = min(G);
                    G_max = max(G);
                    
                    if G_max ~= G_min  % Avoid division by zero
                        conductance_normalized(wellIdx, :) = (G - G_min) / (G_max - G_min);
                    else
                        conductance_normalized(wellIdx, :) = zeros(size(G));
                        obj.logger.logWarning(sprintf('%s Well %d: G_max == G_min, setting normalized to 0', ...
                            ivName, wellIdx));
                    end
                end
                
                % Store both raw and normalized
                measurements.(ivName).conductance_raw = conductance_raw;  % Preserve original
                measurements.(ivName).conductance = conductance_normalized;  % Replace with normalized
                
                obj.logger.logDebug(sprintf('%s: Normalized conductance for %d wells', ivName, numWells));
            end
            
            extractedData.measurements = measurements;
            obj.logger.logInfo('✓ Conductance normalized (0-1 range)');
        end

        function filteredData = applyQualityFilters(obj, extractedData)
            %APPLYQUALITYFILTERS Apply MEDIAN-BASED filters with IV2 fallback
            %   ROBUST: Uses median across 23 sweeps (resistant to outliers)
            %   OPTIONAL: Checks if max is not wildly divergent from median
            
            obj.logger.logInfo('Applying quality filters (median-based, robust to outliers)...');
            
            measurements = extractedData.measurements;
            filters = obj.config.filters;
            numWells = extractedData.numWells;
            
            % Initialize quality assessment arrays
            qualityMask = false(numWells, 1);
            ivUsedForFiltering = strings(numWells, 1);
            
            % Get IV1 and IV2 data
            iv1Data = measurements.iv1;
            hasIV2 = isfield(measurements, 'iv2');
            if hasIV2
                iv2Data = measurements.iv2;
            else
                iv2Data = [];
            end
            
            % Apply filtering with IV2 fallback logic
            for wellIdx = 1:numWells
                [passed, ivUsed] = obj.assessWellQuality(iv1Data, iv2Data, wellIdx, filters, hasIV2);
                qualityMask(wellIdx) = passed;
                ivUsedForFiltering(wellIdx) = ivUsed;
            end
            
            % Create filter report
            filterReport = obj.createIVFallbackFilterReport(extractedData.wellIDs, measurements, ...
                qualityMask, ivUsedForFiltering, filters, hasIV2);
            
            % Apply mask to all measurements
            filteredMeasurements = obj.applyFilterMask(measurements, qualityMask);
            
            filteredData = struct(...
                'wellIDs', extractedData.wellIDs(qualityMask), ...
                'measurements', filteredMeasurements, ...
                'protocolInfo', extractedData.protocolInfo, ...
                'qualityMask', qualityMask, ...
                'ivUsedForFiltering', ivUsedForFiltering(qualityMask), ...
                'filterReport', filterReport, ...
                'numWellsPassed', sum(qualityMask), ...
                'numWellsTotal', length(qualityMask));
            
            % Log filtering results
            obj.logIVFallbackFilteringResults(filterReport, hasIV2);
        end
    end
    
    methods (Access = private)
        function wellIDs = extractWellIDs(obj, dataTable, ~)
            %EXTRACTWELLIDS Extract Well_ID values from first column
            %   FIXED: dataTable is already sliced, so start from row 1
            %   Note: Third parameter (dataStartRow) is ignored but kept for compatibility
            
            % dataTable is already positioned at the data rows (no headers)
            % Extract ALL rows from column 1
            wellColumn = dataTable{:, 1};
            wellIDs = string(wellColumn);
            
            % Filter out empty/missing well IDs
            validMask = ~ismissing(wellIDs) & wellIDs ~= "";
            wellIDs = wellIDs(validMask);
            
            obj.logger.logInfo(sprintf('Extracted %d well IDs', length(wellIDs)));
        end
        
        function measurements = extractByProtocol(obj, dataTable, protocolInfo, ~)
            %EXTRACTBYPROTOCOL Extract ALL sweep measurements by protocol type
            %   FIXED: dataTable is already sliced, so use it directly
            %   Note: Fourth parameter (dataStartRow) is ignored but kept for compatibility
            
            % dataTable is already positioned at the data section (no double-slicing)
            dataRows = dataTable;  % Use the table as-is
            
            switch protocolInfo.type
                case 'activation'
                    measurements = obj.extractActivationMeasurements(dataRows, protocolInfo);
                case 'inactivation'
                    measurements = obj.extractInactivationMeasurements(dataRows, protocolInfo);
                otherwise
                    error('NanionDataExtractor:UnknownProtocol', ...
                        'Unknown protocol type: %s', protocolInfo.type);
            end
            
            obj.logger.logInfo(sprintf('Extracted %s measurements', protocolInfo.type));
        end
        
        function measurements = extractActivationMeasurements(obj, dataRows, protocolInfo)
            %EXTRACTACTIVATIONMEASUREMENTS Extract ALL activation sweeps
            %   Column structure: Cols 1-3 = metadata, then every 6 columns per sweep
            %   First sweep: Cols 4-9 [Compound, Conc, SeriesR(6), SealR(7), Cap(8), Peak(9)]
            %   Returns [numWells × 23] arrays for all parameters
            
            columnMapping = protocolInfo.columnMapping;
            numIVs = protocolInfo.numIVs;
            numSweeps = protocolInfo.numSweeps;
            
            measurements = struct();
            
            for iv = 1:numIVs
                ivName = sprintf('iv%d', iv);
                
                % Calculate base column for this IV
                % IV1: baseCol = 3, IV2: baseCol = 3 + 23*6 = 141, etc.
                baseCol = 3 + (iv - 1) * (numSweeps * columnMapping.columnPattern);
                
                % Generate column arrays for all 23 sweeps
                % Series R at columns [6, 12, 18, ..., 138] for IV1
                seriesCols = baseCol + 3 + (0:(numSweeps-1)) * columnMapping.columnPattern;
                sealCols = baseCol + 4 + (0:(numSweeps-1)) * columnMapping.columnPattern;
                capCols = baseCol + 5 + (0:(numSweeps-1)) * columnMapping.columnPattern;
                peakCols = baseCol + 6 + (0:(numSweeps-1)) * columnMapping.columnPattern;
                
                % Extract ALL sweeps (returns [numWells × 23] arrays)
                measurements.(ivName) = struct(...
                    'seriesResistance', obj.extractMultipleColumns(dataRows, seriesCols, 'seriesR'), ...
                    'sealResistance', obj.extractMultipleColumns(dataRows, sealCols, 'sealR'), ...
                    'capacitance', obj.extractMultipleColumns(dataRows, capCols, 'capacitance'), ...
                    'peakCurrent', obj.extractMultipleColumns(dataRows, peakCols, 'current'));
                
                obj.logger.logDebug(sprintf('IV%d: Extracted %d sweeps, columns %d-%d', ...
                    iv, numSweeps, seriesCols(1), seriesCols(end)));
            end
        end
        
        function measurements = extractInactivationMeasurements(obj, dataRows, protocolInfo)
            %EXTRACTINACTIVATIONMEASUREMENTS Extract ALL inactivation sweeps
            %   Column structure: Every 7 columns per sweep
            %   First sweep: [Compound, Conc, SeriesR(6), SealR(7), Cap(8), Inact(9), Act(10)]
            %   Returns [numWells × 23] arrays
            
            columnMapping = protocolInfo.columnMapping;
            numIVs = protocolInfo.numIVs;
            numSweeps = protocolInfo.numSweeps;
            
            measurements = struct();
            
            for iv = 1:numIVs
                ivName = sprintf('iv%d', iv);
                
                % Base column for inactivation (7 columns per sweep)
                baseCol = 3 + (iv - 1) * (numSweeps * columnMapping.columnPattern);
                
                % Generate column arrays for all sweeps
                seriesCols = baseCol + 3 + (0:(numSweeps-1)) * columnMapping.columnPattern;
                sealCols = baseCol + 4 + (0:(numSweeps-1)) * columnMapping.columnPattern;
                capCols = baseCol + 5 + (0:(numSweeps-1)) * columnMapping.columnPattern;
                inactCols = baseCol + 6 + (0:(numSweeps-1)) * columnMapping.columnPattern;
                actCols = baseCol + 7 + (0:(numSweeps-1)) * columnMapping.columnPattern;
                
                % Extract ALL sweeps
                measurements.(ivName) = struct(...
                    'seriesResistance', obj.extractMultipleColumns(dataRows, seriesCols, 'seriesR'), ...
                    'sealResistance', obj.extractMultipleColumns(dataRows, sealCols, 'sealR'), ...
                    'capacitance', obj.extractMultipleColumns(dataRows, capCols, 'capacitance'), ...
                    'inactivationData', obj.extractMultipleColumns(dataRows, inactCols, 'current'), ...
                    'activationData', obj.extractMultipleColumns(dataRows, actCols, 'current'));
                
                obj.logger.logDebug(sprintf('IV%d: Extracted %d sweeps', iv, numSweeps));
            end
        end
        
        function dataArray = extractMultipleColumns(obj, dataRows, columnIndices, paramType)
            %EXTRACTMULTIPLECOLUMNS Extract multiple columns and return [numWells × numColumns] array
            %   NEW METHOD: Extracts all 23 sweeps per parameter
            
            numWells = height(dataRows);
            numCols = length(columnIndices);
            
            dataArray = NaN(numWells, numCols);
            
            for colIdx = 1:numCols
                col = columnIndices(colIdx);
                if col <= size(dataRows, 2)
                    rawData = dataRows{:, col};
                    numericData = obj.convertToNumeric(rawData);
                    dataArray(:, colIdx) = obj.applyUnitConversion(numericData, paramType);
                else
                    obj.logger.logWarning(sprintf('Column %d out of range, using NaN', col));
                end
            end
        end
        
        function values = extractAndConvert(obj, dataRows, columnIndex, paramType)
            %EXTRACTANDCONVERT Single column extraction (kept for compatibility)
            
            if columnIndex > size(dataRows, 2)
                obj.logger.logWarning(sprintf('Column %d not found, using NaN', columnIndex));
                values = NaN(height(dataRows), 1);
                return;
            end
            
            rawData = dataRows{:, columnIndex};
            numericData = obj.convertToNumeric(rawData);
            values = obj.applyUnitConversion(numericData, paramType);
        end
        
        function convertedData = applyUnitConversion(obj, rawData, paramType)
            %APPLYUNITCONVERSION Convert raw values to scientific units
            
            switch lower(paramType)
                case 'seriesr'
                    convertedData = rawData / 1e6;  % Ω → MΩ
                    
                case 'sealr'
                    convertedData = rawData / 1e9;  % Ω → GΩ
                    
                case 'capacitance'
                    if all(rawData == 0 | isnan(rawData), 'all')
                        obj.logger.logWarning('Capacitance values all zero/NaN');
                        convertedData = rawData;
                    else
                        convertedData = rawData * 1e12;  % F → pF
                    end
                    
                case 'current'
                    convertedData = rawData * 1e12;  % A → pA
                    
                otherwise
                    convertedData = rawData;
            end
        end
        
        function numericData = convertToNumeric(obj, rawData)
            %CONVERTTONUMERIC Convert cell array to numeric values
            
            if isnumeric(rawData)
                numericData = rawData;
                return;
            end
            
            numericData = NaN(size(rawData));
            
            for i = 1:numel(rawData)
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
            %ASSESSWELLQUALITY Robust median-based quality check with IV2 fallback
            %   Uses MEDIAN across 23 sweeps (resistant to outlier spikes)
            %   Optionally checks if max is wildly divergent from median
            
            % Get outlier threshold from config (default: 2.0 = max can be 2x median)
            if isfield(filters, 'outlierThreshold')
                outlierThreshold = filters.outlierThreshold;
            else
                outlierThreshold = 2.0;  % Default: max > 2 × median is considered outlier
            end
            
            % Extract ALL sweeps for this well from IV1 (1 × 23 arrays)
            iv1SeriesR = iv1Data.seriesResistance(wellIdx, :);
            iv1SealR = iv1Data.sealResistance(wellIdx, :);
            iv1Cap = iv1Data.capacitance(wellIdx, :);
            
            % Check if we have enough valid data (at least 15 of 23 sweeps)
            iv1SeriesRValid = sum(~isnan(iv1SeriesR));
            iv1SealRValid = sum(~isnan(iv1SealR));
            iv1CapValid = sum(~isnan(iv1Cap));
            
            minValidSweeps = 15;  % Require at least 15/23 valid sweeps
            iv1HasData = (iv1SeriesRValid >= minValidSweeps) && ...
                        (iv1SealRValid >= minValidSweeps) && ...
                        (iv1CapValid >= minValidSweeps);
            
            if iv1HasData
                % Calculate medians (robust to outliers)
                iv1SeriesRMedian = median(iv1SeriesR, 'omitnan');
                iv1SealRMedian = median(iv1SealR, 'omitnan');
                iv1CapMedian = median(iv1Cap, 'omitnan');
                
                % Main quality check: median must be below threshold
                medianPasses = (iv1SeriesRMedian <= filters.maxSeriesResistance) && ...
                              (iv1SealRMedian <= filters.maxSealResistance) && ...
                              (iv1CapMedian <= filters.maxCapacitance);
                
                if medianPasses
                    % Optional: Check if max is not wildly divergent
                    % (This catches systematic problems vs single spike artifacts)
                    iv1SeriesRMax = max(iv1SeriesR, [], 'omitnan');
                    iv1SealRMax = max(iv1SealR, [], 'omitnan');
                    iv1CapMax = max(iv1Cap, [], 'omitnan');
                    
                    % Fail if max is absurdly high (e.g., max > median × outlierThreshold)
                    outlierCheck = (iv1SeriesRMax <= iv1SeriesRMedian * outlierThreshold) && ...
                                  (iv1SealRMax <= iv1SealRMedian * outlierThreshold) && ...
                                  (iv1CapMax <= iv1CapMedian * outlierThreshold);
                    
                    if outlierCheck
                        passed = true;
                        ivUsed = 'iv1';
                        return;
                    end
                end
            end
            
            % Try IV2 fallback if available
            if hasIV2 && ~isempty(iv2Data)
                iv2SeriesR = iv2Data.seriesResistance(wellIdx, :);
                iv2SealR = iv2Data.sealResistance(wellIdx, :);
                iv2Cap = iv2Data.capacitance(wellIdx, :);
                
                iv2SeriesRValid = sum(~isnan(iv2SeriesR));
                iv2SealRValid = sum(~isnan(iv2SealR));
                iv2CapValid = sum(~isnan(iv2Cap));
                
                iv2HasData = (iv2SeriesRValid >= minValidSweeps) && ...
                            (iv2SealRValid >= minValidSweeps) && ...
                            (iv2CapValid >= minValidSweeps);
                
                if iv2HasData
                    iv2SeriesRMedian = median(iv2SeriesR, 'omitnan');
                    iv2SealRMedian = median(iv2SealR, 'omitnan');
                    iv2CapMedian = median(iv2Cap, 'omitnan');
                    
                    medianPasses = (iv2SeriesRMedian <= filters.maxSeriesResistance) && ...
                                  (iv2SealRMedian <= filters.maxSealResistance) && ...
                                  (iv2CapMedian <= filters.maxCapacitance);
                    
                    if medianPasses
                        iv2SeriesRMax = max(iv2SeriesR, [], 'omitnan');
                        iv2SealRMax = max(iv2SealR, [], 'omitnan');
                        iv2CapMax = max(iv2Cap, [], 'omitnan');
                        
                        outlierCheck = (iv2SeriesRMax <= iv2SeriesRMedian * outlierThreshold) && ...
                                      (iv2SealRMax <= iv2SealRMedian * outlierThreshold) && ...
                                      (iv2CapMax <= iv2CapMedian * outlierThreshold);
                        
                        if outlierCheck
                            passed = true;
                            ivUsed = 'iv2';
                            return;
                        end
                    end
                end
            end
            
            % Both IVs failed
            passed = false;
            if iv1HasData
                ivUsed = 'iv1_threshold_fail';
            elseif hasIV2 && ~isempty(iv2Data) && sum(~isnan(iv2Data.seriesResistance(wellIdx, :))) >= minValidSweeps
                ivUsed = 'iv2_threshold_fail';
            else
                ivUsed = 'insufficient_data';
            end
        end
        
        function filterReport = createIVFallbackFilterReport(obj, wellIDs, measurements, ...
                qualityMask, ivUsedForFiltering, filters, hasIV2)
            %CREATEIVFALLBACKFILTERREPORT Generate filter report for median-based filtering
            
            numWells = length(wellIDs);
            iv1Data = measurements.iv1;
            
            % Count IV usage
            iv1Used = sum(ivUsedForFiltering == "iv1");
            if hasIV2
                iv2Used = sum(ivUsedForFiltering == "iv2");
            else
                iv2Used = 0;
            end
            
            % Calculate statistics for reporting (using median-based approach)
            minValidSweeps = 15;
            
            % Count wells with insufficient data
            iv1SeriesRInsufficient = sum(sum(~isnan(iv1Data.seriesResistance), 2) < minValidSweeps);
            iv1SealRInsufficient = sum(sum(~isnan(iv1Data.sealResistance), 2) < minValidSweeps);
            iv1CapInsufficient = sum(sum(~isnan(iv1Data.capacitance), 2) < minValidSweeps);
            
            % Count wells where median exceeds threshold
            iv1SeriesRMedians = median(iv1Data.seriesResistance, 2, 'omitnan');
            iv1SealRMedians = median(iv1Data.sealResistance, 2, 'omitnan');
            iv1CapMedians = median(iv1Data.capacitance, 2, 'omitnan');
            
            iv1SeriesRMedianFail = sum(iv1SeriesRMedians > filters.maxSeriesResistance);
            iv1SealRMedianFail = sum(iv1SealRMedians > filters.maxSealResistance);
            iv1CapMedianFail = sum(iv1CapMedians > filters.maxCapacitance);
            
            % Count wells with valid data
            iv1SeriesRValid = sum(sum(~isnan(iv1Data.seriesResistance), 2) >= minValidSweeps);
            iv1SealRValid = sum(sum(~isnan(iv1Data.sealResistance), 2) >= minValidSweeps);
            iv1CapValid = sum(sum(~isnan(iv1Data.capacitance), 2) >= minValidSweeps);
            
            filterReport = struct(...
                'totalWells', numWells, ...
                'passedWells', sum(qualityMask), ...
                'failedWells', sum(~qualityMask), ...
                'ivUsage', struct(...
                    'iv1Used', iv1Used, ...
                    'iv2Used', iv2Used, ...
                    'iv2Available', hasIV2), ...
                'insufficientData', struct(...
                    'seriesR', struct('count', iv1SeriesRInsufficient), ...
                    'sealR', struct('count', iv1SealRInsufficient), ...
                    'capacitance', struct('count', iv1CapInsufficient)), ...
                'medianThresholdFailures', struct(...
                    'seriesR', struct('count', iv1SeriesRMedianFail, 'threshold', filters.maxSeriesResistance), ...
                    'sealR', struct('count', iv1SealRMedianFail, 'threshold', filters.maxSealResistance), ...
                    'capacitance', struct('count', iv1CapMedianFail, 'threshold', filters.maxCapacitance)), ...
                'validDataCounts', struct(...
                    'seriesR', iv1SeriesRValid, ...
                    'sealR', iv1SealRValid, ...
                    'capacitance', iv1CapValid));
        end
        
        function logIVFallbackFilteringResults(obj, filterReport, hasIV2)
            %LOGIVFALLBACKFILTERINGRESULTS Log filtering results
            
            obj.logger.logInfo(sprintf('✓ Quality filtering: %d/%d wells passed (%.1f%%)', ...
                filterReport.passedWells, filterReport.totalWells, ...
                100 * filterReport.passedWells / filterReport.totalWells));
            
            if hasIV2
                obj.logger.logInfo('--- IV Usage for Quality Assessment ---');
                obj.logger.logInfo(sprintf('IV1 used: %d wells (%.1f%%)', ...
                    filterReport.ivUsage.iv1Used, ...
                    100 * filterReport.ivUsage.iv1Used / filterReport.totalWells));
                obj.logger.logInfo(sprintf('IV2 fallback: %d wells (%.1f%%)', ...
                    filterReport.ivUsage.iv2Used, ...
                    100 * filterReport.ivUsage.iv2Used / filterReport.totalWells));
            end
            
            obj.logger.logInfo('--- Insufficient Data (<15 valid sweeps) ---');
            obj.logger.logInfo(sprintf('Series R: %d wells', filterReport.insufficientData.seriesR.count));
            obj.logger.logInfo(sprintf('Seal R: %d wells', filterReport.insufficientData.sealR.count));
            obj.logger.logInfo(sprintf('Capacitance: %d wells', filterReport.insufficientData.capacitance.count));
            
            obj.logger.logInfo('--- Median Threshold Exceedances ---');
            obj.logger.logInfo(sprintf('Series R median > %.1f MΩ: %d/%d wells', ...
                filterReport.medianThresholdFailures.seriesR.threshold, ...
                filterReport.medianThresholdFailures.seriesR.count, ...
                filterReport.validDataCounts.seriesR));
            obj.logger.logInfo(sprintf('Seal R median > %.1f GΩ: %d/%d wells', ...
                filterReport.medianThresholdFailures.sealR.threshold, ...
                filterReport.medianThresholdFailures.sealR.count, ...
                filterReport.validDataCounts.sealR));
            obj.logger.logInfo(sprintf('Capacitance median > %.1f pF: %d/%d wells', ...
                filterReport.medianThresholdFailures.capacitance.threshold, ...
                filterReport.medianThresholdFailures.capacitance.count, ...
                filterReport.validDataCounts.capacitance));
        end
        
        function filteredMeasurements = applyFilterMask(obj, measurements, qualityMask)
            %APPLYFILTERMASK Apply quality mask to all IVs
            %   UPDATED: Handles [wells × 23] arrays
            
            filteredMeasurements = struct();
            ivFields = fieldnames(measurements);
            
            for i = 1:length(ivFields)
                ivName = ivFields{i};
                ivData = measurements.(ivName);
                
                paramFields = fieldnames(ivData);
                for j = 1:length(paramFields)
                    paramName = paramFields{j};
                    % Apply mask to rows (first dimension)
                    filteredMeasurements.(ivName).(paramName) = ivData.(paramName)(qualityMask, :);
                end
            end
        end
    end
end
