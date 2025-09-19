function phase1_demo()
    %PHASE1_DEMO Demonstrate Phase 1 infrastructure components
    %   Shows file validation, protocol detection, and basic data reading
    
    fprintf('=== NANION ANALYSIS PHASE 1 DEMO ===\n\n');
    
    %% 1. Initialize Configuration
    fprintf('1. Setting up configuration...\n');
    
    % You can create default config or load from file
    config = NanionConfig();  % Uses defaults
    % config = NanionConfig('configs/dev_config.json');  % From file
    
    fprintf('Configuration loaded:\n%s\n\n', config.getSummary());
    
    %% 2. Create Pipeline
    fprintf('2. Initializing pipeline...\n');
    
    pipeline = NanionAnalysisPipeline();
    fprintf('Pipeline initialized successfully\n\n');
    
    %% 3. File Selection and Validation
    fprintf('3. Select files for analysis...\n');
    
    % Interactive file selection
    [filenames, pathname] = uigetfile(...
        {'*.xlsx;*.xls', 'Excel Files (*.xlsx, *.xls)'}, ...
        'Select Nanion Excel Files for Phase 1 Demo', ...
        'MultiSelect', 'on');
    
    if isequal(filenames, 0)
        fprintf('No files selected. Demo terminated.\n');
        return;
    end
    
    % Convert to cell array if single file
    if ischar(filenames)
        filenames = {filenames};
    end
    
    % Create full file paths
    filePaths = cellfun(@(f) fullfile(pathname, f), filenames, 'UniformOutput', false);
    
    fprintf('Selected %d files for analysis\n\n', length(filePaths));
    
    %% 4. Protocol Detection Demo
    fprintf('4. Protocol detection...\n');
    
    fileDetector = NanionFileDetector(NanionLogger(config));
    
    protocolResults = cell(length(filePaths), 1);
    
    for i = 1:length(filePaths)
        fprintf('  Analyzing file %d: %s\n', i, filenames{i});
        
        protocolInfo = fileDetector.detectProtocol(filePaths{i});
        
        if ~isempty(protocolInfo)
            fprintf('    ✓ Protocol: %s (%d IVs)\n', ...
                protocolInfo.type, protocolInfo.numIVs);
            fprintf('    ✓ Column pattern: every %d columns\n', ...
                protocolInfo.columnMapping.columnPattern);
        else
            fprintf('    ✗ Protocol detection failed\n');
        end
        
        protocolResults{i} = protocolInfo;
    end
    
    fprintf('\n');
    
    %% 5. File Reading Demo
    fprintf('5. File reading demonstration...\n');
    
    ioManager = NanionIOManager(config, NanionLogger(config));
    
    % Read first file as demo
    if ~isempty(protocolResults{1})
        fprintf('  Reading first file: %s\n', filenames{1});
        
        try
            % Read raw data
            rawData = ioManager.readFile(filePaths{1});
            
            % Parse data
            parsedData = ioManager.parseData(rawData, protocolResults{1});
            
            fprintf('    ✓ Data shape: %dx%d\n', size(parsedData.dataTable));
            fprintf('    ✓ Header rows: %d\n', parsedData.headerRows);
            fprintf('    ✓ Data samples: %d\n', parsedData.headerRows);
            
            % Show sample of headers
            headers = parsedData.dataTable.Properties.VariableNames;
            fprintf('    ✓ First 10 headers: %s...\n', strjoin(headers(1:min(10, length(headers))), ', '));
            
        catch ME
            fprintf('    ✗ Reading failed: %s\n', ME.message);
        end
    end
    
    fprintf('\n');
    
    %% 6. Configuration Management Demo
    fprintf('6. Configuration management...\n');
    
    % Show parameter access
    fprintf('  Current filter thresholds:\n');
    fprintf('    Series resistance: %.1f MΩ\n', config.filters.maxSeriesResistance);
    fprintf('    Seal resistance: %.1f GΩ\n', config.filters.maxSealResistance);
    fprintf('    Capacitance: %.1f pF\n', config.filters.maxCapacitance);
    
    % Demonstrate parameter update with validation
    fprintf('  Testing parameter update...\n');
    
    try
        config.updateParameter('filters', 'maxSeriesResistance', 75);
        fprintf('    ✓ Updated series resistance threshold to 75 MΩ\n');
    catch ME
        fprintf('    ✗ Update failed: %s\n', ME.message);
    end
    
    % Show saving configuration
    configFile = 'demo_config.json';
    try
        config.saveConfig(configFile);
        fprintf('    ✓ Configuration saved to: %s\n', configFile);
    catch ME
        fprintf('    ✗ Save failed: %s\n', ME.message);
    end
    
    fprintf('\n');
    
    %% 7. Summary Report
    fprintf('=== PHASE 1 DEMO SUMMARY ===\n');
    
    activationFiles = sum(cellfun(@(p) ~isempty(p) && strcmp(p.type, 'activation'), protocolResults));
    inactivationFiles = sum(cellfun(@(p) ~isempty(p) && strcmp(p.type, 'inactivation'), protocolResults));
    failedDetection = sum(cellfun(@isempty, protocolResults));
    
    fprintf('Files analyzed: %d\n', length(filePaths));
    fprintf('Activation protocols: %d\n', activationFiles);
    fprintf('Inactivation protocols: %d\n', inactivationFiles);
    fprintf('Detection failures: %d\n', failedDetection);
    
    fprintf('\nPhase 1 infrastructure is ready for Phase 2 development!\n');
    
    %% 8. Clean up demo files
    if exist(configFile, 'file')
        delete(configFile);
    end
end