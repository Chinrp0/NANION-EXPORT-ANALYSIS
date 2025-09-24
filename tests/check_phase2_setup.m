function check_phase2_setup()
%CHECK_PHASE2_SETUP Diagnose Phase 2 setup issues

fprintf('=== PHASE 2 SETUP DIAGNOSTIC ===\n\n');

% Check 1: Current directory
fprintf('Current directory: %s\n', pwd);

% Check 2: SRC directory structure
fprintf('\n=== DIRECTORY STRUCTURE ===\n');
if exist('SRC', 'dir')
    fprintf('✓ SRC directory exists\n');
    
    srcContents = dir('SRC');
    fprintf('SRC contents:\n');
    for i = 1:length(srcContents)
        if srcContents(i).isdir && ~startsWith(srcContents(i).name, '.')
            fprintf('  📁 %s/\n', srcContents(i).name);
        end
    end
    
    % Check analysis directory
    if exist('SRC/analysis', 'dir')
        fprintf('✓ SRC/analysis directory exists\n');
        
        analysisContents = dir('SRC/analysis');
        fprintf('SRC/analysis contents:\n');
        for i = 1:length(analysisContents)
            if ~startsWith(analysisContents(i).name, '.')
                fprintf('  📄 %s\n', analysisContents(i).name);
            end
        end
        
        % Check for NanionDataExtractor.m specifically
        if exist('SRC/analysis/NanionDataExtractor.m', 'file')
            fprintf('✓ NanionDataExtractor.m file found\n');
        else
            fprintf('❌ NanionDataExtractor.m file NOT found\n');
            fprintf('   → You need to save the NanionDataExtractor class as SRC/analysis/NanionDataExtractor.m\n');
        end
        
    else
        fprintf('❌ SRC/analysis directory does NOT exist\n');
        fprintf('   → Create directory: mkdir(''SRC/analysis'')\n');
    end
    
else
    fprintf('❌ SRC directory does NOT exist\n');
    fprintf('   → Create directory structure first\n');
end

% Check 3: MATLAB path
fprintf('\n=== MATLAB PATH CHECK ===\n');
currentPath = path;
if contains(currentPath, 'SRC/analysis')
    fprintf('✓ SRC/analysis is in MATLAB path\n');
else
    fprintf('❌ SRC/analysis is NOT in MATLAB path\n');
    fprintf('   → Add to path: addpath(''SRC/analysis'')\n');
end

% Check 4: Existing classes
fprintf('\n=== EXISTING CLASSES CHECK ===\n');
try
    config = NanionConfig();
    fprintf('✓ NanionConfig loads correctly\n');
catch
    fprintf('❌ NanionConfig has issues\n');
end

try
    logger = NanionLogger(NanionConfig());
    fprintf('✓ NanionLogger loads correctly\n');
catch
    fprintf('❌ NanionLogger has issues\n');
end

% Check 5: Try to load NanionDataExtractor
fprintf('\n=== NANIONDATAEXTRACTOR TEST ===\n');
try
    % First add path
    addpath('SRC/analysis');
    
    % Try to create instance
    config = NanionConfig();
    logger = NanionLogger(config);
    extractor = NanionDataExtractor(config, logger);
    fprintf('✓ NanionDataExtractor loads successfully!\n');
    
catch ME
    fprintf('❌ NanionDataExtractor failed to load: %s\n', ME.message);
    
    if contains(ME.message, 'Undefined function')
        fprintf('   → File likely not saved or not in correct location\n');
        fprintf('   → Make sure you saved the class as: SRC/analysis/NanionDataExtractor.m\n');
    elseif contains(ME.message, 'constructor')
        fprintf('   → File exists but has syntax errors\n');
        fprintf('   → Check the class file for MATLAB syntax issues\n');
    else
        fprintf('   → Other error: %s\n', ME.message);
    end
end

fprintf('\n=== SETUP RECOMMENDATIONS ===\n');
fprintf('1. Create directory: mkdir(''SRC/analysis'')\n');
fprintf('2. Save NanionDataExtractor.m in SRC/analysis/\n');
fprintf('3. Add to path: addpath(''SRC/analysis'')\n');
fprintf('4. Test again with: phase2_integration_test()\n');

end