%% Test Script for Boltzmann Fitting and Plotting
% Tests normalization, fitting, and plot generation

clear; clc;

%% Setup paths
basePath = "C:\Users\xdach\OneDrive - Johns Hopkins\Maher_Lab\Protocols\Matlab_scripts\Fede\Master files for CHIN 9_17_2025\";
actFile = fullfile(basePath, "18T22880 NGN2 ACT_IV raw.xlsx");
inactFile = fullfile(basePath, "18T22880 NGN2 INACT.xlsx");

%% Test Activation Protocol
fprintf('===========================================\n');
fprintf('TESTING ACTIVATION PROTOCOL\n');
fprintf('===========================================\n\n');

pipeline = NanionAnalysisPipeline();
act_results = pipeline.runAnalysis({actFile}, 'test_output');

r_act = act_results{1};

% Check normalization
cond = r_act.filteredData.measurements.iv1.conductance;
cond_raw = r_act.filteredData.measurements.iv1.conductance_raw;

fprintf('\n=== NORMALIZATION CHECK ===\n');
fprintf('Conductance range: %.3f to %.3f (should be 0.000 to 1.000)\n', ...
    min(cond(:)), max(cond(:)));
fprintf('Raw conductance range: %.3f to %.3f nS\n', ...
    min(cond_raw(:)), max(cond_raw(:)));

% Find good wells
goodWells = [];
for i = 1:length(r_act.fittedData.wells)
    if strcmp(r_act.fittedData.wells(i).iv1.fitQuality, 'Good')
        goodWells(end+1) = i;
    end
end

fprintf('\n=== FIT SUMMARY ===\n');
fprintf('Total wells: %d\n', length(r_act.fittedData.wells));
fprintf('Good fits: %d (IV1+IV2 combined)\n', r_act.fittedData.summary.fitResults.good);
fprintf('Wells with good IV1 fits: %d\n', length(goodWells));

% Show example good well
if ~isempty(goodWells)
    goodWell = r_act.fittedData.wells(goodWells(1));
    fprintf('\n=== EXAMPLE GOOD WELL: %s ===\n', goodWell.wellID);
    fprintf('IV1: V_mid=%.2f mV, k=%.2f, R²=%.3f, Quality=%s\n', ...
        goodWell.iv1.fitParams.V_mid, goodWell.iv1.fitParams.k, ...
        goodWell.iv1.fitParams.R2, goodWell.iv1.fitQuality);
    if ~isempty(goodWell.iv2)
        fprintf('IV2: V_mid=%.2f mV, k=%.2f, R²=%.3f, Quality=%s\n', ...
            goodWell.iv2.fitParams.V_mid, goodWell.iv2.fitParams.k, ...
            goodWell.iv2.fitParams.R2, goodWell.iv2.fitQuality);
    end
end

% Plot first good activation well
if ~isempty(goodWells)
    fprintf('\n=== PLOTTING ACTIVATION (WELL %s) ===\n', goodWell.wellID);
    
    plotter = NanionBoltzmannPlotter(pipeline.config, pipeline.logger);
    voltages = r_act.protocol.voltages;
    
    % Find well index in filtered data
    wellIdxInFiltered = find(strcmp(r_act.filteredData.wellIDs, goodWell.wellID));
    
    % Extract IV1 data
    iv1Data = struct(...
        'conductance', r_act.filteredData.measurements.iv1.conductance(wellIdxInFiltered, :), ...
        'peakCurrent', r_act.filteredData.measurements.iv1.peakCurrent(wellIdxInFiltered, :));
    
    % Extract IV2 data
    iv2Data = struct(...
        'conductance', r_act.filteredData.measurements.iv2.conductance(wellIdxInFiltered, :), ...
        'peakCurrent', r_act.filteredData.measurements.iv2.peakCurrent(wellIdxInFiltered, :));
    
    % Plot
    plotter.plotActivationDualAxis(goodWell.wellID, voltages, iv1Data, iv2Data, goodWell.iv1, goodWell.iv2);
    
    fprintf('✓ Activation plot generated\n');
