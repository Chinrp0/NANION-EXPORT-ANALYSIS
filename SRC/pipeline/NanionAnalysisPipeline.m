classdef NanionAnalysisPipeline < handle
    %NANIONANALYSISPIPELINE Main controller for electrophysiology analysis
    %   UPDATED: Added Step 5 for statistics calculation and metadata export
    
    properties (Access = public)
        config
        logger
    end
    
    properties (Access = private)
        ioManager
        fileDetector
        dataExtractor
        results
    end
    
    methods
        function obj = NanionAnalysisPipeline(configPath)
            if nargin < 1
                configPath = [];
            end
            
            obj.ensureAnalysisPathAvailable();
            
            obj.config = NanionConfig(configPath);
            obj.logger = NanionLogger(obj.config);
            obj.ioManager = NanionIOManager(obj.config, obj.logger);
            obj.fileDetector = NanionFileDetector(obj.logger);
            obj.dataExtractor = NanionDataExtractor(obj.config, obj.logger);
            obj.results = {};
        end
        
        function results = runAnalysis(obj, filePaths, outputDir)
            %RUNANALYSIS Execute complete analysis pipeline with export
            
            if ischar(filePaths)
                filePaths = {filePaths};
            end
            
            if ~exist(outputDir, 'dir')
                mkdir(outputDir);
            end
            
            obj.logger.logInfo(sprintf('Starting analysis of %d files', length(filePaths)));
            obj.logger.logInfo(sprintf('Output directory: %s', outputDir));
            
            try
                % Phase 1: File validation
                validatedFiles = obj.validateAndCategorizeFiles(filePaths);
                
                if isempty(validatedFiles)
                    obj.logger.logError('No valid files found');
                    results = {};
                    return;
                end
                
                % Phase 2: Process files
                if obj.config.processing.useParallel && length(validatedFiles) > 1
                    results = obj.processFilesParallel(validatedFiles, outputDir);
                else
                    results = obj.processFilesSequential(validatedFiles, outputDir);
                end
                
                % Phase 3: Export summary tables
                obj.exportSummaryTables(results, outputDir);
                
                % Phase 4: Generate summary report
                obj.generateSummaryReport(results, outputDir);
                
                obj.logger.logInfo('✓ Analysis pipeline completed successfully');
                
            catch ME
                obj.logger.logError(sprintf('Pipeline failed: %s', ME.message));
                obj.logger.logError(sprintf('Stack trace: %s', getReport(ME)));
                rethrow(ME);
            end
        end
        
        function fileInfo = validateAndCategorizeFiles(obj, filePaths)
            obj.logger.logInfo('Validating and categorizing input files...');
            
            fileInfo = {};
            for i = 1:length(filePaths)
                filePath = filePaths{i};
                
                try
                    if ~exist(filePath, 'file')
                        obj.logger.logWarning(sprintf('File not found: %s', filePath));
                        continue;
                    end
                    
                    protocolInfo = obj.fileDetector.detectProtocol(filePath);
                    
                    if isempty(protocolInfo)
                        obj.logger.logWarning(sprintf('Could not detect protocol: %s', filePath));
                        continue;
                    end
                    
                    fileInfo{end+1} = struct(...
                        'path', filePath, ...
                        'name', obj.extractFileName(filePath), ...
                        'protocol', protocolInfo, ...
                        'validated', true);
                    
                    obj.logger.logInfo(sprintf('✓ %s: %s protocol (%d IVs)', ...
                        fileInfo{end}.name, protocolInfo.type, protocolInfo.numIVs));
                    
                catch ME
                    obj.logger.logError(sprintf('Validation failed for %s: %s', filePath, ME.message));
                end
            end
            
            obj.logger.logInfo(sprintf('File validation: %d/%d files valid', ...
                length(fileInfo), length(filePaths)));
        end
        
        function results = processFilesSequential(obj, validatedFiles, outputDir)
            results = cell(length(validatedFiles), 1);
            
            for i = 1:length(validatedFiles)
                fileInfo = validatedFiles{i};
                obj.logger.logInfo(sprintf('Processing file %d/%d: %s', ...
                    i, length(validatedFiles), fileInfo.name));
                
                try
                    results{i} = obj.processSingleFile(fileInfo, outputDir);
                    results{i}.status = 'success';
                    
                catch ME
                    obj.logger.logError(sprintf('Failed to process %s: %s', ...
                        fileInfo.name, ME.message));
                    results{i} = struct('status', 'failed', 'error', ME.message, ...
                        'fileName', fileInfo.name);
                end
            end
        end
        
        function results = processFilesParallel(obj, validatedFiles, outputDir)
            obj.logger.logInfo(sprintf('Starting parallel processing with %d workers', ...
                obj.config.processing.maxWorkers));
            
            poolObj = obj.initializeParallelPool();
            
            if isempty(poolObj)
                error('NanionAnalysisPipeline:ParallelSetupFailed', ...
                    'Parallel processing requested but pool initialization failed');
            end
            
            results = cell(length(validatedFiles), 1);
            futures = parallel.FevalFuture.empty(length(validatedFiles), 0);
            
            for i = 1:length(validatedFiles)
                futures(i) = parfeval(poolObj, @obj.processSingleFileStatic, 1, ...
                    validatedFiles{i}, outputDir, obj.config);
            end
            
            for i = 1:length(validatedFiles)
                try
                    results{i} = fetchOutputs(futures(i));
                    results{i}.status = 'success';
                    
                    obj.logger.logInfo(sprintf('✓ Completed %d/%d: %s', ...
                        i, length(validatedFiles), validatedFiles{i}.name));
                        
                catch ME
                    results{i} = struct('status', 'failed', 'error', ME.message, ...
                        'fileName', validatedFiles{i}.name);
                    obj.logger.logError(sprintf('✗ Failed %d/%d: %s', ...
                        i, length(validatedFiles), validatedFiles{i}.name));
                end
            end
        end
        
        function result = processSingleFile(obj, fileInfo, outputDir)
            %PROCESSSINGLEFILE Core processing with statistics and export
            
            obj.logger.logInfo(sprintf('Processing: %s', fileInfo.name));
            
            try
                % Step 1: Read and parse
                obj.logger.logInfo('Step 1: Reading and parsing data...');
                rawData = obj.ioManager.readFile(fileInfo.path);
                parsedData = obj.ioManager.parseData(rawData, fileInfo.protocol);
                parsedData.fileName = fileInfo.name;  % Store file name
                
                % Step 2: Extract measurements (now includes current density & metadata)
                obj.logger.logInfo('Step 2: Extracting measurements...');
                extractedData = obj.dataExtractor.extractMeasurements(parsedData);
                
                % Step 3: Apply quality filters
                obj.logger.logInfo('Step 3: Applying quality filters...');
                filteredData = obj.dataExtractor.applyQualityFilters(extractedData);
                
                obj.logger.logInfo(sprintf('Quality filtering: %d/%d wells passed (%.1f%%)', ...
                    filteredData.numWellsPassed, filteredData.numWellsTotal, ...
                    100 * filteredData.numWellsPassed / filteredData.numWellsTotal));
                
                % Step 4: Calculate sweep statistics
                obj.logger.logInfo('Step 4: Calculating sweep statistics...');
                filteredData = obj.dataExtractor.calculateSweepStatistics(filteredData);
                
                % Step 5: Fit Boltzmann curves
                obj.logger.logInfo('Step 5: Fitting Boltzmann curves...');
                fitter = NanionBoltzmannFitter(obj.config, obj.logger);
                fittedData = fitter.fitBoltzmann(filteredData);
                
                obj.logger.logInfo(sprintf('Boltzmann fitting: %d Good, %d Acceptable, %d Poor, %d Failed', ...
                    fittedData.summary.fitResults.good, ...
                    fittedData.summary.fitResults.acceptable, ...
                    fittedData.summary.fitResults.poor, ...
                    fittedData.summary.fitResults.failed));
                
                % Step 6: Build summary table
                obj.logger.logInfo('Step 6: Building summary table...');
                tableBuilder = NanionSummaryTableBuilder(obj.config, obj.logger);
                summaryTable = tableBuilder.buildSummaryTable(filteredData, fittedData, fileInfo.name);
                
                % Create result structure
                result = struct(...
                    'fileName', fileInfo.name, ...
                    'protocol', fileInfo.protocol, ...
                    'extractedData', extractedData, ...
                    'filteredData', filteredData, ...
                    'fittedData', fittedData, ...
                    'summaryTable', summaryTable, ...
                    'processingSteps', {{'dataReading', 'measurementExtraction', ...
                                        'qualityFiltering', 'statisticsCalculation', ...
                                        'boltzmannFitting', 'summaryTableBuilding'}}, ...
                    'outputDir', fullfile(outputDir, fileInfo.name));
                
                obj.logger.logInfo(sprintf('✓ Processing complete: %s', fileInfo.name));
                
            catch ME
                obj.logger.logError(sprintf('Processing failed for %s: %s', fileInfo.name, ME.message));
                rethrow(ME);
            end
        end

        function exportSummaryTables(obj, results, outputDir)
            %EXPORTSUMMARYTABLES Export all summary tables with grouping
            
            obj.logger.logInfo('=== EXPORTING SUMMARY TABLES ===');
            
            % Filter successful results
            successfulResults = results(cellfun(@(x) strcmp(x.status, 'success'), results));
            
            if isempty(successfulResults)
                obj.logger.logWarning('No successful results to export');
                return;
            end
            
            % Extract summary tables and file names
            summaryTables = cellfun(@(x) x.summaryTable, successfulResults, 'UniformOutput', false);
            fileNames = cellfun(@(x) x.fileName, successfulResults, 'UniformOutput', false);
            
            % Create exporter
            exporter = NanionMetadataExporter(obj.config, obj.logger);
            
            % Export individual and aggregated tables
            if length(summaryTables) == 1
                % Single file
                outputPath = exporter.exportSummaryTable(summaryTables{1}, outputDir, fileNames{1});
            else
                % Multiple files
                outputPath = exporter.exportMultipleFiles(summaryTables, outputDir, fileNames);
                
                % Also export grouped summaries
                aggregatedTable = vertcat(summaryTables{:});
                exporter.exportGroupedSummaries(aggregatedTable, outputPath);
            end
            
            obj.logger.logInfo(sprintf('✓ Summary tables exported to: %s', outputPath));
        end

        function generateSummaryReport(obj, results, outputDir)
            successCount = sum(cellfun(@(x) strcmp(x.status, 'success'), results));
            totalCount = length(results);
            
            summaryFile = fullfile(outputDir, 'analysis_summary.txt');
            
            fid = fopen(summaryFile, 'w');
            if fid > 0
                fprintf(fid, '=== NANION ANALYSIS SUMMARY ===\n');
                fprintf(fid, 'Date: %s\n', datestr(now));
                fprintf(fid, 'Total files: %d\n', totalCount);
                fprintf(fid, 'Successful: %d\n', successCount);
                fprintf(fid, 'Failed: %d\n', totalCount - successCount);
                fprintf(fid, 'Success rate: %.1f%%\n', 100 * successCount / totalCount);
                fprintf(fid, '\n--- FILE DETAILS ---\n');
                
                for i = 1:length(results)
                    if strcmp(results{i}.status, 'success')
                        fprintf(fid, '✓ %s\n', results{i}.fileName);
                    else
                        fprintf(fid, '✗ %s: %s\n', results{i}.fileName, results{i}.error);
                    end
                end
                
                fclose(fid);
            end
            
            obj.logger.logInfo(sprintf('Summary report saved: %s', summaryFile));
        end
    end
    
    methods (Access = private)
        function poolObj = initializeParallelPool(obj)
            poolObj = gcp('nocreate');
            
            if isempty(poolObj)
                try
                    poolObj = parpool('Processes', obj.config.processing.maxWorkers, ...
                        'IdleTimeout', 30);
                    obj.logger.logInfo(sprintf('Created parallel pool: %d workers', ...
                        poolObj.NumWorkers));
                catch ME
                    error('NanionAnalysisPipeline:ParallelPoolFailed', ...
                        'Failed to create parallel pool: %s', ME.message);
                end
            else
                obj.logger.logInfo(sprintf('Using existing parallel pool: %d workers', ...
                    poolObj.NumWorkers));
            end
        end
        
        function fileName = extractFileName(~, filePath)
            [~, fileName, ~] = fileparts(filePath);
        end

        function ensureAnalysisPathAvailable(obj)
            requiredComponents = struct(...
                'NanionConfig', 'config', ...
                'NanionLogger', 'utils', ...
                'NanionDataExtractor', 'analysis', ...
                'NanionBoltzmannFitter', 'fitting', ...
                'BoltzmannModel', 'fitting', ...
                'FitQualityAssessor', 'fitting', ...
                'NanionBoltzmannPlotter', 'plotting', ...
                'NanionSummaryTableBuilder', 'io', ...
                'NanionMetadataExporter', 'io');
            
            componentNames = fieldnames(requiredComponents);
            missingComponents = {};
            
            for i = 1:length(componentNames)
                className = componentNames{i};
                if ~exist(className, 'class')
                    missingComponents{end+1} = className;
                end
            end
            
            if isempty(missingComponents)
                return;
            end
            
            fprintf('Some required classes not found. Attempting to add paths...\n');
            
            currentFile = mfilename('fullpath');
            currentDir = fileparts(currentFile);
            
            possibleRoots = {
                currentDir,
                fileparts(currentDir),
                fullfile(fileparts(currentDir), 'SRC'),
                pwd
            };
            
            repoRoot = '';
            for i = 1:length(possibleRoots)
                testRoot = possibleRoots{i};
                if exist(fullfile(testRoot, 'config'), 'dir') && ...
                   exist(fullfile(testRoot, 'analysis'), 'dir') && ...
                   exist(fullfile(testRoot, 'fitting'), 'dir')
                    repoRoot = testRoot;
                    break;
                end
            end
            
            if isempty(repoRoot)
                error('NanionAnalysisPipeline:PathNotFound', ...
                    ['Cannot locate repository root. Missing classes: ' strjoin(missingComponents, ', ')]);
            end
            
            requiredDirs = {'config', 'utils', 'io', 'analysis', 'fitting', 'plotting', 'pipeline', 'detection'};
            
            for i = 1:length(requiredDirs)
                dirPath = fullfile(repoRoot, requiredDirs{i});
                if exist(dirPath, 'dir') && ~contains(path, dirPath)
                    addpath(dirPath);
                    fprintf('Added to path: %s\n', dirPath);
                end
            end
            
            stillMissing = {};
            for i = 1:length(componentNames)
                className = componentNames{i};
                if ~exist(className, 'class')
                    stillMissing{end+1} = className;
                end
            end
            
            if ~isempty(stillMissing)
                error('NanionAnalysisPipeline:PathSetupFailed', ...
                    ['Failed to locate required classes: ' strjoin(stillMissing, ', ')]);
            end
            
            fprintf('✓ All required paths added successfully\n\n');
        end
    end
    
    methods (Static)
        function result = processSingleFileStatic(fileInfo, outputDir, config)
            logger = NanionLogger(config);
            ioManager = NanionIOManager(config, logger);
            dataExtractor = NanionDataExtractor(config, logger);
            
            tempPipeline = NanionAnalysisPipeline();
            tempPipeline.config = config;
            tempPipeline.logger = logger;
            tempPipeline.ioManager = ioManager;
            tempPipeline.dataExtractor = dataExtractor;
            
            result = tempPipeline.processSingleFile(fileInfo, outputDir);
        end
    end
end
