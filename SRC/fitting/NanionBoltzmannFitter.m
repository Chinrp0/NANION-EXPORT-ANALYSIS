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
            
            % Get data based on protocol type
            if strcmp(protocolType, 'activation')
                if ~isfield(filteredData.measurements.iv1, 'conductance')
                    error('NanionBoltzmannFitter:MissingConductance', ...
                        'Conductance not calculated. Run calculateConductance() first.');
                end
                
                iv1Data = filteredData.measurements.iv1.conductance;
                if isfield(filteredData.measurements, 'iv2')
                    iv2Data = filteredData.measurements.iv2.conductance;
                else
                    iv2Data = [];
                end
                
                dataType = 'conductance';
                dataUnits = 'nS';
                obj.logger.logInfo('Using conductance (nS) for activation protocol');
            
                else % inactivation
                    % Normalize inactivation data for fitting
                    iv1_inact_raw = filteredData.measurements.iv1.inactivationData;
                    
                    % Normalize each well by its own minimum (most negative = maximum absolute current)
                    numWells = size(iv1_inact_raw, 1);
                    iv1Data = zeros(size(iv1_inact_raw));
                    for i = 1:numWells
                        wellMin = min(iv1_inact_raw(i, :));
                        if wellMin ~= 0
                            iv1Data(i, :) = iv1_inact_raw(i, :) / wellMin;
                        else
                            iv1Data(i, :) = iv1_inact_raw(i, :);
                        end
                    end
                    
                    % Normalize IV2 if available
                    if isfield(filteredData.measurements, 'iv2')
                        iv2_inact_raw = filteredData.measurements.iv2.inactivationData;
                        iv2Data = zeros(size(iv2_inact_raw));
                        for i = 1:numWells
                            wellMin = min(iv2_inact_raw(i, :));
                            if wellMin ~= 0
                                iv2Data(i, :) = iv2_inact_raw(i, :) / wellMin;
                            else
                                iv2Data(i, :) = iv2_inact_raw(i, :);
                            end
                        end
                    else
                        iv2Data = [];
                    end
                    
                    dataType = 'normalized_inactivation';
                    dataUnits = '0-1';
                    obj.logger.logInfo('Normalized inactivation data for Boltzmann fitting');
                end

            
                % Initialize wells array - UPDATED STRUCTURE
                wells(numWells) = struct(...
                    'wellID', '', ...
                    'protocol', '', ...
                    'ivUsed', '', ...
                    'voltages', [], ...
                    'dataType', dataType, ...
                    'dataUnits', dataUnits, ...
                    'iv1', struct(), ...
                    'iv2', []);
            
            % Fit wells (sequential for debugging)
            if obj.config.boltzmann.useParallel && numWells > 1
                obj.logger.logWarning('⚠ Parallel processing enabled - errors may be hidden!');
                wells = obj.fitWellsParallel(wells, filteredData.wellIDs, voltages, ...
                    iv1Data, iv2Data, ivUsed, protocolType, dataType, dataUnits);
            else
                obj.logger.logInfo('Using sequential processing for fitting (better error visibility)');
                wells = obj.fitWellsSequential(wells, filteredData.wellIDs, voltages, ...
                    iv1Data, iv2Data, ivUsed, protocolType, dataType, dataUnits);
            end
            

            % Generate summary statistics from new nested structure
            summary = obj.generateFitSummary(wells);
            
            % Package results
            fittedData = struct(...
                'wells', wells, ...
                'summary', summary, ...
                'numWells', numWells, ...
                'protocol', protocolType, ...
                'dataType', dataType, ...
                'dataUnits', dataUnits);
            
            obj.logger.logInfo(sprintf('✓ Boltzmann fitting complete: %d Good, %d Acceptable, %d Poor, %d Failed', ...
                summary.fitResults.good, summary.fitResults.acceptable, ...
                summary.fitResults.poor, summary.fitResults.failed));
            
            % Package results
            fittedData = struct(...
                'wells', wells, ...
                'summary', summary, ...
                'numWells', numWells, ...
                'protocol', protocolType, ...
                'dataType', dataType, ...
                'dataUnits', dataUnits);
            
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
                    voltages, fitresult.V_min, fitresult.V_max, fitresult.V_mid, fitresult.k);
                
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
            iv1Data, iv2Data, ivUsed, protocolType, dataType, dataUnits)
        %FITWELLSSEQUENTIAL Fit ALL available IVs for each well
        
        numWells = length(wellIDs);
        errorCount = 0;
        hasIV2 = ~isempty(iv2Data);
        
        for wellIdx = 1:numWells
            % Fit IV1 (always available)
            iv1_data = iv1Data(wellIdx, :);
            iv1Fit = obj.fitSingleWell(voltages, iv1_data, protocolType, 'iv1');
            
            % Fit IV2 (if available)
            if hasIV2
                iv2_data = iv2Data(wellIdx, :);
                iv2Fit = obj.fitSingleWell(voltages, iv2_data, protocolType, 'iv2');
            else
                iv2Fit = [];
            end
            
            % Track errors from either IV
            if ~isempty(iv1Fit.fitError)
                errorCount = errorCount + 1;
                if errorCount <= 3
                    obj.logger.logError(sprintf('Well %d (%s) IV1: %s', ...
                        wellIdx, wellIDs(wellIdx), iv1Fit.fitError));
                end
            end
            
            if hasIV2 && ~isempty(iv2Fit.fitError)
                errorCount = errorCount + 1;
                if errorCount <= 3
                    obj.logger.logError(sprintf('Well %d (%s) IV2: %s', ...
                        wellIdx, wellIDs(wellIdx), iv2Fit.fitError));
                end
            end
            
            % Store results - BOTH IVs
            wells(wellIdx).wellID = wellIDs(wellIdx);
            wells(wellIdx).protocol = protocolType;
            wells(wellIdx).ivUsed = ivUsed(wellIdx);  % For quality reference
            wells(wellIdx).voltages = voltages;
            wells(wellIdx).dataType = dataType;
            wells(wellIdx).dataUnits = dataUnits;
            
            % Store IV1 fit
            wells(wellIdx).iv1 = struct(...
                'data', iv1_data, ...
                'validPoints', iv1Fit.validPoints, ...
                'fitParams', iv1Fit.fitParams, ...
                'fittedCurve', iv1Fit.fittedCurve, ...
                'fitQuality', iv1Fit.fitQuality, ...
                'fitError', iv1Fit.fitError);
            
            % Store IV2 fit (if exists)
            if hasIV2
                wells(wellIdx).iv2 = struct(...
                    'data', iv2_data, ...
                    'validPoints', iv2Fit.validPoints, ...
                    'fitParams', iv2Fit.fitParams, ...
                    'fittedCurve', iv2Fit.fittedCurve, ...
                    'fitQuality', iv2Fit.fitQuality, ...
                    'fitError', iv2Fit.fitError);
            else
                wells(wellIdx).iv2 = [];
            end
            
            % Progress logging
            if mod(wellIdx, 10) == 0 || wellIdx == numWells
                obj.logger.logInfo(sprintf('Fitting progress: %d/%d wells (%d errors)', ...
                    wellIdx, numWells, errorCount));
            end
        end
        
        if errorCount > 0
            obj.logger.logWarning(sprintf('⚠ Total fitting errors: %d/%d IVs', ...
                errorCount, numWells * (1 + hasIV2)));
        end
    end
        
             function wells = fitWellsParallel(obj, wells, wellIDs, voltages, ...
                    iv1Data, iv2Data, ivUsed, protocolType, dataType, dataUnits)
                %FITWELLSPARALLEL Fit wells in parallel (errors harder to debug)
                
                numWells = length(wellIDs);
                config = obj.config;
                
                obj.logger.logWarning('⚠ Using parallel processing - detailed errors may be suppressed');
                
                % Pre-declare for parfor - MUST be before parfor loop
                hasIV2 = ~isempty(iv2Data);
                
                parfor wellIdx = 1:numWells
                    % Fit IV1
                    iv1_data = iv1Data(wellIdx, :);
                    iv1Fit = NanionBoltzmannFitter.fitSingleWellStatic(...
                        voltages, iv1_data, protocolType, 'iv1', config);
                    
                    % Fit IV2 if available
                    if hasIV2
                        iv2_data = iv2Data(wellIdx, :);
                        iv2Fit = NanionBoltzmannFitter.fitSingleWellStatic(...
                            voltages, iv2_data, protocolType, 'iv2', config);
                    else
                        iv2Fit = struct(...
                            'fitError', 'No IV2 data', ...
                            'fittedCurve', [], ...
                            'fitParams', struct('converged', false), ...
                            'fitQuality', 'Failed', ...
                            'validPoints', 0);
                    end
                    
                    % Store results - BOTH IVs
                    wells(wellIdx).wellID = wellIDs(wellIdx);
                    wells(wellIdx).protocol = protocolType;
                    wells(wellIdx).ivUsed = ivUsed(wellIdx);
                    wells(wellIdx).voltages = voltages;
                    wells(wellIdx).dataType = dataType;
                    wells(wellIdx).dataUnits = dataUnits;
                    
                    % Store IV1
                    wells(wellIdx).iv1 = struct(...
                        'data', iv1_data, ...
                        'validPoints', iv1Fit.validPoints, ...
                        'fitParams', iv1Fit.fitParams, ...
                        'fittedCurve', iv1Fit.fittedCurve, ...
                        'fitQuality', iv1Fit.fitQuality, ...
                        'fitError', iv1Fit.fitError);
                    
                    % Store IV2
                    if hasIV2
                        wells(wellIdx).iv2 = struct(...
                            'data', iv2_data, ...
                            'validPoints', iv2Fit.validPoints, ...
                            'fitParams', iv2Fit.fitParams, ...
                            'fittedCurve', iv2Fit.fittedCurve, ...
                            'fitQuality', iv2Fit.fitQuality, ...
                            'fitError', iv2Fit.fitError);
                    else
                        wells(wellIdx).iv2 = [];
                    end
                end
                
                obj.logger.logInfo(sprintf('Parallel fitting complete: %d wells processed', numWells));
            end

        function summary = generateFitSummary(obj, wells)
            %GENERATEFITSUMMARY Generate summary statistics from nested IV structure
            %   Counts fit quality across both IV1 and IV2
            
            numWells = length(wells);
            
            % Count fit quality for IV1 and IV2 separately
            iv1_good = 0;
            iv1_acceptable = 0;
            iv1_poor = 0;
            iv1_failed = 0;
            
            iv2_good = 0;
            iv2_acceptable = 0;
            iv2_poor = 0;
            iv2_failed = 0;
            
            for i = 1:numWells
                % Count IV1 results
                if ~isempty(wells(i).iv1) && isfield(wells(i).iv1, 'fitQuality')
                    switch wells(i).iv1.fitQuality
                        case 'Good'
                            iv1_good = iv1_good + 1;
                        case 'Acceptable'
                            iv1_acceptable = iv1_acceptable + 1;
                        case 'Poor'
                            iv1_poor = iv1_poor + 1;
                        case 'Failed'
                            iv1_failed = iv1_failed + 1;
                    end
                else
                    iv1_failed = iv1_failed + 1;
                end
                
                % Count IV2 results (if exists)
                if ~isempty(wells(i).iv2) && isfield(wells(i).iv2, 'fitQuality')
                    switch wells(i).iv2.fitQuality
                        case 'Good'
                            iv2_good = iv2_good + 1;
                        case 'Acceptable'
                            iv2_acceptable = iv2_acceptable + 1;
                        case 'Poor'
                            iv2_poor = iv2_poor + 1;
                        case 'Failed'
                            iv2_failed = iv2_failed + 1;
                    end
                end
            end
            
            % Combined totals (for backward compatibility)
            total_good = iv1_good + iv2_good;
            total_acceptable = iv1_acceptable + iv2_acceptable;
            total_poor = iv1_poor + iv2_poor;
            total_failed = iv1_failed + iv2_failed;
            
            % Build summary structure
            summary = struct(...
                'fitResults', struct(...
                    'good', total_good, ...
                    'acceptable', total_acceptable, ...
                    'poor', total_poor, ...
                    'failed', total_failed), ...
                'iv1Results', struct(...
                    'good', iv1_good, ...
                    'acceptable', iv1_acceptable, ...
                    'poor', iv1_poor, ...
                    'failed', iv1_failed), ...
                'iv2Results', struct(...
                    'good', iv2_good, ...
                    'acceptable', iv2_acceptable, ...
                    'poor', iv2_poor, ...
                    'failed', iv2_failed), ...
                'numWells', numWells);
            
            obj.logger.logDebug(sprintf('Summary: IV1 (%d good, %d acceptable, %d poor, %d failed)', ...
                iv1_good, iv1_acceptable, iv1_poor, iv1_failed));
            
            if iv2_good + iv2_acceptable + iv2_poor + iv2_failed > 0
                obj.logger.logDebug(sprintf('Summary: IV2 (%d good, %d acceptable, %d poor, %d failed)', ...
                    iv2_good, iv2_acceptable, iv2_poor, iv2_failed));
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
                    voltages, fitresult.V_min, fitresult.V_max, fitresult.V_mid, fitresult.k);
                
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
