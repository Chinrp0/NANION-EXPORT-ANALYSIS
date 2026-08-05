classdef NanionSummaryFigure < handle
    %NANIONSUMMARYFIGURE Publication-quality summary figures
    %   FIXED: Colored compound legend + proper current axis scaling + invisible figures
    
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
                'Color', 'w', 'Name', 'Representative Wells', ...
                'Visible', 'off');
            
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
                'Color', 'w', 'Name', 'Cell Type Averages', ...
                'Visible', 'off');
            
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
                
                % Track handles/labels for THIS subplot's legend
                subplotHandles = [];
                subplotLabels = {};
                
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
                        
                        % Add to subplot-specific legend
                        subplotHandles = [subplotHandles; h2];
                        subplotLabels = [subplotLabels; {sprintf('%s (IV2)', obj.formatCompoundName(compound))}];
                        
                        % Track globally for first occurrence
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
                        [h3, ~] = obj.plotCompoundCurve(filteredData, fittedData, iv3Data, ...
                            voltages, protocolType, compound, compoundColor, '--', 's', 'IV3');
                        
                        % Add to subplot-specific legend
                        subplotHandles = [subplotHandles; h3];
                        subplotLabels = [subplotLabels; {sprintf('%s (IV3)', obj.formatCompoundName(compound))}];
                        
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
                
                % Add legend to each subplot showing compounds in THIS cell type
                if ~isempty(subplotHandles)
                    leg = legend(subplotHandles, subplotLabels, ...
                        'Location', 'southeast', ...
                        'FontSize', 9, ...
                        'Box', 'on');
                end
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
            
            % COLORED COMPOUND LEGEND - REMOVED (now in individual subplots)
            % Just show line style reference
            yStart = 0.25;
            
            % Set axis limits to [0,1] for coordinate plotting
            xlim(ax_stats, [0, 1]);
            ylim(ax_stats, [0, 1]);
            
            % Line style legend
            text(ax_stats, 0.05, yStart, '\bf\fontsize{11}Line Styles\rm\fontsize{9}', ...
                'Units', 'data', 'Interpreter', 'tex');
            text(ax_stats, 0.05, yStart - 0.03, repmat('─', 1, 11), ...
                'Units', 'data', 'FontName', 'Courier New', 'FontSize', 9);
            
            % IV2 solid
            plot(ax_stats, [0.08, 0.18], [yStart - 0.06, yStart - 0.06], '-o', ...
                'Color', [0, 0, 0], 'LineWidth', 2, ...
                'MarkerSize', 6, 'MarkerFaceColor', [0.7, 0.7, 0.7], ...
                'MarkerEdgeColor', 'k', ...
                'Clipping', 'off');
            text(ax_stats, 0.20, yStart - 0.06, 'IV2 (solid, ○)', ...
                'Units', 'data', 'FontSize', 9, ...
                'VerticalAlignment', 'middle');
            
            % IV3 dashed
            plot(ax_stats, [0.08, 0.18], [yStart - 0.10, yStart - 0.10], '--s', ...
                'Color', [0, 0, 0], 'LineWidth', 2, ...
                'MarkerSize', 6, 'MarkerFaceColor', [0.7, 0.7, 0.7], ...
                'MarkerEdgeColor', 'k', ...
                'Clipping', 'off');
            text(ax_stats, 0.20, yStart - 0.10, 'IV3 (dashed, □)', ...
                'Units', 'data', 'FontSize', 9, ...
                'VerticalAlignment', 'middle');
            
            hold off;
            
            % Title
            annotation('textbox', [0.06, 0.92, 0.62, 0.06], ...
                'String', sprintf('%s Protocol: Cell Type Comparison', protocolType), ...
                'FontSize', 18, 'FontWeight', 'bold', ...
                'HorizontalAlignment', 'center', 'EdgeColor', 'none');
            
            obj.logger.logInfo(sprintf('✓ Cell type averages figure created (%d cell types)', numCellTypes));
        end

        function figHandles = createAggregatedCellTypeAveragesFigure(obj, filteredData, fittedData, summaryTable, protocolType, includePoorFits)
            %CREATEAGGREGATEDCELLTYPEAVERAGESFIGURE Generate Figure 2 from multiple files
            %   ONE FIGURE PER CELL LINE (cell type) so the individual traces
            %   are easy to see. Returns an ARRAY of figure handles (one per
            %   cell type); each figure carries UserData.cellType for naming
            %   the saved file.

            if nargin < 6
                includePoorFits = false;
            end

            obj.logger.logInfo('Creating AGGREGATED cell type averages figure(s)...');

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
                obj.logger.logWarning('No passing fits for aggregated figure');
                figHandles = gobjects(0);
                return;
            end

            uniqueCellTypes = unique(passingTable.Cell_Type);
            numCellTypes = length(uniqueCellTypes);

            obj.logger.logInfo(sprintf('Aggregated figure: %d cell line(s), %d total rows', ...
                numCellTypes, height(passingTable)));

            % One full-size panel per cell line so individual traces stay legible.
            compoundColorMap = obj.assignCompoundColors(unique(passingTable.Compound));

            figHandles = gobjects(numCellTypes, 1);
            for k = 1:numCellTypes
                cellType = uniqueCellTypes{k};

                fig = figure('Position', [50, 50, 1000, 720], ...
                    'Color', 'w', 'Visible', 'off', ...
                    'Name', sprintf('Cell Line Average - %s (%s)', char(cellType), protocolType));
                fig.UserData = struct('cellType', char(cellType));
                figHandles(k) = fig;

                ax = axes('Parent', fig, 'Position', [0.10, 0.11, 0.86, 0.80]);
                obj.plotCellTypePanel(ax, cellType, passingTable, filteredData, ...
                    fittedData, voltages, protocolType, compoundColorMap);

                sgtitle(fig, sprintf('%s Protocol — Cell Line Average (AGGREGATED)', protocolType), ...
                    'FontSize', 15, 'FontWeight', 'bold');
            end

            obj.logger.logInfo(sprintf('✓ Aggregated figure(s) created: one per cell line (%d total)', ...
                numCellTypes));
        end

        function plotCellTypePanel(obj, ax, cellType, passingTable, filteredData, fittedData, voltages, protocolType, compoundColorMap)
            %PLOTCELLTYPEPANEL Draw one cell-type panel (IV2 solid, IV3 dashed);
            %   V_1/2 stats are folded into the legend labels (no external stats box).

            hold(ax, 'on');
            cellTypeTable = passingTable(strcmp(passingTable.Cell_Type, cellType), :);
            cellTypeCompounds = unique(cellTypeTable.Compound);

            % Plot every IV present (IV1 reference + IV2..IVN conditions): line
            % style encodes the IV, colour the compound. The legend collapses to
            % ONE row per compound with V_1/2 averaged across that compound's IVs
            % (spread = std); per-IV V_1/2 lives in the exported CSV.
            ivNums = unique(cellTypeTable.IV_Number(:))';
            lineStyles = {'-', '--', ':', '-.'};
            markers = {'o', 's', '^', 'd', 'v', '>', '<', 'p'};

            handles = [];
            labels = {};

            for c = 1:numel(cellTypeCompounds)
                compound = cellTypeCompounds{c};
                compoundColor = compoundColorMap(compound);

                for ivNum = ivNums
                    d = cellTypeTable(strcmp(cellTypeTable.Compound, compound) & ...
                        cellTypeTable.IV_Number == ivNum, :);
                    if height(d) == 0; continue; end
                    ls = lineStyles{mod(ivNum - 1, numel(lineStyles)) + 1};
                    mk = markers{mod(ivNum - 1, numel(markers)) + 1};
                    obj.plotCompoundCurve(filteredData, fittedData, d, voltages, ...
                        protocolType, compound, compoundColor, ls, mk, sprintf('IV%d', ivNum));
                end

                % One legend entry per compound: clean solid swatch + aggregate V_1/2
                dc = cellTypeTable(strcmp(cellTypeTable.Compound, compound), :);
                if height(dc) == 0; continue; end
                hSwatch = plot(ax, NaN, NaN, '-', 'Color', compoundColor, 'LineWidth', 2.5);
                vMid = mean(dc.V_mid_mV, 'omitnan');
                vStd = std(dc.V_mid_mV, 'omitnan');
                nWells = numel(unique(dc.Well_ID));
                handles = [handles; hSwatch]; %#ok<AGROW>
                labels = [labels; {sprintf('%s (n=%d, V_{1/2}=%.1f\\pm%.1f)', ...
                    obj.formatCompoundName(compound), nWells, vMid, vStd)}]; %#ok<AGROW>
            end
            hold(ax, 'off');

            xlabel(ax, 'Voltage (mV)', 'FontSize', 11, 'FontWeight', 'bold');
            if strcmp(protocolType, 'activation')
                ylabel(ax, 'Norm. Conductance (G/G_{max})', 'FontSize', 11, 'FontWeight', 'bold');
            else
                ylabel(ax, 'Norm. Inactivation (I/I_{max})', 'FontSize', 11, 'FontWeight', 'bold');
            end
            title(ax, char(cellType), 'FontSize', 14, 'FontWeight', 'bold');
            grid(ax, 'on'); box(ax, 'on');
            ylim(ax, [0 1.1]);
            xlim(ax, [min(voltages) - 5, max(voltages) + 5]);
            set(ax, 'GridAlpha', 0.2, 'LineWidth', 1.1, 'FontSize', 10);

            if ~isempty(handles)
                legend(ax, handles, labels, 'Location', 'southeast', 'FontSize', 7, 'Box', 'on');
            end
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

            % Build one entry per IV carrying: the normalized data that was fit
            % and the fitted curve (both stored by the fitter, protocol-agnostic),
            % plus the protocol-specific raw current for the right axis.
            hasFit = ~isempty(fittedData) && wellIdx <= numel(fittedData.wells);
            ivDataArray = cell(1, numIVs);
            for i = 1:numIVs
                ivName = ivNames{i};
                entry = struct();

                if hasFit && isfield(fittedData.wells(wellIdx), ivName)
                    wf = fittedData.wells(wellIdx).(ivName);
                    if isfield(wf, 'data');        entry.normData = wf.data; end
                    if isfield(wf, 'fittedCurve') && ~isempty(wf.fittedCurve)
                        entry.fittedCurve = wf.fittedCurve;
                    end
                    if isfield(wf, 'fitParams');   entry.fitParams = wf.fitParams; end
                end

                m = filteredData.measurements.(ivName);
                if strcmp(protocolType, 'activation') && isfield(m, 'peakCurrent')
                    entry.current = m.peakCurrent(wellIdx, :);
                elseif isfield(m, 'inactivationData')
                    entry.current = m.inactivationData(wellIdx, :);
                end

                ivDataArray{i} = entry;
            end

            [legendHandles, legendLabels] = obj.plotDualAxisFormatMultiIV(wellID, voltages, ivDataArray, ...
                ivNames, category, r2, protocolType, showLegend);
        end
        
        function [legendHandles, legendLabels] = plotDualAxisFormatMultiIV(obj, wellID, voltages, ivDataArray, ...
                ivNames, category, r2, protocolType, showLegend)
            %PLOTDUALAXISFORMATMULTIIV Left: normalized data + Boltzmann fit.
            %   Right: protocol-specific raw current. Works for activation AND
            %   inactivation and for any number of IVs.

            if nargin < 9
                showLegend = true;
            end

            markerSize = 5;
            lineWidth = 1.8;
            fitLineWidth = 2.5;

            % Enough distinct colours for up to 8 IVs
            ivColors = [
                0.00, 0.00, 0.00; 0.00, 0.45, 0.74; 0.85, 0.33, 0.10; 0.49, 0.18, 0.56;
                0.47, 0.67, 0.19; 0.30, 0.75, 0.93; 0.64, 0.08, 0.18; 0.50, 0.50, 0.50];
            ivCurrentColors = ivColors * 0.55 + 0.45;   % lighter variants for the current traces

            numIVs = numel(ivDataArray);
            legendHandles = [];
            legendLabels = {};

            % Right-axis current limits across all IVs
            allCurrents = [];
            for i = 1:numIVs
                e = ivDataArray{i};
                if isfield(e, 'current'); allCurrents = [allCurrents, e.current]; end %#ok<AGROW>
            end
            if ~isempty(allCurrents) && any(~isnan(allCurrents))
                mn = min(allCurrents, [], 'omitnan');
                mx = max(allCurrents, [], 'omitnan');
                pad = 0.10 * max(abs([mn, mx]), [], 'omitnan') + eps;
                currentLimMin = min(mn - pad, 0);
                currentLimMax = max(mx + pad, 0);
            else
                currentLimMin = -1500;
                currentLimMax = 0;
            end

            %% LEFT: normalized data (markers) + fitted curve (line)
            yyaxis left
            hold on;
            for i = 1:numIVs
                e = ivDataArray{i};
                col = ivColors(min(i, size(ivColors, 1)), :);

                if isfield(e, 'normData') && any(~isnan(e.normData))
                    h = plot(voltages, e.normData, 'o', 'Color', col, ...
                        'MarkerSize', markerSize, 'MarkerFaceColor', col, 'LineWidth', 1);
                    legendHandles = [legendHandles; h]; %#ok<AGROW>
                    legendLabels = [legendLabels; {sprintf('%s data', upper(ivNames{i}))}]; %#ok<AGROW>
                end

                if isfield(e, 'fittedCurve') && ~isempty(e.fittedCurve)
                    vmid = NaN;
                    if isfield(e, 'fitParams') && isfield(e.fitParams, 'V_mid'); vmid = e.fitParams.V_mid; end
                    h = plot(voltages, e.fittedCurve, '-', 'Color', col, 'LineWidth', fitLineWidth);
                    legendHandles = [legendHandles; h]; %#ok<AGROW>
                    legendLabels = [legendLabels; {sprintf('%s fit (V_{1/2}=%.1f)', upper(ivNames{i}), vmid)}]; %#ok<AGROW>
                end
            end
            if strcmp(protocolType, 'activation')
                leftLabel = 'Normalized Conductance (G/G_{max})';
            else
                leftLabel = 'Normalized Inactivation (I/I_{max})';
            end
            ylabel(leftLabel, 'FontSize', 11, 'FontWeight', 'bold');
            ax = gca; ax.YColor = [0, 0, 0];
            ylim([-0.1, 1.2]);

            %% RIGHT: raw current
            yyaxis right
            hold on;
            for i = 1:numIVs
                e = ivDataArray{i};
                if ~isfield(e, 'current'); continue; end
                col = ivCurrentColors(min(i, size(ivCurrentColors, 1)), :);
                plot(voltages, e.current, '-s', 'Color', col, 'MarkerSize', markerSize, ...
                    'MarkerFaceColor', 'none', 'LineWidth', lineWidth);
            end
            if strcmp(protocolType, 'activation')
                rightLabel = 'Peak Current (pA)';
            else
                rightLabel = 'Test-pulse Current (pA)';
            end
            ylabel(rightLabel, 'FontSize', 11, 'FontWeight', 'bold');
            ax = gca; ax.YColor = [0, 0, 0];
            if currentLimMax > currentLimMin
                ylim([currentLimMin, currentLimMax]);
            end

            %% FORMATTING
            xlabel('Voltage (mV)', 'FontSize', 11, 'FontWeight', 'bold');
            xlim([min(voltages) - 5, max(voltages) + 5]);
            title(sprintf('%s: %s (R²=%.3f)', category, char(wellID), r2), ...
                'FontSize', 12, 'FontWeight', 'bold');
            grid on;
            ax = gca; ax.GridAlpha = 0.15; ax.Box = 'on'; ax.LineWidth = 1.2;
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

            % Dynamic IV lookup — supports any number of IVs (iv1..ivN)
            if isfield(well, ivName) && ~isempty(well.(ivName)) && isfield(well.(ivName), 'fitParams')
                ivFit = well.(ivName);
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
