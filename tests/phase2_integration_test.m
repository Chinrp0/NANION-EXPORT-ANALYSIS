function phase2_integration_test()
%PHASE2_INTEGRATION_TEST Test Phase 2 data extraction functionality

% Add analysis directory to path
addpath('SRC/analysis');

fprintf('=== PHASE 2 INTEGRATION TEST ===\n\n');

try
    % Test 1: Component initialization
    fprintf('TEST 1: Component Initialization...\n');
    config = NanionConfig();
    logger = NanionLogger(config);
    dataExtractor = NanionDataExtractor(config, logger);
    fprintf('  ✓ NanionDataExtractor created successfully\n');
    
    % Test 2: Pipeline with data extraction
    fprintf('\nTEST 2: Pipeline with Data Extraction...\n');
    pipeline = NanionAnalysisPipeline();
    
    % Check if dataExtractor property exists
    if isprop(pipeline, 'dataExtractor')
        fprintf('  ✓ Pipeline has dataExtractor property\n');
    else
        error('Pipeline missing dataExtractor property');
    end
    
    % Test 3: Run pipeline on test file
    fprintf('\nTEST 3: Interactive Pipeline Test...\n');
    fprintf('  → Running interactive pipeline to test data extraction...\n');
    
    % This will open file dialog - select one of your test files
    run_pipeline_interactive();
    
    fprintf('\n=== INTEGRATION TEST RESULTS ===\n');
    fprintf('✓ All components initialized correctly\n');
    fprintf('✓ Pipeline includes data extraction functionality\n');
    fprintf('✓ Ready for Phase 2 development\n');
    fprintf('\n🎯 Next Steps:\n');
    fprintf('  1. Run the interactive pipeline with your test files\n');
    fprintf('  2. Check logs for "Step 2: Extracting measurements..."\n');
    fprintf('  3. Verify Well_ID extraction in the output\n');
    
catch ME
    fprintf('\n❌ TEST FAILED: %s\n', ME.message);
    fprintf('Stack trace: %s\n', getReport(ME));
end
end