end

%% Test Inactivation Protocol
fprintf('\n\n===========================================\n');
fprintf('TESTING INACTIVATION PROTOCOL\n');
fprintf('===========================================\n\n');

inact_results = pipeline.runAnalysis({inactFile}, 'test_output');
r_inact = inact_results{1};

% Find good wells
goodWells_inact = [];
for i = 1:length(r_inact.fittedData.wells)
    if strcmp(r_inact.fittedData.wells(i).iv1.fitQuality, 'Good')
        goodWells_inact(end+1) = i;
    end
end

fprintf('=== FIT SUMMARY ===\n');
fprintf('Total wells: %d\n', length(r_inact.fittedData.wells));
fprintf('Good fits: %d (IV1+IV2 combined)\n', r_inact.fittedData.summary.fitResults.good);
fprintf('Wells with good IV1 fits: %d\n', length(goodWells_inact));

% Show example good well
if ~isempty(goodWells_inact)
    goodWell_inact = r_inact.fittedData.wells(goodWells_inact(1));
    fprintf('\n=== EXAMPLE GOOD WELL: %s ===\n', goodWell_inact.wellID);
    fprintf('IV1: V_mid=%.2f mV, k=%.2f, R²=%.3f, Quality=%s\n', ...
        goodWell_inact.iv1.fitParams.V_mid, goodWell_inact.iv1.fitParams.k, ...
        goodWell_inact.iv1.fitParams.R2, goodWell_inact.iv1.fitQuality);
    if ~isempty(goodWell_inact.iv2)
        fprintf('IV2: V_mid=%.2f mV, k=%.2f, R²=%.3f, Quality=%s\n', ...
            goodWell_inact.iv2.fitParams.V_mid, goodWell_inact.iv2.fitParams.k, ...
            goodWell_inact.iv2.fitParams.R2, goodWell_inact.iv2.fitQuality);
    end
end

% Plot first good inactivation well
if ~isempty(goodWells_inact)
    fprintf('\n=== PLOTTING INACTIVATION (WELL %s) ===\n', goodWell_inact.wellID);
    
    plotter = NanionBoltzmannPlotter(pipeline.config, pipeline.logger);
    voltages = r_inact.protocol.voltages;
    
    % Find well index in filtered data
    wellIdxInFiltered = find(strcmp(r_inact.filteredData.wellIDs, goodWell_inact.wellID));
    
    % Extract IV1 data
    iv1Data = struct(...
        'inactivationData', r_inact.filteredData.measurements.iv1.inactivationData(wellIdxInFiltered, :), ...
        'activationData', r_inact.filteredData.measurements.iv1.activationData(wellIdxInFiltered, :));
    
    % Extract IV2 data
    iv2Data = struct(...
        'inactivationData', r_inact.filteredData.measurements.iv2.inactivationData(wellIdxInFiltered, :), ...
        'activationData', r_inact.filteredData.measurements.iv2.activationData(wellIdxInFiltered, :));
    
    % Plot
    plotter.plotInactivationDualAxis(goodWell_inact.wellID, voltages, iv1Data, iv2Data, goodWell_inact.iv1, goodWell_inact.iv2);
    
    fprintf('✓ Inactivation plot generated\n');
end

%% Summary
fprintf('\n\n===========================================\n');
fprintf('TESTS COMPLETE\n');
fprintf('===========================================\n');
fprintf('Activation: %d good fits, plot generated\n', length(goodWells));
fprintf('Inactivation: %d good fits, plot generated\n', length(goodWells_inact));
fprintf('\nCheck the figure windows to verify:\n');
fprintf('1. Boltzmann fit curves are aligned with data points\n');
fprintf('2. Both IV1 and IV2 are plotted\n');
fprintf('3. Y-axis shows "Normalized Conductance (0-1)" for activation\n');
fprintf('4. Fits look smooth and follow the data\n');
