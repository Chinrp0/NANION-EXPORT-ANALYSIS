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
            
            % Define color scheme
            obj.colors = struct(...
                'iv1', [0.0, 0.0, 0.0], ...           % Black (conductance)
                'iv1_current', [0.5, 0.5, 0.5], ...   % Gray (current)
                'iv2', [0.0, 0.45, 0.74], ...         % Blue (conductance)
                'iv2_current', [0.4, 0.7, 1.0]);      % Light blue (current)
        end
        
        function plotActivationDualAxis(obj, wellID, voltages, iv1Data, iv2Data, iv1Fit, iv2Fit)
            %PLOTACTIVATIONDUALAXIS Dual y-axis plot for activation protocols
            %   Left axis: Conductance with Boltzmann fits
            %   Right axis: Peak Current
            %   Plots both IV1 and IV2 with connected lines
            
            figure('Name', sprintf('Well %s - Activation', wellID), ...
                   'Position', [100, 100, 1000, 650], ...
                   'Color', 'white');
            
            % Marker and line settings
            markerSize = 5;           % Smaller markers
            lineWidth = 1.8;          % Slightly thicker lines
            fitLineWidth = 2.5;       % Thicker fit lines
            markerAlpha = 0.85;       % Slight transparency for overlapping points
            
            %% LEFT Y-AXIS: Conductance (nS)
            yyaxis left
            hold on;
            
            % IV1 Conductance data (circles, filled, black)
            h1_cond = plot(voltages, iv1Data.conductance, '-o', ...
                'Color', obj.colors.iv1, ...
                'MarkerSize', markerSize, ...
                'MarkerFaceColor', obj.colors.iv1, ...
                'LineWidth', lineWidth, ...
                'DisplayName', 'IV1 Conductance');
            h1_cond.Color(4) = markerAlpha;  % Set transparency
            
            % IV1 Boltzmann fit
            if ~isempty(iv1Fit) && isfield(iv1Fit, 'fittedCurve')
                plot(voltages, iv1Fit.fittedCurve, '--', ...
                    'Color', obj.colors.iv1, ...
                    'LineWidth', fitLineWidth, ...
                    'DisplayName', sprintf('IV1 Fit (V_{1/2}=%.1f, k=%.1f)', ...
                        iv1Fit.fitParams.V_mid, iv1Fit.fitParams.k));
            end
            
            % IV2 Conductance data (circles, filled, blue)
            if ~isempty(iv2Data)
                h2_cond = plot(voltages, iv2Data.conductance, '-o', ...
                    'Color', obj.colors.iv2, ...
                    'MarkerSize', markerSize, ...
                    'MarkerFaceColor', obj.colors.iv2, ...
                    'LineWidth', lineWidth, ...
                    'DisplayName', 'IV2 Conductance');
                h2_cond.Color(4) = markerAlpha;  % Set transparency
                
                % IV2 Boltzmann fit
                if ~isempty(iv2Fit) && isfield(iv2Fit, 'fittedCurve')
                    plot(voltages, iv2Fit.fittedCurve, '--', ...
                        'Color', obj.colors.iv2, ...
                        'LineWidth', fitLineWidth, ...
                        'DisplayName', sprintf('IV2 Fit (V_{1/2}=%.1f, k=%.1f)', ...
                            iv2Fit.fitParams.V_mid, iv2Fit.fitParams.k));
                end
            end
            
            ylabel('Normalized Conductance (0-1)', 'FontSize', 12, 'FontWeight', 'bold');
            ax = gca;
            ax.YColor = [0, 0, 0];  % Black for left axis
            ylim_left = ylim;
            ylim([0, ylim_left(2) * 1.1]);  % Start at 0, add 10% headroom
            
            %% RIGHT Y-AXIS: Peak Current (pA)
            yyaxis right
            hold on;
            
            % IV1 Peak Current (gray squares, hollow)
            h1_current = plot(voltages, iv1Data.peakCurrent, '-s', ...
                'Color', obj.colors.iv1_current, ...
                'MarkerSize', markerSize, ...
                'MarkerFaceColor', 'none', ...
                'LineWidth', lineWidth, ...
                'DisplayName', 'IV1 Current');
            h1_current.Color(4) = markerAlpha;  % Set transparency
            
            % IV2 Peak Current (light blue squares, hollow)
            if ~isempty(iv2Data)
                h2_current = plot(voltages, iv2Data.peakCurrent, '-s', ...
                    'Color', obj.colors.iv2_current, ...
                    'MarkerSize', markerSize, ...
                    'MarkerFaceColor', 'none', ...
                    'LineWidth', lineWidth, ...
                    'DisplayName', 'IV2 Current');
                h2_current.Color(4) = markerAlpha;  % Set transparency
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
            
            % Title with fit quality (indicate normalized conductance)
            if ~isempty(iv1Fit)
                titleStr = sprintf('Well %s: Activation Protocol (IV1: R^2=%.3f)', ...
                    wellID, iv1Fit.fitParams.R2);
            else
                titleStr = sprintf('Well %s: Activation Protocol', wellID);
            end
            title(titleStr, 'FontSize', 14, 'FontWeight', 'bold');
            
            % Grid and legend
            grid on;
            ax = gca;
            ax.GridAlpha = 0.15;  % Subtle grid
            ax.GridLineStyle = '-';
            ax.MinorGridAlpha = 0.05;
            ax.Box = 'on';
            ax.LineWidth = 1.2;
            
            legend('Location', 'west', 'FontSize', 9, 'Box', 'off', ...
                'NumColumns', 1);  % Single column, top-left position
            
            hold off;
            
            obj.logger.logInfo(sprintf('Plotted dual-axis activation for well %s', wellID));
        end
        
        function plotInactivationDualAxis(obj, wellID, voltages, iv1Data, iv2Data, iv1Fit, iv2Fit)
            %PLOTINACTIVATIONDUALAXIS Single plot with dual y-axis for inactivation
            %   Left axis: Normalized inactivation (0-1) with Boltzmann fits
            %   Right axis: Test pulse current (pA)
            
            figure('Name', sprintf('Well %s - Inactivation', wellID), ...
                   'Position', [100, 100, 1000, 650], ...
                   'Color', 'white');
            
            markerSize = 5;
            lineWidth = 1.8;
            fitLineWidth = 2.5;
            markerAlpha = 0.85;
            
            %% LEFT Y-AXIS: Normalized Inactivation
            yyaxis left
            hold on;
            
            % IV1 Normalized Inactivation (black circles, filled)
            iv1_norm = iv1Data.inactivationData / min(iv1Data.inactivationData);
            h1_inact = plot(voltages, iv1_norm, '-o', ...
                'Color', obj.colors.iv1, ...
                'MarkerSize', markerSize, ...
                'MarkerFaceColor', obj.colors.iv1, ...
                'LineWidth', lineWidth, ...
                'DisplayName', 'IV1 Inactivation');
            h1_inact.Color(4) = markerAlpha;
            
            % IV1 Boltzmann Fit
            if ~isempty(iv1Fit) && isfield(iv1Fit, 'fittedCurve')
                plot(voltages, iv1Fit.fittedCurve, '--', ...
                    'Color', obj.colors.iv1, ...
                    'LineWidth', fitLineWidth, ...
                    'DisplayName', sprintf('IV1 Fit (V_{1/2}=%.1f, k=%.1f)', ...
                        iv1Fit.fitParams.V_mid, iv1Fit.fitParams.k));
            end
            
            % IV2 Normalized Inactivation (blue circles, filled)
            if ~isempty(iv2Data)
                iv2_norm = iv2Data.inactivationData / min(iv2Data.inactivationData);
                h2_inact = plot(voltages, iv2_norm, '-o', ...
                    'Color', obj.colors.iv2, ...
                    'MarkerSize', markerSize, ...
                    'MarkerFaceColor', obj.colors.iv2, ...
                    'LineWidth', lineWidth, ...
                    'DisplayName', 'IV2 Inactivation');
                h2_inact.Color(4) = markerAlpha;
                
                % IV2 Boltzmann Fit
                if ~isempty(iv2Fit) && isfield(iv2Fit, 'fittedCurve')
                    plot(voltages, iv2Fit.fittedCurve, '--', ...
                        'Color', obj.colors.iv2, ...
                        'LineWidth', fitLineWidth, ...
                        'DisplayName', sprintf('IV2 Fit (V_{1/2}=%.1f, k=%.1f)', ...
                            iv2Fit.fitParams.V_mid, iv2Fit.fitParams.k));
                end
            end
            
            ylabel('Normalized Inactivation (0-1)', 'FontSize', 12, 'FontWeight', 'bold');
            ax = gca;
            ax.YColor = [0, 0, 0];
            ylim([0, 1.1]);
            
            %% RIGHT Y-AXIS: Test Pulse Current
            yyaxis right
            hold on;
            
            % IV1 Test Current (gray squares, hollow)
            h1_test = plot(voltages, iv1Data.activationData, '-s', ...
                'Color', obj.colors.iv1_current, ...
                'MarkerSize', markerSize, ...
                'MarkerFaceColor', 'none', ...
                'LineWidth', lineWidth, ...
                'DisplayName', 'IV1 Test Current');
            h1_test.Color(4) = markerAlpha;
            
            % IV2 Test Current (light blue squares, hollow)
            if ~isempty(iv2Data)
                h2_test = plot(voltages, iv2Data.activationData, '-s', ...
                    'Color', obj.colors.iv2_current, ...
                    'MarkerSize', markerSize, ...
                    'MarkerFaceColor', 'none', ...
                    'LineWidth', lineWidth, ...
                    'DisplayName', 'IV2 Test Current');
                h2_test.Color(4) = markerAlpha;
            end
            
            ylabel('Test Pulse Current (pA)', 'FontSize', 12, 'FontWeight', 'bold');
            ax = gca;
            ax.YColor = [0, 0, 0];
            
            % Auto-scale right axis appropriately
            ylim_right = ylim;
            if ylim_right(1) < 0
                ylim([ylim_right(1) * 1.1, max(ylim_right(2), 100)]);
            end
            
            %% X-AXIS and FORMATTING
            xlabel('Conditioning Voltage (mV)', 'FontSize', 12, 'FontWeight', 'bold');
            xlim([min(voltages) - 5, max(voltages) + 5]);
            
            % Title
            titleStr = sprintf('Well %s: Inactivation Protocol', wellID);
            if ~isempty(iv1Fit)
                titleStr = sprintf('%s (IV1: R^2=%.3f)', titleStr, iv1Fit.fitParams.R2);
            end
            title(titleStr, 'FontSize', 14, 'FontWeight', 'bold');
            
            % Grid and legend
            grid on;
            ax = gca;
            ax.GridAlpha = 0.15;
            ax.GridLineStyle = '-';
            ax.Box = 'on';
            ax.LineWidth = 1.2;
            
            legend('Location', 'west', 'FontSize', 9, 'Box', 'off', 'NumColumns', 1);  % Single column, top-right position

            hold off;
            
            obj.logger.logInfo(sprintf('Plotted dual-axis inactivation for well %s', wellID));
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
