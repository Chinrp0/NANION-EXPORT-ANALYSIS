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
                    'EmptyFieldRule', 'skip', ...   % Handle empty cells consistently  
                    'MissingRule', 'omitrow');      % Skip completely empty rows
                
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
            %VALIDATERAWDATA Post-read data validation
            
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
            
            % Check for reasonable data density
            nonEmptyCells = sum(~cellfun(@isempty, rawData(:)));
            totalCells = numel(rawData);
            dataDensity = nonEmptyCells / totalCells;
            
            if dataDensity < 0.1
                obj.logger.logWarning(sprintf('Low data density (%.1f%%) in file', dataDensity * 100));
            end
            
            obj.logger.logInfo(sprintf('Data validation passed: %.1f%% density', dataDensity * 100));
        end
        
        function headerInfo = findHeaderStructure(obj, rawData)
            %FINDHEADERSTRUCTURE Locate header rows in data
            
            col1 = rawData(:, 1);
            
            % Find first empty cell in column 1
            emptyIdx = [];
            for i = 1:length(col1)
                if obj.isEmptyCell(col1{i})
                    emptyIdx = i;
                    break;
                end
            end
            
            if isempty(emptyIdx)
                error('NanionIOManager:NoHeaderStructure', 'Cannot find header structure (no empty cell in column 1)');
            end
            
            headerInfo = struct(...
                'emptyRowIdx', emptyIdx, ...
                'headerRow1Idx', emptyIdx + 1, ...
                'headerRow2Idx', emptyIdx + 2, ...
                'dataStartRow', emptyIdx + 3);
            
            obj.logger.logInfo(sprintf('Header structure: empty=%d, headers=%d,%d, data starts=%d', ...
                headerInfo.emptyRowIdx, headerInfo.headerRow1Idx, ...
                headerInfo.headerRow2Idx, headerInfo.dataStartRow));
        end
        
        function headers = extractHeaders(obj, rawData, headerInfo)
            %EXTRACTHEADERS Extract and clean header information
            
            % Get raw headers
            headerRow1 = rawData(headerInfo.headerRow1Idx, :);
            headerRow2 = rawData(headerInfo.headerRow2Idx, :);
            
            % Convert to strings and clean
            headerRow1 = obj.cleanHeaderRow(headerRow1);
            headerRow2 = obj.cleanHeaderRow(headerRow2);
            
            % Create combined headers for table
            numCols = min(length(headerRow1), length(headerRow2));
            combinedHeaders = cell(1, numCols);
            
            for i = 1:numCols
                combinedHeaders{i} = obj.createValidTableHeader(headerRow1{i}, headerRow2{i}, i);
            end
            
            headers = struct(...
                'row1', headerRow1, ...
                'row2', headerRow2, ...
                'combined', combinedHeaders);
        end
        
        function cleanRow = cleanHeaderRow(obj, rawRow)
            %CLEANHEADERROW Clean and standardize header row
            
            cleanRow = cell(size(rawRow));
            
            for i = 1:length(rawRow)
                cellValue = rawRow{i};
                
                if obj.isEmptyCell(cellValue)
                    cleanRow{i} = '';
                elseif isnumeric(cellValue)
                    cleanRow{i} = num2str(cellValue);
                elseif ischar(cellValue) || isstring(cellValue)
                    cleanRow{i} = char(strtrim(string(cellValue)));
                else
                    cleanRow{i} = '';
                end
            end
        end
        
        function header = createValidTableHeader(obj, row1Val, row2Val, colIdx)
            %CREATEVALIDTABLEHEADER Create valid MATLAB table header
            
            % Combine header parts
            combined = strtrim([row1Val, ' ', row2Val]);
            
            if isempty(combined)
                header = sprintf('Column_%d', colIdx);
            else
                % Make valid MATLAB variable name
                header = matlab.lang.makeValidName(combined);
                
                % Ensure uniqueness (basic approach)
                if strcmp(header, 'x_') || startsWith(header, 'x_')
                    header = sprintf('Col_%d_%s', colIdx, header);
                end
            end
        end
        
        function dataTable = createDataTable(obj, rawData, headerInfo, headers)
            %CREATEDATATABLE Create MATLAB table from raw data
            
            % Extract data portion
            dataRows = rawData(headerInfo.dataStartRow:end, :);
            
            % Trim to header length
            numHeaderCols = length(headers.combined);
            if size(dataRows, 2) > numHeaderCols
                dataRows = dataRows(:, 1:numHeaderCols);
            end
            
            % Create table
            try
                dataTable = array2table(dataRows, 'VariableNames', headers.combined);
            catch ME
                obj.logger.logError(sprintf('Table creation failed: %s', ME.message));
                
                % Fallback with generic headers
                genericHeaders = arrayfun(@(x) sprintf('Col_%d', x), 1:size(dataRows, 2), ...
                    'UniformOutput', false);
                dataTable = array2table(dataRows, 'VariableNames', genericHeaders);
            end
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
        
        function isEmpty = isEmptyCell(obj, cellValue)
            %ISEMPTYCELL Check if cell value is empty
            
            isEmpty = isempty(cellValue) || ...
                      (isnumeric(cellValue) && isnan(cellValue)) || ...
                      (ischar(cellValue) && isempty(strtrim(cellValue))) || ...
                      (isstring(cellValue) && (ismissing(cellValue) || strtrim(cellValue) == ""));
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