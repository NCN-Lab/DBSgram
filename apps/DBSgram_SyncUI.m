classdef DBSgram_SyncUI < handle
    % DBSgram_SyncUI - Prominence-Driven Bilateral Alignment Interface
    
    properties
        ParentApp       DBSgram_MainUI 
        UIFigure        matlab.ui.Figure
        MainGrid        matlab.ui.container.GridLayout
        ControlPanel    matlab.ui.container.Panel
        PlotPanel       matlab.ui.container.Panel
        
        % Interaction Fields
        DropdownHemi    matlab.ui.control.DropDown
        DelayField      matlab.ui.control.NumericEditField
        BtnNudgeUp      matlab.ui.control.Button
        BtnNudgeDown    matlab.ui.control.Button
        BtnCommit       matlab.ui.control.Button
        TxtInfo         matlab.ui.control.TextArea
        
        % Oscilloscope Grid Layout Channels
        TileGrid        matlab.graphics.layout.TiledChartLayout
        AxLFP           matlab.graphics.axis.Axes
        AxIHandU        matlab.graphics.axis.Axes
        AxFinger        matlab.graphics.axis.Axes
    end
    
    properties (Access = private)
        % Trace Memory Coordinates
        ActiveLfpTime       datetime
        ActiveLfpSigFiltered double 
        ActiveIHandUTime    datetime
        ActiveIHandUSig     double
        ActiveFingerTime    datetime
        ActiveFingerSig     double
        
        SelectedBodySide    string = "Left"
        
        % Detected peak positions for landmark synchronization markers
        LfpPeakTimes        datetime
        IHandUPeakTimes     datetime
        IHandUPeakVals      double
        FingerPeakTimes     datetime
        FingerPeakVals      double
    end
    
    methods
        function obj = DBSgram_SyncUI(parentHandle)
            obj.ParentApp = parentHandle;
            buildUI(obj);
            initializeAlignmentEngine(obj);
        end
    end
    
    methods (Access = private)
        function buildUI(obj)
            screensize = get(groot,'ScreenSize');
            w = screensize(3) * 0.9; h = screensize(4) * 0.85; 
            x = (screensize(3)-w)/2; y = (screensize(4)-h)/2;

            obj.UIFigure = uifigure('Name', 'DBSgram Sync Alignment Workspace', ...
                                   'Position', [x, y, w, h]);
            obj.MainGrid = uigridlayout(obj.UIFigure, [1, 2]);
            obj.MainGrid.ColumnWidth = {320, '1x'};
            
            % --- ERGONOMIC CONTROL PANEL ---
            obj.ControlPanel = uipanel(obj.MainGrid, 'Title', 'Control Panel');
            ctrlLayout = uigridlayout(obj.ControlPanel, [6, 1]);
            ctrlLayout.RowHeight = {25, 35, 25, 35, '1x', 45};
            
            uilabel(ctrlLayout, 'Text', 'Active LFP Hemisphere:', 'FontWeight', 'bold');
            obj.DropdownHemi = uidropdown(ctrlLayout, 'Items', {'Left', 'Right'}, ...
                'Value', 'Left', 'ValueChangedFcn', @(src, event) obj.cbHemisphereChanged(src, event));
            
            uilabel(ctrlLayout, 'Text', 'Synchronization Shift Delay (s):', 'FontWeight', 'bold');
            
            nudgeGrid = uigridlayout(ctrlLayout, [1, 3]);
            nudgeGrid.ColumnWidth = {'1x', 45, 45}; nudgeGrid.Padding = [0 0 0 0];
            
            obj.DelayField = uieditfield(nudgeGrid, 'numeric', 'Value', 0, ...
                'ValueChangedFcn', @(src, event) obj.cbManualDelayChanged(src, event));
            
            obj.BtnNudgeDown = uibutton(nudgeGrid, 'Text', '▼', ...
                'ButtonPushedFcn', @(src, event) obj.nudgeDelay(src, event, -0.1));
            obj.BtnNudgeUp = uibutton(nudgeGrid, 'Text', '▲', ...
                'ButtonPushedFcn', @(src, event) obj.nudgeDelay(src, event, 0.1));
            
            obj.TxtInfo = uitextarea(ctrlLayout, 'Editable', 'off', 'FontAngle', 'normal');
            
            obj.BtnCommit = uibutton(ctrlLayout, 'Text', '🔒 Lock Synchronization Alignment', ...
                'BackgroundColor', [0.76 0.89 0.76], 'FontWeight', 'bold', ...
                'ButtonPushedFcn', @(src, event) obj.cbFinalizeWorkspace(src, event));
            
            % --- PLOT CANVAS PANEL ---
            obj.PlotPanel = uipanel(obj.MainGrid, 'Title', 'Synchronized Protocol Section 0');
            obj.TileGrid = tiledlayout(obj.PlotPanel, 3, 1, 'Padding', 'compact', 'TileSpacing', 'compact');
            
            obj.AxLFP = nexttile(obj.TileGrid); grid(obj.AxLFP, 'on'); hold(obj.AxLFP, 'on');
            obj.AxIHandU = nexttile(obj.TileGrid); grid(obj.AxIHandU, 'on'); hold(obj.AxIHandU, 'on');
            obj.AxFinger = nexttile(obj.TileGrid); grid(obj.AxFinger, 'on'); hold(obj.AxFinger, 'on');
            
            linkaxes([obj.AxLFP, obj.AxIHandU, obj.AxFinger], 'x');
        end
        
        function initializeAlignmentEngine(obj)
            selectedHemi = upper(obj.DropdownHemi.Value);
            wearables = obj.ParentApp.WorkspaceData.WearablesObj;

            task_wearables = wearables(string({wearables.task_id}) == "0");
            
            if isempty(task_wearables)
                uialert(obj.UIFigure, 'No kinematic records are currently mapped to alignment Section 0.', 'Workspace Sync Error');
                return;
            end
            
            target_lfp_run_idx = task_wearables(1).lfp_rec_num;
            
            % Extract and Filter LFP (Low Gamma 35 - 60 Hz)
            lfp_data_raw  = obj.ParentApp.WorkspaceData.StreamingObj.streaming_parameters.time_domain.data{target_lfp_run_idx};
            lfp_time_rel  = obj.ParentApp.WorkspaceData.StreamingObj.streaming_parameters.time_domain.time{target_lfp_run_idx};
            lfp_channels  = obj.ParentApp.WorkspaceData.StreamingObj.streaming_parameters.time_domain.channel_names{target_lfp_run_idx};
            
            if isfield(obj.ParentApp.WorkspaceData.StreamingObj.streaming_parameters.time_domain, 'fs')
                fs_lfp = double(obj.ParentApp.WorkspaceData.StreamingObj.streaming_parameters.time_domain.fs);
            else
                fs_lfp = double(obj.ParentApp.WorkspaceData.StreamingObj.streaming_parameters.time_domain.sample_rate);
            end
            
            % Normalize timelines as naive local datetimes to enable flawless subplot linkage
            lfp_start_datetime = obj.ParentApp.WorkspaceData.StreamingObj.streaming_parameters.time_domain.first_packet_datetimes{target_lfp_run_idx};
            lfp_start_datetime.TimeZone = ''; 
            obj.ActiveLfpTime = lfp_start_datetime + seconds(lfp_time_rel - lfp_time_rel(1));
            obj.ActiveLfpTime.TimeZone = '';
            
            hemiIdx = find(contains(lfp_channels, selectedHemi), 1);
            if isempty(hemiIdx), hemiIdx = 1; end
            raw_lfp_signal = lfp_data_raw(:, hemiIdx);
            
            [b, a] = butter(5, [35 60] / (fs_lfp / 2), 'bandpass');
            obj.ActiveLfpSigFiltered = filtfilt(b, a, raw_lfp_signal);
            
            % Bilateral Cross-Auditing Peak Evaluation Matrix
            % UPDATED: Now looking for 'L' and 'R' suffixes and 'HandSensor'
            sides_map = ["L", "R"];
            max_prominence_per_side = zeros(1, 2);
            wearable_ids = string({task_wearables.wearable_id});
            
            for s = 1:2
                test_ihandu = task_wearables(endsWith(wearable_ids, sides_map(s), 'IgnoreCase', true) & contains(wearable_ids, 'HandSensor', 'IgnoreCase', true));
                if ~isempty(test_ihandu)
                    at_test = sqrt(test_ihandu.data.ax.^2 + test_ihandu.data.ay.^2 + test_ihandu.data.az.^2);
                    [clean_at, ~] = rmmissing(at_test);
                    if ~isempty(clean_at)
                        [~, ~, ~, proms] = findpeaks(clean_at, 'SortStr', 'descend', 'NPeaks', 1);
                        if ~isempty(proms), max_prominence_per_side(s) = proms(1); end
                    end
                end
            end
            
            if max_prominence_per_side(2) > max_prominence_per_side(1)
                obj.SelectedBodySide = "Right";
            else
                obj.SelectedBodySide = "Left";
            end
            
            % Map Selected Body Side back to "L" or "R"
            if strcmpi(obj.SelectedBodySide, "Left")
                target_side_str = "L";
            else
                target_side_str = "R";
            end
            
            % UPDATED: Now mapping to HandSensor and FingerSensor
            ihandu_struct = task_wearables(endsWith(wearable_ids, target_side_str, 'IgnoreCase', true) & contains(wearable_ids, 'HandSensor', 'IgnoreCase', true));
            finger_struct = task_wearables(endsWith(wearable_ids, target_side_str, 'IgnoreCase', true) & contains(wearable_ids, 'FingerSensor', 'IgnoreCase', true));
            
            fs_wearable = 50; 
            if ~isempty(ihandu_struct) && isfield(ihandu_struct, 'sampling_freq_Hz')
                fs_wearable = double(ihandu_struct.sampling_freq_Hz);
            end
            
            if ~isempty(ihandu_struct)
                at = sqrt(ihandu_struct.data.ax.^2 + ihandu_struct.data.ay.^2 + ihandu_struct.data.az.^2);
                [obj.ActiveIHandUSig, cleanIdx] = rmmissing(at);
                obj.ActiveIHandUTime = ihandu_struct.time(~cleanIdx);
                obj.ActiveIHandUTime.TimeZone = ''; 
            else
                obj.ActiveIHandUSig = []; obj.ActiveIHandUTime = datetime.empty;
            end
            
            if ~isempty(finger_struct)
                at = sqrt(finger_struct.data.ax.^2 + finger_struct.data.ay.^2 + finger_struct.data.az.^2);
                [obj.ActiveFingerSig, cleanIdx] = rmmissing(at);
                obj.ActiveFingerTime = finger_struct.time(~cleanIdx);
                obj.ActiveFingerTime.TimeZone = ''; 
            else
                obj.ActiveFingerSig = []; obj.ActiveFingerTime = datetime.empty;
            end
            
            % =========================================================================
            % 1. WEARABLES PEAK EXTRACTION ENGINE (Primary Anchor)
            % =========================================================================
            max_wearable_peaks = 0;
            
            % Dynamic HandSensor
            if ~isempty(obj.ActiveIHandUSig)
                ih_prom_thresh = 3.5 * std(obj.ActiveIHandUSig);
                [obj.IHandUPeakVals, ihIdx] = findpeaks(obj.ActiveIHandUSig, 'MinPeakProminence', ih_prom_thresh, 'MinPeakDistance', fs_wearable);
                obj.IHandUPeakTimes = obj.ActiveIHandUTime(ihIdx);
                if ~isempty(obj.IHandUPeakTimes), obj.IHandUPeakTimes.TimeZone = ''; end
                
                max_wearable_peaks = max(max_wearable_peaks, numel(obj.IHandUPeakTimes));
            else
                obj.IHandUPeakVals = []; obj.IHandUPeakTimes = datetime.empty;
            end
            
            % Dynamic FingerSensor
            if ~isempty(obj.ActiveFingerSig)
                fg_prom_thresh = 3.5 * std(obj.ActiveFingerSig);
                [obj.FingerPeakVals, fgIdx] = findpeaks(obj.ActiveFingerSig, 'MinPeakProminence', fg_prom_thresh, 'MinPeakDistance', fs_wearable);
                obj.FingerPeakTimes = obj.ActiveFingerTime(fgIdx);
                if ~isempty(obj.FingerPeakTimes), obj.FingerPeakTimes.TimeZone = ''; end
                
                max_wearable_peaks = max(max_wearable_peaks, numel(obj.FingerPeakTimes));
            else
                obj.FingerPeakVals = []; obj.FingerPeakTimes = datetime.empty;
            end
            
            % =========================================================================
            % 2. LFP PEAK EXTRACTION & ANCHOR-BASED ALIGNMENT ENGINE
            % =========================================================================
            calculated_delay = 0;
            
            % Determine the "Master Wearable" (the one that caught the most clear impacts)
            if numel(obj.IHandUPeakTimes) >= numel(obj.FingerPeakTimes)
                master_w_times = obj.IHandUPeakTimes;
                master_w_vals  = obj.IHandUPeakVals;
            else
                master_w_times = obj.FingerPeakTimes;
                master_w_vals  = obj.FingerPeakVals;
            end
            num_sync_peaks = numel(master_w_times);
            
            if num_sync_peaks > 0
                % --- ROUGH PASS: Global Anchor Matching ---
                % Find the absolute largest impact in the wearable
                [~, max_w_idx] = max(master_w_vals);
                t_w_anchor = master_w_times(max_w_idx);
                
                % Find the absolute largest artifact in the LFP
                [~, max_lfp_idx] = max(abs(obj.ActiveLfpSigFiltered));
                t_lfp_anchor = obj.ActiveLfpTime(max_lfp_idx);
                
                % Calculate Initial Anchor Delay (Immune to array sorting issues)
                rough_delay = seconds(t_w_anchor - t_lfp_anchor);
                
                % --- WINDOWED REFINEMENT PASS ---
                % Project where ALL LFP peaks *should* be based on the anchor
                expected_lfp_times = master_w_times - seconds(rough_delay);
                
                refined_lfp_idx = zeros(1, num_sync_peaks);
                valid_pairs_w = datetime.empty;
                valid_pairs_lfp = datetime.empty;
                
                search_window = seconds(0.5); % +/- 500ms generous search window
                
                for p = 1:num_sync_peaks
                    target_t = expected_lfp_times(p);
                    
                    % Create a mask for this specific time window in the LFP signal
                    mask = (obj.ActiveLfpTime >= (target_t - search_window)) & (obj.ActiveLfpTime <= (target_t + search_window));
                    
                    if any(mask)
                        % Find the absolute maximum artifact purely within this window
                        window_idxs = find(mask);
                        [~, max_rel_idx] = max(abs(obj.ActiveLfpSigFiltered(mask)));
                        idx_found = window_idxs(max_rel_idx);
                        
                        refined_lfp_idx(p) = idx_found;
                        valid_pairs_w(end+1)   = master_w_times(p); %#ok<AGROW>
                        valid_pairs_lfp(end+1) = obj.ActiveLfpTime(idx_found); %#ok<AGROW>
                    end
                end
                
                % Clean up any missed windows
                refined_lfp_idx = refined_lfp_idx(refined_lfp_idx > 0);
                
                % Commit refined peaks
                obj.LfpPeakTimes = obj.ActiveLfpTime(refined_lfp_idx);
                if ~isempty(obj.LfpPeakTimes), obj.LfpPeakTimes.TimeZone = ''; end
                
                % --- CALCULATE FINAL EXACT MEAN DELAY ---
                if ~isempty(valid_pairs_w)
                    % Force column arrays (:) to guarantee a scalar mean
                    final_delays = seconds(valid_pairs_w(:) - valid_pairs_lfp(:));
                    calculated_delay = mean(final_delays, 'omitnan');
                else
                    calculated_delay = rough_delay;
                end
            else
                % Wearables Failed / Missing Fallback
                lfp_prom_thresh = 3.5 * std(abs(obj.ActiveLfpSigFiltered));
                [~, lfpIdx] = findpeaks(abs(obj.ActiveLfpSigFiltered), 'MinPeakProminence', lfp_prom_thresh, 'MinPeakDistance', fs_lfp);
                obj.LfpPeakTimes = obj.ActiveLfpTime(lfpIdx);
                if ~isempty(obj.LfpPeakTimes), obj.LfpPeakTimes.TimeZone = ''; end
            end
            
            % Overwrite workspace values with the newly refined mean delta
            if isnan(calculated_delay), calculated_delay = 0; end
            obj.DelayField.Value = calculated_delay;
                       
            obj.TxtInfo.Value = { ...
                '--- Sub-Second Alignment Profile ---'; ...
                sprintf('Synchronized LFP Rec Target: #%d', target_lfp_run_idx); ...
                sprintf('Evaluated Prominence Side: %s', obj.SelectedBodySide); ...
                sprintf('LFP Peaks Localized: %d', numel(obj.LfpPeakTimes)); ...
                sprintf('HandSensor Peaks Localized: %d', numel(obj.IHandUPeakTimes)); ...
                sprintf('FingerSensor Peaks Localized: %d', numel(obj.FingerPeakTimes)); ...
                '------------------------------------'; ...
                sprintf('Peak-Driven Shift: %.3f s', calculated_delay)};
            
            renderLinkedPlots(obj);
        end
        
        function renderLinkedPlots(obj)
            currentDelay = seconds(obj.DelayField.Value);
            adjustedIHandUTime = obj.ActiveIHandUTime - currentDelay;
            adjustedFingerTime = obj.ActiveFingerTime - currentDelay;
            
            adjIHandUPeakTimes = obj.IHandUPeakTimes - currentDelay;
            adjFingerPeakTimes = obj.FingerPeakTimes - currentDelay;
            
            handColor   = [0.85 0.33 0.1];
            fingerColor = [0.93 0.69 0.13]; 
            
            % --- 1. FIRST RENDER OR LIGHTNING UPDATE? ---
            if isempty(findobj(obj.AxLFP, 'Tag', 'StaticLFP'))
                
                % Plot Static LFP (Never moves)
                plot(obj.AxLFP, obj.ActiveLfpTime, obj.ActiveLfpSigFiltered, ...
                    'Color', [0 0.45 0.74], 'LineWidth', 1.1, 'Tag', 'StaticLFP');
                
                if ~isempty(obj.LfpPeakTimes)
                    true_vals = obj.ActiveLfpSigFiltered(ismember(obj.ActiveLfpTime, obj.LfpPeakTimes));
                    plot(obj.AxLFP, obj.LfpPeakTimes, true_vals, 'kv', ...
                        'MarkerFaceColor', 'k', 'MarkerSize', 6, 'Tag', 'StaticLFP');
                end
                ylabel(obj.AxLFP, 'LFP (\muV)');
                title(obj.AxLFP, sprintf('%s Hemisphere Neural Target (35-60 Hz)', obj.DropdownHemi.Value));
                
                % Plot Dynamic HandSensor
                if ~isempty(obj.ActiveIHandUSig)
                    plot(obj.AxIHandU, adjustedIHandUTime, obj.ActiveIHandUSig, ...
                        'Color', handColor, 'LineWidth', 1.1, 'Tag', 'DynLine_Hand');
                    if ~isempty(adjIHandUPeakTimes)
                        plot(obj.AxIHandU, adjIHandUPeakTimes, obj.IHandUPeakVals, 'kv', ...
                            'MarkerFaceColor', 'k', 'MarkerSize', 6, 'Tag', 'DynPeaks_Hand');
                    end
                    ylabel(obj.AxIHandU, 'Accel (g)');
                    title(obj.AxIHandU, sprintf('%s HandSensor Signal Vector (Shift Corrected)', obj.SelectedBodySide));
                end
                
                % Plot Dynamic FingerSensor
                if ~isempty(obj.ActiveFingerSig)
                    plot(obj.AxFinger, adjustedFingerTime, obj.ActiveFingerSig, ...
                        'Color', fingerColor, 'LineWidth', 1.1, 'Tag', 'DynLine_Finger');
                    if ~isempty(adjFingerPeakTimes)
                        plot(obj.AxFinger, adjFingerPeakTimes, obj.FingerPeakVals, 'kv', ...
                            'MarkerFaceColor', 'k', 'MarkerSize', 6, 'Tag', 'DynPeaks_Finger');
                    end
                    ylabel(obj.AxFinger, 'Accel (g)');
                    title(obj.AxFinger, sprintf('%s FingerSensor Signal Vector (Shift Corrected)', obj.SelectedBodySide));
                end
                
                % Set initial limits ONLY on first render, preserving user zoom later
                if ~isempty(obj.LfpPeakTimes)
                    targetLim = [obj.LfpPeakTimes(1) - seconds(5), obj.LfpPeakTimes(1) + seconds(5)];
                    xlim(obj.AxLFP, targetLim);
                elseif ~isempty(obj.ActiveLfpTime)
                    targetLim = [obj.ActiveLfpTime(1), obj.ActiveLfpTime(1) + seconds(10)];
                    xlim(obj.AxLFP, targetLim);
                end
                
            else
                % --- LIGHTNING FAST NUDGE (Updates memory, bypasses rendering engine) ---
                set(findobj(obj.AxIHandU, 'Tag', 'DynLine_Hand'), 'XData', adjustedIHandUTime);
                set(findobj(obj.AxIHandU, 'Tag', 'DynPeaks_Hand'), 'XData', adjIHandUPeakTimes);
                
                set(findobj(obj.AxFinger, 'Tag', 'DynLine_Finger'), 'XData', adjustedFingerTime);
                set(findobj(obj.AxFinger, 'Tag', 'DynPeaks_Finger'), 'XData', adjFingerPeakTimes);
            end
            
            % --- 2. REFRESH CROSSHAIRS ONLY ON LFP AXIS ---
            % Clean up old markers
            delete(findobj(obj.AxLFP, 'Tag', 'SyncMarker'));
            
            % Natively pass the entire array of peak times to xline in ONE command! 
            % No for-loops needed. This is the absolute fastest way to render them.
            if ~isempty(adjIHandUPeakTimes)
                xline(obj.AxLFP, adjIHandUPeakTimes, '-.', 'Color', handColor, ...
                    'LineWidth', 1.5, 'HandleVisibility', 'on', 'Layer', 'bottom', 'Tag', 'SyncMarker');
            end
            
            if ~isempty(adjFingerPeakTimes)
                xline(obj.AxLFP, adjFingerPeakTimes, ':', 'Color', fingerColor, ...
                    'LineWidth', 1.5, 'HandleVisibility', 'on', 'Layer', 'bottom', 'Tag', 'SyncMarker');
            end
        end
        
        function nudgeDelay(obj, ~, ~, stepMagnitude)
            obj.DelayField.Value = obj.DelayField.Value + stepMagnitude;
            renderLinkedPlots(obj);
        end
        
        function cbHemisphereChanged(obj, ~, ~)
            % Force a master wipe of the specific tagged elements, ensuring 
            % the new hemisphere triggers the "First Render" logic.
            delete(findobj(obj.AxLFP, 'Tag', 'StaticLFP'));
            delete(findobj(obj.AxIHandU, 'Tag', 'DynLine_Hand'));
            delete(findobj(obj.AxIHandU, 'Tag', 'DynPeaks_Hand'));
            delete(findobj(obj.AxFinger, 'Tag', 'DynLine_Finger'));
            delete(findobj(obj.AxFinger, 'Tag', 'DynPeaks_Finger'));
            delete(findobj(obj.AxLFP, 'Tag', 'SyncMarker'));
            
            cla(obj.AxLFP); cla(obj.AxIHandU); cla(obj.AxFinger);
            
            initializeAlignmentEngine(obj);
        end

        function cbManualDelayChanged(obj, ~, ~)
            % DO NOT use cla() here! 
            % Let renderLinkedPlots handle the smart tag-based cleanup so 
            % we don't lose the zoomed-in state or delete the heavy LFP line.
            renderLinkedPlots(obj);
        end
        
        function cbFinalizeWorkspace(obj, ~, ~)
            % --- CONFIRMATION DIALOG BEFORE IRREVERSIBLE LOCK ---
            confirmMsg = sprintf([ ...
                'Are you sure you want to lock the synchronization alignment (Delay: %.3f s)?\n\n' ...
                'Warning: Once locked, raw data streams are consolidated into the Master Clock. ' ...
                'Data ingestion, task mapping, and synchronization can no longer be changed.'], ...
                obj.DelayField.Value);
                
            userChoice = uiconfirm(obj.UIFigure, confirmMsg, 'Confirm Synchronization Lock', ...
                'Options', {'Lock & Proceed', 'Cancel'}, ...
                'DefaultOption', 2, ...
                'CancelOption', 2, ...
                'Icon', 'warning');
                
            if ~strcmp(userChoice, 'Lock & Proceed')
                return; % Abort and return to the Synchronization UI without changes
            end

            currentDelay = seconds(obj.DelayField.Value);
            obj.ParentApp.WorkspaceData.DelayIpg = currentDelay;
            
            w_obj = obj.ParentApp.WorkspaceData.WearablesObj;
            s_obj = obj.ParentApp.WorkspaceData.StreamingObj;
            
            unique_tasks = unique(string({w_obj.task_id}));
            AlignedData = [];
            warning_messages = string.empty; % Tracker for cropped data warnings
            
            for i = 1:numel(unique_tasks)
                t_id = unique_tasks(i);
                
                if t_id == "<Discard>" || t_id == "NaN" || t_id == "0"
                    continue; 
                end
                
                w_mask = string({w_obj.task_id}) == t_id;
                w_sub = w_obj(w_mask);
                if isempty(w_sub), continue; end
                
                lfp_nums = w_sub(1).lfp_rec_num; 
                lfp_nums = lfp_nums(~isnan(lfp_nums));
                if isempty(lfp_nums), continue; end
                
                % --- PRE-ALLOCATE CONCATENATION ARRAYS ---
                t_lfp_concat     = datetime.empty;
                data_lfp_concat  = [];
                t_stim_concat    = datetime.empty;
                data_stim_concat = [];
                
                % 1. Stitch all mapped LFPs for this task into one continuous timeline
                for k = 1:numel(lfp_nums)
                    rec_idx = lfp_nums(k);
                    
                    lfp_start = s_obj.streaming_parameters.time_domain.first_packet_datetimes{rec_idx};
                    lfp_start.TimeZone = '';
                    
                    t_lfp_part = lfp_start + seconds(s_obj.streaming_parameters.time_domain.time{rec_idx} - s_obj.streaming_parameters.time_domain.time{rec_idx}(1));
                    t_lfp_part.TimeZone = '';
                    
                    t_stim_part = lfp_start + seconds(s_obj.streaming_parameters.stim_amp.time{rec_idx} - s_obj.streaming_parameters.stim_amp.time{rec_idx}(1));
                    t_stim_part.TimeZone = '';
                    
                    % Append to master arrays
                    t_lfp_concat     = [t_lfp_concat; t_lfp_part(:)];
                    data_lfp_concat  = [data_lfp_concat; s_obj.streaming_parameters.time_domain.data{rec_idx}];
                    
                    t_stim_concat    = [t_stim_concat; t_stim_part(:)];
                    data_stim_concat = [data_stim_concat; s_obj.streaming_parameters.stim_amp.data{rec_idx}];
                end
                
                % Sort to ensure chronological order (in case user mapped them out of order)
                [t_lfp_concat, sort_lfp] = sort(t_lfp_concat);
                data_lfp_concat = data_lfp_concat(sort_lfp, :);
                
                [t_stim_concat, sort_stim] = sort(t_stim_concat);
                data_stim_concat = data_stim_concat(sort_stim, :);
                
                % Now create the SINGLE entry for this Task
                entry = struct();
                entry.task_id = t_id;
                entry.lfp_rec_num = lfp_nums; % Keep array for reference
                
                if isfield(w_sub, 'symptom')
                    entry.symptom = string(w_sub(1).symptom);
                else
                    entry.symptom = "Unknown";
                end
                
                % --- PRE-ALLOCATE TOP-LEVEL SENSORS ---
                entry.HandSensorL   = table(); entry.HandSensorR   = table();
                entry.FingerSensorL = table(); entry.FingerSensorR = table();
                
                % 2. Determine Minimum Common Overlap Bounds (Smart Contextual Cropping)
                global_start = max(t_lfp_concat(1), t_stim_concat(1));
                global_end   = min(t_lfp_concat(end), t_stim_concat(end));
                
                start_culprit = "LFP/Stim";
                end_culprit   = "LFP/Stim";
                
                % Deduce Titration Side to prevent Ipsilateral sensors from cropping the Master Clock
                is_titration = endsWith(t_id, "L", 'IgnoreCase', true) || endsWith(t_id, "R", 'IgnoreCase', true) || endsWith(t_id, "a", 'IgnoreCase', true) || endsWith(t_id, "b", 'IgnoreCase', true);
                if is_titration
                    if endsWith(t_id, "L", 'IgnoreCase', true) || endsWith(t_id, "a", 'IgnoreCase', true)
                        contra_suffix = "R"; % Left Hemi Titration -> Right Body
                    else
                        contra_suffix = "L"; % Right Hemi Titration -> Left Body
                    end
                end
                
                for w_idx = 1:numel(w_sub)
                    sensor_name = string(w_sub(w_idx).wearable_id);
                    t_w = w_sub(w_idx).time - currentDelay;
                    t_w.TimeZone = '';
                    
                    restrict_bounds = true;
                    if is_titration && ~endsWith(sensor_name, contra_suffix, 'IgnoreCase', true)
                        % DO NOT let ipsilateral missing data crop the master timeline!
                        restrict_bounds = false; 
                    end
                    
                    if restrict_bounds && ~isempty(t_w)
                        if t_w(1) > global_start
                            global_start = t_w(1);
                            start_culprit = sensor_name;
                        end
                        if t_w(end) < global_end
                            global_end = t_w(end);
                            end_culprit = sensor_name;
                        end
                    end
                end
                
                % Skip if the restricting streams do not overlap at all
                if global_start >= global_end
                    warning_messages(end+1) = sprintf('Task %s (Rec %s): Complete loss of overlap between %s and %s.', ...
                        t_id, strjoin(string(lfp_nums), '&'), start_culprit, end_culprit); %#ok<AGROW>
                    continue; 
                end
                
                % =========================================================
                % AUDIT TITRATION LEVEL PRESERVATION (15s THRESHOLD)
                % =========================================================
                raw_stim_data = data_stim_concat; % Audit the stitched data
                t_stim        = t_stim_concat;
                if is_titration
                    titrating_col = 1;
                    if endsWith(t_id, "R", 'IgnoreCase', true) || endsWith(t_id, "b", 'IgnoreCase', true)
                        titrating_col = 2;
                    end
                    
                    if size(raw_stim_data, 2) >= titrating_col
                        raw_stim_target = round(raw_stim_data(:, titrating_col), 1);
                        unique_lvls = unique(raw_stim_target);
                        
                        % Count original stable levels (>= 15s)
                        orig_count = 0;
                        for u = 1:numel(unique_lvls)
                            mask = (raw_stim_target == unique_lvls(u));
                            if any(mask) && seconds(t_stim(find(mask, 1, 'last')) - t_stim(find(mask, 1, 'first'))) >= 15
                                orig_count = orig_count + 1;
                            end
                        end
                        
                        % Count stable levels remaining after temporal cropping
                        cropped_mask = (t_stim >= global_start) & (t_stim <= global_end);
                        t_stim_crop = t_stim(cropped_mask);
                        stim_crop_target = raw_stim_target(cropped_mask);
                        
                        crop_count = 0;
                        for u = 1:numel(unique_lvls)
                            mask = (stim_crop_target == unique_lvls(u));
                            if any(mask) && seconds(t_stim_crop(find(mask, 1, 'last')) - t_stim_crop(find(mask, 1, 'first'))) >= 15
                                crop_count = crop_count + 1;
                            end
                        end
                        
                        % Log a warning if a valid level was destroyed
                        if crop_count < orig_count
                            warning_messages(end+1) = sprintf('Task %s (Rec %s): Lost %d valid titration step(s).\n  -> Start constrained by: %s\n  -> End constrained by: %s', ...
                                t_id, strjoin(string(lfp_nums), '&'), orig_count - crop_count, start_culprit, end_culprit); %#ok<AGROW>
                        end
                    end
                end
                % =========================================================
                
                % 3. Create the Master Clock
                valid_lfp_mask = (t_lfp_concat >= global_start) & (t_lfp_concat <= global_end);
                master_time = t_lfp_concat(valid_lfp_mask);
                entry.CommonTime = master_time(:); 
                
                % 4. Embed LFP Data
                entry.LFP.data = data_lfp_concat(valid_lfp_mask, :);
                entry.LFP.channel_names = s_obj.streaming_parameters.time_domain.channel_names{lfp_nums(1)};
                
                % 5. Interpolate Stimulation Data 
                entry.Stim.data = interp1(t_stim_concat, data_stim_concat, entry.CommonTime, 'previous', 'extrap');
                
                % 6. Interpolate Wearables Kinematics into Top-Level N x V Tables
                for w_idx = 1:numel(w_sub)
                    w_item = w_sub(w_idx);
                    sensor_name = string(w_item.wearable_id);
                    
                    t_w = w_item.time - currentDelay;
                    t_w.TimeZone = '';
                    
                    if isempty(t_w), continue; end
                    
                    % Ensure unique time coordinates for interp1
                    [t_w_uniq, uniq_idx] = unique(t_w);
                    
                    var_names = w_item.data.Properties.VariableNames;
                    temp_struct = struct();
                    
                    for v = 1:numel(var_names)
                        col_name = var_names{v};
                        col_data = w_item.data.(col_name);
                        
                        if isnumeric(col_data)
                            col_data_uniq = col_data(uniq_idx);
                            interp_col = interp1(t_w_uniq, col_data_uniq, entry.CommonTime, 'linear', NaN);
                            temp_struct.(col_name) = interp_col(:);
                        end
                    end
                    
                    if isfield(entry, sensor_name)
                        entry.(sensor_name) = struct2table(temp_struct);
                    end
                end
                
                if isempty(AlignedData)
                    AlignedData = entry;
                else
                    AlignedData(end+1) = entry; %#ok<AGROW>
                end
            end
            
            % --- PUSH TO GLOBAL WORKSPACE MEMORY ---
            obj.ParentApp.WorkspaceData.AlignedData = AlignedData;
            obj.ParentApp.WorkspaceData.DelayIpg    = currentDelay;
            
            % --- ALIGN BRAINSENSE LFP OBJ 1-TO-1 WITH ALIGNED DATA ---
            if isfield(obj.ParentApp.WorkspaceData, 'BrainSenseLfpObj') && ~isempty(AlignedData)
                old_bs = obj.ParentApp.WorkspaceData.BrainSenseLfpObj;
                % A task can have multiple LFPs, map the primary (first) LFP to the BrainSense obj
                valid_indices = arrayfun(@(x) x.lfp_rec_num(1), AlignedData); 
                obj.ParentApp.WorkspaceData.BrainSenseLfpObj = old_bs(valid_indices); 
            end
                        
            obj.ParentApp.WorkspaceData = rmfield(obj.ParentApp.WorkspaceData, "StreamingObj");
            obj.ParentApp.WorkspaceData = rmfield(obj.ParentApp.WorkspaceData, "WearablesObj");
            obj.ParentApp.WorkspaceData = rmfield(obj.ParentApp.WorkspaceData, "ProtocolSections");
            
            obj.ParentApp.updateStatus(sprintf('✔ Data streams micro-alignment locked. Master Clock generated. Delay: %.3fs.', ...
                obj.DelayField.Value));
            obj.ParentApp.IsTimeAligned = true;
            
            if ismethod(obj.ParentApp, 'refreshStateEngine')
                obj.ParentApp.refreshStateEngine();
            end
            
            % --- SHOW WARNINGS BEFORE CLOSING ---
            if ~isempty(warning_messages)
                hWarn = warndlg(strjoin(warning_messages, '\n\n'), 'Data Cropping Warning', 'modal');
                uiwait(hWarn); 
            end
            
            delete(obj.UIFigure);
        end
        
        function cbCloseWindow(obj, ~, ~)
            delete(obj.UIFigure);
        end
    end
end