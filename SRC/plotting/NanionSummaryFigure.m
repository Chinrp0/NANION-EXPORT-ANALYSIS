classdef NanionSummaryFigure < handle
    %NANIONSUMMARYFIGURE Generate publication-quality summary figures
    %   Figure 1: Best/Worst representative wells (dual y-axis format)
    %   Figure 2: Cell type averages grouped by compound
    
    properties (Access = private)
        config
        logger
        plotter  % NanionBoltzmannPlotter instance
        compoundColors
        concentrationStyles
    end
    
    methods
        function obj = NanionSummaryFigure(config, logger)
            obj.config = config;
            obj.logger = logger;
            
            % Initialize plotter for representative wells
            obj.plotter = NanionBoltzmannPlotter(config, logger);
            
            % Define compound color palette (colorblind-friendly)
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
            
            % Define concentration line styles
            obj.concentrationStyles = {'-', '--', ':', '-.'};
        end
        
        function [fig1, fig2] = createSummaryFigures(obj, filteredData, fittedData, summaryTable, outputPath, includePoorFits)
            %CREATESUMMARYFIGURES Generate both representative and average figures
            %   Inputs:
            %     filteredData, fittedData, summaryTable - analysis results
            %     outputPath - where to save figures (optional)
            %     includePoorFits - quality filter for Figure 2 (default: 0)
            %       0 or false = Good + Acceptable only (strict)
            %       1 or true  = Good + Acceptable + Poor (permissive)
            %       2          = All fits including Failed (inspection mode)
            %   Returns:
            %     fig1 - Representative wells figure (always Good/Acceptable only)
            %     fig2 - Cell type averages figure (compound-grouped)
            
            if nargin < 6
                includePoorFits = 0;
            end
            
            obj.logger.logInfo('Creating summary figures...');
            
            % Figure 1: Representative Wells (always use Good/Acceptable only)
            fig1 = obj.createRepresentativeWellsFigure(filteredData, fittedData, summaryTable);
            
            if nargin >= 5 && ~isempty(outputPath)
                obj.saveFigure(fig1, outputPath, 'fig1_representative_wells');
            end
            
            % Figure 2: Cell Type Averages (Compound-Grouped)
            fig2 = obj.createCellTypeAveragesFigure(filteredData, fittedData, summaryTable, includePoorFits);
            
            if nargin >= 5 && ~isempty(outputPath)
                obj.saveFigure(fig2, outputPath, 'fig2_cell_type_averages');
            end
            
            % Export compound group statistics
            if nargin >= 5 && ~isempty(outputPath)
                obj.exportCompoundGroupStats(summaryTable, outputPath, includePoorFits);
            end
            
            obj.logger.logInfo('✓ Summary figures created');
        end
        
        function figHandle = createRepresentativeWellsFigure(obj, filteredData, fittedData, summaryTable)
            %CREATEREPRESENTATIVEWELLSFIGURE Best and worst passing fits
            %   Uses NanionBoltzmannPlotter dual-axis format
            
            obj.logger.logInfo('Creating representative wells figure...');
            
            protocolType = filteredData.protocolInfo.type;
            voltages = filteredData.protocolInfo.voltages;
            
            % Select wells for best/worst fits
            [bestWells, worstWells] = obj.selectRepresentativeWells(summaryTable);
            
            numBest = min(3, height(bestWells));
            numWorst = min(3, height(worstWells));
            
            % Create figure (2 rows × 3 columns)
            figHandle = figure('Position', [100, 100, 1500, 900], ...
                'Color', 'w', 'Name', 'Representative Wells');
            
            % Row 1: Best fits
            obj.logger.logInfo(sprintf('Plotting %d best fits...', numBest));
            for i = 1:numBest
                subplot(2, 3, i);
                obj.plotRepresentativeWell(filteredData, fittedData, bestWells(i, :), ...
                    voltages, protocolType, 'Best');
            end
            
            % Row 2: Worst passing fits
            obj.logger.logInfo(sprintf('Plotting %d worst passing fits...', numWorst));
            for i = 1:numWorst
                subplot(2, 3, 3 + i);
                obj.plotRepresentativeWell(filteredData, fittedData, worstWells(i, :), ...
                    voltages, protocolType, 'Acceptable');
            end
            
            % Add overall title
            sgtitle(sprintf('%s Protocol: Representative Wells', protocolType), ...
                'FontSize', 16, 'FontWeight', 'bold');
            
            obj.logger.logInfo('✓ Representative wells figure created');
        end
        
        function figHandle = createCellTypeAveragesFigure(obj, filteredData, fittedData, summaryTable, includePoorFits)
            %CREATECELLTYPEAVERAGESFIGURE Compound-grouped averages
            %   One subplot per Cell_Type + Compound combination
            %   Multiple concentrations shown with different line styles
            
            if nargin < 5
                includePoorFits = false;
            end
            
            obj.logger.logInfo('Creating cell type averages figure...');
            
            protocolType = filteredData.protocolInfo.type;
            voltages = filteredData.protocolInfo.voltages;
            
            % Get unique Cell_Type + Compound combinations (filter by quality)
            if includePoorFits == 2  % Special mode: include even Failed fits
                obj.logger.logWarning('Including ALL fits (Good/Acceptable/Poor/Failed) in averages');
                passingMask = true(height(summaryTable), 1);  % Include everything
            elseif includePoorFits == 1 || includePoorFits == true
                obj.logger.logInfo('Including Poor quality fits in averages');
                passingMask = strcmp(summaryTable.Fit_Quality, 'Good') | ...
                              strcmp(summaryTable.Fit_Quality, 'Acceptable') | ...
                              strcmp(summaryTable.Fit_Quality, 'Poor');
            else
                passingMask = strcmp(summaryTable.Fit_Quality, 'Good') | ...
                              strcmp(summaryTable.Fit_Quality, 'Acceptable');
            end
            
            passingTable = summaryTable(passingMask, :);
            
            if height(passingTable) == 0
                obj.logger.logWarning('No passing fits for cell type averages');
                figHandle = [];
                return;
            end
            
            % Group by Cell_Type + Compound
            [groupKeys, ~, groupIdx] = unique(passingTable(:, {'Cell_Type', 'Compound'}), 'rows');
            numGroups = height(groupKeys);
            
            obj.logger.logInfo(sprintf('Found %d Cell_Type × Compound groups', numGroups));
            
            % Calculate dynamic grid layout (reserve 1 spot for legend)
            [nRows, nCols] = obj.calculateGridLayout(numGroups + 1);
            
            % Create figure
            figWidth = 500 * nCols;
            figHeight = 400 * nRows;
            figHandle = figure('Position', [50, 50, figWidth, figHeight], ...
                'Color', 'w', 'Name', 'Cell Type Averages');
            
            % Assign colors to compounds
            uniqueCompounds = unique(groupKeys.Compound);
            compoundColorMap = obj.assignCompoundColors(uniqueCompounds);
            
            % Storage for legend entries
            legendHandles = [];
            legendLabels = {};
            
            % Plot each group
            for g = 1:numGroups
                subplot(nRows, nCols, g);
                
                cellType = groupKeys.Cell_Type{g};
                compound = groupKeys.Compound{g};
                
                % Get all rows for this Cell_Type + Compound
                groupMask = (groupIdx == g);
                groupTable = passingTable(groupMask, :);
                
                % Plot this group
                [handles, labels] = obj.plotCompoundGroup(filteredData, fittedData, ...
                    groupTable, cellType, compound, voltages, protocolType, compoundColorMap);
                
                % Collect legend entries (only from first group to avoid duplicates)
                if g == 1 || isempty(legendHandles)
                    legendHandles = [legendHandles; handles];
                    legendLabels = [legendLabels; labels];
                end
            end
            
            % Create shared legend in last subplot
            subplot(nRows, nCols, numGroups + 1);
            obj.createSharedLegend(legendHandles, legendLabels);
            
            % Add overall title
            sgtitle(sprintf('%s Protocol: Cell Type Averages by Compound', protocolType), ...
                'FontSize', 16, 'FontWeight', 'bold');
            
            obj.logger.logInfo(sprintf('✓ Cell type averages figure created (%d groups)', numGroups));
        end
    end
    
    methods (Access = private)
        %% REPRESENTATIVE WELLS METHODS
        
        function [bestWells, worstWells] = selectRepresentativeWells(obj, summaryTable)
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
                worstWells = sortedTable;
            end
            
            obj.logger.logDebug(sprintf('Selected %d best, %d worst passing wells', ...
                height(bestWells), height(worstWells)));
        end
        
        function plotRepresentativeWell(obj, filteredData, fittedData, wellRow, ...
                voltages, protocolType, category)
            %PLOTREPRESENTATIVEWELL Plot using NanionBoltzmannPlotter format
            %   Dual y-axis: Conductance (left) + Current (right)
            %   Shows ALL available IVs (iv1, iv2, iv3, iv4)
            
            % Extract well info
            wellID = wellRow.Well_ID{1};
            r2 = wellRow.R_squared(1);
            
            % Find well index
            wellIdx = find(strcmp(filteredData.wellIDs, wellID), 1);
            
            if isempty(wellIdx)
                text(0.5, 0.5, 'Well not found', 'HorizontalAlignment', 'center');
                return;
            end
            
            % Determine which IVs are available
            ivNames = fieldnames(filteredData.measurements);
            numIVs = length(ivNames);
            
            % Extract data and fits for all IVs
            ivDataArray = {};
            ivFitArray = {};
            
            for i = 1:numIVs
                ivName = ivNames{i};
                ivDataArray{i} = obj.extractWellData(filteredData.measurements.(ivName), wellIdx);
                ivFit = obj.extractFitParams(fittedData, wellIdx, ivName);
                
                % Format fit struct
                if ~isempty(ivFit) && ivFit.converged
                    ivFitStruct.fitParams = ivFit;
                    % Generate normalized Boltzmann curve (0-1 scale)
                    ivFitStruct.fittedCurve = 1 ./ (1 + exp((ivFit.V_mid - voltages) / ivFit.k));
                    ivFitArray{i} = ivFitStruct;
                else
                    ivFitArray{i} = [];
                end
            end
            
            % Plot using dual-axis format with all IVs
            obj.plotDualAxisFormatMultiIV(wellID, voltages, ivDataArray, ivFitArray, ...
                ivNames, category, r2, protocolType);
        end
        
        function plotDualAxisFormatMultiIV(obj, wellID, voltages, ivDataArray, ivFitArray, ...
                ivNames, category, r2, protocolType)
            %PLOTDUALAXISFORMATMULTIIV Replicate NanionBoltzmannPlotter style for multiple IVs
            %   Left axis: Conductance, Right axis: Current
            %   Handles iv1, iv2, iv3, iv4 dynamically
            
            markerSize = 5;
            lineWidth = 1.8;
            fitLineWidth = 2.5;
            markerAlpha = 0.85;
            
            % Extended color scheme for up to 4 IVs
            ivColors = [
                0.0, 0.0, 0.0;           % IV1: Black
                0.0, 0.45, 0.74;         % IV2: Blue
                0.85, 0.33, 0.10;        % IV3: Red-orange
                0.49, 0.18, 0.56;        % IV4: Purple
            ];
            
            ivCurrentColors = [
                0.5, 0.5, 0.5;           % IV1 current: Gray
                0.4, 0.7, 1.0;           % IV2 current: Light blue
                1.0, 0.6, 0.4;           % IV3 current: Light orange
                0.7, 0.5, 0.8;           % IV4 current: Light purple
            ];
            
            numIVs = length(ivDataArray);
            
            %% LEFT Y-AXIS: Normalized Conductance (0-1)
            yyaxis left
            hold on;
            
            for i = 1:numIVs
                ivData = ivDataArray{i};
                ivFit = ivFitArray{i};
                
                if isempty(ivData) || ~isfield(ivData, 'conductance')
                    continue;
                end
                
                % Get color for this IV
                color_idx = min(i, size(ivColors, 1));
                condColor = ivColors(color_idx, :);
                
                % Plot conductance data
                h_cond = plot(voltages, ivData.conductance, '-o', ...
                    'Color', condColor, ...
                    'MarkerSize', markerSize, ...
                    'MarkerFaceColor', condColor, ...
                    'LineWidth', lineWidth, ...
                    'DisplayName', sprintf('%s Conductance', upper(ivNames{i})));
                h_cond.Color(4) = markerAlpha;
                
                % Plot fit
                if ~isempty(ivFit) && isfield(ivFit, 'fittedCurve')
                    fitColor = condColor;
                    fitColor(4) = 0.7;
                    plot(voltages, ivFit.fittedCurve, ':', ...
                        'Color', fitColor, ...
                        'LineWidth', fitLineWidth, ...
                        'DisplayName', sprintf('%s Fit (V_{1/2}=%.1f)', ...
                            upper(ivNames{i}), ivFit.fitParams.V_mid));
                end
            end
            
            ylabel('Normalized Conductance (G/G_{max})', 'FontSize', 11, 'FontWeight', 'bold');
            ax = gca;
            ax.YColor = [0, 0, 0];
            ylim([0, 1.1]);
            
            %% RIGHT Y-AXIS: Peak Current (pA)
            yyaxis right
            hold on;
            
            for i = 1:numIVs
                ivData = ivDataArray{i};
                
                if isempty(ivData) || ~isfield(ivData, 'peakCurrent')
                    continue;
                end
                
                % Get color for this IV
                color_idx = min(i, size(ivCurrentColors, 1));
                currentColor = ivCurrentColors(color_idx, :);
                
                % Plot current data
                h_current = plot(voltages, ivData.peakCurrent, '-s', ...
                    'Color', currentColor, ...
                    'MarkerSize', markerSize, ...
                    'MarkerFaceColor', 'none', ...
                    'LineWidth', lineWidth, ...
                    'DisplayName', sprintf('%s Current', upper(ivNames{i})));
                h_current.Color(4) = markerAlpha;
            end
            
            ylabel('Peak Current (pA)', 'FontSize', 11, 'FontWeight', 'bold');
            ax = gca;
            ax.YColor = [0, 0, 0];
            
            ylim_right = ylim;
            ylim([ylim_right(1) * 1.1, 0]);
            
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
            
            legend('Location', 'northwest', 'FontSize', 7, 'Box', 'off', 'NumColumns', 1);
            
            hold off;
        end
        
        %% CELL TYPE AVERAGES METHODS
        
        function [handles, labels] = plotCompoundGroup(obj, filteredData, fittedData, ...
                groupTable, cellType, compound, voltages, protocolType, compoundColorMap)
            %PLOTCOMPOUNDGROUP Plot one Cell_Type + Compound combination
            %   Plots IV2 and IV3 with different markers/styles
            %   Returns legend handles and labels for shared legend
            
            % Filter for IV2 and IV3 only
            iv2Mask = (groupTable.IV_Number == 2);
            iv3Mask = (groupTable.IV_Number == 3);
            
            iv2Table = groupTable(iv2Mask, :);
            iv3Table = groupTable(iv3Mask, :);
            
            % Get unique concentrations across both IVs
            allConcs = unique([iv2Table.Concentration_uM; iv3Table.Concentration_uM]);
            numConcs = length(allConcs);
            
            % Get compound color
            compoundColor = compoundColorMap(compound);
            
            % Storage for legend
            handles = [];
            labels = {};
            
            hold on;
            
            % IV markers: circle for IV2, square for IV3
            iv2Marker = 'o';
            iv3Marker = 's';
            
            % Plot each concentration for IV2
            for c = 1:numConcs
                conc = allConcs(c);
                concMaskIV2 = (iv2Table.Concentration_uM == conc);
                concTableIV2 = iv2Table(concMaskIV2, :);
                
                if height(concTableIV2) == 0
                    continue;
                end
                
                % Get line style for this concentration
                lineStyle = obj.getConcentrationLineStyle(c);
                
                % Plot individual wells (thin, transparent)
                for w = 1:height(concTableIV2)
                    wellID = concTableIV2.Well_ID{w};
                    
                    wellIdx = find(strcmp(filteredData.wellIDs, wellID), 1);
                    if isempty(wellIdx)
                        continue;
                    end
                    
                    measurements = filteredData.measurements.iv2;
                    
                    % Get normalized data
                    if strcmp(protocolType, 'activation')
                        yData = measurements.conductance(wellIdx, :);
                    else
                        yData = measurements.inactivationData(wellIdx, :);
                        yData = (yData - min(yData)) / (max(yData) - min(yData));
                    end
                    
                    % Plot thin transparent line
                    plot(voltages, yData, lineStyle, ...
                        'Color', [compoundColor, 0.15], ...
                        'LineWidth', 0.5, ...
                        'HandleVisibility', 'off');
                end
                
                % Calculate group average for IV2
                V_mid_mean = mean(concTableIV2.V_mid_mV, 'omitnan');
                k_mean = mean(concTableIV2.Slope_k_mV, 'omitnan');
                V_mid_SEM = std(concTableIV2.V_mid_mV, 'omitnan') / sqrt(height(concTableIV2));
                
                % Plot average Boltzmann curve (thick) with circle marker
                V_fit = linspace(min(voltages), max(voltages), 100);
                G_mean = 1 ./ (1 + exp((V_mid_mean - V_fit) / k_mean));
                
                h = plot(V_fit, G_mean, [lineStyle iv2Marker], ...
                    'Color', compoundColor, ...
                    'LineWidth', 2.5, ...
                    'MarkerSize', 6, ...
                    'MarkerFaceColor', compoundColor, ...
                    'MarkerIndices', 1:10:length(V_fit), ...
                    'DisplayName', sprintf('%s %.1fμM IV2 (n=%d)', ...
                        obj.formatCompoundName(compound), conc, height(concTableIV2)));
                
                % Store for legend and stats
                handles = [handles; h];
                labels = [labels; {sprintf('%s %.1fμM IV2 (n=%d)', ...
                    obj.formatCompoundName(compound), conc, height(concTableIV2))}];
                
                concStatsIV2(c).conc = conc;
                concStatsIV2(c).n = height(concTableIV2);
                concStatsIV2(c).V_mid = V_mid_mean;
                concStatsIV2(c).V_mid_SEM = V_mid_SEM;
                concStatsIV2(c).iv = 'IV2';
            end
            
            % Plot each concentration for IV3
            for c = 1:numConcs
                conc = allConcs(c);
                concMaskIV3 = (iv3Table.Concentration_uM == conc);
                concTableIV3 = iv3Table(concMaskIV3, :);
                
                if height(concTableIV3) == 0
                    continue;
                end
                
                % Get line style for this concentration
                lineStyle = obj.getConcentrationLineStyle(c);
                
                % Plot individual wells (thin, transparent)
                for w = 1:height(concTableIV3)
                    wellID = concTableIV3.Well_ID{w};
                    
                    wellIdx = find(strcmp(filteredData.wellIDs, wellID), 1);
                    if isempty(wellIdx)
                        continue;
                    end
                    
                    measurements = filteredData.measurements.iv3;
                    
                    % Get normalized data
                    if strcmp(protocolType, 'activation')
                        yData = measurements.conductance(wellIdx, :);
                    else
                        yData = measurements.inactivationData(wellIdx, :);
                        yData = (yData - min(yData)) / (max(yData) - min(yData));
                    end
                    
                    % Plot thin transparent line
                    plot(voltages, yData, lineStyle, ...
                        'Color', [compoundColor, 0.15], ...
                        'LineWidth', 0.5, ...
                        'HandleVisibility', 'off');
                end
                
                % Calculate group average for IV3
                V_mid_mean = mean(concTableIV3.V_mid_mV, 'omitnan');
                k_mean = mean(concTableIV3.Slope_k_mV, 'omitnan');
                V_mid_SEM = std(concTableIV3.V_mid_mV, 'omitnan') / sqrt(height(concTableIV3));
                
                % Plot average Boltzmann curve (thick) with square marker
                V_fit = linspace(min(voltages), max(voltages), 100);
                G_mean = 1 ./ (1 + exp((V_mid_mean - V_fit) / k_mean));
                
                h = plot(V_fit, G_mean, [lineStyle iv3Marker], ...
                    'Color', compoundColor, ...
                    'LineWidth', 2.5, ...
                    'MarkerSize', 6, ...
                    'MarkerFaceColor', compoundColor, ...
                    'MarkerIndices', 1:10:length(V_fit), ...
                    'DisplayName', sprintf('%s %.1fμM IV3 (n=%d)', ...
                        obj.formatCompoundName(compound), conc, height(concTableIV3)));
                
                % Store for legend and stats
                handles = [handles; h];
                labels = [labels; {sprintf('%s %.1fμM IV3 (n=%d)', ...
                    obj.formatCompoundName(compound), conc, height(concTableIV3))}];
                
                concStatsIV3(c).conc = conc;
                concStatsIV3(c).n = height(concTableIV3);
                concStatsIV3(c).V_mid = V_mid_mean;
                concStatsIV3(c).V_mid_SEM = V_mid_SEM;
                concStatsIV3(c).iv = 'IV3';
            end
            
            hold off;
            
            % Formatting
            xlabel('Voltage (mV)', 'FontSize', 10);
            if strcmp(protocolType, 'activation')
                ylabel('Norm. Conductance (G/G_{max})', 'FontSize', 10);
            else
                ylabel('Norm. Inactivation', 'FontSize', 10);
            end
            
            title(sprintf('%s: %s', char(cellType), obj.formatCompoundName(compound)), ...
                'FontSize', 11, 'FontWeight', 'bold');
            
            grid on;
            box on;
            ylim([0 1.1]);
            xlim([min(voltages) - 5, max(voltages) + 5]);
            
            ax = gca;
            ax.GridAlpha = 0.15;
            ax.LineWidth = 1.0;
            
            % Add stats box for both IV2 and IV3
            if exist('concStatsIV2', 'var') || exist('concStatsIV3', 'var')
                allStats = [];
                if exist('concStatsIV2', 'var')
                    allStats = [allStats, concStatsIV2];
                end
                if exist('concStatsIV3', 'var')
                    allStats = [allStats, concStatsIV3];
                end
                obj.addStatsBoxMultiIV(allStats, cellType, compound);
            end
        end
        
        function addStatsBoxMultiIV(obj, concStats, cellType, compound)
            %ADDSTATSBOXMULTIIV Add statistics text box to subplot for IV2 and IV3
            
            % Build stats text
            statsText = sprintf('%s: %s\n', char(cellType), obj.formatCompoundName(compound));
            
            % Group by concentration, show IV2 and IV3 together
            uniqueConcs = unique([concStats.conc]);
            
            for c = 1:length(uniqueConcs)
                conc = uniqueConcs(c);
                
                % Find IV2 stats for this concentration
                iv2Idx = find([concStats.conc] == conc & strcmp({concStats.iv}, 'IV2'), 1);
                % Find IV3 stats for this concentration
                iv3Idx = find([concStats.conc] == conc & strcmp({concStats.iv}, 'IV3'), 1);
                
                statsText = sprintf('%s\n%.1fμM:', statsText, conc);
                
                if ~isempty(iv2Idx)
                    statsText = sprintf('%s\n  IV2 (n=%d): V½=%.1f±%.1f', statsText, ...
                        concStats(iv2Idx).n, concStats(iv2Idx).V_mid, concStats(iv2Idx).V_mid_SEM);
                end
                
                if ~isempty(iv3Idx)
                    statsText = sprintf('%s\n  IV3 (n=%d): V½=%.1f±%.1f', statsText, ...
                        concStats(iv3Idx).n, concStats(iv3Idx).V_mid, concStats(iv3Idx).V_mid_SEM);
                end
            end
            
            % Add text box
            text(0.05, 0.95, statsText, 'Units', 'normalized', ...
                'VerticalAlignment', 'top', 'FontSize', 7, ...
                'BackgroundColor', 'w', 'EdgeColor', 'k', ...
                'Margin', 5);
        end
        
        function addStatsBox(obj, concStats, cellType, compound)
            %ADDSTATSBOX Add statistics text box to subplot (legacy, single IV)
            
            % Build stats text
            statsText = sprintf('%s: %s\n', char(cellType), obj.formatCompoundName(compound));
            
            for c = 1:length(concStats)
                statsText = sprintf('%s\n%.1fμM (n=%d):', statsText, ...
                    concStats(c).conc, concStats(c).n);
                statsText = sprintf('%s\n  V½ = %.1f ± %.1f mV', statsText, ...
                    concStats(c).V_mid, concStats(c).V_mid_SEM);
            end
            
            % Add text box
            text(0.05, 0.95, statsText, 'Units', 'normalized', ...
                'VerticalAlignment', 'top', 'FontSize', 8, ...
                'BackgroundColor', 'w', 'EdgeColor', 'k', ...
                'Margin', 5);
        end
        
        function createSharedLegend(obj, handles, labels)
            %CREATESHAREDLEGEND Create dedicated legend subplot
            
            % Turn off axes
            axis off;
            
            % Create legend in center of subplot
            legend(handles, labels, ...
                'Location', 'center', ...
                'FontSize', 9, ...
                'Box', 'on', ...
                'NumColumns', 1);
            
            title('Legend', 'FontSize', 11, 'FontWeight', 'bold', 'Visible', 'on');
        end
        
        %% HELPER METHODS
        
        function [nRows, nCols] = calculateGridLayout(obj, numSubplots)
            %CALCULATEGRIDLAYOUT Calculate optimal grid dimensions
            %   Aims for roughly square layout
            
            nCols = ceil(sqrt(numSubplots));
            nRows = ceil(numSubplots / nCols);
        end
        
        function colorMap = assignCompoundColors(obj, compounds)
            %ASSIGNCOMPOUNDCOLORS Create compound → color mapping
            
            colorMap = containers.Map('KeyType', 'char', 'ValueType', 'any');
            numCompounds = length(compounds);
            
            for i = 1:numCompounds
                compoundName = char(compounds(i));
                colorIdx = mod(i - 1, size(obj.compoundColors, 1)) + 1;
                colorMap(compoundName) = obj.compoundColors(colorIdx, :);
            end
        end
        
        function lineStyle = getConcentrationLineStyle(obj, concIndex)
            %GETCONCENTRATIONLINESTYLE Get line style for concentration
            
            styleIdx = mod(concIndex - 1, length(obj.concentrationStyles)) + 1;
            lineStyle = obj.concentrationStyles{styleIdx};
        end
        
        function shortName = formatCompoundName(obj, compoundName)
            %FORMATCOMPOUNDNAME Abbreviate common compound names
            
            % Common abbreviations
            abbrevMap = containers.Map(...
                {'Tetrodotoxin', 'tetrodotoxin', 'TTX', ...
                 '4-Aminopyridine', '4-aminopyridine', '4-AP', ...
                 'Tetraethylammonium', 'tetraethylammonium', 'TEA', ...
                 'Control', 'Vehicle', 'DMSO'}, ...
                {'TTX', 'TTX', 'TTX', ...
                 '4-AP', '4-AP', '4-AP', ...
                 'TEA', 'TEA', 'TEA', ...
                 'Control', 'Vehicle', 'DMSO'});
            
            compoundStr = char(compoundName);
            
            if isKey(abbrevMap, compoundStr)
                shortName = abbrevMap(compoundStr);
            else
                % Truncate long names
                if length(compoundStr) > 15
                    shortName = [compoundStr(1:12), '...'];
                else
                    shortName = compoundStr;
                end
            end
        end
        
        function wellData = extractWellData(obj, ivData, wellIndex)
            %EXTRACTWELLDATA Extract single well's data from IV measurements
            
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
        
        function exportCompoundGroupStats(obj, summaryTable, outputPath, includePoorFits)
            %EXPORTCOMPOUNDGROUPSTATS Export grouped statistics
            
            if nargin < 4
                includePoorFits = false;
            end
            
            obj.logger.logInfo('Exporting compound group statistics...');
            
            % Filter by quality
            if includePoorFits == 2  % Include all, even Failed
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
            
            % Group by Cell_Type + Compound + Concentration
            [groupKeys, ~, groupIdx] = unique(...
                passingTable(:, {'Cell_Type', 'Compound', 'Concentration_uM'}), 'rows');
            
            numGroups = height(groupKeys);
            
            % Initialize stats table
            statsTable = table();
            
            for g = 1:numGroups
                groupMask = (groupIdx == g);
                groupData = passingTable(groupMask, :);
                
                % Calculate statistics
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
            
            % Sort by Cell_Type, Compound, Concentration
            statsTable = sortrows(statsTable, {'Cell_Type', 'Compound', 'Concentration_uM'});
            
            % Print to console
            fprintf('\n=== COMPOUND GROUP STATISTICS ===\n');
            disp(statsTable);
            
            % Export to Excel
            excelFile = fullfile(outputPath, 'summary_table.xlsx');
            
            try
                writetable(statsTable, excelFile, 'Sheet', 'Compound_Group_Stats');
                obj.logger.logInfo(sprintf('✓ Saved compound group stats to: %s', excelFile));
            catch ME
                obj.logger.logWarning(sprintf('Could not write to Excel: %s', ME.message));
            end
        end
        
        function saveFigure(obj, figHandle, outputPath, baseName)
            %SAVEFIGURE Save figure in multiple formats
            
            if isempty(figHandle)
                return;
            end
            
            % Ensure output directory exists
            if ~exist(outputPath, 'dir')
                mkdir(outputPath);
            end
            
            % Generate filename with timestamp
            timestamp = datestr(now, 'yyyymmdd_HHMMSS');
            fileName = sprintf('%s_%s', baseName, timestamp);
            
            % Save as PNG
            pngFile = fullfile(outputPath, [fileName, '.png']);
            saveas(figHandle, pngFile);
            obj.logger.logInfo(sprintf('✓ Saved PNG: %s', pngFile));
            
            % Save as FIG
            figFile = fullfile(outputPath, [fileName, '.fig']);
            savefig(figHandle, figFile);
            obj.logger.logInfo(sprintf('✓ Saved FIG: %s', figFile));
            
            % Save as PDF (if available)
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
