function test_dual_axis_plotting()
    %TEST_DUAL_AXIS_PLOTTING Test the new dual y-axis plotter
    %   Plots IV1 and IV2 with Boltzmann fits
    
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
    fitResults = struct('iv1', [], 'iv2', []);
    numWells = filteredData.numWellsPassed;
    
    for i = 1:numWells
        wellID = filteredData.wellIDs(i);
        fprintf('  Fitting well %s...', wellID);
        
        % Fit IV1
        try
            iv1_conductance = filteredData.measurements.iv1.conductance(i, :);
            iv1Fit = fitter.fitBoltzmannCurve(protocolInfo.voltages, iv1_conductance, 'activation');
            fitResults(i).iv1 = iv1Fit;
            fprintf(' IV1: R²=%.3f', iv1Fit.quality.rsquared);
        catch ME
            fitResults(i).iv1 = [];
            fprintf(' IV1: FAILED');
        end
        
        % Fit IV2 (if available)
        if isfield(filteredData.measurements, 'iv2')
            try
                iv2_conductance = filteredData.measurements.iv2.conductance(i, :);
                iv2Fit = fitter.fitBoltzmannCurve(protocolInfo.voltages, iv2_conductance, 'activation');
                fitResults(i).iv2 = iv2Fit;
                fprintf(', IV2: R²=%.3f\n', iv2Fit.quality.rsquared);
            catch ME
                fitResults(i).iv2 = [];
                fprintf(', IV2: FAILED\n');
            end
        else
            fprintf('\n');
        end
    end
    
    % Plot first 3 wells as examples
    numToPlot = min(3, numWells);
    fprintf('\nGenerating plots for first %d wells...\n', numToPlot);
    
    for i = 1:numToPlot
        wellID = filteredData.wellIDs(i);
        
        % Extract IV1 data
        iv1Data = struct(...
            'conductance', filteredData.measurements.iv1.conductance(i, :), ...
            'peakCurrent', filteredData.measurements.iv1.peakCurrent(i, :));
        
        % Extract IV2 data (if available)
        if isfield(filteredData.measurements, 'iv2')
            iv2Data = struct(...
                'conductance', filteredData.measurements.iv2.conductance(i, :), ...
                'peakCurrent', filteredData.measurements.iv2.peakCurrent(i, :));
        else
            iv2Data = [];
        end
        
        % Get fits
        iv1Fit = fitResults(i).iv1;
        if isfield(fitResults(i), 'iv2')
            iv2Fit = fitResults(i).iv2;
        else
            iv2Fit = [];
        end
        
        % Generate plot
        plotter.plotActivationDualAxis(wellID, protocolInfo.voltages, ...
            iv1Data, iv2Data, iv1Fit, iv2Fit);
        
        fprintf('  ✓ Plotted well %s\n', wellID);
    end
    
    fprintf('\n=== PLOTTING COMPLETE ===\n');
    fprintf('Check the generated figures!\n');
end
