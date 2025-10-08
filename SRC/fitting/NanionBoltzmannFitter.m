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
                % CRITICAL: Check if we should normalize inactivation data
                iv1Data = filteredData.measurements.iv1.inactivationData;
                if isfield(filteredData.measurements, 'iv2')
                    iv2Data = filteredData.measurements.iv2.inactivationData;
                else
                    iv2Data = [];
                end
                
                dataType = 'current';
                dataUnits = 'pA';
                obj.logger.logInfo('Using current (pA) for inactivation protocol');
                obj.logger.logWarning('⚠ Inactivation data NOT normalized - may cause fitting issues!');
            end
            
            % Initialize wells array
            wells(numWells) = struct(...
                'wellID', '', 'protocol', '', 'ivUsed', '', ...
                'voltages', [], 'data', [], 'dataType', dataType, 'dataUnits', dataUnits, ...
                'validPoints', 0, 'fitParams', struct(), 'fitQuality', '', 'fitError', '');
            
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
            
            % Generate summary statistics
            summary = FitQualityAssessor.summarizeFitResults(struct('wells', wells));
            
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
                [startPoints, lowerBounds, upperBounds] = BoltzmannModel.getInitialParams(...
                    V_valid, D_valid, protocolType, obj.config);
                
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
                if isfield(obj.config.configData.analysis, 'temperature')
                    temperature = obj.config.configData.analysis.temperature;
                else
                    temperature = 25;
                    obj.logger.logWarning('Temperature not in config, using default 25°C');
                end
                
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
                
                % Assess fit quality
                quality = FitQualityAssessor.assessQuality(fitParams, gof, protocolType, obj.config);
                
                % Update result
                wellFit.fitParams = fitParams;
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
            %FITWELLSSEQUENTIAL Fit wells one by one with error tracking
            
            numWells = length(wellIDs);
            errorCount = 0;
            
            for wellIdx = 1:numWells
                % Get data for this well
                if strcmp(ivUsed(wellIdx), 'iv1')
                    data = iv1Data(wellIdx, :);
                else
                    data = iv2Data(wellIdx, :);
                end
                
                % Fit well
                wellFit = obj.fitSingleWell(voltages, data, protocolType, ivUsed(wellIdx));
                
                % Track errors
                if ~isempty(wellFit.fitError)
                    errorCount = errorCount + 1;
                    if errorCount <= 3  % Log first 3 errors in detail
                        obj.logger.logError(sprintf('Well %d (%s): %s', ...
                            wellIdx, wellIDs(wellIdx), wellFit.fitError));
                    end
                end
                
                % Store result
                wells(wellIdx).wellID = wellIDs(wellIdx);
                wells(wellIdx).protocol = protocolType;
                wells(wellIdx).ivUsed = wellFit.ivUsed;
                wells(wellIdx).voltages = wellFit.voltages;
                wells(wellIdx).data = wellFit.data;
                wells(wellIdx).dataType = dataType;
                wells(wellIdx).dataUnits = dataUnits;
                wells(wellIdx).validPoints = wellFit.validPoints;
                wells(wellIdx).fitParams = wellFit.fitParams;
                wells(wellIdx).fitQuality = wellFit.fitQuality;
                wells(wellIdx).fitError = wellFit.fitError;
                
                % Progress logging
                if mod(wellIdx, 10) == 0 || wellIdx == numWells
                    obj.logger.logInfo(sprintf('Fitting progress: %d/%d wells (%d errors so far)', ...
                        wellIdx, numWells, errorCount));
                end
            end
            
            if errorCount > 0
                obj.logger.logWarning(sprintf('⚠ Total fitting errors: %d/%d wells', errorCount, numWells));
            end
        end
        
        function wells = fitWellsParallel(obj, wells, wellIDs, voltages, ...
                iv1Data, iv2Data, ivUsed, protocolType, dataType, dataUnits)
            %FITWELLSPARALLEL Fit wells in parallel (errors harder to debug)
            
            numWells = length(wellIDs);
            config = obj.config;
            
            obj.logger.logWarning('⚠ Using parallel processing - detailed errors may be suppressed');
            
            parfor wellIdx = 1:numWells
                if strcmp(ivUsed(wellIdx), 'iv1')
                    data = iv1Data(wellIdx, :);
                else
                    if ~isempty(iv2Data)
                        data = iv2Data(wellIdx, :);
                    else
                        data = iv1Data(wellIdx, :);
                    end
                end
                
                wellFit = NanionBoltzmannFitter.fitSingleWellStatic(...
                    voltages, data, protocolType, ivUsed(wellIdx), config);
                
                wells(wellIdx).wellID = wellIDs(wellIdx);
                wells(wellIdx).protocol = protocolType;
                wells(wellIdx).ivUsed = wellFit.ivUsed;
                wells(wellIdx).voltages = wellFit.voltages;
                wells(wellIdx).data = wellFit.data;
                wells(wellIdx).dataType = dataType;
                wells(wellIdx).dataUnits = dataUnits;
                wells(wellIdx).validPoints = wellFit.validPoints;
                wells(wellIdx).fitParams = wellFit.fitParams;
                wells(wellIdx).fitQuality = wellFit.fitQuality;
                wells(wellIdx).fitError = wellFit.fitError;
            end
            
            obj.logger.logInfo(sprintf('Parallel fitting complete: %d wells processed', numWells));
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
                [startPoints, lowerBounds, upperBounds] = BoltzmannModel.getInitialParams(...
                    V_valid, D_valid, protocolType, config);
                
                ft = BoltzmannModel.createFitType(protocolType);
                
                [fitresult, gof] = fit(V_valid(:), D_valid(:), ft, ...
                    'StartPoint', startPoints, ...
                    'Lower', lowerBounds, ...
                    'Upper', upperBounds);
                
                if isfield(config.configData.analysis, 'temperature')
                    temperature = config.configData.analysis.temperature;
                else
                    temperature = 25;
                end
                
                fitParams = struct(...
                    'V_min', fitresult.V_min, ...
                    'V_max', fitresult.V_max, ...
                    'V_mid', fitresult.V_mid, ...
                    'k', fitresult.k, ...
                    'z_a', BoltzmannModel.calculateGatingCharge(fitresult.k, temperature), ...
                    'R2', gof.rsquare, ...
                    'RMSE', gof.rmse, ...
                    'converged', true);
                
                quality = FitQualityAssessor.assessQuality(fitParams, gof, protocolType, config);
                
                wellFit.fitParams = fitParams;
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
