classdef NanionConfig < handle
    %NANIONCONFIG Centralized configuration management
    %   UPDATED: Added public temperature property for Boltzmann fitting
    %
    %   >>> TO TUNE THE ANALYSIS, EDIT THE "USER-CONFIGURABLE PARAMETERS"
    %       CONSTANTS BLOCK DIRECTLY BELOW. Everything a user normally changes
    %       (QC review, quality thresholds, fitting, analysis constants, plotting)
    %       lives there. loadDefaultConfig() just assembles these into the config.

    properties (Constant, Access = private)
        % =================================================================
        %                 USER-CONFIGURABLE PARAMETERS
        %   Edit the values here. These are the defaults used when a pipeline
        %   is created without an explicit JSON config file.
        % =================================================================

        % ---- QC REVIEW WORKFLOW ----------------------------------------
        QC_ENABLE_REVIEW   = true          % master switch: true = review runs automatically at pipeline start; set false to skip
        QC_REVIEW_MODE     = 'blocking'    % 'blocking' (pause + launch app now) | 'standalone' (review saved results later)
        QC_DECISION_STORE  = 'central'     % 'central' (one decisions file per batch) | 'sidecar' (one per raw file)

        % ---- QUALITY FILTER THRESHOLDS ---------------------------------
        FILTER_MAX_SERIES_R_MOHM   = 50    % MΩ  - reject wells above this median series resistance
        FILTER_MAX_SEAL_R_GOHM     = 50    % GΩ  - reject wells above this median seal resistance
        FILTER_MAX_CAPACITANCE_PF  = 250   % pF  - reject wells above this median capacitance
        FILTER_MIN_CURRENT_DENSITY = 50    % pA/pF - IV1 signal gate; rejects leak-only wells with no functional current
        FILTER_OUTLIER_THRESHOLD   = 2.0   % x median - flag sweeps exceeding this as unstable
        FILTER_MIN_VALID_SWEEPS    = 19    % require at least this many valid sweeps (of 23)

        % ---- BOLTZMANN FITTING -----------------------------------------
        BOLTZ_CORR_THRESHOLD       = 0.90         % R² for a "Good" fit
        BOLTZ_ACCEPTABLE_THRESHOLD = 0.75         % R² for an "Acceptable" fit
        BOLTZ_SLOPE_LIMITS         = [1, 100]     % mV slope-factor k bounds (positive for a rising curve)
        BOLTZ_ACT_VMID_RANGE       = [-100, 0]    % mV allowed V_mid range, activation
        BOLTZ_INACT_VMID_RANGE     = [-100, -30]  % mV allowed V_mid range, inactivation
        BOLTZ_MIN_VALID_POINTS     = 15           % minimum voltage points needed to attempt a fit
        BOLTZ_USE_PARALLEL         = false        % parallel fitting (keep false for clearer errors)

        % ---- ANALYSIS CONSTANTS ----------------------------------------
        ANALYSIS_NUM_DATA_POINTS   = 23    % voltage steps per IV
        ANALYSIS_NERNST_POTENTIAL  = 68    % mV reversal potential used for conductance
        ANALYSIS_TEMPERATURE_C     = 20    % °C - used for gating-charge calculation

        % ---- PLOTTING --------------------------------------------------
        PLOT_FIGURE_SIZE       = [1920, 1080]
        PLOT_DPI               = 300
        PLOT_ROWS_PER_FIGURE   = 3
        PLOT_COLS_PER_FIGURE   = 4
        PLOT_MARKER_SIZE       = 8
        PLOT_LINE_WIDTH        = 2
        PLOT_FONT_SIZE_TITLE   = 12
        PLOT_FONT_SIZE_AXIS    = 10

        % ---- PROCESSING ------------------------------------------------
        PROC_USE_PARALLEL            = true
        PROC_MAX_WORKERS             = 8   % capped against available compute threads at load time
        PROC_MEMORY_CLEANUP_INTERVAL = 3
        PROC_TIMEOUT_MINUTES         = 30

        % ---- FILE I/O --------------------------------------------------
        IO_READ_METHOD       = 'readcell'
        IO_ENABLE_FALLBACKS  = false
        IO_MAX_FILE_SIZE_MB  = 100
        IO_ENCODING          = 'UTF-8'
        % =================================================================
        %              END USER-CONFIGURABLE PARAMETERS
        % =================================================================
    end

    properties (Access = private)
        configData
        isValidated
    end
    
    properties (Dependent)
        % Data processing parameters
        numDataPoints
        nernstPotential
        temperature  % ADDED - required for gating charge calculation
        
        % Quality filter thresholds  
        filters
        
        % Boltzmann fitting parameters
        boltzmann
        
        % Plotting parameters
        plotting
        
        % Processing parameters
        processing
        
        % File I/O parameters
        io
        
        % Protocol detection parameters
        protocols

        % QC review workflow parameters
        qc
    end
    
    methods
        function obj = NanionConfig(configPath)
            if nargin < 1 || isempty(configPath)
                obj.loadDefaultConfig();
            else
                obj.loadConfigFromFile(configPath);
            end
            
            obj.validateConfiguration();
        end
        
        function value = get.numDataPoints(obj)
            value = obj.configData.analysis.numDataPoints;
        end
        
        function value = get.nernstPotential(obj)
            value = obj.configData.analysis.nernstPotential;
        end
        
        function value = get.temperature(obj)
            % ADDED: Public getter for temperature
            if isfield(obj.configData.analysis, 'temperature')
                value = obj.configData.analysis.temperature;
            else
                value = 25;  % Default fallback
            end
        end
        
        function value = get.filters(obj)
            value = obj.configData.filters;
        end
        
        function value = get.boltzmann(obj)
            value = obj.configData.boltzmann;
        end
        
        function value = get.plotting(obj)
            value = obj.configData.plotting;
        end
        
        function value = get.processing(obj)
            value = obj.configData.processing;
        end
        
        function value = get.io(obj)
            value = obj.configData.io;
        end
        
        function value = get.protocols(obj)
            value = obj.configData.protocols;
        end

        function value = get.qc(obj)
            if isfield(obj.configData, 'qc')
                value = obj.configData.qc;
            else
                % Backward-compatible default for configs loaded before qc existed
                value = struct('enableReview', false, ...
                    'reviewMode', 'blocking', 'decisionStore', 'sidecar');
            end
        end
        
        function updateParameter(obj, category, parameter, value)
            if ~isfield(obj.configData, category)
                error('NanionConfig:InvalidCategory', 'Category "%s" not found', category);
            end
            
            if ~isfield(obj.configData.(category), parameter)
                error('NanionConfig:InvalidParameter', 'Parameter "%s.%s" not found', category, parameter);
            end
            
            oldValue = obj.configData.(category).(parameter);
            obj.configData.(category).(parameter) = value;
            
            try
                obj.validateConfiguration();
            catch ME
                obj.configData.(category).(parameter) = oldValue;
                rethrow(ME);
            end
        end
        
        function saveConfig(obj, filePath)
            [~, ~, ext] = fileparts(filePath);
            
            switch lower(ext)
                case '.json'
                    obj.saveAsJSON(filePath);
                case '.yaml'
                    obj.saveAsYAML(filePath);
                otherwise
                    error('NanionConfig:UnsupportedFormat', 'Supported formats: .json, .yaml');
            end
        end
        
        function configStruct = exportStruct(obj)
            configStruct = obj.configData;
        end
        
        function summary = getSummary(obj)
            if obj.processing.useParallel
                parallelStr = 'Yes';
            else
                parallelStr = 'No';
            end
            
            summary = sprintf(['Configuration Summary:\n' ...
                '  Data Points per IV: %d\n' ...
                '  Nernst Potential: %.1f mV\n' ...
                '  Temperature: %.1f °C\n' ...
                '  Series R Threshold: %.1f MΩ\n' ...
                '  Seal R Threshold: %.1f GΩ\n' ...
                '  Capacitance Threshold: %.1f pF\n' ...
                '  Boltzmann R² Good: %.2f\n' ...
                '  Boltzmann R² Acceptable: %.2f\n' ...
                '  Min Valid Points: %d\n' ...
                '  Parallel Processing: %s\n' ...
                '  Max Workers: %d'], ...
                obj.numDataPoints, obj.nernstPotential, obj.temperature, ...
                obj.filters.maxSeriesResistance, obj.filters.maxSealResistance, ...
                obj.filters.maxCapacitance, ...
                obj.boltzmann.corrThreshold, obj.boltzmann.acceptableThreshold, ...
                obj.boltzmann.minValidPoints, ...
                parallelStr, obj.processing.maxWorkers);
        end
    end
    
    methods (Access = private)
        function loadDefaultConfig(obj)
            %LOADDEFAULTCONFIG Assemble configData from the USER-CONFIGURABLE
            %   PARAMETERS constants at the top of this file. To change a value,
            %   edit the constant there — not this method.

            obj.configData = struct();

            % Analysis parameters
            obj.configData.analysis = struct(...
                'numDataPoints', obj.ANALYSIS_NUM_DATA_POINTS, ...
                'nernstPotential', obj.ANALYSIS_NERNST_POTENTIAL, ...
                'temperature', obj.ANALYSIS_TEMPERATURE_C);

            % Quality filter thresholds
            obj.configData.filters = struct(...
                'maxSeriesResistance', obj.FILTER_MAX_SERIES_R_MOHM, ...
                'maxSealResistance', obj.FILTER_MAX_SEAL_R_GOHM, ...
                'maxCapacitance', obj.FILTER_MAX_CAPACITANCE_PF, ...
                'minCurrentDensity', obj.FILTER_MIN_CURRENT_DENSITY, ...
                'outlierThreshold', obj.FILTER_OUTLIER_THRESHOLD, ...
                'minValidSweeps', obj.FILTER_MIN_VALID_SWEEPS);

            % Boltzmann fitting parameters
            obj.configData.boltzmann = struct(...
                'corrThreshold', obj.BOLTZ_CORR_THRESHOLD, ...
                'acceptableThreshold', obj.BOLTZ_ACCEPTABLE_THRESHOLD, ...
                'slopeLimits', obj.BOLTZ_SLOPE_LIMITS, ...
                'activationVmidRange', obj.BOLTZ_ACT_VMID_RANGE, ...
                'inactivationVmidRange', obj.BOLTZ_INACT_VMID_RANGE, ...
                'minValidPoints', obj.BOLTZ_MIN_VALID_POINTS, ...
                'useParallel', obj.BOLTZ_USE_PARALLEL);

            % Plotting parameters
            obj.configData.plotting = struct(...
                'figureSize', obj.PLOT_FIGURE_SIZE, ...
                'dpi', obj.PLOT_DPI, ...
                'rowsPerFigure', obj.PLOT_ROWS_PER_FIGURE, ...
                'colsPerFigure', obj.PLOT_COLS_PER_FIGURE, ...
                'markerSize', obj.PLOT_MARKER_SIZE, ...
                'lineWidth', obj.PLOT_LINE_WIDTH, ...
                'fontSizeTitle', obj.PLOT_FONT_SIZE_TITLE, ...
                'fontSizeAxis', obj.PLOT_FONT_SIZE_AXIS);

            % Processing parameters
            obj.configData.processing = struct(...
                'useParallel', obj.PROC_USE_PARALLEL, ...
                'maxWorkers', min(maxNumCompThreads, obj.PROC_MAX_WORKERS), ...
                'memoryCleanupInterval', obj.PROC_MEMORY_CLEANUP_INTERVAL, ...
                'timeoutMinutes', obj.PROC_TIMEOUT_MINUTES);

            % File I/O parameters
            obj.configData.io = struct(...
                'readMethod', obj.IO_READ_METHOD, ...
                'enableFallbacks', obj.IO_ENABLE_FALLBACKS, ...
                'maxFileSizeMB', obj.IO_MAX_FILE_SIZE_MB, ...
                'encoding', obj.IO_ENCODING);

            % Protocol detection parameters (ADVANCED — column layout of the raw
            % Nanion export; rarely changed. Left here rather than in the user
            % block above because it encodes the file format, not an analysis knob.)
            obj.configData.protocols = struct(...
                'activation', struct(...
                    'columnPattern', 6, ...
                    'seriesResCol', [6, 12, 18], ...
                    'sealResCol', [7, 13, 19], ...
                    'capacitanceCol', [8, 14, 20], ...
                    'peakCurrentCol', [9, 15, 21], ...
                    'markerKeywords', {{'Peak'}}), ...
                'inactivation', struct(...
                    'columnPattern', 7, ...
                    'seriesResCol', [6, 13, 20], ...
                    'sealResCol', [7, 14, 21], ...
                    'capacitanceCol', [8, 15, 22], ...
                    'inactDataCol', [9, 16, 23], ...
                    'actDataCol', [10, 17, 24], ...
                    'markerKeywords', {{'Inact', 'Act'}}));

            % QC review workflow (values come from the USER PARAMETERS block above)
            obj.configData.qc = struct(...
                'enableReview', obj.QC_ENABLE_REVIEW, ...
                'reviewMode', obj.QC_REVIEW_MODE, ...
                'decisionStore', obj.QC_DECISION_STORE);
        end
        
        function loadConfigFromFile(obj, configPath)
            if ~exist(configPath, 'file')
                error('NanionConfig:FileNotFound', 'Config file not found: %s', configPath);
            end
            
            [~, ~, ext] = fileparts(configPath);
            
            switch lower(ext)
                case '.json'
                    obj.loadFromJSON(configPath);
                case '.yaml'
                    obj.loadFromYAML(configPath);
                otherwise
                    error('NanionConfig:UnsupportedFormat', 'Supported formats: .json, .yaml');
            end
        end
        
        function loadFromJSON(obj, filePath)
            fid = fopen(filePath, 'r');
            if fid < 0
                error('NanionConfig:CannotOpenFile', 'Cannot open file: %s', filePath);
            end
            
            try
                jsonText = fread(fid, '*char')';
                fclose(fid);
                
                if exist('jsondecode', 'builtin')
                    obj.configData = jsondecode(jsonText);
                else
                    error('NanionConfig:JSONNotSupported', 'JSON decoding not available');
                end
                
            catch ME
                if fid > 0
                    fclose(fid);
                end
                rethrow(ME);
            end
        end
        
        function loadFromYAML(obj, ~)
            error('NanionConfig:YAMLNotImplemented', 'YAML support not implemented. Use JSON format.');
        end
        
        function validateConfiguration(obj)
            try
                p = obj.configData;
                
                % Analysis parameters
                assert(isnumeric(p.analysis.numDataPoints) && p.analysis.numDataPoints > 0, ...
                    'numDataPoints must be positive integer');
                assert(isnumeric(p.analysis.nernstPotential) && abs(p.analysis.nernstPotential) < 200, ...
                    'nernstPotential must be reasonable voltage value');
                
                if isfield(p.analysis, 'temperature')
                    assert(isnumeric(p.analysis.temperature) && p.analysis.temperature > -50 && p.analysis.temperature < 50, ...
                        'temperature must be between -50 and 50 °C');
                end
                    
                % Filter parameters
                assert(isnumeric(p.filters.maxSeriesResistance) && p.filters.maxSeriesResistance > 0, ...
                    'maxSeriesResistance must be positive');
                assert(isnumeric(p.filters.maxSealResistance) && p.filters.maxSealResistance > 0, ...
                    'maxSealResistance must be positive');
                assert(isnumeric(p.filters.maxCapacitance) && p.filters.maxCapacitance > 0, ...
                    'maxCapacitance must be positive');
                if isfield(p.filters, 'minCurrentDensity')
                    assert(isnumeric(p.filters.minCurrentDensity) && p.filters.minCurrentDensity >= 0, ...
                        'minCurrentDensity must be >= 0');
                end
                assert(isnumeric(p.filters.outlierThreshold) && p.filters.outlierThreshold >= 1.0, ...
                    'outlierThreshold must be >= 1.0');
                assert(isnumeric(p.filters.minValidSweeps) && p.filters.minValidSweeps > 0 && p.filters.minValidSweeps <= 23, ...
                    'minValidSweeps must be between 1 and 23');
                    
                % Boltzmann parameters
                assert(isnumeric(p.boltzmann.corrThreshold) && p.boltzmann.corrThreshold > 0 && p.boltzmann.corrThreshold <= 1, ...
                    'corrThreshold must be between 0 and 1');
                assert(isnumeric(p.boltzmann.acceptableThreshold) && p.boltzmann.acceptableThreshold > 0 && p.boltzmann.acceptableThreshold <= 1, ...
                    'acceptableThreshold must be between 0 and 1');
                assert(isnumeric(p.boltzmann.slopeLimits) && length(p.boltzmann.slopeLimits) == 2, ...
                    'slopeLimits must be 2-element array');
                assert(isnumeric(p.boltzmann.activationVmidRange) && length(p.boltzmann.activationVmidRange) == 2, ...
                    'activationVmidRange must be 2-element array');
                assert(isnumeric(p.boltzmann.inactivationVmidRange) && length(p.boltzmann.inactivationVmidRange) == 2, ...
                    'inactivationVmidRange must be 2-element array');
                assert(isnumeric(p.boltzmann.minValidPoints) && p.boltzmann.minValidPoints > 0, ...
                    'minValidPoints must be positive integer');
                assert(islogical(p.boltzmann.useParallel) || (isnumeric(p.boltzmann.useParallel) && ismember(p.boltzmann.useParallel, [0,1])), ...
                    'useParallel must be logical');
                    
                % Processing parameters
                assert(islogical(p.processing.useParallel) || (isnumeric(p.processing.useParallel) && ismember(p.processing.useParallel, [0,1])), ...
                    'useParallel must be logical');
                assert(isnumeric(p.processing.maxWorkers) && p.processing.maxWorkers > 0, ...
                    'maxWorkers must be positive integer');
                    
                % I/O parameters
                validMethods = {'readcell'};
                assert(ischar(p.io.readMethod) && ismember(p.io.readMethod, validMethods), ...
                    'readMethod must be readcell');

                % QC review parameters
                if isfield(p, 'qc')
                    assert(ismember(lower(p.qc.reviewMode), {'blocking', 'standalone'}), ...
                        'qc.reviewMode must be blocking or standalone');
                    assert(ismember(lower(p.qc.decisionStore), {'sidecar', 'central'}), ...
                        'qc.decisionStore must be sidecar or central');
                end

                obj.isValidated = true;
                
            catch ME
                obj.isValidated = false;
                error('NanionConfig:ValidationFailed', 'Configuration validation failed: %s', ME.message);
            end
        end
        
        function saveAsJSON(obj, filePath)
            if exist('jsonencode', 'builtin')
                jsonText = jsonencode(obj.configData, 'PrettyPrint', true);
                
                fid = fopen(filePath, 'w');
                if fid < 0
                    error('NanionConfig:CannotWriteFile', 'Cannot write to file: %s', filePath);
                end
                
                try
                    fprintf(fid, '%s', jsonText);
                    fclose(fid);
                catch ME
                    fclose(fid);
                    rethrow(ME);
                end
            else
                error('NanionConfig:JSONNotSupported', 'JSON encoding not available');
            end
        end
        
        function saveAsYAML(obj, ~)
            error('NanionConfig:YAMLNotImplemented', 'YAML export not implemented. Use JSON format.');
        end       
    end
end
