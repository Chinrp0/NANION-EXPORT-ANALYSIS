function test_unit_conversion()
    %TEST_UNIT_CONVERSION Verify that unit conversions work correctly
    
    fprintf('=== TESTING UNIT CONVERSIONS ===\n\n');
    
    % Add paths
    addpath(genpath('SRC'));
    addpath(genpath('configs'));
    
    % Get test file
    testFile = "C:/Users/xdach/OneDrive - Johns Hopkins/Maher_Lab/Protocols/Matlab_scripts/Fede/Master files for CHIN 9_17_2025/18T22880 NGN2 ACT_IV raw.xlsx";
    
    if ~exist(testFile, 'file')
        fprintf('❌ Test file not found: %s\n', testFile);
        return;
    end
    
    try
        % Create pipeline with default config
        fprintf('1. Creating pipeline...\n');
        pipeline = NanionAnalysisPipeline();
        
        % Run analysis on test file
        fprintf('2. Running analysis with unit conversions...\n');
        results = pipeline.runAnalysis({testFile}, 'tests/unit_test_output');
        
        if isempty(results) || ~strcmp(results{1}.status, 'success')
            fprintf('❌ Analysis failed\n');
            return;
        end
        
        % Extract the data
        extractedData = results{1}.extractedData;
        iv1Data = extractedData.measurements.iv1;
        
        % Display converted values
        fprintf('\n=== CONVERTED VALUES (FIRST 10 WELLS) ===\n');
        fprintf('Well ID   | Series R (MΩ) | Seal R (GΩ) | Capacitance (pF) | Peak Current (pA)\n');
        fprintf('----------|---------------|-------------|------------------|------------------\n');
        
        for i = 1:min(10, length(extractedData.wellIDs))
            fprintf('%-8s | %12.2f | %11.2f | %15.2f | %16.2f\n', ...
                extractedData.wellIDs(i), ...
                iv1Data.seriesResistance(i), ...
                iv1Data.sealResistance(i), ...
                iv1Data.capacitance(i), ...
                iv1Data.peakCurrent(i));
        end
        
        % Display statistics
        fprintf('\n=== UNIT CONVERSION STATISTICS ===\n');
        
        fprintf('Series Resistance (MΩ):\n');
        fprintf('  Min: %.2f, Max: %.2f, Median: %.2f\n', ...
            min(iv1Data.seriesResistance), max(iv1Data.seriesResistance), median(iv1Data.seriesResistance));
        
        fprintf('Seal Resistance (GΩ):\n');
        fprintf('  Min: %.2f, Max: %.2f, Median: %.2f\n', ...
            min(iv1Data.sealResistance), max(iv1Data.sealResistance), median(iv1Data.sealResistance));
        
        fprintf('Capacitance (pF):\n');
        fprintf('  Min: %.2f, Max: %.2f, Median: %.2f\n', ...
            min(iv1Data.capacitance), max(iv1Data.capacitance), median(iv1Data.capacitance));
        
        fprintf('Peak Current (pA):\n');
        fprintf('  Min: %.2f, Max: %.2f, Median: %.2f\n', ...
            min(iv1Data.peakCurrent), max(iv1Data.peakCurrent), median(iv1Data.peakCurrent));
        
        % Test quality filters with default thresholds
        fprintf('\n=== TESTING QUALITY FILTERS ===\n');
        filteredData = results{1}.filteredData;
        
        fprintf('Filter Results with Default Thresholds:\n');
        fprintf('  Series R ≤ 50 MΩ: %d wells pass\n', sum(iv1Data.seriesResistance <= 50));
        fprintf('  Seal R ≤ 50 GΩ: %d wells pass\n', sum(iv1Data.sealResistance <= 50));
        fprintf('  Capacitance ≤ 250 pF: %d wells pass\n', sum(iv1Data.capacitance <= 250));
        fprintf('  Combined: %d/%d wells pass (%.1f%%)\n', ...
            filteredData.numWellsPassed, filteredData.numWellsTotal, ...
            100 * filteredData.numWellsPassed / filteredData.numWellsTotal);
        
        % Test with more reasonable thresholds
        fprintf('\n=== TESTING WITH REASONABLE THRESHOLDS ===\n');
        reasonableFilters = struct(...
            'maxSeriesResistance', 100, ...  % 100 MΩ
            'maxSealResistance', 10, ...     % 10 GΩ  
            'maxCapacitance', 50);           % 50 pF
        
        seriesPass = sum(iv1Data.seriesResistance <= reasonableFilters.maxSeriesResistance);
        sealPass = sum(iv1Data.sealResistance <= reasonableFilters.maxSealResistance);
        capPass = sum(iv1Data.capacitance <= reasonableFilters.maxCapacitance);
        combinedPass = sum((iv1Data.seriesResistance <= reasonableFilters.maxSeriesResistance) & ...
                          (iv1Data.sealResistance <= reasonableFilters.maxSealResistance) & ...
                          (iv1Data.capacitance <= reasonableFilters.maxCapacitance));
        
        fprintf('Reasonable Thresholds:\n');
        fprintf('  Series R ≤ %d MΩ: %d wells pass (%.1f%%)\n', ...
            reasonableFilters.maxSeriesResistance, seriesPass, 100*seriesPass/length(iv1Data.seriesResistance));
        fprintf('  Seal R ≤ %d GΩ: %d wells pass (%.1f%%)\n', ...
            reasonableFilters.maxSealResistance, sealPass, 100*sealPass/length(iv1Data.sealResistance));
        fprintf('  Capacitance ≤ %d pF: %d wells pass (%.1f%%)\n', ...
            reasonableFilters.maxCapacitance, capPass, 100*capPass/length(iv1Data.capacitance));
        fprintf('  Combined: %d wells pass (%.1f%%)\n', ...
            combinedPass, 100*combinedPass/length(iv1Data.seriesResistance));
        
        % Check for unit conversion success
        fprintf('\n=== UNIT CONVERSION VALIDATION ===\n');
        
        % Series resistance should be in reasonable MΩ range (not millions)
        if median(iv1Data.seriesResistance) < 1000  % Less than 1000 MΩ
            fprintf('✅ Series resistance units look correct (median: %.1f MΩ)\n', median(iv1Data.seriesResistance));
        else
            fprintf('❌ Series resistance still looks unconverted (median: %.0f)\n', median(iv1Data.seriesResistance));
        end
        
        % Seal resistance should be in reasonable GΩ range
        if median(iv1Data.sealResistance) < 1000  % Less than 1000 GΩ
            fprintf('✅ Seal resistance units look correct (median: %.1f GΩ)\n', median(iv1Data.sealResistance));
        else
            fprintf('❌ Seal resistance still looks unconverted (median: %.0f)\n', median(iv1Data.sealResistance));
        end
        
        % Check capacitance
        if all(iv1Data.capacitance == 0)
            fprintf('⚠️  Capacitance still all zeros - need to investigate column mapping\n');
        else
            fprintf('✅ Capacitance has non-zero values (median: %.1f pF)\n', median(iv1Data.capacitance));
        end
        
        fprintf('\n=== TEST COMPLETE ===\n');
        
    catch ME
        fprintf('❌ Test failed with error: %s\n', ME.message);
        fprintf('Stack trace:\n%s\n', getReport(ME));
    end
end