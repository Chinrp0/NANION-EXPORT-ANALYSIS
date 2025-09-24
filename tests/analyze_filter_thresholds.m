function analyze_filter_thresholds()
    % ANALYZE_FILTER_THRESHOLDS - Check what filter values would work better
    
    fprintf('=== ANALYZING FILTER THRESHOLDS ===\n');
    fprintf('Your current filters are too strict (0%% pass rate)\n');
    fprintf('Let''s analyze the data to find better thresholds...\n\n');
    
    % Test the same file to get the raw measurements
    chin_file = 'C:\Users\xdach\OneDrive - Johns Hopkins\Maher_Lab\Protocols\Matlab_scripts\Fede\Master files for CHIN 9_17_2025\18T22880 NGN2 ACT_IV raw.xlsx';
    
    try
        pipeline = NanionAnalysisPipeline();
        
        % Run analysis to get the measurements
        output_dir = fullfile(pwd, 'threshold_analysis');
        if ~exist(output_dir, 'dir')
            mkdir(output_dir);
        end
        
        results = pipeline.runAnalysis({chin_file}, output_dir);
        
        if ~isempty(results) && strcmp(results{1}.status, 'success')
            result = results{1};
            
            % Get IV1 measurements (used for filtering)
            measurements = result.extractedData.measurements.iv1;
            
            fprintf('=== CURRENT DATA DISTRIBUTION ===\n');
            
            % Series Resistance analysis
            series_r = measurements.seriesResistance;
            valid_series = series_r(~isnan(series_r) & ~isinf(series_r));
            
            if ~isempty(valid_series)
                fprintf('Series Resistance (MΩ):\n');
                fprintf('  Min: %.1f, Max: %.1f, Median: %.1f\n', ...
                    min(valid_series), max(valid_series), median(valid_series));
                fprintf('  25th percentile: %.1f, 75th percentile: %.1f\n', ...
                    prctile(valid_series, 25), prctile(valid_series, 75));
                fprintf('  Current threshold: 50 MΩ (%.0f%% would pass)\n', ...
                    100 * sum(valid_series <= 50) / length(valid_series));
                
                % Suggest better threshold
                suggested_series = prctile(valid_series, 80);
                fprintf('  Suggested threshold: %.1f MΩ (80%% would pass)\n', suggested_series);
            end
            
            fprintf('\n');
            
            % Seal Resistance analysis  
            seal_r = measurements.sealResistance;
            valid_seal = seal_r(~isnan(seal_r) & ~isinf(seal_r));
            
            if ~isempty(valid_seal)
                fprintf('Seal Resistance (GΩ):\n');
                fprintf('  Min: %.1f, Max: %.1f, Median: %.1f\n', ...
                    min(valid_seal), max(valid_seal), median(valid_seal));
                fprintf('  25th percentile: %.1f, 75th percentile: %.1f\n', ...
                    prctile(valid_seal, 25), prctile(valid_seal, 75));
                fprintf('  Current threshold: 50 GΩ (%.0f%% would pass)\n', ...
                    100 * sum(valid_seal <= 50) / length(valid_seal));
                
                % Suggest better threshold
                suggested_seal = prctile(valid_seal, 80);
                fprintf('  Suggested threshold: %.1f GΩ (80%% would pass)\n', suggested_seal);
            end
            
            fprintf('\n');
            
            % Capacitance analysis
            cap = measurements.capacitance;
            valid_cap = cap(~isnan(cap) & ~isinf(cap));
            
            if ~isempty(valid_cap)
                fprintf('Capacitance (pF):\n');
                fprintf('  Min: %.1f, Max: %.1f, Median: %.1f\n', ...
                    min(valid_cap), max(valid_cap), median(valid_cap));
                fprintf('  25th percentile: %.1f, 75th percentile: %.1f\n', ...
                    prctile(valid_cap, 25), prctile(valid_cap, 75));
                fprintf('  Current threshold: 250 pF (%.0f%% would pass)\n', ...
                    100 * sum(valid_cap <= 250) / length(valid_cap));
                
                % Suggest better threshold
                suggested_cap = prctile(valid_cap, 80);
                fprintf('  Suggested threshold: %.1f pF (80%% would pass)\n', suggested_cap);
            end
            
            fprintf('\n=== RECOMMENDED CONFIG UPDATE ===\n');
            if exist('suggested_series', 'var') && exist('suggested_seal', 'var') && exist('suggested_cap', 'var')
                fprintf('Update your NanionConfig.m with these values:\n\n');
                fprintf('obj.configData.filters = struct(...\n');
                fprintf('    ''maxSeriesResistance'', %.1f, ...\n', suggested_series);
                fprintf('    ''maxSealResistance'', %.1f, ...\n', suggested_seal);
                fprintf('    ''maxCapacitance'', %.1f);\n', suggested_cap);
                
                fprintf('\nOr test with relaxed thresholds:\n');
                fprintf('test_with_relaxed_filters(%.1f, %.1f, %.1f)\n', ...
                    suggested_series, suggested_seal, suggested_cap);
            end
            
        else
            fprintf('Could not analyze - pipeline failed\n');
        end
        
    catch ME
        fprintf('Analysis failed: %s\n', ME.message);
    end
end

function test_with_relaxed_filters(max_series, max_seal, max_cap)
    % TEST_WITH_RELAXED_FILTERS - Test with custom filter thresholds
    
    fprintf('\n=== TESTING WITH RELAXED FILTERS ===\n');
    fprintf('New thresholds: Series=%.1f MΩ, Seal=%.1f GΩ, Cap=%.1f pF\n', ...
        max_series, max_seal, max_cap);
    
    % Create custom config
    config = NanionConfig();
    config.updateParameter('filters', 'maxSeriesResistance', max_series);
    config.updateParameter('filters', 'maxSealResistance', max_seal);
    config.updateParameter('filters', 'maxCapacitance', max_cap);
    
    % Test with relaxed filters
    pipeline = NanionAnalysisPipeline();
    pipeline.config = config;  % This won't work due to private properties
    
    fprintf('Note: You need to update the config file directly\n');
    fprintf('The pipeline uses config during initialization\n');
end