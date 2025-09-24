classdef NanionAnalysisPipeline < handle
    %NANIONANALYSISPIPELINE Main controller for electrophysiology analysis
    %   Orchestrates the complete analysis workflow with proper error handling
    %   and logging. Designed for both single-file and batch processing.
    
    properties (Access = private)
        config
        logger
        ioManager
        fileDetector
        dataExtractor  % ADDED FOR PHASE 2
        results
    end
    
    methods
        function obj = NanionAnalysisPipeline(configPath)
            %NANIONANALYSISPIPELINE Constructor
            %   configPath - Path to configuration file (optional)
            
            if nargin < 1
                configPath = [];
            end
            
            obj.ensureAnalysisPathAvailable();
            
            % Initialize core components
            obj.config = NanionConfig(configPath);
            obj.logger = NanionLogger(obj.config);
            obj.ioManager = NanionIOManager(obj.config, obj.logger);
            obj.fileDetector = NanionFileDetector(obj.logger);
            obj.dataExtractor = NanionDataExtractor(obj.config, obj.logger);  % ADDED FOR PHASE 2
            obj.results = {};
        end
        
        function results = runAnalysis(obj, filePaths, outputDir)
            %RUNANALYSIS Execute complete analysis pipeline
            %   filePaths - Cell array of file paths or single path string
            %   outputDir - Output directory path
            %   Returns: Cell array of result structures
            
            % Input validation
            if ischar(filePaths)
                filePaths = {filePaths};
            end
            
            if ~exist(outputDir, 'dir')
                mkdir(outputDir);
            end
            
            obj.logger.logInfo(sprintf('Starting analysis of %d files', length(filePaths)));
            obj.logger.logInfo(sprintf('Output directory: %s', outputDir));
            
            try
                % Phase 1: File validation and type detection
                validatedFiles = obj.validateAndCategorizeFiles(filePaths);
                
                if isempty(validatedFiles)
                    obj.logger.logError('No valid files found for processing');
                    results = {};
                    return;
                end
                
                % Phase 2: Process files (parallel or sequential)
                if obj.config.processing.useParallel && length(validatedFiles) > 1
                    results = obj.processFilesParallel(validatedFiles, outputDir);
                else
                    results = obj.processFilesSequential(validatedFiles, outputDir);
                end
                
                % Phase 3: Generate summary report
                obj.generateSummaryReport(results, outputDir);
                
                obj.logger.logInfo('Analysis pipeline completed successfully');
                
            catch ME
                obj.logger.logError(sprintf('Pipeline failed: %s', ME.message));
                obj.logger.logError(sprintf('Stack trace: %s', getReport(ME)));
                rethrow(ME);
            end
        end
        
        function fileInfo = validateAndCategorizeFiles(obj, filePaths)
            %VALIDATEANDCATEGORIZEFILES Validate files and detect protocols
            
            obj.logger.logInfo('Validating and categorizing input files...');
            
            fileInfo = {};
            for i = 1:length(filePaths)
                filePath = filePaths{i};
                
                try
                    % Basic file validation
                    if ~exist(filePath, 'file')
                        obj.logger.logWarning(sprintf('File not found: %s', filePath));
                        continue;
                    end
                    
                    % Quick read to determine file type
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
            
            obj.logger.logInfo(sprintf('File validation complete: %d/%d files valid', ...
                length(fileInfo), length(filePaths)));
        end
        
        function results = processFilesSequential(obj, validatedFiles, outputDir)
            %PROCESSFILESSEQUENTIAL Process files one by one
            
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
            %PROCESSFILESPARALLEL Process files in parallel
            
            obj.logger.logInfo(sprintf('Starting parallel processing with %d workers', ...
                obj.config.processing.maxWorkers));
            
            % Initialize parallel pool - FAIL if this doesn't work
            poolObj = obj.initializeParallelPool();
            
            if isempty(poolObj)
                error('NanionAnalysisPipeline:ParallelSetupFailed', ...
                    'Parallel processing requested but pool initialization failed');
            end
            
            results = cell(length(validatedFiles), 1);
            
            % Submit parallel jobs
            futures = parallel.FevalFuture.empty(length(validatedFiles), 0);
            
            for i = 1:length(validatedFiles)
                futures(i) = parfeval(poolObj, @obj.processSingleFileStatic, 1, ...
                    validatedFiles{i}, outputDir, obj.config);
            end
            
            % Collect results with progress monitoring
            for i = 1:length(validatedFiles)
                try
                    results{i} = fetchOutputs(futures(i));
                    results{i}.status = 'success';
                    
                    obj.logger.logInfo(sprintf('✓ Completed %d/%d: %s', ...
                        i, length(validatedFiles), validatedFiles{i}.name));
                        
                catch ME
                    results{i} = struct('status', 'failed', 'error', ME.message, ...
                        'fileName', validatedFiles{i}.name);
                    obj.logger.logError(sprintf('✗ Failed %d/%d: %s - %s', ...
                        i, length(validatedFiles), validatedFiles{i}.name, ME.message));
                end
            end
        end
        
        function result = processSingleFile(obj, fileInfo, outputDir)
            %PROCESSSINGLEFILE Core single-file processing logic - Phase 2 Version
            
            obj.logger.logInfo(sprintf('Processing data from: %s', fileInfo.name));
            
            try
                % Phase 2.1: Read and parse data (existing Phase 1 functionality)
                obj.logger.logInfo('Step 1: Reading and parsing data...');
                rawData = obj.ioManager.readFile(fileInfo.path);
                parsedData = obj.ioManager.parseData(rawData, fileInfo.protocol);
                
                % Phase 2.2: Extract measurements with Well_ID mapping
                obj.logger.logInfo('Step 2: Extracting measurements...');
                extractedData = obj.dataExtractor.extractMeasurements(parsedData);
                
                % Phase 2.3: Apply quality filters
                obj.logger.logInfo('Step 3: Applying quality filters...');
                filteredData = obj.dataExtractor.applyQualityFilters(extractedData);
                
                % Log filtering results
                obj.logger.logInfo(sprintf('Quality filtering: %d/%d wells passed (%.1f%%)', ...
                    filteredData.numWellsPassed, filteredData.numWellsTotal, ...
                    100 * filteredData.numWellsPassed / filteredData.numWellsTotal));
                
                % Create comprehensive result structure
                result = struct(...
                    'fileName', fileInfo.name, ...
                    'protocol', fileInfo.protocol, ...
                    'extractedData', extractedData, ...
                    'filteredData', filteredData, ...
                    'processingSteps', {{'dataReading', 'measurementExtraction', 'qualityFiltering'}}, ...
                    'outputDir', fullfile(outputDir, fileInfo.name));
                
                obj.logger.logInfo(sprintf('✓ Processing complete: %s', fileInfo.name));
                
            catch ME
                obj.logger.logError(sprintf('Processing failed for %s: %s', fileInfo.name, ME.message));
                rethrow(ME);
            end
        end
        
        function generateSummaryReport(obj, results, outputDir)
            %GENERATESUMMARYREPORT Create analysis summary
            
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
            %INITIALIZEPARALLELPOOL Setup parallel computing
            
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
            %EXTRACTFILENAME Get base filename without extension
            [~, fileName, ~] = fileparts(filePath);
        end

        function ensureAnalysisPathAvailable(obj)
            %ENSUREANALYSISPATHAVAILABLE Add analysis directory to path
            
            % Check if NanionDataExtractor can be found
            if exist('NanionDataExtractor', 'class')
                return; % Already available
            end
            
            % Try different possible locations
            possiblePaths = {'analysis', 'SRC/analysis', '../analysis'};
            
            for i = 1:length(possiblePaths)
                testPath = possiblePaths{i};
                if exist(fullfile(testPath, 'NanionDataExtractor.m'), 'file')
                    addpath(testPath);
                    fprintf('Added to path: %s\n', testPath);
                    return;
                end
            end
            
            % If we get here, the analysis directory wasn't found
            error('NanionAnalysisPipeline:AnalysisPathNotFound', ...
                'Could not locate analysis directory containing NanionDataExtractor.m');
        end
        
    end
    
    methods (Static)
        function result = processSingleFileStatic(fileInfo, outputDir, config)
            %PROCESSSINGLEFILESTATIC Static version for parallel processing - Phase 2
            
            % Create temporary instances for parallel workers
            logger = NanionLogger(config);
            ioManager = NanionIOManager(config, logger);
            dataExtractor = NanionDataExtractor(config, logger);  % ADDED FOR PHASE 2
            
            % Create temporary pipeline instance
            tempPipeline = NanionAnalysisPipeline();
            tempPipeline.config = config;
            tempPipeline.logger = logger;
            tempPipeline.ioManager = ioManager;
            tempPipeline.dataExtractor = dataExtractor;  % ADDED FOR PHASE 2
            
            result = tempPipeline.processSingleFile(fileInfo, outputDir);
        end
    end
end