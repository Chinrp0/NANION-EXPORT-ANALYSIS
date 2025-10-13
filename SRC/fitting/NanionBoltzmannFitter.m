classdef NanionBoltzmannFitter < handle
    %NANIONBOLTZMANNFITTER Main Boltzmann curve fitting class
    %   UPDATED: Added error logging to catch blocks for debugging
    
    properties (Access = private)
        config
        logger
    end
    
    methods
        function obj = NanionBoltzmannFitter(config, logger)
            obj.config = config;
            obj.logger = logger;
        end
        
        function fittedData = fitBoltzmann(obj, filteredData)
            %FITBOLTZMANN Main entry point: fits all wells in filteredData
            
            obj.logger.logInfo('Starting Boltzmann curve fitting...');
            
            numWells = filteredData.numWellsPassed;
            protocolType = filteredData.protocolInfo.type;
            voltages = filteredData.protocolInfo.voltages;
            ivUsed = filteredData.ivUsedForFiltering;
            
            % DYNAMIC IV DETECTION - Get all available IVs
            ivNames = fieldnames(filteredData.measurements);
            numIVs = length(ivNames);
            obj.logger.logInfo(sprintf('Detected %d IVs: %s', numIVs, strjoin(ivNames, ', ')));
            
            % Extract data for all available IVs
            ivDataArray = cell(1, numIVs);
            
            if strcmp(protocolType, 'activation')
                % Check conductance is calculated
                if ~isfield(filteredData.measurements.iv1, 'conductance')
                    error('NanionBoltzmannFitter:MissingConductance', ...
                        'Conductance not calculated. Run calculateConductance() first.');
                end
                
                % Extract conductance for all IVs
                for i = 1:numIVs
                    ivDataArray{i} = filteredData.measurements.(ivNames{i}).conductance;
                end
                
                dataType = 'conductance';
                dataUnits = 'nS';
                obj.logger.logInfo('Using conductance (nS) for activation protocol');
                
            else % inactivation
                % Normalize inactivation data for all IVs
                for i = 1:numIVs
                    ivName = ivNames{i};
                    iv_inact_raw = filteredData.measurements.(ivName).inactivationData;
                    
                    % Normalize each well by its own minimum
                    numWellsInIV = size(iv_inact_raw, 1);
                    ivDataNormalized = zeros(size(iv_inact_raw));
                    
                    for w = 1:numWellsInIV
                        wellMin = min(iv_inact_raw(w, :));
                        if wellMin ~= 0
                            ivDataNormalized(w, :) = iv_inact_raw(w, :) / wellMin;
                        else
                            ivDataNormalized(w, :) = iv_inact_raw(w, :);
                        end
                    end
                    
                    ivDataArray{i} = ivDataNormalized;
                end
                
                dataType = 'normalized_inactivation';
                dataUnits = '0-1';
                obj.logger.logInfo('Normalized inactivation data for Boltzmann fitting');
            end
            
            % Initialize wells array with dynamic IV fields
            wells(numWells) = struct(...
                'wellID', '', ...
                'protocol', '', ...
                'ivUsed', '', ...
                'voltages', [], ...
                'dataType', dataType, ...
                'dataUnits', dataUnits);
            
            % Add IV fields dynamically
            for i = 1:numIVs
                ivFieldName = ivNames{i};
                for w = 1:numWells
                    wells(w).(ivFieldName) = struct();
                end
            end
            
            % Fit wells (sequential for debugging)
            if obj.config.boltzmann.useParallel && numWells > 1
                obj.logger.logWarning('⚠ Parallel processing enabled - errors may be hidden!');
                wells = obj.fitWellsParallel(wells, filteredData.wellIDs, voltages, ...
                    ivDataArray, ivNames, ivUsed, protocolType, dataType, dataUnits);
            else
                obj.logger.logInfo('Using sequential processing for fitting (better error visibility)');
                wells = obj.fitWellsSequential(wells, filteredData.wellIDs, voltages, ...
                    ivDataArray, ivNames, ivUsed, protocolType, dataType, dataUnits);
            end
            
            % Generate summary statistics from nested structure
            summary = obj.generateFitSummary(wells, ivNames);
            
            % Package results
            fittedData = struct(...
                'wells', wells, ...
                'summary', summary, ...
                'numWells', numWells, ...
                'protocol', protocolType, ...
                'dataType', dataType, ...
                'dataUnits', dataUnits, ...
                'ivNames', {ivNames});
            
            obj.logger.logInfo(sprintf('✓ Boltzmann fitting complete: %d Good, %d Acceptable, %d Poor, %d Failed', ...
                summary.fitResults.good, summary.fitResults.acceptable, ...
                summary.fitResults.poor, summary.fitResults.failed));
        end
        
        function wellFit = fitSingleWell(obj, voltages, data, protocolType, ivUsed)
            %FITSINGLEWELL Fit one well with DETAILED error logging
            
            % Remove NaN values
            validIdx = ~isnan(data) & ~isnan(voltages);
            V_valid = voltages(validIdx);
            D_valid = data(validIdx);
            numValid = sum(validIdx);
            
            % Initialize result structure
            wellFit = struct(...
                'voltages', voltages, ...
                'data', data, ...
                'validPoints', numValid, ...
                'fitParams', struct('converged', false), ...
                'fitQuality', 'Failed', ...
                'fitError', '', ...
                'ivUsed', ivUsed);
            
            % Check minimum data requirement
            if numValid < obj.config.boltzmann.minValidPoints
                wellFit.fitError = sprintf('Insufficient valid points: %d < %d', ...
                    numValid, obj.config.boltzmann.minValidPoints);
                obj.logger.logWarning(wellFit.fitError);
                return;
            end
            
            try
                % Get initial parameters and bounds
                % Detect if data is normalized (0-1 range) - applies to both inactivation AND activation
                if (strcmp(protocolType, 'inactivation') || strcmp(protocolType, 'activation')) && ...
                   max(D_valid) <= 1.5 && min(D_valid) >= -0.5
                    % Data appears to be normalized
                    [startPoints, lowerBounds, upperBounds] = BoltzmannModel.getInitialParams(...
                        V_valid, D_valid, protocolType, obj.config);
                    
                    % Override V_min and V_max bounds for normalized data
                    lowerBounds(1) = 0.0;      % V_min lower bound
                    upperBounds(1) = 0.2;      % V_min upper bound
                    lowerBounds(2) = 0.8;      % V_max lower bound
                    upperBounds(2) = 1.2;      % V_max upper bound
                    startPoints(1) = 0.0;      % V_min start
                    startPoints(2) = 1.0;      % V_max start
                    
                    obj.logger.logDebug('Using normalized data bounds (0-1)');
                else
                    [startPoints, lowerBounds, upperBounds] = BoltzmannModel.getInitialParams(...
                        V_valid, D_valid, protocolType, obj.config);
                end
                
                % DEBUG: Log fitting setup
                obj.logger.logDebug(sprintf('Fitting setup: V range [%.1f, %.1f], Data range [%.3e, %.3e]', ...
                    min(V_valid), max(V_valid), min(D_valid), max(D_valid)));
                obj.logger.logDebug(sprintf('Start points: V_min=%.3e, V_max=%.3e, V_mid=%.1f, k=%.1f', ...
                    startPoints(1), startPoints(2), startPoints(3), startPoints(4)));
                
                % Create fittype
                ft = BoltzmannModel.createFitType(protocolType);
                
                % Perform fit
                [fitresult, gof] = fit(V_valid(:), D_valid(:), ft, ...
                    'StartPoint', startPoints, ...
                    'Lower', lowerBounds, ...
                    'Upper', upperBounds);
                
                % Get temperature
                temperature = obj.config.temperature;  % Uses public Dependent property
                
                % Extract parameters
                fitParams = struct(...
                    'V_min', fitresult.V_min, ...
                    'V_max', fitresult.V_max, ...
                    'V_mid', fitresult.V_mid, ...
                    'k', fitresult.k, ...
                    'z_a', BoltzmannModel.calculateGatingCharge(fitresult.k, temperature), ...
                    'R2', gof.rsquare, ...
                    'RMSE', gof.rmse, ...
                    'converged', true);
                
                % Generate fitted curve by evaluating Boltzmann at all voltage points
                fittedCurve = BoltzmannModel.evaluateBoltzmann(...
                    voltages, fitresult.V_min, fitresult.V_max, fitresult.V_mid, fitresult.k, protocolType);
                
                % Assess fit quality
                quality = FitQualityAssessor.assessQuality(fitParams, gof, protocolType, obj.config);
                
                % Update result
                wellFit.fitParams = fitParams;
                wellFit.fittedCurve = fittedCurve;  % NEW
                wellFit.fitQuality = quality;
                wellFit.fitError = ''; % Success
                
                obj.logger.logDebug(sprintf('Fit succeeded: V_mid=%.2f, k=%.2f, R²=%.4f, Quality=%s', ...
                    fitParams.V_mid, fitParams.k, fitParams.R2, quality));
                
            catch ME
                % ENHANCED ERROR LOGGING
                wellFit.fitQuality = 'Failed';
                wellFit.fitError = ME.message;
                
                obj.logger.logError(sprintf('❌ Fit failed: %s', ME.message));
                obj.logger.logError(sprintf('   Error ID: %s', ME.identifier));
                
                if ~isempty(ME.stack)
                    obj.logger.logError(sprintf('   In: %s (line %d)', ...
                        ME.stack(1).name, ME.stack(1).line));
                end
                
                % Log data characteristics for debugging
                obj.logger.logError(sprintf('   Data range: [%.3e, %.3e]', min(D_valid), max(D_valid)));
                obj.logger.logError(sprintf('   Voltage range: [%.1f, %.1f] mV', min(V_valid), max(V_valid)));
                obj.logger.logError(sprintf('   Valid points: %d', numValid));
            end
        end
    end
    
    methods (Access = private)
        function wells = fitWellsSequential(obj, wells, wellIDs, voltages, ...
        ivDataArray, ivNames, ivUsed, protocolType, dataType, dataUnits)
            %FITWELLSSEQUENTIAL Fit ALL available IVs for each well (DYNAMIC)
            
            numWells = length(wellIDs);
            numIVs = length(ivNames);
            errorCount = 0;
            
            obj.logger.logInfo(sprintf('Fitting %d wells × %d IVs = %d total fits', ...
                numWells, numIVs, numWells * numIVs));
            
            for wellIdx = 1:numWells
                % Fit all available IVs for this well
                for ivIdx = 1:numIVs
                    ivName = ivNames{ivIdx};
                    ivData = ivDataArray{ivIdx};
                    
                    % Get data for this well
                    iv_data = ivData(wellIdx, :);
                    
                    % Fit this IV
                    ivFit = obj.fitSingleWell(voltages, iv_data, protocolType, ivName);
                    
                    % Track errors
                    if ~isempty(ivFit.fitError)
                        errorCount = errorCount + 1;
                        if errorCount <= 5  % Show first 5 errors
                            obj.logger.logError(sprintf('Well %d (%s) %s: %s', ...
                                wellIdx, wellIDs(wellIdx), upper(ivName), ivFit.fitError));
                        end
                    end
                    
                    % Store fit results
                    wells(wellIdx).(ivName) = struct(...
                        'data', iv_data, ...
                        'validPoints', ivFit.validPoints, ...
                        'fitParams', ivFit.fitParams, ...
                        'fittedCurve', ivFit.fittedCurve, ...
                        'fitQuality', ivFit.fitQuality, ...
                        'fitError', ivFit.fitError);
                end
                
                % Store well metadata (once per well)
                wells(wellIdx).wellID = wellIDs(wellIdx);
                wells(wellIdx).protocol = protocolType;
                wells(wellIdx).ivUsed = ivUsed(wellIdx);
                wells(wellIdx).voltages = voltages;
                wells(wellIdx).dataType = dataType;
                wells(wellIdx).dataUnits = dataUnits;
                
                % Progress logging
                if mod(wellIdx, 10) == 0 || wellIdx == numWells
                    obj.logger.logInfo(sprintf('Fitting progress: %d/%d wells (%d errors)', ...
                        wellIdx, numWells, errorCount));
                end
            end
            
            totalFits = numWells * numIVs;
            if errorCount > 0
                obj.logger.logWarning(sprintf('⚠ Total fitting errors: %d/%d fits (%.1f%%)', ...
                    errorCount, totalFits, 100 * errorCount / totalFits));
            else
                obj.logger.logInfo(sprintf('✓ All %d fits completed successfully', totalFits));
            end
        end
        
             function wells = fitWellsParallel(obj, wells, wellIDs, voltages, ...
                    ivDataArray, ivNames, ivUsed, protocolType, dataType, dataUnits)
                %FITWELLSPARALLEL Fit wells in parallel (DYNAMIC IV support)
                
                numWells = length(wellIDs);
                numIVs = length(ivNames);
                config = obj.config;
                
                obj.logger.logWarning('⚠ Using parallel processing - detailed errors may be suppressed');
                obj.logger.logInfo(sprintf('Fitting %d wells × %d IVs = %d total fits in parallel', ...
                    numWells, numIVs, numWells * numIVs));
                
                parfor wellIdx = 1:numWells
                    % Fit all IVs for this well
                    for ivIdx = 1:numIVs
                        ivName = ivNames{ivIdx};
                        ivData = ivDataArray{ivIdx};
                        iv_data = ivData(wellIdx, :);
                        
                        % Fit this IV
                        ivFit = NanionBoltzmannFitter.fitSingleWellStatic(...
                            voltages, iv_data, protocolType, ivName, config);
                        
                        % Store results
                        wells(wellIdx).(ivName) = struct(...
                            'data', iv_data, ...
                            'validPoints', ivFit.validPoints, ...
                            'fitParams', ivFit.fitParams, ...
                            'fittedCurve', ivFit.fittedCurve, ...
                            'fitQuality', ivFit.fitQuality, ...
                            'fitError', ivFit.fitError);
                    end
                    
                    % Store well metadata
                    wells(wellIdx).wellID = wellIDs(wellIdx);
                    wells(wellIdx).protocol = protocolType;
                    wells(wellIdx).ivUsed = ivUsed(wellIdx);
                    wells(wellIdx).voltages = voltages;
                    wells(wellIdx).dataType = dataType;
                    wells(wellIdx).dataUnits = dataUnits;
                end
                
                obj.logger.logInfo(sprintf('Parallel fitting complete: %d wells × %d IVs processed', ...
                    numWells, numIVs));
            end

         function summary = generateFitSummary(obj, wells, ivNames)
            %GENERATEFITSUMMARY Generate summary statistics from nested IV structure (DYNAMIC)
            %   Counts fit quality across all available IVs
            
            numWells = length(wells);
            numIVs = length(ivNames);
            
            % Initialize counters for each IV
            ivResults = struct();
            for i = 1:numIVs
                ivName = ivNames{i};
                ivResults.(ivName) = struct('good', 0, 'acceptable', 0, 'poor', 0, 'failed', 0);
            end
            
            % Count quality for each IV
            for w = 1:numWells
                for i = 1:numIVs
                    ivName = ivNames{i};
                    
                    if isfield(wells(w), ivName) && ~isempty(wells(w).(ivName)) && ...
                       isfield(wells(w).(ivName), 'fitQuality')
                        
                        quality = wells(w).(ivName).fitQuality;
                        
                        switch quality
                            case 'Good'
                                ivResults.(ivName).good = ivResults.(ivName).good + 1;
                            case 'Acceptable'
                                ivResults.(ivName).acceptable = ivResults.(ivName).acceptable + 1;
                            case 'Poor'
                                ivResults.(ivName).poor = ivResults.(ivName).poor + 1;
                            case 'Failed'
                                ivResults.(ivName).failed = ivResults.(ivName).failed + 1;
                        end
                    else
                        ivResults.(ivName).failed = ivResults.(ivName).failed + 1;
                    end
                end
            end
            
            % Calculate combined totals
            total_good = 0;
            total_acceptable = 0;
            total_poor = 0;
            total_failed = 0;
            
            for i = 1:numIVs
                ivName = ivNames{i};
                total_good = total_good + ivResults.(ivName).good;
                total_acceptable = total_acceptable + ivResults.(ivName).acceptable;
                total_poor = total_poor + ivResults.(ivName).poor;
                total_failed = total_failed + ivResults.(ivName).failed;
            end
            
            % Build summary structure with combined + per-IV results
            summary = struct(...
                'fitResults', struct(...
                    'good', total_good, ...
                    'acceptable', total_acceptable, ...
                    'poor', total_poor, ...
                    'failed', total_failed), ...
                'numWells', numWells);
            
            % Add per-IV results dynamically
            for i = 1:numIVs
                ivName = ivNames{i};
                fieldName = [ivName 'Results'];
                summary.(fieldName) = ivResults.(ivName);
            end
            
            % Log per-IV breakdown
            for i = 1:numIVs
                ivName = ivNames{i};
                ivRes = ivResults.(ivName);
                obj.logger.logInfo(sprintf('  %s: %d Good, %d Acceptable, %d Poor, %d Failed', ...
                    upper(ivName), ivRes.good, ivRes.acceptable, ivRes.poor, ivRes.failed));
            end
        end
    end
    
    methods (Static)
        function wellFit = fitSingleWellStatic(voltages, data, protocolType, ivUsed, config)
            %FITSINGLEWELLSTATIC Static version for parfor - WITH ERROR CAPTURE
            
            validIdx = ~isnan(data) & ~isnan(voltages);
            V_valid = voltages(validIdx);
            D_valid = data(validIdx);
            numValid = sum(validIdx);
            
            wellFit = struct(...
                'voltages', voltages, ...
                'data', data, ...
                'validPoints', numValid, ...
                'fitParams', struct('converged', false), ...
                'fitQuality', 'Failed', ...
                'fitError', '', ...
                'ivUsed', ivUsed);
            
            if numValid < config.boltzmann.minValidPoints
                wellFit.fitError = sprintf('Insufficient points: %d < %d', ...
                    numValid, config.boltzmann.minValidPoints);
                return;
            end
            
            try
               % Get initial parameters and bounds
                % Detect if data is normalized (0-1 range) - applies to both inactivation AND activation
                if (strcmp(protocolType, 'inactivation') || strcmp(protocolType, 'activation')) && ...
                   max(D_valid) <= 1.5 && min(D_valid) >= -0.5
                    % Data appears to be normalized
                    [startPoints, lowerBounds, upperBounds] = BoltzmannModel.getInitialParams(...
                        V_valid, D_valid, protocolType, obj.config);
                    
                    % Override V_min and V_max bounds for normalized data
                    lowerBounds(1) = 0.0;      % V_min lower bound
                    upperBounds(1) = 0.2;      % V_min upper bound
                    lowerBounds(2) = 0.8;      % V_max lower bound
                    upperBounds(2) = 1.2;      % V_max upper bound
                    startPoints(1) = 0.0;      % V_min start
                    startPoints(2) = 1.0;      % V_max start
                    
                    obj.logger.logDebug('Using normalized data bounds (0-1)');
                else
                    [startPoints, lowerBounds, upperBounds] = BoltzmannModel.getInitialParams(...
                        V_valid, D_valid, protocolType, obj.config);
                end
                
                ft = BoltzmannModel.createFitType(protocolType);
                
                [fitresult, gof] = fit(V_valid(:), D_valid(:), ft, ...
                    'StartPoint', startPoints, ...
                    'Lower', lowerBounds, ...
                    'Upper', upperBounds);
                
                temperature = config.temperature;  % Uses public Dependent property
                
                fitParams = struct(...
                    'V_min', fitresult.V_min, ...
                    'V_max', fitresult.V_max, ...
                    'V_mid', fitresult.V_mid, ...
                    'k', fitresult.k, ...
                    'z_a', BoltzmannModel.calculateGatingCharge(fitresult.k, temperature), ...
                    'R2', gof.rsquare, ...
                    'RMSE', gof.rmse, ...
                    'converged', true);
                
                % Generate fitted curve
                fittedCurve = BoltzmannModel.evaluateBoltzmann(...
                    voltages, fitresult.V_min, fitresult.V_max, fitresult.V_mid, fitresult.k, protocolType);
                
                quality = FitQualityAssessor.assessQuality(fitParams, gof, protocolType, config);
                
                wellFit.fitParams = fitParams;
                wellFit.fittedCurve = fittedCurve;  % NEW
                wellFit.fitQuality = quality;
                wellFit.fitError = '';
                
            catch ME
                % CAPTURE ERROR MESSAGE IN PARALLEL
                wellFit.fitQuality = 'Failed';
                wellFit.fitError = sprintf('%s: %s', ME.identifier, ME.message);
            end
        end
    end
end
