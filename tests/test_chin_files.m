function test_chin_files()
    % TEST_CHIN_FILES - Test Phase 2 with CHIN 9_17_2025 files
    
    fprintf('=== PHASE 2 TEST WITH CHIN FILES ===\n');
    
    % Directory path provided by user
    chin_dir = 'C:\Users\xdach\OneDrive - Johns Hopkins\Maher_Lab\Protocols\Matlab_scripts\Fede\Master files for CHIN 9_17_2025';
    
    fprintf('Looking for files in: %s\n', chin_dir);
    
    if ~exist(chin_dir, 'dir')
        fprintf('❌ Directory not found: %s\n', chin_dir);
        return;
    end
    
    % Find Excel files
    xlsx_files = dir(fullfile(chin_dir, '*.xlsx'));
    
    if isempty(xlsx_files)
        fprintf('❌ No .xlsx files found in directory\n');
        return;
    end
    
    fprintf('✅ Found %d Excel files:\n', length(xlsx_files));
    for i = 1:length(xlsx_files)
        fprintf('  %d. %s (%.1f KB)\n', i, xlsx_files(i).name, xlsx_files(i).bytes/1024);
    end
    
    % Test with first file
    test_file = fullfile(xlsx_files(1).folder, xlsx_files(1).name);
    fprintf('\n--- Testing with: %s ---\n', xlsx_files(1).name);
    
    try
        % Initialize pipeline
        pipeline = NanionAnalysisPipeline();
        output_dir = fullfile(pwd, 'chin_test_results');
        
        if ~exist(output_dir, 'dir')
            mkdir(output_dir);
        end
        
        % Run Phase 2 analysis
        fprintf('🚀 Running Phase 2 analysis...\n');
        tic;
        results = pipeline.runAnalysis({test_file}, output_dir);
        elapsed_time = toc;
        
        % Analyze results
        if ~isempty(results) && strcmp(results{1}.status, 'success')
            result = results{1};
            
            fprintf('\n🎉 PHASE 2 SUCCESS! (%.1f seconds)\n', elapsed_time);
            fprintf('\n=== ANALYSIS RESULTS ===\n');
            fprintf('File: %s\n', result.fileName);
            fprintf('Protocol Type: %s\n', result.protocol.type);
            fprintf('Number of IVs: %d\n', result.protocol.numIVs);
            
            % Extraction results
            fprintf('\n=== DATA EXTRACTION ===\n');
            fprintf('Total wells extracted: %d\n', result.extractedData.numWells);
            
            if length(result.extractedData.wellIDs) > 0
                fprintf('Well ID range: %s to %s\n', ...
                    result.extractedData.wellIDs(1), result.extractedData.wellIDs(end));
                
                % Show sample of well IDs
                sample_size = min(10, length(result.extractedData.wellIDs));
                fprintf('Sample wells: ');
                for i = 1:sample_size
                    fprintf('%s', result.extractedData.wellIDs(i));
                    if i < sample_size
                        fprintf(', ');
                    end
                end
                if length(result.extractedData.wellIDs) > sample_size
                    fprintf(', ...');
                end
                fprintf('\n');
            end
            
            % Quality filtering results
            fprintf('\n=== QUALITY FILTERING ===\n');
            fprintf('Total wells processed: %d\n', result.filteredData.numWellsTotal);
            fprintf('Wells passed filters: %d\n', result.filteredData.numWellsPassed);
            fprintf('Success rate: %.1f%%\n', 100 * result.filteredData.numWellsPassed / result.filteredData.numWellsTotal);
            
            % Show filter failure details
            if isfield(result.filteredData, 'filterReport')
                report = result.filteredData.filterReport;
                fprintf('\nFilter failure breakdown:\n');
                
                if isfield(report, 'seriesFailures') && report.seriesFailures.count > 0
                    fprintf('  Series resistance failures: %d wells\n', report.seriesFailures.count);
                end
                
                if isfield(report, 'sealFailures') && report.sealFailures.count > 0
                    fprintf('  Seal resistance failures: %d wells\n', report.sealFailures.count);
                end
                
                if isfield(report, 'capacitanceFailures') && report.capacitanceFailures.count > 0
                    fprintf('  Capacitance failures: %d wells\n', report.capacitanceFailures.count);
                end
            end
            
            % Show measurement data availability
            fprintf('\n=== MEASUREMENTS EXTRACTED ===\n');
            measurements = result.extractedData.measurements;
            iv_names = fieldnames(measurements);
            
            for i = 1:length(iv_names)
                iv_name = iv_names{i};
                iv_data = measurements.(iv_name);
                param_names = fieldnames(iv_data);
                
                fprintf('%s: %s\n', iv_name, strjoin(param_names, ', '));
            end
            
            fprintf('\n📁 Results saved to: %s\n', output_dir);
            
            % List output files
            output_files = dir(output_dir);
            output_files = output_files(~[output_files.isdir] & ~startsWith({output_files.name}, '.'));
            if ~isempty(output_files)
                fprintf('\nOutput files created:\n');
                for i = 1:length(output_files)
                    fprintf('  %s\n', output_files(i).name);
                end
            end
            
            fprintf('\n✅ PHASE 2 COMPLETE AND WORKING!\n');
            
        else
            fprintf('❌ Analysis failed\n');
            if ~isempty(results) && isfield(results{1}, 'error')
                fprintf('Error: %s\n', results{1}.error);
            end
        end
        
    catch ME
        fprintf('❌ Test failed with error: %s\n', ME.message);
        fprintf('Stack trace:\n%s\n', getReport(ME));
    end
    
    % Offer to test additional files
    if length(xlsx_files) > 1
        fprintf('\n🔧 To test other files from this directory:\n');
        for i = 2:min(5, length(xlsx_files))
            file_path = fullfile(xlsx_files(i).folder, xlsx_files(i).name);
            fprintf('  test_single_chin_file(''%s'')\n', file_path);
        end
        if length(xlsx_files) > 5
            fprintf('  ... and %d more files\n', length(xlsx_files) - 5);
        end
    end
end

function test_single_chin_file(file_path)
    % TEST_SINGLE_CHIN_FILE - Test a specific file from CHIN directory
    
    fprintf('Testing single file: %s\n', file_path);
    
    if ~exist(file_path, 'file')
        fprintf('File not found: %s\n', file_path);
        return;
    end
    
    try
        pipeline = NanionAnalysisPipeline();
        output_dir = fullfile(pwd, 'chin_single_test');
        
        if ~exist(output_dir, 'dir')
            mkdir(output_dir);
        end
        
        results = pipeline.runAnalysis({file_path}, output_dir);
        
        if ~isempty(results) && strcmp(results{1}.status, 'success')
            fprintf('✅ SUCCESS: %s protocol, %d wells, %d passed filters\n', ...
                results{1}.protocol.type, ...
                results{1}.extractedData.numWells, ...
                results{1}.filteredData.numWellsPassed);
        else
            fprintf('❌ FAILED\n');
        end
        
    catch ME
        fprintf('❌ Error: %s\n', ME.message);
    end
end