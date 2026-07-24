classdef NanionDataExtractor < handle
    %NANIONDATAEXTRACTOR Extract electrophysiology measurements from parsed data
    %   UPDATED: Added current density, sweep statistics, and metadata extraction
    
    properties (Access = private)
        config
        logger
    end
    
    methods
        function obj = NanionDataExtractor(config, logger)
            obj.config = config;
            obj.logger = logger;
        end
        
        function extractedData = extractMeasurements(obj, parsedData)
            %EXTRACTMEASUREMENTS Extract ALL sweep measurements from parsed table
            %   NOW INCLUDES: Current density and metadata extraction
            
            dataTable = parsedData.dataTable;
            protocolInfo = parsedData.protocolInfo;
            dataStartRow = parsedData.headerInfo.dataStartRow;
            
            obj.logger.logInfo('Extracting ALL sweeps from parsed data...');
            
            try
                % Extract Well IDs
                wellIDs = obj.extractWellIDs(dataTable, dataStartRow);
                
                % Extract well-level metadata (Cell Type, Cell Concentration)
                wellMetadata = obj.extractWellMetadata(dataTable);
                
                % Extract measurements (ALL sweeps per IV)
                measurements = obj.extractByProtocol(dataTable, protocolInfo, dataStartRow);
                
                % Package extracted data
                extractedData = struct(...
                    'wellIDs', wellIDs, ...
                    'wellMetadata', wellMetadata, ...
                    'measurements', measurements, ...
                    'protocolInfo', protocolInfo, ...
                    'fileName', parsedData.fileName, ...
                    'numWells', length(wellIDs), ...
                    'numIVs', protocolInfo.numIVs, ...
                    'numSweeps', protocolInfo.numSweeps);
                
                obj.logger.logInfo(sprintf('✓ Extracted: %d wells × %d sweeps × %d IVs', ...
                    extractedData.numWells, extractedData.numSweeps, extractedData.numIVs));
                                
                % Calculate conductance for activation protocols
                if strcmp(protocolInfo.type, 'activation')
                    extractedData = obj.calculateConductance(extractedData);
                    extractedData = obj.filterNegativeConductance(extractedData);  % Just the filter
                    extractedData = obj.normalizeConductance(extractedData);
                end
                                
                % Calculate current density (for ALL protocols)
                extractedData = obj.calculateCurrentDensity(extractedData);
                
                % Extract IV-level metadata (Compound, Concentration)
                extractedData = obj.extractConditions(extractedData, dataTable);
                
            catch ME
                obj.logger.logError(sprintf('Measurement extraction failed: %s', ME.message));
                rethrow(ME);
            end
        end

        function extractedData = calculateCurrentDensity(obj, extractedData)
            %CALCULATECURRENTDENSITY Calculate sweep-by-sweep current density
            %   Activation: Density = peakCurrent / Capacitance
            %   Inactivation: Density = inactivationData / Capacitance
            
            obj.logger.logInfo('Calculating current density (I/C)...');
            
            protocolType = extractedData.protocolInfo.type;
            measurements = extractedData.measurements;
            ivFields = fieldnames(measurements);
            
            for i = 1:length(ivFields)
                ivName = ivFields{i};
                ivData = measurements.(ivName);
                capacitance = ivData.capacitance;  % pF
                
                % Select appropriate current data based on protocol
                if strcmp(protocolType, 'activation')
                    currentData = ivData.peakCurrent;  % pA
                elseif strcmp(protocolType, 'inactivation')
                    currentData = ivData.inactivationData;  % pA
                else
                    error('Unknown protocol type: %s', protocolType);
                end
                
                % Calculate density: I / C (element-wise division)
                currentDensity = currentData ./ capacitance;  % [numWells × 23] in pA/pF
                
                % Handle division by zero/NaN
                currentDensity(isinf(currentDensity) | isnan(capacitance) | capacitance <= 0) = NaN;
                
                % Store current density
                measurements.(ivName).currentDensity = currentDensity;  % pA/pF
                
                obj.logger.logDebug(sprintf('%s: Calculated current density (I/C)', ivName));
            end
            
            extractedData.measurements = measurements;
            obj.logger.logInfo('✓ Current density calculated');
        end

        function extractedData = calculateConductance(obj, extractedData)
            %CALCULATECONDUCTANCE Calculate conductance for activation protocols
            
            if ~strcmp(extractedData.protocolInfo.type, 'activation')
                return;
            end
            
            obj.logger.logInfo('Calculating conductance (G = I / (V - E_rev))...');
            
            voltages = extractedData.protocolInfo.voltages;
            V_rev = obj.config.nernstPotential;
            drivingForce = voltages - V_rev;
            
            measurements = extractedData.measurements;
            ivFields = fieldnames(measurements);
            
            for i = 1:length(ivFields)
                ivName = ivFields{i};
                peakCurrent = measurements.(ivName).peakCurrent;
                conductance = peakCurrent ./ drivingForce;
                conductance(isinf(conductance)) = NaN;
                measurements.(ivName).conductance = conductance;
                
                obj.logger.logDebug(sprintf('%s: Calculated conductance', ivName));
            end
            
            extractedData.measurements = measurements;
            obj.logger.logInfo('✓ Conductance calculated');
        end

        function extractedData = normalizeConductance(obj, extractedData)
            %NORMALIZECONDUCTANCE Normalize conductance using VOLTAGE-BASED endpoints
            %   For activation: G at most negative V → 0, G at most positive V → 1
            %   This prevents inversion artifacts from min/max normalization
            
            if ~strcmp(extractedData.protocolInfo.type, 'activation')
                return;
            end
            
            obj.logger.logInfo('Normalizing conductance (voltage-based endpoints)...');
            
            measurements = extractedData.measurements;
            ivFields = fieldnames(measurements);
            
            for i = 1:length(ivFields)
                ivName = ivFields{i};
                conductance_raw = measurements.(ivName).conductance;
                numWells = size(conductance_raw, 1);
                numVoltages = size(conductance_raw, 2);
                conductance_normalized = zeros(size(conductance_raw));
                
                for wellIdx = 1:numWells
                    G = conductance_raw(wellIdx, :);
                    
                    % Use conductance at EXTREME VOLTAGES (not min/max)
                    % Assumes voltages are sorted: [most negative ... most positive]
                    G_at_min_voltage = G(1);        % Should be low for activation
                    G_at_max_voltage = G(end);      % Should be high for activation
                    
                    % Check if we have valid data at endpoints
                    if isnan(G_at_min_voltage) || isnan(G_at_max_voltage)
                        % Fallback: use first/last non-NaN values
                        validIdx = find(~isnan(G));
                        if length(validIdx) >= 2
                            G_at_min_voltage = G(validIdx(1));
                            G_at_max_voltage = G(validIdx(end));
                        else
                            % Insufficient data - store NaNs
                            conductance_normalized(wellIdx, :) = NaN(size(G));
                            obj.logger.logWarning(sprintf('%s Well %d: Insufficient valid conductance data', ...
                                ivName, wellIdx));
                            continue;
                        end
                    end
                    
                    % Normalize: (G - G_baseline) / (G_max - G_baseline)
                    G_range = G_at_max_voltage - G_at_min_voltage;
                    
                    if abs(G_range) > 1e-12  % Avoid division by zero
                        conductance_normalized(wellIdx, :) = (G - G_at_min_voltage) / G_range;
                        
                        % DIAGNOSTIC: Check if normalization looks inverted
                        if conductance_normalized(wellIdx, 1) > 0.5 && ...
                           conductance_normalized(wellIdx, end) < 0.5
                            obj.logger.logWarning(sprintf(['%s Well %d: Normalized curve appears INVERTED ' ...
                                '(starts high, ends low). Check raw conductance calculation!'], ivName, wellIdx));
                        end
                    else
                        % Flat conductance curve (no activation)
                        conductance_normalized(wellIdx, :) = 0.5 * ones(size(G));
                        obj.logger.logDebug(sprintf('%s Well %d: Flat conductance (G_range ≈ 0)', ...
                            ivName, wellIdx));
                    end
                end
                
                % Store BOTH raw and normalized
                measurements.(ivName).conductance_raw = conductance_raw;
                measurements.(ivName).conductance = conductance_normalized;
                
                obj.logger.logDebug(sprintf('%s: Normalized %d wells using voltage-based endpoints', ...
                    ivName, numWells));
            end
            
            extractedData.measurements = measurements;
            obj.logger.logInfo('✓ Conductance normalized (voltage-based method)');
        end

        function filteredData = applyQualityFilters(obj, extractedData)
            %APPLYQUALITYFILTERS Assess every well, then drop those failing auto-QC.
            %   Thin wrapper preserving the original behaviour: it composes the
            %   new assess/apply split using the automatic verdicts. The review
            %   workflow instead calls assessQuality, lets the user override the
            %   verdicts, then calls applyDecisions with the final keep mask.

            assessedData = obj.assessQuality(extractedData);
            filteredData = obj.applyDecisions(assessedData, assessedData.autoKeepMask);
        end

        function assessedData = assessQuality(obj, extractedData)
            %ASSESSQUALITY Annotate EVERY well with a QC verdict + reasons; discard nothing.
            %   Returns extractedData augmented with:
            %     .verdicts            [numWells x 1] struct (wellID, autoPass, reasons, ivUsed, metrics)
            %     .autoKeepMask        logical [numWells x 1] (true = auto-pass)
            %     .ivUsedForFiltering  string  [numWells x 1]

            obj.logger.logInfo('Assessing well quality (annotating all wells, discarding none)...');

            measurements = extractedData.measurements;
            filters = obj.config.filters;
            numWells = extractedData.numWells;

            iv1Data = measurements.iv1;
            hasIV2 = isfield(measurements, 'iv2');
            if hasIV2
                iv2Data = measurements.iv2;
            else
                iv2Data = [];
            end

            autoKeepMask = false(numWells, 1);
            ivUsedForFiltering = strings(numWells, 1);
            verdicts = repmat(obj.emptyVerdict(), numWells, 1);

            for wellIdx = 1:numWells
                a = obj.assessWellQuality(iv1Data, iv2Data, wellIdx, filters, hasIV2);
                autoKeepMask(wellIdx) = a.passed;
                ivUsedForFiltering(wellIdx) = string(a.ivUsed);

                v = obj.emptyVerdict();
                v.wellID = string(extractedData.wellIDs(wellIdx));
                v.fileName = string(extractedData.fileName);
                v.wellKey = v.fileName + "::" + v.wellID;
                v.autoPass = a.passed;
                if a.passed
                    v.autoVerdict = "pass";
                else
                    v.autoVerdict = "fail";
                end
                v.reasons = a.reasons;
                v.ivUsed = string(a.ivUsed);
                v.metrics = a.metrics;
                verdicts(wellIdx) = v;
            end

            assessedData = extractedData;
            assessedData.verdicts = verdicts;
            assessedData.autoKeepMask = autoKeepMask;
            assessedData.ivUsedForFiltering = ivUsedForFiltering;

            obj.logger.logInfo(sprintf('✓ Assessed %d wells: %d auto-pass, %d auto-fail', ...
                numWells, sum(autoKeepMask), sum(~autoKeepMask)));
        end

        function filteredData = applyDecisions(obj, assessedData, keepMask)
            %APPLYDECISIONS Drop wells not in keepMask; return filtered data (pipeline shape).
            %   keepMask defaults to the automatic verdicts when omitted, so the
            %   result matches the legacy applyQualityFilters output. The full
            %   verdict list (including rejected wells) is carried through so the
            %   review app can still show and re-include rejected wells.

            if nargin < 3 || isempty(keepMask)
                keepMask = assessedData.autoKeepMask;
            end
            keepMask = logical(keepMask(:));

            measurements = assessedData.measurements;
            filters = obj.config.filters;
            hasIV2 = isfield(measurements, 'iv2');

            filteredMeasurements = obj.applyFilterMask(measurements, keepMask);

            filterReport = obj.createIVFallbackFilterReport(assessedData.wellIDs, measurements, ...
                keepMask, assessedData.ivUsedForFiltering, filters, hasIV2);

            % Add negative conductance filter info to report (if it was applied)
            if isfield(assessedData, 'negativeConductanceFilter')
                filterReport.negativeConductanceFiltered = assessedData.negativeConductanceFilter.numFiltered;
            else
                filterReport.negativeConductanceFiltered = 0;
            end

            filteredData = struct(...
                'wellIDs', assessedData.wellIDs(keepMask), ...
                'wellMetadata', struct(...
                    'cellType', assessedData.wellMetadata.cellType(keepMask), ...
                    'cellConcentration', assessedData.wellMetadata.cellConcentration(keepMask)), ...
                'measurements', filteredMeasurements, ...
                'protocolInfo', assessedData.protocolInfo, ...
                'fileName', assessedData.fileName, ...
                'qualityMask', keepMask, ...
                'ivUsedForFiltering', assessedData.ivUsedForFiltering(keepMask), ...
                'filterReport', filterReport, ...
                'numWellsPassed', sum(keepMask), ...
                'numWellsTotal', numel(keepMask), ...
                'verdicts', {assessedData.verdicts}, ...
                'keptVerdicts', {assessedData.verdicts(keepMask)});

            obj.logIVFallbackFilteringResults(filterReport, hasIV2);
        end

        function filteredData = calculateSweepStatistics(obj, filteredData)
            %CALCULATESWEEPSTATISTICS Calculate statistics across 23 sweeps for each well, each IV
            %   Computes mean/min/max/std for all measurements
            
            obj.logger.logInfo('Calculating sweep statistics (mean/min/max/std across 23 sweeps)...');
            
            measurements = filteredData.measurements;
            ivFields = fieldnames(measurements);
            protocolType = filteredData.protocolInfo.type;
            
            for i = 1:length(ivFields)
                ivName = ivFields{i};
                ivData = measurements.(ivName);
                
                stats = struct();
                
                % Quality metrics (across 23 sweeps)
                stats.seriesR = obj.computeStats(ivData.seriesResistance);
                stats.sealR = obj.computeStats(ivData.sealResistance);
                stats.capacitance = obj.computeStats(ivData.capacitance);
                
                % Current metrics - protocol-specific
                if strcmp(protocolType, 'activation')
                    stats.peakCurrent = obj.computeStats(ivData.peakCurrent);
                elseif strcmp(protocolType, 'inactivation')
                    stats.inactivationData = obj.computeStats(ivData.inactivationData);
                    stats.activationData = obj.computeStats(ivData.activationData);
                end
                
                % Current density (for all protocols)
                stats.currentDensity = obj.computeStats(ivData.currentDensity);
                
                % Raw conductance (activation only)
                if strcmp(protocolType, 'activation') && isfield(ivData, 'conductance_raw')
                    stats.conductance_raw = obj.computeStats(ivData.conductance_raw);
                end
                
                % Store statistics
                measurements.(ivName).statistics = stats;
                
                obj.logger.logDebug(sprintf('%s: Computed statistics for %d wells', ...
                    ivName, size(ivData.seriesResistance, 1)));
            end
            
            filteredData.measurements = measurements;
            obj.logger.logInfo('✓ Sweep statistics calculated');
        end
    end
    
    methods (Access = private)
        function stats = computeStats(obj, data)
            %COMPUTESTATS Compute mean/min/max/std across columns (23 sweeps)
            %   data: [numWells × 23]
            %   Returns: struct with [numWells × 1] arrays
            
            stats = struct(...
                'mean', mean(data, 2, 'omitnan'), ...
                'min', min(data, [], 2, 'omitnan'), ...
                'max', max(data, [], 2, 'omitnan'), ...
                'std', std(data, 0, 2, 'omitnan'));
        end

        function wellMetadata = extractWellMetadata(obj, dataTable)
            %EXTRACTWELLMETADATA Extract well-level metadata (Cell Type, Cell Concentration)
            %   These appear ONCE per well in columns 2-3
            
            numWells = height(dataTable);
            
            % Column 2: Cell Type
            if size(dataTable, 2) >= 2
                rawCellType = dataTable{:, 2};
                cellType = obj.convertToString(rawCellType);
            else
                obj.logger.logWarning('Cell Type column (2) not found');
                cellType = repmat("", numWells, 1);
            end
            
            % Column 3: Cell Concentration
            if size(dataTable, 2) >= 3
                rawCellConc = dataTable{:, 3};
                cellConcentration = obj.convertToString(rawCellConc);
            else
                obj.logger.logWarning('Cell Concentration column (3) not found');
                cellConcentration = repmat("", numWells, 1);
            end
            
            wellMetadata = struct(...
                'cellType', cellType, ...
                'cellConcentration', cellConcentration);
            
            obj.logger.logDebug(sprintf('Extracted well metadata: %d unique cell types', ...
                length(unique(cellType))));
        end

        function extractedData = extractConditions(obj, extractedData, dataTable)
            %EXTRACTCONDITIONS Extract IV-level metadata (Compound, Concentration)
            %   These appear in the FIRST SWEEP of each IV
            
            obj.logger.logInfo('Extracting Compound and Concentration metadata per IV...');
            
            protocolInfo = extractedData.protocolInfo;
            columnMapping = protocolInfo.columnMapping;
            numIVs = protocolInfo.numIVs;
            numSweeps = protocolInfo.numSweeps;
            numWells = extractedData.numWells;
            measurements = extractedData.measurements;
            
            for iv = 1:numIVs
                ivName = sprintf('iv%d', iv);
                
                % Calculate base column for this IV (sweep 1)
                baseCol = 3 + (iv - 1) * (numSweeps * columnMapping.columnPattern);
                
                % Metadata columns in first sweep: baseCol + 1, baseCol + 2
                compoundCol = baseCol + 1;
                concentrationCol = baseCol + 2;
                
                % Extract Compound (string)
                if compoundCol <= size(dataTable, 2)
                    rawCompound = dataTable{:, compoundCol};
                    compound = obj.convertToString(rawCompound);
                else
                    obj.logger.logWarning(sprintf('%s: Compound column %d not found', ivName, compoundCol));
                    compound = repmat("", numWells, 1);
                end
                
                % Extract Concentration (numeric, µM)
                if concentrationCol <= size(dataTable, 2)
                    rawConc = dataTable{:, concentrationCol};
                    concentration = obj.convertToNumeric(rawConc);
                else
                    obj.logger.logWarning(sprintf('%s: Concentration column %d not found', ivName, concentrationCol));
                    concentration = NaN(numWells, 1);
                end
                
                % Store in measurements structure
                measurements.(ivName).compound = compound;
                measurements.(ivName).concentration = concentration;
                
                obj.logger.logDebug(sprintf('%s: Extracted metadata (columns %d,%d)', ...
                    ivName, compoundCol, concentrationCol));
            end
            
            extractedData.measurements = measurements;
            obj.logger.logInfo('✓ Compound and Concentration extracted per IV');
        end

        function strArray = convertToString(obj, rawData)
            %CONVERTTOSTRING Convert cell array to string array
            
            if isstring(rawData)
                strArray = rawData;
                return;
            end
            
            strArray = strings(size(rawData));
            
            for i = 1:numel(rawData)
                if ischar(rawData{i}) || isstring(rawData{i})
                    strArray(i) = string(rawData{i});
                elseif isnumeric(rawData{i})
                    strArray(i) = string(num2str(rawData{i}));
                else
                    strArray(i) = "";
                end
            end
            
            strArray(ismissing(strArray)) = "";
        end

        function wellIDs = extractWellIDs(obj, dataTable, ~)
            %EXTRACTWELLIDS Extract Well_ID values from first column
            
            wellColumn = dataTable{:, 1};
            wellIDs = string(wellColumn);
            validMask = ~ismissing(wellIDs) & wellIDs ~= "";
            wellIDs = wellIDs(validMask);
            
            obj.logger.logInfo(sprintf('Extracted %d well IDs', length(wellIDs)));
        end
        
        function measurements = extractByProtocol(obj, dataTable, protocolInfo, ~)
            %EXTRACTBYPROTOCOL Extract ALL sweep measurements by protocol type
            
            dataRows = dataTable;
            
            switch protocolInfo.type
                case 'activation'
                    measurements = obj.extractActivationMeasurements(dataRows, protocolInfo);
                case 'inactivation'
                    measurements = obj.extractInactivationMeasurements(dataRows, protocolInfo);
                otherwise
                    error('NanionDataExtractor:UnknownProtocol', 'Unknown protocol: %s', protocolInfo.type);
            end
        end
        
        function measurements = extractActivationMeasurements(obj, dataRows, protocolInfo)
            %EXTRACTACTIVATIONMEASUREMENTS Extract ALL activation sweeps
            
            columnMapping = protocolInfo.columnMapping;
            numIVs = protocolInfo.numIVs;
            numSweeps = protocolInfo.numSweeps;
            
            measurements = struct();
            
            for iv = 1:numIVs
                ivName = sprintf('iv%d', iv);
                baseCol = 3 + (iv - 1) * (numSweeps * columnMapping.columnPattern);
                
                seriesCols = baseCol + 3 + (0:(numSweeps-1)) * columnMapping.columnPattern;
                sealCols = baseCol + 4 + (0:(numSweeps-1)) * columnMapping.columnPattern;
                capCols = baseCol + 5 + (0:(numSweeps-1)) * columnMapping.columnPattern;
                peakCols = baseCol + 6 + (0:(numSweeps-1)) * columnMapping.columnPattern;
                
                measurements.(ivName) = struct(...
                    'seriesResistance', obj.extractMultipleColumns(dataRows, seriesCols, 'seriesR'), ...
                    'sealResistance', obj.extractMultipleColumns(dataRows, sealCols, 'sealR'), ...
                    'capacitance', obj.extractMultipleColumns(dataRows, capCols, 'capacitance'), ...
                    'peakCurrent', obj.extractMultipleColumns(dataRows, peakCols, 'current'));
            end
        end
        
        function measurements = extractInactivationMeasurements(obj, dataRows, protocolInfo)
            %EXTRACTINACTIVATIONMEASUREMENTS Extract ALL inactivation sweeps
            
            columnMapping = protocolInfo.columnMapping;
            numIVs = protocolInfo.numIVs;
            numSweeps = protocolInfo.numSweeps;
            
            measurements = struct();
            
            for iv = 1:numIVs
                ivName = sprintf('iv%d', iv);
                baseCol = 3 + (iv - 1) * (numSweeps * columnMapping.columnPattern);
                
                seriesCols = baseCol + 3 + (0:(numSweeps-1)) * columnMapping.columnPattern;
                sealCols = baseCol + 4 + (0:(numSweeps-1)) * columnMapping.columnPattern;
                capCols = baseCol + 5 + (0:(numSweeps-1)) * columnMapping.columnPattern;
                inactCols = baseCol + 6 + (0:(numSweeps-1)) * columnMapping.columnPattern;
                actCols = baseCol + 7 + (0:(numSweeps-1)) * columnMapping.columnPattern;
                
                measurements.(ivName) = struct(...
                    'seriesResistance', obj.extractMultipleColumns(dataRows, seriesCols, 'seriesR'), ...
                    'sealResistance', obj.extractMultipleColumns(dataRows, sealCols, 'sealR'), ...
                    'capacitance', obj.extractMultipleColumns(dataRows, capCols, 'capacitance'), ...
                    'inactivationData', obj.extractMultipleColumns(dataRows, inactCols, 'current'), ...
                    'activationData', obj.extractMultipleColumns(dataRows, actCols, 'current'));
            end
        end
        
        function dataArray = extractMultipleColumns(obj, dataRows, columnIndices, paramType)
            %EXTRACTMULTIPLECOLUMNS Extract multiple columns
            
            numWells = height(dataRows);
            numCols = length(columnIndices);
            dataArray = NaN(numWells, numCols);
            
            for colIdx = 1:numCols
                col = columnIndices(colIdx);
                if col <= size(dataRows, 2)
                    rawData = dataRows{:, col};
                    numericData = obj.convertToNumeric(rawData);
                    dataArray(:, colIdx) = obj.applyUnitConversion(numericData, paramType);
                end
            end
        end
        
        function convertedData = applyUnitConversion(obj, rawData, paramType)
            %APPLYUNITCONVERSION Convert raw values to scientific units
            
            switch lower(paramType)
                case 'seriesr'
                    convertedData = rawData / 1e6;
                case 'sealr'
                    convertedData = rawData / 1e9;
                case 'capacitance'
                    convertedData = rawData * 1e12;
                case 'current'
                    convertedData = rawData * 1e12;
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
        
        function assessment = assessWellQuality(obj, iv1Data, iv2Data, wellIdx, filters, hasIV2)
            %ASSESSWELLQUALITY Robust median-based quality check with reasons.
            %   Returns a struct: passed (logical), ivUsed (char), reasons (cellstr),
            %   metrics (struct of the key values, for display in the review app).
            %   Same pass/fail outcome as before; now also reports WHY a well failed.

            if isfield(filters, 'outlierThreshold')
                outlierThreshold = filters.outlierThreshold;
            else
                outlierThreshold = 2.0;
            end

            metrics = struct('iv1PeakDensity', NaN, ...
                             'seriesRMedian', NaN, 'sealRMedian', NaN, 'capMedian', NaN);

            % Signal gate (IV1-referenced): reject leak-only wells with no functional
            % current. A smooth leak ramp still fits a sigmoid (R2~0.9, V_mid~0), so
            % without this it would clear every other filter.
            if isfield(iv1Data, 'currentDensity')
                metrics.iv1PeakDensity = max(-iv1Data.currentDensity(wellIdx, :), [], 'omitnan');
            end
            if isfield(filters, 'minCurrentDensity') && ...
               (isnan(metrics.iv1PeakDensity) || metrics.iv1PeakDensity < filters.minCurrentDensity)
                assessment = struct('passed', false, 'ivUsed', 'low_signal', ...
                    'reasons', {{'low_signal'}}, 'metrics', metrics);
                return;
            end

            % Rs / seal / cap quality on IV1 (with IV2 fallback)
            [iv1ok, iv1reasons, iv1metrics] = obj.checkQualityBlock(iv1Data, wellIdx, filters, outlierThreshold);
            metrics.seriesRMedian = iv1metrics.seriesRMedian;
            metrics.sealRMedian = iv1metrics.sealRMedian;
            metrics.capMedian = iv1metrics.capMedian;
            if iv1ok
                assessment = struct('passed', true, 'ivUsed', 'iv1', 'reasons', {{}}, 'metrics', metrics);
                return;
            end

            if hasIV2 && ~isempty(iv2Data)
                iv2ok = obj.checkQualityBlock(iv2Data, wellIdx, filters, outlierThreshold);
                if iv2ok
                    assessment = struct('passed', true, 'ivUsed', 'iv2', 'reasons', {{}}, 'metrics', metrics);
                    return;
                end
            end

            assessment = struct('passed', false, 'ivUsed', 'insufficient_data', ...
                'reasons', {iv1reasons}, 'metrics', metrics);
        end

        function [ok, reasons, metrics] = checkQualityBlock(obj, ivData, wellIdx, filters, outlierThreshold) %#ok<INUSL>
            %CHECKQUALITYBLOCK Median + outlier Rs/seal/cap check for one IV of one well.
            %   Returns ok (logical), reasons (cellstr of specific failures), metrics.

            seriesR = ivData.seriesResistance(wellIdx, :);
            sealR = ivData.sealResistance(wellIdx, :);
            cap = ivData.capacitance(wellIdx, :);
            minValidSweeps = 15;

            metrics = struct('seriesRMedian', median(seriesR, 'omitnan'), ...
                             'sealRMedian', median(sealR, 'omitnan'), ...
                             'capMedian', median(cap, 'omitnan'));
            reasons = {};

            hasData = (sum(~isnan(seriesR)) >= minValidSweeps) && ...
                      (sum(~isnan(sealR)) >= minValidSweeps) && ...
                      (sum(~isnan(cap)) >= minValidSweeps);
            if ~hasData
                ok = false; reasons = {'insufficient_valid_sweeps'}; return;
            end

            if metrics.seriesRMedian > filters.maxSeriesResistance; reasons{end+1} = 'high_series_resistance'; end
            if metrics.sealRMedian > filters.maxSealResistance;   reasons{end+1} = 'high_seal_resistance'; end
            if metrics.capMedian > filters.maxCapacitance;        reasons{end+1} = 'high_capacitance'; end
            if ~isempty(reasons); ok = false; return; end

            if max(seriesR, [], 'omitnan') > metrics.seriesRMedian * outlierThreshold; reasons{end+1} = 'unstable_series_resistance'; end
            if max(sealR, [], 'omitnan')   > metrics.sealRMedian * outlierThreshold;   reasons{end+1} = 'unstable_seal_resistance'; end
            if max(cap, [], 'omitnan')     > metrics.capMedian * outlierThreshold;     reasons{end+1} = 'unstable_capacitance'; end
            ok = isempty(reasons);
        end

        function v = emptyVerdict(~)
            %EMPTYVERDICT Template for a per-well QC verdict record.
            v = struct('wellID', "", 'fileName', "", 'wellKey', "", ...
                'autoPass', false, 'autoVerdict', "fail", 'reasons', {{}}, ...
                'ivUsed', "", 'metrics', struct());
        end
        
        function filterReport = createIVFallbackFilterReport(obj, wellIDs, measurements, ...
                qualityMask, ivUsedForFiltering, filters, hasIV2)
            %CREATEIVFALLBACKFILTERREPORT Generate filter report
            
            numWells = length(wellIDs);
            iv1Data = measurements.iv1;
            
            iv1Used = sum(ivUsedForFiltering == "iv1");
            if hasIV2
                iv2Used = sum(ivUsedForFiltering == "iv2");
            else
                iv2Used = 0;
            end
            
            minValidSweeps = 15;
            
            iv1SeriesRMedians = median(iv1Data.seriesResistance, 2, 'omitnan');
            iv1SealRMedians = median(iv1Data.sealResistance, 2, 'omitnan');
            iv1CapMedians = median(iv1Data.capacitance, 2, 'omitnan');
            
            filterReport = struct(...
                'totalWells', numWells, ...
                'passedWells', sum(qualityMask), ...
                'failedWells', sum(~qualityMask), ...
                'ivUsage', struct('iv1Used', iv1Used, 'iv2Used', iv2Used));
        end
        
        function logIVFallbackFilteringResults(obj, filterReport, hasIV2)
            %LOGIVFALLBACKFILTERINGRESULTS Log filtering results
            
            obj.logger.logInfo(sprintf('✓ Quality filtering: %d/%d wells passed (%.1f%%)', ...
                filterReport.passedWells, filterReport.totalWells, ...
                100 * filterReport.passedWells / filterReport.totalWells));
            
            if hasIV2
                obj.logger.logInfo(sprintf('IV1 used: %d, IV2 fallback: %d', ...
                    filterReport.ivUsage.iv1Used, filterReport.ivUsage.iv2Used));
            end
            
            % ADD THIS:
            if isfield(filterReport, 'negativeConductanceFiltered') && filterReport.negativeConductanceFiltered > 0
                obj.logger.logInfo(sprintf('⚠ Pre-filtered: %d wells removed for negative conductance', ...
                    filterReport.negativeConductanceFiltered));
            end
        end
        
        function filteredMeasurements = applyFilterMask(obj, measurements, qualityMask)
            %APPLYFILTERMASK Apply quality mask to all IVs
            
            filteredMeasurements = struct();
            ivFields = fieldnames(measurements);
            
            for i = 1:length(ivFields)
                ivName = ivFields{i};
                ivData = measurements.(ivName);
                
                paramFields = fieldnames(ivData);
                for j = 1:length(paramFields)
                    paramName = paramFields{j};
                    data = ivData.(paramName);
                    
                    % Handle both 2D arrays [wells × sweeps] and 1D arrays [wells × 1]
                    if size(data, 1) == length(qualityMask)
                        filteredMeasurements.(ivName).(paramName) = data(qualityMask, :);
                    else
                        filteredMeasurements.(ivName).(paramName) = data;
                    end
                end
            end
        end

        function diagnoseConductanceInversion(extractedData, logger)
            %DIAGNOSECONDUCTANCEINVERSION Check for inverted raw conductance
            %   Run this AFTER calculateConductance() but BEFORE normalizeConductance()
            
            logger.logInfo('=== CONDUCTANCE DIAGNOSTIC ===');
            
            measurements = extractedData.measurements;
            voltages = extractedData.protocolInfo.voltages;
            V_rev = extractedData.protocolInfo.V_rev;  % Assumes stored in protocolInfo
            
            ivFields = fieldnames(measurements);
            
            for i = 1:length(ivFields)
                ivName = ivFields{i};
                
                % Get raw data
                peakCurrent = measurements.(ivName).peakCurrent;  % [wells × voltages]
                conductance_raw = measurements.(ivName).conductance;
                
                numWells = size(conductance_raw, 1);
                inverted_count = 0;
                negative_count = 0;
                
                for wellIdx = 1:numWells
                    G = conductance_raw(wellIdx, :);
                    I = peakCurrent(wellIdx, :);
                    
                    % Check 1: Is conductance decreasing with voltage?
                    G_start = G(1);   % At most negative V
                    G_end = G(end);   % At most positive V
                    
                    if ~isnan(G_start) && ~isnan(G_end) && G_end < G_start
                        inverted_count = inverted_count + 1;
                        
                        if inverted_count <= 3  % Log first 3 cases
                            logger.logWarning(sprintf(['%s Well %d: INVERTED conductance! ' ...
                                'G(V_min)=%.2e, G(V_max)=%.2e'], ivName, wellIdx, G_start, G_end));
                            
                            % Detailed diagnosis
                            logger.logDebug(sprintf('  Current range: [%.1f, %.1f] pA', ...
                                min(I, [], 'omitnan'), max(I, [], 'omitnan')));
                            logger.logDebug(sprintf('  Driving force: V - V_rev = [%.1f, %.1f] - %.1f mV', ...
                                voltages(1), voltages(end), V_rev));
                        end
                    end
                    
                    % Check 2: Are there negative conductance values?
                    if any(G < 0)  % any() ignores NaNs for comparison operators
                        negative_count = negative_count + 1;
                    end
                end
                
                % Summary
                if inverted_count > 0 || negative_count > 0
                    logger.logWarning(sprintf('%s: %d/%d wells have INVERTED conductance', ...
                        ivName, inverted_count, numWells));
                    logger.logWarning(sprintf('%s: %d/%d wells have NEGATIVE conductance values', ...
                        ivName, negative_count, numWells));
                else
                    logger.logInfo(sprintf('%s: All wells have normal conductance direction', ivName));
                end
            end
            
            logger.logInfo('=== END DIAGNOSTIC ===');
        end


        function extractedData = filterNegativeConductance(obj, extractedData)
            %FILTERNEGATIVECONDUCTANCE Remove wells with negative conductance values
            %   Marks wells as failed quality if ANY conductance value is negative
            %   Updates metadata to track reason for filtering
            
            if ~strcmp(extractedData.protocolInfo.type, 'activation')
                return;  % Only applies to activation protocols
            end
            
            obj.logger.logInfo('Filtering wells with negative conductance...');
            
            measurements = extractedData.measurements;
            ivFields = fieldnames(measurements);
            numWells = extractedData.numWells;
            
            % Track which wells have negative conductance
            hasNegativeConductance = false(numWells, 1);
            negativeConductanceIV = strings(numWells, 1);  % Which IV has negative values
            
            for i = 1:length(ivFields)
                ivName = ivFields{i};
                conductance_raw = measurements.(ivName).conductance;
                
                for wellIdx = 1:numWells
                    G = conductance_raw(wellIdx, :);
                    
                    % Check if ANY conductance value is negative
                    if any(G < 0)
                        hasNegativeConductance(wellIdx) = true;
                        
                        % Track which IV(s) have the problem
                        if negativeConductanceIV(wellIdx) == ""
                            negativeConductanceIV(wellIdx) = ivName;
                        else
                            negativeConductanceIV(wellIdx) = negativeConductanceIV(wellIdx) + "," + ivName;
                        end
                    end
                end
            end
            
            % Count how many wells will be filtered
            numFiltered = sum(hasNegativeConductance);
            
            if numFiltered > 0
                obj.logger.logWarning(sprintf('Found %d/%d wells with negative conductance', ...
                    numFiltered, numWells));
                
                % Log first few affected wells
                filteredWellIndices = find(hasNegativeConductance);
                numToLog = min(5, numFiltered);
                
                for i = 1:numToLog
                    wellIdx = filteredWellIndices(i);
                    obj.logger.logWarning(sprintf('  Well %s (%s): negative conductance detected', ...
                        extractedData.wellIDs(wellIdx), negativeConductanceIV(wellIdx)));
                end
                
                if numFiltered > 5
                    obj.logger.logWarning(sprintf('  ... and %d more wells', numFiltered - 5));
                end
                
                % SAVE FILTERED WELL IDs BEFORE FILTERING
                filteredWellIDs = extractedData.wellIDs(hasNegativeConductance);
                
                % Apply filter: remove wells with negative conductance
                validMask = ~hasNegativeConductance;
                
                % Filter all data structures
                extractedData.wellIDs = extractedData.wellIDs(validMask);
                extractedData.wellMetadata.cellType = extractedData.wellMetadata.cellType(validMask);
                extractedData.wellMetadata.cellConcentration = extractedData.wellMetadata.cellConcentration(validMask);
                
                % Filter measurements
                for i = 1:length(ivFields)
                    ivName = ivFields{i};
                    ivData = measurements.(ivName);
                    
                    paramFields = fieldnames(ivData);
                    for j = 1:length(paramFields)
                        paramName = paramFields{j};
                        data = ivData.(paramName);
                        
                        % Filter 2D arrays [wells × sweeps] and 1D arrays [wells × 1]
                        if size(data, 1) == numWells
                            measurements.(ivName).(paramName) = data(validMask, :);
                        end
                    end
                end
                
                extractedData.measurements = measurements;
                extractedData.numWells = sum(validMask);
                
                % Add filter metadata
                extractedData.negativeConductanceFilter = struct(...
                    'applied', true, ...
                    'numFiltered', numFiltered, ...
                    'numRemaining', sum(validMask), ...
                    'filteredWellIDs', filteredWellIDs);  % ← USE SAVED VARIABLE
                
                obj.logger.logInfo(sprintf('✓ Negative conductance filter: %d wells removed, %d remaining', ...
                    numFiltered, sum(validMask)));

            else
                obj.logger.logInfo('✓ No wells with negative conductance detected');
                
                extractedData.negativeConductanceFilter = struct(...
                    'applied', true, ...
                    'numFiltered', 0, ...
                    'numRemaining', numWells);
            end
        end

    end
end
