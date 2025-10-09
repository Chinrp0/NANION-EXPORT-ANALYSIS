function plot_specific_wells()
    %PLOT_SPECIFIC_WELLS Plot user-specified wells with Boltzmann fits
    
    fprintf('=== SPECIFIC WELL PLOTTER ===\n\n');
    
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
    fprintf('Processing: %s\n\n', filename);
    protocolInfo = detector.detectProtocol(filePath);
    rawData = ioManager.readFile(filePath);
    parsedData = ioManager.parseData(rawData, protocolInfo);
    extractedData = extractor.extractMeasurements(parsedData);
    filteredData = extractor.applyQualityFilters(extractedData);
    
    fprintf('Wells passed filtering: %d\n', filteredData.numWellsPassed);
    fprintf('Available wells: %s\n\n', strjoin(filteredData.wellIDs, ', '));
    
    % Ask user which wells to plot
    wellsToPlot = input('Enter well IDs to plot (e.g., ["E01", "F02", "G02"]): ');
    
    if isempty(wellsToPlot)
        fprintf('No wells specified. Exiting.\n');
        return;
    end
    
    % Convert to string array if needed
    if ischar(wellsToPlot)
        wellsToPlot = string(wellsToPlot);
    end
    
    % Fit all wells first
    fprintf('\nFitting Boltzmann curves...\n');
    
    % Force IV1 for all wells
    filteredData_iv1 = filteredData;
    filteredData_iv1.ivUsedForFiltering(:) = "iv1";
    fittedData_iv1 = fitter.fitBoltzmann(filteredData_iv1);
    
    % Force IV2 for all wells
    filteredData_iv2 = filteredData;
    filteredData_iv2.ivUsedForFiltering(:) = "iv2";
    if isfield(filteredData.measurements, 'iv2')
        fittedData_iv2 = fitter.fitBoltzmann(filteredData_iv2);
    else
        fittedData_iv2 = [];
    end
    
    fprintf('Fitting complete!\n\n');
    
    % Plot each requested well
    for i = 1:length(wellsToPlot)
        wellID = wellsToPlot(i);
        
        % Find well index
        wellIdx = find(strcmpi(filteredData.wellIDs, wellID), 1);
        
        if isempty(wellIdx)
            fprintf('❌ Well %s not found in filtered data (may have been rejected by QC)\n', wellID);
            continue;
        end
        
        fprintf('Plotting well %s (index %d)...\n', wellID, wellIdx);
        
        % Extract data based on protocol type
        if strcmp(protocolInfo.type, 'activation')
            % Activation data
            iv1Data = struct(...
                'conductance', filteredData.measurements.iv1.conductance(wellIdx, :), ...
                'peakCurrent', filteredData.measurements.iv1.peakCurrent(wellIdx, :));
            
            if isfield(filteredData.measurements, 'iv2')
                iv2Data = struct(...
                    'conductance', filteredData.measurements.iv2.conductance(wellIdx, :), ...
                    'peakCurrent', filteredData.measurements.iv2.peakCurrent(wellIdx, :));
            else
                iv2Data = [];
            end
            
            % Get fits
            iv1Fit = extractFitResult(fittedData_iv1, wellIdx, protocolInfo);
            iv2Fit = extractFitResult(fittedData_iv2, wellIdx, protocolInfo);
            
            % Plot
            plotter.plotActivationDualAxis(wellID, protocolInfo.voltages, ...
                iv1Data, iv2Data, iv1Fit, iv2Fit);
            
        else  % inactivation
            % Inactivation data
            iv1Data = struct(...
                'inactivationData', filteredData.measurements.iv1.inactivationData(wellIdx, :), ...
                'activationData', filteredData.measurements.iv1.activationData(wellIdx, :));
            
            if isfield(filteredData.measurements, 'iv2')
                iv2Data = struct(...
                    'inactivationData', filteredData.measurements.iv2.inactivationData(wellIdx, :), ...
                    'activationData', filteredData.measurements.iv2.activationData(wellIdx, :));
            else
                iv2Data = [];
            end
            
            % Get fits
            iv1Fit = extractFitResult(fittedData_iv1, wellIdx, protocolInfo);
            iv2Fit = extractFitResult(fittedData_iv2, wellIdx, protocolInfo);
            
            % Plot
            plotter.plotInactivationDualPanel(wellID, protocolInfo.voltages, ...
                iv1Data, iv2Data, iv1Fit, iv2Fit);
        end
        
        % Print fit quality
        if ~isempty(iv1Fit)
            fprintf('  IV1: V_mid=%.1f mV, k=%.1f, R²=%.3f\n', ...
                iv1Fit.params.V_mid, iv1Fit.params.k, iv1Fit.params.R2);
        end
        if ~isempty(iv2Fit)
            fprintf('  IV2: V_mid=%.1f mV, k=%.1f, R²=%.3f\n', ...
                iv2Fit.params.V_mid, iv2Fit.params.k, iv2Fit.params.R2);
        end
    end
    
    fprintf('\n=== PLOTTING COMPLETE ===\n');
end

function fitResult = extractFitResult(fittedData, wellIdx, protocolInfo)
    %EXTRACTFITRESULT Extract fit result for a specific well
    
    if isempty(fittedData) || wellIdx > length(fittedData.wells)
        fitResult = [];
        return;
    end
    
    wellFit = fittedData.wells(wellIdx);
    
    if ~wellFit.fitParams.converged
        fitResult = [];
        return;
    end
    
    % Generate fitted curve
    voltages = protocolInfo.voltages;
    V_min = wellFit.fitParams.V_min;
    V_max = wellFit.fitParams.V_max;
    V_mid = wellFit.fitParams.V_mid;
    k = wellFit.fitParams.k;
    
    if strcmp(protocolInfo.type, 'activation')
        fittedCurve = V_min + (V_max - V_min) ./ (1 + exp(-(voltages - V_mid) ./ k));
    else
        fittedCurve = V_min + (V_max - V_min) ./ (1 + exp(-(V_mid - voltages) ./ k));
    end
    
    fitResult = struct(...
        'params', wellFit.fitParams, ...
        'quality', struct('rsquared', wellFit.fitParams.R2), ...
        'fittedCurve', fittedCurve);
end
