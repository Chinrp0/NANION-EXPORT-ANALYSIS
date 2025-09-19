function phase1_verification_test()
    %PHASE1_VERIFICATION_TEST Comprehensive test of simplified Phase 1 components
    %   Tests each component individually and then the integrated pipeline
    
    fprintf('=== PHASE 1 VERIFICATION TEST ===\n\n');
    
    testResults = struct();
    overallPassed = true;
    
    try
        %% Test 1: Configuration System
        fprintf('TEST 1: Configuration Management...\n');
        try
            config = NanionConfig();
            
            % Test parameter access
            assert(config.numDataPoints == 23, 'numDataPoints should be 23');
            assert(config.filters.maxSeriesResistance == 50, 'maxSeriesResistance should be 50');
            
            % Test parameter update
            config.updateParameter('filters', 'maxSeriesResistance', 75);
            assert(config.filters.maxSeriesResistance == 75, 'Parameter update failed');
            
            % Test validation
            try
                config.updateParameter('filters', 'maxSeriesResistance', -10);
                error('Should have failed validation');
            catch ME
                if contains(ME.message, 'positive')
                    % Expected validation error
                else
                    rethrow(ME);
                end
            end
            
            fprintf('  ✓ Configuration system working\n');
            testResults.config = true;
            
        catch ME
            fprintf('  ✗ Configuration test failed: %s\n', ME.message);
            testResults.config = false;
            overallPassed = false;
        end
        
        %% Test 2: Logger System
        fprintf('TEST 2: Logging System...\n');
        try
            logger = NanionLogger(config);
            
            % Test different log levels
            logger.logInfo('Test info message');
            logger.logWarning('Test warning message');
            logger.logError('Test error message');
            
            fprintf('  ✓ Logger system working\n');
            testResults.logger = true;
            
        catch ME
            fprintf('  ✗ Logger test failed: %s\n', ME.message);
            testResults.logger = false;
            overallPassed = false;
        end
        
        %% Test 3: File Selection and Detection
        fprintf('TEST 3: File Detection (Interactive)...\n');
        try
            % Get test file
            [filename, pathname] = uigetfile(...
                {'*.xlsx;*.xls', 'Excel Files (*.xlsx, *.xls)'}, ...
                'Select ONE test file for verification');
            
                            if isequal(filename, 0)
                fprintf('  ⚠ No file selected - skipping file tests\n');
                testResults.fileDetection = 'skipped';
                testResults.fileReading = 'skipped';
                testResults.pipeline = 'skipped';
            else
                filePath = fullfile(pathname, filename);
                
                % Test protocol detection
                fileDetector = NanionFileDetector(logger);
                protocolInfo = fileDetector.detectProtocol(filePath);
                
                if isempty(protocolInfo)
                    fprintf('  ✗ Protocol detection failed\n');
                    testResults.fileDetection = false;
                    testResults.fileReading = 'skipped';
                    testResults.pipeline = 'skipped';
                    overallPassed = false;
                else
                    fprintf('  ✓ Detected %s protocol with %d IVs\n', ...
                        protocolInfo.type, protocolInfo.numIVs);
                    testResults.fileDetection = true;
                    fprintf('  ✓ Detected %s protocol with %d IVs\n', ...
                        protocolInfo.type, protocolInfo.numIVs);
                    testResults.fileDetection = true;
                
                    %% Test 4: File Reading
                    fprintf('TEST 4: File Reading...\n');
                    try
                        ioManager = NanionIOManager(config, logger);
                        
                        % Test raw file reading
                        rawData = ioManager.readFile(filePath);
                        fprintf('  ✓ Raw data read: %dx%d\n', size(rawData));
                        
                        % Test data parsing
                        parsedData = ioManager.parseData(rawData, protocolInfo);
                        fprintf('  ✓ Data parsed: %dx%d table\n', size(parsedData.dataTable));
                        fprintf('  ✓ Header rows: %d\n', parsedData.headerRows);
                        
                        % Verify table structure
                        headers = parsedData.dataTable.Properties.VariableNames;
                        assert(all(contains(headers, 'Col_')), 'Headers should be Col_X format');
                        
                        fprintf('  ✓ File reading system working\n');
                        testResults.fileReading = true;
                        
                    catch ME
                        fprintf('  ✗ File reading test failed: %s\n', ME.message);
                        testResults.fileReading = false;
                        overallPassed = false;
                    end
                    
                    %% Test 5: Full Pipeline
                    fprintf('TEST 5: Complete Pipeline...\n');
                    try
                        pipeline = NanionAnalysisPipeline();
                        
                        % Create temporary output directory
                        outputDir = fullfile(tempdir, 'nanion_test_output');
                        if ~exist(outputDir, 'dir')
                            mkdir(outputDir);
                        end
                        
                        % Run pipeline on single file
                        results = pipeline.runAnalysis({filePath}, outputDir);
                        
                        % Verify results
                        assert(length(results) == 1, 'Should have 1 result');
                        assert(strcmp(results{1}.status, 'success'), 'Result should be successful');
                        
                        fprintf('  ✓ Pipeline completed successfully\n');
                        fprintf('  ✓ Output directory: %s\n', outputDir);
                        testResults.pipeline = true;
                        
                        % Clean up
                        rmdir(outputDir, 's');
                        
                    catch ME
                        fprintf('  ✗ Pipeline test failed: %s\n', ME.message);
                        testResults.pipeline = false;
                        overallPassed = false;
                    end
                end
            end
            
        catch ME
            fprintf('  ✗ File detection test failed: %s\n', ME.message);
            testResults.fileDetection = false;
            testResults.fileReading = 'skipped';
            testResults.pipeline = 'skipped';
            overallPassed = false;
        end
        
    catch ME
        fprintf('FATAL ERROR in test setup: %s\n', ME.message);
        overallPassed = false;
    end
    
    %% Test Results Summary
    fprintf('\n=== TEST RESULTS SUMMARY ===\n');
    
    testNames = {'Configuration', 'Logger', 'File Detection', 'File Reading', 'Pipeline'};
    testFields = {'config', 'logger', 'fileDetection', 'fileReading', 'pipeline'};
    
    for i = 1:length(testNames)
        if isfield(testResults, testFields{i})
            result = testResults.(testFields{i});
            if islogical(result) && result
                fprintf('✓ %s: PASSED\n', testNames{i});
            elseif islogical(result) && ~result
                fprintf('✗ %s: FAILED\n', testNames{i});
            else
                fprintf('⚠ %s: SKIPPED\n', testNames{i});
            end
        else
            fprintf('⚠ %s: NOT RUN\n', testNames{i});
        end
    end
    
    fprintf('\n');
    
    if overallPassed
        fprintf('🎉 ALL TESTS PASSED - Phase 1 pipeline is functional!\n');
        fprintf('✓ Simplified codebase is working correctly\n');
        fprintf('✓ Ready to proceed to Phase 2\n');
    else
        fprintf('❌ SOME TESTS FAILED - Issues need to be resolved\n');
        fprintf('Check the error messages above for details\n');
    end
    
    %% Line Count Verification
    fprintf('\n=== CODE SIMPLIFICATION VERIFICATION ===\n');
    
    % Check if files exist and estimate line counts
    srcFiles = {
        'SRC/config/NanionConfig.m',
        'SRC/io/NanionIOManager.m', 
        'SRC/io/NanionFileDetector.m',
        'SRC/utils/NanionLogger.m',
        'SRC/pipeline/NanionAnalysisPipeline.m'
    };
    
    totalLines = 0;
    for i = 1:length(srcFiles)
        if exist(srcFiles{i}, 'file')
            fid = fopen(srcFiles{i}, 'r');
            if fid > 0
                lines = 0;
                while ~feof(fid)
                    fgetl(fid);
                    lines = lines + 1;
                end
                fclose(fid);
                totalLines = totalLines + lines;
                
                [~, filename, ext] = fileparts(srcFiles{i});
                fprintf('%s%s: %d lines\n', filename, ext, lines);
            end
        else
            fprintf('File not found: %s\n', srcFiles{i});
        end
    end
    
    fprintf('Total Phase 1 code: %d lines\n', totalLines);
    
    if totalLines < 400
        fprintf('✓ Good! Codebase is appropriately simple for Phase 1\n');
    elseif totalLines < 600
        fprintf('⚠ Acceptable size, but could be simpler\n');
    else
        fprintf('❌ Still too complex - more simplification needed\n');
    end
end