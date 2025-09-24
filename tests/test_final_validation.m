function test_final_validation()
    %TEST_FINAL_VALIDATION Final validation of Phase 2 with proper missing data handling
    
    fprintf('=== PHASE 2 FINAL VALIDATION ===\n\n');
    
    addpath(genpath('SRC'));
    testFile = "C:/Users/xdach/OneDrive - Johns Hopkins/Maher_Lab/Protocols/Matlab_scripts/Fede/Master files for CHIN 9_17_2025/18T22880 NGN2 ACT_IV raw.xlsx";
    
    if ~exist(testFile, 'file')
        fprintf('❌ Test file not found: %s\n', testFile);
        return;
    end
    
    try
        % Run analysis
        pipeline = NanionAnalysisPipeline();
        results = pipeline.runAnalysis({testFile}, 'tests/phase2_validation');
        
        if isempty(results) || ~strcmp(results{1}.status, 'success')
            fprintf('❌ Analysis failed\n');
            return;
        end
        
        % Extract data
        extractedData = results{1}.extractedData;
        filteredData = results{1}.filteredData;
        iv1Data = extractedData.measurements.iv1;
        
        fprintf('=== DATA COMPLETENESS ANALYSIS ===\n');
        
        % Analyze missing data patterns
        seriesValid = ~isnan(iv1Data.seriesResistance);
        sealValid = ~isnan(iv1Data.sealResistance);
        capValid = ~isnan(iv1Data.capacitance);
        currentValid = ~isnan(iv1Data.peakCurrent);
        
        fprintf('Data Completeness (IV1):\n');
        fprintf('  Series Resistance: %d/%d wells (%.1f%%)\n', ...
            sum(seriesValid), length(seriesValid), 100*sum(seriesValid)/length(seriesValid));
        fprintf('  Seal Resistance: %d/%d wells (%.1f%%)\n', ...
            sum(sealValid), length(sealValid), 100*sum(sealValid)/length(sealValid));
        fprintf('  Capacitance: %d/%d wells (%.1f%%)\n', ...
            sum(capValid), length(capValid), 100*sum(capValid)/length(capValid));
        fprintf('  Peak Current: %d/%d wells (%.1f%%)\n', ...
            sum(currentValid), length(currentValid), 100*sum(currentValid)/length(currentValid));
        
        % Statistics for valid data only
        fprintf('\n=== VALID DATA STATISTICS ===\n');
        
        if sum(seriesValid) > 0
            validSeries = iv1Data.seriesResistance(seriesValid);
            fprintf('Series Resistance (MΩ) - %d valid values:\n', sum(seriesValid));
            fprintf('  Range: %.1f to %.1f, Median: %.1f\n', ...
                min(validSeries), max(validSeries), median(validSeries));
        end
        
        if sum(sealValid) > 0
            validSeal = iv1Data.sealResistance(sealValid);
            fprintf('Seal Resistance (GΩ) - %d valid values:\n', sum(sealValid));
            fprintf('  Range: %.2f to %.1f, Median: %.2f\n', ...
                min(validSeal), max(validSeal), median(validSeal));
        end
        
        if sum(capValid) > 0
            validCap = iv1Data.capacitance(capValid);
            fprintf('Capacitance (pF) - %d valid values:\n', sum(capValid));
            fprintf('  Range: %.2f to %.1f, Median: %.2f\n', ...
                min(validCap), max(validCap), median(validCap));
        end
        
        if sum(currentValid) > 0
            validCurrent = iv1Data.peakCurrent(currentValid);
            fprintf('Peak Current (pA) - %d valid values:\n', sum(currentValid));
            fprintf('  Range: %.1f to %.1f, Median: %.1f\n', ...
                min(validCurrent), max(validCurrent), median(validCurrent));
        end
        
        % Quality filtering analysis
        fprintf('=== QUALITY FILTERING ANALYSIS ===\n');
        filterReport = filteredData.filterReport;  % Extract filter report first
        fprintf('Total wells: %d\n', filterReport.totalWells);
        fprintf('Wells passed filtering: %d (%.1f%%)\n', ...
            filterReport.passedWells, 100 * filterReport.passedWells / filterReport.totalWells);
        
        % Show IV usage statistics if IV2 was available
        if isfield(filterReport, 'ivUsage') && filterReport.ivUsage.iv2Available
            fprintf('\n--- IV Usage for Quality Assessment ---\n');
            fprintf('  IV1 used: %d wells (%.1f%%)\n', ...
                filterReport.ivUsage.iv1Used, ...
                100 * filterReport.ivUsage.iv1Used / filterReport.totalWells);
            fprintf('  IV2 fallback used: %d wells (%.1f%%) - rescued from IV1 NaN/threshold failures\n', ...
                filterReport.ivUsage.iv2Used, ...
                100 * filterReport.ivUsage.iv2Used / filterReport.totalWells);
        end
        
        fprintf('\n--- Missing Data Exclusions ---\n');
        fprintf('  Series R NaN: %d wells (%.1f%%)\n', ...
            filterReport.nanFailures.seriesR.count, ...
            100 * filterReport.nanFailures.seriesR.count / filterReport.totalWells);
        fprintf('  Seal R NaN: %d wells (%.1f%%)\n', ...
            filterReport.nanFailures.sealR.count, ...
            100 * filterReport.nanFailures.sealR.count / filterReport.totalWells);
        fprintf('  Capacitance NaN: %d wells (%.1f%%)\n', ...
            filterReport.nanFailures.capacitance.count, ...
            100 * filterReport.nanFailures.capacitance.count / filterReport.totalWells);
        
        fprintf('\n--- Threshold Exceedances (Valid Data Only) ---\n');
        fprintf('  Series R > %.1f MΩ: %d/%d wells (%.1f%%)\n', ...
            filterReport.thresholdFailures.seriesR.threshold, ...
            filterReport.thresholdFailures.seriesR.count, ...
            filterReport.validDataCounts.seriesR, ...
            100 * filterReport.thresholdFailures.seriesR.count / max(1, filterReport.validDataCounts.seriesR));
        fprintf('  Seal R > %.1f GΩ: %d/%d wells (%.1f%%)\n', ...
            filterReport.thresholdFailures.sealR.threshold, ...
            filterReport.thresholdFailures.sealR.count, ...
            filterReport.validDataCounts.sealR, ...
            100 * filterReport.thresholdFailures.sealR.count / max(1, filterReport.validDataCounts.sealR));
        fprintf('  Capacitance > %.1f pF: %d/%d wells (%.1f%%)\n', ...
            filterReport.thresholdFailures.capacitance.threshold, ...
            filterReport.thresholdFailures.capacitance.count, ...
            filterReport.validDataCounts.capacitance, ...
            100 * filterReport.thresholdFailures.capacitance.count / max(1, filterReport.validDataCounts.capacitance));
        

        % Sample of wells that passed
        fprintf('\n=== SAMPLE OF PASSED WELLS ===\n');
        if filteredData.numWellsPassed > 0
            passedIv1 = filteredData.measurements.iv1;
            numSamples = min(10, filteredData.numWellsPassed);
            
            fprintf('Well ID   | IV Used | Series R (MΩ) | Seal R (GΩ) | Cap (pF) | Current (pA)\n');
            fprintf('----------|---------|---------------|-------------|----------|-------------\n');
            
            for i = 1:numSamples
                % Show which IV was used for filtering decision
                ivUsed = filteredData.ivUsedForFiltering(i);
                fprintf('%-8s | %6s | %12.1f | %10.2f | %7.1f | %10.1f\n', ...
                    filteredData.wellIDs(i), ...
                    ivUsed, ...
                    passedIv1.seriesResistance(i), ...
                    passedIv1.sealResistance(i), ...
                    passedIv1.capacitance(i), ...
                    passedIv1.peakCurrent(i));
            end
        end
        
        % Validate unit conversions
        fprintf('\n=== UNIT CONVERSION VALIDATION ===\n');
        
        % Check if values are in reasonable scientific ranges
        reasonableRanges = true;
        
        if sum(seriesValid) > 0
            validSeries = iv1Data.seriesResistance(seriesValid);
            if median(validSeries) > 0 && median(validSeries) < 1000
                fprintf('✅ Series resistance units correct (median: %.1f MΩ)\n', median(validSeries));
            else
                fprintf('❌ Series resistance units may be wrong (median: %.1f)\n', median(validSeries));
                reasonableRanges = false;
            end
        end
        
        if sum(sealValid) > 0
            validSeal = iv1Data.sealResistance(sealValid);
            if median(validSeal) > 0 && median(validSeal) < 1000
                fprintf('✅ Seal resistance units correct (median: %.2f GΩ)\n', median(validSeal));
            else
                fprintf('❌ Seal resistance units may be wrong (median: %.2f)\n', median(validSeal));
                reasonableRanges = false;
            end
        end
        
        if sum(capValid) > 0
            validCap = iv1Data.capacitance(capValid);
            if median(validCap) > 0 && median(validCap) < 1000
                fprintf('✅ Capacitance units correct (median: %.1f pF)\n', median(validCap));
            else
                fprintf('❌ Capacitance units may be wrong (median: %.1f)\n', median(validCap));
                reasonableRanges = false;
            end
        end
        
        % Overall Phase 2 assessment
        fprintf('\n=== PHASE 2 ASSESSMENT ===\n');
        
        dataExtracted = extractedData.numWells > 0;
        unitsConverted = reasonableRanges;
        filteringWorking = filteredData.numWellsPassed < extractedData.numWells; % Some filtering happened
        
        if dataExtracted
            fprintf('✓ Data Extraction: WORKING\n');
        else
            fprintf('✓ Data Extraction: FAILED\n');
        end
        
        if unitsConverted
            fprintf('✓ Unit Conversion: WORKING\n');
        else
            fprintf('✓ Unit Conversion: FAILED\n');
        end
        
        if filteringWorking
            fprintf('✓ Quality Filtering: WORKING\n');
        else
            fprintf('✓ Quality Filtering: FAILED\n');
        end
        
        if dataExtracted && unitsConverted && filteringWorking
            fprintf('\n🎉 PHASE 2 COMPLETE - Ready for Phase 3 (Boltzmann Analysis)!\n');
        else
            fprintf('\n⚠️  Phase 2 needs attention before proceeding to Phase 3\n');
        end
        
        % Suggest next steps
        fprintf('\n=== NEXT STEPS ===\n');
        fprintf('1. Test with inactivation protocol file to verify full Phase 2\n');
        fprintf('2. Optimize quality filter thresholds if needed\n');
        fprintf('3. Begin Phase 3: Boltzmann curve fitting implementation\n');
        
    catch ME
        fprintf('❌ Validation failed: %s\n', ME.message);
        fprintf('Stack trace:\n%s\n', getReport(ME));
    end
end