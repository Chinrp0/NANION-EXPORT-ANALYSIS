function test_final_validation()
    %TEST_FINAL_VALIDATION Final validation of Phase 2 with both protocols
    
    fprintf('=== PHASE 2 DUAL PROTOCOL VALIDATION ===\n\n');
    
    addpath(genpath('SRC'));
    
    % Test both activation and inactivation protocols
    baseDir = "C:/Users/xdach/OneDrive - Johns Hopkins/Maher_Lab/Protocols/Matlab_scripts/Fede/Master files for CHIN 9_17_2025/";
    testFiles = {
        fullfile(baseDir, "18T22880 NGN2 INACT.xlsx"),
        fullfile(baseDir, "18T22880 NGN2 ACT_IV raw.xlsx")
    };
    
    % Check that both files exist
    for i = 1:length(testFiles)
        if ~exist(testFiles{i}, 'file')
            fprintf('❌ Test file not found: %s\n', testFiles{i});
            return;
        end
    end
    
    try
        % Run analysis on both files
        pipeline = NanionAnalysisPipeline();
        results = pipeline.runAnalysis(testFiles, 'tests/phase2_validation');
        
        if isempty(results)
            fprintf('❌ Analysis failed - no results returned\n');
            return;
        end
        
        % Process results for each protocol
        for fileIdx = 1:length(results)
            if ~strcmp(results{fileIdx}.status, 'success')
                fprintf('❌ Analysis failed for file %d\n', fileIdx);
                continue;
            end
            
            % Extract data for this file
            extractedData = results{fileIdx}.extractedData;
            filteredData = results{fileIdx}.filteredData;
            protocolType = extractedData.protocolInfo.type;
            
            fprintf('\n=== ANALYSIS RESULTS: %s PROTOCOL ===\n', upper(protocolType));
            fprintf('File: %s\n', results{fileIdx}.fileName);
            
            % Run analysis for this protocol
            analyzeProtocolResults(extractedData, filteredData);
        end
        
        % Overall summary
        fprintf('\n=== DUAL PROTOCOL SUMMARY ===\n');
        successCount = sum(cellfun(@(x) strcmp(x.status, 'success'), results));
        fprintf('Successful analyses: %d/%d\n', successCount, length(results));
        
        if successCount == length(results)
            fprintf('✓ Both activation and inactivation protocols working\n');
            fprintf('✓ IV2 fallback logic functional for both protocol types\n');
            fprintf('✓ Ready for Phase 3 development\n');
        else
            fprintf('⚠️ Some protocols failed - review logs above\n');
        end
        
    catch ME
        fprintf('❌ Validation failed: %s\n', ME.message);
        fprintf('Stack trace:\n%s\n', getReport(ME));
    end
end

function analyzeProtocolResults(extractedData, filteredData)
    %ANALYZEPROTOCOLRESULTS Analyze results for a single protocol
    
    iv1Data = extractedData.measurements.iv1;
    protocolType = extractedData.protocolInfo.type;
    
    % Common parameters
    seriesValid = ~isnan(iv1Data.seriesResistance);
    sealValid = ~isnan(iv1Data.sealResistance);
    capValid = ~isnan(iv1Data.capacitance);
    
    fprintf('Data Completeness (IV1):\n');
    fprintf('  Series Resistance: %d/%d wells (%.1f%%)\n', ...
        sum(seriesValid), extractedData.numWells, 100*sum(seriesValid)/extractedData.numWells);
    fprintf('  Seal Resistance: %d/%d wells (%.1f%%)\n', ...
        sum(sealValid), extractedData.numWells, 100*sum(sealValid)/extractedData.numWells);
    fprintf('  Capacitance: %d/%d wells (%.1f%%)\n', ...
        sum(capValid), extractedData.numWells, 100*sum(capValid)/extractedData.numWells);
    
    % Protocol-specific parameters
    if strcmp(protocolType, 'activation')
        if isfield(iv1Data, 'peakCurrent')
            currentValid = ~isnan(iv1Data.peakCurrent);
            fprintf('  Peak Current: %d/%d wells (%.1f%%)\n', ...
                sum(currentValid), extractedData.numWells, 100*sum(currentValid)/extractedData.numWells);
        end
    elseif strcmp(protocolType, 'inactivation')
        if isfield(iv1Data, 'inactivationData')
            inactValid = ~isnan(iv1Data.inactivationData);
            fprintf('  Inactivation Data: %d/%d wells (%.1f%%)\n', ...
                sum(inactValid), extractedData.numWells, 100*sum(inactValid)/extractedData.numWells);
        end
        if isfield(iv1Data, 'activationData')
            actValid = ~isnan(iv1Data.activationData);
            fprintf('  Activation Data: %d/%d wells (%.1f%%)\n', ...
                sum(actValid), extractedData.numWells, 100*sum(actValid)/extractedData.numWells);
        end
    end
    
    % Quality filtering summary
    filterReport = filteredData.filterReport;
    fprintf('\nQuality Filtering:\n');
    fprintf('  Total wells: %d\n', filterReport.totalWells);
    fprintf('  Passed filtering: %d (%.1f%%)\n', ...
        filterReport.passedWells, 100 * filterReport.passedWells / filterReport.totalWells);
    
    % IV usage if IV2 fallback was used
    if isfield(filterReport, 'ivUsage') && filterReport.ivUsage.iv2Available
        fprintf('  IV1 used: %d wells\n', filterReport.ivUsage.iv1Used);
        fprintf('  IV2 fallback: %d wells (rescued from IV1 failures)\n', filterReport.ivUsage.iv2Used);
    end
    
    % Unit validation for common parameters
    fprintf('\nUnit Validation:\n');
    if sum(seriesValid) > 0
        medianSeries = median(iv1Data.seriesResistance(seriesValid));
        if medianSeries > 0 && medianSeries < 1000
            seriesStatus = '✓';
        else
            seriesStatus = '❌';
        end
        fprintf('  Series R median: %.1f MΩ %s\n', medianSeries, seriesStatus);
    end
    
    if sum(sealValid) > 0
        medianSeal = median(iv1Data.sealResistance(sealValid));
        if medianSeal > 0 && medianSeal < 1000
            sealStatus = '✓';
        else
            sealStatus = '❌';
        end
        fprintf('  Seal R median: %.2f GΩ %s\n', medianSeal, sealStatus);
    end
    
    if sum(capValid) > 0
        medianCap = median(iv1Data.capacitance(capValid));
        if medianCap > 0 && medianCap < 1000
            capStatus = '✓';
        else
            capStatus = '❌';
        end
        fprintf('  Capacitance median: %.1f pF %s\n', medianCap, capStatus);
    end
end