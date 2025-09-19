classdef NanionLogger < handle
    %NANIONLOGGER Centralized logging system
    %   Thread-safe logging with multiple output destinations
    
    properties (Access = private)
        config
        logFile
        logLevel
        sessionId
    end
    
    properties (Constant)
        LEVEL_ERROR = 1;
        LEVEL_WARNING = 2; 
        LEVEL_INFO = 3;
        LEVEL_DEBUG = 4;
    end
    
    methods
        function obj = NanionLogger(config, logFile)
            %NANIONLOGGER Constructor
            
            obj.config = config;
            obj.logLevel = obj.LEVEL_INFO; % Default level
            obj.sessionId = obj.generateSessionId();
            
            if nargin >= 2 && ~isempty(logFile)
                obj.logFile = logFile;
                obj.initializeLogFile();
            end
        end
        
        function logInfo(obj, message)
            %LOGINFO Log informational message
            obj.writeLog('INFO', message, obj.LEVEL_INFO);
        end
        
        function logWarning(obj, message)  
            %LOGWARNING Log warning message
            obj.writeLog('WARN', message, obj.LEVEL_WARNING);
        end
        
        function logError(obj, message)
            %LOGERROR Log error message
            obj.writeLog('ERROR', message, obj.LEVEL_ERROR);
        end
        
        function logDebug(obj, message)
            %LOGDEBUG Log debug message
            obj.writeLog('DEBUG', message, obj.LEVEL_DEBUG);
        end
        
        function setLogLevel(obj, level)
            %SETLOGLEVEL Set minimum log level
            obj.logLevel = level;
        end
        
        function setLogFile(obj, filePath)
            %SETLOGFILE Set log file path
            obj.logFile = filePath;
            obj.initializeLogFile();
        end
    end
    
    methods (Access = private)
        function writeLog(obj, levelStr, message, level)
            %WRITELOG Write log message to outputs
            
            if level > obj.logLevel
                return; % Skip if below log level
            end
            
            timestamp = datestr(now, 'yyyy-mm-dd HH:MM:SS.FFF');
            logEntry = sprintf('[%s] [%s] [%s] %s', ...
                timestamp, levelStr, obj.sessionId, message);
            
            % Always write to console
            fprintf('%s\n', logEntry);
            
            % Write to file if specified
            if ~isempty(obj.logFile)
                obj.writeToFile(logEntry);
            end
        end
        
        function writeToFile(obj, logEntry)
            %WRITETOFILE Write entry to log file
            
            fid = fopen(obj.logFile, 'a');
            if fid < 0
                error('NanionLogger:CannotWriteLogFile', 'Cannot write to log file: %s', obj.logFile);
            end
            
            try
                fprintf(fid, '%s\n', logEntry);
                fclose(fid);
            catch ME
                fclose(fid);
                error('NanionLogger:LogWriteFailed', 'Failed to write log entry: %s', ME.message);
            end
        end
        
        function initializeLogFile(obj)
            %INITIALIZELOGFILE Initialize log file with session header
            
            if isempty(obj.logFile)
                return;
            end
            
            fid = fopen(obj.logFile, 'w'); 
            if fid < 0
                error('NanionLogger:CannotCreateLogFile', 'Cannot create log file: %s', obj.logFile);
            end
            
            try
                fprintf(fid, '=== NANION ANALYSIS LOG SESSION %s ===\n', obj.sessionId);
                fprintf(fid, 'Started: %s\n', datestr(now));
                fprintf(fid, 'MATLAB Version: %s\n', version);
                fprintf(fid, '\n');
                fclose(fid);
            catch ME
                fclose(fid);
                error('NanionLogger:LogInitializationFailed', 'Failed to initialize log file: %s', ME.message);
            end
        end
        
        function sessionId = generateSessionId(obj)
            %GENERATESESSIONID Create unique session identifier
            sessionId = sprintf('S%s', datestr(now, 'yyyymmdd_HHMMSS'));
        end
    end
end