classdef NanionXLSXExporter < handle
    %NANIONXLSXEXPORTER Comprehensive XLSX export with formatting and organization
    %   Combines multi-sheet workbooks, enhanced formatting, and hierarchical structure
    %   No CSV or TXT files - everything in formatted Excel workbooks
    
    properties (Access = private)
        config
        logger
    end
    
    methods
        function obj = NanionXLSXExporter(config, logger)
            obj.config = config;
            obj.logger = logger;
        end
        
        function outputPath = exportSummaryTable(obj, summaryTable, filteredData, fittedData, baseOutputDir, fileName, useSubfolder)
            %EXPORTSUMMARYTABLE Export single file to comprehensive multi-sheet workbook
            %   Creates organized workbook with:
            %     - Summary Statistics sheet
            %     - All Data sheet
            %     - Per-IV sheets
            %     - Grouped sheets
            %     - Fit Quality Report sheet
            %
            %   useSubfolder (default true): when true, writes into a fresh
            %   timestamped subfolder of baseOutputDir. Pass false to write
            %   directly into baseOutputDir (e.g. a shared Individual_Master_Files
            %   folder) so per-file workbooks are not each isolated in their own
            %   single-file folder.

            if nargin < 7
                useSubfolder = true;
            end

            if useSubfolder
                outputPath = obj.createTimestampedFolder(baseOutputDir);
            else
                outputPath = baseOutputDir;
                if ~exist(outputPath, 'dir')
                    mkdir(outputPath);
                end
            end
            obj.logger.logInfo(sprintf('Exporting comprehensive workbook to: %s', outputPath));
            
            [~, baseFileName, ~] = fileparts(fileName);
            excelFile = fullfile(outputPath, sprintf('%s_COMPLETE.xlsx', baseFileName));
            
            % Delete existing file if present
            if exist(excelFile, 'file')
                delete(excelFile);
            end
            
            try
                % Sheet 1: Summary Statistics
                obj.logger.logInfo('Creating Summary Statistics sheet...');
                obj.createSummaryStatsSheet(excelFile, summaryTable, filteredData, fittedData, fileName);
                
                % Sheet 2: All Data (full summary table)
                obj.logger.logInfo('Creating All Data sheet...');
                writetable(summaryTable, excelFile, 'Sheet', 'All_Data', 'WriteMode', 'append');
                obj.formatSheet(excelFile, 'All_Data', summaryTable);
                
                % Sheets 3-N: Per-IV sheets
                obj.logger.logInfo('Creating per-IV sheets...');
                obj.createPerIVSheets(excelFile, summaryTable);
                
                % Sheets N+1: Grouped sheets (by Cell_Type + Compound + Concentration)
                %obj.logger.logInfo('Creating grouped sheets...');
                %obj.createGroupedSheets(excelFile, summaryTable);
                
                % Final Sheet: Fit Quality Report
                obj.logger.logInfo('Creating Fit Quality Report sheet...');
                obj.createFitQualitySheet(excelFile, summaryTable, fittedData);
                
                obj.logger.logInfo(sprintf('✓ Complete workbook exported: %s', excelFile));
                obj.logger.logInfo(sprintf('  %d total rows across multiple organized sheets', height(summaryTable)));
                
            catch ME
                obj.logger.logError(sprintf('XLSX export failed: %s', ME.message));
                obj.logger.logError(sprintf('Stack: %s', getReport(ME)));
                rethrow(ME);
            end
        end
        
        function outputPath = exportMultipleFiles(obj, summaryTables, filteredDataArray, fittedDataArray, baseOutputDir, fileNames)
            %EXPORTMULTIPLEFILES Export multiple files + aggregated workbook
            
            outputPath = obj.createTimestampedFolder(baseOutputDir);
            obj.logger.logInfo(sprintf('Exporting %d comprehensive workbooks...', length(summaryTables)));
            
            % Export individual workbooks
            for i = 1:length(summaryTables)
                obj.logger.logInfo(sprintf('Exporting file %d/%d: %s', i, length(summaryTables), fileNames{i}));
                obj.exportSummaryTable(summaryTables{i}, filteredDataArray{i}, fittedDataArray{i}, outputPath, fileNames{i});
            end
            
            % Create aggregated workbook
            obj.logger.logInfo('Creating AGGREGATED workbook...');
            aggregatedTable = vertcat(summaryTables{:});
            aggFile = fullfile(outputPath, 'AGGREGATED_COMPLETE.xlsx');
            
            if exist(aggFile, 'file')
                delete(aggFile);
            end
            
            % Aggregated workbook structure
            obj.createAggregatedSummaryStats(aggFile, summaryTables, fileNames);
            writetable(aggregatedTable, aggFile, 'Sheet', 'All_Data', 'WriteMode', 'append');
            obj.formatSheet(aggFile, 'All_Data', aggregatedTable);
            
            obj.createPerIVSheets(aggFile, aggregatedTable);
            %obj.createGroupedSheets(aggFile, aggregatedTable);
            obj.createAggregatedFitQualitySheet(aggFile, aggregatedTable, fileNames);
            
            obj.logger.logInfo('✓ All workbooks exported successfully');
        end
    end

    methods (Access = public)
            function formatSheet(obj, excelFile, sheetName, dataTable)
            %FORMATSHEET Apply formatting: frozen header, auto-size, conditional formatting
            
            try
                % Use Excel COM automation for advanced formatting
                if ispc  % Windows only
                    obj.formatSheetWindows(excelFile, sheetName, dataTable);
                else
                    obj.logger.logDebug('Advanced formatting only available on Windows');
                end
            catch ME
                obj.logger.logDebug(sprintf('Formatting warning: %s', ME.message));
            end
        end
        
        function createPerIVSheets(obj, excelFile, summaryTable)
            %CREATEPERIVSHEETS Create one sheet per IV
            
            ivNumbers = unique(summaryTable.IV_Number);
            
            for i = 1:length(ivNumbers)
                ivNum = ivNumbers(i);
                sheetName = sprintf('IV%d', ivNum);
                
                ivTable = summaryTable(summaryTable.IV_Number == ivNum, :);
                
                writetable(ivTable, excelFile, 'Sheet', sheetName, 'WriteMode', 'append');
                obj.formatSheet(excelFile, sheetName, ivTable);
                
                obj.logger.logDebug(sprintf('  Created sheet: %s (%d rows)', sheetName, height(ivTable)));
            end
        end
        
        function createGroupedSheets(obj, excelFile, summaryTable)
            %CREATEGROUPEDSHEETS Create sheets grouped by Cell_Type + Compound + Concentration
            
            if ~all(ismember({'Cell_Type', 'Compound', 'Concentration_uM'}, summaryTable.Properties.VariableNames))
                obj.logger.logWarning('Missing grouping columns - skipping grouped sheets');
                return;
            end
            
            % Get unique groups
            groups = summaryTable(:, {'Cell_Type', 'Compound', 'Concentration_uM'});
            [uniqueGroups, ~, groupIdx] = unique(groups, 'rows');
            
            obj.logger.logDebug(sprintf('Creating %d grouped sheets...', height(uniqueGroups)));
            
            for i = 1:height(uniqueGroups)
                groupMask = (groupIdx == i);
                groupTable = summaryTable(groupMask, :);
                
                % Create sanitized sheet name
                cellType = char(uniqueGroups.Cell_Type(i));
                compound = char(uniqueGroups.Compound(i));
                conc = uniqueGroups.Concentration_uM(i);
                
                sheetName = obj.createGroupSheetName(cellType, compound, conc);
                
                try
                    writetable(groupTable, excelFile, 'Sheet', sheetName, 'WriteMode', 'append');
                    obj.formatSheet(excelFile, sheetName, groupTable);
                    obj.logger.logDebug(sprintf('  Created group: %s (%d rows)', sheetName, height(groupTable)));
                catch ME
                    obj.logger.logWarning(sprintf('Failed to create group sheet: %s', ME.message));
                end
            end
        end
        
        function createAggregatedSummaryStats(obj, excelFile, summaryTables, fileNames)
            %CREATEAGGREGATEDSUMMARYSTATS Create summary for multiple files
            
            metrics = {};
            values = {};
            
            metrics{end+1} = 'Aggregated Analysis'; values{end+1} = '';
            metrics{end+1} = 'Export Date'; values{end+1} = datestr(now);
            metrics{end+1} = ''; values{end+1} = '';
            
            metrics{end+1} = 'Total Files'; values{end+1} = sprintf('%d', length(summaryTables));
            totalRows = sum(cellfun(@height, summaryTables));
            metrics{end+1} = 'Total Rows'; values{end+1} = sprintf('%d', totalRows);
            metrics{end+1} = ''; values{end+1} = '';
            
            metrics{end+1} = 'Individual Files'; values{end+1} = '';
            for i = 1:length(fileNames)
                [~, baseName, ~] = fileparts(fileNames{i});
                metrics{end+1} = sprintf('  %s', baseName);
                values{end+1} = sprintf('%d rows', height(summaryTables{i}));
            end
            
            statsTable = table(metrics', values', 'VariableNames', {'Metric', 'Value'});
            writetable(statsTable, excelFile, 'Sheet', 'Summary_Statistics', 'WriteMode', 'overwritesheet');
            obj.formatSheet(excelFile, 'Summary_Statistics', statsTable);
        end
        
        function createAggregatedFitQualitySheet(obj, excelFile, aggregatedTable, fileNames)
            %CREATEAGGREGATEDFITQUALITYSHEET Fit quality for aggregated data
            
            obj.createFitQualitySheet(excelFile, aggregatedTable, []);
        end
    end
    
    methods (Access = private)
        function createSummaryStatsSheet(obj, excelFile, summaryTable, filteredData, fittedData, fileName)
            %CREATESUMMARYSTATSSHEET Create formatted summary statistics sheet
            
            % Build statistics as a table for better formatting
            stats = obj.buildStatisticsTable(summaryTable, filteredData, fittedData, fileName);
            
            writetable(stats, excelFile, 'Sheet', 'Summary_Statistics', 'WriteMode', 'overwritesheet', ...
                'WriteRowNames', false);
            
            % Apply basic formatting
            obj.formatSheet(excelFile, 'Summary_Statistics', stats);
        end
        
        function statsTable = buildStatisticsTable(obj, summaryTable, filteredData, fittedData, fileName)
            %BUILDSTATISTICSTABLE Convert statistics to table format
            
            % Create two-column table: Metric | Value
            metrics = {};
            values = {};
            
            % File info
            metrics{end+1} = 'File Name'; values{end+1} = fileName;
            metrics{end+1} = 'Export Date'; values{end+1} = datestr(now);
            metrics{end+1} = ''; values{end+1} = '';  % Blank row
            
            % Data dimensions
            metrics{end+1} = 'Total Rows'; values{end+1} = sprintf('%d', height(summaryTable));
            metrics{end+1} = 'Total Columns'; values{end+1} = sprintf('%d', width(summaryTable));
            metrics{end+1} = 'Unique Wells'; values{end+1} = sprintf('%d', length(unique(summaryTable.Well_ID)));
            metrics{end+1} = 'Number of IVs'; values{end+1} = sprintf('%d', length(unique(summaryTable.IV_Number)));
            metrics{end+1} = ''; values{end+1} = '';
            
            % Protocol info
            if ~isempty(summaryTable.Protocol_Type)
                protocolType = char(summaryTable.Protocol_Type{1});
                metrics{end+1} = 'Protocol Type'; values{end+1} = protocolType;
            end
            metrics{end+1} = 'Voltage Steps'; values{end+1} = sprintf('%d', summaryTable.Num_Voltage_Steps(1));
            metrics{end+1} = 'Temperature (°C)'; values{end+1} = sprintf('%.1f', summaryTable.Temperature_C(1));
            metrics{end+1} = 'Nernst Potential (mV)'; values{end+1} = sprintf('%.1f', summaryTable.Nernst_Potential_mV(1));
            metrics{end+1} = ''; values{end+1} = '';
            
            % Filtering statistics
            metrics{end+1} = 'Wells Passed QC'; values{end+1} = sprintf('%d', filteredData.numWellsPassed);
            metrics{end+1} = 'Wells Total'; values{end+1} = sprintf('%d', filteredData.numWellsTotal);
            metrics{end+1} = 'Pass Rate'; values{end+1} = sprintf('%.1f%%', 100 * filteredData.numWellsPassed / filteredData.numWellsTotal);
            metrics{end+1} = ''; values{end+1} = '';
            
            % Cell type breakdown
            if ismember('Cell_Type', summaryTable.Properties.VariableNames)
                cellTypes = unique(obj.robustCellToString(summaryTable.Cell_Type), 'stable');
                metrics{end+1} = 'Cell Types'; values{end+1} = '';
                for i = 1:length(cellTypes)
                    cellTypeStr = char(cellTypes(i));
                    count = sum(strcmp(obj.robustCellToString(summaryTable.Cell_Type), cellTypeStr));
                    metrics{end+1} = sprintf('  %s', cellTypeStr);
                    values{end+1} = sprintf('%d rows', count);
                end
                metrics{end+1} = ''; values{end+1} = '';
            end
            
            % Fit quality breakdown
            if ismember('Fit_Quality', summaryTable.Properties.VariableNames)
                metrics{end+1} = 'Fit Quality Distribution'; values{end+1} = '';
                qualities = {'Good', 'Acceptable', 'Poor', 'Failed'};
                qualityData = obj.robustCellToString(summaryTable.Fit_Quality);
                
                for i = 1:length(qualities)
                    count = sum(strcmp(qualityData, qualities{i}));
                    pct = 100 * count / height(summaryTable);
                    metrics{end+1} = sprintf('  %s', qualities{i});
                    values{end+1} = sprintf('%d (%.1f%%)', count, pct);
                end
                metrics{end+1} = ''; values{end+1} = '';
            end
            
            % Fit convergence
            if ismember('Fit_Converged', summaryTable.Properties.VariableNames)
                converged = sum(summaryTable.Fit_Converged == 'TRUE');
                metrics{end+1} = 'Fits Converged'; 
                values{end+1} = sprintf('%d (%.1f%%)', converged, 100 * converged / height(summaryTable));
            end
            
            % Create table
            statsTable = table(metrics', values', 'VariableNames', {'Metric', 'Value'});
        end
        
        
        
        function sheetName = createGroupSheetName(obj, cellType, compound, conc)
            %CREATEGROUPSHEETNAME Create valid Excel sheet name (max 31 chars)
            
            % Sanitize inputs
            cellType = strrep(cellType, ' ', '_');
            compound = strrep(compound, ' ', '_');
            
            % Build name
            baseName = sprintf('GRP_%s_%s_%.1fuM', cellType, compound, conc);
            
            % Remove invalid characters
            baseName = regexprep(baseName, '[^\w_.]', '');
            
            % Truncate to 31 characters (Excel limit)
            if length(baseName) > 31
                baseName = baseName(1:31);
            end
            
            sheetName = baseName;
        end
        
        function createFitQualitySheet(obj, excelFile, summaryTable, fittedData)
            %CREATEFITQUALITYSHEET Create detailed fit quality breakdown sheet
            
            % Build fit quality summary table
            qualities = {'Good', 'Acceptable', 'Poor', 'Failed'};
            qualityData = obj.robustCellToString(summaryTable.Fit_Quality);
            
            % Overall counts
            overallCounts = zeros(length(qualities), 1);
            overallPcts = zeros(length(qualities), 1);
            
            for i = 1:length(qualities)
                overallCounts(i) = sum(strcmp(qualityData, qualities{i}));
                overallPcts(i) = 100 * overallCounts(i) / height(summaryTable);
            end
            
            % Per-IV breakdown
            ivNumbers = unique(summaryTable.IV_Number);
            ivBreakdown = zeros(length(qualities), length(ivNumbers));
            
            for i = 1:length(ivNumbers)
                ivMask = summaryTable.IV_Number == ivNumbers(i);
                ivQuality = qualityData(ivMask);
                
                for j = 1:length(qualities)
                    ivBreakdown(j, i) = sum(strcmp(ivQuality, qualities{j}));
                end
            end
            
            % Create combined table
            ivColNames = arrayfun(@(x) sprintf('IV%d', x), ivNumbers, 'UniformOutput', false);
            fitQualityTable = table(qualities', overallCounts, overallPcts, ...
                'VariableNames', {'Fit_Quality', 'Total_Count', 'Percentage'});
            
            % Add IV columns
            for i = 1:length(ivNumbers)
                fitQualityTable.(ivColNames{i}) = ivBreakdown(:, i);
            end
            
            % Add R² statistics
            if ismember('R_squared', summaryTable.Properties.VariableNames)
                r2Metrics = {'Mean R²'; 'Median R²'; 'Min R²'; 'Max R²'; 'Std R²'};
                r2Values = [mean(summaryTable.R_squared, 'omitnan'); 
                            median(summaryTable.R_squared, 'omitnan');
                            min(summaryTable.R_squared, [], 'omitnan');
                            max(summaryTable.R_squared, [], 'omitnan');
                            std(summaryTable.R_squared, 'omitnan')];
                r2Stats = table(r2Metrics, r2Values, 'VariableNames', {'Metric', 'Value'});
            end
            
            % Convert fitQualityTable to all-cell format for easy combining
            numCols = width(fitQualityTable);
            numRows = height(fitQualityTable);
            
            fitQualityData = cell(numRows, numCols);
            for col = 1:numCols
                colData = fitQualityTable{:, col};
                if isnumeric(colData)
                    fitQualityData(:, col) = num2cell(colData);
                else
                    fitQualityData(:, col) = colData;
                end
            end
            
            fitQualityCellTable = cell2table(fitQualityData, ...
                'VariableNames', fitQualityTable.Properties.VariableNames);
            
            % Write fit quality table
            if exist('r2Stats', 'var')
                % Create blank rows
                blankData = cell(3, numCols);
                blankData(:) = {''};
                blankData{2, 1} = '--- R² Statistics ---';
                
                % Pad r2Stats to match column count
                r2PaddedData = cell(height(r2Stats), numCols);
                r2PaddedData(:) = {''};
                for i = 1:height(r2Stats)
                    r2PaddedData{i, 1} = r2Stats.Metric{i};
                    r2PaddedData{i, 2} = r2Stats.Value(i);
                end
                
                % Combine all
                combinedData = [fitQualityData; blankData; r2PaddedData];
                combinedTable = cell2table(combinedData, ...
                    'VariableNames', fitQualityTable.Properties.VariableNames);
                
                writetable(combinedTable, excelFile, 'Sheet', 'Fit_Quality_Report', 'WriteMode', 'append');
            else
                writetable(fitQualityCellTable, excelFile, 'Sheet', 'Fit_Quality_Report', 'WriteMode', 'append');
            end
            
            obj.formatSheet(excelFile, 'Fit_Quality_Report', fitQualityTable);
        end
        
        
        
        
        function formatSheetWindows(obj, excelFile, sheetName, dataTable)
            %FORMATSHEETWINDOWS Apply Excel formatting using COM (Windows only)
            
            try
                Excel = actxserver('Excel.Application');
                Excel.Visible = false;
                Excel.DisplayAlerts = false;
                
                Workbook = Excel.Workbooks.Open(excelFile);
                
                % Find sheet
                sheetFound = false;
                for i = 1:Workbook.Sheets.Count
                    if strcmp(Workbook.Sheets.Item(i).Name, sheetName)
                        Sheet = Workbook.Sheets.Item(i);
                        sheetFound = true;
                        break;
                    end
                end
                
                if ~sheetFound
                    Workbook.Close(false);
                    Excel.Quit();
                    delete(Excel);
                    return;
                end
                
                % Freeze top row
                Sheet.Range('A2').Select;
                Excel.ActiveWindow.FreezePanes = true;
                
                % Bold header row
                headerRange = Sheet.Range(sprintf('A1:%s1', obj.columnLetter(width(dataTable))));
                headerRange.Font.Bold = true;
                headerRange.Interior.Color = hex2dec('D9D9D9');  % Light gray
                
                % Auto-fit columns
                Sheet.Columns.AutoFit;
                
                % Apply conditional formatting to Fit_Quality column if present
                if ismember('Fit_Quality', dataTable.Properties.VariableNames)
                    qualityCol = find(strcmp(dataTable.Properties.VariableNames, 'Fit_Quality'));
                    qualityRange = Sheet.Range(sprintf('%s2:%s%d', ...
                        obj.columnLetter(qualityCol), obj.columnLetter(qualityCol), height(dataTable) + 1));
                    
                    % Good = Green
                    obj.addConditionalFormat(qualityRange, 'Good', [0, 176/255, 80/255]);
                    % Acceptable = Yellow
                    obj.addConditionalFormat(qualityRange, 'Acceptable', [1, 1, 0]);
                    % Poor = Orange
                    obj.addConditionalFormat(qualityRange, 'Poor', [1, 192/255, 0]);
                    % Failed = Red
                    obj.addConditionalFormat(qualityRange, 'Failed', [1, 0, 0]);
                end
                
                % Apply conditional formatting to R_squared column if present
                if ismember('R_squared', dataTable.Properties.VariableNames)
                    r2Col = find(strcmp(dataTable.Properties.VariableNames, 'R_squared'));
                    r2Range = Sheet.Range(sprintf('%s2:%s%d', ...
                        obj.columnLetter(r2Col), obj.columnLetter(r2Col), height(dataTable) + 1));
                    
                    % Color scale: red (0.8) -> yellow (0.9) -> green (1.0)
                    obj.addColorScaleFormat(r2Range, 0.8, 0.95);
                end
                
                % Save and close
                Workbook.Save();
                Workbook.Close(false);
                Excel.Quit();
                delete(Excel);
                
            catch ME
                try
                    if exist('Workbook', 'var')
                        Workbook.Close(false);
                    end
                    if exist('Excel', 'var')
                        Excel.Quit();
                        delete(Excel);
                    end
                catch
                    % Cleanup failed, continue
                end
                obj.logger.logDebug(sprintf('COM formatting error: %s', ME.message));
            end
        end
        
        function addConditionalFormat(obj, range, text, color)
            %ADDCONDITIONALFORMAT Add text-based conditional formatting
            
            try
                formatCondition = range.FormatConditions.Add(2, [], sprintf('="%s"', text));
                formatCondition.Interior.Color = obj.rgbToExcel(color);
            catch
                % Silently fail
            end
        end
        
        function addColorScaleFormat(obj, range, minVal, maxVal)
            %ADDCOLORSCALEFORMAT Add color scale conditional formatting
            
            try
                colorScale = range.FormatConditions.AddColorScale(3);
                
                % Min (red)
                colorScale.ColorScaleCriteria.Item(1).Type = 0;  % Lowest value
                colorScale.ColorScaleCriteria.Item(1).FormatColor.Color = obj.rgbToExcel([1, 0, 0]);
                
                % Mid (yellow)
                colorScale.ColorScaleCriteria.Item(2).Type = 4;  % Percentile
                colorScale.ColorScaleCriteria.Item(2).Value = 50;
                colorScale.ColorScaleCriteria.Item(2).FormatColor.Color = obj.rgbToExcel([1, 1, 0]);
                
                % Max (green)
                colorScale.ColorScaleCriteria.Item(3).Type = 1;  % Highest value
                colorScale.ColorScaleCriteria.Item(3).FormatColor.Color = obj.rgbToExcel([0, 176/255, 80/255]);
            catch
                % Silently fail
            end
        end
        
        function excelColor = rgbToExcel(obj, rgb)
            %RGBTOTEXCEL Convert RGB [0-1] to Excel BGR integer
            excelColor = rgb(3) * 255 + rgb(2) * 255 * 256 + rgb(1) * 255 * 65536;
        end
        
        function letter = columnLetter(obj, colNum)
            %COLUMNLETTER Convert column number to Excel letter (A, B, ..., AA, AB, ...)
            
            letter = '';
            while colNum > 0
                remainder = mod(colNum - 1, 26);
                letter = [char(65 + remainder), letter];
                colNum = floor((colNum - 1) / 26);
            end
        end
        
        function outputPath = createTimestampedFolder(obj, baseDir)
            %CREATETIMESTAMPEDFOLDER Create YYYYMMDD_HHMMSS output folder
            
            timestamp = datestr(now, 'yyyymmdd_HHMMSS');
            outputPath = fullfile(baseDir, timestamp);
            
            if ~exist(outputPath, 'dir')
                mkdir(outputPath);
                obj.logger.logInfo(sprintf('Created output folder: %s', outputPath));
            end
        end
        
        function strArray = robustCellToString(obj, data)
            %ROBUSTCELLTOSTRING Safely convert any cell/table column to string array
            
            if isstring(data)
                strArray = data;
                return;
            end
            
            if iscategorical(data)
                strArray = string(data);
                return;
            end
            
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
            
            if isnumeric(data)
                strArray = string(arrayfun(@num2str, data, 'UniformOutput', false));
            else
                try
                    strArray = string(data);
                catch
                    strArray = repmat("", size(data));
                end
            end
        end
    end
end
