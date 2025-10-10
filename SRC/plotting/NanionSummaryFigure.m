classdef NanionSummaryFigure < handle
    %NANIONSUMMARYFIGURE Generate publication-quality summary figures
    %   Creates 3-row grid: Best fits, Worst passing fits, Cell type averages
    
    properties (Access = private)
        config
        logger
    end
    
    methods
        function obj = NanionSummaryFigure(config, logger)
            obj.config = config;
            obj.logger = logger;
        end
        
        function figHandle = createSummaryFigure(obj, filteredData, fittedData, summaryTable, outputPath)
            %CREATESUMMARYFIGURE Generate comprehensive summary figure
            %   Inputs:
            %     filteredData - data structure from NanionDataExtractor
            %     fittedData - fit results from NanionBoltzmannFitter
            %     summaryTable - summary table from NanionSummaryTableBuilder
            %     outputPath - where to save figure
            
            obj.logger.logInfo('Creating summary figure...');
            
            protocolType = filteredData.protocolInfo.type;
            voltages = filteredData.protocolInfo.voltages;
            
            % Select wells for best/worst fits
            [bestWells, worstWells] = obj.selectRepresentativeWells(summaryTable, fittedData);
            
            % Get unique cell types for averaging
            cellTypes = unique(summaryTable.Cell_Type);
            cellTypes = cellTypes(cellTypes ~= "");  % Remove empty
            
            % Determine grid layout
            numBest = min(3, height(bestWells));
            numWorst = min(3, height(worstWells));
            numCellTypes = min(3, length(cellTypes));  % Max 3 cell types per figure
            
            totalCols = max([numBest, numWorst, numCellTypes]);
            
            % Create figure
            figHandle = figure('Position', [100, 100, 400*totalCols, 1200], ...
                'Color', 'w', 'Name', 'Summary Figure');
            
            % Row 1: Best fits
            obj.logger.logInfo(sprintf('Plotting %d best fits...', numBest));
            for i = 1:numBest
                subplot(3, totalCols, i);
                obj.plotSingleWell(filteredData, fittedData, bestWells(i, :), voltages, protocolType, 'Best');
            end
            
            % Row 2: Worst passing fits
            obj.logger.logInfo(sprintf('Plotting %d worst passing fits...', numWorst));
            for i = 1:numWorst
                subplot(3, totalCols, totalCols + i);
                obj.plotSingleWell(filteredData, fittedData, worstWells(i, :), voltages, protocolType, 'Acceptable');
            end
            
            % Row 3: Cell type averages
            obj.logger.logInfo(sprintf('Plotting %d cell type averages...', numCellTypes));
            for i = 1:numCellTypes
                subplot(3, totalCols, 2*totalCols + i);
                obj.plotCellTypeAverage(filteredData, fittedData, summaryTable, ...
                    cellTypes(i), voltages, protocolType);
            end
            
            % Add overall title
            sgtitle(sprintf('%s Protocol Summary', protocolType), ...
                'FontSize', 16, 'FontWeight', 'bold');
            
            % Save figure
            if nargin >= 5 && ~isempty(outputPath)
                obj.saveFigure(figHandle, outputPath, 'summary_figure');
            end
            
            obj.logger.logInfo('✓ Summary figure created');
        end
    end
    
    methods (Access = private)
        function [bestWells, worstWells] = selectRepresentativeWells(obj, summaryTable, fittedData)
            %SELECTREPRESENTATIVEWELLS Select best and worst passing fits
            
            % Filter for Good and Acceptable fits only
            goodMask = strcmp(summaryTable.Fit_Quality, 'Good') | ...
                       strcmp(summaryTable.Fit_Quality, 'Acceptable');
            
            passingTable = summaryTable(goodMask, :);
            
            if height(passingTable) == 0
                obj.logger.logWarning('No passing fits found');
                bestWells = [];
                worstWells = [];
                return;
            end
            
            % Sort by R²
            [~, sortIdx] = sort(passingTable.R_squared, 'descend');
            sortedTable = passingTable(sortIdx, :);
            
            % Best: Top 3 (highest R²)
            numBest = min(3, height(sortedTable));
            bestWells = sortedTable(1:numBest, :);
            
            % Worst passing: Bottom 3 (lowest R² but still passing)
            if height(sortedTable) > 3
                worstWells = sortedTable(end-2:end, :);
            else
                worstWells = sortedTable;  % If ≤3 wells, use same as best
            end
            
            obj.logger.logDebug(sprintf('Selected %d best, %d worst passing wells', ...
                height(bestWells), height(worstWells)));
        end
        
        function plotSingleWell(obj, filteredData, fittedData, wellRow, voltages, protocolType, category)
            %PLOTSINGLEWELL Plot individual well with Boltzmann fit
            
            % Extract values from single-row table
            wellID = wellRow.Well_ID{1};  % Cell array - extract first element
            ivNumber = wellRow.IV_Number(1);  % Numeric - extract first element
            r2 = wellRow.R_squared(1);  % Numeric - extract first element
            
            % Find well index in filteredData
            wellIdx = find(strcmp(filteredData.wellIDs, wellID), 1);
            
            if isempty(wellIdx)
                text(0.5, 0.5, 'Well not found', 'HorizontalAlignment', 'center');
                return;
            end
            
            % Get IV data
            ivName = sprintf('iv%d', ivNumber);
            measurements = filteredData.measurements.(ivName);
            
            % Extract data based on protocol
            if strcmp(protocolType, 'activation')
                % Use raw conductance (nS) for plotting
                yData = measurements.conductance_raw(wellIdx, :);
                yLabel = 'Conductance (nS)';
                
                % Normalize for fitting visualization
                yDataNorm = measurements.conductance(wellIdx, :);
            else
                % Inactivation protocol
                yData = measurements.inactivationData(wellIdx, :);
                yLabel = 'Current (pA)';
                
                % Normalize
                yMin = min(yData);
                yMax = max(yData);
                if yMax ~= yMin
                    yDataNorm = (yData - yMin) / (yMax - yMin);
                else
                    yDataNorm = zeros(size(yData));
                end
            end
            
            % Plot data points
            hold on;
            plot(voltages, yData, 'ko', 'MarkerSize', 6, 'MarkerFaceColor', 'k');
            
            % Plot fit if available
            fitParams = obj.extractFitParams(fittedData, wellIdx, ivName);
            if ~isempty(fitParams) && fitParams.converged
                V_mid = fitParams.V_mid;
                k = fitParams.k;
                
                % Generate smooth fit curve
                V_fit = linspace(min(voltages), max(voltages), 100);
                G_fit_norm = 1 ./ (1 + exp((V_mid - V_fit) / k));
                
                % Scale fit to match data range
                if strcmp(protocolType, 'activation')
                    G_fit = G_fit_norm * (max(yData) - min(yData)) + min(yData);
                else
                    G_fit = G_fit_norm * (max(yData) - min(yData)) + min(yData);
                end
                
                plot(V_fit, G_fit, 'r-', 'LineWidth', 2);
            end
            
            hold off;
            
            % Formatting
            xlabel('Voltage (mV)', 'FontSize', 10);
            ylabel(yLabel, 'FontSize', 10);
            title(sprintf('%s: %s (R²=%.3f)', category, char(wellID), r2), ...
                'FontSize', 11, 'FontWeight', 'bold');
            grid on;
            box on;
            
            % Add V_mid marker if fit exists
            if ~isempty(fitParams) && fitParams.converged
                xline(V_mid, '--', sprintf('V_{1/2}=%.1f mV', V_mid), ...
                    'Color', [0.5 0.5 0.5], 'LineWidth', 1, 'FontSize', 8);
            end
        end
        
        function plotCellTypeAverage(obj, filteredData, fittedData, summaryTable, cellType, voltages, protocolType)
            %PLOTCELLTYPEAVERAGE Plot averaged data for a cell type
            
            % Filter for this cell type
            typeMask = strcmp(summaryTable.Cell_Type, cellType);
            typeTable = summaryTable(typeMask, :);
            
            if height(typeTable) == 0
                text(0.5, 0.5, sprintf('No data for %s', char(cellType)), ...
                    'HorizontalAlignment', 'center');
                return;
            end
            
            % Calculate group statistics
            groupStats = struct();
            groupStats.n = height(typeTable);
            groupStats.V_mid_mean = mean(typeTable.V_mid_mV, 'omitnan');
            groupStats.V_mid_SEM = std(typeTable.V_mid_mV, 'omitnan') / sqrt(groupStats.n);
            groupStats.k_mean = mean(typeTable.Slope_k_mV, 'omitnan');
            groupStats.k_SEM = std(typeTable.Slope_k_mV, 'omitnan') / sqrt(groupStats.n);
            groupStats.R2_mean = mean(typeTable.R_squared, 'omitnan');
            groupStats.R2_SEM = std(typeTable.R_squared, 'omitnan') / sqrt(groupStats.n);
            
            hold on;
            
            % Plot individual wells (semi-transparent)
            for i = 1:height(typeTable)
                wellID = typeTable.Well_ID{i};  % Cell array - extract element
                ivNumber = typeTable.IV_Number(i);  % Numeric
                
                % Find well in filteredData
                wellIdx = find(strcmp(filteredData.wellIDs, wellID), 1);
                if isempty(wellIdx)
                    continue;
                end
                
                % Get data
                ivName = sprintf('iv%d', ivNumber);
                measurements = filteredData.measurements.(ivName);
                
                if strcmp(protocolType, 'activation')
                    yData = measurements.conductance(wellIdx, :);  % Normalized
                else
                    yData = measurements.inactivationData(wellIdx, :);
                    yData = (yData - min(yData)) / (max(yData) - min(yData));
                end
                
                % Plot thin transparent line
                plot(voltages, yData, '-', 'Color', [0.7 0.7 0.7 0.3], 'LineWidth', 0.5);
            end
            
            % Plot group average (thick line)
            V_fit = linspace(min(voltages), max(voltages), 100);
            G_mean = 1 ./ (1 + exp((groupStats.V_mid_mean - V_fit) / groupStats.k_mean));
            
            plot(V_fit, G_mean, 'b-', 'LineWidth', 3);
            
            % Add SEM band
            G_upper = 1 ./ (1 + exp(((groupStats.V_mid_mean - groupStats.V_mid_SEM) - V_fit) / groupStats.k_mean));
            G_lower = 1 ./ (1 + exp(((groupStats.V_mid_mean + groupStats.V_mid_SEM) - V_fit) / groupStats.k_mean));
            
            fill([V_fit, fliplr(V_fit)], [G_upper, fliplr(G_lower)], ...
                'b', 'FaceAlpha', 0.2, 'EdgeColor', 'none');
            
            hold off;
            
            % Formatting
            xlabel('Voltage (mV)', 'FontSize', 10);
            if strcmp(protocolType, 'activation')
                ylabel('Normalized Conductance (G/G_{max})', 'FontSize', 10);
            else
                ylabel('Normalized Inactivation', 'FontSize', 10);
            end
            
            title(sprintf('%s (n=%d)', char(cellType), groupStats.n), ...
                'FontSize', 11, 'FontWeight', 'bold');
            
            grid on;
            box on;
            ylim([0 1]);
            
            % Add statistics box
            statsText = sprintf('V_{1/2} = %.1f ± %.1f mV\nk = %.1f ± %.1f mV\nR² = %.3f ± %.3f', ...
                groupStats.V_mid_mean, groupStats.V_mid_SEM, ...
                groupStats.k_mean, groupStats.k_SEM, ...
                groupStats.R2_mean, groupStats.R2_SEM);
            
            text(0.05, 0.95, statsText, 'Units', 'normalized', ...
                'VerticalAlignment', 'top', 'FontSize', 8, ...
                'BackgroundColor', 'w', 'EdgeColor', 'k');
        end
        
        function fitParams = extractFitParams(obj, fittedData, wellIdx, ivName)
            %EXTRACTFITPARAMS Extract fit parameters for specific well and IV
            
            if isempty(fittedData) || wellIdx > length(fittedData.wells)
                fitParams = [];
                return;
            end
            
            well = fittedData.wells(wellIdx);
            
            if strcmp(ivName, 'iv1') && ~isempty(well.iv1)
                ivFit = well.iv1;
            elseif strcmp(ivName, 'iv2') && ~isempty(well.iv2)
                ivFit = well.iv2;
            elseif strcmp(ivName, 'iv3') && isfield(well, 'iv3') && ~isempty(well.iv3)
                ivFit = well.iv3;
            elseif strcmp(ivName, 'iv4') && isfield(well, 'iv4') && ~isempty(well.iv4)
                ivFit = well.iv4;
            else
                fitParams = [];
                return;
            end
            
            fitParams = ivFit.fitParams;
            fitParams.quality = ivFit.fitQuality;
        end
        
        function saveFigure(obj, figHandle, outputPath, baseName)
            %SAVEFIGURE Save figure in multiple formats
            
            % Ensure output directory exists
            if ~exist(outputPath, 'dir')
                mkdir(outputPath);
            end
            
            % Generate filename with timestamp
            timestamp = datestr(now, 'yyyymmdd_HHMMSS');
            fileName = sprintf('%s_%s', baseName, timestamp);
            
            % Save as PNG (high resolution)
            pngFile = fullfile(outputPath, [fileName, '.png']);
            saveas(figHandle, pngFile);
            obj.logger.logInfo(sprintf('✓ Saved PNG: %s', pngFile));
            
            % Save as FIG (MATLAB format for editing)
            figFile = fullfile(outputPath, [fileName, '.fig']);
            savefig(figHandle, figFile);
            obj.logger.logInfo(sprintf('✓ Saved FIG: %s', figFile));
            
            % Optionally save as PDF (vector graphics)
            try
                pdfFile = fullfile(outputPath, [fileName, '.pdf']);
                exportgraphics(figHandle, pdfFile, 'ContentType', 'vector');
                obj.logger.logInfo(sprintf('✓ Saved PDF: %s', pdfFile));
            catch
                obj.logger.logDebug('PDF export not available (requires MATLAB R2020a+)');
            end
        end
    end
end
