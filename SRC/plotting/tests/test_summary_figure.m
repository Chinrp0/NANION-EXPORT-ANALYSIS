% Test script for NanionSummaryFigure
% Run this after successful pipeline analysis

clear all
close all

% Manually add paths to avoid pipeline's path checker
addpath('SRC/config');
addpath('SRC/utils');
addpath('SRC/io');
addpath('SRC/analysis');
addpath('SRC/fitting');
addpath('SRC/plotting');
addpath('SRC/pipeline');
addpath('SRC/detection');

% Test if NanionSummaryFigure loads
fprintf('Testing NanionSummaryFigure class loading...\n');
try
    config = NanionConfig();
    logger = NanionLogger(config);
    figGen = NanionSummaryFigure(config, logger);
    fprintf('✓ NanionSummaryFigure loaded successfully\n\n');
catch ME
    fprintf('✗ Error loading NanionSummaryFigure:\n');
    fprintf('  %s\n', ME.message);
    fprintf('  File location: %s\n', which('NanionSummaryFigure'));
    error('Cannot proceed - fix class syntax first');
end

% Run analysis
fprintf('Running pipeline analysis...\n');
pipeline = NanionAnalysisPipeline();
filepathAct1 = "C:\Users\xdach\OneDrive - Johns Hopkins\Maher_Lab\Protocols\Matlab_scripts\Fede\Master files for CHIN 9_17_2025\18T22880 NGN2 ACT_IV raw.xlsx";
outputDir = 'output/';

results = pipeline.runAnalysis(filepathAct1, outputDir);

% Extract data from successful result
successResult = results{1};
filteredData = successResult.filteredData;
fittedData = successResult.fittedData;
summaryTable = successResult.summaryTable;

% Find the output folder that was just created
outputFolders = dir(fullfile(outputDir, '2025*'));
if ~isempty(outputFolders)
    [~, idx] = max([outputFolders.datenum]);
    latestFolder = fullfile(outputDir, outputFolders(idx).name);
else
    latestFolder = outputDir;
end

% Create figure generator (already tested above)
figGenerator = NanionSummaryFigure(config, logger);

% Generate summary figure
fprintf('\nGenerating summary figure...\n');
figHandle = figGenerator.createSummaryFigure(filteredData, fittedData, summaryTable, latestFolder);

fprintf('\n✓ Summary figure created successfully!\n');
fprintf('  Output folder: %s\n', latestFolder);
fprintf('  Files saved: summary_figure_*.png/fig/pdf\n\n');
