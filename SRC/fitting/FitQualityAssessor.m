classdef FitQualityAssessor
    %FITQUALITYASSESSOR Quality categorization for Boltzmann fits
    %   UPDATED: Added slope direction validation for activation/inactivation
    
    methods (Static)
        function quality = assessQuality(fitParams, gof, protocolType, config)
            %ASSESSQUALITY Categorize fit quality
            %   Returns: 'Good', 'Acceptable', 'Poor', or 'Failed'
            
            % Check if fit converged
            if ~fitParams.converged
                quality = 'Failed';
                return;
            end
            
            % Check parameter bounds
            boundsOK = FitQualityAssessor.checkParameterBounds(fitParams, protocolType, config);
            
            if ~boundsOK
                quality = 'Poor';
                return;
            end
            
            % Check R² thresholds
            R2 = gof.rsquare;
            
            if R2 >= config.boltzmann.corrThreshold
                quality = 'Good';
            elseif R2 >= config.boltzmann.acceptableThreshold
                quality = 'Acceptable';
            else
                quality = 'Poor';
            end
        end
        
        function isValid = checkParameterBounds(fitParams, protocolType, config)
            %CHECKPARAMETERBOUNDS Verify parameters are physically reasonable
            %   UPDATED: Added slope direction validation
            
            isValid = true;
            
            % Check 1: V_max > V_min (required for both protocols)
            % - Activation: V_max > V_min → curve rises (positive slope)
            % - Inactivation: V_max > V_min → curve falls (negative slope)
            % The equation form determines slope sign, not V_max vs V_min
            if fitParams.V_max <= fitParams.V_min
                isValid = false;
                return;
            end
            
            % Check 2: Slope factor k is within limits
            k = fitParams.k;
            if k < config.boltzmann.slopeLimits(1) || k > config.boltzmann.slopeLimits(2)
                isValid = false;
                return;
            end
            
            % Check 3: V_mid is within protocol-specific range
            V_mid = fitParams.V_mid;
            
            switch lower(protocolType)
                case 'activation'
                    V_mid_range = config.boltzmann.activationVmidRange;
                    
                    % Additional check: V_mid must be negative for activation
                    if V_mid >= 0
                        isValid = false;
                        return;
                    end
                    
                case 'inactivation'
                    V_mid_range = config.boltzmann.inactivationVmidRange;
                    
                otherwise
                    error('FitQualityAssessor:InvalidProtocol', ...
                        'Protocol type must be activation or inactivation');
            end
            
            if V_mid < V_mid_range(1) || V_mid > V_mid_range(2)
                isValid = false;
                return;
            end
        end
        
        function summary = summarizeFitResults(fittedData)
            %SUMMARIZEFITRESULTS Generate summary statistics for fitted data
            
            if isempty(fittedData.wells)
                summary = struct(...
                    'totalWells', 0, ...
                    'fitResults', struct('good', 0, 'acceptable', 0, 'poor', 0, 'failed', 0), ...
                    'parameterStats', struct());
                return;
            end
            
            % Count fit quality categories
            qualities = {fittedData.wells.fitQuality};
            numGood = sum(strcmp(qualities, 'Good'));
            numAcceptable = sum(strcmp(qualities, 'Acceptable'));
            numPoor = sum(strcmp(qualities, 'Poor'));
            numFailed = sum(strcmp(qualities, 'Failed'));
            
            % Calculate statistics for Good + Acceptable fits only
            goodOrAcceptable = strcmp(qualities, 'Good') | strcmp(qualities, 'Acceptable');
            
            if sum(goodOrAcceptable) > 0
                % Extract parameters
                V_mids = arrayfun(@(x) x.fitParams.V_mid, fittedData.wells(goodOrAcceptable));
                ks = arrayfun(@(x) x.fitParams.k, fittedData.wells(goodOrAcceptable));
                R2s = arrayfun(@(x) x.fitParams.R2, fittedData.wells(goodOrAcceptable));
                
                parameterStats = struct(...
                    'V_mid_mean', mean(V_mids), ...
                    'V_mid_std', std(V_mids), ...
                    'V_mid_median', median(V_mids), ...
                    'V_mid_range', [min(V_mids), max(V_mids)], ...
                    'k_mean', mean(ks), ...
                    'k_std', std(ks), ...
                    'k_median', median(ks), ...
                    'R2_mean', mean(R2s), ...
                    'R2_median', median(R2s));
            else
                parameterStats = struct(...
                    'V_mid_mean', NaN, 'V_mid_std', NaN, 'V_mid_median', NaN, ...
                    'V_mid_range', [NaN, NaN], 'k_mean', NaN, 'k_std', NaN, ...
                    'k_median', NaN, 'R2_mean', NaN, 'R2_median', NaN);
            end
            
            summary = struct(...
                'totalWells', length(fittedData.wells), ...
                'fitResults', struct(...
                    'good', numGood, ...
                    'acceptable', numAcceptable, ...
                    'poor', numPoor, ...
                    'failed', numFailed), ...
                'parameterStats', parameterStats);
        end
    end
end
