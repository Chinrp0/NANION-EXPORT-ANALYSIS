classdef NanionSummaryFigure < handle
    %NANIONSUMMARYFIGURE Publication-quality summary figures
    %   FIXED: Colored compound legend + proper current axis scaling
    
    properties (Access = private)
        config
        logger
        compoundColors
        concentrationStyles
    end
    
    methods
        function obj = NanionSummaryFigure(config, logger)
            obj.config = config;
            obj.logger = logger;
            
            % Colorblind-friendly palette
            obj.compoundColors = [
                0.0, 0.45, 0.74;   % Blue
                0.85, 0.33, 0.10;  % Red-orange
                0.93, 0.69, 0.13;  % Gold
                0.49, 0.18, 0.56;  % Purple
                0.47, 0.67, 0.19;  % Green
                0.30, 0.75, 0.93;  % Cyan
                0.64, 0.08, 0.18;  % Maroon
                0.20, 0.20, 0.20;  % Dark gray
            ];
            
            obj.concentrationStyles = {'-', '--', ':', '-.'};
        end
        
        function [fig1, fig2] = createSummaryFigures(obj, filteredData, fittedData, summaryTable, outputPath, includePoorFits)
            if nargin < 6
                includePoorFits = 0;
            end
            
            obj.logger.logInfo('Creating summary figures...');
            
            fig1 = obj.createRepresentativeWellsFigure(filteredData, fittedData, summaryTable);
            
            if nargin >= 5 && ~isempty(outputPath)
                obj.saveFigure(fig1, outputPath, 'fig1_representative_wells');
            end
            
            fig2 = obj.createCellTypeAveragesFigure(filteredData, fittedData, summaryTable, includePoorFits);
            
            if nargin >= 5 && ~isempty(outputPath)
                obj.saveFigure(fig2, outputPath, 'fig2_cell_type_averages');
            end
            
            if nargin >= 5 && ~isempty(outputPath)
                obj.exportCompoundGroupStats(summaryTable, outputPath, includePoorFits);
            end
            
            obj.logger.logInfo('✓ Summary figures created');
        end
        
        function figHandle = createRepresentativeWellsFigure(obj, filteredData, fittedData, summaryTable)
            %CREATEREPRESENTATIVEWELLSFIGURE Optimized layout with fixed current axis scaling
            
            obj.logger.logInfo('Creating representative wells figure...');
            
            protocolType = filteredData.protocolInfo.type;
            voltages = filteredData.protocolInfo.voltages;
            
            [bestWells, worstWells] = obj.selectRepresentativeWells(summaryTable);
            
            numBest = min(3, height(bestWells));
            numWorst = min(3, height(worstWells));
            
            figHandle = figure('Position', [50, 50, 2100, 900], ...
                'Color', 'w', 'Name', 'Representative Wells');
            
            sharedLegendHandles = [];
            sharedLegendLabels = {};
            
            % Tight margins
            leftMargin = 0.05;
            rightMargin = 0.16;
            topMargin = 0.08;
            bottomMargin = 0.08;
            hspace = 0.08;
            vspace = 0.10;
            
            % Row 1: Best fits
            obj.logger.logInfo(sprintf('Plotting %d best fits...', numBest));
            for i = 1:numBest
                row = 1;
                col = i;
                
                plotWidth = (1 - leftMargin - rightMargin - 2*hspace) / 3;
                plotHeight = (1 - topMargin - bottomMargin - vspace) / 2;
                
                xPos = leftMargin + (col-1) * (plotWidth + hspace);
                yPos = 1 - topMargin - row * plotHeight - (row-1) * vspace;
                
                ax = axes('Position', [xPos, yPos, plotWidth, plotHeight]);
                
                [h, l] = obj.plotRepresentativeWell(filteredData, fittedData, bestWells(i, :), ...
                    voltages, protocolType, 'Best', false);
                
                if i == 1
                    sharedLegendHandles = h;
                    sharedLegendLabels = l;
                end
            end
            
            % Row 2: Worst passing fits
            obj.logger.logInfo(sprintf('Plotting %d worst passing fits...', numWorst));
            for i = 1:numWorst
                row = 2;
                col = i;
                
                plotWidth = (1 - leftMargin - rightMargin - 2*hspace) / 3;
                plotHeight = (1 - topMargin - bottomMargin - vspace) / 2;
                
                xPos = leftMargin + (col-1) * (plotWidth + hspace);
                yPos = 1 - topMargin - row * plotHeight - (row-1) * vspace;
                
                ax = axes('Position', [xPos, yPos, plotWidth, plotHeight]);
                
                obj.plotRepresentativeWell(filteredData, fittedData, worstWells(i, :), ...
                    voltages, protocolType, 'Acceptable', false);
            end
            
            % External legend
            if ~isempty(sharedLegendHandles)
                ax_legend = axes('Position', [0.87, 0.35, 0.12, 0.3], 'Visible', 'off');
                
                cleanLabels = cell(size(sharedLegendLabels));
                for i = 1:length(sharedLegendLabels)
                    label = sharedLegendLabels{i};
                    if contains(label, 'Fit')
                        parts = strsplit(label, ' ');
                        cleanLabels{i} = [parts{1} ' Fit'];
                    else
                        cleanLabels{i} = label;
                    end
                end
                
                legend(ax_legend, sharedLegendHandles, cleanLabels, ...
                    'Location', 'west', 'FontSize', 11, 'Box', 'on');
                title(ax_legend, 'Legend', 'FontSize', 13, 'FontWeight', 'bold', 'Visible', 'on');
            end
            
            % Title
            annotation('textbox', [0.05, 0.94, 0.78, 0.05], ...
                'String', sprintf('%s Protocol: Representative Wells', protocolType), ...
                'FontSize', 18, 'FontWeight', 'bold', ...
                'HorizontalAlignment', 'center', 'EdgeColor', 'none');
            
            obj.logger.logInfo('✓ Representative wells figure created');
        end
        
        function figHandle = createCellTypeAveragesFigure(obj, filteredData, fittedData, summaryTable, includePoorFits)
            %CREATECELLTYPEAVERAGESFIGURE With colored compound legend
            
            if nargin < 5
                includePoorFits = false;
            end
            
            obj.logger.logInfo('Creating cell type averages figure...');
            
            protocolType = filteredData.protocolInfo.type;
            voltages = filteredData.protocolInfo.voltages;
            
            % Filter by quality
            if includePoorFits == 2
                passingMask = true(height(summaryTable), 1);
            elseif includePoorFits == 1 || includePoorFits == true
                passingMask = strcmp(summaryTable.Fit_Quality, 'Good') | ...
                              strcmp(summaryTable.Fit_Quality, 'Acceptable') | ...
                              strcmp(summaryTable.Fit_Quality, 'Poor');
            else
                passingMask = strcmp(summaryTable.Fit_Quality, 'Good') | ...
                              strcmp(summaryTable.Fit_Quality, 'Acceptable');
            end
            
            passingTable = summaryTable(passingMask, :);
            
            if height(passingTable) == 0
                figHandle = [];
                return;
            end
            
            uniqueCellTypes = unique(passingTable.Cell_Type);
            numCellTypes = length(uniqueCellTypes);
            
            obj.logger.logInfo(sprintf('Found %d unique cell types', numCellTypes));
            
            figHandle = figure('Position', [50, 50, 1800, 700], ...
                'Color', 'w', 'Name', 'Cell Type Averages');
            
            allCompounds = unique(passingTable.Compound);
            compoundColorMap = obj.assignCompoundColors(allCompounds);
            
            allHandles = [];
            allLabels = {};
            compoundsSeen = containers.Map('KeyType', 'char', 'ValueType', 'logical');
            allStatsData = {};
            
            % Tight layout
            leftMargin = 0.06;
            rightMargin = 0.28;
            bottomMargin = 0.12;
            topMargin = 0.12;
            hspace = 0.04;
            
            for ct = 1:numCellTypes
                plotWidth = (1 - leftMargin - rightMargin - (numCellTypes-1)*hspace) / numCellTypes;
                plotHeight = 1 - topMargin - bottomMargin;
                
                xPos = leftMargin + (ct-1) * (plotWidth + hspace);
                yPos = bottomMargin;
                
                ax = axes('Position', [xPos, yPos, plotWidth, plotHeight]);
                
                cellType = uniqueCellTypes{ct};
                cellTypeMask = strcmp(passingTable.Cell_Type, cellType);
                cellTypeTable = passingTable(cellTypeMask, :);
                
                cellTypeCompounds = unique(cellTypeTable.Compound);
                
                hold on;
                
                for c = 1:length(cellTypeCompounds)
                    compound = cellTypeCompounds{c};
                    
                    compoundMask = strcmp(cellTypeTable.Compound, compound);
                    iv2Mask = compoundMask & (cellTypeTable.IV_Number == 2);
                    iv3Mask = compoundMask & (cellTypeTable.IV_Number == 3);
                    
                    iv2Data = cellTypeTable(iv2Mask, :);
                    iv3Data = cellTypeTable(iv3Mask, :);
                    
                    compoundColor = compoundColorMap(compound);
                    
                    % Plot IV2
                    if height(iv2Data) > 0
                        [h2, ~] = obj.plotCompoundCurve(filteredData, fittedData, iv2Data, ...
                            voltages, protocolType, compound, compoundColor, '-', 'o', 'IV2');
                        
                        compoundKey = char(compound);
                        if ~isKey(compoundsSeen, compoundKey)
                            allHandles = [allHandles; h2];
                            allLabels = [allLabels; {obj.formatCompoundName(compound)}];
                            compoundsSeen(compoundKey) = true;
                        end
                        
                        V_mid_mean = mean(iv2Data.V_mid_mV, 'omitnan');
                        V_mid_SEM = std(iv2Data.V_mid_mV, 'omitnan') / sqrt(height(iv2Data));
                        allStatsData{end+1} = {char(cellType), obj.formatCompoundName(compound), ...
                            height(iv2Data), V_mid_mean, V_mid_SEM, 'IV2'};
                    end
                    
                    % Plot IV3
                    if height(iv3Data) > 0
                        obj.plotCompoundCurve(filteredData, fittedData, iv3Data, ...
                            voltages, protocolType, compound, compoundColor, '--', 's', 'IV3');
                        
                        V_mid_mean = mean(iv3Data.V_mid_mV, 'omitnan');
                        V_mid_SEM = std(iv3Data.V_mid_mV, 'omitnan') / sqrt(height(iv3Data));
                        allStatsData{end+1} = {char(cellType), obj.formatCompoundName(compound), ...
                            height(iv3Data), V_mid_mean, V_mid_SEM, 'IV3'};
                    end
                end
                
                hold off;
                
                % Formatting
                xlabel('Voltage (mV)', 'FontSize', 13, 'FontWeight', 'bold');
                if ct == 1
                    if strcmp(protocolType, 'activation')
                        ylabel('Norm. Conductance (G/G_{max})', 'FontSize', 13, 'FontWeight', 'bold');
                    else
                        ylabel('Norm. Inactivation', 'FontSize', 13, 'FontWeight', 'bold');
                    end
                end
                
                title(sprintf('%s', char(cellType)), 'FontSize', 16, 'FontWeight', 'bold');
                
                grid on;
                box on;
                ylim([0 1.1]);
                xlim([min(voltages) - 5, max(voltages) + 5]);
                
                ax.GridAlpha = 0.2;
                ax.LineWidth = 1.2;
                ax.FontSize = 12;
            end
            
            % External stats panel with COLORED LEGEND
            ax_stats = axes('Position', [0.75, 0.12, 0.23, 0.76], 'Visible', 'off');
            hold on;
            
            % Format stats table
            statsText = sprintf('\\bf\\fontsize{14}Statistics\\rm\\fontsize{10}\n\n');
            
            currentCellType = '';
            for s = 1:length(allStatsData)
                cellType = allStatsData{s}{1};
                
                if ~strcmp(cellType, currentCellType)
                    if ~isempty(currentCellType)
                        statsText = sprintf('%s\n', statsText);
                    end
                    statsText = sprintf('%s\\bf%s\\rm\n', statsText, cellType);
                    statsText = sprintf('%s%s\n', statsText, repmat('─', 1, length(cellType)));
                    currentCellType = cellType;
                end
                
                compound = allStatsData{s}{2};
                n = allStatsData{s}{3};
                v_mid = allStatsData{s}{4};
                v_sem = allStatsData{s}{5};
                iv = allStatsData{s}{6};
                
                statsText = sprintf('%s%s (n=%d)\n', statsText, compound, n);
                statsText = sprintf('%s  %s: V½=%.1f±%.1f\n', statsText, iv, v_mid, v_sem);
            end
            
            % Display stats text
            text(0.05, 0.98, statsText, ...
                'Units', 'normalized', ...
                'VerticalAlignment', 'top', ...
                'FontName', 'Courier New', ...
                'FontSize', 9, ...
                'Interpreter', 'tex', ...
                'BackgroundColor', [0.98 0.98 0.98], ...
                'EdgeColor', [0.3 0.3 0.3], ...
                'LineWidth', 1.5, ...
                'Margin', 10);
            
            % COLORED COMPOUND LEGEND
            % Create legend entries with actual colors
            yStart = 0.30;  % Starting position for legend
            ySpacing = 0.04;  % Space between entries
            
            % Header
            text(0.05, yStart + 0.02, '\bf\fontsize{12}Compounds\rm\fontsize{10}', ...
                'Units', 'normalized', 'Interpreter', 'tex');
            text(0.05, yStart - 0.01, repmat('─', 1, 12), ...
                'Units', 'normalized', 'FontName', 'Courier New', 'FontSize', 10);
            
            % Plot colored markers for each compound
            for i = 1:length(allLabels)
                yPos = yStart - 0.04 - (i * ySpacing);
                
                % Get compound color
                compoundKey = char(allLabels{i});
                if isKey(compoundColorMap, compoundKey)
                    color = compoundColorMap(compoundKey);
                else
                    color = [0, 0, 0];
                end
                
                % Plot colored line/marker
                plot([0.08, 0.18], [yPos, yPos], '-o', ...
                    'Color', color, 'LineWidth', 2.5, ...
                    'MarkerSize', 7, 'MarkerFaceColor', color, ...
                    'MarkerEdgeColor', 'k', ...
                    'Parent', ax_stats, 'Clipping', 'off');
                
                % Add label
                text(0.20, yPos, allLabels{i}, ...
                    'Units', 'normalized', ...
                    'FontSize', 10, ...
                    'VerticalAlignment', 'middle');
            end
            
            % Add line style legend
            yLegendStart = yStart - 0.04 - ((length(allLabels) + 1) * ySpacing);
            text(0.05, yLegendStart - 0.02, '\bf\fontsize{11}Line Styles\rm\fontsize{9}', ...
                'Units', 'normalized', 'Interpreter', 'tex');
            text(0.05, yLegendStart - 0.05, repmat('─', 1, 11), ...
                'Units', 'normalized', 'FontName', 'Courier New', 'FontSize', 9);
            
            % IV2 solid
            plot([0.08, 0.18], [yLegendStart - 0.08, yLegendStart - 0.08], '-o', ...
                'Color', [0, 0, 0], 'LineWidth', 2, ...
                'MarkerSize', 6, 'MarkerFaceColor', [0.7, 0.7, 0.7], ...
                'MarkerEdgeColor', 'k', ...
                'Parent', ax_stats, 'Clipping', 'off');
            text(0.20, yLegendStart - 0.08, 'IV2 (solid, ○)', ...
                'Units', 'normalized', 'FontSize', 9, ...
                'VerticalAlignment', 'middle');
            
            % IV3 dashed
            plot([0.08, 0.18], [yLegendStart - 0.12, yLegendStart - 0.12], '--s', ...
                'Color', [0, 0, 0], 'LineWidth', 2, ...
                'MarkerSize', 6, 'MarkerFaceColor', [0.7, 0.7, 0.7], ...
                'MarkerEdgeColor', 'k', ...
                'Parent', ax_stats, 'Clipping', 'off');
            text(0.20, yLegendStart - 0.12, 'IV3 (dashed, □)', ...
                'Units', 'normalized', 'FontSize', 9, ...
                'VerticalAlignment', 'middle');
            
            hold off;
            
            % Title
            annotation('textbox', [0.06, 0.92, 0.62, 0.06], ...
                'String', sprintf('%s Protocol: Cell Type Comparison', protocolType), ...
                'FontSize', 18, 'FontWeight', 'bold', ...
                'HorizontalAlignment', 'center', 'EdgeColor', 'none');
            
            obj.logger.logInfo(sprintf('✓ Cell type averages figure created (%d cell types)', numCellTypes));
        end
    end
    
    methods (Access = private)
        %% REPRESENTATIVE WELLS METHODS
        
        function [bestWells, worstWells] = selectRepresentativeWells(obj, summaryTable)
            goodMask = strcmp(summaryTable.Fit_Quality, 'Good') | ...
                       strcmp(summaryTable.Fit_Quality, 'Acceptable');
            
            passingTable = summaryTable(goodMask, :);
            
            if height(passingTable) == 0
                bestWells = [];
                worstWells = [];
                return;
            end
            
            [~, sortIdx] = sort(passingTable.R_squared, 'descend');
            sortedTable = passingTable(sortIdx, :);
            
            numBest = min(3, height(sortedTable));
            bestWells = sortedTable(1:numBest, :);
            
            if height(sortedTable) > 3
                worstWells = sortedTable(end-2:end, :);
            else
                worstWells = sortedTable;
            end
        end
        
        function [legendHandles, legendLabels] = plotRepresentativeWell(obj, filteredData, fittedData, wellRow, ...
                voltages, protocolType, category, showLegend)
            
            if nargin < 8
                showLegend = true;
            end
            
            wellID = wellRow.Well_ID{1};
            r2 = wellRow.R_squared(1);
            
            wellIdx = find(strcmp(filteredData.wellIDs, wellID), 1);
            
            if isempty(wellIdx)
                text(0.5, 0.5, 'Well not found', 'HorizontalAlignment', 'west');
                legendHandles = [];
                legendLabels = {};
                return;
            end
            
            ivNames = fieldnames(filteredData.measurements);
            numIVs = length(ivNames);
            
            ivDataArray = {};
            ivFitArray = {};
            
            for i = 1:numIVs
                ivName = ivNames{i};
                ivDataArray{i} = obj.extractWellData(filteredData.measurements.(ivName), wellIdx);
                ivFit = obj.extractFitParams(fittedData, wellIdx, ivName);
                
                if ~isempty(ivFit) && ivFit.converged
                    ivFitStruct.fitParams = ivFit;
                    ivFitStruct.fittedCurve = 1 ./ (1 + exp((ivFit.V_mid - voltages) / ivFit.k));
                    ivFitArray{i} = ivFitStruct;
                else
                    ivFitArray{i} = [];
                end
            end
            
            [legendHandles, legendLabels] = obj.plotDualAxisFormatMultiIV(wellID, voltages, ivDataArray, ivFitArray, ...
                ivNames, category, r2, protocolType, showLegend);
        end
        
        function [legendHandles, legendLabels] = plotDualAxisFormatMultiIV(obj, wellID, voltages, ivDataArray, ivFitArray, ...
                ivNames, category, r2, protocolType, showLegend)
            %PLOTDUALAXISFORMATMULTIIV FIXED: Proper current axis scaling
            
            if nargin < 10
                showLegend = true;
            end
            
            markerSize = 5;
            lineWidth = 1.8;
            fitLineWidth = 2.5;
            markerAlpha = 0.85;
            
            ivColors = [
                0.0, 0.0, 0.0;
                0.0, 0.45, 0.74;
                0.85, 0.33, 0.10;
                0.49, 0.18, 0.56;
            ];
            
            ivCurrentColors = [
                0.5, 0.5, 0.5;
                0.4, 0.7, 1.0;
                1.0, 0.6, 0.4;
                0.7, 0.5, 0.8;
            ];
            
            numIVs = length(ivDataArray);
            
            legendHandles = [];
            legendLabels = {};
            
            %% FIRST: Find min/max current across ALL IVs for proper scaling
            allCurrents = [];
            for i = 1:numIVs
                ivData = ivDataArray{i};
                if ~isempty(ivData) && isfield(ivData, 'peakCurrent')
                    allCurrents = [allCurrents, ivData.peakCurrent];
                end
            end
            
            % Calculate proper limits with margin
            if ~isempty(allCurrents)
                minCurrent = min(allCurrents);
                maxCurrent = max(allCurrents);
                
                % Add 15% margin for better visibility
                marginFactor = 0.15;
                currentRange = abs(minCurrent - maxCurrent);
                
                if currentRange > 0
                    currentLimMin = minCurrent - marginFactor * currentRange;
                    currentLimMax = 0;  % Always keep 0 at top
                else
                    % All currents are the same
                    currentLimMin = minCurrent * 1.2;
                    currentLimMax = 0;
                end
            else
                currentLimMin = -1500;
                currentLimMax = 0;
            end
            
            %% LEFT: Conductance
            yyaxis left
            hold on;
            
            for i = 1:numIVs
                ivData = ivDataArray{i};
                ivFit = ivFitArray{i};
                
                if isempty(ivData) || ~isfield(ivData, 'conductance')
                    continue;
                end
                
                color_idx = min(i, size(ivColors, 1));
                condColor = ivColors(color_idx, :);
                
                h_cond = plot(voltages, ivData.conductance, '-o', ...
                    'Color', condColor, 'MarkerSize', markerSize, ...
                    'MarkerFaceColor', condColor, 'LineWidth', lineWidth, ...
                    'DisplayName', sprintf('%s Conductance', upper(ivNames{i})));
                h_cond.Color(4) = markerAlpha;
                
                legendHandles = [legendHandles; h_cond];
                legendLabels = [legendLabels; {sprintf('%s Conductance', upper(ivNames{i}))}];
                
                if ~isempty(ivFit) && isfield(ivFit, 'fittedCurve')
                    fitColor = condColor;
                    fitColor(4) = 0.7;
                    h_fit = plot(voltages, ivFit.fittedCurve, ':', ...
                        'Color', fitColor, 'LineWidth', fitLineWidth, ...
                        'DisplayName', sprintf('%s Fit (V_{1/2}=%.1f)', ...
                            upper(ivNames{i}), ivFit.fitParams.V_mid));
                    
                    legendHandles = [legendHandles; h_fit];
                    legendLabels = [legendLabels; {sprintf('%s Fit (V_{1/2}=%.1f)', ...
                        upper(ivNames{i}), ivFit.fitParams.V_mid)}];
                end
            end
            
            ylabel('Normalized Conductance (G/G_{max})', 'FontSize', 11, 'FontWeight', 'bold');
            ax = gca;
            ax.YColor = [0, 0, 0];
            ylim([0, 1.1]);
            
            %% RIGHT: Current (FIXED SCALING)
            yyaxis right
            hold on;
            
            for i = 1:numIVs
                ivData = ivDataArray{i};
                
                if isempty(ivData) || ~isfield(ivData, 'peakCurrent')
                    continue;
                end
                
                color_idx = min(i, size(ivCurrentColors, 1));
                currentColor = ivCurrentColors(color_idx, :);
                
                h_current = plot(voltages, ivData.peakCurrent, '-s', ...
                    'Color', currentColor, 'MarkerSize', markerSize, ...
                    'MarkerFaceColor', 'none', 'LineWidth', lineWidth, ...
                    'DisplayName', sprintf('%s Current', upper(ivNames{i})));
                h_current.Color(4) = markerAlpha;
                
                legendHandles = [legendHandles; h_current];
                legendLabels = [legendLabels; {sprintf('%s Current', upper(ivNames{i}))}];
            end
            
            ylabel('Peak Current (pA)', 'FontSize', 11, 'FontWeight', 'bold');
            ax = gca;
            ax.YColor = [0, 0, 0];
            
            % FIXED: Use calculated limits based on actual data
            ylim([currentLimMin, currentLimMax]);
            
            %% FORMATTING
            xlabel('Voltage (mV)', 'FontSize', 11, 'FontWeight', 'bold');
            xlim([min(voltages) - 5, max(voltages) + 5]);
            
            title(sprintf('%s: %s (R²=%.3f)', category, char(wellID), r2), ...
                'FontSize', 12, 'FontWeight', 'bold');
            
            grid on;
            ax = gca;
            ax.GridAlpha = 0.15;
            ax.Box = 'on';
            ax.LineWidth = 1.2;
            
            if showLegend
                legend('Location', 'northwest', 'FontSize', 7, 'Box', 'off');
            end
            
            hold off;
        end
        
        %% CELL TYPE AVERAGES METHODS
        
        function [h, label] = plotCompoundCurve(obj, filteredData, fittedData, compoundData, ...
                voltages, protocolType, compound, color, lineStyle, markerStyle, ivLabel)
            
            V_mid_mean = mean(compoundData.V_mid_mV, 'omitnan');
            k_mean = mean(compoundData.Slope_k_mV, 'omitnan');
            
            % Plot individual wells
            for w = 1:height(compoundData)
                wellID = compoundData.Well_ID{w};
                wellIdx = find(strcmp(filteredData.wellIDs, wellID), 1);
                
                if isempty(wellIdx)
                    continue;
                end
                
                ivNum = compoundData.IV_Number(w);
                ivFieldName = sprintf('iv%d', ivNum);
                
                if ~isfield(filteredData.measurements, ivFieldName)
                    continue;
                end
                
                measurements = filteredData.measurements.(ivFieldName);
                
                if strcmp(protocolType, 'activation')
                    yData = measurements.conductance(wellIdx, :);
                else
                    yData = measurements.inactivationData(wellIdx, :);
                    yData = (yData - min(yData)) / (max(yData) - min(yData));
                end
                
                plot(voltages, yData, lineStyle, ...
                    'Color', [color, 0.15], 'LineWidth', 0.5, ...
                    'Marker', 'none', 'HandleVisibility', 'off');
            end
            
            % Plot average curve
            V_fit = linspace(min(voltages), max(voltages), 100);
            G_mean = 1 ./ (1 + exp((V_mid_mean - V_fit) / k_mean));
            
            h = plot(V_fit, G_mean, lineStyle, ...
                'Color', color, 'LineWidth', 2.5, ...
                'Marker', markerStyle, 'MarkerSize', 7, ...
                'MarkerFaceColor', color, 'MarkerEdgeColor', 'k', ...
                'MarkerIndices', 1:10:length(V_fit), ...
                'DisplayName', sprintf('%s (n=%d)', obj.formatCompoundName(compound), height(compoundData)));
            
            label = sprintf('%s (n=%d)', obj.formatCompoundName(compound), height(compoundData));
        end
        
        %% HELPER METHODS
        
        function colorMap = assignCompoundColors(obj, compounds)
            colorMap = containers.Map('KeyType', 'char', 'ValueType', 'any');
            numCompounds = length(compounds);
            
            for i = 1:numCompounds
                compoundName = char(compounds(i));
                colorIdx = mod(i - 1, size(obj.compoundColors, 1)) + 1;
                colorMap(compoundName) = obj.compoundColors(colorIdx, :);
            end
        end
        
        function shortName = formatCompoundName(obj, compoundName)
            abbrevMap = containers.Map(...
                {'Tetrodotoxin', 'tetrodotoxin', 'TTX', ...
                 '4-Aminopyridine', '4-aminopyridine', '4-AP', ...
                 'Tetraethylammonium', 'tetraethylammonium', 'TEA', ...
                 'Control', 'Vehicle', 'VEHICLE', 'Reference'}, ...
                {'TTX', 'TTX', 'TTX', ...
                 '4-AP', '4-AP', '4-AP', ...
                 'TEA', 'TEA', 'TEA', ...
                 'Control', 'Vehicle', 'Vehicle', 'Reference'});
            
            compoundStr = char(compoundName);
            
            if isKey(abbrevMap, compoundStr)
                shortName = abbrevMap(compoundStr);
            else
                if length(compoundStr) > 15
                    shortName = [compoundStr(1:12), '...'];
                else
                    shortName = compoundStr;
                end
            end
        end
        
        function wellData = extractWellData(obj, ivData, wellIndex)
            fields = fieldnames(ivData);
            wellData = struct();
            
            for i = 1:length(fields)
                fieldName = fields{i};
                if size(ivData.(fieldName), 1) >= wellIndex
                    wellData.(fieldName) = ivData.(fieldName)(wellIndex, :);
                end
            end
        end
        
        function fitParams = extractFitParams(obj, fittedData, wellIdx, ivName)
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
        
        function exportCompoundGroupStats(obj, summaryTable, outputPath, includePoorFits)
            if nargin < 4
                includePoorFits = false;
            end
            
            obj.logger.logInfo('Exporting compound group statistics...');
            
            if includePoorFits == 2
                passingMask = true(height(summaryTable), 1);
            elseif includePoorFits == 1 || includePoorFits == true
                passingMask = strcmp(summaryTable.Fit_Quality, 'Good') | ...
                              strcmp(summaryTable.Fit_Quality, 'Acceptable') | ...
                              strcmp(summaryTable.Fit_Quality, 'Poor');
            else
                passingMask = strcmp(summaryTable.Fit_Quality, 'Good') | ...
                              strcmp(summaryTable.Fit_Quality, 'Acceptable');
            end
            
            passingTable = summaryTable(passingMask, :);
            
            if height(passingTable) == 0
                obj.logger.logWarning('No passing fits for statistics export');
                return;
            end
            
            [groupKeys, ~, groupIdx] = unique(...
                passingTable(:, {'Cell_Type', 'Compound', 'Concentration_uM'}), 'rows');
            
            numGroups = height(groupKeys);
            statsTable = table();
            
            for g = 1:numGroups
                groupMask = (groupIdx == g);
                groupData = passingTable(groupMask, :);
                
                stats = struct();
                stats.Cell_Type = groupKeys.Cell_Type(g);
                stats.Compound = groupKeys.Compound(g);
                stats.Concentration_uM = groupKeys.Concentration_uM(g);
                stats.N_Wells = height(groupData);
                stats.V_mid_Mean_mV = mean(groupData.V_mid_mV, 'omitnan');
                stats.V_mid_SEM_mV = std(groupData.V_mid_mV, 'omitnan') / sqrt(height(groupData));
                stats.V_mid_SD_mV = std(groupData.V_mid_mV, 'omitnan');
                stats.Slope_k_Mean_mV = mean(groupData.Slope_k_mV, 'omitnan');
                stats.Slope_k_SEM_mV = std(groupData.Slope_k_mV, 'omitnan') / sqrt(height(groupData));
                stats.Slope_k_SD_mV = std(groupData.Slope_k_mV, 'omitnan');
                stats.R_squared_Mean = mean(groupData.R_squared, 'omitnan');
                stats.R_squared_SEM = std(groupData.R_squared, 'omitnan') / sqrt(height(groupData));
                
                statsTable = [statsTable; struct2table(stats)];
            end
            
            statsTable = sortrows(statsTable, {'Cell_Type', 'Compound', 'Concentration_uM'});
            
            fprintf('\n=== COMPOUND GROUP STATISTICS ===\n');
            disp(statsTable);
            
            excelFile = fullfile(outputPath, 'summary_table.xlsx');
            
            try
                writetable(statsTable, excelFile, 'Sheet', 'Compound_Group_Stats');
                obj.logger.logInfo(sprintf('✓ Saved compound group stats to: %s', excelFile));
            catch ME
                obj.logger.logWarning(sprintf('Could not write to Excel: %s', ME.message));
            end
        end
        
        function saveFigure(obj, figHandle, outputPath, baseName)
            if isempty(figHandle)
                return;
            end
            
            if ~exist(outputPath, 'dir')
                mkdir(outputPath);
            end
            
            timestamp = datestr(now, 'yyyymmdd_HHMMSS');
            fileName = sprintf('%s_%s', baseName, timestamp);
            
            pngFile = fullfile(outputPath, [fileName, '.png']);
            saveas(figHandle, pngFile);
            obj.logger.logInfo(sprintf('✓ Saved PNG: %s', pngFile));
            
            figFile = fullfile(outputPath, [fileName, '.fig']);
            savefig(figHandle, figFile);
            obj.logger.logInfo(sprintf('✓ Saved FIG: %s', figFile));
            
            try
                pdfFile = fullfile(outputPath, [fileName, '.pdf']);
                exportgraphics(figHandle, pdfFile, 'ContentType', 'vector');
                obj.logger.logInfo(sprintf('✓ Saved PDF: %s', pdfFile));
            catch
                obj.logger.logDebug('PDF export not available');
            end
        end
    end
end
