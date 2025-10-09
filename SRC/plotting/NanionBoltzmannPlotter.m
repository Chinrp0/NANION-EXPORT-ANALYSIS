classdef NanionBoltzmannPlotter < handle
    %NANIONBOLTZMANNPLOTTER Dual y-axis plotting for activation protocols
    %   Left axis: Conductance (nS)
    %   Right axis: Peak Current (pA)
    %   Plots IV1 and IV2 with Boltzmann fits
    
    properties (Access = private)
        config
        logger
        colors
    end
    
    methods
        function obj = NanionBoltzmannPlotter(config, logger)
            %NANIONBOLTZMANNPLOTTER Constructor
            obj.config = config;
            obj.logger = logger;
            
            % Define color scheme (consistent per IV)
            obj.colors = struct(...
                'iv1', [0.00, 0.45, 0.74], ...  % Blue
                'iv2', [0.85, 0.33, 0.10]);     % Orange/Red
        end
        
        function plotActivationDualAxis(obj, wellID, voltages, iv1Data, iv2Data, iv1Fit, iv2Fit)
            %PLOTACTIVATIONDUALAXIS Dual y-axis plot for activation protocols
            %   Left axis: Conductance with Boltzmann fits
            %   Right axis: Peak Current
            %   Plots both IV1 and IV2 with connected lines
            
            figure('Name', sprintf('Well %s - Activation', wellID), ...
                   'Position', [100, 100, 900, 600]);
            
            % Marker and line settings
            markerSize = 4;
            lineWidth = 1.5;
            fitLineWidth = 2.0;
            
            %% LEFT Y-AXIS: Conductance (nS)
            yyaxis left
            hold on;
            
            % IV1 Conductance data (circles, filled)
            plot(voltages, iv1Data.conductance, '-o', ...
                'Color', obj.colors.iv1, ...
                'MarkerSize', markerSize, ...
                'MarkerFaceColor', obj.colors.iv1, ...
                'LineWidth', lineWidth, ...
                'DisplayName', 'IV1 Conductance');
            
            % IV1 Boltzmann fit
            if ~isempty(iv1Fit) && isfield(iv1Fit, 'fittedCurve')
                plot(voltages, iv1Fit.fittedCurve, '--', ...
                    'Color', obj.colors.iv1, ...
                    'LineWidth', fitLineWidth, ...
                    'DisplayName', sprintf('IV1 Fit (V_{1/2}=%.1f, k=%.1f)', ...
                        iv1Fit.params.V_mid, iv1Fit.params.k));
            end
            
            % IV2 Conductance data (circles, filled)
            if ~isempty(iv2Data)
                plot(voltages, iv2Data.conductance, '-o', ...
                    'Color', obj.colors.iv2, ...
                    'MarkerSize', markerSize, ...
                    'MarkerFaceColor', obj.colors.iv2, ...
                    'LineWidth', lineWidth, ...
                    'DisplayName', 'IV2 Conductance');
                
                % IV2 Boltzmann fit
                if ~isempty(iv2Fit) && isfield(iv2Fit, 'fittedCurve')
                    plot(voltages, iv2Fit.fittedCurve, '--', ...
                        'Color', obj.colors.iv2, ...
                        'LineWidth', fitLineWidth, ...
                        'DisplayName', sprintf('IV2 Fit (V_{1/2}=%.1f, k=%.1f)', ...
                            iv2Fit.params.V_mid, iv2Fit.params.k));
                end
            end
            
            ylabel('Conductance (nS)', 'FontSize', 12, 'FontWeight', 'bold');
            ax = gca;
            ax.YColor = [0, 0, 0];  % Black for left axis
            ylim_left = ylim;
            ylim([0, ylim_left(2) * 1.1]);  % Start at 0, add 10% headroom
            
            %% RIGHT Y-AXIS: Peak Current (pA)
            yyaxis right
            hold on;
            
            % IV1 Peak Current (squares, hollow)
            plot(voltages, iv1Data.peakCurrent, '-s', ...
                'Color', obj.colors.iv1, ...
                'MarkerSize', markerSize, ...
                'MarkerFaceColor', 'none', ...
                'LineWidth', lineWidth, ...
                'DisplayName', 'IV1 Current');
            
            % IV2 Peak Current (squares, hollow)
            if ~isempty(iv2Data)
                plot(voltages, iv2Data.peakCurrent, '-s', ...
                    'Color', obj.colors.iv2, ...
                    'MarkerSize', markerSize, ...
                    'MarkerFaceColor', 'none', ...
                    'LineWidth', lineWidth, ...
                    'DisplayName', 'IV2 Current');
            end
            
            ylabel('Peak Current (pA)', 'FontSize', 12, 'FontWeight', 'bold');
            ax = gca;
            ax.YColor = [0, 0, 0];  % Black for right axis
            
            % Set y-limits to show negative current clearly
            ylim_right = ylim;
            ylim([ylim_right(1) * 1.1, 0]);  % Extend negative, cap at 0
            
            %% X-AXIS and FORMATTING
            xlabel('Voltage (mV)', 'FontSize', 12, 'FontWeight', 'bold');
            xlim([min(voltages) - 5, max(voltages) + 5]);
            
            % Title with fit quality
            if ~isempty(iv1Fit)
                titleStr = sprintf('Well %s: Activation Protocol (IV1: R^2=%.3f)', ...
                    wellID, iv1Fit.quality.rsquared);
            else
                titleStr = sprintf('Well %s: Activation Protocol', wellID);
            end
            title(titleStr, 'FontSize', 14, 'FontWeight', 'bold');
            
            % Grid and legend
            grid on;
            legend('Location', 'best', 'FontSize', 9);
            
            hold off;
            
            obj.logger.logInfo(sprintf('Plotted dual-axis activation for well %s', wellID));
        end
        
        function plotInactivationDualPanel(obj, wellID, voltages, iv1Data, iv2Data, iv1Fit, iv2Fit)
            %PLOTINACTIVATIONDUALPANEL Two-panel plot for inactivation protocols
            %   Top panel: Normalized inactivation with Boltzmann fits
            %   Bottom panel: Test pulse current (activationData field)
            
            figure('Name', sprintf('Well %s - Inactivation', wellID), ...
                   'Position', [100, 100, 900, 700]);
            
            markerSize = 4;
            lineWidth = 1.5;
            fitLineWidth = 2.0;
            
            %% TOP PANEL: Normalized Inactivation
            subplot(2, 1, 1);
            hold on;
            
            % IV1 Normalized Inactivation (circles, filled)
            iv1_norm = iv1Data.inactivationData / min(iv1Data.inactivationData);
            plot(voltages, iv1_norm, '-o', ...
                'Color', obj.colors.iv1, ...
                'MarkerSize', markerSize, ...
                'MarkerFaceColor', obj.colors.iv1, ...
                'LineWidth', lineWidth, ...
                'DisplayName', 'IV1 Inactivation');
            
            % IV1 Fit
            if ~isempty(iv1Fit) && isfield(iv1Fit, 'fittedCurve')
                plot(voltages, iv1Fit.fittedCurve, '--', ...
                    'Color', obj.colors.iv1, ...
                    'LineWidth', fitLineWidth, ...
                    'DisplayName', sprintf('IV1 Fit (V_{1/2}=%.1f, k=%.1f)', ...
                        iv1Fit.params.V_mid, iv1Fit.params.k));
            end
            
            % IV2 Normalized Inactivation (circles, filled)
            if ~isempty(iv2Data)
                iv2_norm = iv2Data.inactivationData / min(iv2Data.inactivationData);
                plot(voltages, iv2_norm, '-o', ...
                    'Color', obj.colors.iv2, ...
                    'MarkerSize', markerSize, ...
                    'MarkerFaceColor', obj.colors.iv2, ...
                    'LineWidth', lineWidth, ...
                    'DisplayName', 'IV2 Inactivation');
                
                % IV2 Fit
                if ~isempty(iv2Fit) && isfield(iv2Fit, 'fittedCurve')
                    plot(voltages, iv2Fit.fittedCurve, '--', ...
                        'Color', obj.colors.iv2, ...
                        'LineWidth', fitLineWidth, ...
                        'DisplayName', sprintf('IV2 Fit (V_{1/2}=%.1f, k=%.1f)', ...
                            iv2Fit.params.V_mid, iv2Fit.params.k));
                end
            end
            
            ylabel('Normalized Inactivation (0-1)', 'FontSize', 12, 'FontWeight', 'bold');
            xlabel('Conditioning Voltage (mV)', 'FontSize', 12, 'FontWeight', 'bold');
            title(sprintf('Well %s: Inactivation Protocol', wellID), ...
                'FontSize', 14, 'FontWeight', 'bold');
            grid on;
            legend('Location', 'best', 'FontSize', 9);
            ylim([0, 1.1]);
            xlim([min(voltages) - 5, max(voltages) + 5]);
            hold off;
            
            %% BOTTOM PANEL: Test Pulse Current
            subplot(2, 1, 2);
            hold on;
            
            % IV1 Test Pulse Current (circles, filled)
            plot(voltages, iv1Data.activationData, '-o', ...
                'Color', obj.colors.iv1, ...
                'MarkerSize', markerSize, ...
                'MarkerFaceColor', obj.colors.iv1, ...
                'LineWidth', lineWidth, ...
                'DisplayName', 'IV1 Test Current');
            
            % IV2 Test Pulse Current (circles, filled)
            if ~isempty(iv2Data)
                plot(voltages, iv2Data.activationData, '-o', ...
                    'Color', obj.colors.iv2, ...
                    'MarkerSize', markerSize, ...
                    'MarkerFaceColor', obj.colors.iv2, ...
                    'LineWidth', lineWidth, ...
                    'DisplayName', 'IV2 Test Current');
            end
            
            ylabel('Test Pulse Current (pA)', 'FontSize', 12, 'FontWeight', 'bold');
            xlabel('Conditioning Voltage (mV)', 'FontSize', 12, 'FontWeight', 'bold');
            title('Test Pulse Current vs Conditioning Voltage', 'FontSize', 12);
            grid on;
            legend('Location', 'best', 'FontSize', 9);
            xlim([min(voltages) - 5, max(voltages) + 5]);
            hold off;
            
            obj.logger.logInfo(sprintf('Plotted dual-panel inactivation for well %s', wellID));
        end
        
        function plotBatch(obj, wellIDs, voltages, measurements, fitResults, protocolType)
            %PLOTBATCH Generate plots for multiple wells
            %   Creates individual plots for each well
            
            numWells = length(wellIDs);
            obj.logger.logInfo(sprintf('Generating %d plots for %s protocol...', ...
                numWells, protocolType));
            
            for i = 1:numWells
                wellID = wellIDs(i);
                
                % Extract data for this well
                iv1Data = obj.extractWellData(measurements.iv1, i);
                
                if isfield(measurements, 'iv2')
                    iv2Data = obj.extractWellData(measurements.iv2, i);
                else
                    iv2Data = [];
                end
                
                % Extract fit results
                iv1Fit = [];
                iv2Fit = [];
                if ~isempty(fitResults)
                    if i <= length(fitResults)
                        if isfield(fitResults(i), 'iv1')
                            iv1Fit = fitResults(i).iv1;
                        end
                        if isfield(fitResults(i), 'iv2')
                            iv2Fit = fitResults(i).iv2;
                        end
                    end
                end
                
                % Generate appropriate plot
                if strcmp(protocolType, 'activation')
                    obj.plotActivationDualAxis(wellID, voltages, iv1Data, iv2Data, iv1Fit, iv2Fit);
                elseif strcmp(protocolType, 'inactivation')
                    obj.plotInactivationDualPanel(wellID, voltages, iv1Data, iv2Data, iv1Fit, iv2Fit);
                end
            end
            
            obj.logger.logInfo(sprintf('✓ Generated %d plots', numWells));
        end
    end
    
    methods (Access = private)
        function wellData = extractWellData(obj, ivData, wellIndex)
            %EXTRACTWELLDATA Extract single well's data from IV measurements
            
            fields = fieldnames(ivData);
            wellData = struct();
            
            for i = 1:length(fields)
                fieldName = fields{i};
                % Extract row for this well (handle both 1D and 2D arrays)
                if size(ivData.(fieldName), 1) >= wellIndex
                    wellData.(fieldName) = ivData.(fieldName)(wellIndex, :);
                end
            end
        end
    end
end
