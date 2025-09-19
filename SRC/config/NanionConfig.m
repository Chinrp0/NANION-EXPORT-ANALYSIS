classdef NanionConfig < handle
    %NANIONCONFIG Centralized configuration management
    %   Handles all analysis parameters with validation and type checking
    %   Supports loading from JSON/YAML files and environment-specific configs
    
    properties (Access = private)
        configData
        isValidated
    end
    
    properties (Dependent)
        % Data processing parameters
        numDataPoints
        nernstPotential
        
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
    end
    
    methods
        function obj = NanionConfig(configPath)
            %NANIONCONFIG Constructor
            %   configPath - Optional path to configuration file
            
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
        
        function updateParameter(obj, category, parameter, value)
            %UPDATEPARAMETER Update a single parameter with validation
            
            if ~isfield(obj.configData, category)
                error('NanionConfig:InvalidCategory', 'Category "%s" not found', category);
            end
            
            if ~isfield(obj.configData.(category), parameter)
                error('NanionConfig:InvalidParameter', 'Parameter "%s.%s" not found', category, parameter);
            end
            
            % Store old value for validation
            oldValue = obj.configData.(category).(parameter);
            obj.configData.(category).(parameter) = value;
            
            % Validate the change
            try
                obj.validateConfiguration();
            catch ME
                % Restore old value if validation fails
                obj.configData.(category).(parameter) = oldValue;
                rethrow(ME);
            end
        end
        
        function saveConfig(obj, filePath)
            %SAVECONFIG Save current configuration to file
            
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
            %EXPORTSTRUCT Export configuration as MATLAB struct
            configStruct = obj.configData;
        end
        
        function summary = getSummary(obj)
        %GETSUMMARY Get configuration summary string
        
        % Simple inline replacement for deleted yesNo() method
        if obj.processing.useParallel
            parallelStr = 'Yes';
        else
            parallelStr = 'No';
        end
        
        summary = sprintf(['Configuration Summary:\n' ...
            '  Data Points per IV: %d\n' ...
            '  Nernst Potential: %.1f mV\n' ...
            '  Series R Threshold: %.1f MΩ\n' ...
            '  Seal R Threshold: %.1f GΩ\n' ...
            '  Capacitance Threshold: %.1f pF\n' ...
            '  Boltzmann R² Threshold: %.2f\n' ...
            '  Parallel Processing: %s\n' ...
            '  Max Workers: %d'], ...
            obj.numDataPoints, obj.nernstPotential, ...
            obj.filters.maxSeriesResistance, obj.filters.maxSealResistance, ...
            obj.filters.maxCapacitance, obj.boltzmann.corrThreshold, ...
            parallelStr, obj.processing.maxWorkers);
    end
    end
    
    methods (Access = private)
        function loadDefaultConfig(obj)
            %LOADDEFAULTCONFIG Load default configuration values
            
            obj.configData = struct();
            
            % Analysis parameters
            obj.configData.analysis = struct(...
                'numDataPoints', 23, ...
                'nernstPotential', 68);  % mV
            
            % Quality filter thresholds
            obj.configData.filters = struct(...
                'maxSeriesResistance', 50, ...    % MΩ
                'maxSealResistance', 50, ...      % GΩ  
                'maxCapacitance', 250);           % pF
            
            % Boltzmann fitting parameters
            obj.configData.boltzmann = struct(...
                'corrThreshold', 0.9, ...
                'slopeLimits', [-100, 0], ...
                'activationVmidMax', 0, ...       % mV, must be ≤ 0
                'inactivationVmidRange', [-95, -30]); % mV
            
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
                'memoryCleanupInterval', 3, ...   % Every N files
                'timeoutMinutes', 30);
            
            % File I/O parameters
            obj.configData.io = struct(...
                'readMethod', 'readcell', ...     % Force readcell only
                'enableFallbacks', false, ...     % No fallback methods
                'maxFileSizeMB', 100, ...        % Warning threshold
                'encoding', 'UTF-8');
            
            % Protocol detection parameters  
            obj.configData.protocols = struct(...
                'activation', struct(...
                    'columnPattern', 6, ...       % Every 6th column
                    'seriesResCol', [6, 12, 18], ...  % Pattern starts
                    'sealResCol', [7, 13, 19], ...
                    'capacitanceCol', [8, 14, 20], ...
                    'peakCurrentCol', [9, 15, 21], ...
                    'markerKeywords', {{'Peak'}}), ...
                'inactivation', struct(...
                    'columnPattern', 7, ...       % Every 7th column  
                    'seriesResCol', [6, 13, 20], ...
                    'sealResCol', [7, 14, 21], ...
                    'capacitanceCol', [8, 15, 22], ...
                    'inactDataCol', [9, 16, 23], ...
                    'actDataCol', [10, 17, 24], ...
                    'markerKeywords', {{'Inact', 'Act'}}));
        end
        
        function loadConfigFromFile(obj, configPath)
            %LOADCONFIGFROMFILE Load configuration from JSON/YAML file
            
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
            %LOADFROMJSON Load from JSON file
            
            fid = fopen(filePath, 'r');
            if fid < 0
                error('NanionConfig:CannotOpenFile', 'Cannot open file: %s', filePath);
            end
            
            try
                jsonText = fread(fid, '*char')';
                fclose(fid);
                
                % MATLAB 2025a: Use built-in JSON decode
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
        
        function loadFromYAML(obj, filePath)
            %LOADFROMYAML Load from YAML file (requires external parser)
            
            % Note: MATLAB doesn't have built-in YAML support
            % This would require a third-party YAML parser
            error('NanionConfig:YAMLNotImplemented', 'YAML support not implemented. Use JSON format.');
        end
        
        function validateConfiguration(obj)
            %VALIDATECONFIGURATION Validate all configuration parameters
            
            try
                p = obj.configData;
                
                % Analysis parameters
                assert(isnumeric(p.analysis.numDataPoints) && p.analysis.numDataPoints > 0, ...
                    'numDataPoints must be positive integer');
                assert(isnumeric(p.analysis.nernstPotential) && abs(p.analysis.nernstPotential) < 200, ...
                    'nernstPotential must be reasonable voltage value');
                    
                % Filter parameters
                assert(isnumeric(p.filters.maxSeriesResistance) && p.filters.maxSeriesResistance > 0, ...
                    'maxSeriesResistance must be positive');
                assert(isnumeric(p.filters.maxSealResistance) && p.filters.maxSealResistance > 0, ...
                    'maxSealResistance must be positive');
                assert(isnumeric(p.filters.maxCapacitance) && p.filters.maxCapacitance > 0, ...
                    'maxCapacitance must be positive');
                    
                % Boltzmann parameters
                assert(isnumeric(p.boltzmann.corrThreshold) && p.boltzmann.corrThreshold > 0 && p.boltzmann.corrThreshold <= 1, ...
                    'corrThreshold must be between 0 and 1');
                assert(isnumeric(p.boltzmann.slopeLimits) && length(p.boltzmann.slopeLimits) == 2, ...
                    'slopeLimits must be 2-element array');
                    
                % Processing parameters
                assert(islogical(p.processing.useParallel) || (isnumeric(p.processing.useParallel) && ismember(p.processing.useParallel, [0,1])), ...
                    'useParallel must be logical');
                assert(isnumeric(p.processing.maxWorkers) && p.processing.maxWorkers > 0, ...
                    'maxWorkers must be positive integer');
                    
                % I/O parameters
                validMethods = {'readcell'};
                assert(ischar(p.io.readMethod) && ismember(p.io.readMethod, validMethods), ...
                    'readMethod must be readcell');
                    
                obj.isValidated = true;
                
            catch ME
                obj.isValidated = false;
                error('NanionConfig:ValidationFailed', 'Configuration validation failed: %s', ME.message);
            end
        end
        
        function saveAsJSON(obj, filePath)
            %SAVEASJSON Save configuration as JSON
            
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
        
        function saveAsYAML(obj, filePath)
            %SAVEASYAML Save configuration as YAML (not implemented)
            error('NanionConfig:YAMLNotImplemented', 'YAML export not implemented. Use JSON format.');
        end       
    end
end