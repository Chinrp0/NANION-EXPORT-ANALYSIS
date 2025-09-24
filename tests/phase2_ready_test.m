% PHASE2_READY_TEST - Test Phase 2 with real data
fprintf('=== PHASE 2 READY TEST ===\n');
fprintf('Testing the complete Phase 2 pipeline with real data...\n\n');

% Test 1: Initialize pipeline
try
    pipeline = NanionAnalysisPipeline();
    fprintf('✅ Step 1: Pipeline initialized successfully\n');
    
    % Verify all components
    if ~isempty(pipeline.dataExtractor)
        fprintf('✅ Step 2: DataExtractor component ready\n');
    else
        fprintf('❌ Step 2: DataExtractor missing\n');
        return;
    end
    
catch ME
    fprintf('❌ Pipeline initialization failed: %s\n', ME.message);
    return;
end

% Test 2: Find test files
fprintf('\n--- Looking for test data files ---\n');
possible_paths = {
    '../test-data/*.xlsx',
    '../TEST_DATA/*.xlsx', 
    '../../test-data/*.xlsx',
    '../*.xlsx',
    '*.xlsx'
};

test_files = {};
for i = 1:length(possible_paths)
    files = dir(possible_paths{i});
    if ~isempty(files)
        fprintf('Found %d Excel files in: %s\n', length(files), fileparts(possible_paths{i}));
        for j = 1:length(files)
            full_path = fullfile(files(j).folder, files(j).name);
            test_files{end+1} = full_path;
            fprintf('  %s\n', files(j).name);
        end
        break;  % Use first location found
    end
end

if isempty(test_files)
    fprintf('⚠️  No test Excel files found. Please put test .xlsx files in one of these locations:\n');
    for i = 1:length(possible_paths)
        fprintf('   %s\n', possible_paths{i});
    end
    fprintf('\n🔧 Manual test: Provide file path\n');
    fprintf('   test_file = ''path/to/your/nanion_file.xlsx'';\n');
    fprintf('   phase2_ready_test_manual(test_file);\n');
    return;
end

% Test 3: Run Phase 2 on first file
test_file = test_files{1};
fprintf('\n--- Testing Phase 2 on: %s ---\n', test_file);

try
    % Create output directory
    output_dir = fullfile(pwd, 'test_output');
    if ~exist(output_dir, 'dir')
        mkdir(output_dir);
    end
    
    fprintf('Output directory: %s\n', output_dir);
    
    % Run the complete Phase 2 pipeline
    fprintf('\n🚀 Running Phase 2 Analysis Pipeline...\n');
    results = pipeline.runAnalysis({test_file}, output_dir);
    
    if ~isempty(results) && strcmp(results{1}.status, 'success')
        fprintf('🎉 PHASE 2 SUCCESS!\n\n');
        
        result = results{1};
        fprintf('Results Summary:\n');
        fprintf('  Protocol: %s\n', result.protocol.type);
        fprintf('  Number of IVs: %d\n', result.protocol.numIVs);
        fprintf('  Wells extracted: %d\n', result.extractedData.numWells);
        fprintf('  Wells passed filters: %d\n', result.filteredData.numWellsPassed);
        fprintf('  Success rate: %.1f%%\n', 100 * result.filteredData.numWellsPassed / result.filteredData.numWellsTotal);
        
        % Show sample well IDs
        if length(result.filteredData.wellIDs) > 0
            fprintf('  Sample well IDs: %s', result.filteredData.wellIDs(1));
            if length(result.filteredData.wellIDs) > 1
                fprintf(', %s', result.filteredData.wellIDs(2));
            end
            if length(result.filteredData.wellIDs) > 2
                fprintf(', ...');
            end
            fprintf('\n');
        end
        
        fprintf('\n📁 Output files created in: %s\n', output_dir);
        
    else
        fprintf('❌ Phase 2 failed: %s\n', results{1}.error);
    end
    
catch ME
    fprintf('❌ Phase 2 pipeline error: %s\n', ME.message);
    fprintf('Stack trace:\n%s\n', getReport(ME));
end

function phase2_ready_test_manual(test_file)
    % Manual version for when no test files are auto-found
    fprintf('=== MANUAL PHASE 2 TEST ===\n');
    fprintf('Testing with: %s\n', test_file);
    
    if ~exist(test_file, 'file')
        fprintf('❌ File not found: %s\n', test_file);
        return;
    end
    
    try
        pipeline = NanionAnalysisPipeline();
        output_dir = fullfile(pwd, 'manual_test_output');
        if ~exist(output_dir, 'dir')
            mkdir(output_dir);
        end
        
        results = pipeline.runAnalysis({test_file}, output_dir);
        
        if ~isempty(results) && strcmp(results{1}.status, 'success')
            fprintf('🎉 MANUAL TEST SUCCESS!\n');
        else
            fprintf('❌ Manual test failed\n');
        end
        
    catch ME
        fprintf('❌ Manual test error: %s\n', ME.message);
    end
end