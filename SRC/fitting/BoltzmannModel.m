classdef BoltzmannModel
    %BOLTZMANNMODEL Static methods for Boltzmann equation fitting
    %   Provides equation definitions and fit setup for channel kinetics
    
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
        
        function z_a = calculateGatingCharge(k)
            %CALCULATEGATINGCHARGE Calculate apparent gating charge
            %   z_a = 25.7/k at 25°C
            
            z_a = 25.7 ./ k;
        end
    end
end
