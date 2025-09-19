classdef NanionAnalysisPipeline < handle
    %NANIONANALYSISPIPELINE Main controller for electrophysiology analysis
    %   Orchestrates the complete analysis workflow with proper error handling
    %   and logging. Designed for both single-file and batch processing.
    
    properties (Access = private)
        config
        logger
        ioManager
        fileDetector
        results
    end
    
    methods
        function obj = NanionAnalysisPipeline(configPath)
            %NANIONANALYSISPIPELINE Constructor
            %   configPath - Path to configuration file (optional)
            
            if nargin < 1
                configPath = [];
            end
            
            % Initialize core components
            obj.config = NanionConfig(configPath);
            obj.logger = NanionLogger(obj.config);
            obj.ioManager = NanionIOManager(obj.config, obj.logger);
            obj.fileDetector = NanionFileDetector(obj.logger);
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
            %PROCESSSINGLEFILE Core single-file processing logic
            %   This method will be expanded in later phases
            
            % For Phase 1, just demonstrate the data reading capability
            obj.logger.logInfo(sprintf('Reading data from: %s', fileInfo.name));
            
            % Read and parse data
            rawData = obj.ioManager.readFile(fileInfo.path);
            parsedData = obj.ioManager.parseData(rawData, fileInfo.protocol);
            
            % Create output structure
            result = struct(...
                'fileName', fileInfo.name, ...
                'protocol', fileInfo.protocol, ...
                'dataShape', size(parsedData.dataTable), ...
                'numSamples', size(parsedData.dataTable, 1) - parsedData.headerRows, ...
                'outputDir', fullfile(outputDir, fileInfo.name), ...
                'processingTime', 0);  % Will be populated in later phases
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
    end
    
    methods (Static)
        function result = processSingleFileStatic(fileInfo, outputDir, config)
            %PROCESSSINGLEFILESTATIC Static version for parallel processing
            %   Required because parfeval needs static methods
            
            % Create temporary instances for parallel workers
            logger = NanionLogger(config);
            ioManager = NanionIOManager(config, logger);
            
            % Create temporary pipeline instance
            tempPipeline = NanionAnalysisPipeline();
            tempPipeline.config = config;
            tempPipeline.logger = logger;
            tempPipeline.ioManager = ioManager;
            
            result = tempPipeline.processSingleFile(fileInfo, outputDir);
        end
    end
end