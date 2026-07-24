function setup_nanion_paths(verbose)
    %SETUP_NANION_PATHS Add all Nanion analysis directories to MATLAB path
    %   Call this function at the start of your analysis session or add it
    %   to your MATLAB startup.m file
    %
    %   Usage:
    %       setup_nanion_paths()         % Silent mode
    %       setup_nanion_paths(true)     % Verbose mode with progress output
    %
    %   This function automatically detects the repository root and adds
    %   all required subdirectories to the MATLAB path.
    
    if nargin < 1
        verbose = false;
    end
    
    % Get the directory where this script is located
    scriptPath = fileparts(mfilename('fullpath'));
    
    % Determine repository root (assuming script is in SRC/ or root)
    if endsWith(scriptPath, 'SRC') || endsWith(scriptPath, 'src')
        repoRoot = scriptPath;
    elseif exist(fullfile(scriptPath, 'SRC'), 'dir')
        repoRoot = fullfile(scriptPath, 'SRC');
    else
        repoRoot = scriptPath;
    end
    
    if verbose
        fprintf('=== NANION PATH SETUP ===\n');
        fprintf('Repository root: %s\n\n', repoRoot);
    end
    
    % Define required subdirectories in dependency order
    requiredDirs = {
        'utils',      % Base utilities (logger, etc.)
        'config',     % Configuration classes
        'io',         % File I/O (if exists)
        'analysis',   % Data extraction and filtering
        'fitting',    % Boltzmann fitting
        'plotting',   % Visualization
        'qc',         % QC review decisions/session
        'pipeline',   % Main pipeline orchestration
        'detection'   % Protocol detection (if exists)
    };
    
    % Add repository root first
    if ~contains(path, repoRoot)
        addpath(repoRoot);
        if verbose
            fprintf('✓ Added root: %s\n', repoRoot);
        end
    end
    
    % Add each subdirectory
    addedCount = 0;
    missingCount = 0;
    
    for i = 1:length(requiredDirs)
        dirName = requiredDirs{i};
        fullPath = fullfile(repoRoot, dirName);
        
        if exist(fullPath, 'dir')
            if ~contains(path, fullPath)
                addpath(fullPath);
                addedCount = addedCount + 1;
                
                if verbose
                    fprintf('✓ Added: %s\n', dirName);
                end
            else
                if verbose
                    fprintf('  Already in path: %s\n', dirName);
                end
            end
        else
            missingCount = missingCount + 1;
            if verbose
                fprintf('⚠ Not found: %s (skipping)\n', dirName);
            end
        end
    end
    
    % Also add test directories (optional, for development)
    testDirs = {
        'analysis/tests',
        'fitting/tests',
        'pipeline/tests'
    };
    
    for i = 1:length(testDirs)
        testPath = fullfile(repoRoot, testDirs{i});
        if exist(testPath, 'dir') && ~contains(path, testPath)
            addpath(testPath);
            if verbose
                fprintf('✓ Added test directory: %s\n', testDirs{i});
            end
        end
    end
    
    % Verify critical classes are now accessible
    criticalClasses = {
        'NanionConfig',
        'NanionLogger',
        'NanionDataExtractor',
        'NanionBoltzmannFitter',
        'BoltzmannModel',
        'FitQualityAssessor',
        'NanionBoltzmannPlotter',
        'NanionAnalysisPipeline'
    };
    
    allFound = true;
    missingClasses = {};
    
    for i = 1:length(criticalClasses)
        className = criticalClasses{i};
        if ~exist(className, 'class')
            allFound = false;
            missingClasses{end+1} = className;
        end
    end
    
    if verbose
        fprintf('\n--- VERIFICATION ---\n');
        if allFound
            fprintf('✓ All critical classes accessible (%d/%d)\n', ...
                length(criticalClasses), length(criticalClasses));
        else
            fprintf('✗ Missing classes: %d/%d\n', ...
                length(missingClasses), length(criticalClasses));
            for i = 1:length(missingClasses)
                fprintf('  - %s\n', missingClasses{i});
            end
        end
        
        fprintf('\nSummary:\n');
        fprintf('  Directories added: %d\n', addedCount);
        fprintf('  Directories missing: %d\n', missingCount);
        fprintf('\n=== PATH SETUP COMPLETE ===\n');
    end
    
    % Error if critical classes missing
    if ~allFound
        error('NanionPaths:MissingClasses', ...
            ['Path setup incomplete. Missing classes: ' strjoin(missingClasses, ', ') ...
            '. Check your repository structure.']);
    end
end
