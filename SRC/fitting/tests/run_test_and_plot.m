function run_test_and_plot()
    %RUN_TEST_AND_PLOT Run Boltzmann fitting test and immediately plot results
    %   Combines test_boltzmann_fitting + plot_test_results in one script
    
    fprintf('=== BOLTZMANN TEST & PLOT ===\n\n');
    
    % Step 1: Run test
    fprintf('Step 1: Running Boltzmann fitting test...\n');
    results = test_boltzmann_fitting();
    
    if isempty(results)
        fprintf('No results generated. Exiting.\n');
        return;
    end
    
    fprintf('\n');
    
    % Step 2: Plot results
    fprintf('Step 2: Generating plots...\n');
    plot_test_results();
    
    fprintf('\n=== COMPLETE ===\n');
    fprintf('✓ Testing complete\n');
    fprintf('✓ Plots generated\n');
    fprintf('✓ Results saved in workspace as "results"\n');
end
