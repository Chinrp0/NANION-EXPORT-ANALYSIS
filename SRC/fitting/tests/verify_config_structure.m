function verify_config_structure()
    %VERIFY_CONFIG_STRUCTURE Check NanionConfig has all required fields
    
    fprintf('=== CONFIG STRUCTURE VERIFICATION ===\n\n');
    
    try
        config = NanionConfig();
        fprintf('✓ NanionConfig loaded successfully\n\n');
    catch ME
        fprintf('❌ Failed to load NanionConfig: %s\n', ME.message);
        return;
    end
    
    % Check critical fields
    critical = struct();
    critical.analysis = {'numDataPoints', 'nernstPotential', 'temperature'};
    critical.boltzmann = {'corrThreshold', 'acceptableThreshold', 'slopeLimits', ...
        'activationVmidRange', 'inactivationVmidRange', 'minValidPoints', 'useParallel'};
    critical.filters = {'maxSeriesResistance', 'maxSealResistance', 'maxCapacitance', ...
        'outlierThreshold', 'minValidSweeps'};
    
    categories = fieldnames(critical);
    allPassed = true;
    
    for c = 1:length(categories)
        category = categories{c};
        fields = critical.(category);
        
        fprintf('--- %s ---\n', upper(category));
        
        if ~isfield(config.configData, category)
            fprintf('❌ Category "%s" MISSING!\n', category);
            allPassed = false;
            continue;
        end
        
        for f = 1:length(fields)
            fieldName = fields{f};
            
            if isfield(config.configData.(category), fieldName)
                value = config.configData.(category).(fieldName);
                
                % Format value for display
                if isnumeric(value)
                    if length(value) == 1
                        valueStr = sprintf('%.2f', value);
                    else
                        valueStr = sprintf('[%s]', num2str(value, '%.1f '));
                    end
                elseif islogical(value)
                    valueStr = mat2str(value);
                else
                    valueStr = char(value);
                end
                
                fprintf('  ✓ %-25s = %s\n', fieldName, valueStr);
            else
                fprintf('  ❌ %-25s MISSING!\n', fieldName);
                allPassed = false;
            end
        end
        fprintf('\n');
    end
    
    % Check temperature specifically
    fprintf('--- CRITICAL: TEMPERATURE CHECK ---\n');
    if isfield(config.configData.analysis, 'temperature')
        temp = config.configData.analysis.temperature;
        fprintf('✓ Temperature field exists: %.1f°C\n', temp);
        
        if temp < -50 || temp > 50
            fprintf('⚠ WARNING: Temperature value unusual (%.1f°C)\n', temp);
        end
    else
        fprintf('❌ Temperature field MISSING from config.configData.analysis\n');
        fprintf('   This will cause gating charge calculation to use default 25°C\n');
        fprintf('   Add this to NanionConfig.loadDefaultConfig():\n');
        fprintf('   obj.configData.analysis.temperature = 20;  %% or your experimental temp\n');
        allPassed = false;
    end
    
    fprintf('\n--- PARALLEL PROCESSING CHECK ---\n');
    if config.boltzmann.useParallel
        fprintf('⚠ Parallel processing is ENABLED\n');
        fprintf('  This makes debugging harder. Consider setting to false:\n');
        fprintf('  config.updateParameter(''boltzmann'', ''useParallel'', false);\n');
    else
        fprintf('✓ Parallel processing is DISABLED (good for debugging)\n');
    end
    
    fprintf('\n--- FITTING PARAMETER RANGES ---\n');
    fprintf('Slope factor (k): [%.1f, %.1f] mV\n', ...
        config.boltzmann.slopeLimits(1), config.boltzmann.slopeLimits(2));
    fprintf('Activation V_mid: [%.1f, %.1f] mV\n', ...
        config.boltzmann.activationVmidRange(1), config.boltzmann.activationVmidRange(2));
    fprintf('Inactivation V_mid: [%.1f, %.1f] mV\n', ...
        config.boltzmann.inactivationVmidRange(1), config.boltzmann.inactivationVmidRange(2));
    fprintf('Min valid points: %d\n', config.boltzmann.minValidPoints);
    
    fprintf('\n=== VERIFICATION COMPLETE ===\n');
    
    if allPassed
        fprintf('✓ All critical fields present\n');
    else
        fprintf('❌ Some fields missing - see above\n');
    end
end
