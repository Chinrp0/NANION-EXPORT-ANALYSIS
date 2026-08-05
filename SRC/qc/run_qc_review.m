function run_qc_review(storeDir, configPath)
    %RUN_QC_REVIEW Standalone QC review of already-analyzed results.
    %   Loads the review bundles saved by a 'standalone'-mode pipeline run
    %   (<storeDir>/qc_review_bundles/*.mat) plus the persisted decision store,
    %   launches the review app for each file in turn, and saves the updated
    %   decisions. Re-running the pipeline afterwards applies those overrides.
    %
    %   run_qc_review()               % prompts for the output/store directory
    %   run_qc_review(storeDir)       % uses default config
    %   run_qc_review(storeDir, cfg)  % explicit config file

    if nargin < 1 || isempty(storeDir)
        storeDir = uigetdir(pwd, 'Select the analysis output directory (QC store)');
        if isequal(storeDir, 0)
            fprintf('Cancelled.\n');
            return;
        end
    end
    if nargin < 2
        configPath = [];
    end

    % Ensure classes are on the path (mirror pipeline path setup)
    thisDir = fileparts(mfilename('fullpath'));
    srcRoot = fileparts(thisDir);
    if exist('setup_nanion_paths', 'file')
        setup_nanion_paths();
    else
        addpath(genpath(srcRoot));
    end

    config = NanionConfig(configPath);
    logger = NanionLogger(config);

    bundleDir = fullfile(storeDir, 'qc_review_bundles');
    listing = dir(fullfile(bundleDir, '*_qc_bundle.mat'));
    if isempty(listing)
        error('run_qc_review:NoBundles', ...
            'No review bundles found in %s. Run the pipeline in standalone review mode first.', bundleDir);
    end

    session = QCReviewSession(config, logger);
    session.load(storeDir);

    fprintf('QC review: %d file bundle(s) found in %s\n', numel(listing), bundleDir);

    for i = 1:numel(listing)
        S = load(fullfile(listing(i).folder, listing(i).name), 'bundle');
        bundle = S.bundle;
        fprintf('Reviewing %d/%d: %s\n', i, numel(listing), bundle.fileName);

        session.ingestAssessment(bundle.assessedData);
        app = NanionQCReviewApp(config, logger, session, ...
            bundle.assessedData, bundle.fittedData);
        app.waitForCompletion();
        session.save(storeDir);
    end

    csvPath = fullfile(storeDir, 'qc_decisions.csv');
    session.exportCSV(csvPath);
    fprintf('✓ Review complete. Decisions saved to %s\n', storeDir);
    fprintf('  Re-run the pipeline (same output dir) to apply these decisions.\n');
end
