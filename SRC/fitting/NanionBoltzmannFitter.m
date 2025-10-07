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
            %   Returns fittedData structure with wells array and summary
            
            obj.logger.logInfo('Starting Boltzmann curve fitting...');
            
            numWells = filteredData.numWellsPassed;
            protocolType = filteredData.protocolInfo.type;
            voltages = filteredData.protocolInfo.voltages;
            
            % Determine which IV to use for each well
            ivUsed = filteredData.ivUsedForFiltering;
            
            % Get current data based on protocol
            if strcmp(protocolType, 'activation')
                iv1Currents = filteredData.measurements.iv1.peakCurrent;
                if isfield(filteredData.measurements, 'iv2')
                    iv2Currents = filteredData.measurements.iv2.peakCurrent;
                else
                    iv2Currents = [];
                end
            else % inactivation
                iv1Currents = filteredData.measurements.iv1.inactivationData;
                if isfield(filteredData.measurements, 'iv2')
                    iv2Currents = filteredData.measurements.iv2.inactivationData;
                else
                    iv2Currents = [];
                end
            end
            
            % Initialize wells array
            wells(numWells) = struct(...
                'wellID', '', 'protocol', '', 'ivUsed', '', ...
                'voltages', [], 'currents', [], 'validPoints', 0, ...
                'fitParams', struct(), 'fitQuality', '');
            
            % Fit wells (parallel or sequential)
            if obj.config.boltzmann.useParallel && numWells > 1
                obj.logger.logInfo('Using parallel processing for fitting...');
                wells = obj.fitWellsParallel(wells, filteredData.wellIDs, voltages, ...
                    iv1Currents, iv2Currents, ivUsed, protocolType);
            else
                obj.logger.logInfo('Using sequential processing for fitting...');
                wells = obj.fitWellsSequential(wells, filteredData.wellIDs, voltages, ...
                    iv1Currents, iv2Currents, ivUsed, protocolType);
            end
            
            % Generate summary statistics
            summary = FitQualityAssessor.summarizeFitResults(struct('wells', wells));
            
            % Package results
            fittedData = struct(...
                'wells', wells, ...
                'summary', summary, ...
                'numWells', numWells, ...
                'protocol', protocolType);
            
            obj.logger.logInfo(sprintf('✓ Boltzmann fitting complete: %d Good, %d Acceptable, %d Poor, %d Failed', ...
                summary.fitResults.good, summary.fitResults.acceptable, ...
                summary.fitResults.poor, summary.fitResults.failed));
        end
        
        function wellFit = fitSingleWell(obj, voltages, currents, protocolType, ivUsed)
            %FITSINGLEWELL Fit one well, returns struct with fitParams, gof, quality
            
            % Remove NaN values
            validIdx = ~isnan(currents) & ~isnan(voltages);
            V_valid = voltages(validIdx);
            I_valid = currents(validIdx);
            numValid = sum(validIdx);
            
            % Initialize result structure
            wellFit = struct(...
                'voltages', voltages, ...
                'currents', currents, ...
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
                    V_valid, I_valid, protocolType, obj.config);
                
                % Create fittype
                ft = BoltzmannModel.createFitType(protocolType);
                
                % Perform fit
                [fitresult, gof] = fit(V_valid(:), I_valid(:), ft, ...
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
                iv1Currents, iv2Currents, ivUsed, protocolType)
            %FITWELLSSEQUENTIAL Fit wells one by one
            
            numWells = length(wellIDs);
            
            for wellIdx = 1:numWells
                % Get current data for this well
                if strcmp(ivUsed(wellIdx), 'iv1')
                    currents = iv1Currents(wellIdx, :);
                else
                    currents = iv2Currents(wellIdx, :);
                end
                
                % Fit well
                wellFit = obj.fitSingleWell(voltages, currents, protocolType, ivUsed(wellIdx));
                
                % Store result
                wells(wellIdx).wellID = wellIDs(wellIdx);
                wells(wellIdx).protocol = protocolType;
                wells(wellIdx).ivUsed = wellFit.ivUsed;
                wells(wellIdx).voltages = wellFit.voltages;
                wells(wellIdx).currents = wellFit.currents;
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
                iv1Currents, iv2Currents, ivUsed, protocolType)
            %FITWELLSPARALLEL Fit wells in parallel using parfor
            
            numWells = length(wellIDs);
            config = obj.config; % Copy for parfor
            
            parfor wellIdx = 1:numWells
                % Get current data for this well
                if strcmp(ivUsed(wellIdx), 'iv1')
                    currents = iv1Currents(wellIdx, :);
                else
                    if ~isempty(iv2Currents)
                        currents = iv2Currents(wellIdx, :);
                    else
                        currents = iv1Currents(wellIdx, :);
                    end
                end
                
                % Fit well (static method for parfor)
                wellFit = NanionBoltzmannFitter.fitSingleWellStatic(...
                    voltages, currents, protocolType, ivUsed(wellIdx), config);
                
                % Store result
                wells(wellIdx).wellID = wellIDs(wellIdx);
                wells(wellIdx).protocol = protocolType;
                wells(wellIdx).ivUsed = wellFit.ivUsed;
                wells(wellIdx).voltages = wellFit.voltages;
                wells(wellIdx).currents = wellFit.currents;
                wells(wellIdx).validPoints = wellFit.validPoints;
                wells(wellIdx).fitParams = wellFit.fitParams;
                wells(wellIdx).fitQuality = wellFit.fitQuality;
            end
            
            obj.logger.logInfo(sprintf('Parallel fitting complete: %d wells processed', numWells));
        end
    end
    
    methods (Static)
        function wellFit = fitSingleWellStatic(voltages, currents, protocolType, ivUsed, config)
            %FITSINGLEWELLSTATIC Static version for parfor compatibility
            
            % Remove NaN values
            validIdx = ~isnan(currents) & ~isnan(voltages);
            V_valid = voltages(validIdx);
            I_valid = currents(validIdx);
            numValid = sum(validIdx);
            
            % Initialize result
            wellFit = struct(...
                'voltages', voltages, ...
                'currents', currents, ...
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
                    V_valid, I_valid, protocolType, config);
                
                % Create fittype
                ft = BoltzmannModel.createFitType(protocolType);
                
                % Perform fit
                [fitresult, gof] = fit(V_valid(:), I_valid(:), ft, ...
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
