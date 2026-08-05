classdef NanionAnalysisPipeline < handle
    %NANIONANALYSISPIPELINE Main controller for electrophysiology analysis
    %   UPDATED: Batch processing with protocol grouping + aggregated outputs
    
    properties (Access = public)
        config
        logger
    end
    
    properties (Access = private)
        ioManager
        fileDetector
        dataExtractor
        results
        cache
        reviewSession    % QCReviewSession (created lazily when qc.enableReview)
        reviewStoreDir   % directory holding the persisted qc decisions
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
            obj.cache = containers.Map('KeyType', 'char', 'ValueType', 'any');
        end

        function cachedData = getCachedData(obj, filePath, dataType)
            %GETCACHEDDATA Retrieve cached data if available
            fileInfo = dir(filePath);
            cacheKey = sprintf('%s_%s_%.0f', filePath, dataType, fileInfo.datenum);
            
            if isKey(obj.cache, cacheKey)
                obj.logger.logInfo('✓ Using cached data');
                cachedData = obj.cache(cacheKey);
            else
                cachedData = [];
            end
        end
        
        function setCachedData(obj, filePath, dataType, data)
            %SETCACHEDDATA Store data in cache
            fileInfo = dir(filePath);
            cacheKey = sprintf('%s_%s_%.0f', filePath, dataType, fileInfo.datenum);
            obj.cache(cacheKey) = data;
        end
        
        function results = runAnalysis(obj, filePaths, outputDir)
            %RUNANALYSIS Execute analysis with automatic batch detection
            %   Single file: Process normally
            %   Multiple files: Auto-group by protocol, generate aggregated outputs
            
            if ischar(filePaths)
                filePaths = {filePaths};
            end
            
            if ~exist(outputDir, 'dir')
                mkdir(outputDir);
            end

            obj.logger.logInfo(sprintf('Starting analysis of %d file(s)', length(filePaths)));
            obj.logger.logInfo(sprintf('Output directory: %s', outputDir));

            % Set up the QC review session (loads any prior decisions so
            % overrides survive across runs). Only when review is enabled.
            obj.initReviewSession(outputDir);
            
            try
                % Phase 1: Validate and categorize files
                validatedFiles = obj.validateAndCategorizeFiles(filePaths);
                
                if isempty(validatedFiles)
                    obj.logger.logError('No valid files found');
                    results = {};
                    return;
                end
                
                % Phase 2: Group by protocol type
                protocolGroups = obj.groupFilesByProtocol(validatedFiles);
                
                % Phase 3: Determine processing mode
                isBatchMode = length(validatedFiles) > 1;
                
                if isBatchMode
                    obj.logger.logInfo(sprintf('=== BATCH MODE: %d files, %d protocol group(s) ===', ...
                        length(validatedFiles), length(fieldnames(protocolGroups))));
                    results = obj.processBatchMode(protocolGroups, outputDir);
                else
                    obj.logger.logInfo('=== SINGLE FILE MODE ===');
                    results = obj.processSingleMode(validatedFiles{1}, outputDir);
                end
                
                obj.logger.logInfo('✓ Analysis pipeline completed successfully');
                
            catch ME
                obj.logger.logError(sprintf('Pipeline failed: %s', ME.message));
                obj.logger.logError(sprintf('Stack trace: %s', getReport(ME)));
                rethrow(ME);
            end
        end
        
        function protocolGroups = groupFilesByProtocol(obj, validatedFiles)
            %GROUPFILESBYPROTOCOL Separate files by activation/inactivation
            
            obj.logger.logInfo('Grouping files by protocol type...');
            
            protocolGroups = struct();
            
            for i = 1:length(validatedFiles)
                fileInfo = validatedFiles{i};
                protocolType = fileInfo.protocol.type;
                
                if ~isfield(protocolGroups, protocolType)
                    protocolGroups.(protocolType) = {};
                end
                
                protocolGroups.(protocolType){end+1} = fileInfo;
            end
            
            % Log grouping results
            protocolNames = fieldnames(protocolGroups);
            for i = 1:length(protocolNames)
                protocolType = protocolNames{i};
                numFiles = length(protocolGroups.(protocolType));
                obj.logger.logInfo(sprintf('  %s: %d file(s)', protocolType, numFiles));
            end
        end
        
        function results = processSingleMode(obj, fileInfo, outputDir)
            %PROCESSSINGLEMODE Standard single-file processing
            
            % Create file-specific output folder
            [inputDir, ~, ~] = fileparts(fileInfo.path);
            fileOutputDir = fullfile(inputDir, 'Analysis_Output', fileInfo.name);
            
            if ~exist(fileOutputDir, 'dir')
                mkdir(fileOutputDir);
            end
            
            % Process file
            result = obj.processSingleFile(fileInfo, fileOutputDir);
            result.status = 'success';
            
            % Export summary table
            exporter = NanionXLSXExporter(obj.config, obj.logger);
            exporter.exportSummaryTable(result.summaryTable, result.filteredData, ...
                result.fittedData, fileOutputDir, fileInfo.name);
            
            results = {result};
            
            % Auto-open folder
            obj.openOutputFolder(fileOutputDir);
        end
        
        function results = processBatchMode(obj, protocolGroups, outputDir)
            %PROCESSBATCHMODE Process multiple files grouped by protocol
            
            % Create batch output folder
            timestamp = datestr(now, 'yyyymmdd_HHMMSS');
            batchOutputDir = fullfile(outputDir, sprintf('Batch_%s', timestamp));
            mkdir(batchOutputDir);
            
            obj.logger.logInfo(sprintf('Batch output directory: %s', batchOutputDir));
            
            allResults = {};
            protocolNames = fieldnames(protocolGroups);
            
            % Process each protocol group
            for p = 1:length(protocolNames)
                protocolType = protocolNames{p};
                filesInGroup = protocolGroups.(protocolType);
                
                obj.logger.logInfo(sprintf('\n=== PROCESSING %s GROUP (%d files) ===', ...
                    upper(protocolType), length(filesInGroup)));
                
                % Create protocol-specific subfolder
                protocolOutputDir = fullfile(batchOutputDir, protocolType);
                mkdir(protocolOutputDir);
                
                % Process all files in this protocol group
                groupResults = obj.processProtocolGroup(filesInGroup, protocolOutputDir);
                
                allResults = [allResults; groupResults];
            end
            
            results = allResults;
            
            % Auto-open batch folder
            obj.openOutputFolder(batchOutputDir);
        end
        
        function groupResults = processProtocolGroup(obj, filesInGroup, protocolOutputDir)
            %PROCESSPROTOCOLGROUP Process files + generate aggregated outputs
            
            numFiles = length(filesInGroup);
            groupResults = cell(numFiles, 1);
            
            % Step 1: Process each file individually (with Figure 1)
            obj.logger.logInfo(sprintf('Step 1: Processing %d individual files...', numFiles));
            
            for i = 1:numFiles
                fileInfo = filesInGroup{i};
                obj.logger.logInfo(sprintf('  File %d/%d: %s', i, numFiles, fileInfo.name));
                
                try
                    % Process file (generates Figure 1)
                    result = obj.processSingleFile(fileInfo, protocolOutputDir);
                    result.status = 'success';
                    groupResults{i} = result;
                    
                    obj.logger.logInfo(sprintf('  ✓ %s processed successfully', fileInfo.name));
                    
                catch ME
                    obj.logger.logError(sprintf('  ✗ Failed to process %s: %s', ...
                        fileInfo.name, ME.message));
                    groupResults{i} = struct('status', 'failed', 'error', ME.message, ...
                        'fileName', fileInfo.name);
                end
            end
            
            % Step 2: Export individual Excel workbooks
            obj.logger.logInfo('Step 2: Exporting individual workbooks...');
            obj.exportIndividualWorkbooks(groupResults, protocolOutputDir);
            
            % Step 3: Generate aggregated outputs
            obj.logger.logInfo('Step 3: Generating aggregated outputs...');
            obj.generateAggregatedOutputs(groupResults, protocolOutputDir);
            
            obj.logger.logInfo(sprintf('✓ Protocol group processing complete: %s', protocolOutputDir));
        end
        
        function exportIndividualWorkbooks(obj, groupResults, protocolOutputDir)
            %EXPORTINDIVIDUALWORKBOOKS Export Excel for each file
            
            exporter = NanionXLSXExporter(obj.config, obj.logger);
            
            for i = 1:length(groupResults)
                result = groupResults{i};
                
                if strcmp(result.status, 'success')
                    exporter.exportSummaryTable(result.summaryTable, result.filteredData, ...
                        result.fittedData, protocolOutputDir, result.fileName);
                end
            end
        end
        
        function generateAggregatedOutputs(obj, groupResults, protocolOutputDir)
            %GENERATEAGGREGATEDOUTPUTS Create aggregated Figure 2 + Excel
            
            % Filter successful results
            successfulResults = groupResults(cellfun(@(x) strcmp(x.status, 'success'), groupResults));
            
            if isempty(successfulResults)
                obj.logger.logWarning('No successful results for aggregation');
                return;
            end
            
            % Extract protocol type from first result
            protocolType = successfulResults{1}.protocol.type;
            
            obj.logger.logInfo(sprintf('Aggregating %d %s files...', ...
                length(successfulResults), protocolType));
            
            % Aggregate data structures
            aggregatedData = obj.aggregateResultData(successfulResults);
            
            % Generate aggregated Figure 2
            obj.logger.logInfo('Creating aggregated Figure 2...');
            figureGenerator = NanionSummaryFigure(obj.config, obj.logger);
            
            fig2_aggregated = figureGenerator.createAggregatedCellTypeAveragesFigure(...
                aggregatedData.filteredData, ...
                aggregatedData.fittedData, ...
                aggregatedData.summaryTable, ...
                protocolType, ...
                false);
            
            % Save aggregated Figure 2 page(s)
            timestamp = datestr(now, 'yyyymmdd_HHMMSS');
            multiPage = numel(fig2_aggregated) > 1;
            for p = 1:numel(fig2_aggregated)
                if ~isgraphics(fig2_aggregated(p))
                    continue;
                end
                if multiPage
                    figBaseName = sprintf('fig2_cell_type_averages_%s_AGGREGATED_p%d_%s', ...
                        protocolType, p, timestamp);
                else
                    figBaseName = sprintf('fig2_cell_type_averages_%s_AGGREGATED_%s', ...
                        protocolType, timestamp);
                end
                obj.saveFigure(fig2_aggregated(p), protocolOutputDir, figBaseName);
            end
            if ~isempty(fig2_aggregated)
                obj.logger.logInfo('✓ Aggregated Figure 2 saved');
            end
            
            % Export aggregated Excel workbook
            obj.logger.logInfo('Creating aggregated Excel workbook...');
            obj.exportAggregatedWorkbook(successfulResults, protocolOutputDir, protocolType);
        end
        
        function aggregatedData = aggregateResultData(obj, successfulResults)
            %AGGREGATERESULTDATA Combine data from multiple files
            
            % Concatenate summary tables
            summaryTables = cellfun(@(x) x.summaryTable, successfulResults, 'UniformOutput', false);
            aggregatedSummaryTable = vertcat(summaryTables{:});
            
            % Aggregate filteredData (combine measurements)
            firstFiltered = successfulResults{1}.filteredData;
            aggregatedFilteredData = firstFiltered;
            
            % Combine well IDs and metadata
            allWellIDs = [];
            allCellTypes = [];
            allCellConc = [];
            
            for i = 1:length(successfulResults)
                result = successfulResults{i};
                allWellIDs = [allWellIDs; result.filteredData.wellIDs];
                allCellTypes = [allCellTypes; result.filteredData.wellMetadata.cellType];
                allCellConc = [allCellConc; result.filteredData.wellMetadata.cellConcentration];
            end
            
            aggregatedFilteredData.wellIDs = allWellIDs;
            aggregatedFilteredData.wellMetadata.cellType = allCellTypes;
            aggregatedFilteredData.wellMetadata.cellConcentration = allCellConc;
            aggregatedFilteredData.numWellsPassed = length(allWellIDs);
            
            % Files in a group may have DIFFERENT IV counts (e.g. 2 vs 3 vs 8).
            % Aggregate only the IVs common to every file so the combined
            % per-IV data stays aligned with the combined well list.
            commonIVs = fieldnames(successfulResults{1}.filteredData.measurements);
            for i = 2:length(successfulResults)
                commonIVs = intersect(commonIVs, ...
                    fieldnames(successfulResults{i}.filteredData.measurements), 'stable');
            end
            if numel(commonIVs) < numel(fieldnames(firstFiltered.measurements))
                obj.logger.logWarning(sprintf(...
                    'Aggregating files with differing IV counts; using %d common IV(s): %s', ...
                    numel(commonIVs), strjoin(commonIVs, ', ')));
            end

            % Combine measurements for each common IV
            aggregatedFilteredData.measurements = struct();
            for ivIdx = 1:numel(commonIVs)
                ivName = commonIVs{ivIdx};
                ivFields = fieldnames(firstFiltered.measurements.(ivName));

                for fIdx = 1:numel(ivFields)
                    fieldName = ivFields{fIdx};
                    if strcmp(fieldName, 'statistics')
                        continue;  % recalculated downstream if needed
                    end

                    combinedData = [];
                    for i = 1:length(successfulResults)
                        ivData = successfulResults{i}.filteredData.measurements.(ivName);
                        if isfield(ivData, fieldName)
                            combinedData = [combinedData; ivData.(fieldName)]; %#ok<AGROW>
                        end
                    end
                    aggregatedFilteredData.measurements.(ivName).(fieldName) = combinedData;
                end
            end

            % Aggregate fittedData wells. Wells from files with different IV
            % counts have different fields (iv1..ivN), so reduce every file's
            % wells to their common fields before concatenating.
            commonWellFields = fieldnames(successfulResults{1}.fittedData.wells);
            for i = 2:length(successfulResults)
                commonWellFields = intersect(commonWellFields, ...
                    fieldnames(successfulResults{i}.fittedData.wells), 'stable');
            end

            allFittedWells = [];
            for i = 1:length(successfulResults)
                result = successfulResults{i};
                if isempty(result.fittedData) || ~isfield(result.fittedData, 'wells')
                    continue;
                end
                currentWells = result.fittedData.wells(:);  % force N×1
                extraFields = setdiff(fieldnames(currentWells), commonWellFields);
                if ~isempty(extraFields)
                    currentWells = rmfield(currentWells, extraFields);
                end
                currentWells = orderfields(currentWells, commonWellFields);
                allFittedWells = [allFittedWells; currentWells]; %#ok<AGROW>
            end

            aggregatedFittedData = successfulResults{1}.fittedData;
            aggregatedFittedData.wells = allFittedWells;
            aggregatedFittedData.ivNames = commonIVs;
            
            % Package aggregated data
            aggregatedData = struct(...
                'summaryTable', aggregatedSummaryTable, ...
                'filteredData', aggregatedFilteredData, ...
                'fittedData', aggregatedFittedData);
        end
        
        function exportAggregatedWorkbook(obj, successfulResults, protocolOutputDir, protocolType)
            %EXPORTAGGREGATEDWORKBOOK Create combined Excel workbook
            
            summaryTables = cellfun(@(x) x.summaryTable, successfulResults, 'UniformOutput', false);
            filteredDataArray = cellfun(@(x) x.filteredData, successfulResults, 'UniformOutput', false);
            fittedDataArray = cellfun(@(x) x.fittedData, successfulResults, 'UniformOutput', false);
            fileNames = cellfun(@(x) x.fileName, successfulResults, 'UniformOutput', false);
            
            % Combine all summary tables
            aggregatedTable = vertcat(summaryTables{:});
            
            % Create aggregated workbook filename
            timestamp = datestr(now, 'yyyymmdd_HHMMSS');
            aggFileName = sprintf('AGGREGATED_%s_COMPLETE_%s.xlsx', protocolType, timestamp);
            aggFile = fullfile(protocolOutputDir, aggFileName);
            
            if exist(aggFile, 'file')
                delete(aggFile);
            end
            
            % Export aggregated workbook
            exporter = NanionXLSXExporter(obj.config, obj.logger);
            
            % Summary statistics sheet
            exporter.createAggregatedSummaryStats(aggFile, summaryTables, fileNames);
            
            % All data sheet
            writetable(aggregatedTable, aggFile, 'Sheet', 'All_Data', 'WriteMode', 'append');
            exporter.formatSheet(aggFile, 'All_Data', aggregatedTable);
            
            % Per-IV sheets
            exporter.createPerIVSheets(aggFile, aggregatedTable);
            
            % Grouped sheets
            exporter.createGroupedSheets(aggFile, aggregatedTable);
            
            % Fit quality report
            exporter.createAggregatedFitQualitySheet(aggFile, aggregatedTable, fileNames);
            
            obj.logger.logInfo(sprintf('✓ Aggregated workbook saved: %s', aggFileName));
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
        
        function result = processSingleFile(obj, fileInfo, outputDir)
            %PROCESSSINGLEFILE Core processing (no Excel export here)
            
            obj.logger.logInfo(sprintf('Processing: %s', fileInfo.name));
            
            try
                % Step 1: Read and parse
                obj.logger.logInfo('Step 1: Reading and parsing data...');
                
                cachedRaw = obj.getCachedData(fileInfo.path, 'rawData');
                if isempty(cachedRaw)
                    rawData = obj.ioManager.readFile(fileInfo.path);
                    obj.setCachedData(fileInfo.path, 'rawData', rawData);
                else
                    rawData = cachedRaw;
                end
                
                parsedData = obj.ioManager.parseData(rawData, fileInfo.protocol);
                parsedData.fileName = fileInfo.name;
                
                % Step 2: Extract measurements
                obj.logger.logInfo('Step 2: Extracting measurements...');
                extractedData = obj.dataExtractor.extractMeasurements(parsedData);
                
                % Step 3: Assess quality (annotate EVERY well; discard nothing)
                obj.logger.logInfo('Step 3: Assessing well quality...');
                assessedData = obj.dataExtractor.assessQuality(extractedData);

                % Step 4: Fit Boltzmann curves for ALL wells BEFORE any decision,
                % so rejected wells still have a fit to display during review.
                obj.logger.logInfo('Step 4: Fitting Boltzmann curves (all wells)...');
                allData = obj.dataExtractor.applyDecisions(assessedData, ...
                    true(extractedData.numWells, 1));
                fitter = NanionBoltzmannFitter(obj.config, obj.logger);
                fittedAll = fitter.fitBoltzmann(allData);

                % Step 5: Review — user may override auto verdicts. In blocking
                % mode the pipeline pauses here and launches the review app; when
                % review is disabled this returns the automatic keep mask.
                obj.logger.logInfo('Step 5: QC review / decision...');
                keepMask = obj.runReview(assessedData, fittedAll);

                % Step 6: Apply final decisions -> kept wells only, then compute
                % sweep statistics and align the fits to the surviving wells.
                filteredData = obj.dataExtractor.applyDecisions(assessedData, keepMask);
                filteredData = obj.dataExtractor.calculateSweepStatistics(filteredData);
                fittedData = fitter.subsetFitted(fittedAll, keepMask);

                obj.logger.logInfo(sprintf('Quality decisions: %d/%d wells kept (%.1f%%)', ...
                    filteredData.numWellsPassed, filteredData.numWellsTotal, ...
                    100 * filteredData.numWellsPassed / max(filteredData.numWellsTotal, 1)));
                obj.logger.logInfo(sprintf('Boltzmann fitting: %d Good, %d Acceptable, %d Poor, %d Failed', ...
                    fittedData.summary.fitResults.good, ...
                    fittedData.summary.fitResults.acceptable, ...
                    fittedData.summary.fitResults.poor, ...
                    fittedData.summary.fitResults.failed));
                
                % Step 6: Build summary table
                obj.logger.logInfo('Step 6: Building summary table...');
                tableBuilder = NanionSummaryTableBuilder(obj.config, obj.logger);
                summaryTable = tableBuilder.buildSummaryTable(filteredData, fittedData, fileInfo.name);
                
                % Step 7: Generate figures (Figure 1 only, Figure 2 generated later for aggregation)
                obj.logger.logInfo('Step 7: Generating Figure 1...');
                figureGenerator = NanionSummaryFigure(obj.config, obj.logger);
                
                fig1 = figureGenerator.createRepresentativeWellsFigure(...
                    filteredData, fittedData, summaryTable);
                
                % Save Figure 1
                if ~isempty(fig1)
                    timestamp = datestr(now, 'yyyymmdd_HHMMSS');
                    figBaseName = sprintf('fig1_representative_wells_%s_%s', fileInfo.name, timestamp);
                    obj.saveFigure(fig1, outputDir, figBaseName);
                end
                
                figures = struct('fig1', fig1, 'fig2', []);
                obj.logger.logInfo('✓ Figure 1 generated');
                
                % Create result structure
                result = struct(...
                    'fileName', fileInfo.name, ...
                    'protocol', fileInfo.protocol, ...
                    'extractedData', extractedData, ...
                    'filteredData', filteredData, ...
                    'fittedData', fittedData, ...
                    'summaryTable', summaryTable, ...
                    'figures', figures, ...
                    'processingSteps', {{'dataReading', 'measurementExtraction', ...
                                        'qualityFiltering', 'statisticsCalculation', ...
                                        'boltzmannFitting', 'summaryTableBuilding', 'figureGeneration'}}, ...
                    'outputDir', outputDir);
                                
                obj.logger.logInfo(sprintf('✓ Processing complete: %s', fileInfo.name));
                
            catch ME
                obj.logger.logError(sprintf('Processing failed for %s: %s', fileInfo.name, ME.message));
                rethrow(ME);
            end
        end
        
       function saveFigure(obj, figHandle, outputPath, baseName)
            %SAVEFIGURE Save figure as PNG only
            
            if isempty(figHandle)
                return;
            end
            
            if ~exist(outputPath, 'dir')
                mkdir(outputPath);
            end
            
            pngFile = fullfile(outputPath, [baseName, '.png']);
            saveas(figHandle, pngFile);
            obj.logger.logInfo(sprintf('✓ Saved PNG: %s', baseName));
        end
        
        function openOutputFolder(obj, folderPath)
            %OPENOUTPUTFOLDER Auto-open folder in file explorer
            
            try
                if ispc
                    winopen(folderPath);
                elseif ismac
                    system(['open "' folderPath '"']);
                else
                    system(['xdg-open "' folderPath '"']);
                end
            catch
                obj.logger.logDebug('Could not auto-open output folder');
            end
        end
    end
    
    methods (Access = private)
        function fileName = extractFileName(~, filePath)
            [~, fileName, ~] = fileparts(filePath);
        end

        function initReviewSession(obj, outputDir)
            %INITREVIEWSESSION Create + preload the QC review session (if enabled).
            if ~obj.config.qc.enableReview
                obj.reviewSession = [];
                return;
            end
            obj.reviewStoreDir = outputDir;
            obj.reviewSession = QCReviewSession(obj.config, obj.logger);
            obj.reviewSession.load(obj.reviewStoreDir);
        end

        function keepMask = runReview(obj, assessedData, fittedAll)
            %RUNREVIEW Resolve the final keep mask for one file's assessed wells.
            %   Branches on config.qc: review disabled -> automatic verdicts;
            %   'blocking' -> launch the review app and wait; 'standalone' ->
            %   persist a review bundle for later and proceed with current
            %   decisions (auto, or any overrides reloaded from disk).

            if ~obj.config.qc.enableReview || isempty(obj.reviewSession)
                keepMask = assessedData.autoKeepMask;
                return;
            end

            session = obj.reviewSession;
            session.ingestAssessment(assessedData);

            switch lower(obj.config.qc.reviewMode)
                case 'blocking'
                    obj.logger.logInfo('QC review (blocking): launching review app...');
                    app = NanionQCReviewApp(obj.config, obj.logger, session, ...
                        assessedData, fittedAll);
                    app.waitForCompletion();
                    keepMask = session.keepMaskFor(assessedData);

                case 'standalone'
                    obj.saveReviewBundle(assessedData, fittedAll);
                    keepMask = session.keepMaskFor(assessedData);
                    obj.logger.logInfo(['QC review (standalone): saved bundle; ' ...
                        'run run_qc_review to review, then re-run to apply.']);

                otherwise
                    obj.logger.logWarning(sprintf(...
                        'Unknown qc.reviewMode "%s"; using automatic verdicts', ...
                        obj.config.qc.reviewMode));
                    keepMask = assessedData.autoKeepMask;
            end

            session.save(obj.reviewStoreDir);
        end

        function saveReviewBundle(obj, assessedData, fittedAll)
            %SAVEREVIEWBUNDLE Persist assessed+fitted data for standalone review.
            %   One bundle per file (keyed by fileName) so run_qc_review can
            %   reload the exact plots the user needs to see.
            bundleDir = fullfile(obj.reviewStoreDir, 'qc_review_bundles');
            if ~exist(bundleDir, 'dir'); mkdir(bundleDir); end
            bundle = struct('assessedData', assessedData, ...
                'fittedData', fittedAll, ...
                'fileName', char(assessedData.fileName)); %#ok<NASGU>
            safeName = matlab.lang.makeValidName(char(assessedData.fileName));
            bundleFile = fullfile(bundleDir, [safeName '_qc_bundle.mat']);
            save(bundleFile, 'bundle', '-v7.3');
            obj.logger.logInfo(sprintf('QCReviewSession: saved review bundle -> %s', bundleFile));
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
                'NanionSummaryFigure', 'plotting', ...
                'NanionSummaryTableBuilder', 'analysis', ...
                'NanionXLSXExporter', 'io');
            
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
            
            requiredDirs = {'config', 'utils', 'io', 'analysis', 'fitting', 'plotting', 'qc', 'pipeline', 'detection'};
            
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
