classdef DBSgram_MainUI < handle
    % DBSgram_MainUI - Unified Multi-Symptom Titration Framework Workspace
    
    % PUBLIC FRAMEWORK CORE DATA STORES
    properties  
        WorkspaceData       
        
        % Pipeline Execution Lifecycle Flags
        IsDataLoaded        logical = false
        IsDataMapped        logical = false
        IsTimeAligned       logical = false
        IsQualityAudited    logical = false
        IsLfpCleaned        logical = false
        IsKinIntervaled     logical = false
        IsClinicalMapped    logical = false
    end
    
    % PRIVATE GRAPHICAL ENGINE COMPONENT INSTANCES
    properties (Access = private)
        UIFigure            matlab.ui.Figure
        MainGrid            matlab.ui.container.GridLayout
        ControlsGrid        matlab.ui.container.GridLayout
        
        % Panel 1: Data Loading and Temporal Alignment
        PanelLoading        matlab.ui.container.Panel
        BtnLoadData         matlab.ui.control.Button
        BtnTimeAlign        matlab.ui.control.Button
        
        % Panel 2: Data Pre-Processing and Quality Audit
        PanelPreProcessing  matlab.ui.container.Panel
        BtnTestDataQual     matlab.ui.control.Button
        BtnCleanECG         matlab.ui.control.Button
        BtnKinEvaluation    matlab.ui.control.Button
        
        % Panel 3: Clinical Metrics & Reports Generation
        PanelReporting      matlab.ui.container.Panel
        BtnClinicalOver     matlab.ui.control.Button
        BtnGenerateDBS      matlab.ui.control.Button
        
        % Full-Width Lower Notification Console Register
        LblLog              matlab.ui.control.Label
        TxtGlobalLog        matlab.ui.control.TextArea
        BtnLogMapping       matlab.ui.control.Button
    end
    
    % PUBLIC LIFECYCLE MANAGEMENT METHODS
    methods
        function obj = DBSgram_MainUI()
            DBSgram_setup();
            % Safeguard structural master fields inside RAM on startup
            obj.WorkspaceData = struct();
                        
            buildMainInterface(obj);
            updateStatus(obj, 'DBSgram Framework Suite initialized successfully.');
            refreshStateEngine(obj);
            
            % Keep the standalone .exe process open until the main UI is closed
            if isdeployed
                waitfor(obj.UIFigure);
            end

        end
        
        function updateStatus(obj, textString)
            % Appends incoming text frames directly to the full-width console log register
            timestamp = datestr(now, 'HH:MM:SS');
            obj.TxtGlobalLog.Value = [sprintf('[%s] %s', timestamp, textString); obj.TxtGlobalLog.Value];
            drawnow;
        end
        function refreshStateEngine(obj)
            % Evaluates pipeline flags to dynamically toggle workflow button permissions
            hasData = obj.IsDataLoaded;
            
            % Panel 1 Visibility Control Gateways (All disable once Time Alignment is locked)
            obj.BtnLoadData.Enable      = ~obj.IsTimeAligned;
            obj.BtnLogMapping.Enable    = hasData && ~obj.IsTimeAligned;
            obj.BtnTimeAlign.Enable     = hasData && obj.IsDataMapped && ~obj.IsTimeAligned;
            
            % Panel 2 Visibility Control Gateways
            obj.BtnTestDataQual.Enable  = hasData && obj.IsTimeAligned;
            obj.BtnCleanECG.Enable      = hasData && obj.IsTimeAligned;
            obj.BtnKinEvaluation.Enable = hasData && obj.IsQualityAudited;
            
            % Panel 3 Visibility Control Gateways
            obj.BtnClinicalOver.Enable  = hasData && obj.IsQualityAudited;
            obj.BtnGenerateDBS.Enable   = hasData && obj.IsQualityAudited && obj.IsKinIntervaled && obj.IsClinicalMapped;
            
            % Dynamic Green Palette Feedback for Processed States
            if obj.IsDataLoaded,        obj.BtnLoadData.BackgroundColor      = [0.75 0.88 0.75]; end
            if obj.IsDataMapped,        obj.BtnLogMapping.BackgroundColor    = [0.75 0.88 0.75]; end
            if obj.IsTimeAligned
                obj.BtnTimeAlign.BackgroundColor = [0.75 0.88 0.75];
                obj.BtnTimeAlign.Text = '🔗 Temporal Alignment Visualization (Locked)';
            end
            if obj.IsQualityAudited,    obj.BtnTestDataQual.BackgroundColor  = [0.75 0.88 0.75]; end
            if obj.IsLfpCleaned,        obj.BtnCleanECG.BackgroundColor      = [0.75 0.88 0.75]; end
            if obj.IsKinIntervaled,     obj.BtnKinEvaluation.BackgroundColor = [0.75 0.88 0.75]; end
            if obj.IsClinicalMapped,    obj.BtnClinicalOver.BackgroundColor  = [0.75 0.88 0.75]; end
            if obj.BtnGenerateDBS.Enable
                obj.updateStatus('Finalized Data Ingestion and Data Quality Checks. The generation of the DBSgram is now enabled!')
            end
        end
    end
    
    % PRIVATE BACKEND & GRAPHICAL ENGINE HELPER METHODS
    methods (Access = private)
        function buildMainInterface(obj)
            screensize = get(groot,'ScreenSize');
            w = screensize(3) * 0.9; h = screensize(4) * 0.85; 
            x = (screensize(3)-w)/2; y = (screensize(4)-h)/2;

            obj.UIFigure = uifigure('Name', 'DBSgram Titration Preprocessing & Reporting Framework Suite', ...
                                   'Position', [x, y, w, h]);
            
            % Stacked vertical container grid layout definition
            obj.MainGrid = uigridlayout(obj.UIFigure, [3, 1]);
            % Bumped row 2 height from 22 to 30 to comfortably accommodate the new button
            obj.MainGrid.RowHeight = {'1x', 22, 130};
            obj.MainGrid.Padding = [12 12 12 12]; obj.MainGrid.RowSpacing = 8;
            
            obj.ControlsGrid = uigridlayout(obj.MainGrid, [1, 3]);
            obj.ControlsGrid.ColumnWidth = {'1x', '1x', '1x'};
            obj.ControlsGrid.ColumnSpacing = 15; obj.ControlsGrid.Padding = [0 0 0 0];
            
            % --- PANEL 1: DATA LOADING AND TEMPORAL ALIGNMENT ---
            obj.PanelLoading = uipanel(obj.ControlsGrid, 'Title', '1. Data Loading and Temporal Alignment');
            c1Grid = uigridlayout(obj.PanelLoading, [3, 1]);
            c1Grid.RowHeight = {'1x', '1x', '1x'}; c1Grid.Padding = [10 12 10 12];
            
            % 1. Loading Electrophysiology and Kinematics data
            obj.BtnLoadData = uibutton(c1Grid, 'Text', '📂 Loading Electrophysiology and Kinematics data', ...
                'FontWeight', 'bold', 'ButtonPushedFcn', @(src, event) obj.cbUnifiedDataIngestion(src, event));
            
            % 2. Log Mapping
            obj.BtnLogMapping = uibutton(c1Grid, 'Text', '📝 LFP-to-Wearables Task Mapping', ...
                'FontWeight', 'bold', 'ButtonPushedFcn', @(src, event) obj.cbLogMapping(src, event)); % Make sure cbLogMapping exists
            
            % 3. Allignment Visualization
            obj.BtnTimeAlign = uibutton(c1Grid, 'Text', '🔗 Temporal Alignment Visualization', ...
                'FontWeight', 'bold', 'ButtonPushedFcn', @(src, event) obj.cbLaunchFineAlignment(src, event));
            
            % --- PANEL 2: DATA PRE-PROCESSING AND QUALITY AUDIT ---
            obj.PanelPreProcessing = uipanel(obj.ControlsGrid, 'Title', '2. Data Pre-Processing and Quality Audit');
            c2Grid = uigridlayout(obj.PanelPreProcessing, [3, 1]);
            c2Grid.RowHeight = {'1x', '1x', '1x'}; c2Grid.Padding = [10 12 10 12];
            
            obj.BtnTestDataQual = uibutton(c2Grid, 'Text', '🛡️ Audit Channel Data Inclusion', ...
                'FontWeight', 'bold', 'ButtonPushedFcn', @(src, event) obj.cbLaunchDataInclusionAudit(src, event));
            
            obj.BtnCleanECG = uibutton(c2Grid, 'Text', '❤️ Remove Cardiac ECG SVD Artifacts', ...
                'FontWeight', 'bold', 'ButtonPushedFcn', @(src, event) obj.cbLaunchEcgWorkspace(src, event));
            
            obj.BtnKinEvaluation = uibutton(c2Grid, 'Text', '✂️ Select Kinematic Evaluation Periods', ...
                'FontWeight', 'bold', 'ButtonPushedFcn', @(src, event) obj.cbKinematicsAnalysis(src, event));
            
            % --- PANEL 3: CLINICAL METRICS & REPORTS GENERATION ---
            obj.PanelReporting = uipanel(obj.ControlsGrid, 'Title', '3. Clinical Metrics & Reports Generation');
            c3Grid = uigridlayout(obj.PanelReporting, [3, 1]);
            c3Grid.Padding = [10 12 10 12]; c3Grid.RowSpacing = 10; c3Grid.RowHeight = {'1x', '1x', '1x'};
            
            obj.BtnClinicalOver = uibutton(c3Grid, 'Text', '📋 Log Clinical Titration UPDRS Scores', ...
                'FontWeight', 'bold', 'ButtonPushedFcn', @(src, event) obj.cbLaunchClinicalOverview(src, event));
            
            % Expanded multi-row report generator button
            obj.BtnGenerateDBS = uibutton(c3Grid, 'Text', '🖨️ Compile Stacked DBSgram A4 Reports', ...
                'BackgroundColor', [0.85 0.92 1.0], 'FontWeight', 'bold', 'FontSize', 13);
            obj.BtnGenerateDBS.Layout.Row = [2, 3]; obj.BtnGenerateDBS.Layout.Column = 1;
            obj.BtnGenerateDBS.ButtonPushedFcn = @(src, event) obj.cbCompileFinalDBSgram(src, event);
            
            % --- SYSTEM LOG TERMINAL LABEL & CONSOLE ---
            obj.LblLog = uilabel(obj.MainGrid, 'Text', 'System Log', 'FontWeight', 'bold', ...
                'FontSize', 12, 'FontColor', [0.2 0.2 0.2]);
            
            % Full width log terminal below
            obj.TxtGlobalLog = uitextarea(obj.MainGrid, 'Editable', 'off', ...
                'FontName', 'Consolas', 'FontSize', 11, 'BackgroundColor', [0.98 0.98 0.98]);
        end
        
        function cbUnifiedDataIngestion(obj, ~, ~)
            % =========================================================================
            % MASTER DIRECTORY SELECTION (JSON + CSVs)
            % =========================================================================
            folderPath = uigetdir('', 'Select the folder containing BOTH the LFP .json and Wearables .csv files');
            if folderPath == 0
                obj.updateStatus('⚠️ Loading skipped by user choice.');
                return; 
            end

            % --- Save source directory path for downstream UPDRS.xlsx lookup ---
            obj.WorkspaceData.SourceFolderPath = folderPath;
            
            jsonFiles = dir(fullfile(folderPath, '*.json'));
            if isempty(jsonFiles)
                uialert(obj.UIFigure, 'No .json LFP file found in the selected directory.', 'File Error');
                return;
            end
            
            jsonFileName = jsonFiles(1).name;
            jsonFilePath = fullfile(folderPath, jsonFileName);
            dataPathname = [folderPath filesep]; 
            
            % =========================================================================
            % PHASE 1: ELECTROPHYSIOLOGY IMPORT MODULE
            % =========================================================================
            obj.updateStatus('Initializing DBScope parsing sequence...');
            
            try
                patient_ctx = NCNPERCEPT_FILE;
                [parsing_status, ~] = patient_ctx.loadFile(dataPathname, jsonFileName);
                
                if parsing_status == 0
                    error('Failed to parse the JSON file using NCNPERCEPT_FILE.loadFile.');
                end
                
                obj.WorkspaceData.StreamingObj = patient_ctx.streaming_obj;
                obj.WorkspaceData.GroupsObj    = patient_ctx.parameters.groups.final;
                obj.WorkspaceData.SurveyObj    = patient_ctx.survey_obj;
                obj.WorkspaceData.SetupObj     = patient_ctx.setup_obj;
                obj.WorkspaceData.PatientKey   = string(patient_ctx.parameters.patient_information.patient_id);
                obj.WorkspaceData.SessionDate  = patient_ctx.parameters.session_date;
                obj.WorkspaceData.SessionDate.Format = 'dd-MMM-yyyy';
                
                obj.WorkspaceData.BrainSenseLfpObj = [];
                try
                    temp_raw_json_struct = jsondecode(fileread(jsonFilePath));
                    
                    % 1. Extract BrainSense LFP
                    if isfield(temp_raw_json_struct, 'BrainSenseLfp')
                        obj.WorkspaceData.BrainSenseLfpObj = temp_raw_json_struct.BrainSenseLfp;
                        obj.updateStatus('✔ Extracted raw BrainSenseLfp snapshots from JSON file.');
                    end
                    
                    % 2. Extract Program Settings
                    if isfield(temp_raw_json_struct, 'Groups') && isfield(temp_raw_json_struct.Groups, 'Final')
                        num_groups = numel(temp_raw_json_struct.Groups.Final);
                        for i = 1:num_groups
                            obj.WorkspaceData.GroupsObj(i).("ProgrammSettings") = temp_raw_json_struct.Groups.Final(i).ProgramSettings;
                        end
                        obj.updateStatus(sprintf('✔ Extracted Program Settings for %d Group(s) from JSON file.', num_groups));
                    end
                    
                    % 3. Extract Patient Demographics & Device Info
                    if isfield(temp_raw_json_struct, 'PatientInformation') && isfield(temp_raw_json_struct.PatientInformation, 'Initial')
                        p_info = temp_raw_json_struct.PatientInformation.Initial;
                        if isfield(p_info, 'PatientFirstName') && isfield(p_info, 'PatientLastName')
                            obj.WorkspaceData.PatientName = string(p_info.PatientFirstName) + " " + string(p_info.PatientLastName);
                        end
                        if isfield(p_info, 'PatientGender')
                            raw_gender = string(p_info.PatientGender);
                            gender_parts = split(raw_gender, ".");
                            if numel(gender_parts) > 1
                                obj.WorkspaceData.PatientSex = gender_parts(end);
                            else
                                obj.WorkspaceData.PatientSex = raw_gender;
                            end
                        end
                        
                        % --- NEW: ROBUST DOB PARSING ---
                        if isfield(p_info, 'PatientDateOfBirth')
                            try
                                raw_dob = string(p_info.PatientDateOfBirth);
                                % Removes the 'T00:00:00Z' artifact natively found in Medtronic JSONs
                                clean_dob = extractBefore(raw_dob, "T"); 
                                if ismissing(clean_dob), clean_dob = raw_dob; end
                                obj.WorkspaceData.PatientDOB = datetime(clean_dob, 'InputFormat', 'yyyy-MM-dd');
                            catch
                                % Failsafe if format is completely mangled
                            end
                        end
                    end
                    
                    if isfield(temp_raw_json_struct, 'DeviceInformation') && isfield(temp_raw_json_struct.DeviceInformation, 'Initial')
                        d_info = temp_raw_json_struct.DeviceInformation.Initial;
                        dev_name = ""; dev_mod = "";
                        if isfield(d_info, 'Neurostimulator')
                            dev_name = string(d_info.Neurostimulator);
                        end
                        if isfield(d_info, 'NeurostimulatorModel')
                            dev_mod = string(d_info.NeurostimulatorModel);
                        end
                        obj.WorkspaceData.DeviceModel = dev_name + " (" + dev_mod + ")";
                    end
                    
                    % --- NEW: AUTOMATIC AGE CALCULATION ---
                    if isfield(obj.WorkspaceData, 'PatientDOB') && isfield(obj.WorkspaceData, 'SessionDate')
                        try
                            % Calculates total calendar years between DOB and Session Date
                            age_cal = between(obj.WorkspaceData.PatientDOB, obj.WorkspaceData.SessionDate, 'Years');
                            obj.WorkspaceData.PatientAge = char(string(calyears(age_cal)));
                        catch
                            obj.WorkspaceData.PatientAge = "N/A";
                        end
                    else
                        obj.WorkspaceData.PatientAge = "N/A";
                    end
                    
                    obj.updateStatus('✔ Extracted Patient Demographics and Calculated Age.');
                    
                    clear("temp_raw_json_struct");
                catch jsonME
                    warning('DBSgram:JsonParseWarning', 'Could not parse raw JSON: %s', jsonME.message);
                end
                
                obj.updateStatus(sprintf('✔ Loaded LFP Telemetry matrices for Patient %s (%s).', ...
                    obj.WorkspaceData.PatientKey, string(obj.WorkspaceData.SessionDate)));
            catch ME
                uialert(obj.UIFigure, ME.message, 'LFP Ingestion Failure');
                return;
            end
            
            % =========================================================================
            % PHASE 2: WEARABLES IN-MEMORY PARSING ENGINE
            % =========================================================================
            csvFiles = dir(fullfile(folderPath, '*.csv'));
            if isempty(csvFiles)
                obj.updateStatus('⚠️ No Wearables .csv files found in the JSON directory. Wearables loading skipped.');
                return;
            else
                obj.updateStatus(sprintf('Starting high-precision parsing of %d Wearables CSV file(s)...', length(csvFiles)));
                drawnow;
            end
            
            try
                num_files = length(csvFiles);
                filenames = {csvFiles.name};
                
                temp_wearables = []; 
                progress_step = max(1, round(num_files / 4)); 
                
                for f = 1:num_files
                    cleanName = filenames{f};
                    info = strsplit(cleanName, '_');
                    if length(info) >= 4
                        sensorType = string(info{2});
                        rawSymptom = string(info{3});
                        sideStr    = extractBefore(string(info{4}), '.');
                    else
                        continue; 
                    end
                    
                    wearableId = sprintf('%s%s', sensorType, upper(sideStr));
                    
                    if strcmpi(rawSymptom, 'RestingTremor')
                        extractedSymptom = "Tremor";
                    elseif strcmpi(rawSymptom, 'WristRigidity')
                        extractedSymptom = "Rigidity";
                    elseif strcmpi(rawSymptom, 'OpenCloseHand')
                        extractedSymptom = "Bradykinesia";
                    else
                        extractedSymptom = rawSymptom;
                    end
                    
                    rawText = fileread(fullfile(folderPath, cleanName));
                    wearable_start_time = NaT;
                    ts_tokens = regexp(rawText, 'Test_starttime=([^\r\n]+)', 'tokens', 'once');
                    if ~isempty(ts_tokens)
                        clean_ts = strrep(ts_tokens{1}, 'Z', ''); 
                        clean_ts = strrep(clean_ts, '"', '');
                        clean_ts = strtrim(clean_ts);
                        try
                            wearable_start_time = datetime(clean_ts, 'InputFormat', 'yyyy-MM-dd HH:mm:ss.SSSSSS');
                        catch
                            wearable_start_time = datetime(clean_ts);
                        end
                        wearable_start_time.Format = 'yyyy-MM-dd HH:mm:ss.SSS'; 
                    end
                    
                    rawText = regexprep(rawText, '("20\d{2}-\d{2}-\d{2})\r?\n', '$1 ');
                    rawText = strrep(rawText, '"', ''); 
                    
                    dataStartIdx = regexp(rawText, '(?m)^20\d{2}-\d{2}-\d{2}', 'once');
                    if ~isempty(dataStartIdx)
                        dataBlock = rawText(dataStartIdx:end);
                    else
                        lines = strsplit(rawText, '\n');
                        dataStartIndex = 1;
                        for l = 1:min(100, length(lines))
                            tempScan = textscan(lines{l}, '%s %f %f %f %f %f %f', 'Delimiter', ',');
                            if ~isempty(tempScan{2}) && ~isnan(tempScan{2}(1))
                                dataStartIndex = l;
                                break;
                            end
                        end
                        dataBlock = strjoin(lines(dataStartIndex:end), '\n');
                    end
                    
                    dataCells = textscan(dataBlock, '%s %f %f %f %f %f %f %f %f %f %f %f %f', 'Delimiter', ',');
                    if isempty(dataCells) || isempty(dataCells{1}), continue; end
                    
                    raw_time_strings = dataCells{1};
                    raw_time_strings = strrep(raw_time_strings, 'Z', ''); 
                    try
                        dts = datetime(raw_time_strings, 'InputFormat', 'yyyy-MM-dd HH:mm:ss.SSSSSS');
                    catch
                        dts = datetime(raw_time_strings);
                    end
                    dts.Format = 'yyyy-MM-dd HH:mm:ss.SSS'; 
                    
                    ax = dataCells{2}; ay = dataCells{3}; az = dataCells{4};
                    gx = dataCells{5}; gy = dataCells{6}; gz = dataCells{7};
                    fsActual = 50; 
                    
                    diff_dt = [diff(dts); seconds(1)];
                    indx_end_packet = find(diff_dt > milliseconds(1));
                    indx_last = 0;
                    if ~isempty(indx_end_packet)
                        dt_last = dts(indx_end_packet(1)) - seconds(1/fsActual*(indx_end_packet(1) - indx_last));
                        for i = 1:numel(indx_end_packet)
                            delta = (dts(indx_end_packet(i))-dt_last) / (indx_end_packet(i)-indx_last);
                            for sample = 1:indx_end_packet(i)-indx_last-1
                                dts(indx_end_packet(i) - sample) = dt_last + (indx_end_packet(i)-indx_last - sample)*delta;
                            end
                            indx_last = indx_end_packet(i); 
                            dt_last = dts(indx_end_packet(i));
                        end
                    end
                    
                    cleanData = table(dts, ax, ay, az, gx, gy, gz, 'VariableNames', {'time', 'ax', 'ay', 'az', 'gx', 'gy', 'gz'});
                    
                    item = struct();
                    item.wearable_id      = wearableId;
                    item.sampling_freq_Hz = fsActual;
                    item.recording_start  = wearable_start_time;
                    item.time             = dts; 
                    item.data             = cleanData;
                    item.lfp_rec_num      = NaN;
                    item.symptom          = extractedSymptom;
                    
                    if isempty(temp_wearables)
                        temp_wearables = item;
                    else
                        temp_wearables(end+1) = item; %#ok<AGROW>
                    end
                    
                    if mod(f, progress_step) == 0 || f == num_files
                        pct = round((f / num_files) * 100);
                        obj.updateStatus(sprintf('  ⏳ Parsed %d/%d Wearables CSV files (%d%%)...', f, num_files, pct));
                        drawnow limitrate;
                    end
                end
                
                if isempty(temp_wearables)
                    uialert(obj.UIFigure, 'No valid Wearables CSV files could be parsed.', 'Data Error');
                    return;
                end
                
                [~, sortIdx] = sort([temp_wearables.recording_start]);
                temp_wearables = temp_wearables(sortIdx);
                num_parsed_files = numel(temp_wearables);
                
                % =========================================================================
                % STAGE C1: LFP TELEMETRY GAP AUDIT & CORRECTION
                % =========================================================================
                obj.updateStatus('Auditing LFP telemetry packets for Bluetooth dropouts...');
                drawnow;
                
                lfp_data_cell  = obj.WorkspaceData.StreamingObj.streaming_parameters.time_domain.data;
                lfp_time_cell  = obj.WorkspaceData.StreamingObj.streaming_parameters.time_domain.time;
                num_raw_lfp    = numel(lfp_data_cell);
                
                if isfield(obj.WorkspaceData.StreamingObj.streaming_parameters.time_domain, 'fs')
                    lfp_Fs = double(obj.WorkspaceData.StreamingObj.streaming_parameters.time_domain.fs);
                else
                    lfp_Fs = double(obj.WorkspaceData.StreamingObj.streaming_parameters.time_domain.sample_rate);
                end
                
                total_gaps_found = 0;
                
                for rec = 1:num_raw_lfp
                    missing_samples_detected = false;
                    lfp_ticks_ms   = obj.WorkspaceData.StreamingObj.streaming_parameters.time_domain.global_packets_ticks{rec};
                    lfp_ticks_size = obj.WorkspaceData.StreamingObj.streaming_parameters.time_domain.global_packets_size{rec};
                    if isempty(lfp_ticks_ms), continue; end
                    
                    new_lfp_time = (0:length(lfp_time_cell{rec})-1) / lfp_Fs; 
                    diff_ticks_lfp = [0, diff(lfp_ticks_ms) - 250]; 
                    indx_gaps_lfp  = find(diff_ticks_lfp > 0);
                    
                    if ~isempty(indx_gaps_lfp)
                        missing_samples_detected = true;
                        total_gaps_found = total_gaps_found + numel(indx_gaps_lfp);
                        cum_packets_size = [0, cumsum(lfp_ticks_size)];
                        
                        for i = indx_gaps_lfp
                            new_lfp_time(cum_packets_size(i):end) = new_lfp_time(cum_packets_size(i):end) + diff_ticks_lfp(i)/1000;
                        end
                    end
                    
                    if isfield(obj.WorkspaceData.StreamingObj.streaming_parameters, 'text_adaptive') || isfield(obj.WorkspaceData.StreamingObj.streaming_parameters, 'stim_amp')
                        stim_ticks_ms = obj.WorkspaceData.StreamingObj.streaming_parameters.stim_amp.global_packets_ticks{rec};
                    else
                        stim_ticks_ms = obj.WorkspaceData.StreamingObj.streaming_parameters.stim_amplitude_ticks{rec}; 
                    end
                    
                    if ~isempty(stim_ticks_ms)
                        new_stim_time = (stim_ticks_ms - stim_ticks_ms(1)) / 1000; 
                        diff_ticks_stim = [0, diff(stim_ticks_ms) - 500]; 
                        indx_gaps_stim  = find(diff_ticks_stim > 0);
                        for i = indx_gaps_stim
                            new_stim_time(i:end) = new_stim_time(i:end) + diff_ticks_stim(i)/1000;
                        end
                    else
                        new_stim_time = [];
                    end
                    
                    if missing_samples_detected
                        obj.WorkspaceData.StreamingObj.correctMissingSamples(rec, new_lfp_time, new_stim_time);
                    end
                end
                
                if total_gaps_found > 0
                    obj.updateStatus(sprintf('✔ LFP Telemetry Audit: %d recording(s) checked. Repaired %d gap(s).', num_raw_lfp, total_gaps_found));
                else
                    obj.updateStatus(sprintf('✔ LFP Telemetry Audit: All %d recordings intact (0 gaps).', num_raw_lfp));
                end
                
                % =========================================================================
                % STAGE C2: TWO-PASS BIOMETRIC ALIGNMENT TRACKING FILTER
                % =========================================================================
                obj.updateStatus('Starting automatic Wearables Task to LFP Recording mapping...');
                lfp_time_cell_clean = obj.WorkspaceData.StreamingObj.streaming_parameters.time_domain.time;
                repaired_durations = zeros(1, num_raw_lfp);
                is_valid_run       = false(1, num_raw_lfp);
                
                for r = 1:num_raw_lfp
                    t_vec_clean = lfp_time_cell_clean{r};
                    if isempty(t_vec_clean), continue; end
                    dur = t_vec_clean(end) - t_vec_clean(1);
                    if dur >= 45
                        repaired_durations(r) = dur;
                        is_valid_run(r)       = true;
                    end
                end
                
                valid_run_indices = find(is_valid_run);
                num_validated_runs = numel(valid_run_indices);
                
                if num_validated_runs == 0
                    uialert(obj.UIFigure, 'No valid LFP recordings with duration >= 45s found.', 'Data Error');
                    return;
                end
                
                % --- SMART AUTO-MAPPING ALGORITHM (Stimulation-Aware) ---
                lfp_signatures = repmat(string("<Discard>"), 1, num_raw_lfp);
                
                stim_left_cell  = cell(1, num_validated_runs);
                stim_right_cell = cell(1, num_validated_runs);
                
                for idx = 1:num_validated_runs
                    rec = valid_run_indices(idx);
                    s_data = [];
                    if isfield(obj.WorkspaceData.StreamingObj.streaming_parameters, 'stim_amp') && isfield(obj.WorkspaceData.StreamingObj.streaming_parameters.stim_amp, 'data')
                        s_data = obj.WorkspaceData.StreamingObj.streaming_parameters.stim_amp.data{rec};
                    elseif isfield(obj.WorkspaceData.StreamingObj.streaming_parameters, 'stim_amplitude_data')
                        s_data = obj.WorkspaceData.StreamingObj.streaming_parameters.stim_amplitude_data{rec};
                    end
                    
                    if ~isempty(s_data) && size(s_data, 2) >= 2
                        stim_left_cell{idx}  = round(s_data(:, 1), 1);
                        stim_right_cell{idx} = round(s_data(:, 2), 1);
                    else
                        stim_left_cell{idx}  = 0;
                        stim_right_cell{idx} = 0;
                    end
                end
                
                if num_validated_runs >= 1, lfp_signatures(valid_run_indices(1)) = "0"; end
                if num_validated_runs >= 2, lfp_signatures(valid_run_indices(2)) = "1"; end
                
                last_is_5 = false;
                if num_validated_runs >= 3
                    stim_L_final = stim_left_cell{end};
                    stim_R_final = stim_right_cell{end};
                    
                    mode_L = mode(stim_L_final);
                    mode_R = mode(stim_R_final);
                    
                    is_L_const = (sum(stim_L_final == mode_L) / numel(stim_L_final)) > 0.85;
                    is_R_const = (sum(stim_R_final == mode_R) / numel(stim_R_final)) > 0.85;
                    
                    if is_L_const && is_R_const && (mode_L > 0) && (mode_R > 0)
                        lfp_signatures(valid_run_indices(end)) = "5";
                        last_is_5 = true;
                    end
                end
                
                left_titration_tasks  = ["2L", "3L", "4L", "4a"];
                right_titration_tasks = ["2R", "3R", "4R", "4b"];
                l_count = 1;
                r_count = 1;
                
                end_titration_idx = num_validated_runs;
                if last_is_5
                    end_titration_idx = num_validated_runs - 1;
                end
                
                for idx = 3:end_titration_idx
                    stim_L = stim_left_cell{idx};
                    stim_R = stim_right_cell{idx};
                    
                    l_changes = (numel(unique(stim_L)) > 1);
                    r_changes = (numel(unique(stim_R)) > 1);
                    
                    if l_changes && ~r_changes
                        if l_count <= numel(left_titration_tasks)
                            lfp_signatures(valid_run_indices(idx)) = left_titration_tasks(l_count);
                            l_count = l_count + 1;
                        end
                    elseif r_changes && ~l_changes
                        if r_count <= numel(right_titration_tasks)
                            lfp_signatures(valid_run_indices(idx)) = right_titration_tasks(r_count);
                            r_count = r_count + 1;
                        end
                    end
                end
                
                lfp_anchor_idx = valid_run_indices(1); 
                wearable_anchor_start = temp_wearables(1).recording_start;
                lfp_anchor_start = obj.WorkspaceData.StreamingObj.streaming_parameters.time_domain.first_packet_datetimes{lfp_anchor_idx};
                
                obj.WorkspaceData.DelayIpg = wearable_anchor_start - lfp_anchor_start;
                
                % =========================================================================
                % PHASE 3: STABLE 1-TO-1 SEQUENTIAL DIRECT PAIRING ENGINE (DURATION-AWARE)
                % =========================================================================
                num_packs = floor(num_parsed_files / 4);
                obj.updateStatus('----------------- INGESTION DIAGNOSTIC AUDIT LOG -----------------');
                
                used_lfp_runs = [];
                last_matched_v = 0;
                
                for p = 1:num_packs
                    indices_of_pack = (4 * (p - 1) + 1):(4 * p);
                    pack_start_time = temp_wearables(indices_of_pack(1)).recording_start;
                    pack_duration   = max(arrayfun(@(idx) height(temp_wearables(idx).data) / temp_wearables(idx).sampling_freq_Hz, indices_of_pack));
                    
                    matched_run = NaN;
                    
                    for v = (last_matched_v + 1):num_validated_runs
                        cand_run = valid_run_indices(v);
                        if ismember(cand_run, used_lfp_runs), continue; end
                        
                        cand_dur = repaired_durations(cand_run);
                        if abs(cand_dur - pack_duration) < max(40, 0.20 * pack_duration)
                            matched_run = cand_run;
                            last_matched_v = v;
                            break;
                        end
                    end
                    
                    if isnan(matched_run)
                        for v = 1:last_matched_v
                            cand_run = valid_run_indices(v);
                            if ismember(cand_run, used_lfp_runs), continue; end
                            
                            cand_dur = repaired_durations(cand_run);
                            if abs(cand_dur - pack_duration) < max(40, 0.20 * pack_duration)
                                matched_run = cand_run;
                                last_matched_v = v;
                                break;
                            end
                        end
                    end
                    
                    if isnan(matched_run)
                        lfp_target_ptr = max(1, min(p, num_validated_runs));
                        matched_run = valid_run_indices(lfp_target_ptr);
                        last_matched_v = find(valid_run_indices == matched_run, 1);
                    end
                    
                    used_lfp_runs(end+1) = matched_run; %#ok<AGROW>
                    assigned_task = lfp_signatures(matched_run);
                    cand_lfp_duration = repaired_durations(matched_run);
                    
                    obj.updateStatus(sprintf('Pack %d [Time: %s, Dur: %.1fs] -> Matched LFP Rec #%d [Task: %s, Dur: %.1fs]', ...
                        p, datestr(pack_start_time, 'HH:MM:SS'), pack_duration, matched_run, assigned_task, cand_lfp_duration));
                    
                    for idx = indices_of_pack
                        temp_wearables(idx).task_id     = assigned_task;
                        temp_wearables(idx).lfp_rec_num = matched_run;
                        
                        if ismember(assigned_task, ["0", "1", "5", "<Discard>"])
                            temp_wearables(idx).symptom = "NaN";
                        end
                    end
                end
                obj.updateStatus('-----------------------------------------------------------------');
                
                % =========================================================================
                % PHASE 4: WORKSPACE DATA CONSOLIDATION & CLEANUP
                % =========================================================================
                obj.updateStatus('Consolidating data into unified Workspace memory...');
                
                obj.WorkspaceData.WearablesObj = temp_wearables;
                obj.WorkspaceData.ProtocolSections = unique(lfp_signatures, 'stable');
                
                obj.IsDataLoaded = true;
                obj.updateStatus('✔ Ingestion, Audit & Consolidation Complete.');
                obj.refreshStateEngine();
                
            catch ME
                uialert(obj.UIFigure, ME.message, 'Kinematics Preprocessing Failure');
            end
        end
        
        function cbLogMapping(obj, ~, ~)
            % 1. Resolve Data Locations
            if isfield(obj.WorkspaceData, 'WearablesObj') && ~isempty(obj.WorkspaceData.WearablesObj)
                w_obj = obj.WorkspaceData.WearablesObj;
            else
                uialert(obj.UIFigure, 'Wearables data not found. Please load data first.', 'Data Missing');
                return;
            end
                        
            if isfield(obj.WorkspaceData, 'StreamingObj') && ~isempty(obj.WorkspaceData.StreamingObj)
                s_obj = obj.WorkspaceData.StreamingObj;
            else
                uialert(obj.UIFigure, 'Streaming LFP data not found. Please load data first.', 'Data Missing');
                return;
            end
            
            % 2. Standardize Task IDs for Dropdown Options
            % Ensure the full standard protocol suite is ALWAYS available to select, 
            % regardless of whether the parsing engine found them all.
            standard_tasks = ["0", "1", "2L", "2R", "3L", "3R", "4L", "4R", "5"];
            
            % Extract any unique tasks actually found in the wearables data 
            % (This ensures we don't lose edge-case tasks like "4a" or "4b" if they exist)
            all_tasks = string({w_obj.task_id});
            unique_found = unique(all_tasks);
            
            % Merge them, keeping the standard chronological order first
            combined_tasks = unique([standard_tasks, unique_found], 'stable');
            
            dropdown_options = ["<Discard>", combined_tasks];
            
            % 3. Extract LFP & Stim Recording Info
            lfp_times = s_obj.streaming_parameters.time_domain.time;
            stim_data = s_obj.streaming_parameters.stim_amp.data;
            stim_time = s_obj.streaming_parameters.stim_amp.time;
            num_lfp = numel(lfp_times);
            
            if num_lfp == 0
                uialert(obj.UIFigure, 'No LFP recordings found in the streaming parameters.', 'Data Deficit');
                return;
            end
            
            % --- ULTRA-COMPACT HEIGHT CALCULATION ---
            row_height = 28;     % Crushed from 45px -> 28px (Absolute physical limit for 2 lines of text)
            header_height = 20;  % Tightened header
            base_ui_height = 65; % Reduced footprint for the bottom button and tight padding
            
            target_height = base_ui_height + header_height + (num_lfp * row_height) + (num_lfp * 2);

            obj.updateStatus('Initializing LFP-to-Wearables mapping...')
            
            % Cap at 950px, but it will now hold nearly twice as many recordings before scrolling!
            fig_height = min(950, max(300, target_height));
            
            % 4. Build the Mapping Sub-UI
            mapFig = uifigure('Name', 'LFP to Wearables Task Mapping', 'Position', [150, 80, 1050, fig_height]);
            
            mainLayout = uigridlayout(mapFig, [2, 1]);
            mainLayout.RowHeight = {'1x', 35}; % Thinner button row
            mainLayout.Padding = [5 5 5 5];    % Crushed global padding
            mainLayout.RowSpacing = 5;
            
            scrollPanel = uipanel(mainLayout, 'Scrollable', 'on', 'BorderType', 'none');
            
            listGrid = uigridlayout(scrollPanel, [num_lfp + 1, 4]);
            listGrid.ColumnWidth = {75, 75, '1x', 130};
            
            % Apply the ultra-slim 28px height to data rows
            listGrid.RowHeight = [{header_height}, num2cell(repmat(row_height, 1, num_lfp))]; 
            
            listGrid.Padding = [5 2 5 2]; % Left, Top, Right, Bottom
            listGrid.RowSpacing = 2;      % Crushed inter-row gap from 10px down to 2px
            
            % Render Headers (Font size explicitly set)
            uilabel(listGrid, 'Text', 'LFP Rec #', 'FontWeight', 'bold', 'FontSize', 11);
            uilabel(listGrid, 'Text', 'Duration', 'FontWeight', 'bold', 'FontSize', 11);
            uilabel(listGrid, 'Text', 'Stable Stimulation Levels (Hemisphere Breakdown)', 'FontWeight', 'bold', 'FontSize', 11);
            uilabel(listGrid, 'Text', 'Mapped Task ID', 'FontWeight', 'bold', 'FontSize', 11);
            
            dd_array = gobjects(num_lfp, 1);
            
            for i = 1:num_lfp
                % Col 1: LFP Index
                uilabel(listGrid, 'Text', sprintf('Rec %d', i), 'FontWeight', 'bold', 'FontColor', [0 0.45 0.74], 'FontSize', 11);
                
                % Col 2: Duration
                t_array = lfp_times{i};
                if ~isempty(t_array)
                    if isdatetime(t_array), dur_sec = seconds(t_array(end) - t_array(1));
                    else, dur_sec = t_array(end) - t_array(1); end
                    uilabel(listGrid, 'Text', sprintf('%.1f s', dur_sec), 'FontSize', 11);
                else
                    uilabel(listGrid, 'Text', '0.0 s', 'FontSize', 11);
                end
                
                % Col 3: Hemisphere Breakdown (Font size 10 to fit dual lines in 28px height)
                s_mat = stim_data{i};
                s_t = stim_time{i};
                
                if ~isempty(s_mat) && ~isempty(s_t)
                    if isdatetime(s_t), s_t_sec = seconds(s_t - s_t(1));
                    else, s_t_sec = s_t - s_t(1); end
                    
                    left_str = obj.parseStimDuration(s_mat(:, 1), s_t_sec, 10);
                    if size(s_mat, 2) >= 2
                        right_str = obj.parseStimDuration(s_mat(:, 2), s_t_sec, 10);
                    else
                        right_str = "N/A";
                    end
                    
                    lbl_stim = uilabel(listGrid, 'FontSize', 10); % 10pt font ensures no clipping
                    lbl_stim.Text = {sprintf('Left:  %s', left_str), sprintf('Right: %s', right_str)};
                else
                    uilabel(listGrid, 'Text', 'No Stim Data Available', 'FontSize', 11);
                end
                
                % Col 4: Task Dropdown
                current_task = "<Discard>";
                for w = 1:numel(w_obj)
                    if ismember(i, w_obj(w).lfp_rec_num)
                        current_task = string(w_obj(w).task_id);
                        break;
                    end
                end
                dd_array(i) = uidropdown(listGrid, 'Items', dropdown_options, 'Value', current_task, 'FontSize', 11);
            end
            
            % 5. Save Button
            btnSave = uibutton(mainLayout, 'Text', '💾 Save Mappings & Close', ...
                'FontWeight', 'bold', 'BackgroundColor', [0.85 0.95 0.85]);
            btnSave.ButtonPushedFcn = @(src, event) obj.saveLogMapping(mapFig, dd_array, num_lfp, w_obj);
        end

        function result_str = parseStimDuration(~, stim_col, time_sec, min_dur)
            % HELPER: Finds continuous blocks of stimulation, calculates duration, and filters < 10s
            rounded_stim = round(stim_col, 1);
            idx_change = find(diff(rounded_stim) ~= 0);
            starts = [1; idx_change + 1];
            ends = [idx_change; length(rounded_stim)];
            
            valid_levels = [];
            valid_durs = [];
            
            for k = 1:length(starts)
                dur = time_sec(ends(k)) - time_sec(starts(k));
                if dur >= min_dur
                    lvl = rounded_stim(starts(k));
                    % If the user returns to the same stim level later in the file, add to its total time
                    existing_idx = find(valid_levels == lvl, 1);
                    if ~isempty(existing_idx)
                        valid_durs(existing_idx) = valid_durs(existing_idx) + dur;
                    else
                        valid_levels(end+1) = lvl; %#ok<AGROW>
                        valid_durs(end+1) = dur;   %#ok<AGROW>
                    end
                end
            end
            
            % Format the output string cleanly
            if isempty(valid_levels)
                result_str = "None";
            else
                [valid_levels, sort_idx] = sort(valid_levels);
                valid_durs = valid_durs(sort_idx);
                
                str_parts = strings(1, length(valid_levels));
                for k = 1:length(valid_levels)
                    str_parts(k) = sprintf('%.1fmA (%.0fs)', valid_levels(k), valid_durs(k));
                end
                result_str = join(str_parts, ', ');
            end
        end
        
        function saveLogMapping(obj, mapFig, dd_array, num_lfp, w_obj)
            % 1. Extract the new Task ID strings selected by the user
            selected_tasks = strings(num_lfp, 1);
            for i = 1:num_lfp
                selected_tasks(i) = string(dd_array(i).Value);
            end
            
            % 2. Extract the TRUE chronological sequence of valid tasks from the UI
            % e.g., ["0", "2L", "2R", "3L"...] (Automatically skips "1" if you didn't select it)
            valid_tasks = selected_tasks(selected_tasks ~= "<Discard>");
            ordered_valid_tasks = unique(valid_tasks, 'stable');
            
            % 3. MASTER OVERRIDE: Assign Wearables strictly by chronological pack order
            % We know wearables always come in chronological packs of 4 sensors.
            num_w = numel(w_obj);
            num_packs = floor(num_w / 4);
            
            for p = 1:num_packs
                indices_of_pack = (4 * (p - 1) + 1) : (4 * p);
                
                if p <= numel(ordered_valid_tasks)
                    assigned_task = ordered_valid_tasks(p);
                    
                    % Find ALL LFP recordings that map to this specific task
                    matched_lfps = find(selected_tasks == assigned_task);
                    
                    % Forcefully overwrite the ingestion engine's guess with the human truth
                    for idx = indices_of_pack
                        w_obj(idx).task_id = assigned_task;
                        w_obj(idx).lfp_rec_num = matched_lfps(:)'; % Ensure row vector for concatenations
                        
                        % Clean up symptom field for baseline tasks just in case
                        if ismember(assigned_task, ["0", "1", "5"])
                            w_obj(idx).symptom = "NaN";
                        elseif ismember(assigned_task,["2L","2R"])
                            w_obj(idx).symptom = "Tremor";
                        elseif ismember(assigned_task,["3L","3R"])
                            w_obj(idx).symptom = "Rigidity";
                        elseif ismember(assigned_task,["4L","4R"])
                            w_obj(idx).symptom = "Bradykinesia";
                        end
                    end
                else
                    % If there are more Wearable packs than mapped tasks, discard the extra wearables
                    for idx = indices_of_pack
                        w_obj(idx).task_id = "<Discard>";
                        w_obj(idx).lfp_rec_num = NaN;
                    end
                end
            end
            
            % 4. Save correctly to the EXACT WorkspaceData fields
            obj.WorkspaceData.WearablesObj = w_obj;
            obj.WorkspaceData.ProtocolSections = ordered_valid_tasks';
            
            % Sync the audited run labels for any downstream telemetry parsing
            obj.WorkspaceData.audited_run_labels = selected_tasks';
            
            % 5. Wrap up and close
            obj.updateStatus('LFP recordings and Wearable Tasks have been successfully mapped!');
            obj.IsDataMapped = true;
            
            if ismethod(obj, 'refreshStateEngine')
                obj.refreshStateEngine();
            end
            delete(mapFig);
        end
        function cbLaunchFineAlignment(obj, ~, ~)
            obj.updateStatus('Initializing Temporal Synchronization...');
            DBSgram_SyncUI(obj);
        end
        
        function cbLaunchDataInclusionAudit(obj, ~, ~)
            obj.updateStatus('Initializing parallel multi-modal Data Quality Profile evaluation...');
            
            % DEFENSIVE GUARD: Ensure the workspace memory frame is safely initialized
            if isempty(obj.WorkspaceData) || ~isstruct(obj.WorkspaceData)
                obj.WorkspaceData = struct();
            end
                        
            % Launch the interactive Data Quality and Synchronization Workspace
            DBSgram_DataQualityUI(obj);
            
        end
        
        function cbKinematicsAnalysis(obj, ~, ~)
            obj.updateStatus('Opening Manual Evaluation Segment Editor for Bradykinesia & Rigidity windows...');
            DBSgram_KinematicSelectorUI(obj);
            obj.refreshStateEngine();
        end
        
        function cbLaunchEcgWorkspace(obj, ~, ~)
            obj.updateStatus('Opening SVD Subspace Filtering Workstation...');
            DBSgram_EcgCleanUI(obj);
            obj.refreshStateEngine();
        end
        
        function cbLaunchClinicalOverview(obj, ~, ~)
            obj.updateStatus('Opening Multi-Symptom UPDRS Titration scoring matrix...');
            DBSgram_ClinicalOverUI(obj);
            obj.refreshStateEngine();
        end
        
        function cbCompileFinalDBSgram(obj, ~, ~)
            % Open a file selection dialog to choose where to save the document
            [fileName, filePath] = uiputfile('*.pdf', 'Export Clinical DBSgram Report Workbook', ...
                sprintf('DBSgram_Report_Patient_%s.pdf', obj.WorkspaceData.PatientKey));
            
            if isequal(fileName, 0) || isequal(filePath, 0)
                obj.updateStatus('⚠️ PDF generation canceled by user.');
                return;
            end
            
            fullReportPath = fullfile(filePath, fileName);
            obj.updateStatus('Generating multi-page vector DBSgram document blueprint...');
            
            % Initialize the report engine and generate the document
            engine = DBSgram_ReportEngine(obj);
            try
                engine.generateDBSgramPDF(fullReportPath);
                obj.updateStatus(sprintf('✔ PDF successfully generated: %s', fileName));
                
                % Automatically open the finished document using the system's default viewer
                if ispc
                    winopen(fullReportPath);
                else
                    system(sprintf('open "%s" &', fullReportPath));
                end
            catch ME
                uialert(obj.UIFigure, sprintf('Failed to compile composite PDF report: %s', ME.message), 'PDF Engine Failure');
                obj.updateStatus('❌ PDF report generation error encountered.');
            end
        end
    end
end