classdef NanionQCReviewApp < handle
    %NANIONQCREVIEWAPP Interactive QC review UI (programmatic uifigure).
    %   Shows every assessed well colour-coded by its final verdict, plots the
    %   selected well's Boltzmann fits (all IVs) with per-IV V_mid / slope / R2,
    %   and lets the user override the automatic decision with Keep / Reject /
    %   Reset-to-auto. Decisions are written straight into a QCReviewSession so
    %   the calling pipeline reads them back through session.keepMaskFor(...).
    %
    %   Usage (blocking mode):
    %     app = NanionQCReviewApp(config, logger, session, assessedData, fittedData);
    %     app.waitForCompletion();            % blocks until the user clicks Done
    %     keepMask = session.keepMaskFor(assessedData);
    %
    %   The public *Current / selectWellByIndex methods are also the callback
    %   bodies, so a headless test can drive the app without mouse events.

    properties (Access = public)
        fig                 % uifigure handle
    end

    properties (Access = private)
        config
        logger
        session             % QCReviewSession (decisions live here)
        assessedData        % all wells: verdicts, measurements, protocolInfo
        fittedData          % all wells (aligned 1:1 with assessedData well order)

        wellKeys            % string [nWells x 1], global order
        wellIDs             % string [nWells x 1]
        ivNames             % cellstr of IV field names
        voltages            % numeric row/col of test voltages
        protocolType        % 'activation' | 'inactivation'

        % UI widgets
        tbl                 % uitable well navigator
        ax                  % uiaxes plot
        infoArea            % uitextarea with verdict/metrics/fit details
        statusLbl           % uilabel status/summary
        filterDD            % uidropdown well filter
        ivBlankPanel        % uipanel holding per-IV blank checkboxes
        ivBlankBoxes        % array of uicheckbox handles

        rowToWell           % vector: current table row -> global well index
        selectedWell        % global well index currently shown
        blankedIVs          % containers.Map: wellKey -> logical vector over ivNames

        ivColors            % palette for IV traces
        finished            % logical, set true when Done/closed
    end

    methods
        function obj = NanionQCReviewApp(config, logger, session, assessedData, fittedData)
            obj.config = config;
            obj.logger = logger;
            obj.session = session;
            obj.assessedData = assessedData;
            obj.fittedData = fittedData;
            obj.finished = false;

            V = assessedData.verdicts;
            obj.wellKeys = arrayfun(@(v) string(v.wellKey), V(:));
            obj.wellIDs  = arrayfun(@(v) string(v.wellID),  V(:));
            obj.ivNames  = fieldnames(assessedData.measurements);
            obj.voltages = assessedData.protocolInfo.voltages;
            obj.protocolType = assessedData.protocolInfo.type;
            obj.blankedIVs = containers.Map('KeyType', 'char', 'ValueType', 'any');

            obj.ivColors = [
                0.00 0.00 0.00; 0.00 0.45 0.74; 0.85 0.33 0.10; 0.49 0.18 0.56;
                0.47 0.67 0.19; 0.30 0.75 0.93; 0.64 0.08 0.18; 0.50 0.50 0.50];

            obj.buildUI();
            obj.refreshTable();
            if ~isempty(obj.rowToWell)
                obj.selectWellByIndex(obj.rowToWell(1));
            end
            obj.updateStatus();
        end

        function waitForCompletion(obj)
            %WAITFORCOMPLETION Block until the user finishes the review.
            if isempty(obj.fig) || ~isvalid(obj.fig)
                return;
            end
            uiwait(obj.fig);
        end

        % ----- callback bodies (also the public/testable API) -----

        function selectWellByIndex(obj, wellIdx)
            %SELECTWELLBYINDEX Show a well by its GLOBAL index (1..nWells).
            if wellIdx < 1 || wellIdx > numel(obj.wellKeys)
                return;
            end
            obj.selectedWell = wellIdx;
            obj.buildIVBlankBoxes();
            obj.plotWell();
            obj.updateInfo();
            obj.syncTableSelection();
        end

        function keepCurrent(obj)
            % Keep + advance to the next well so the user can review quickly.
            obj.setCurrentVerdict('keep', true);
        end

        function rejectCurrent(obj)
            obj.setCurrentVerdict('reject', true);
        end

        function resetCurrent(obj)
            % Reset is a correction, not a decision — stay on the well.
            obj.setCurrentVerdict('auto', false);
        end

        function idx = currentWellIndex(obj)
            %CURRENTWELLINDEX Global index of the well currently shown (0 if none).
            if isempty(obj.selectedWell); idx = 0; else; idx = obj.selectedWell; end
        end

        function finish(obj)
            %FINISH End the review and release waitForCompletion.
            obj.finished = true;
            if ~isempty(obj.fig) && isvalid(obj.fig)
                uiresume(obj.fig);
                delete(obj.fig);
            end
        end
    end

    methods (Access = private)
        function buildUI(obj)
            fileName = char(obj.assessedData.fileName);
            obj.fig = uifigure('Name', sprintf('QC Review — %s', fileName), ...
                'Position', [80 80 1220 720]);
            obj.fig.CloseRequestFcn = @(~,~) obj.onClose();

            gl = uigridlayout(obj.fig, [3 2]);
            gl.RowHeight = {30, '1x', 40};
            gl.ColumnWidth = {470, '1x'};

            % --- header row ---
            obj.statusLbl = uilabel(gl, 'Text', '', 'FontWeight', 'bold');
            obj.statusLbl.Layout.Row = 1; obj.statusLbl.Layout.Column = [1 2];

            % --- left column: filter + navigator table ---
            leftGl = uigridlayout(gl, [2 1]);
            leftGl.Layout.Row = 2; leftGl.Layout.Column = 1;
            leftGl.RowHeight = {30, '1x'};
            leftGl.Padding = [0 0 0 0];

            obj.filterDD = uidropdown(leftGl, ...
                'Items', {'All wells', 'Auto-rejected', 'Kept (final)', ...
                          'Rejected (final)', 'Overridden'}, ...
                'Value', 'All wells', ...
                'ValueChangedFcn', @(~,~) obj.refreshTable());
            obj.filterDD.Layout.Row = 1;

            obj.tbl = uitable(leftGl);
            obj.tbl.Layout.Row = 2;
            obj.tbl.ColumnName = {'Well', 'Auto', 'User', 'Final', 'Reject reason'};
            obj.tbl.ColumnWidth = {80, 55, 55, 55, 190};
            obj.tbl.SelectionType = 'row';
            obj.tbl.Multiselect = 'off';
            obj.tbl.CellSelectionCallback = @(src, ev) obj.onTableSelect(ev);

            % --- right column: plot + info + per-IV blank ---
            rightGl = uigridlayout(gl, [2 1]);
            rightGl.Layout.Row = 2; rightGl.Layout.Column = 2;
            rightGl.RowHeight = {'1x', 150};
            rightGl.Padding = [0 0 0 0];

            obj.ax = uiaxes(rightGl);
            obj.ax.Layout.Row = 1;
            title(obj.ax, '');

            infoGl = uigridlayout(rightGl, [1 2]);
            infoGl.Layout.Row = 2;
            infoGl.ColumnWidth = {'1x', 200};
            infoGl.Padding = [0 0 0 0];

            obj.infoArea = uitextarea(infoGl, 'Editable', 'off');
            obj.infoArea.Layout.Column = 1;

            obj.ivBlankPanel = uipanel(infoGl, 'Title', 'Blank IV (exclude)');
            obj.ivBlankPanel.Layout.Column = 2;

            % --- footer row: action buttons ---
            btnGl = uigridlayout(gl, [1 5]);
            btnGl.Layout.Row = 3; btnGl.Layout.Column = [1 2];
            btnGl.Padding = [0 0 0 0];

            uibutton(btnGl, 'Text', 'Keep', ...
                'BackgroundColor', [0.75 0.92 0.75], ...
                'ButtonPushedFcn', @(~,~) obj.keepCurrent());
            uibutton(btnGl, 'Text', 'Reject', ...
                'BackgroundColor', [0.95 0.78 0.78], ...
                'ButtonPushedFcn', @(~,~) obj.rejectCurrent());
            uibutton(btnGl, 'Text', 'Reset to auto', ...
                'ButtonPushedFcn', @(~,~) obj.resetCurrent());
            uilabel(btnGl, 'Text', '');   % spacer
            uibutton(btnGl, 'Text', 'Done', ...
                'BackgroundColor', [0.80 0.86 0.98], ...
                'FontWeight', 'bold', ...
                'ButtonPushedFcn', @(~,~) obj.finish());
        end

        function onClose(obj)
            % Closing the window is treated as "Done".
            obj.finish();
        end

        function onTableSelect(obj, ev)
            if isempty(ev.Indices); return; end
            row = ev.Indices(1);
            if row >= 1 && row <= numel(obj.rowToWell)
                obj.selectWellByIndex(obj.rowToWell(row));
            end
        end

        function idx = filteredWellIndices(obj)
            %FILTEREDWELLINDICES Global well indices matching the filter dropdown.
            n = numel(obj.wellKeys);
            switch obj.filterDD.Value
                case 'All wells'
                    idx = (1:n)';
                case 'Auto-rejected'
                    auto = arrayfun(@(v) ~v.autoPass, obj.assessedData.verdicts(:));
                    idx = find(auto);
                case 'Kept (final)'
                    idx = find(obj.finalKeepFlags());
                case 'Rejected (final)'
                    idx = find(~obj.finalKeepFlags());
                case 'Overridden'
                    idx = find(obj.overriddenFlags());
                otherwise
                    idx = (1:n)';
            end
        end

        function flags = finalKeepFlags(obj)
            flags = obj.session.keepMaskFor(obj.assessedData);
        end

        function flags = overriddenFlags(obj)
            n = numel(obj.wellKeys);
            flags = false(n, 1);
            for i = 1:n
                d = obj.session.getDecision(obj.wellKeys(i));
                flags(i) = ~isempty(d) && ismember(d.userVerdict, {'keep', 'reject'});
            end
        end

        function refreshTable(obj)
            %REFRESHTABLE Rebuild navigator rows for the current filter + recolour.
            obj.rowToWell = obj.filteredWellIndices();
            nRows = numel(obj.rowToWell);
            data = cell(nRows, 5);
            keepFlags = obj.finalKeepFlags();
            for r = 1:nRows
                gi = obj.rowToWell(r);
                d = obj.session.getDecision(obj.wellKeys(gi));
                if isempty(d)
                    autoV = char(obj.assessedData.verdicts(gi).autoVerdict);
                    userV = '';
                    if obj.assessedData.verdicts(gi).autoPass; finalV = 'keep'; else; finalV = 'reject'; end
                else
                    autoV = d.autoVerdict; userV = d.userVerdict; finalV = d.finalVerdict;
                end
                reasons = obj.assessedData.verdicts(gi).reasons;
                if isempty(reasons)
                    reasonStr = '';
                else
                    reasonStr = strjoin(cellstr(reasons), ', ');
                end
                data{r, 1} = char(obj.wellIDs(gi));
                data{r, 2} = autoV;
                data{r, 3} = userV;
                data{r, 4} = finalV;
                data{r, 5} = reasonStr;
            end
            obj.tbl.Data = data;
            obj.applyRowColors(keepFlags);
            obj.syncTableSelection();
        end

        function applyRowColors(obj, keepFlags)
            %APPLYROWCOLORS Green = kept, red = rejected, blue tint = overridden.
            removeStyle(obj.tbl);
            over = obj.overriddenFlags();
            keepRows = []; rejRows = []; ovRows = [];
            for r = 1:numel(obj.rowToWell)
                gi = obj.rowToWell(r);
                if keepFlags(gi); keepRows(end+1) = r; else; rejRows(end+1) = r; end %#ok<AGROW>
                if over(gi); ovRows(end+1) = r; end %#ok<AGROW>
            end
            if ~isempty(keepRows)
                addStyle(obj.tbl, uistyle('BackgroundColor', [0.82 0.93 0.82]), 'row', keepRows);
            end
            if ~isempty(rejRows)
                addStyle(obj.tbl, uistyle('BackgroundColor', [0.96 0.82 0.82]), 'row', rejRows);
            end
            if ~isempty(ovRows)
                % Mark overrides with a bold blue font so they stand out over the
                % keep/reject background.
                addStyle(obj.tbl, uistyle('FontColor', [0.10 0.20 0.70], ...
                    'FontWeight', 'bold'), 'row', ovRows);
            end
        end

        function syncTableSelection(obj)
            if isempty(obj.selectedWell) || isempty(obj.rowToWell); return; end
            row = find(obj.rowToWell == obj.selectedWell, 1);
            if ~isempty(row)
                try obj.tbl.Selection = row; catch; end
            end
        end

        function setCurrentVerdict(obj, verdict, advance)
            %SETCURRENTVERDICT Record a verdict for the selected well.
            %   advance=true moves to the next navigator row afterwards.
            if nargin < 3; advance = false; end
            if isempty(obj.selectedWell); return; end
            actedWell = obj.selectedWell;
            prevRow = find(obj.rowToWell == actedWell, 1);
            obj.session.setUserVerdict(obj.wellKeys(actedWell), verdict);
            obj.refreshTable();
            obj.updateStatus();
            if advance
                obj.advanceSelection(actedWell, prevRow);
            else
                obj.updateInfo();
            end
        end

        function advanceSelection(obj, actedWell, prevRow)
            %ADVANCESELECTION Select the next well in the current filter view.
            %   If the acted well stayed in the filter, move to the row after it;
            %   if the override pushed it out of the filter, the next well now sits
            %   at the acted well's old row position.
            if isempty(obj.rowToWell); return; end
            stillRow = find(obj.rowToWell == actedWell, 1);
            if ~isempty(stillRow)
                nextRow = stillRow + 1;
            elseif ~isempty(prevRow)
                nextRow = prevRow;
            else
                nextRow = 1;
            end
            nextRow = min(max(nextRow, 1), numel(obj.rowToWell));
            obj.selectWellByIndex(obj.rowToWell(nextRow));
        end

        function buildIVBlankBoxes(obj)
            %BUILDIVBLANKBOXES One checkbox per IV; reflects this well's blank set.
            delete(obj.ivBlankPanel.Children);
            n = numel(obj.ivNames);
            obj.ivBlankBoxes = gobjects(n, 1);
            key = char(obj.wellKeys(obj.selectedWell));
            if isKey(obj.blankedIVs, key)
                blanked = obj.blankedIVs(key);
            else
                blanked = false(n, 1);
            end
            boxGl = uigridlayout(obj.ivBlankPanel, [n 1]);
            boxGl.RowHeight = repmat({20}, 1, n);
            boxGl.Padding = [4 4 4 4];
            boxGl.RowSpacing = 2;
            for i = 1:n
                obj.ivBlankBoxes(i) = uicheckbox(boxGl, ...
                    'Text', upper(obj.ivNames{i}), ...
                    'Value', blanked(i), ...
                    'ValueChangedFcn', @(~,~) obj.onBlankToggle());
            end
        end

        function onBlankToggle(obj)
            n = numel(obj.ivNames);
            blanked = false(n, 1);
            for i = 1:n
                blanked(i) = obj.ivBlankBoxes(i).Value;
            end
            obj.blankedIVs(char(obj.wellKeys(obj.selectedWell))) = blanked;
            obj.plotWell();
        end

        function blanked = currentBlanked(obj)
            key = char(obj.wellKeys(obj.selectedWell));
            if isKey(obj.blankedIVs, key)
                blanked = obj.blankedIVs(key);
            else
                blanked = false(numel(obj.ivNames), 1);
            end
        end

        function plotWell(obj)
            %PLOTWELL Draw the selected well: normalized data + Boltzmann fit
            %   (left axis) and raw current (right axis), for every non-blanked IV.
            cla(obj.ax, 'reset');
            wi = obj.selectedWell;
            well = obj.fittedData.wells(wi);
            V = obj.voltages(:);
            blanked = obj.currentBlanked();

            yyaxis(obj.ax, 'left');
            hold(obj.ax, 'on');
            legendEntries = {};
            legendHandles = [];
            for i = 1:numel(obj.ivNames)
                if blanked(i); continue; end
                ivName = obj.ivNames{i};
                col = obj.ivColors(min(i, size(obj.ivColors, 1)), :);
                if ~isfield(well, ivName) || isempty(well.(ivName)); continue; end
                wf = well.(ivName);
                if isfield(wf, 'data') && any(~isnan(wf.data))
                    h = plot(obj.ax, V, wf.data(:), 'o', 'Color', col, ...
                        'MarkerFaceColor', col, 'MarkerSize', 5);
                    legendHandles(end+1) = h; %#ok<AGROW>
                    legendEntries{end+1} = sprintf('%s data', upper(ivName)); %#ok<AGROW>
                end
                if isfield(wf, 'fittedCurve') && ~isempty(wf.fittedCurve)
                    vmid = NaN;
                    if isfield(wf, 'fitParams') && isfield(wf.fitParams, 'V_mid')
                        vmid = wf.fitParams.V_mid;
                    end
                    h = plot(obj.ax, V, wf.fittedCurve(:), '-', 'Color', col, 'LineWidth', 2);
                    legendHandles(end+1) = h; %#ok<AGROW>
                    legendEntries{end+1} = sprintf('%s fit (V_{1/2}=%.1f)', upper(ivName), vmid); %#ok<AGROW>
                end
            end
            if strcmp(obj.protocolType, 'activation')
                ylabel(obj.ax, 'Normalized Conductance (G/G_{max})');
            else
                ylabel(obj.ax, 'Normalized Inactivation (I/I_{max})');
            end
            ylim(obj.ax, [-0.1 1.2]);

            % right axis: raw current
            yyaxis(obj.ax, 'right');
            for i = 1:numel(obj.ivNames)
                if blanked(i); continue; end
                ivName = obj.ivNames{i};
                cur = obj.rawCurrentFor(ivName, wi);
                if isempty(cur); continue; end
                col = obj.ivColors(min(i, size(obj.ivColors, 1)), :) * 0.55 + 0.45;
                plot(obj.ax, V, cur(:), '-s', 'Color', col, 'MarkerSize', 4);
            end
            if strcmp(obj.protocolType, 'activation')
                ylabel(obj.ax, 'Peak Current (pA)');
            else
                ylabel(obj.ax, 'Test-pulse Current (pA)');
            end

            yyaxis(obj.ax, 'left');
            hold(obj.ax, 'off');
            xlabel(obj.ax, 'Voltage (mV)');
            grid(obj.ax, 'on');
            v = obj.assessedData.verdicts(wi);
            title(obj.ax, sprintf('%s  (auto: %s)', char(obj.wellIDs(wi)), char(v.autoVerdict)));
            if ~isempty(legendHandles)
                legend(obj.ax, legendHandles, legendEntries, 'Location', 'northwest', 'FontSize', 7);
            end
        end

        function cur = rawCurrentFor(obj, ivName, wi)
            cur = [];
            if ~isfield(obj.assessedData.measurements, ivName); return; end
            m = obj.assessedData.measurements.(ivName);
            if strcmp(obj.protocolType, 'activation') && isfield(m, 'peakCurrent')
                cur = m.peakCurrent(wi, :);
            elseif isfield(m, 'inactivationData')
                cur = m.inactivationData(wi, :);
            end
        end

        function updateInfo(obj)
            wi = obj.selectedWell;
            v = obj.assessedData.verdicts(wi);
            d = obj.session.getDecision(obj.wellKeys(wi));
            lines = {};
            lines{end+1} = sprintf('Well: %s   (%s)', char(obj.wellIDs(wi)), char(obj.assessedData.fileName));
            if ~isempty(d)
                lines{end+1} = sprintf('Auto: %s   User: %s   Final: %s', ...
                    d.autoVerdict, ternstr(d.userVerdict), d.finalVerdict);
            else
                lines{end+1} = sprintf('Auto: %s', char(v.autoVerdict));
            end
            if ~isempty(v.reasons)
                lines{end+1} = sprintf('Reasons: %s', strjoin(cellstr(v.reasons), ', '));
            else
                lines{end+1} = 'Reasons: (passed auto-QC)';
            end
            m = v.metrics;
            lines{end+1} = sprintf('IV1 peak density: %s pA/pF', num2strOr(getfieldOr(m,'iv1PeakDensity',NaN)));
            lines{end+1} = sprintf('Series R: %s MΩ   Seal R: %s GΩ   Cap: %s pF', ...
                num2strOr(getfieldOr(m,'seriesRMedian',NaN)), ...
                num2strOr(getfieldOr(m,'sealRMedian',NaN)), ...
                num2strOr(getfieldOr(m,'capMedian',NaN)));
            lines{end+1} = '--- Fit per IV ---';
            well = obj.fittedData.wells(wi);
            for i = 1:numel(obj.ivNames)
                ivName = obj.ivNames{i};
                if ~isfield(well, ivName) || isempty(well.(ivName)); continue; end
                wf = well.(ivName);
                if isfield(wf, 'fitParams') && isfield(wf.fitParams, 'V_mid') && ...
                        isfield(wf.fitParams, 'converged') && wf.fitParams.converged
                    fp = wf.fitParams;
                    lines{end+1} = sprintf('%s: V_{1/2}=%.1f  k=%.1f  R²=%.3f  [%s]', ...
                        upper(ivName), fp.V_mid, fp.k, fp.R2, wf.fitQuality); %#ok<AGROW>
                else
                    lines{end+1} = sprintf('%s: no fit (%s)', upper(ivName), wf.fitQuality); %#ok<AGROW>
                end
            end
            obj.infoArea.Value = lines;
        end

        function updateStatus(obj)
            s = obj.session.summary();
            obj.statusLbl.Text = sprintf(...
                'File: %s   |   %d wells   |   keep: %d   reject: %d   overridden: %d', ...
                char(obj.assessedData.fileName), s.total, s.keep, s.reject, s.overridden);
        end
    end
end

% ---- small local helpers ----
function s = ternstr(x)
    if isempty(x); s = '(auto)'; else; s = x; end
end

function s = num2strOr(x)
    if isempty(x) || (isnumeric(x) && isnan(x)); s = 'n/a'; else; s = num2str(x, '%.1f'); end
end

function v = getfieldOr(s, f, default)
    if isstruct(s) && isfield(s, f); v = s.(f); else; v = default; end
end
