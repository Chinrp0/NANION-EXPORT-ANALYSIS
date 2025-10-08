classdef NanionBoltzmannFitter < handle
    %NANIONBOLTZMANNFITTER Main Boltzmann curve fitting class
    %   Fits 4-parameter Boltzmann equations to I-V curves with quality assessment
    
    properties (Access = private)
        config
        logger
    end
    
    methods
        function obj = NanionBoltzmannFitter(config, logger)
            %NANIONBOLTZMANNFITTER Constructor
            
            obj.config = config;
            obj.logger = logger;
        end
        
        function fittedData = fitBoltzmann(obj, filteredData)
            %FITBOLTZMANN Main entry point: fits all wells in filteredData
            %   Uses CONDUCTANCE for activation, CURRENT for inactivation
            
            obj.logger.logInfo('Starting Boltzmann curve fitting...');
            
            numWells = filteredData.numWellsPassed;
            protocolType = filteredData.protocolInfo.type;
            voltages = filteredData.protocolInfo.voltages;
            
            % Determine which IV to use for each well
            ivUsed = filteredData.ivUsedForFiltering;
            
            % Get data based on protocol type
            if strcmp(protocolType, 'activation')
                % Use CONDUCTANCE for activation
                if ~isfield(filteredData.measurements.iv1, 'conductance')
                    error('NanionBoltzmannFitter:MissingConductance', ...
                        'Conductance not calculated. Run calculateConductance() first.');
                end
                
                iv1Data = filteredData.measurements.iv1.conductance;  % nS
                if isfield(filteredData.measurements, 'iv2')
                    iv2Data = filteredData.measurements.iv2.conductance;
                else
                    iv2Data = [];
                end
                
                dataType = 'conductance';
                dataUnits = 'nS';
                obj.logger.logInfo('Using conductance (nS) for activation protocol');
                
            else % inactivation
                % Use CURRENT for inactivation
                iv1Data = filteredData.measurements.iv1.inactivationData;  % pA
                if isfield(filteredData.measurements, 'iv2')
                    iv2Data = filteredData.measurements.iv2.inactivationData;
                else
                    iv2Data = [];
                end
                
                dataType = 'current';
                dataUnits = 'pA';
                obj.logger.logInfo('Using current (pA) for inactivation protocol');
            end
            
            % Initialize wells array
            wells(numWells) = struct(...
                'wellID', '', 'protocol', '', 'ivUsed', '', ...
                'voltages', [], 'data', [], 'dataType', dataType, 'dataUnits', dataUnits, ...
                'validPoints', 0, 'fitParams', struct(), 'fitQuality', '');
            
            % Fit wells (parallel or sequential)
            if obj.config.boltzmann.useParallel && numWells > 1
                obj.logger.logInfo('Using parallel processing for fitting...');
                wells = obj.fitWellsParallel(wells, filteredData.wellIDs, voltages, ...
                    iv1Data, iv2Data, ivUsed, protocolType, dataType, dataUnits);
            else
                obj.logger.logInfo('Using sequential processing for fitting...');
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
            %FITSINGLEWELL Fit one well, returns struct with fitParams, gof, quality
            %   'data' can be conductance (for activation) or current (for inactivation)
            
            % Remove NaN values
            validIdx = ~isnan(data) & ~isnan(voltages);
            V_valid = voltages(validIdx);
            D_valid = data(validIdx);  % Generic data (G or I)
            numValid = sum(validIdx);
            
            % Initialize result structure
            wellFit = struct(...
                'voltages', voltages, ...
                'data', data, ...
                'validPoints', numValid, ...
                'fitParams', struct('converged', false), ...
                'fitQuality', 'Failed', ...
                'ivUsed', ivUsed);
            
            % Check minimum data requirement
            if numValid < obj.config.boltzmann.minValidPoints
                return; % Return Failed
            end
            
            try
                % Get initial parameters and bounds
                [startPoints, lowerBounds, upperBounds] = BoltzmannModel.getInitialParams(...
                    V_valid, D_valid, protocolType, obj.config);
                
                % Create fittype
                ft = BoltzmannModel.createFitType(protocolType);
                
                % Perform fit
                [fitresult, gof] = fit(V_valid(:), D_valid(:), ft, ...
                    'StartPoint', startPoints, ...
                    'Lower', lowerBounds, ...
                    'Upper', upperBounds);
                
                % Extract parameters
                fitParams = struct(...
                    'V_min', fitresult.V_min, ...
                    'V_max', fitresult.V_max, ...
                    'V_mid', fitresult.V_mid, ...
                    'k', fitresult.k, ...
                    'z_a', BoltzmannModel.calculateGatingCharge(fitresult.k), ...
                    'R2', gof.rsquare, ...
                    'RMSE', gof.rmse, ...
                    'converged', true);
                
                % Assess fit quality
                quality = FitQualityAssessor.assessQuality(fitParams, gof, protocolType, obj.config);
                
                % Update result
                wellFit.fitParams = fitParams;
                wellFit.fitQuality = quality;
                
            catch ME
                % Fit failed - log warning but don't stop pipeline
                obj.logger.logWarning(sprintf('Fit failed: %s', ME.message));
                wellFit.fitQuality = 'Failed';
            end
        end
    end
    
    methods (Access = private)
        function wells = fitWellsSequential(obj, wells, wellIDs, voltages, ...
                iv1Data, iv2Data, ivUsed, protocolType, dataType, dataUnits)
            %FITWELLSSEQUENTIAL Fit wells one by one
            
            numWells = length(wellIDs);
            
            for wellIdx = 1:numWells
                % Get data for this well
                if strcmp(ivUsed(wellIdx), 'iv1')
                    data = iv1Data(wellIdx, :);
                else
                    data = iv2Data(wellIdx, :);
                end
                
                % Fit well
                wellFit = obj.fitSingleWell(voltages, data, protocolType, ivUsed(wellIdx));
                
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
                
                % Progress logging
                if mod(wellIdx, 10) == 0 || wellIdx == numWells
                    obj.logger.logInfo(sprintf('Fitting progress: %d/%d wells', wellIdx, numWells));
                end
            end
        end

        
        function wells = fitWellsParallel(obj, wells, wellIDs, voltages, ...
                iv1Data, iv2Data, ivUsed, protocolType, dataType, dataUnits)
            %FITWELLSPARALLEL Fit wells in parallel using parfor
            
            numWells = length(wellIDs);
            config = obj.config; % Copy for parfor
            
            parfor wellIdx = 1:numWells
                % Get data for this well
                if strcmp(ivUsed(wellIdx), 'iv1')
                    data = iv1Data(wellIdx, :);
                else
                    if ~isempty(iv2Data)
                        data = iv2Data(wellIdx, :);
                    else
                        data = iv1Data(wellIdx, :);
                    end
                end
                
                % Fit well (static method for parfor)
                wellFit = NanionBoltzmannFitter.fitSingleWellStatic(...
                    voltages, data, protocolType, ivUsed(wellIdx), config);
                
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
            end
            
            obj.logger.logInfo(sprintf('Parallel fitting complete: %d wells processed', numWells));
        end
    end
    
    methods (Static)
        function wellFit = fitSingleWellStatic(voltages, data, protocolType, ivUsed, config)
            %FITSINGLEWELLSTATIC Static version for parfor compatibility
            
            % Remove NaN values
            validIdx = ~isnan(data) & ~isnan(voltages);
            V_valid = voltages(validIdx);
            D_valid = data(validIdx);
            numValid = sum(validIdx);
            
            % Initialize result
            wellFit = struct(...
                'voltages', voltages, ...
                'data', data, ...
                'validPoints', numValid, ...
                'fitParams', struct('converged', false), ...
                'fitQuality', 'Failed', ...
                'ivUsed', ivUsed);
            
            % Check minimum data requirement
            if numValid < config.boltzmann.minValidPoints
                return;
            end
            
            try
                % Get initial parameters and bounds
                [startPoints, lowerBounds, upperBounds] = BoltzmannModel.getInitialParams(...
                    V_valid, D_valid, protocolType, config);
                
                % Create fittype
                ft = BoltzmannModel.createFitType(protocolType);
                
                % Perform fit
                [fitresult, gof] = fit(V_valid(:), D_valid(:), ft, ...
                    'StartPoint', startPoints, ...
                    'Lower', lowerBounds, ...
                    'Upper', upperBounds);
                
                % Extract parameters
                fitParams = struct(...
                    'V_min', fitresult.V_min, ...
                    'V_max', fitresult.V_max, ...
                    'V_mid', fitresult.V_mid, ...
                    'k', fitresult.k, ...
                    'z_a', BoltzmannModel.calculateGatingCharge(fitresult.k), ...
                    'R2', gof.rsquare, ...
                    'RMSE', gof.rmse, ...
                    'converged', true);
                
                % Assess quality
                quality = FitQualityAssessor.assessQuality(fitParams, gof, protocolType, config);
                
                % Update result
                wellFit.fitParams = fitParams;
                wellFit.fitQuality = quality;
                
            catch
                wellFit.fitQuality = 'Failed';
            end
        end
    end
end
