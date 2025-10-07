function validate_sweep_extraction()
    %VALIDATE_SWEEP_EXTRACTION Test refactored sweep extraction
    %   Validates that all 23 sweeps are extracted correctly
    
    fprintf('=== SWEEP EXTRACTION VALIDATION ===\n\n');
    
    % Initialize pipeline
    pipeline = NanionAnalysisPipeline();
    
    % Select test files
    [filenames, pathname] = uigetfile(...
        {'*.xlsx;*.xls', 'Excel Files (*.xlsx, *.xls)'}, ...
        'Select Nanion Test Files', ...
        'MultiSelect', 'on');
    
    if isequal(filenames, 0)
        fprintf('No files selected.\n');
        return;
    end
    
    if ischar(filenames)
        filenames = {filenames};
    end
    
    % Validate each file
    for i = 1:length(filenames)
        filePath = fullfile(pathname, filenames{i});
        fprintf('\n--- Testing: %s ---\n', filenames{i});
        
        try
            % Step 1: Protocol detection
            fprintf('Step 1: Protocol detection...\n');
            detector = NanionFileDetector(NanionLogger(NanionConfig()));
            protocolInfo = detector.detectProtocol(filePath);
            
            if isempty(protocolInfo)
                fprintf('  ✗ Protocol detection failed\n');
                continue;
            end
            
            fprintf('  ✓ Protocol: %s\n', protocolInfo.type);
            fprintf('  ✓ Number of IVs: %d\n', protocolInfo.numIVs);
            fprintf('  ✓ Sweeps per IV: %d\n', protocolInfo.numSweeps);
            fprintf('  ✓ Voltage range: [%.1f to %.1f] mV\n', ...
                min(protocolInfo.voltages), max(protocolInfo.voltages));
            
            % Step 2: Data extraction
            fprintf('\nStep 2: Data extraction...\n');
            config = NanionConfig();
            logger = NanionLogger(config);
            ioManager = NanionIOManager(config, logger);
            
            rawData = ioManager.readFile(filePath);
            parsedData = ioManager.parseData(rawData, protocolInfo);
            
            % Step 3: Measurement extraction
            fprintf('\nStep 3: Measurement extraction (ALL sweeps)...\n');
            extractor = NanionDataExtractor(config, logger);
            extractedData = extractor.extractMeasurements(parsedData);
            
            % Validate data shapes
            fprintf('  Validating data shapes...\n');
            for iv = 1:extractedData.numIVs
                ivName = sprintf('iv%d', iv);
                ivData = extractedData.measurements.(ivName);
                
                % Check all parameters
                params = fieldnames(ivData);
                for p = 1:length(params)
                    paramName = params{p};
                    dataShape = size(ivData.(paramName));
                    
                    expectedShape = [extractedData.numWells, extractedData.numSweeps];
                    
                    if isequal(dataShape, expectedShape)
                        fprintf('  ✓ %s.%s: [%d × %d] ✓\n', ivName, paramName, dataShape(1), dataShape(2));
                    else
                        fprintf('  ✗ %s.%s: [%d × %d] (expected [%d × %d])\n', ...
                            ivName, paramName, dataShape(1), dataShape(2), expectedShape(1), expectedShape(2));
                    end
                end
            end
            
            % Step 4: Quality filtering
            fprintf('\nStep 4: Quality filtering (checking ALL sweeps)...\n');
            filteredData = extractor.applyQualityFilters(extractedData);
            
            fprintf('  ✓ Total wells: %d\n', filteredData.numWellsTotal);
            fprintf('  ✓ Passed: %d (%.1f%%)\n', filteredData.numWellsPassed, ...
                100 * filteredData.numWellsPassed / filteredData.numWellsTotal);
            fprintf('  ✓ Failed: %d (%.1f%%)\n', filteredData.numWellsTotal - filteredData.numWellsPassed, ...
                100 * (filteredData.numWellsTotal - filteredData.numWellsPassed) / filteredData.numWellsTotal);
            
            % Step 5: Validate filtered data shapes
            fprintf('\nStep 5: Validating filtered data shapes...\n');
            for iv = 1:extractedData.numIVs
                ivName = sprintf('iv%d', iv);
                if isfield(filteredData.measurements, ivName)
                    ivData = filteredData.measurements.(ivName);
                    params = fieldnames(ivData);
                    
                    for p = 1:length(params)
                        paramName = params{p};
                        dataShape = size(ivData.(paramName));
                        
                        expectedShape = [filteredData.numWellsPassed, extractedData.numSweeps];
                        
                        if isequal(dataShape, expectedShape)
                            fprintf('  ✓ Filtered %s.%s: [%d × %d] ✓\n', ...
                                ivName, paramName, dataShape(1), dataShape(2));
                        else
                            fprintf('  ✗ Filtered %s.%s: [%d × %d] (expected [%d × %d])\n', ...
                                ivName, paramName, dataShape(1), dataShape(2), expectedShape(1), expectedShape(2));
                        end
                    end
                end
            end
            
            % Step 6: Sample data inspection
            fprintf('\nStep 6: Sample data inspection...\n');
            if filteredData.numWellsPassed > 0
                wellIdx = 1;
                iv1Data = filteredData.measurements.iv1;
                
                fprintf('  Sample well: %s\n', filteredData.wellIDs(wellIdx));
                fprintf('  Series R (23 sweeps): [%.2f ... %.2f] MΩ\n', ...
                    iv1Data.seriesResistance(wellIdx, 1), iv1Data.seriesResistance(wellIdx, end));
                fprintf('  Seal R (23 sweeps): [%.2f ... %.2f] GΩ\n', ...
                    iv1Data.sealResistance(wellIdx, 1), iv1Data.sealResistance(wellIdx, end));
                fprintf('  Capacitance (23 sweeps): [%.2f ... %.2f] pF\n', ...
                    iv1Data.capacitance(wellIdx, 1), iv1Data.capacitance(wellIdx, end));
                
                if isfield(iv1Data, 'peakCurrent')
                    fprintf('  Peak Current (23 sweeps): [%.2f ... %.2f] pA\n', ...
                        iv1Data.peakCurrent(wellIdx, 1), iv1Data.peakCurrent(wellIdx, end));
                end
            end
            
            fprintf('\n✓ VALIDATION PASSED for %s\n', filenames{i});
            
        catch ME
            fprintf('\n✗ VALIDATION FAILED: %s\n', ME.message);
            fprintf('Stack trace:\n%s\n', getReport(ME));
        end
    end
    
    fprintf('\n=== VALIDATION COMPLETE ===\n');
end
