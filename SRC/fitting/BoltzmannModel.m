classdef BoltzmannModel
    %BOLTZMANNMODEL Static methods for Boltzmann equation fitting
    %   UPDATED: Fixed overlapping V_min/V_max bounds that caused fitting failures
    
    methods (Static)
        function y = activation(V, V_min, V_max, V_mid, k)
            %ACTIVATION Boltzmann activation equation (RISING sigmoid)
            %   Standard form: negative of (V - V_mid) in exponent
            y = V_min + (V_max - V_min) ./ (1 + exp(-(V - V_mid) ./ k));
        end
        
        function y = inactivation(V, V_min, V_max, V_mid, k)
            %INACTIVATION Boltzmann inactivation equation (FALLING sigmoid)
            %   Standard form: negative of (V_mid - V) in exponent
            y = V_min + (V_max - V_min) ./ (1 + exp(-(V_mid - V) ./ k));
        end
        
        function ft = createFitType(protocolType)
            %CREATEFITTYPE Create MATLAB fittype for protocol
            
            switch lower(protocolType)
                case 'activation'
                    ft = fittype(...
                        'V_min + (V_max - V_min) / (1 + exp(-(V - V_mid) / k))', ...
                        'independent', 'V', ...
                        'dependent', 'I', ...
                        'coefficients', {'V_min', 'V_max', 'V_mid', 'k'});
                    
                case 'inactivation'
                    ft = fittype(...
                        'V_min + (V_max - V_min) / (1 + exp(-(V_mid - V) / k))', ...
                        'independent', 'V', ...
                        'dependent', 'I', ...
                        'coefficients', {'V_min', 'V_max', 'V_mid', 'k'});
                    
                otherwise
                    error('BoltzmannModel:InvalidProtocol', ...
                        'Protocol type must be activation or inactivation');
            end
        end
        
        function [startPoints, lowerBounds, upperBounds] = getInitialParams(voltages, currents, protocolType, config)
            %GETINITIALPARAMS Calculate initial guesses and bounds
            %   FIXED: Prevents V_min/V_max bound overlap by using data midpoint
            
            % Calculate initial guesses from data
            V_min_init = min(currents);
            V_max_init = max(currents);
            V_mid_init = median(voltages);
            k_init = 10;  % mV, typical slope factor
            
            startPoints = [V_min_init, V_max_init, V_mid_init, k_init];
            
            % Get protocol-specific V_mid range
            switch lower(protocolType)
                case 'activation'
                    V_mid_lower = config.boltzmann.activationVmidRange(1);
                    V_mid_upper = config.boltzmann.activationVmidRange(2);
                    
                case 'inactivation'
                    V_mid_lower = config.boltzmann.inactivationVmidRange(1);
                    V_mid_upper = config.boltzmann.inactivationVmidRange(2);
                    
                otherwise
                    error('BoltzmannModel:InvalidProtocol', ...
                        'Protocol type must be activation or inactivation');
            end
            
            % Slope factor (k) bounds
            k_lower = config.boltzmann.slopeLimits(1);
            k_upper = config.boltzmann.slopeLimits(2);
            
            % FIXED BOUNDS: Prevent V_min and V_max overlap
            % Strategy: Allow flexibility but ensure separation
            dataRange = V_max_init - V_min_init;
            
            % V_min bounds: Allow baseline to vary, but not approach V_max
            V_min_lower = V_min_init - 2.0 * abs(dataRange);  % Can go well below minimum
            V_min_upper = V_min_init + 0.2 * abs(dataRange);  % Can rise slightly above minimum
            
            % V_max bounds: Allow saturation to vary, but not approach V_min  
            V_max_lower = V_max_init - 0.2 * abs(dataRange);  % Can drop slightly below maximum
            V_max_upper = V_max_init + 2.0 * abs(dataRange);  % Can rise well above maximum
            
            % CRITICAL: Ensure no overlap (add safety margin)
            safetyMargin = 0.05 * abs(dataRange);
            
            if V_min_upper + safetyMargin >= V_max_lower
                % Bounds would overlap - adjust them with guaranteed separation
                midpoint = (V_min_upper + V_max_lower) / 2;
                V_min_upper = midpoint - safetyMargin;
                V_max_lower = midpoint + safetyMargin;
            end
            
            % Assemble bounds
            lowerBounds = [V_min_lower, V_max_lower, V_mid_lower, k_lower];
            upperBounds = [V_min_upper, V_max_upper, V_mid_upper, k_upper];
        end
        
        function z_a = calculateGatingCharge(k, temperature)
            %CALCULATEGATINGCHARGE Calculate apparent gating charge
            %   z_a = RT/F / k (elementary charges)
            
            if nargin < 2
                temperature = 25;  % Default to 25°C
            end
            
            % Calculate RT/F in millivolts
            T_kelvin = temperature + 273.15;
            RT_over_F = (T_kelvin * 8.314 / 96485) * 1000;  % mV
            
            % Calculate gating charge
            z_a = RT_over_F ./ k;
        end
    end
end
