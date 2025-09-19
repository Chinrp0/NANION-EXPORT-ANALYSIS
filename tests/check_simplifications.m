function check_simplifications()
    %CHECK_SIMPLIFICATIONS Identify which simplifications weren't implemented
    
    fprintf('=== SIMPLIFICATION CHECK ===\n\n');
    
    % Check NanionConfig methods
    fprintf('Checking NanionConfig methods...\n');
    methods_config = methods('NanionConfig');
    
    old_validation_methods = {'validateAnalysisParams', 'validateFilterParams', ...
        'validateBoltzmannParams', 'validatePlottingParams', 'validateProcessingParams', ...
        'validateIOParams', 'validateProtocolParams', 'yesNo'};
    
    found_old_methods = {};
    for i = 1:length(old_validation_methods)
        if any(strcmp(methods_config, old_validation_methods{i}))
            found_old_methods{end+1} = old_validation_methods{i};
        end
    end
    
    if isempty(found_old_methods)
        fprintf('  ✓ NanionConfig validation methods consolidated\n');
    else
        fprintf('  ❌ Still has old validation methods: %s\n', strjoin(found_old_methods, ', '));
    end
    
    % Check NanionIOManager methods
    fprintf('Checking NanionIOManager methods...\n');
    methods_io = methods('NanionIOManager');
    
    old_io_methods = {'cleanHeaderRow', 'createValidTableHeader', 'isEmptyCell', ...
        'readFilesBatchParallel', 'readSingleFileStatic'};
    
    found_old_io_methods = {};
    for i = 1:length(old_io_methods)
        if any(strcmp(methods_io, old_io_methods{i}))
            found_old_io_methods{end+1} = old_io_methods{i};
        end
    end
    
    if isempty(found_old_io_methods)
        fprintf('  ✓ NanionIOManager methods simplified\n');
    else
        fprintf('  ❌ Still has old methods: %s\n', strjoin(found_old_io_methods, ', '));
    end
    
    % Check NanionFileDetector methods
    fprintf('Checking NanionFileDetector methods...\n');
    methods_detector = methods('NanionFileDetector');
    
    old_detector_methods = {'validateProtocol', 'validateKeyColumns', 'convertToStringArray'};
    
    found_old_detector_methods = {};
    for i = 1:length(old_detector_methods)
        if any(strcmp(methods_detector, old_detector_methods{i}))
            found_old_detector_methods{end+1} = old_detector_methods{i};
        end
    end
    
    if isempty(found_old_detector_methods)
        fprintf('  ✓ NanionFileDetector methods simplified\n');
    else
        fprintf('  ❌ Still has old methods: %s\n', strjoin(found_old_detector_methods, ', '));
    end
    
    % Line count per file analysis
    fprintf('\nLine count analysis:\n');
    srcFiles = {
        'SRC/config/NanionConfig.m',
        'SRC/io/NanionIOManager.m', 
        'SRC/io/NanionFileDetector.m',
        'SRC/utils/NanionLogger.m',
        'SRC/pipeline/NanionAnalysisPipeline.m'
    };
    
    targets = [150, 200, 80, 50, 100]; % Target line counts
    
    for i = 1:length(srcFiles)
        if exist(srcFiles{i}, 'file')
            fid = fopen(srcFiles{i}, 'r');
            if fid > 0
                lines = 0;
                while ~feof(fid)
                    fgetl(fid);
                    lines = lines + 1;
                end
                fclose(fid);
                
                [~, filename, ext] = fileparts(srcFiles{i});
                if lines > targets(i)
                    fprintf('  ❌ %s%s: %d lines (target: %d) - needs more simplification\n', ...
                        filename, ext, lines, targets(i));
                else
                    fprintf('  ✓ %s%s: %d lines (target: %d)\n', ...
                        filename, ext, lines, targets(i));
                end
            end
        end
    end
    
    fprintf('\n=== ACTIONS NEEDED ===\n');
    if ~isempty(found_old_methods)
        fprintf('1. Delete these methods from NanionConfig: %s\n', strjoin(found_old_methods, ', '));
    end
    if ~isempty(found_old_io_methods)
        fprintf('2. Delete these methods from NanionIOManager: %s\n', strjoin(found_old_io_methods, ', '));
    end
    if ~isempty(found_old_detector_methods)
        fprintf('3. Delete these methods from NanionFileDetector: %s\n', strjoin(found_old_detector_methods, ', '));
    end
    
    fprintf('4. Fix detectProtocol method in NanionFileDetector (string array issue)\n');
    fprintf('5. Replace complex methods with simplified versions\n');
end