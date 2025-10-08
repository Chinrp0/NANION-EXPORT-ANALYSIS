function check_normalization()
    %CHECK_NORMALIZATION Verify conductance calculation matches expected values
    %   Compares raw current to conductance for a specific well
    
    fprintf('=== NORMALIZATION CHECKER ===\n\n');
    
    % Initialize
    config = NanionConfig();
    logger = NanionLogger(config);
    detector = NanionFileDetector(logger);
    ioManager = NanionIOManager(config, logger);
    extractor = NanionDataExtractor(config, logger);
    
    % Load file
    [filename, pathname] = uigetfile('*.xlsx', 'Select File');
    if isequal(filename, 0)
        return;
    end
    filePath = fullfile(pathname, filename);
    
    % Process
    protocolInfo = detector.detectProtocol(filePath);
    rawData = ioManager.readFile(filePath);
    parsedData = ioManager.parseData(rawData, protocolInfo);
    extractedData = extractor.extractMeasurements(parsedData);
    filteredData = extractor.applyQualityFilters(extractedData);
    
    % Select well F02
    targetWell = 'F02';
    wellIdx = find(strcmp(filteredData.wellIDs, targetWell), 1);
    
    if isempty(wellIdx)
        fprintf('Well %s not found\n', targetWell);
        return;
    end
    
    fprintf('Well: %s (IV1 only)\n\n', targetWell);
    
    % Get data
    voltages = protocolInfo.voltages;
    
    if strcmp(protocolInfo.type, 'activation')
        % Activation: Compare current and conductance
        current_iv1 = filteredData.measurements.iv1.peakCurrent(wellIdx, :);  % pA
        conductance_iv1 = filteredData.measurements.iv1.conductance(wellIdx, :);  % nS
        
        V_rev = config.nernstPotential;  % mV
        
        fprintf('--- Conductance Calculation Check ---\n');
        fprintf('Formula: G = I / (V - V_rev)\n');
        fprintf('V_rev = %.1f mV\n\n', V_rev);
        
        fprintf('%8s %10s %12s %12s %10s\n', 'V (mV)', 'I (pA)', 'V-Vrev', 'G_calc (nS)', 'G_stored');
        fprintf('%s\n', repmat('-', 1, 70));
        
        validIdx = ~isnan(current_iv1) & ~isnan(conductance_iv1);
        
        for i = find(validIdx)
            V = voltages(i);
            I = current_iv1(i);
            G_stored = conductance_iv1(i);
            
            % Recalculate conductance
            drivingForce = V - V_rev;
            G_calc = I / drivingForce;  % pA/mV = nS
            
            % Check match
            match = abs(G_calc - G_stored) < 1e-6;
            marker = '';
            if ~match
                marker = ' ❌';
            end
            
            fprintf('%8.1f %10.3f %12.3f %12.6f %12.6f%s\n', ...
                V, I, drivingForce, G_calc, G_stored, marker);
        end
        
        fprintf('\n--- Summary Statistics ---\n');
        fprintf('Current (pA):\n');
        fprintf('  Min: %.3f\n', min(current_iv1(validIdx)));
        fprintf('  Max: %.3f\n', max(current_iv1(validIdx)));
        fprintf('  Mean: %.3f\n', mean(current_iv1(validIdx)));
        
        fprintf('\nConductance (nS):\n');
        fprintf('  Min (Gmin): %.6f nS\n', min(conductance_iv1(validIdx)));
        fprintf('  Max (Gmax): %.6f nS\n', max(conductance_iv1(validIdx)));
        fprintf('  Mean: %.6f nS\n', mean(conductance_iv1(validIdx)));
        
        fprintf('\n--- Expected Values (from your previous analysis) ---\n');
        fprintf('Gmin: 0.145838 nS\n');
        fprintf('Gmax: 25.52614 nS\n');
        fprintf('Vmid: -35.51 mV\n');
        fprintf('Correlation: 0.9775\n');
        
        fprintf('\n--- Comparison ---\n');
        Gmin_actual = min(conductance_iv1(validIdx));
        Gmax_actual = max(conductance_iv1(validIdx));
        
        Gmin_match = abs(Gmin_actual - 0.145838) < 0.01;
        Gmax_match = abs(Gmax_actual - 25.52614) < 0.5;
        
        if Gmin_match && Gmax_match
            fprintf('✓ Conductance values match expected!\n');
        else
            fprintf('⚠ Conductance mismatch:\n');
            fprintf('  Gmin: %.6f (expected 0.145838) - diff = %.6f\n', ...
                Gmin_actual, Gmin_actual - 0.145838);
            fprintf('  Gmax: %.6f (expected 25.52614) - diff = %.6f\n', ...
                Gmax_actual, Gmax_actual - 25.52614);
        end
        
    else
        fprintf('Protocol type: %s\n', protocolInfo.type);
        fprintf('Normalization check only implemented for activation\n');
    end
    
    fprintf('\n=== CHECK COMPLETE ===\n');
end
