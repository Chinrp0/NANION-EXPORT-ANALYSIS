classdef BoltzmannModel
    %BOLTZMANNMODEL Static methods for Boltzmann equation fitting
    %   Provides equation definitions and fit setup for channel kinetics
    %   UPDATED: Temperature-dependent gating charge calculation
    
    methods (Static)
        function y = activation(V, V_min, V_max, V_mid, k)
            %ACTIVATION Boltzmann activation equation
            %   f(V) = V_min + (V_max - V_min) / (1 + exp((V - V_mid) / k))
            
            y = V_min + (V_max - V_min) ./ (1 + exp((V - V_mid) ./ k));
        end
        
        function y = inactivation(V, V_min, V_max, V_mid, k)
            %INACTIVATION Boltzmann inactivation equation
            %   f(V) = V_min + (V_max - V_min) / (1 + exp((V_mid - V) / k))
            
            y = V_min + (V_max - V_min) ./ (1 + exp((V_mid - V) ./ k));
        end
        
        function ft = createFitType(protocolType)
            %CREATEFITTYPE Create MATLAB fittype for protocol
            
            switch lower(protocolType)
                case 'activation'
                    ft = fittype(...
                        'V_min + (V_max - V_min) / (1 + exp((V - V_mid) / k))', ...
                        'independent', 'V', ...
                        'dependent', 'I', ...
                        'coefficients', {'V_min', 'V_max', 'V_mid', 'k'});
                    
                case 'inactivation'
                    ft = fittype(...
                        'V_min + (V_max - V_min) / (1 + exp((V_mid - V) / k))', ...
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
            %   Returns: [startPoints, lowerBounds, upperBounds]
            
            % Calculate initial guesses from data
            V_min_init = min(currents);
            V_max_init = max(currents);
            V_mid_init = median(voltages);
            k_init = 10;  % mV, typical slope factor
            
            startPoints = [V_min_init, V_max_init, V_mid_init, k_init];
            
            % Set bounds based on protocol type
            switch lower(protocolType)
                case 'activation'
                    % V_mid range for activation
                    V_mid_lower = config.boltzmann.activationVmidRange(1);
                    V_mid_upper = config.boltzmann.activationVmidRange(2);
                    
                case 'inactivation'
                    % V_mid range for inactivation
                    V_mid_lower = config.boltzmann.inactivationVmidRange(1);
                    V_mid_upper = config.boltzmann.inactivationVmidRange(2);
                    
                otherwise
                    error('BoltzmannModel:InvalidProtocol', ...
                        'Protocol type must be activation or inactivation');
            end
            
            % Slope factor (k) bounds
            k_lower = config.boltzmann.slopeLimits(1);
            k_upper = config.boltzmann.slopeLimits(2);
            
            % V_min and V_max bounds: allow flexibility around data range
            dataRange = V_max_init - V_min_init;
            V_min_lower = V_min_init - abs(dataRange);
            V_min_upper = V_min_init + abs(dataRange);
            V_max_lower = V_max_init - abs(dataRange);
            V_max_upper = V_max_init + abs(dataRange);
            
            % Assemble bounds
            lowerBounds = [V_min_lower, V_max_lower, V_mid_lower, k_lower];
            upperBounds = [V_min_upper, V_max_upper, V_mid_upper, k_upper];
        end
        
        function z_a = calculateGatingCharge(k, temperature)
            %CALCULATEGATINGCHARGE Calculate apparent gating charge
            %   z_a = RT/F / k
            %   
            %   Inputs:
            %       k - Slope factor(s) in mV (scalar or array)
            %       temperature - Temperature in °C (optional, default = 25°C)
            %   
            %   Output:
            %       z_a - Apparent gating charge (elementary charges)
            %   
            %   Physics:
            %       At T=20°C: RT/F = 24.9 mV, so z_a ≈ 24.9/k
            %       At T=25°C: RT/F = 25.7 mV, so z_a ≈ 25.7/k
            %   
            %   Reference: Matches Origin Lab manual fitting equation
            %       f(V) = V_min + (V_max-V_min)/(1 + e^((z_a*F/RT)*(V-V_mid)))
            
            if nargin < 2
                temperature = 25;  % Default to 25°C
            end
            
            % Calculate RT/F in millivolts
            % R = 8.314 J/(mol·K) - gas constant
            % F = 96485 C/mol - Faraday constant
            % T in Kelvin = T_celsius + 273.15
            % RT/F in mV = (T_K * R / F) * 1000
            
            T_kelvin = temperature + 273.15;
            RT_over_F = (T_kelvin * 8.314 / 96485) * 1000;  % mV
            
            % Calculate gating charge: z_a = RT/F / k
            z_a = RT_over_F ./ k;
        end
    end
end
