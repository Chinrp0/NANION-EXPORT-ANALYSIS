classdef QCReviewSession < handle
    %QCREVIEWSESSION Persistent store of per-well QC decisions.
    %   Holds one decision per well (keyed by wellKey = "fileName::wellID"),
    %   combining the automatic verdict from NanionDataExtractor.assessQuality
    %   with an optional user override. Persists decisions to disk so a re-run
    %   reloads prior review calls instead of starting from scratch.
    %
    %   Storage layout is chosen by config.qc.decisionStore:
    %     'sidecar' - one <fileName>_qc_decisions.mat next to (a given dir of) each raw file
    %     'central' - one qc_decisions.mat for the whole batch
    %
    %   Typical flow:
    %     s = QCReviewSession(config, logger);
    %     s.load(storeDir);                 % reload any prior decisions
    %     s.ingestAssessment(assessedData); % add/refresh auto verdicts (keeps overrides)
    %     s.setUserVerdict(wellKey, 'keep');
    %     mask = s.keepMaskFor(assessedData);
    %     filtered = extractor.applyDecisions(assessedData, mask);
    %     s.save(storeDir);

    properties (Access = private)
        config
        logger
        decisions   % containers.Map: wellKey (char) -> decision struct
    end

    methods
        function obj = QCReviewSession(config, logger)
            obj.config = config;
            obj.logger = logger;
            obj.decisions = containers.Map('KeyType', 'char', 'ValueType', 'any');
        end

        function ingestAssessment(obj, assessedData)
            %INGESTASSESSMENT Add/refresh decisions from assessQuality verdicts.
            %   Existing user overrides are preserved; auto fields are refreshed.
            if ~isfield(assessedData, 'verdicts')
                error('QCReviewSession:NoVerdicts', ...
                    'assessedData has no .verdicts (run assessQuality first)');
            end
            V = assessedData.verdicts;
            for i = 1:numel(V)
                key = char(V(i).wellKey);
                if isKey(obj.decisions, key)
                    d = obj.decisions(key);
                    d.autoVerdict = char(V(i).autoVerdict);
                    d.reasons = V(i).reasons;
                    d.metrics = V(i).metrics;
                else
                    d = obj.newDecision(V(i));
                end
                d.finalVerdict = obj.resolveFinal(d);
                obj.decisions(key) = d;
            end
            obj.logger.logInfo(sprintf('QCReviewSession: %d decisions tracked', obj.decisions.Count));
        end

        function setUserVerdict(obj, wellKey, verdict)
            %SETUSERVERDICT Override a well: 'keep' | 'reject' | 'auto' (clear override)
            key = char(wellKey);
            if ~isKey(obj.decisions, key)
                error('QCReviewSession:UnknownWell', 'Unknown wellKey: %s', key);
            end
            verdict = lower(verdict);
            if ~ismember(verdict, {'keep', 'reject', 'auto'})
                error('QCReviewSession:BadVerdict', 'verdict must be keep, reject, or auto');
            end
            d = obj.decisions(key);
            if strcmp(verdict, 'auto')
                d.userVerdict = '';
            else
                d.userVerdict = verdict;
            end
            d.finalVerdict = obj.resolveFinal(d);
            d.updated = datestr(now, 'yyyy-mm-dd HH:MM:SS');
            obj.decisions(key) = d;
        end

        function d = getDecision(obj, wellKey)
            key = char(wellKey);
            if isKey(obj.decisions, key)
                d = obj.decisions(key);
            else
                d = [];
            end
        end

        function mask = keepMask(obj, wellKeys)
            %KEEPMASK Ordered logical mask (final verdict == keep) for wellKeys.
            n = numel(wellKeys);
            mask = false(n, 1);
            for i = 1:n
                key = char(wellKeys(i));
                if isKey(obj.decisions, key)
                    mask(i) = strcmp(obj.decisions(key).finalVerdict, 'keep');
                end
            end
        end

        function mask = keepMaskFor(obj, assessedData)
            %KEEPMASKFOR Ordered keep-mask aligned to assessedData well order.
            %   Falls back to the auto verdict for any well not yet tracked.
            V = assessedData.verdicts;
            n = numel(V);
            mask = false(n, 1);
            for i = 1:n
                key = char(V(i).wellKey);
                if isKey(obj.decisions, key)
                    mask(i) = strcmp(obj.decisions(key).finalVerdict, 'keep');
                else
                    mask(i) = V(i).autoPass;
                end
            end
        end

        function s = summary(obj)
            %SUMMARY Counts of final/auto/user verdicts across tracked wells.
            d = obj.toStructArray();
            if isempty(d)
                s = struct('total', 0, 'keep', 0, 'reject', 0, 'overridden', 0);
                return;
            end
            final = string({d.finalVerdict});
            user = string({d.userVerdict});
            s = struct('total', numel(d), ...
                'keep', sum(final == "keep"), ...
                'reject', sum(final == "reject"), ...
                'overridden', sum(user == "keep" | user == "reject"));
        end

        function t = toTable(obj)
            %TOTABLE Human-readable table of decisions (for inspection/export).
            d = obj.toStructArray();
            if isempty(d)
                t = table();
                return;
            end
            reasonsJoined = arrayfun(@(x) string(strjoin(x.reasons, '; ')), d(:));
            iv1Density = arrayfun(@(x) obj.metricOr(x.metrics, 'iv1PeakDensity'), d(:));
            t = table(string({d.wellKey})', string({d.fileName})', string({d.wellID})', ...
                string({d.autoVerdict})', string({d.userVerdict})', string({d.finalVerdict})', ...
                reasonsJoined, iv1Density, string({d.updated})', ...
                'VariableNames', {'wellKey', 'fileName', 'wellID', 'autoVerdict', ...
                'userVerdict', 'finalVerdict', 'reasons', 'iv1PeakDensity_pA_pF', 'updated'});
        end

        function exportCSV(obj, csvPath)
            %EXPORTCSV Write the decisions table to CSV for manual inspection.
            writetable(obj.toTable(), csvPath);
            obj.logger.logInfo(sprintf('QCReviewSession: exported decisions CSV -> %s', csvPath));
        end

        % ----- persistence (dispatches on config.qc.decisionStore) -----

        function save(obj, targetDir)
            switch lower(obj.config.qc.decisionStore)
                case 'central'; obj.saveCentral(targetDir);
                case 'sidecar'; obj.saveSidecar(targetDir);
                otherwise
                    error('QCReviewSession:BadStore', 'Unknown decisionStore: %s', obj.config.qc.decisionStore);
            end
        end

        function load(obj, targetDir)
            switch lower(obj.config.qc.decisionStore)
                case 'central'; obj.loadCentral(targetDir);
                case 'sidecar'; obj.loadSidecar(targetDir);
                otherwise
                    error('QCReviewSession:BadStore', 'Unknown decisionStore: %s', obj.config.qc.decisionStore);
            end
        end

        function saveCentral(obj, targetDir)
            if ~exist(targetDir, 'dir'); mkdir(targetDir); end
            decisions = obj.toStructArray(); %#ok<NASGU>
            file = fullfile(targetDir, 'qc_decisions.mat');
            save(file, 'decisions', '-v7');
            obj.logger.logInfo(sprintf('QCReviewSession: saved %d decisions -> %s', ...
                obj.decisions.Count, file));
        end

        function loadCentral(obj, targetDir)
            file = fullfile(targetDir, 'qc_decisions.mat');
            if ~exist(file, 'file')
                obj.logger.logInfo('QCReviewSession: no central decisions file to load');
                return;
            end
            S = load(file, 'decisions');
            obj.mergeStructArray(S.decisions);
            obj.logger.logInfo(sprintf('QCReviewSession: loaded %d decisions <- %s', ...
                numel(S.decisions), file));
        end

        function saveSidecar(obj, targetDir)
            if ~exist(targetDir, 'dir'); mkdir(targetDir); end
            d = obj.toStructArray();
            if isempty(d); return; end
            files = unique(string({d.fileName}));
            for i = 1:numel(files)
                decisions = d(string({d.fileName}) == files(i)); %#ok<NASGU>
                file = fullfile(targetDir, char(files(i) + "_qc_decisions.mat"));
                save(file, 'decisions', '-v7');
                obj.logger.logInfo(sprintf('QCReviewSession: saved %d decisions -> %s', ...
                    numel(decisions), file));
            end
        end

        function loadSidecar(obj, targetDir)
            listing = dir(fullfile(targetDir, '*_qc_decisions.mat'));
            if isempty(listing)
                obj.logger.logInfo('QCReviewSession: no sidecar decisions files to load');
                return;
            end
            for i = 1:numel(listing)
                S = load(fullfile(listing(i).folder, listing(i).name), 'decisions');
                obj.mergeStructArray(S.decisions);
            end
            obj.logger.logInfo(sprintf('QCReviewSession: loaded %d sidecar file(s)', numel(listing)));
        end
    end

    methods (Access = private)
        function d = newDecision(obj, verdict)
            d = struct(...
                'wellKey', char(verdict.wellKey), ...
                'wellID', char(verdict.wellID), ...
                'fileName', char(verdict.fileName), ...
                'autoVerdict', char(verdict.autoVerdict), ...
                'reasons', {verdict.reasons}, ...
                'metrics', verdict.metrics, ...
                'userVerdict', '', ...
                'finalVerdict', 'reject', ...
                'updated', '');
            d.finalVerdict = obj.resolveFinal(d);
        end

        function fv = resolveFinal(~, d)
            if ismember(d.userVerdict, {'keep', 'reject'})
                fv = d.userVerdict;
            elseif strcmp(d.autoVerdict, 'pass')
                fv = 'keep';
            else
                fv = 'reject';
            end
        end

        function arr = toStructArray(obj)
            if obj.decisions.Count == 0
                arr = struct([]);
                return;
            end
            vals = obj.decisions.values;
            arr = [vals{:}];
        end

        function mergeStructArray(obj, arr)
            for i = 1:numel(arr)
                d = arr(i);
                d.finalVerdict = obj.resolveFinal(d);
                obj.decisions(char(d.wellKey)) = d;
            end
        end

        function v = metricOr(~, m, field)
            if isstruct(m) && isfield(m, field)
                v = m.(field);
            else
                v = NaN;
            end
        end
    end
end
