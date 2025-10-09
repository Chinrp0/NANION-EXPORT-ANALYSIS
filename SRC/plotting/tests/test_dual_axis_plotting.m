function test_dual_axis_plotting()
    %TEST_DUAL_AXIS_PLOTTING Test the new dual y-axis plotter with Boltzmann fits
    %   Plots IV1 and IV2 with fitted curves
    
    fprintf('=== TESTING DUAL Y-AXIS PLOTTER ===\n\n');
    
    % Initialize pipeline
    config = NanionConfig();
    logger = NanionLogger(config);
    detector = NanionFileDetector(logger);
    ioManager = NanionIOManager(config, logger);
    extractor = NanionDataExtractor(config, logger);
    fitter = NanionBoltzmannFitter(config, logger);
    plotter = NanionBoltzmannPlotter(config, logger);
    
    % Select file
    [filename, pathname] = uigetfile('*.xlsx', 'Select Nanion File');
    if isequal(filename, 0)
        return;
    end
    filePath = fullfile(pathname, filename);
    
    % Process data
    fprintf('Processing: %s\n', filename);
    protocolInfo = detector.detectProtocol(filePath);
    rawData = ioManager.readFile(filePath);
    parsedData = ioManager.parseData(rawData, protocolInfo);
    extractedData = extractor.extractMeasurements(parsedData);
    filteredData = extractor.applyQualityFilters(extractedData);
    
    fprintf('Wells passed filtering: %d\n\n', filteredData.numWellsPassed);
    
    if filteredData.numWellsPassed == 0
        fprintf('No wells passed filtering. Cannot plot.\n');
        return;
    end
    
    % Fit Boltzmann curves for IV1 and IV2
    fprintf('Fitting Boltzmann curves to IV1 and IV2...\n');
    
    % Create separate filtered data for IV1 and IV2
    filteredData_iv1 = filteredData;
    filteredData_iv1.ivUsedForFiltering(:) = "iv1";  % Force IV1
    
    filteredData_iv2 = filteredData;
    filteredData_iv2.ivUsedForFiltering(:) = "iv2";  % Force IV2
    
    % Fit IV1
    fprintf('  Fitting IV1 for all wells...\n');
    try
        fittedData_iv1 = fitter.fitBoltzmann(filteredData_iv1);
        iv1_success = sum(strcmp({fittedData_iv1.wells.fitQuality}, 'Good') | ...
                         strcmp({fittedData_iv1.wells.fitQuality}, 'Acceptable'));
        fprintf('    IV1: %d/%d wells fitted successfully\n', iv1_success, filteredData.numWellsPassed);
    catch ME
        fprintf('    IV1 fitting failed: %s\n', ME.message);
        fittedData_iv1 = [];
    end
    
    % Fit IV2
    fprintf('  Fitting IV2 for all wells...\n');
    if isfield(filteredData.measurements, 'iv2')
        try
            fittedData_iv2 = fitter.fitBoltzmann(filteredData_iv2);
            iv2_success = sum(strcmp({fittedData_iv2.wells.fitQuality}, 'Good') | ...
                             strcmp({fittedData_iv2.wells.fitQuality}, 'Acceptable'));
            fprintf('    IV2: %d/%d wells fitted successfully\n', iv2_success, filteredData.numWellsPassed);
        catch ME
            fprintf('    IV2 fitting failed: %s\n', ME.message);
            fittedData_iv2 = [];
        end
    else
        fittedData_iv2 = [];
    end
    
    % Plot first 3 wells
    numToPlot = min(3, filteredData.numWellsPassed);
    fprintf('\nGenerating plots for first %d wells...\n', numToPlot);
    
    for i = 1:numToPlot
        wellID = filteredData.wellIDs(i);
        
        % Check protocol type and extract appropriate data
        if strcmp(protocolInfo.type, 'activation')
            % Extract IV1 data (activation)
            iv1Data = struct(...
                'conductance', filteredData.measurements.iv1.conductance(i, :), ...
                'peakCurrent', filteredData.measurements.iv1.peakCurrent(i, :));
            
            % Extract IV2 data (activation)
            if isfield(filteredData.measurements, 'iv2')
                iv2Data = struct(...
                    'conductance', filteredData.measurements.iv2.conductance(i, :), ...
                    'peakCurrent', filteredData.measurements.iv2.peakCurrent(i, :));
            else
                iv2Data = [];
            end
            
            % Get fit results and generate fitted curves
            iv1Fit = [];
            if ~isempty(fittedData_iv1)
                wellFit = fittedData_iv1.wells(i);
                if wellFit.fitParams.converged
                    fittedCurve = generateFittedCurve(protocolInfo.voltages, ...
                        wellFit.fitParams, protocolInfo.type);
                    iv1Fit = struct(...
                        'params', wellFit.fitParams, ...
                        'quality', struct('rsquared', wellFit.fitParams.R2), ...
                        'fittedCurve', fittedCurve);
                end
            end
            
            iv2Fit = [];
            if ~isempty(fittedData_iv2)
                wellFit = fittedData_iv2.wells(i);
                if wellFit.fitParams.converged
                    fittedCurve = generateFittedCurve(protocolInfo.voltages, ...
                        wellFit.fitParams, protocolInfo.type);
                    iv2Fit = struct(...
                        'params', wellFit.fitParams, ...
                        'quality', struct('rsquared', wellFit.fitParams.R2), ...
                        'fittedCurve', fittedCurve);
                end
            end
            
            % Generate activation plot
            plotter.plotActivationDualAxis(wellID, protocolInfo.voltages, ...
                iv1Data, iv2Data, iv1Fit, iv2Fit);
            
        else  % inactivation
            % Extract IV1 data (inactivation)
            iv1Data = struct(...
                'inactivationData', filteredData.measurements.iv1.inactivationData(i, :), ...
                'activationData', filteredData.measurements.iv1.activationData(i, :));
            
            % Extract IV2 data (inactivation)
            if isfield(filteredData.measurements, 'iv2')
                iv2Data = struct(...
                    'inactivationData', filteredData.measurements.iv2.inactivationData(i, :), ...
                    'activationData', filteredData.measurements.iv2.activationData(i, :));
            else
                iv2Data = [];
            end
            
            % Get fit results (same structure as activation)
            iv1Fit = [];
            if ~isempty(fittedData_iv1)
                wellFit = fittedData_iv1.wells(i);
                if wellFit.fitParams.converged
                    fittedCurve = generateFittedCurve(protocolInfo.voltages, ...
                        wellFit.fitParams, protocolInfo.type);
                    iv1Fit = struct(...
                        'params', wellFit.fitParams, ...
                        'quality', struct('rsquared', wellFit.fitParams.R2), ...
                        'fittedCurve', fittedCurve);
                end
            end
            
            iv2Fit = [];
            if ~isempty(fittedData_iv2)
                wellFit = fittedData_iv2.wells(i);
                if wellFit.fitParams.converged
                    fittedCurve = generateFittedCurve(protocolInfo.voltages, ...
                        wellFit.fitParams, protocolInfo.type);
                    iv2Fit = struct(...
                        'params', wellFit.fitParams, ...
                        'quality', struct('rsquared', wellFit.fitParams.R2), ...
                        'fittedCurve', fittedCurve);
                end
            end
            
            % Generate inactivation plot
            plotter.plotInactivationDualPanel(wellID, protocolInfo.voltages, ...
                iv1Data, iv2Data, iv1Fit, iv2Fit);
        end
        
        fprintf('  ✓ Plotted well %s', wellID);
        if ~isempty(iv1Fit)
            fprintf(' (IV1: V_mid=%.1f mV, R²=%.3f)', ...
                iv1Fit.params.V_mid, iv1Fit.params.R2);
        end
        if ~isempty(iv2Fit)
            fprintf(' (IV2: V_mid=%.1f mV, R²=%.3f)', ...
                iv2Fit.params.V_mid, iv2Fit.params.R2);
        end
        fprintf('\n');
    end
    
    fprintf('\n=== PLOTTING COMPLETE ===\n');
    fprintf('Check the generated figures!\n');
end

function fittedCurve = generateFittedCurve(voltages, fitParams, protocolType)
    %GENERATEFITTEDCURVE Generate fitted curve from Boltzmann parameters
    
    V_min = fitParams.V_min;
    V_max = fitParams.V_max;
    V_mid = fitParams.V_mid;
    k = fitParams.k;
    
    if strcmp(protocolType, 'activation')
        % Activation: rising sigmoid
        fittedCurve = V_min + (V_max - V_min) ./ (1 + exp(-(voltages - V_mid) ./ k));
    else
        % Inactivation: falling sigmoid
        fittedCurve = V_min + (V_max - V_mid) ./ (1 + exp(-(V_mid - voltages) ./ k));
    end
end
