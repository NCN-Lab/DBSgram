classdef DBSgram_ClinicalOverUI < handle
    % DBSgram_ClinicalOverUI - Wizard-Driven Symptom-Grouped Titration Logger
    
    properties
        ParentApp       DBSgram_MainUI
        UIFigure        matlab.ui.Figure
        MainGrid        matlab.ui.container.GridLayout
        SidebarGrid     matlab.ui.container.GridLayout
        MatrixGrid      matlab.ui.container.GridLayout
        
        LeftPanel       matlab.ui.container.Panel
        RightPanel      matlab.ui.container.Panel
        
        % Sequential Navigation Elements
        LblSymptomTitle matlab.ui.control.Label
        BtnBack         matlab.ui.control.Button
        BtnNext         matlab.ui.control.Button
        TxtLog          matlab.ui.control.TextArea
        
        % Dynamic Row Matrix Component Allocation Buffers
        ActiveDropdowns cell = cell(1,2)
        ActiveCheckboxes cell = cell(1,2)
    end
    
    properties (Access = private)
        CurrentSymptomIdx   double = 1 
        
        % Dynamic Session Mappings Ingested from AlignedData Workspace
        ValidRunIndices     double
        ValidRunLabels      string
        ValidRunSymptoms    string
        UniqueSymptoms      string
        
        % Master Clinical History Caches Indexed via Struct Symptom Keys
        ScoreStorageStruct  struct
        LevelsStorageStruct struct
    end
    
    methods
        function obj = DBSgram_ClinicalOverUI(parentHandle)
            obj.ParentApp = parentHandle;
            
            if ~isfield(obj.ParentApp.WorkspaceData, 'AlignedData') || isempty(obj.ParentApp.WorkspaceData.AlignedData)
                uialert(obj.ParentApp.UIFigure, 'AlignedData struct not found. Please complete the pre-processing pipeline.', 'Data Error');
                return;
            end
            
            obj.ScoreStorageStruct = struct();
            obj.LevelsStorageStruct = struct();
            
            mapCachesToSymptoms(obj);
            
            if isempty(obj.UniqueSymptoms)
                uialert(obj.ParentApp.UIFigure, 'No valid clinical symptoms were found in the parsed titration blocks.', 'Data Deficit');
                return;
            end
            
            extractTestedStimLevels(obj);
            buildInterface(obj);
            prepopulateExistingWorkspaceCaches(obj);
            renderActiveSymptomScreen(obj);
            
            logStatus(obj, 'Symptom-centric titration review sequencer activated.');
        end
    end
    
    methods (Access = private)
        function mapCachesToSymptoms(obj)
            a_data = obj.ParentApp.WorkspaceData.AlignedData;
            
            % Extract metadata directly from the pre-compiled AlignedData blocks
            all_labels   = string({a_data.task_id});
            all_symptoms = string({a_data.symptom});
            
            % Strip baseline tracking tasks (0, 1), maintenance blocks (5), and discards
            keep_mask = (all_labels ~= "0") & (all_labels ~= "1") & (all_labels ~= "5") & ...
                        (all_labels ~= "NaN") & (all_labels ~= "<Discard>");
                    
            % With AlignedData, ValidRunIndices is just a direct pointer to the struct array
            obj.ValidRunIndices  = find(keep_mask);
            obj.ValidRunLabels   = all_labels(keep_mask);
            obj.ValidRunSymptoms = all_symptoms(keep_mask);
            
            % Enforce sequential evaluation for strictly valid mapped symptoms
            raw_symptoms = obj.ValidRunSymptoms(obj.ValidRunSymptoms ~= "NaN" & ...
                                                obj.ValidRunSymptoms ~= "" & ...
                                                obj.ValidRunSymptoms ~= "Unknown");
            obj.UniqueSymptoms = unique(raw_symptoms, 'stable');
        end
        
        function extractTestedStimLevels(obj)
            ws = obj.ParentApp.WorkspaceData;
            a_data = ws.AlignedData;
            
            for s = 1:numel(obj.UniqueSymptoms)
                symptom_name = obj.UniqueSymptoms(s);
                sym_key = regexprep(symptom_name, '\W+', '_');
                
                left_accum = double.empty;
                right_accum = double.empty;
                
                for k = 1:numel(obj.ValidRunLabels)
                    if obj.ValidRunSymptoms(k) ~= symptom_name, continue; end
                    
                    section_str = obj.ValidRunLabels(k);
                    run_idx     = obj.ValidRunIndices(k); % Pointer to AlignedData block
                    char_label  = char(section_str);
                    h_side      = char_label(end);
                    
                    lbl_levels = double.empty;
                    sync_key = sprintf('titration_bounds_%s_synchronized', section_str);
                    
                    % Priority 1: Pull from Kinematic Selector's saved boundaries if available
                    if isfield(ws, sync_key) && ~isempty(ws.(sync_key))
                        saved_matrix = ws.(sync_key);
                        lbl_levels = zeros(1, size(saved_matrix, 1));
                        for r = 1:size(saved_matrix, 1)
                            lbl_levels(r) = double(saved_matrix{r, 1});
                        end
                    else
                        % Priority 2: Extract strictly from AlignedData logic
                        a_block = a_data(run_idx);
                        h_ptr = 1; if h_side == 'R', h_ptr = 2; end
                        
                        stim_vector = double(a_block.Stim.data(:, h_ptr));
                        rounded_data = round(stim_vector, 1);
                        amps = unique(rounded_data);
                        
                        % Adaptive duration gate using cleanly synced seconds
                        target_duration_seconds = 15; 
                        t_sec = seconds(a_block.CommonTime - a_block.CommonTime(1));
                        
                        for a = 1:numel(amps)
                            matching_indices = find(rounded_data == amps(a));
                            if ~isempty(matching_indices)
                                % ==========================================================
                                % NEW FIX: Isolate Contiguous Chunks
                                % Split indices wherever the gap between them is > 1
                                % ==========================================================
                                split_pts = find(diff(matching_indices) > 1);
                                
                                % Define start and end boundaries for each contiguous chunk
                                c_starts = [1; split_pts + 1];
                                c_ends   = [split_pts; length(matching_indices)];
                                
                                is_valid_level = false;
                                
                                % Check the duration of each isolated, contiguous chunk
                                for c = 1:length(c_starts)
                                    idx_start = matching_indices(c_starts(c));
                                    idx_end   = matching_indices(c_ends(c));
                                    
                                    chunk_duration = t_sec(idx_end) - t_sec(idx_start);
                                    
                                    % If this specific, uninterrupted block is >= 15s, it passes!
                                    if chunk_duration >= target_duration_seconds
                                        is_valid_level = true;
                                        break; 
                                    end
                                end
                                
                                if is_valid_level
                                    lbl_levels(end+1) = amps(a); %#ok<AGROW>
                                end
                            end
                        end
                        
                        if isempty(lbl_levels)
                            lbl_levels = amps(:)';
                        end
                    end
                    
                    lbl_levels = lbl_levels(:)'; 
                    if h_side == 'L'
                        left_accum = [left_accum, lbl_levels]; %#ok<AGROW>
                    else
                        right_accum = [right_accum, lbl_levels]; %#ok<AGROW>
                    end
                end
                
                obj.LevelsStorageStruct.(sprintf('%s_Left', sym_key))  = unique(sort(left_accum(:)'))';
                obj.LevelsStorageStruct.(sprintf('%s_Right', sym_key)) = unique(sort(right_accum(:)'))';
            end
        end
        
        function buildInterface(obj)
            screensize = get(groot,'ScreenSize');
            w = screensize(3) * 0.9; h = screensize(4) * 0.85; 
            x = (screensize(3)-w)/2; y = (screensize(4)-h)/2;

            obj.UIFigure = uifigure('Name', 'Multi-Symptom Titration Workflow Clinical Overview Panel', ...
                                   'Position', [x, y, w, h]);

            obj.MainGrid = uigridlayout(obj.UIFigure, [1, 2]);
            obj.MainGrid.ColumnWidth = {350, '1x'};
            
            % --- SIDEBAR CONTROLS ---
            obj.SidebarGrid = uigridlayout(obj.MainGrid, [4, 1]);
            obj.SidebarGrid.RowHeight = {50, 35, 35, '1x'};
            obj.SidebarGrid.RowSpacing = 10; obj.SidebarGrid.Padding = [10 10 10 10];
            
            obj.LblSymptomTitle = uilabel(obj.SidebarGrid, 'Text', 'Evaluating Symptom: INITIALIZING', ...
                'FontSize', 14, 'FontWeight', 'bold', 'FontColor', [0 0.45 0.74]);
            
            obj.BtnBack = uibutton(obj.SidebarGrid, 'Text', '◀ Back Symptom', 'Enable', 'off', ...
                'ButtonPushedFcn', @(src, event) obj.cbNavigateSymptom(src, event, -1));
            
            obj.BtnNext = uibutton(obj.SidebarGrid, 'Text', 'Confirm & Next Symptom ▶', 'FontWeight', 'bold', ...
                'ButtonPushedFcn', @(src, event) obj.cbNavigateSymptom(src, event, 1));
            
            obj.TxtLog = uitextarea(obj.SidebarGrid, 'Editable', 'off', 'FontAngle', 'normal', 'FontSize', 11);
            
            % --- VERTICAL PANEL GRID ---
            obj.MatrixGrid = uigridlayout(obj.MainGrid, [2, 1]);
            obj.MatrixGrid.RowHeight = {'1x', '1x'}; 
            obj.MatrixGrid.ColumnWidth = {'1x'};
            obj.MatrixGrid.Padding = [10 10 10 10]; obj.MatrixGrid.RowSpacing = 15;
            
            obj.LeftPanel  = uipanel(obj.MatrixGrid, 'Title', 'Left Hemisphere Titration (Evaluating Right Body)');
            obj.RightPanel = uipanel(obj.MatrixGrid, 'Title', 'Right Hemisphere Titration (Evaluating Left Body)');
        end
        
        function renderActiveSymptomScreen(obj)
            delete(obj.LeftPanel.Children);
            delete(obj.RightPanel.Children);
            
            symptom_name = obj.UniqueSymptoms(obj.CurrentSymptomIdx);
            sym_key = regexprep(symptom_name, '\W+', '_');
            
            obj.LblSymptomTitle.Text = sprintf('Clinical Symptom: %s\n(Step %d of %d)', ...
                symptom_name, obj.CurrentSymptomIdx, numel(obj.UniqueSymptoms));
            
            left_levels  = obj.LevelsStorageStruct.(sprintf('%s_Left', sym_key));
            right_levels = obj.LevelsStorageStruct.(sprintf('%s_Right', sym_key));
            
            ws = obj.ParentApp.WorkspaceData;
            left_usable = false; right_usable = false;
            left_has_data = false; right_has_data = false;
            
            for k = 1:numel(obj.ValidRunLabels)
                if obj.ValidRunSymptoms(k) ~= symptom_name, continue; end
                lbl = obj.ValidRunLabels(k);
                
                % Resolve usability exactly against the verified masks from DataQuality UI
                ws_idx = find(ws.audited_run_labels == lbl, 1);
                
                char_lbl = char(lbl);
                if ~isempty(char_lbl) && char_lbl(end) == 'L'
                    left_has_data = true;
                    if ~isempty(ws_idx), left_usable = ws.verified_left_mask(ws_idx); end
                elseif ~isempty(char_lbl) && char_lbl(end) == 'R'
                    right_has_data = true;
                    if ~isempty(ws_idx), right_usable = ws.verified_right_mask(ws_idx); end
                end
            end
            
            buildHemisphereSymptomGrid(obj, obj.LeftPanel, 1, left_levels, left_usable, left_has_data);
            buildHemisphereSymptomGrid(obj, obj.RightPanel, 2, right_levels, right_usable, right_has_data);
            
            obj.BtnBack.Enable = (obj.CurrentSymptomIdx > 1);
            if obj.CurrentSymptomIdx == numel(obj.UniqueSymptoms)
                obj.BtnNext.Text = '🔒 Finalize Data Blueprint to Dashboard';
                obj.BtnNext.BackgroundColor = [0.76 0.89 0.76];
            else
                obj.BtnNext.Text = 'Confirm & Next Symptom ▶';
                obj.BtnNext.BackgroundColor = [0.85 0.92 1.0];
            end
        end
        
        function buildHemisphereSymptomGrid(obj, parentPanel, hemiMode, levels, isUsable, hasData)
            symptom_name = obj.UniqueSymptoms(obj.CurrentSymptomIdx);
            sym_key = regexprep(symptom_name, '\W+', '_');
            num_rows = numel(levels);
            
            if ~hasData || isempty(levels)
                layoutGrid = uigridlayout(parentPanel, [1, 1]);
                uilabel(layoutGrid, 'Text', 'Symptom not evaluated on this hemisphere side.', ...
                    'FontWeight', 'bold', 'HorizontalAlignment', 'center', 'FontColor', [0.5 0.5 0.5]);
                return;
            end
            
            layoutGrid = uigridlayout(parentPanel, [num_rows + 1, 3]);
            layoutGrid.ColumnWidth = {110, '1x', 240};
            layoutGrid.RowHeight = [{30}, repmat({32}, 1, num_rows)];
            layoutGrid.Padding = [12 10 12 10];
            
            uilabel(layoutGrid, 'Text', 'Current Level', 'FontWeight', 'bold');
            uilabel(layoutGrid, 'Text', 'UPDRS Motor Item Score', 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
            uilabel(layoutGrid, 'Text', 'Adverse Side Effects Status', 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
            
            updrs_items = {'0 - Normal', '1 - Slight', '2 - Mild', '3 - Moderate', '4 - Severe'};
            
            obj.ActiveDropdowns{hemiMode}  = [];
            obj.ActiveCheckboxes{hemiMode} = [];
            
            storage_key = sprintf('%s_Hemi_%d', sym_key, hemiMode);
            if isfield(obj.ScoreStorageStruct, storage_key)
                saved_data = obj.ScoreStorageStruct.(storage_key);
                current_scores = saved_data.scores;
                current_sidefx = saved_data.sidefx;
                
                % Overwrite cache array shape if it gets de-synchronized from levels count updates
                if numel(current_scores) ~= num_rows
                    current_scores = zeros(1, num_rows);
                    current_sidefx = false(1, num_rows);
                end
            else
                current_scores = zeros(1, num_rows);
                current_sidefx = false(1, num_rows);
            end
            
            for r = 1:num_rows
                uilabel(layoutGrid, 'Text', sprintf('  %.2f mA', levels(r)), 'FontWeight', 'bold');
                
                if isUsable
                    d = uidropdown(layoutGrid, 'Items', updrs_items, 'Value', obj.convertIdxToTextScore(current_scores(r)), ...
                        'ValueChangedFcn', @(src, event) obj.cbLiveScoreUpdated(src, event, hemiMode, r, 'UPDRS'));
                    
                    c = uicheckbox(layoutGrid, 'Text', 'Overstimulation Side Effects Present', 'Value', current_sidefx(r), ...
                        'ValueChangedFcn', @(src, event) obj.cbLiveScoreUpdated(src, event, hemiMode, r, 'SideFx'));
                else
                    d = uidropdown(layoutGrid, 'Items', {'[Flagged Unusable in Audit]'}, 'Value', '[Flagged Unusable in Audit]', 'Enable', 'off');
                    c = uicheckbox(layoutGrid, 'Text', 'Excl: Quality Audit Filtered', 'Value', false, 'Enable', 'off');
                end
                
                obj.ActiveDropdowns{hemiMode}  = [obj.ActiveDropdowns{hemiMode}, d];
                obj.ActiveCheckboxes{hemiMode} = [obj.ActiveCheckboxes{hemiMode}, c];
            end
        end
        
        function out_str = convertIdxToTextScore(~, val)
            items = {'0 - Normal', '1 - Slight', '2 - Mild', '3 - Moderate', '4 - Severe'};
            clamped_val = max(min(val + 1, 5), 1);
            out_str = items{clamped_val};
        end
        
        function logStatus(obj, messageText)
            timestamp = datestr(now, 'HH:MM:SS');
            obj.TxtLog.Value = [sprintf('[%s] %s', timestamp, messageText); obj.TxtLog.Value];
        end
        
        function prepopulateExistingWorkspaceCaches(obj)
            ws = obj.ParentApp.WorkspaceData;
            
            % 1. Priority 1: Restore from active session memory if already edited
            if isfield(ws, 'clinical_overview_updrs') && ...
               isfield(ws.clinical_overview_updrs, 'score_storage_struct') && ...
               ~isempty(fieldnames(ws.clinical_overview_updrs.score_storage_struct))
                obj.ScoreStorageStruct = ws.clinical_overview_updrs.score_storage_struct;
                obj.logStatus('Restored clinical tracking entries from current session memory.');
                return;
            end
            
            % 2. Priority 2: Look for UPDRS.xlsx in the initial data folder
            folderPath = '';
            if isfield(ws, 'SourceFolderPath') && ~isempty(ws.SourceFolderPath)
                folderPath = ws.SourceFolderPath;
            end
            
            excelPath = '';
            if ~isempty(folderPath) && isfolder(folderPath)
                % Case-insensitive search for UPDRS.xlsx / UPDRS.xls
                dirFiles = [dir(fullfile(folderPath, '*.xlsx')); dir(fullfile(folderPath, '*.xls'))];
                for f = 1:numel(dirFiles)
                    [~, fName, ~] = fileparts(dirFiles(f).name);
                    if strcmpi(fName, 'UPDRS')
                        excelPath = fullfile(folderPath, dirFiles(f).name);
                        break;
                    end
                end
            end
            
            % Raise a warning dialog if no UPDRS.xlsx file is found
            if isempty(excelPath) || ~isfile(excelPath)
                uialert(obj.UIFigure, ...
                    ['No "UPDRS.xlsx" file was found in the patient data directory. ' ...
                     'All clinical scores have been initialized to 0 (Normal) for manual entry.'], ...
                    'UPDRS File Not Found', 'Icon', 'warning');
                obj.logStatus('⚠️ No UPDRS.xlsx found. Initialized default scores for manual entry.');
                return;
            end
            
            % 3. Parse UPDRS.xlsx and populate ScoreStorageStruct
            try
                rawCells = readcell(excelPath);
                obj.parseUpdrsExcelCells(rawCells);
                obj.logStatus('✔ Pre-populated UPDRS scores and side effects from UPDRS.xlsx.');
            catch ME
                uialert(obj.UIFigure, ...
                    sprintf('Failed to parse UPDRS.xlsx:\n%s\n\nScores initialized to default.', ME.message), ...
                    'UPDRS Parse Warning', 'Icon', 'warning');
                obj.logStatus('⚠️ Error parsing UPDRS.xlsx. Initialized default scores.');
            end
        end
        
        function parseUpdrsExcelCells(obj, rawCells)
            % Locate the "Stim Level" header row (Row 3 in standard template)
            [nRows, nCols] = size(rawCells);
            headerRow = 3; 
            for r = 1:min(10, nRows)
                val = rawCells{r, 1};
                if (ischar(val) || isstring(val)) && contains(string(val), 'Stim Level', 'IgnoreCase', true)
                    headerRow = r;
                    break;
                end
            end
            
            symptomRow = max(1, headerRow - 1);
            
            % Collect valid sequential data rows (where Column A is numeric 1, 2, 3...)
            dataRows = [];
            for r = (headerRow + 1):nRows
                val = rawCells{r, 1};
                if isnumeric(val) && isscalar(val) && ~isnan(val)
                    dataRows(end+1) = r; %#ok<AGROW>
                elseif ~ismissing(string(val)) && strlength(strtrim(string(val))) > 0
                    % Stop when hitting footer text like "Legend"
                    break;
                end
            end
            
            % Map each symptom in UniqueSymptoms to its Left/Right columns
            for s = 1:numel(obj.UniqueSymptoms)
                symptom_name = obj.UniqueSymptoms(s);
                sym_key = regexprep(symptom_name, '\W+', '_');
                
                % Search symptomRow for matching header ("Tremor", "Rigidity", "Bradykinesia")
                symCol = NaN;
                for c = 2:nCols
                    cellVal = rawCells{symptomRow, c};
                    if (ischar(cellVal) || isstring(cellVal)) && contains(string(cellVal), symptom_name, 'IgnoreCase', true)
                        symCol = c;
                        break;
                    end
                end
                
                % Fallback to standard template column positions if header text was altered
                if isnan(symCol)
                    if strcmpi(symptom_name, 'Tremor'),           symCol = 2;
                    elseif strcmpi(symptom_name, 'Rigidity'),     symCol = 4;
                    elseif strcmpi(symptom_name, 'Bradykinesia'), symCol = 6;
                    end
                end
                
                if isnan(symCol) || (symCol + 1) > nCols
                    continue;
                end
                
                % Populate Left (hemiMode = 1 -> symCol) and Right (hemiMode = 2 -> symCol + 1)
                for hemiMode = 1:2
                    h_str = "Left"; if hemiMode == 2, h_str = "Right"; end
                    targetCol = symCol + (hemiMode - 1);
                    
                    levels = obj.LevelsStorageStruct.(sprintf('%s_%s', sym_key, h_str));
                    num_levels = numel(levels);
                    if num_levels == 0, continue; end
                    
                    scores = zeros(1, num_levels);
                    sidefx = false(1, num_levels);
                    
                    num_to_read = min(num_levels, numel(dataRows));
                    for r = 1:num_to_read
                        cellEntry = rawCells{dataRows(r), targetCol};
                        
                        if isnumeric(cellEntry) && isscalar(cellEntry) && ~isnan(cellEntry)
                            scores(r) = max(0, min(4, round(cellEntry)));
                            sidefx(r) = false;
                        elseif ischar(cellEntry) || isstring(cellEntry)
                            strEntry = strtrim(string(cellEntry));
                            % Detect '*' for Overstimulation Side Effects
                            if contains(strEntry, '*')
                                sidefx(r) = true;
                                strEntry  = strtrim(erase(strEntry, '*'));
                            end
                            numVal = str2double(strEntry);
                            if ~isnan(numVal)
                                scores(r) = max(0, min(4, round(numVal)));
                            end
                        end
                    end
                    
                    storage_key = sprintf('%s_Hemi_%d', sym_key, hemiMode);
                    obj.ScoreStorageStruct.(storage_key).scores = scores;
                    obj.ScoreStorageStruct.(storage_key).sidefx = sidefx;
                end
            end
        end
        
        function cacheCurrentScreenState(obj)
            symptom_name = obj.UniqueSymptoms(obj.CurrentSymptomIdx);
            sym_key = regexprep(symptom_name, '\W+', '_');
            
            for hemiMode = 1:2
                storage_key = sprintf('%s_Hemi_%d', sym_key, hemiMode);
                dds = obj.ActiveDropdowns{hemiMode};
                cbs = obj.ActiveCheckboxes{hemiMode};
                num_rows = numel(dds);
                if num_rows == 0, continue; end
                
                scores = zeros(1, num_rows);
                sidefx = false(1, num_rows);
                
                for r = 1:num_rows
                    dd = dds(r);
                    if isempty(dd) || ~isvalid(dd) || strcmp(dd.Value, '[Flagged Unusable in Audit]')
                        continue; 
                    end
                    match_idx = find(strcmp(dd.Items, dd.Value), 1);
                    scores(r) = max(0, match_idx - 1);
                    sidefx(r) = cbs(r).Value;
                end
                
                obj.ScoreStorageStruct.(storage_key).scores = scores;
                obj.ScoreStorageStruct.(storage_key).sidefx = sidefx;
            end
        end
        
        function cbLiveScoreUpdated(obj, ~, ~, hemiMode, rowIndex, propType)
            symptom_name = obj.UniqueSymptoms(obj.CurrentSymptomIdx);
            sym_key = regexprep(symptom_name, '\W+', '_');
            h_str = "Left"; if hemiMode == 2, h_str = "Right"; end
            levels = obj.LevelsStorageStruct.(sprintf('%s_%s', sym_key, h_str));
            
            if strcmp(propType, 'UPDRS')
                val = obj.ActiveDropdowns{hemiMode}(rowIndex).Value;
                obj.logStatus(sprintf('%s (%s Side, %.1f mA): Motor item score updated to "%s".', symptom_name, h_str, levels(rowIndex), val));
            else
                val = obj.ActiveCheckboxes{hemiMode}(rowIndex).Value;
                if val, stat = "ON"; else, stat = "OFF"; end
                obj.logStatus(sprintf('%s (%s Side, %.1f mA): Overstimulation side effects turned %s.', symptom_name, h_str, levels(rowIndex), stat));
            end
        end
        
        function cbNavigateSymptom(obj, ~, ~, direction)
            cacheCurrentScreenState(obj);
            target_step = obj.CurrentSymptomIdx + direction;
            
            if target_step >= 1 && target_step <= numel(obj.UniqueSymptoms)
                obj.CurrentSymptomIdx = target_step;
                renderActiveSymptomScreen(obj);
            elseif target_step > numel(obj.UniqueSymptoms)
                obj.ParentApp.WorkspaceData.clinical_overview_updrs.unique_symptoms      = obj.UniqueSymptoms;
                obj.ParentApp.WorkspaceData.clinical_overview_updrs.levels_storage_struct = obj.LevelsStorageStruct;
                obj.ParentApp.WorkspaceData.clinical_overview_updrs.score_storage_struct  = obj.ScoreStorageStruct;
                
                obj.ParentApp.updateStatus('✔ All clinical titration profiles have been assigned their respective UPDRS score.');
                obj.ParentApp.IsClinicalMapped = true;
                obj.ParentApp.refreshStateEngine();
                delete(obj.UIFigure);
            end
        end
    end
end