classdef NanionConfig < handle
    %NANIONCONFIG Centralized configuration management
    %   UPDATED: Added public temperature property for Boltzmann fitting
    
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
            obj.configData = struct();
            
            % Analysis parameters
            obj.configData.analysis = struct(...
                'numDataPoints', 23, ...
                'nernstPotential', 68, ...
                'temperature', 20);  % °C for accurate gating charge
            
            % Quality filter thresholds
            obj.configData.filters = struct(...
                'maxSeriesResistance', 50, ...
                'maxSealResistance', 50, ...
                'maxCapacitance', 250, ...
                'minCurrentDensity', 50, ...   % pA/pF - IV1 signal gate; rejects leak-only wells with no functional current
                'outlierThreshold', 2.0, ...
                'minValidSweeps', 19);
            
            % Boltzmann fitting parameters
            obj.configData.boltzmann = struct(...
                'corrThreshold', 0.90, ...
                'acceptableThreshold', 0.75, ...
                'slopeLimits', [1, 100], ...
                'activationVmidRange', [-100, 0], ...  % UPDATED: Must be negative
                'inactivationVmidRange', [-100, -30], ...
                'minValidPoints', 15, ...
                'useParallel', false);  % CHANGED TO FALSE for debugging
            
            % Plotting parameters
            obj.configData.plotting = struct(...
                'figureSize', [1920, 1080], ...
                'dpi', 300, ...
                'rowsPerFigure', 3, ...
                'colsPerFigure', 4, ...
                'markerSize', 8, ...
                'lineWidth', 2, ...
                'fontSizeTitle', 12, ...
                'fontSizeAxis', 10);
            
            % Processing parameters
            obj.configData.processing = struct(...
                'useParallel', true, ...
                'maxWorkers', min(maxNumCompThreads, 8), ...
                'memoryCleanupInterval', 3, ...
                'timeoutMinutes', 30);
            
            % File I/O parameters
            obj.configData.io = struct(...
                'readMethod', 'readcell', ...
                'enableFallbacks', false, ...
                'maxFileSizeMB', 100, ...
                'encoding', 'UTF-8');
            
            % Protocol detection parameters  
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

            % QC review workflow (both options built; chosen here)
            obj.configData.qc = struct(...
                'enableReview', false, ...       % master on/off for the review step
                'reviewMode', 'blocking', ...    % 'blocking' (pause pipeline) | 'standalone' (review saved results)
                'decisionStore', 'central');     % 'sidecar' (file per raw file) | 'central' (one store per batch)
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
