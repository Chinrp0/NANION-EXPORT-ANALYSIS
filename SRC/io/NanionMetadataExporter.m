classdef NanionMetadataExporter < handle
    %NANIONMETADATAEXPORTER Export summary tables to timestamped folders
    %   Creates YYYYMMDD_HHMMSS folders to avoid overwriting
    %   Supports both single-file and multi-file aggregation
    
    properties (Access = private)
        config
        logger
    end
    
    methods
        function obj = NanionMetadataExporter(config, logger)
            obj.config = config;
            obj.logger = logger;
        end
        
        function outputPath = exportSummaryTable(obj, summaryTable, baseOutputDir, fileName)
            %EXPORTSUMMARYTABLE Export single summary table to timestamped folder
            %   Inputs:
            %     summaryTable - MATLAB table from NanionSummaryTableBuilder
            %     baseOutputDir - Base directory for output
            %     fileName - Original file name (for naming output files)
            %   Output:
            %     outputPath - Full path to created output folder
            
            % Create timestamped output folder
            outputPath = obj.createTimestampedFolder(baseOutputDir);
            
            obj.logger.logInfo(sprintf('Exporting summary table to: %s', outputPath));
            
            % Generate file names
            [~, baseFileName, ~] = fileparts(fileName);
            excelFile = fullfile(outputPath, sprintf('%s_summary.xlsx', baseFileName));
            csvFile = fullfile(outputPath, sprintf('%s_summary.csv', baseFileName));
            
            % Export to Excel
            try
                writetable(summaryTable, excelFile, 'WriteMode', 'overwritesheet');
                obj.logger.logInfo(sprintf('✓ Excel export: %s', excelFile));
            catch ME
                obj.logger.logWarning(sprintf('Excel export failed: %s', ME.message));
            end
            
            % Export to CSV (more robust)
            try
                writetable(summaryTable, csvFile, 'WriteMode', 'overwrite');
                obj.logger.logInfo(sprintf('✓ CSV export: %s', csvFile));
            catch ME
                obj.logger.logError(sprintf('CSV export failed: %s', ME.message));
            end
            
            % Generate summary statistics file
            obj.exportTableSummary(summaryTable, outputPath, baseFileName);
            
            obj.logger.logInfo(sprintf('✓ Export complete: %d rows exported', height(summaryTable)));
        end
        
        function outputPath = exportMultipleFiles(obj, summaryTables, baseOutputDir, fileNames)
            %EXPORTMULTIPLEFILES Export and aggregate multiple summary tables
            %   Inputs:
            %     summaryTables - Cell array of MATLAB tables
            %     baseOutputDir - Base directory for output
            %     fileNames - Cell array of original file names
            %   Output:
            %     outputPath - Full path to created output folder
            
            % Create timestamped output folder
            outputPath = obj.createTimestampedFolder(baseOutputDir);
            
            obj.logger.logInfo(sprintf('Exporting %d summary tables to: %s', ...
                length(summaryTables), outputPath));
            
            % Export individual files
            for i = 1:length(summaryTables)
                [~, baseFileName, ~] = fileparts(fileNames{i});
                excelFile = fullfile(outputPath, sprintf('%s_summary.xlsx', baseFileName));
                csvFile = fullfile(outputPath, sprintf('%s_summary.csv', baseFileName));
                
                try
                    writetable(summaryTables{i}, excelFile, 'WriteMode', 'overwritesheet');
                    writetable(summaryTables{i}, csvFile, 'WriteMode', 'overwrite');
                    obj.logger.logInfo(sprintf('✓ Exported: %s', baseFileName));
                catch ME
                    obj.logger.logWarning(sprintf('Export failed for %s: %s', baseFileName, ME.message));
                end
            end
            
            % Create aggregated table
            obj.logger.logInfo('Creating aggregated summary table...');
            aggregatedTable = obj.aggregateTables(summaryTables);
            
            aggExcelFile = fullfile(outputPath, 'AGGREGATED_summary.xlsx');
            aggCSVFile = fullfile(outputPath, 'AGGREGATED_summary.csv');
            
            try
                writetable(aggregatedTable, aggExcelFile, 'WriteMode', 'overwritesheet');
                writetable(aggregatedTable, aggCSVFile, 'WriteMode', 'overwrite');
                obj.logger.logInfo(sprintf('✓ Aggregated table: %d total rows', height(aggregatedTable)));
            catch ME
                obj.logger.logError(sprintf('Aggregated export failed: %s', ME.message));
            end
            
            % Generate batch summary
            obj.exportBatchSummary(summaryTables, fileNames, outputPath);
            
            obj.logger.logInfo('✓ Multi-file export complete');
        end
        
        function groupedTables = exportGroupedSummaries(obj, summaryTable, outputPath)
            %EXPORTGROUPEDSUMMARIES Export tables grouped by Cell_Type + Compound + Concentration
            %   As requested: group by Cell_Type + Compound + Concentration for cross-file comparison
            
            obj.logger.logInfo('Creating grouped summaries (Cell_Type + Compound + Concentration)...');
            
            % Get unique groups
            groups = summaryTable(:, {'Cell_Type', 'Compound', 'Concentration_uM'});
            [uniqueGroups, ~, groupIdx] = unique(groups, 'rows');
            
            obj.logger.logInfo(sprintf('Found %d unique groups', height(uniqueGroups)));
            
            groupedTables = cell(height(uniqueGroups), 1);
            
            for i = 1:height(uniqueGroups)
                groupMask = (groupIdx == i);
                groupTable = summaryTable(groupMask, :);
                
                % Create group name
                cellType = char(uniqueGroups.Cell_Type(i));
                compound = char(uniqueGroups.Compound(i));
                conc = uniqueGroups.Concentration_uM(i);
                
                % Sanitize for filename (remove spaces, special chars)
                groupName = sprintf('%s_%s_%.2fuM', ...
                    strrep(cellType, ' ', '_'), ...
                    strrep(compound, ' ', '_'), ...
                    conc);
                groupName = regexprep(groupName, '[^a-zA-Z0-9_.]', '');
                
                % Export group
                groupFile = fullfile(outputPath, sprintf('GROUP_%s.xlsx', groupName));
                
                try
                    writetable(groupTable, groupFile, 'WriteMode', 'overwritesheet');
                    obj.logger.logInfo(sprintf('✓ Group: %s (%d rows)', groupName, height(groupTable)));
                catch ME
                    obj.logger.logWarning(sprintf('Group export failed: %s', ME.message));
                end
                
                groupedTables{i} = groupTable;
            end
            
            obj.logger.logInfo('✓ Grouped summaries exported');
        end
    end
    
    methods (Access = private)
        function outputPath = createTimestampedFolder(obj, baseDir)
            %CREATETIMESTAMPEDFOLDER Create YYYYMMDD_HHMMSS output folder
            
            % Generate timestamp
            timestamp = datestr(now, 'yyyymmdd_HHMMSS');
            outputPath = fullfile(baseDir, timestamp);
            
            % Create directory
            if ~exist(outputPath, 'dir')
                mkdir(outputPath);
                obj.logger.logInfo(sprintf('Created output folder: %s', outputPath));
            end
        end
        
        function exportTableSummary(obj, summaryTable, outputPath, baseFileName)
            %EXPORTTABLESUMMARY Generate and export summary statistics
            
            summaryFile = fullfile(outputPath, sprintf('%s_statistics.txt', baseFileName));
            
            fid = fopen(summaryFile, 'w');
            if fid < 0
                obj.logger.logWarning('Could not create summary statistics file');
                return;
            end
            
            fprintf(fid, '=== SUMMARY TABLE STATISTICS ===\n');
            fprintf(fid, 'Generated: %s\n\n', datestr(now));
            
            fprintf(fid, 'Total Rows: %d\n', height(summaryTable));
            fprintf(fid, 'Total Columns: %d\n\n', width(summaryTable));
            
            % Count by protocol - ROBUST: Handle nested cells
            if ismember('Protocol_Type', summaryTable.Properties.VariableNames)
                protocolData = obj.robustCellToString(summaryTable.Protocol_Type);
                protocols = unique(protocolData, 'stable');
                
                for i = 1:length(protocols)
                    count = sum(strcmp(protocolData, protocols(i)));
                    fprintf(fid, 'Protocol %s: %d rows\n', char(protocols(i)), count);
                end
                fprintf(fid, '\n');
            end
            
            % Count by Cell Type - ROBUST: Handle nested cells
            if ismember('Cell_Type', summaryTable.Properties.VariableNames)
                cellTypeData = obj.robustCellToString(summaryTable.Cell_Type);
                cellTypes = unique(cellTypeData, 'stable');
                
                fprintf(fid, '--- Cell Types ---\n');
                for i = 1:length(cellTypes)
                    count = sum(strcmp(cellTypeData, cellTypes(i)));
                    fprintf(fid, '%s: %d rows\n', char(cellTypes(i)), count);
                end
                fprintf(fid, '\n');
            end
            
            % Fit quality distribution - ROBUST: Handle nested cells
            if ismember('Fit_Quality', summaryTable.Properties.VariableNames)
                fprintf(fid, '--- Fit Quality Distribution ---\n');
                qualities = {'Good', 'Acceptable', 'Poor', 'Failed'};
                
                qualityData = obj.robustCellToString(summaryTable.Fit_Quality);
                
                for i = 1:length(qualities)
                    count = sum(strcmp(qualityData, qualities{i}));
                    fprintf(fid, '%s: %d (%.1f%%)\n', qualities{i}, count, ...
                        100 * count / height(summaryTable));
                end
            end
            
            fclose(fid);
            obj.logger.logInfo(sprintf('✓ Statistics saved: %s', summaryFile));
        end
        
        function strArray = robustCellToString(obj, data)
            %ROBUSTCELLTOSTRING Safely convert any cell/table column to string array
            %   Handles nested cells, categorical, string, and char arrays
            
            % If already string, return as-is
            if isstring(data)
                strArray = data;
                return;
            end
            
            % If categorical, convert to string
            if iscategorical(data)
                strArray = string(data);
                return;
            end
            
            % If cell array, convert element-by-element
            if iscell(data)
                numElements = numel(data);
                strArray = strings(size(data));
                
                for i = 1:numElements
                    element = data{i};
                    
                    if ischar(element)
                        strArray(i) = string(element);
                    elseif isstring(element)
                        strArray(i) = element;
                    elseif isnumeric(element)
                        strArray(i) = string(num2str(element));
                    elseif iscell(element)
                        % Nested cell - try to extract first element
                        if ~isempty(element)
                            strArray(i) = string(element{1});
                        else
                            strArray(i) = "";
                        end
                    else
                        strArray(i) = "";
                    end
                end
                return;
            end
            
            % If numeric or other, convert to string
            if isnumeric(data)
                strArray = string(arrayfun(@num2str, data, 'UniformOutput', false));
            else
                % Last resort - try direct conversion
                try
                    strArray = string(data);
                catch
                    strArray = repmat("", size(data));
                end
            end
        end
        
        function aggregatedTable = aggregateTables(obj, summaryTables)
            %AGGREGATETABLES Combine multiple summary tables vertically
            
            % Ensure all tables have the same structure
            % If not, align column names
            
            if isempty(summaryTables)
                aggregatedTable = table();
                return;
            end
            
            % Use first table as reference
            refTable = summaryTables{1};
            
            % Check if all tables have same columns
            allSameStructure = true;
            for i = 2:length(summaryTables)
                if ~isequal(refTable.Properties.VariableNames, summaryTables{i}.Properties.VariableNames)
                    allSameStructure = false;
                    break;
                end
            end
            
            if allSameStructure
                % Simple vertical concatenation
                aggregatedTable = vertcat(summaryTables{:});
            else
                % Need to align columns
                obj.logger.logWarning('Tables have different structures - aligning columns...');
                aggregatedTable = obj.alignAndMergeTables(summaryTables);
            end
        end
        
        function mergedTable = alignAndMergeTables(obj, summaryTables)
            %ALIGNANDMERGETABLES Align columns and merge tables with different structures
            
            % Get union of all column names
            allColumns = {};
            for i = 1:length(summaryTables)
                allColumns = union(allColumns, summaryTables{i}.Properties.VariableNames);
            end
            
            % Add missing columns to each table
            alignedTables = cell(size(summaryTables));
            
            for i = 1:length(summaryTables)
                tbl = summaryTables{i};
                missingCols = setdiff(allColumns, tbl.Properties.VariableNames);
                
                for j = 1:length(missingCols)
                    % Add missing column with appropriate default value
                    colName = missingCols{j};
                    tbl.(colName) = repmat({''}, height(tbl), 1);  % Default to empty string
                end
                
                % Reorder columns to match
                alignedTables{i} = tbl(:, allColumns);
            end
            
            % Now vertically concatenate
            mergedTable = vertcat(alignedTables{:});
        end
        
        function exportBatchSummary(obj, summaryTables, fileNames, outputPath)
            %EXPORTBATCHSUMMARY Generate summary for batch processing
            
            summaryFile = fullfile(outputPath, 'BATCH_SUMMARY.txt');
            
            fid = fopen(summaryFile, 'w');
            if fid < 0
                return;
            end
            
            fprintf(fid, '=== BATCH PROCESSING SUMMARY ===\n');
            fprintf(fid, 'Generated: %s\n\n', datestr(now));
            
            fprintf(fid, 'Total Files Processed: %d\n\n', length(summaryTables));
            
            fprintf(fid, '--- Individual File Statistics ---\n');
            for i = 1:length(summaryTables)
                [~, baseName, ~] = fileparts(fileNames{i});
                fprintf(fid, '\n%s:\n', baseName);
                fprintf(fid, '  Rows: %d\n', height(summaryTables{i}));
                
                if ismember('Fit_Quality', summaryTables{i}.Properties.VariableNames)
                    good = sum(strcmp(summaryTables{i}.Fit_Quality, 'Good'));
                    fprintf(fid, '  Good Fits: %d (%.1f%%)\n', good, ...
                        100 * good / height(summaryTables{i}));
                end
            end
            
            fclose(fid);
        end
    end
end
