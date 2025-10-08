classdef NanionBoltzmannPlotter < handle
    %NANIONBOLTZMANNPLOTTER Visualization for Boltzmann fitting results
    %   Creates publication-quality plots of I-V curves and parameter distributions
    
    properties (Access = private)
        config
        logger
        colorMap
    end
    
    methods
        function obj = NanionBoltzmannPlotter(config, logger)
            %NANIONBOLTZMANNPLOTTER Constructor
            
            obj.config = config;
            obj.logger = logger;
            
            % Define quality color scheme
            obj.colorMap = struct(...
                'Good', [0.2, 0.7, 0.3], ...       % Green
                'Acceptable', [0.2, 0.4, 0.8], ... % Blue
                'Poor', [0.9, 0.5, 0.2], ...       % Orange
                'Failed', [0.8, 0.2, 0.2]);        % Red
        end
        
        function plotAllResults(obj, fittedData, outputDir, fileName)
            %PLOTALLRESULTS Generate all visualization plots
            
            obj.logger.logInfo('Generating Boltzmann fit visualizations...');
            
            if ~exist(outputDir, 'dir')
                mkdir(outputDir);
            end
            
            % 1. Individual I-V curves with fits (multi-panel)
            obj.plotIVCurvesGrid(fittedData, outputDir, fileName);
            
            % 2. Parameter distributions
            obj.plotParameterDistributions(fittedData, outputDir, fileName);
            
            % 3. Fit quality summary
            obj.plotFitQualitySummary(fittedData, outputDir, fileName);
            
            % 4. V_mid vs R² scatter plot
            obj.plotVmidVsR2(fittedData, outputDir, fileName);
            
            obj.logger.logInfo(sprintf('✓ Plots saved to: %s', outputDir));
        end
        
        function plotIVCurvesGrid(obj, fittedData, outputDir, fileName)
            %PLOTIVCURVESGRID Plot I-V curves in grid layout
            
            wells = fittedData.wells;
            numWells = length(wells);
            
            % Grid layout
            rowsPerFig = obj.config.plotting.rowsPerFigure;
            colsPerFig = obj.config.plotting.colsPerFigure;
            wellsPerFig = rowsPerFig * colsPerFig;
            numFigures = ceil(numWells / wellsPerFig);
            
            obj.logger.logInfo(sprintf('Plotting %d wells in %d figures (%dx%d grid)', ...
                numWells, numFigures, rowsPerFig, colsPerFig));
            
            for figIdx = 1:numFigures
                fig = figure('Position', [100, 100, obj.config.plotting.figureSize]);
                fig.Color = 'white';
                
                startIdx = (figIdx - 1) * wellsPerFig + 1;
                endIdx = min(figIdx * wellsPerFig, numWells);
                
                for wellIdx = startIdx:endIdx
                    subplot(rowsPerFig, colsPerFig, wellIdx - startIdx + 1);
                    obj.plotSingleIVCurve(wells(wellIdx));
                end
                
                % Save figure
                sgtitle(sprintf('%s - Boltzmann Fits (Page %d/%d)', ...
                    fileName, figIdx, numFigures), ...
                    'Interpreter', 'none', 'FontSize', 14, 'FontWeight', 'bold');
                
                figName = fullfile(outputDir, sprintf('%s_IVcurves_page%d.png', fileName, figIdx));
                saveas(fig, figName);
                close(fig);
                
                obj.logger.logInfo(sprintf('Saved I-V curves page %d/%d', figIdx, numFigures));
            end
        end
        
        function plotSingleIVCurve(obj, well)
            %PLOTSINGLEIVCURVE Plot single well I-V or G-V curve with fit
            
            V = well.voltages;
            D = well.data;  % Conductance (nS) or Current (pA)
            validIdx = ~isnan(D);
            
            % Plot data points
            hold on;
            plot(V(validIdx), D(validIdx), 'o', ...
                'Color', obj.colorMap.(well.fitQuality), ...
                'MarkerSize', obj.config.plotting.markerSize, ...
                'MarkerFaceColor', obj.colorMap.(well.fitQuality));
            
            % Plot fit line if converged
            if well.fitParams.converged
                V_fit = linspace(min(V), max(V), 100);
                
                if strcmp(well.protocol, 'activation')
                    D_fit = BoltzmannModel.activation(V_fit, ...
                        well.fitParams.V_min, well.fitParams.V_max, ...
                        well.fitParams.V_mid, well.fitParams.k);
                else
                    D_fit = BoltzmannModel.inactivation(V_fit, ...
                        well.fitParams.V_min, well.fitParams.V_max, ...
                        well.fitParams.V_mid, well.fitParams.k);
                end
                
                plot(V_fit, D_fit, '-', ...
                    'Color', obj.colorMap.(well.fitQuality), ...
                    'LineWidth', obj.config.plotting.lineWidth);
            end
            
            hold off;
            
            % Formatting
            xlabel('Voltage (mV)', 'FontSize', obj.config.plotting.fontSizeAxis);
            
            % Y-axis label depends on data type
            if strcmp(well.dataType, 'conductance')
                ylabel('Conductance (nS)', 'FontSize', obj.config.plotting.fontSizeAxis);
            else
                ylabel('Current (pA)', 'FontSize', obj.config.plotting.fontSizeAxis);
            end
            
            % Title with key parameters
            if well.fitParams.converged
                titleStr = sprintf('%s: V½=%.1f mV, R²=%.3f', ...
                    well.wellID, well.fitParams.V_mid, well.fitParams.R2);
            else
                titleStr = sprintf('%s: Failed', well.wellID);
            end
            title(titleStr, 'FontSize', obj.config.plotting.fontSizeTitle, ...
                'Interpreter', 'none');
            
            grid on;
            box on;
        end
        
        function plotParameterDistributions(obj, fittedData, outputDir, fileName)
            %PLOTPARAMETERDISTRIBUTIONS Plot histograms of fit parameters
            
            wells = fittedData.wells;
            
            % Extract parameters for Good + Acceptable fits only
            goodOrAcceptable = strcmp({wells.fitQuality}, 'Good') | ...
                              strcmp({wells.fitQuality}, 'Acceptable');
            
            if sum(goodOrAcceptable) == 0
                obj.logger.logWarning('No Good/Acceptable fits to plot distributions');
                return;
            end
            
            V_mids = arrayfun(@(x) x.fitParams.V_mid, wells(goodOrAcceptable));
            ks = arrayfun(@(x) x.fitParams.k, wells(goodOrAcceptable));
            R2s = arrayfun(@(x) x.fitParams.R2, wells(goodOrAcceptable));
            
            fig = figure('Position', [100, 100, 1400, 500]);
            fig.Color = 'white';
            
            % V_mid distribution
            subplot(1, 3, 1);
            histogram(V_mids, 15, 'FaceColor', [0.3, 0.6, 0.8], 'EdgeColor', 'black');
            xlabel('V_{1/2} (mV)', 'FontSize', 12);
            ylabel('Count', 'FontSize', 12);
            title(sprintf('V_{1/2} Distribution\nMean: %.2f ± %.2f mV', ...
                mean(V_mids), std(V_mids)), 'FontSize', 12);
            grid on;
            
            % k distribution
            subplot(1, 3, 2);
            histogram(ks, 15, 'FaceColor', [0.8, 0.5, 0.3], 'EdgeColor', 'black');
            xlabel('Slope Factor k (mV)', 'FontSize', 12);
            ylabel('Count', 'FontSize', 12);
            title(sprintf('Slope Factor Distribution\nMean: %.2f ± %.2f mV', ...
                mean(ks), std(ks)), 'FontSize', 12);
            grid on;
            
            % R² distribution
            subplot(1, 3, 3);
            histogram(R2s, 15, 'FaceColor', [0.3, 0.8, 0.5], 'EdgeColor', 'black');
            xlabel('R²', 'FontSize', 12);
            ylabel('Count', 'FontSize', 12);
            title(sprintf('R² Distribution\nMean: %.4f', mean(R2s)), 'FontSize', 12);
            xlim([0.7, 1.0]);
            grid on;
            
            sgtitle(sprintf('%s - Parameter Distributions (Good + Acceptable Fits)', fileName), ...
                'Interpreter', 'none', 'FontSize', 14, 'FontWeight', 'bold');
            
            % Save
            figName = fullfile(outputDir, sprintf('%s_parameter_distributions.png', fileName));
            saveas(fig, figName);
            close(fig);
            
            obj.logger.logInfo('Saved parameter distribution plots');
        end
        
        function plotFitQualitySummary(obj, fittedData, outputDir, fileName)
            %PLOTFITQUALITYSUMMARY Pie chart of fit quality categories
            
            summary = fittedData.summary;
            
            categories = {'Good', 'Acceptable', 'Poor', 'Failed'};
            counts = [summary.fitResults.good, summary.fitResults.acceptable, ...
                     summary.fitResults.poor, summary.fitResults.failed];
            
            % Remove zero categories
            nonzero = counts > 0;
            categories = categories(nonzero);
            counts = counts(nonzero);
            
            if isempty(counts)
                obj.logger.logWarning('No fit results to plot');
                return;
            end
            
            fig = figure('Position', [100, 100, 800, 600]);
            fig.Color = 'white';
            
            % Create pie chart
            colors = zeros(length(categories), 3);
            for i = 1:length(categories)
                colors(i, :) = obj.colorMap.(categories{i});
            end
            
            pie(counts, categories);
            colormap(colors);
            
            title(sprintf('%s - Fit Quality Summary\nTotal: %d wells', ...
                fileName, sum(counts)), ...
                'Interpreter', 'none', 'FontSize', 14, 'FontWeight', 'bold');
            
            % Add text summary
            annotation('textbox', [0.15, 0.05, 0.7, 0.1], ...
                'String', sprintf('Good: %d (%.1f%%) | Acceptable: %d (%.1f%%) | Poor: %d (%.1f%%) | Failed: %d (%.1f%%)', ...
                    summary.fitResults.good, 100*summary.fitResults.good/sum(counts), ...
                    summary.fitResults.acceptable, 100*summary.fitResults.acceptable/sum(counts), ...
                    summary.fitResults.poor, 100*summary.fitResults.poor/sum(counts), ...
                    summary.fitResults.failed, 100*summary.fitResults.failed/sum(counts)), ...
                'EdgeColor', 'none', 'FontSize', 11, 'HorizontalAlignment', 'center');
            
            % Save
            figName = fullfile(outputDir, sprintf('%s_fit_quality_summary.png', fileName));
            saveas(fig, figName);
            close(fig);
            
            obj.logger.logInfo('Saved fit quality summary plot');
        end
        
        function plotVmidVsR2(obj, fittedData, outputDir, fileName)
            %PLOTVMIDVSR2 Scatter plot of V_mid vs R² colored by quality
            
            wells = fittedData.wells;
            converged = arrayfun(@(x) x.fitParams.converged, wells);
            
            if sum(converged) == 0
                obj.logger.logWarning('No converged fits to plot');
                return;
            end
            
            fig = figure('Position', [100, 100, 800, 600]);
            fig.Color = 'white';
            
            hold on;
            
            % Plot by quality category
            qualities = {'Good', 'Acceptable', 'Poor'};
            for q = 1:length(qualities)
                quality = qualities{q};
                mask = converged & strcmp({wells.fitQuality}, quality);
                
                if sum(mask) > 0
                    V_mids = arrayfun(@(x) x.fitParams.V_mid, wells(mask));
                    R2s = arrayfun(@(x) x.fitParams.R2, wells(mask));
                    
                    scatter(V_mids, R2s, 100, ...
                        'MarkerFaceColor', obj.colorMap.(quality), ...
                        'MarkerEdgeColor', 'black', ...
                        'LineWidth', 1.0, ...
                        'DisplayName', quality);
                end
            end
            
            hold off;
            
            xlabel('V_{1/2} (mV)', 'FontSize', 12);
            ylabel('R²', 'FontSize', 12);
            title(sprintf('%s - V_{1/2} vs Fit Quality', fileName), ...
                'Interpreter', 'none', 'FontSize', 14, 'FontWeight', 'bold');
            
            legend('Location', 'best', 'FontSize', 11);
            grid on;
            box on;
            
            % Add threshold lines
            yline(obj.config.boltzmann.corrThreshold, '--k', 'Good', ...
                'LineWidth', 1.5, 'LabelHorizontalAlignment', 'left');
            yline(obj.config.boltzmann.acceptableThreshold, '--k', 'Acceptable', ...
                'LineWidth', 1.5, 'LabelHorizontalAlignment', 'left');
            
            % Save
            figName = fullfile(outputDir, sprintf('%s_vmid_vs_r2.png', fileName));
            saveas(fig, figName);
            close(fig);
            
            obj.logger.logInfo('Saved V_mid vs R² scatter plot');
        end
    end
end
