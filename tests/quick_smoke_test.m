function quick_smoke_test()
    %QUICK_SMOKE_TEST Fast verification that all classes can be instantiated
    %   Run this first to catch any syntax errors or missing dependencies
    
    fprintf('=== QUICK SMOKE TEST ===\n\n');
    
    try
        %% Test 1: Class Instantiation
        fprintf('Testing class instantiation...\n');
        
        % Test NanionConfig
        config = NanionConfig();
        fprintf('  ✓ NanionConfig created\n');
        
        % Test NanionLogger  
        logger = NanionLogger(config);
        fprintf('  ✓ NanionLogger created\n');
        
        % Test NanionIOManager
        ioManager = NanionIOManager(config, logger);
        fprintf('  ✓ NanionIOManager created\n');
        
        % Test NanionFileDetector
        fileDetector = NanionFileDetector(logger);
        fprintf('  ✓ NanionFileDetector created\n');
        
        % Test NanionAnalysisPipeline
        pipeline = NanionAnalysisPipeline();
        fprintf('  ✓ NanionAnalysisPipeline created\n');
        
        %% Test 2: Basic Method Calls
        fprintf('\nTesting basic method calls...\n');
        
        % Test config methods
        summary = config.getSummary();
        fprintf('  ✓ Config summary generated (%d chars)\n', length(summary));
        
        % Test logger methods
        logger.logInfo('Test message');
        fprintf('  ✓ Logger info message worked\n');
        
        % Test config parameter update
        config.updateParameter('filters', 'maxSeriesResistance', 60);
        assert(config.filters.maxSeriesResistance == 60, 'Parameter update failed');
        fprintf('  ✓ Config parameter update worked\n');
        
        %% Test 3: Method Signature Check
        fprintf('\nChecking simplified method signatures...\n');
        
        % Check that deleted methods are actually gone
        methods_NanionIOManager = methods('NanionIOManager');
        deleted_methods = {'cleanHeaderRow', 'createValidTableHeader', 'isEmptyCell'};
        
        for i = 1:length(deleted_methods)
            if any(strcmp(methods_NanionIOManager, deleted_methods{i}))
                error('Method %s should have been deleted from NanionIOManager', deleted_methods{i});
            end
        end
        fprintf('  ✓ Unused methods successfully removed from NanionIOManager\n');
        
        % Check that validation methods are consolidated
        methods_NanionConfig = methods('NanionConfig');
        old_validation_methods = {'validateAnalysisParams', 'validateFilterParams', 'validateBoltzmannParams'};
        
        for i = 1:length(old_validation_methods)
            if any(strcmp(methods_NanionConfig, old_validation_methods{i}))
                error('Method %s should have been deleted from NanionConfig', old_validation_methods{i});
            end
        end
        fprintf('  ✓ Validation methods successfully consolidated in NanionConfig\n');
        
        fprintf('\n🎉 SMOKE TEST PASSED!\n');
        fprintf('✓ All classes instantiate correctly\n');
        fprintf('✓ Basic methods work\n');
        fprintf('✓ Simplifications implemented correctly\n');
        fprintf('\nReady for full verification test!\n');
        
    catch ME
        fprintf('\n❌ SMOKE TEST FAILED!\n');
        fprintf('Error: %s\n', ME.message);
        fprintf('Stack trace:\n%s\n', getReport(ME));
        
        % Provide debugging hints
        fprintf('\nDebugging hints:\n');
        fprintf('1. Check that all files are in the correct directories\n');
        fprintf('2. Ensure MATLAB path includes all SRC subdirectories\n');
        fprintf('3. Verify all simplified methods were implemented correctly\n');
        fprintf('4. Check for syntax errors in modified files\n');
    end
end