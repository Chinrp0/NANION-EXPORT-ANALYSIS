function phase2_integration_test_corrected()
%PHASE2_INTEGRATION_TEST_CORRECTED Test Phase 2 with corrected paths

% Add analysis directory to path (relative to SRC directory)
addpath('analysis');

fprintf('=== PHASE 2 INTEGRATION TEST (CORRECTED) ===\n\n');

try
    % Test 1: Check if file exists and can be found
    fprintf('TEST 1: File Location Check...\n');
    whichResult = which('NanionDataExtractor');
    if contains(whichResult, 'NanionDataExtractor.m')
        fprintf('  ✓ NanionDataExtractor.m found at: %s\n', whichResult);
    else
        error('NanionDataExtractor.m not found in MATLAB path');
    end
    
    % Test 2: Component initialization
    fprintf('\nTEST 2: Component Initialization...\n');
    config = NanionConfig();
    logger = NanionLogger(config);
    dataExtractor = NanionDataExtractor(config, logger);
    fprintf('  ✓ NanionDataExtractor created successfully\n');
    
    % Test 3: Pipeline integration check
    fprintf('\nTEST 3: Pipeline Integration Check...\n');
    pipeline = NanionAnalysisPipeline();
    
    % Check if dataExtractor property was added to pipeline
    props = properties(pipeline);
    if ismember('dataExtractor', props)
        fprintf('  ✓ Pipeline has dataExtractor property\n');
    else
        fprintf('  ❌ Pipeline missing dataExtractor property\n');
        fprintf('     → You still need to modify NanionAnalysisPipeline.m\n');
        fprintf('     → Add dataExtractor property and initialization\n');
    end
    
    fprintf('\n=== INTEGRATION TEST RESULTS ===\n');
    fprintf('✓ NanionDataExtractor file created and found\n');
    fprintf('✓ Class initializes correctly\n');
    if ismember('dataExtractor', props)
        fprintf('✓ Pipeline integration complete\n');
        fprintf('\n🎯 Ready for full pipeline test!\n');
        fprintf('   Run: debug_data_extraction_corrected()\n');
    else
        fprintf('⚠️  Pipeline integration needed\n');
        fprintf('\n🔧 Next Steps:\n');
        fprintf('   1. Modify NanionAnalysisPipeline.m as instructed\n');
        fprintf('   2. Run this test again to verify\n');
    end
    
catch ME
    fprintf('\n❌ TEST FAILED: %s\n', ME.message);
    
    if contains(ME.message, 'not found')
        fprintf('\n💡 SOLUTION:\n');
        fprintf('   1. Make sure you saved NanionDataExtractor.m in analysis/ folder\n');
        fprintf('   2. Run: addpath(''analysis'')\n');
        fprintf('   3. Check: which(''NanionDataExtractor'')\n');
    end
end
end