classdef NanionSummaryTableBuilder < handle
    %NANIONSUMMARYTABLEBUILDER Build comprehensive summary tables
    %   Creates one row per well PER IV with ~45 columns
    %   Combines filteredData, fittedData, and metadata
    
    properties (Access = private)
        config
        logger
    end
    
    methods
        function obj = NanionSummaryTableBuilder(config, logger)
            obj.config = config;
            obj.logger = logger;
        end
        
        function summaryTable = buildSummaryTable(obj, filteredData, fittedData, fileName)
            %BUILDSUMMARYTABLE Create comprehensive one-row-per-well-per-IV table
            %   Inputs:
            %     filteredData - from NanionDataExtractor after filtering + statistics
            %     fittedData - from NanionBoltzmannFitter
            %     fileName - original Excel file name
            %   Output:
            %     summaryTable - MATLAB table with ~45 columns
            
            obj.logger.logInfo('Building summary table (one row per well per IV)...');
            
            protocolType = filteredData.protocolInfo.type;
            numWells = filteredData.numWellsPassed;
            measurements = filteredData.measurements;
            ivFields = fieldnames(measurements);
            numIVs = length(ivFields);
            
            % Pre-allocate cell arrays for all columns
            totalRows = numWells * numIVs;
            
            % Initialize all column arrays
            rowData = obj.initializeColumns(totalRows, protocolType);
            
            % Populate table row by row
            rowIdx = 0;
            for wellIdx = 1:numWells
                wellID = filteredData.wellIDs(wellIdx);
                cellType = filteredData.wellMetadata.cellType(wellIdx);
                cellConc = filteredData.wellMetadata.cellConcentration(wellIdx);
                
                for ivIdx = 1:numIVs
                    rowIdx = rowIdx + 1;
                    ivName = ivFields{ivIdx};
                    ivNumber = ivIdx;
                    
                    % Extract data for this well and IV
                    ivData = measurements.(ivName);
                    stats = ivData.statistics;
                    
                    % Get Boltzmann fit parameters
                    fitParams = obj.extractFitParams(fittedData, wellIdx, ivName);
                    
                    % Populate row
                    obj.populateRow(rowData, rowIdx, ...
                        wellID, fileName, protocolType, ivNumber, ...
                        cellType, cellConc, ...
                        ivData.compound(wellIdx), ivData.concentration(wellIdx), ...
                        stats, fitParams, wellIdx, ...
                        filteredData.protocolInfo);
                end
            end
            
            % Convert to MATLAB table
            summaryTable = obj.createTable(rowData, protocolType);
            
            obj.logger.logInfo(sprintf('✓ Summary table created: %d rows × %d columns', ...
                height(summaryTable), width(summaryTable)));
        end
    end
    
    methods (Access = private)
        function rowData = initializeColumns(obj, totalRows, protocolType)
            %INITIALIZECOLUMNS Pre-allocate all column arrays
            
            % 1. Identification (8 columns)
            rowData.Well_ID = cell(totalRows, 1);
            rowData.File_Name = cell(totalRows, 1);
            rowData.Protocol_Type = cell(totalRows, 1);
            rowData.IV_Number = zeros(totalRows, 1);
            rowData.Cell_Type = cell(totalRows, 1);
            rowData.Cell_Concentration = cell(totalRows, 1);
            rowData.Compound = cell(totalRows, 1);
            rowData.Concentration_uM = zeros(totalRows, 1);
            
            % 2. Quality Metrics - Statistics (12 columns)
            rowData.Series_R_Mean_MOhm = zeros(totalRows, 1);
            rowData.Series_R_Min_MOhm = zeros(totalRows, 1);
            rowData.Series_R_Max_MOhm = zeros(totalRows, 1);
            rowData.Series_R_Std_MOhm = zeros(totalRows, 1);
            
            rowData.Seal_R_Mean_GOhm = zeros(totalRows, 1);
            rowData.Seal_R_Min_GOhm = zeros(totalRows, 1);
            rowData.Seal_R_Max_GOhm = zeros(totalRows, 1);
            rowData.Seal_R_Std_GOhm = zeros(totalRows, 1);
            
            rowData.Capacitance_Mean_pF = zeros(totalRows, 1);
            rowData.Capacitance_Min_pF = zeros(totalRows, 1);
            rowData.Capacitance_Max_pF = zeros(totalRows, 1);
            rowData.Capacitance_Std_pF = zeros(totalRows, 1);
            
            % 3. Current Metrics (8 columns)
            rowData.Peak_Current_Mean_pA = zeros(totalRows, 1);
            rowData.Peak_Current_Min_pA = zeros(totalRows, 1);
            rowData.Peak_Current_Max_pA = zeros(totalRows, 1);
            rowData.Peak_Current_Std_pA = zeros(totalRows, 1);
            
            rowData.Current_Density_Mean_pA_per_pF = zeros(totalRows, 1);
            rowData.Current_Density_Min_pA_per_pF = zeros(totalRows, 1);
            rowData.Current_Density_Max_pA_per_pF = zeros(totalRows, 1);
            rowData.Current_Density_Std_pA_per_pF = zeros(totalRows, 1);
            
            % 4. Conductance Stats (6 columns, activation only)
            if strcmp(protocolType, 'activation')
                rowData.Conductance_Raw_Min_nS = zeros(totalRows, 1);
                rowData.Conductance_Raw_Max_nS = zeros(totalRows, 1);
                rowData.Conductance_Raw_Range_nS = zeros(totalRows, 1);
                rowData.Conductance_Raw_Mean_nS = zeros(totalRows, 1);
                rowData.Conductance_Normalized_at_Vmax = zeros(totalRows, 1);
                rowData.Conductance_Normalized_at_Vmin = zeros(totalRows, 1);
            end
            
            % 5. Boltzmann Fit Parameters (9 columns)
            rowData.V_mid_mV = zeros(totalRows, 1);
            rowData.Slope_k_mV = zeros(totalRows, 1);
            rowData.z_a_elementary_charges = zeros(totalRows, 1);
            rowData.V_min_fit = zeros(totalRows, 1);
            rowData.V_max_fit = zeros(totalRows, 1);
            rowData.R_squared = zeros(totalRows, 1);
            rowData.RMSE = zeros(totalRows, 1);
            rowData.Fit_Quality = cell(totalRows, 1);
            rowData.Fit_Converged = zeros(totalRows, 1);  % TRUE/FALSE as 1/0
            
            % 6. Protocol Parameters (3 columns)
            rowData.Temperature_C = zeros(totalRows, 1);
            rowData.Nernst_Potential_mV = zeros(totalRows, 1);
            rowData.Num_Voltage_Steps = zeros(totalRows, 1);
        end
        
        function populateRow(obj, rowData, rowIdx, ...
                wellID, fileName, protocolType, ivNumber, ...
                cellType, cellConc, compound, concentration, ...
                stats, fitParams, wellIdx, protocolInfo)
            %POPULATEROW Fill in data for one row
            
            % DEBUG: Log first row to verify data structure
            if rowIdx == 1
                obj.logger.logDebug(sprintf('DEBUG: First row population - wellIdx=%d, ivNumber=%d', wellIdx, ivNumber));
                if isfield(stats, 'seriesR') && isfield(stats.seriesR, 'mean')
                    obj.logger.logDebug(sprintf('  Series R mean size: [%d × %d], value at index %d: %.3f', ...
                        size(stats.seriesR.mean, 1), size(stats.seriesR.mean, 2), wellIdx, stats.seriesR.mean(wellIdx)));
                else
                    obj.logger.logWarning('  WARNING: stats.seriesR.mean not found!');
                end
            end
            
            % 1. Identification
            rowData.Well_ID{rowIdx} = char(wellID);
            rowData.File_Name{rowIdx} = char(fileName);
            rowData.Protocol_Type{rowIdx} = char(protocolType);
            rowData.IV_Number(rowIdx) = ivNumber;
            rowData.Cell_Type{rowIdx} = char(cellType);
            rowData.Cell_Concentration{rowIdx} = char(cellConc);
            rowData.Compound{rowIdx} = char(compound);
            rowData.Concentration_uM(rowIdx) = concentration;
            
            % 2. Quality Metrics Statistics
            % FIX: stats arrays are [numWells × 1], indexed directly by wellIdx
            rowData.Series_R_Mean_MOhm(rowIdx) = obj.safeExtract(stats.seriesR.mean, wellIdx);
            rowData.Series_R_Min_MOhm(rowIdx) = obj.safeExtract(stats.seriesR.min, wellIdx);
            rowData.Series_R_Max_MOhm(rowIdx) = obj.safeExtract(stats.seriesR.max, wellIdx);
            rowData.Series_R_Std_MOhm(rowIdx) = obj.safeExtract(stats.seriesR.std, wellIdx);
            
            rowData.Seal_R_Mean_GOhm(rowIdx) = obj.safeExtract(stats.sealR.mean, wellIdx);
            rowData.Seal_R_Min_GOhm(rowIdx) = obj.safeExtract(stats.sealR.min, wellIdx);
            rowData.Seal_R_Max_GOhm(rowIdx) = obj.safeExtract(stats.sealR.max, wellIdx);
            rowData.Seal_R_Std_GOhm(rowIdx) = obj.safeExtract(stats.sealR.std, wellIdx);
            
            rowData.Capacitance_Mean_pF(rowIdx) = obj.safeExtract(stats.capacitance.mean, wellIdx);
            rowData.Capacitance_Min_pF(rowIdx) = obj.safeExtract(stats.capacitance.min, wellIdx);
            rowData.Capacitance_Max_pF(rowIdx) = obj.safeExtract(stats.capacitance.max, wellIdx);
            rowData.Capacitance_Std_pF(rowIdx) = obj.safeExtract(stats.capacitance.std, wellIdx);
            
            % 3. Current Metrics
            rowData.Peak_Current_Mean_pA(rowIdx) = obj.safeExtract(stats.peakCurrent.mean, wellIdx);
            rowData.Peak_Current_Min_pA(rowIdx) = obj.safeExtract(stats.peakCurrent.min, wellIdx);
            rowData.Peak_Current_Max_pA(rowIdx) = obj.safeExtract(stats.peakCurrent.max, wellIdx);
            rowData.Peak_Current_Std_pA(rowIdx) = obj.safeExtract(stats.peakCurrent.std, wellIdx);
            
            rowData.Current_Density_Mean_pA_per_pF(rowIdx) = obj.safeExtract(stats.currentDensity.mean, wellIdx);
            rowData.Current_Density_Min_pA_per_pF(rowIdx) = obj.safeExtract(stats.currentDensity.min, wellIdx);
            rowData.Current_Density_Max_pA_per_pF(rowIdx) = obj.safeExtract(stats.currentDensity.max, wellIdx);
            rowData.Current_Density_Std_pA_per_pF(rowIdx) = obj.safeExtract(stats.currentDensity.std, wellIdx);
            
            % 4. Conductance Stats (activation only)
            if strcmp(protocolType, 'activation')
                if isfield(stats, 'conductance_raw')
                    rowData.Conductance_Raw_Min_nS(rowIdx) = obj.safeExtract(stats.conductance_raw.min, wellIdx);
                    rowData.Conductance_Raw_Max_nS(rowIdx) = obj.safeExtract(stats.conductance_raw.max, wellIdx);
                    rowData.Conductance_Raw_Mean_nS(rowIdx) = obj.safeExtract(stats.conductance_raw.mean, wellIdx);
                    rowData.Conductance_Raw_Range_nS(rowIdx) = obj.safeExtract(stats.conductance_raw.max, wellIdx) - obj.safeExtract(stats.conductance_raw.min, wellIdx);
                else
                    rowData.Conductance_Raw_Min_nS(rowIdx) = NaN;
                    rowData.Conductance_Raw_Max_nS(rowIdx) = NaN;
                    rowData.Conductance_Raw_Mean_nS(rowIdx) = NaN;
                    rowData.Conductance_Raw_Range_nS(rowIdx) = NaN;
                end
                
                % Normalized conductance at extremes (placeholder for now)
                rowData.Conductance_Normalized_at_Vmax(rowIdx) = NaN;
                rowData.Conductance_Normalized_at_Vmin(rowIdx) = NaN;
            end
            
            % 5. Boltzmann Fit Parameters
            if ~isempty(fitParams) && fitParams.converged
                rowData.V_mid_mV(rowIdx) = fitParams.V_mid;
                rowData.Slope_k_mV(rowIdx) = fitParams.k;
                rowData.z_a_elementary_charges(rowIdx) = fitParams.z_a;
                rowData.V_min_fit(rowIdx) = fitParams.V_min;
                rowData.V_max_fit(rowIdx) = fitParams.V_max;
                rowData.R_squared(rowIdx) = fitParams.R2;
                rowData.RMSE(rowIdx) = fitParams.RMSE;
                rowData.Fit_Quality{rowIdx} = char(fitParams.quality);
                rowData.Fit_Converged(rowIdx) = 1;
            else
                rowData.V_mid_mV(rowIdx) = NaN;
                rowData.Slope_k_mV(rowIdx) = NaN;
                rowData.z_a_elementary_charges(rowIdx) = NaN;
                rowData.V_min_fit(rowIdx) = NaN;
                rowData.V_max_fit(rowIdx) = NaN;
                rowData.R_squared(rowIdx) = NaN;
                rowData.RMSE(rowIdx) = NaN;
                if ~isempty(fitParams)
                    rowData.Fit_Quality{rowIdx} = char(fitParams.quality);
                else
                    rowData.Fit_Quality{rowIdx} = 'Failed';
                end
                rowData.Fit_Converged(rowIdx) = 0;
            end
            
            % 6. Protocol Parameters
            rowData.Temperature_C(rowIdx) = obj.config.temperature;
            rowData.Nernst_Potential_mV(rowIdx) = obj.config.nernstPotential;
            rowData.Num_Voltage_Steps(rowIdx) = protocolInfo.numSweeps;
        end
        
        function fitParams = extractFitParams(obj, fittedData, wellIdx, ivName)
            %EXTRACTFITPARAMS Extract fit parameters for specific well and IV
            
            if isempty(fittedData) || wellIdx > length(fittedData.wells)
                fitParams = [];
                return;
            end
            
            well = fittedData.wells(wellIdx);
            
            % Extract IV-specific fit (iv1, iv2, etc.)
            if strcmp(ivName, 'iv1') && ~isempty(well.iv1)
                ivFit = well.iv1;
            elseif strcmp(ivName, 'iv2') && ~isempty(well.iv2)
                ivFit = well.iv2;
            elseif strcmp(ivName, 'iv3') && isfield(well, 'iv3') && ~isempty(well.iv3)
                ivFit = well.iv3;
            elseif strcmp(ivName, 'iv4') && isfield(well, 'iv4') && ~isempty(well.iv4)
                ivFit = well.iv4;
            else
                fitParams = [];
                return;
            end
            
            % Package fit parameters with quality
            fitParams = ivFit.fitParams;
            fitParams.quality = ivFit.fitQuality;
        end
        
        function summaryTable = createTable(obj, rowData, protocolType)
            %CREATETABLE Convert struct of arrays to MATLAB table
            
            % Convert to table
            if strcmp(protocolType, 'activation')
                summaryTable = struct2table(rowData);
            else
                % Inactivation: remove conductance columns
                conductanceFields = {'Conductance_Raw_Min_nS', 'Conductance_Raw_Max_nS', ...
                    'Conductance_Raw_Range_nS', 'Conductance_Raw_Mean_nS', ...
                    'Conductance_Normalized_at_Vmax', 'Conductance_Normalized_at_Vmin'};
                
                for i = 1:length(conductanceFields)
                    if isfield(rowData, conductanceFields{i})
                        rowData = rmfield(rowData, conductanceFields{i});
                    end
                end
                
                summaryTable = struct2table(rowData);
            end
            
            % Convert logical to categorical for better Excel export
            if ismember('Fit_Converged', summaryTable.Properties.VariableNames)
                summaryTable.Fit_Converged = categorical(summaryTable.Fit_Converged, [0 1], {'FALSE', 'TRUE'});
            end
        end
        
        function value = safeExtract(obj, array, index)
            %SAFEEXTRACT Safely extract value from array with bounds checking
            %   Returns NaN if index out of bounds or array is empty/invalid
            
            try
                if isempty(array) || index < 1 || index > numel(array)
                    value = NaN;
                else
                    value = array(index);
                    % If extracted value is NaN or Inf, keep it as-is
                    if ~isfinite(value)
                        % Already NaN or Inf, no change needed
                    end
                end
            catch
                value = NaN;
            end
        end
    end
end
