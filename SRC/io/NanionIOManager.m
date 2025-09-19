classdef NanionIOManager < handle
    %NANIONIOMANAGER Optimized file I/O for Nanion Excel files  
    %   Uses readcell() exclusively with no fallback methods
    %   Optimized for MATLAB 2025a with parallel processing support
    
    properties (Access = private)
        config
        logger
    end
    
    methods
        function obj = NanionIOManager(config, logger)
            %NANIONIOMANAGER Constructor
            
            if nargin < 2
                error('NanionIOManager:InsufficientArgs', 'Config and logger required');
            end
            
            obj.config = config;
            obj.logger = logger;
            % Note: File validation is handled internally in Phase 1
        end
        
        function rawData = readFile(obj, filePath)
            %READFILE Read Excel file using readcell() exclusively
            %   Returns raw cell array data with validation
            
            obj.logger.logInfo(sprintf('Reading file: %s', obj.getFileName(filePath)));
            
            % Pre-flight validation
            obj.validateFileForReading(filePath);
            
            tic;
            try
                % MATLAB 2025a optimized readcell call
                rawData = readcell(filePath, ...
                    'UseExcel', false, ...          % Use built-in parser (faster)
                    'EmptyFieldRule', 'missing');   % Handle empty cells as missing values
                
                readTime = toc;
                obj.logger.logInfo(sprintf('✓ File read successfully: %dx%d in %.2fs', ...
                    size(rawData, 1), size(rawData, 2), readTime));
                
                % Post-read validation
                obj.validateRawData(rawData, filePath);
                
            catch ME
                obj.logger.logError(sprintf('✗ readcell() failed for %s: %s', ...
                    filePath, ME.message));
                
                % No fallback methods per requirements - fail cleanly
                error('NanionIOManager:ReadFailed', ...
                    'File reading failed and fallbacks disabled: %s', ME.message);
            end
        end
        
        function parsedData = parseData(obj, rawData, protocolInfo)
            %PARSEDATA Parse raw data into structured format
            %   Returns structured data with headers and data sections identified
            
            obj.logger.logInfo('Parsing raw data structure...');
            
            try
                % Find header structure
                headerInfo = obj.findHeaderStructure(rawData);
                
                % Extract and validate headers
                headers = obj.extractHeaders(rawData, headerInfo);
                
                % Create structured data table
                dataTable = obj.createDataTable(rawData, headerInfo, headers);
                
                % Package results
                parsedData = struct(...
                    'dataTable', dataTable, ...
                    'headerInfo', headerInfo, ...
                    'protocolInfo', protocolInfo, ...
                    'headers', headers, ...
                    'headerRows', headerInfo.dataStartRow - 1);
                
                obj.logger.logInfo(sprintf('✓ Parsing complete: %d data rows, %d columns', ...
                    size(dataTable, 1) - parsedData.headerRows, size(dataTable, 2)));
                
            catch ME
                obj.logger.logError(sprintf('Data parsing failed: %s', ME.message));
                rethrow(ME);
            end
        end
        
        function batchData = readFilesBatch(obj, filePaths, protocolInfos)
            %READFILESBATCH Read multiple files efficiently
            %   Optimized for parallel processing when available
            
            numFiles = length(filePaths);
            obj.logger.logInfo(sprintf('Starting batch read of %d files', numFiles));
            
            batchData = cell(numFiles, 1);
            
            if obj.config.processing.useParallel && numFiles > 1
                % Parallel batch reading
                batchData = obj.readFilesBatchParallel(filePaths, protocolInfos);
            else
                % Sequential batch reading  
                batchData = obj.readFilesBatchSequential(filePaths, protocolInfos);
            end
        end
    end
    
    methods (Access = private)
        function validateFileForReading(obj, filePath)
            %VALIDATEFILEFORREADING Pre-read file validation
            
            % File existence and permissions
            if ~exist(filePath, 'file')
                error('NanionIOManager:FileNotFound', 'File not found: %s', filePath);
            end
            
            % File size check
            fileInfo = dir(filePath);
            fileSizeMB = fileInfo.bytes / (1024 * 1024);
            
            if fileSizeMB > obj.config.io.maxFileSizeMB
                obj.logger.logWarning(sprintf('Large file detected: %.1f MB', fileSizeMB));
            end
            
            % File format validation
            [~, ~, ext] = fileparts(filePath);
            if ~ismember(lower(ext), {'.xlsx', '.xls'})
                error('NanionIOManager:UnsupportedFormat', 'Unsupported file format: %s', ext);
            end
            
            obj.logger.logInfo(sprintf('File validation passed: %.1f MB %s file', fileSizeMB, ext));
        end
        
        function validateRawData(obj, rawData, filePath)
        %VALIDATERAWDATA Simple post-read data validation
        
        if isempty(rawData)
            error('NanionIOManager:EmptyFile', 'File contains no data: %s', filePath);
        end
        
        if size(rawData, 1) < 10
            error('NanionIOManager:InsufficientData', 'File has too few rows (%d): %s', ...
                size(rawData, 1), filePath);
        end
        
        if size(rawData, 2) < 20
            error('NanionIOManager:InsufficientColumns', 'File has too few columns (%d): %s', ...
                size(rawData, 2), filePath);
        end
        
        obj.logger.logInfo(sprintf('Data validation passed: %dx%d', size(rawData)));
    end
        
        function headerInfo = findHeaderStructure(obj, rawData)
            %FINDHEADERSTRUCTURE Simple header detection
            
            % Convert first column to strings for searching
            col1Strings = string(rawData(1:min(15, size(rawData,1)), 1));
            col1Strings(ismissing(col1Strings)) = "";
            
            % Find header rows
            sweepRow = find(contains(col1Strings, 'Sweep Results', 'IgnoreCase', true), 1);
            paramRow = find(contains(col1Strings, 'Parameter', 'IgnoreCase', true), 1);
            
            if isempty(sweepRow) || isempty(paramRow)
                error('NanionIOManager:HeadersNotFound', ...
                    'Could not find required headers in file');
            end
            
            headerInfo = struct(...
                'headerRow1Idx', sweepRow, ...
                'headerRow2Idx', paramRow, ...
                'dataStartRow', paramRow + 2);
            
            obj.logger.logInfo(sprintf('Headers found: Sweep=%d, Param=%d, Data=%d', ...
                sweepRow, paramRow, headerInfo.dataStartRow));
        end
        
        function headers = extractHeaders(obj, rawData, headerInfo)
            %EXTRACTHEADERS Create simple column headers
            
            numCols = size(rawData, 2);
            combinedHeaders = arrayfun(@(x) sprintf('Col_%d', x), 1:numCols, 'UniformOutput', false);
            
            headers = struct(...
                'combined', combinedHeaders);
            
            obj.logger.logInfo(sprintf('Generated %d column headers', numCols));
        end
        
        
        function dataTable = createDataTable(obj, rawData, headerInfo, headers)
        %CREATEDATATABLE Create MATLAB table from raw data
        
        % Extract data portion
        dataRows = rawData(headerInfo.dataStartRow:end, :);
        
        % Match column counts
        numDataCols = size(dataRows, 2);
        numHeaderCols = length(headers.combined);
        
        if numDataCols ~= numHeaderCols
            minCols = min(numDataCols, numHeaderCols);
            dataRows = dataRows(:, 1:minCols);
            headers.combined = headers.combined(1:minCols);
            obj.logger.logInfo(sprintf('Adjusted to %d columns', minCols));
        end
        
        % Create table - this should always work with our simple headers
        dataTable = array2table(dataRows, 'VariableNames', headers.combined);
        obj.logger.logInfo(sprintf('✓ Table created: %dx%d', size(dataTable)));
    end

        
        function batchData = readFilesBatchSequential(obj, filePaths, protocolInfos)
            %READFILESBATCHSEQUENTIAL Sequential batch processing
            
            numFiles = length(filePaths);
            batchData = cell(numFiles, 1);
            
            for i = 1:numFiles
                try
                    obj.logger.logInfo(sprintf('Reading file %d/%d', i, numFiles));
                    
                    rawData = obj.readFile(filePaths{i});
                    parsedData = obj.parseData(rawData, protocolInfos{i});
                    
                    batchData{i} = struct(...
                        'status', 'success', ...
                        'filePath', filePaths{i}, ...
                        'data', parsedData);
                    
                    % Memory cleanup for large batches
                    if mod(i, obj.config.processing.memoryCleanupInterval) == 0
                        obj.logger.logInfo('Performing memory cleanup...');
                        java.lang.System.gc();
                    end
                    
                catch ME
                    obj.logger.logError(sprintf('Failed to read file %d: %s', i, ME.message));
                    
                    batchData{i} = struct(...
                        'status', 'failed', ...
                        'filePath', filePaths{i}, ...
                        'error', ME.message);
                end
            end
        end
        
        function batchData = readFilesBatchParallel(obj, filePaths, protocolInfos)
            %READFILESBATCHPARALLEL Parallel batch processing
            
            obj.logger.logInfo('Starting parallel file reading...');
            
            numFiles = length(filePaths);
            batchData = cell(numFiles, 1);
            
            % Check parallel pool availability - FAIL if not available
            pool = gcp('nocreate');
            if isempty(pool)
                error('NanionIOManager:NoParallelPool', ...
                    'Parallel processing requested but no parallel pool available');
            end
            
            futures = parallel.FevalFuture.empty(numFiles, 0);
            
            for i = 1:numFiles
                futures(i) = parfeval(pool, @obj.readSingleFileStatic, 1, ...
                    filePaths{i}, protocolInfos{i}, obj.config);
            end
            
            % Collect results
            for i = 1:numFiles
                try
                    batchData{i} = fetchOutputs(futures(i));
                    batchData{i}.status = 'success';
                catch ME
                    batchData{i} = struct(...
                        'status', 'failed', ...
                        'filePath', filePaths{i}, ...
                        'error', ME.message);
                end
            end
        end
        
        
        function fileName = getFileName(obj, filePath)
            %GETFILENAME Extract filename from path
            [~, fileName, ext] = fileparts(filePath);
            fileName = [fileName, ext];
        end
    end
    
    methods (Static)
        function result = readSingleFileStatic(filePath, protocolInfo, config)
            %READSINGLEFILESTATIC Static method for parallel processing
            
            % Create temporary logger (no shared state in parallel)
            tempLogger = NanionLogger(config);
            tempIO = NanionIOManager(config, tempLogger);
            
            rawData = tempIO.readFile(filePath);
            parsedData = tempIO.parseData(rawData, protocolInfo);
            
            result = struct(...
                'filePath', filePath, ...
                'data', parsedData);
        end
    end
end