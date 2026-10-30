classdef DBSgram_KinematicSelectorUI < handle
    % DBSgram_KinematicSelectorUI - Wizard-Driven Synchronized Stacked Sensor Profiler
    
    properties
        ParentApp           DBSgram_MainUI
        UIFigure            matlab.ui.Figure
        MainGrid            matlab.ui.container.GridLayout
        ControlPanel        matlab.ui.container.Panel
        PlotPanel           matlab.ui.container.Panel
        
        LblSectionTitle     matlab.ui.control.Label
                
        % Interval UI Elements
        BtnResetIntervals   matlab.ui.control.Button
        
        % Bradykinesia Peak Evaluation UI Elements
        DropdownStepSelect  matlab.ui.control.DropDown
        BtnResetMarkers       matlab.ui.control.Button
        
        BtnBack             matlab.ui.control.Button
        BtnConfirmNext      matlab.ui.control.Button
        TxtInfo             matlab.ui.control.TextArea
        
        % Dual stacked timeline diagnostic charts
        TileGrid            matlab.graphics.layout.TiledChartLayout
        AxTop               matlab.graphics.axis.Axes
        AxBottom            matlab.graphics.axis.Axes
    end
    
    properties (Access = private)
        AuditedSections     string
        CurrentSection      string
        CurrentSectionIdx   double = 1 % Master sequential wizard index pointer
        MarkerLines         = [] 
        ActiveDragLine      = [] 
        
        % Time series data storage buffers
        TimeVectorTop       datetime
        AccelMagTop         double
        WarmStimLevelsTop   double
        
        TimeVectorBottom    datetime
        AccelMagBottom      double
        StimLevelsBottom    double

        % Bradykinesia metrics buffers
        FingerGX            double % Extracted Angular Velocity for Bradykinesia
        HandGX              double % NEW: Extracted Angular Velocity for Hand (Palm)
        RelativeCleanGX     double % NEW: Filtered Differential Kinematics

        % Rigidity metrics buffers
        HandGY             double % Angular velocity for distal rigidity sensor
        HandAZ               double % Angular velocity for proximal rigidity sensor
        RelativeRigidityGX  double % Filtered differential kinematics for Rigidity (Flexion/Extension)
        
        UniqueStimSteps     double
        ContralateralID     string
        TopSensorName       string
        BottomSensorName    string
        SymptomEvaluated    string
        
        % Multi-Mode UI State Tracking
        CurrentUIMode       string = "IntervalSelection" % "IntervalSelection" or "PeakValidation"
        
        % Bradykinesia Tracking
        IsBradyTask         logical = false
        BradyStepData       struct
        ActiveBradyStepIdx  double = 1
        
        % NEW: Rigidity Tracking
        IsRigidityTask         logical = false
        RigidityStepData       struct
        ActiveRigidityStepIdx  double = 1
    end
    
    methods
        function obj = DBSgram_KinematicSelectorUI(parentHandle)
            obj.ParentApp = parentHandle;
            
            ws = obj.ParentApp.WorkspaceData;
            if ~isfield(ws, 'audited_run_labels') || isempty(ws.audited_run_labels)
                uialert(obj.ParentApp.UIFigure, 'Please execute the Data Quality Auditor stage before evaluating symptoms.', 'Workflow Blocked');
                return;
            end
            
            valid_list = string.empty;
            for i = 1:numel(ws.audited_run_labels)
                lbl = string(ws.audited_run_labels(i));
                if ismember(lbl, ["0", "1", "2L", "2R", "5"]), continue; end
                
                if contains(lbl, 'L') && ws.verified_left_mask(i)
                    valid_list(end+1) = lbl; %#ok<AGROW>
                elseif contains(lbl, 'R') && ws.verified_right_mask(i)
                    valid_list(end+1) = lbl; %#ok<AGROW>
                end
            end
            
            obj.AuditedSections = unique(valid_list);
            if isempty(obj.AuditedSections)
                uialert(obj.ParentApp.UIFigure, 'No titration runs passed the quality criteria for symptom analysis.', 'Data Deficit');
                return;
            end
            
            obj.CurrentSection = obj.AuditedSections(obj.CurrentSectionIdx);
            buildUI(obj);
            evaluateAndOptimizeWindows(obj);
        end
    end
    
    methods (Access = private)
        function buildUI(obj)
            screensize = get(groot,'ScreenSize');
            w = screensize(3) * 0.9; h = screensize(4) * 0.85; 
            x = (screensize(3)-w)/2; y = (screensize(4)-h)/2;
            obj.UIFigure = uifigure('Name', 'Specialized Synchronized Multilevel Kinematic Selector', ...
                                   'Position', [x, y, w, h]);
            obj.MainGrid = uigridlayout(obj.UIFigure, [1, 2]);
            obj.MainGrid.ColumnWidth = {350, '1x'};
            
            % --- SIDEBAR CONTROL LAYOUT PANEL ---
            obj.ControlPanel = uipanel(obj.MainGrid, 'Title', 'Interval Configurations');
            ctrlLayout = uigridlayout(obj.ControlPanel, [7, 1]);
            
            ctrlLayout.RowHeight = {40, 30, 30, 30, 40, '1x'};
            ctrlLayout.Padding = [10 10 10 10]; ctrlLayout.RowSpacing = 8;
            
            obj.LblSectionTitle = uilabel(ctrlLayout, 'Text', 'Protocol Step: INITIALIZING', ...
                'FontSize', 14, 'FontWeight', 'bold', 'FontColor', [0 0.45 0.74]);
            
            % Interval Phase Control
            obj.BtnResetIntervals = uibutton(ctrlLayout, 'Text', '↺ Auto-Detect Boundaries', ...
                'FontSize', 11, 'ButtonPushedFcn', @(src, event) obj.cbResetIntervals(src, event));
                
            % Hidden controls reserved for Bradykinesia Peak Validation mode
            obj.DropdownStepSelect = uidropdown(ctrlLayout, 'Items', {'Select Step...'}, ...
                'Visible', 'off', 'ValueChangedFcn', @(src, event) obj.cbStepDropdownChanged(src, event));
            
            obj.BtnResetMarkers = uibutton(ctrlLayout, 'Text', '↺ Reset Step Peaks to Auto-Detect', ...
                'Visible', 'off', 'FontSize', 11, 'ButtonPushedFcn', @(src, event) obj.cbResetStepPeaks(src, event));
            
            % Wizard navigation layout segment grid
            navGrid = uigridlayout(ctrlLayout, [1, 2]);
            navGrid.Padding = [0 0 0 0]; navGrid.ColumnSpacing = 10;
            obj.BtnBack = uibutton(navGrid, 'Text', '◀ Back', ...
                'ButtonPushedFcn', @(src, event) obj.cbNavigateStep(src, event, -1));
            obj.BtnConfirmNext = uibutton(navGrid, 'Text', 'Confirm & Next ▶', ...
                'BackgroundColor', [0.85 0.95 0.85], 'FontWeight', 'bold', ...
                'ButtonPushedFcn', @(src, event) obj.cbNavigateStep(src, event, 1));
            
            obj.TxtInfo = uitextarea(ctrlLayout, 'Editable', 'off', 'FontAngle', 'normal', 'FontSize', 11);
            
            % --- TIMELINE CHART PANEL (STACKED DUAL VIEW) ---
            obj.PlotPanel = uipanel(obj.MainGrid, 'Title', 'Synchronized Absolute Datetime Timelines');
            obj.TileGrid = tiledlayout(obj.PlotPanel, 2, 1, 'Padding', 'compact', 'TileSpacing', 'compact');
            
            obj.AxTop = nexttile(obj.TileGrid, 1); hold(obj.AxTop, 'on'); grid(obj.AxTop, 'on');
            obj.AxBottom = nexttile(obj.TileGrid, 2); hold(obj.AxBottom, 'on'); grid(obj.AxBottom, 'on');
            
            % Initial link
            linkaxes([obj.AxTop, obj.AxBottom], 'x');
        end
        
        function evaluateAndOptimizeWindows(obj)
            % 1. Enforce UI Reset to Interval Mode
            obj.CurrentUIMode = "IntervalSelection";
            obj.BtnResetIntervals.Visible  = 'on';
            obj.DropdownStepSelect.Visible = 'off';
            obj.BtnResetMarkers.Visible      = 'off';
            
            
            % =========================================================
            % --- NUCLEAR WIPE: PREPARE PHASE 1 CANVAS ---
            % =========================================================
            linkaxes([obj.AxTop, obj.AxBottom], 'off');
            
            legend(obj.AxTop, 'off');
            legend(obj.AxBottom, 'off');
            
            % Wipe all 4 possible axis sides and unlock their limits
            yyaxis(obj.AxTop, 'left');     cla(obj.AxTop);  obj.AxTop.YLimMode = 'auto';
            yyaxis(obj.AxTop, 'right');    cla(obj.AxTop);  obj.AxTop.YLimMode = 'auto';
            yyaxis(obj.AxBottom, 'left');  cla(obj.AxBottom); obj.AxBottom.YLimMode = 'auto';
            yyaxis(obj.AxBottom, 'right'); cla(obj.AxBottom); obj.AxBottom.YLimMode = 'auto';
            
            % Erase all objects (including stubborn ConstantLines from Phase 2)
            delete(findall(obj.AxTop, 'Type', 'Line'));
            delete(findall(obj.AxBottom, 'Type', 'Line'));
            delete(findall(obj.AxTop, 'Type', 'ConstantRegion'));
            delete(findall(obj.AxBottom, 'Type', 'ConstantRegion'));
            delete(findall(obj.AxTop, 'Type', 'ConstantLine'));
            delete(findall(obj.AxBottom, 'Type', 'ConstantLine'));
            
            % Re-prep the axes
            hold(obj.AxTop, 'on');  grid(obj.AxTop, 'on');
            hold(obj.AxBottom, 'on'); grid(obj.AxBottom, 'on');
            % =========================================================
            
            obj.CurrentSection = obj.AuditedSections(obj.CurrentSectionIdx);
            char_label = char(obj.CurrentSection);
            hemi_side = char_label(end);
            
            % V0.1 Logic: If testing Left Hemisphere ('L'), evaluate Right side ('R')
            if hemi_side == 'L'
                obj.ContralateralID = "Contralateral Right Body (Left Hemisphere Titration)";
                target_side_str = "R";
                full_side_str = "Right";
                hemi_str = "Left";
            else
                obj.ContralateralID = "Contralateral Left Body (Right Hemisphere Titration)";
                target_side_str = "L";
                full_side_str = "Left";
                hemi_str = "Right";
            end
            
            % Dynamic navigation button status updates
            obj.BtnBack.Enable = (obj.CurrentSectionIdx > 1);
            if obj.CurrentSectionIdx == numel(obj.AuditedSections)
                obj.BtnConfirmNext.Text = '🔒 Save & Finish';
                obj.BtnConfirmNext.BackgroundColor = [0.76 0.89 0.76];
            else
                obj.BtnConfirmNext.Text = 'Confirm & Next ▶';
                obj.BtnConfirmNext.BackgroundColor = [0.85 0.95 0.85];
            end
            
            % --- EXTRACT FROM PRE-ALIGNED MASTER CLOCK (AlignedData) ---
            a_data = obj.ParentApp.WorkspaceData.AlignedData;
            block_idx = find(string({a_data.task_id}) == obj.CurrentSection, 1);
            
            if isempty(block_idx)
                cla(obj.AxTop); cla(obj.AxBottom);
                title(obj.AxTop, 'Error: AlignedData block not found for this section.');
                return;
            end
            
            current_block = a_data(block_idx);
            
            % Resolve exact dynamic table names
            sensor_top_key = sprintf('HandSensor%s', target_side_str);
            sensor_bot_key = sprintf('FingerSensor%s', target_side_str);
            
            if ~isfield(current_block, sensor_top_key) || ~isfield(current_block, sensor_bot_key) || ...
               isempty(current_block.(sensor_top_key)) || isempty(current_block.(sensor_bot_key))
                cla(obj.AxTop); cla(obj.AxBottom);
                title(obj.AxTop, 'Error: Kinematic sensor tables missing from this AlignedData block.');
                return;
            end
            
            if isfield(current_block, 'symptom') && current_block.symptom ~= "NaN"
                obj.SymptomEvaluated = string(current_block.symptom);
            else
                obj.SymptomEvaluated = "Titration Assessment Profile";
            end
            
            % Identify Bradykinesia Task for Phase 2 Evaluation
            obj.IsBradyTask = (strcmpi(obj.SymptomEvaluated, "Bradykinesia") || ...
                               strcmpi(obj.SymptomEvaluated, "OpenCloseHand") || ...
                               ismember(obj.CurrentSection, ["4L", "4R", "4a", "4b"]));
            % Identify Rigidity Task for Phase 2 Evaluation
            obj.IsRigidityTask = (strcmpi(obj.SymptomEvaluated, "Rigidity") || ...
                                  ismember(obj.CurrentSection, ["3L", "3R", "3a", "3b"]));
                           
            % Update Blue Formatting Dynamic Title
            obj.LblSectionTitle.Text = sprintf('Protocol Run: %s - %s Hemisphere titration', ...
                obj.SymptomEvaluated, hemi_str);
            
            obj.TopSensorName    = sprintf('%s HandSensor Tracker Profile', full_side_str);
            obj.BottomSensorName = sprintf('%s FingerSensor Tracker Profile', full_side_str);
            
            % --- PERFECTLY ALIGNED TIMELINES ---
            % Since SyncUI generated CommonTime, both sensors share the exact same timeline
            obj.TimeVectorTop    = current_block.CommonTime;
            obj.TimeVectorBottom = current_block.CommonTime;
            
            % Top Sensor (Hand)
            ax_t = current_block.(sensor_top_key).ax;
            ay_t = current_block.(sensor_top_key).ay;
            az_t = current_block.(sensor_top_key).az;
            obj.AccelMagTop = sqrt(ax_t.^2 + ay_t.^2 + az_t.^2);
            obj.HandGX = current_block.(sensor_top_key).gx; % EXTRACT PALM GX
            
            % Bottom Sensor (Finger)
            ax_b = current_block.(sensor_bot_key).ax;
            ay_b = current_block.(sensor_bot_key).ay;
            az_b = current_block.(sensor_bot_key).az;
            obj.AccelMagBottom = sqrt(ax_b.^2 + ay_b.^2 + az_b.^2);
            obj.FingerGX = current_block.(sensor_bot_key).gx;
            
            % Perfectly Interpolated Stimulation Values
            if contains(obj.CurrentSection, 'L'), h_ptr = 1; else, h_ptr = 2; end
            
            obj.WarmStimLevelsTop = current_block.Stim.data(:, h_ptr);
            obj.StimLevelsBottom  = current_block.Stim.data(:, h_ptr);
            
            % --- FIX: Dynamically calculate Master Clock Sample Rate ---
            if length(obj.TimeVectorTop) >= 2
                fs = round(1 / seconds(obj.TimeVectorTop(2) - obj.TimeVectorTop(1)));
            else
                fs = 250; % Safe fallback
            end
            rounded_stim = round(obj.WarmStimLevelsTop, 1);
            raw_steps = unique(rounded_stim);
            
            valid_steps = double.empty;
            for i = 1:numel(raw_steps)
                v = raw_steps(i);
                % A step must be held for a cumulative 15 seconds to be valid
                if sum(rounded_stim == v) >= (15 * fs) 
                    valid_steps(end+1) = v; %#ok<AGROW>
                end
            end
            obj.UniqueStimSteps = sort(valid_steps);
            num_steps = numel(obj.UniqueStimSteps);
            
            % --- RENDER AXES AND RESET DATA TYPES ---
            yyaxis(obj.AxTop, 'left'); cla(obj.AxTop);
            plot(obj.AxTop, obj.TimeVectorTop, obj.AccelMagTop, 'Color', [0.2 0.2 0.2]);
            ylabel(obj.AxTop, 'Accel (g)'); obj.AxTop.YAxis(1).Color = [0.2 0.2 0.2];
            
            yyaxis(obj.AxTop, 'right'); cla(obj.AxTop);
            plot(obj.AxTop, obj.TimeVectorTop, obj.WarmStimLevelsTop, 'Color', [0.85 0.33 0.1], 'LineWidth', 1.4);
            ylabel(obj.AxTop, 'Stim (mA)'); obj.AxTop.YAxis(2).Color = [0.85 0.33 0.1];
            title(obj.AxTop, obj.TopSensorName);
            
            yyaxis(obj.AxBottom, 'left'); cla(obj.AxBottom);
            plot(obj.AxBottom, obj.TimeVectorBottom, obj.AccelMagBottom, 'Color', [0.2 0.4 0.6]);
            ylabel(obj.AxBottom, 'Accel (g)'); obj.AxBottom.YAxis(1).Color = [0.2 0.4 0.6];
            
            yyaxis(obj.AxBottom, 'right'); cla(obj.AxBottom);
            plot(obj.AxBottom, obj.TimeVectorBottom, obj.StimLevelsBottom, 'Color', [0.85 0.33 0.1], 'LineWidth', 1.4);
            ylabel(obj.AxBottom, 'Stim (mA)'); obj.AxBottom.YAxis(2).Color = [0.85 0.33 0.1];
            title(obj.AxBottom, obj.BottomSensorName);
            
            yyaxis(obj.AxTop, 'left'); yyaxis(obj.AxBottom, 'left');
            
            % NOW Re-link axes because they both have standard datetime properties again!
            linkaxes([obj.AxTop, obj.AxBottom], 'x');
            
            obj.MarkerLines = [];
            
            field_key = sprintf('titration_bounds_%s_synchronized', obj.CurrentSection);
            has_existing_bounds = isfield(obj.ParentApp.WorkspaceData, field_key) && ...
                                  ~isempty(obj.ParentApp.WorkspaceData.(field_key));
            
            if has_existing_bounds
                saved_bounds = obj.ParentApp.WorkspaceData.(field_key);
            end
            
            for s = 1:num_steps
                val = obj.UniqueStimSteps(s);
                step_indices = find(rounded_stim == val);
                if numel(step_indices) < (10 * fs), continue; end
                
                if has_existing_bounds && s <= size(saved_bounds, 1) && (saved_bounds{s,1} == val)
                    % Restore user adjustments directly from workspace fields
                    est_start = saved_bounds{s,2};
                    est_end   = saved_bounds{s,3};
                else
                    % --- DYNAMIC BASELINE RAW ISOLATOR ---
                    t_sub = obj.TimeVectorTop(step_indices);
                    a_sub_top = obj.AccelMagTop(step_indices);
                    
                    a_sub_bot = interp1(obj.TimeVectorBottom, obj.AccelMagBottom, t_sub, 'linear', 'extrap');
                    
                    base_top = movmedian(a_sub_top, round(2.0 * fs));
                    base_bot = movmedian(a_sub_bot, round(2.0 * fs));
                    
                    move_top = abs(a_sub_top - base_top);
                    move_bot = abs(a_sub_bot - base_bot);
                    move_sig = move_top + move_bot;
                    
                    env = movmean(move_sig, round(0.5 * fs));
                    
                    peak_val = prctile(env, 98);
                    threshold = max(0.08, peak_val * 0.15); 
                    
                    active_idx = find(env > threshold);
                    
                    if ~isempty(active_idx)
                        split_pts = find(diff(active_idx) > round(1.5 * fs));
                        c_starts = [active_idx(1); active_idx(split_pts + 1)];
                        c_ends   = [active_idx(split_pts); active_idx(end)];
                        
                        [~, best_idx] = max(c_ends - c_starts);
                        b_start = c_starts(best_idx);
                        b_end   = c_ends(best_idx);
                        
                        raw_active = find(move_sig(b_start:b_end) > threshold);
                        if ~isempty(raw_active)
                            win_start_idx = b_start + raw_active(1) - 1;
                            win_end_idx   = b_start + raw_active(end) - 1;
                        else
                            win_start_idx = b_start;
                            win_end_idx   = b_end;
                        end
                        
                        pad = round(0.1 * fs);
                        win_start_idx = max(1, win_start_idx - pad);
                        win_end_idx   = min(length(t_sub), win_end_idx + pad);
                    else
                        win_start_idx = round(0.25 * length(t_sub));
                        win_end_idx   = round(0.75 * length(t_sub));
                    end
                    
                    est_start = t_sub(win_start_idx);
                    est_end   = t_sub(win_end_idx);
                end
                
                mTopIn   = xline(obj.AxTop, est_start, '--g', sprintf('%.1fmA In', val), 'LineWidth', 1.3);
                mTopOut  = xline(obj.AxTop, est_end, '--r', sprintf('%.1fmA Out', val), 'LineWidth', 1.3);
                mBotIn   = xline(obj.AxBottom, est_start, '--g', 'LineWidth', 1.3);
                mBotOut  = xline(obj.AxBottom, est_end, '--r', 'LineWidth', 1.3);
                
                mTopIn.UserData  = struct('partner', mBotIn,  'stepVal', val, 'type', 'In');
                mBotIn.UserData  = struct('partner', mTopIn,  'stepVal', val, 'type', 'In');
                mTopOut.UserData = struct('partner', mBotOut, 'stepVal', val, 'type', 'Out');
                mBotOut.UserData = struct('partner', mTopOut, 'stepVal', val, 'type', 'Out');
                
                mTopIn.ButtonDownFcn  = @(src, event) obj.startLineDrag(src, event);
                mTopOut.ButtonDownFcn = @(src, event) obj.startLineDrag(src, event);
                mBotIn.ButtonDownFcn  = @(src, event) obj.startLineDrag(src, event);
                mBotOut.ButtonDownFcn = @(src, event) obj.startLineDrag(src, event);
                
                obj.MarkerLines = [obj.MarkerLines; mTopIn; mTopOut]; %#ok<AGROW>
            end
            
            updateLogTextSummary(obj);
            xlim(obj.AxTop, [obj.TimeVectorTop(1), obj.TimeVectorTop(end)]);
        end
        
        function cbResetIntervals(obj, ~, ~)
            field_key = sprintf('titration_bounds_%s_synchronized', obj.CurrentSection);
            if isfield(obj.ParentApp.WorkspaceData, field_key)
                obj.ParentApp.WorkspaceData = rmfield(obj.ParentApp.WorkspaceData, field_key);
            end
            evaluateAndOptimizeWindows(obj);
        end
        
        function startLineDrag(obj, src, ~)
            obj.ActiveDragLine = src;
            obj.UIFigure.WindowButtonMotionFcn = @(fSrc, fEvent) obj.trackLineDrag();
            obj.UIFigure.WindowButtonUpFcn     = @(fSrc, fEvent) obj.stopLineDrag();
        end
        
        function trackLineDrag(obj)
            if ~isempty(obj.ActiveDragLine) && isvalid(obj.ActiveDragLine)
                ax_target = obj.ActiveDragLine.Parent;
                cp = ax_target.CurrentPoint;
                x_numeric = cp(1,1);
                
                try
                    adjusted_time = num2ruler(x_numeric, ax_target.XAxis);
                    obj.ActiveDragLine.Value = adjusted_time;
                    
                    if isstruct(obj.ActiveDragLine.UserData) && isfield(obj.ActiveDragLine.UserData, 'partner')
                        obj.ActiveDragLine.UserData.partner.Value = adjusted_time;
                    end
                    
                    updateLogTextSummary(obj);
                    drawnow limitrate;
                catch
                end
            end
        end
        
        function stopLineDrag(obj)
            obj.UIFigure.WindowButtonMotionFcn = '';
            obj.UIFigure.WindowButtonUpFcn     = '';
            obj.ActiveDragLine = [];
            updateLogTextSummary(obj);
        end
        
        function updateLogTextSummary(obj)
            if obj.CurrentUIMode == "IntervalSelection"

                lines = {sprintf('Discovered Levels Count: %d', numel(obj.UniqueStimSteps)); ...
                           '-----------------------------------------'};
                for s = 1:2:numel(obj.MarkerLines)
                    mIn = obj.MarkerLines(s);
                    mOut = obj.MarkerLines(s+1);
                    
                    if isvalid(mIn) && isvalid(mOut)
                        val = mIn.UserData.stepVal;
                        lines = [lines; {sprintf('Step %.1fmA -> [%s to %s]', ...
                            val, datestr(mIn.Value, 'HH:MM:SS'), datestr(mOut.Value, 'HH:MM:SS'))}]; %#ok<AGROW>
                    end
                end
                
            elseif obj.CurrentUIMode == "PeakValidation"

                k = obj.ActiveRigidityStepIdx;
                if isempty(obj.RigidityStepData) || k > numel(obj.RigidityStepData), return; end
                
                sdata = obj.RigidityStepData(k);
                
                % Build the text for the System Log
                lines = string(sprintf('--- STEP %.1f mA METRICS ---', sdata.level_mA));
                
                lines(end+1) = sprintf('PASSIVE CYCLES (Count: %d)', sum(~[sdata.cycles.is_activated]));
                lines(end+1) = sprintf('  ROM: %.1f°', sdata.mean_rom_passive);
                lines(end+1) = sprintf('  P2P Vel: %.1f deg/s', sdata.mean_p2p_pass);
                lines(end+1) = sprintf('  HCR (Cogwheel): %.3f', sdata.hcr_pass);
                lines(end+1) = sprintf('  ICD (Catches): %.2f / cyc', sdata.icd_pass);
                lines(end+1) = sprintf('  DSR (Symmetry): %.2f', sdata.dsr_pass);
                lines(end+1) = sprintf('  ncRMS (Normalized Jitter Energy): %.1f ', sdata.crms_pass);
                
                lines(end+1) = "";
                lines(end+1) = sprintf('ACTIVATED CYCLES (Count: %d)', sum([sdata.cycles.is_activated]));
                lines(end+1) = sprintf('  ROM: %.1f°', sdata.mean_rom_activated);
                lines(end+1) = sprintf('  P2P Vel: %.1f deg/s', sdata.mean_p2p_act);
                lines(end+1) = sprintf('  HCR (Cogwheel): %.3f', sdata.hcr_act);
                lines(end+1) = sprintf('  ICD (Catches): %.2f / cyc', sdata.icd_act);
                lines(end+1) = sprintf('  DSR (Symmetry): %.2f', sdata.dsr_act);
                lines(end+1) = sprintf('  ncRMS (Normalized Jitter Energy): %.1f', sdata.crms_act);
               
            end
            obj.TxtInfo.Value = lines; 
        end
       
        % =========================================================================
        % RIGIDITY INTERACTIVE PEAK DETECTION & PERSISTENCE LOGIC
        % =========================================================================
        
        function initializeRigidityPeakData(obj, forceResetStepIdx)
            if nargin < 2, forceResetStepIdx = -1; end
            
            obj.RigidityStepData = struct();
            field_key = sprintf('titration_bounds_%s_synchronized', obj.CurrentSection);
            if ~isfield(obj.ParentApp.WorkspaceData, field_key), return; end
            
            saved_bounds = obj.ParentApp.WorkspaceData.(field_key);
            task_id = string(obj.CurrentSection);
            
            % Extract signals from AlignedData dynamically based on the section
            a_data = obj.ParentApp.WorkspaceData.AlignedData;
            block_idx = find(string({a_data.task_id}) == task_id, 1);
            a_block = a_data(block_idx);
            
            % Resolve Evaluated vs. Contralateral sensors
            if endsWith(task_id, "L", 'IgnoreCase', true) || endsWith(task_id, "a", 'IgnoreCase', true)
                eval_sensor = "HandSensorR"; act_sensor = "FingerSensorL";
                if ~isfield(a_block, act_sensor) || isempty(a_block.(act_sensor)), act_sensor = "HandSensorL"; end
            else
                eval_sensor = "HandSensorL"; act_sensor = "FingerSensorR";
                if ~isfield(a_block, act_sensor) || isempty(a_block.(act_sensor)), act_sensor = "HandSensorR"; end
            end
            
            master_time  = a_block.CommonTime;
            sensor_table = a_block.(eval_sensor);
            
            if length(master_time) >= 2
                fs = round(1 / seconds(master_time(2) - master_time(1)));
            else
                fs = 50; 
            end
            
            % --- DSP PRE-CLEANING & FILTERING ---
            [b_band, a_band] = butter(3, [0.2 12] / (fs / 2), 'bandpass');
            
            raw_gy = fillmissing(double(sensor_table.gy), 'linear', 'EndValues', 'nearest');
            raw_az = fillmissing(double(sensor_table.az), 'linear', 'EndValues', 'nearest');
            gy_f = filtfilt(b_band, a_band, raw_gy);
            az_f = filtfilt(b_band, a_band, raw_az);
            
            act_acc_f = zeros(size(gy_f));
            if isfield(a_block, act_sensor) && ~isempty(a_block.(act_sensor))
                act_tbl = a_block.(act_sensor);
                c_ax = fillmissing(double(act_tbl.ax), 'linear', 'EndValues', 'nearest');
                c_ay = fillmissing(double(act_tbl.ay), 'linear', 'EndValues', 'nearest');
                c_az = fillmissing(double(act_tbl.az), 'linear', 'EndValues', 'nearest');
                
                % =========================================================
                % THE FROMENT'S FILTER
                % Bandpass 0.5 to 2.5 Hz.
                % This captures voluntary movement (1-2 Hz) and COMPLETELY
                % ERASES resting tremor (4-6 Hz) before the envelope is made.
                % =========================================================
                [b_act, a_act] = butter(3, [0.5 2.5] / (fs / 2), 'bandpass');
                
                act_acc_f = sqrt(filtfilt(b_act, a_act, c_ax).^2 + filtfilt(b_act, a_act, c_ay).^2 + filtfilt(b_act, a_act, c_az).^2);
            end
            smooth_contra_acc = movmean(act_acc_f, round(0.5 * fs));
            
            % Save full arrays to object for canvas rendering references
            obj.HandGY = gy_f;
            obj.HandAZ = az_f;
            obj.RelativeRigidityGX = smooth_contra_acc; % Reusing property for contralateral envelope
            obj.TimeVectorBottom = master_time;
            
            % --- PROCESS EACH TITRATION STEP ---
            task_key = sprintf('Task_%s', obj.CurrentSection);
            existing_data = [];
            if isfield(obj.ParentApp.WorkspaceData, 'validated_rigidity_peaks') && ...
               isfield(obj.ParentApp.WorkspaceData.validated_rigidity_peaks, task_key)
                existing_data = obj.ParentApp.WorkspaceData.validated_rigidity_peaks.(task_key);
            end
            
            for k = 1:size(saved_bounds, 1)
                lvl  = saved_bounds{k, 1};
                t_st = saved_bounds{k, 2};
                t_en = saved_bounds{k, 3};
                
                mask = (master_time >= t_st & master_time <= t_en);
                t_seg       = master_time(mask);
                gy_seg      = gy_f(mask);    
                az_seg      = az_f(mask);    
                sm_act_seg  = smooth_contra_acc(mask);
                raw_act_seg = act_acc_f(mask);
                
                % 1. Extract base cycles
                cycles = obj.extractNativeRigidityCycles(gy_seg, az_seg, fs);
                
                % Check for existing user cycle deletions
                if forceResetStepIdx ~= k && ~isempty(existing_data) && k <= numel(existing_data)
                    if existing_data(k).level_mA == lvl && isfield(existing_data(k), 'cycles')
                        cycles = existing_data(k).cycles;
                    end
                end
                
                if ~isempty(cycles)
                    % 2. Activation Logic
                    first_act_found = false;
                    for c = 1:numel(cycles)
                        act_window = sm_act_seg(cycles(c).st_idx : cycles(c).en_idx);
                        prop_above_thresh = sum(act_window > 0.1) / length(act_window);
                        
                        if prop_above_thresh >= 0.50 || first_act_found
                            cycles(c).is_activated = true;
                            first_act_found = true; 
                        else
                            cycles(c).is_activated = false;
                        end
                    end

                    % 2. Activation Logic
                    first_act_found = false;
                    for c = 1:numel(cycles)
                        act_window = sm_act_seg(cycles(c).st_idx : cycles(c).en_idx);
                        prop_above_thresh = sum(act_window > 0.1) / length(act_window);
                        
                        if prop_above_thresh >= 0.50 || first_act_found
                            cycles(c).is_activated = true;
                            first_act_found = true; 
                        else
                            cycles(c).is_activated = false;
                        end
                    end


                    % 3. Independent State Streak Isolation
                    valid_mask = false(1, numel(cycles));
                    max_gap = 0.75 * fs; 
                    
                    % Process Passive
                    pass_idx = find(~[cycles.is_activated]);
                    if ~isempty(pass_idx)
                        str_ids = ones(1, numel(pass_idx)); curr_str = 1;
                        for i = 2:numel(pass_idx)
                            if (cycles(pass_idx(i)).st_idx - cycles(pass_idx(i-1)).en_idx) > max_gap, curr_str = curr_str + 1; end
                            str_ids(i) = curr_str;
                        end
                        counts = zeros(1, curr_str); for i = 1:curr_str, counts(i) = sum(str_ids == i); end
                        [~, best_str] = max(counts); valid_mask(pass_idx(str_ids == best_str)) = true;
                    end
                    
                    % Process Activated
                    act_idx = find([cycles.is_activated]);
                    if ~isempty(act_idx)
                        str_ids = ones(1, numel(act_idx)); curr_str = 1;
                        for i = 2:numel(act_idx)
                            if (cycles(act_idx(i)).st_idx - cycles(act_idx(i-1)).en_idx) > max_gap, curr_str = curr_str + 1; end
                            str_ids(i) = curr_str;
                        end
                        counts = zeros(1, curr_str); for i = 1:curr_str, counts(i) = sum(str_ids == i); end
                        [~, best_str] = max(counts); valid_mask(act_idx(str_ids == best_str)) = true;
                    end
                    
                    cycles = cycles(valid_mask);
                    
                    % 4. Seamless Gap Bridging
                    for c = 2:numel(cycles)
                        gap = cycles(c).st_idx - cycles(c-1).en_idx;
                        if gap > 0 && gap <= (1.0 * fs)
                            mid_pt = floor((cycles(c).st_idx + cycles(c-1).en_idx) / 2);
                            cycles(c-1).en_idx = mid_pt;
                            cycles(c).st_idx   = mid_pt + 1;
                        end
                    end
                    
                    % 5. Metrics Compilation
                    t_act_window = t_seg(cycles(1).st_idx : cycles(end).en_idx);
                    
                    passive_cycles   = cycles(~[cycles.is_activated]);
                    activated_cycles = cycles([cycles.is_activated]);
                    
                    if ~isempty(passive_cycles)
                        mean_rom_pass = mean([passive_cycles.gy_rom], 'omitnan');
                        mean_p2p_pass = mean([passive_cycles.gy_p2p], 'omitnan');
                    else
                        mean_rom_pass = NaN; mean_p2p_pass = NaN;
                    end
                    [hcr_p, icd_p, dsr_p, crms_p] = obj.computeAdvancedRigidityMetrics(gy_seg, passive_cycles, fs);
                    
                    has_act = false;
                    if ~isempty(activated_cycles)
                        mean_rom_act = mean([activated_cycles.gy_rom], 'omitnan');
                        mean_p2p_act = mean([activated_cycles.gy_p2p], 'omitnan');
                        has_act = true;
                    else
                        mean_rom_act = NaN; mean_p2p_act = NaN;
                    end
                    [hcr_a, icd_a, dsr_a, crms_a] = obj.computeAdvancedRigidityMetrics(gy_seg, activated_cycles, fs);
                else
                    t_act_window = []; has_act = false;
                    mean_rom_pass = NaN; mean_p2p_pass = NaN; hcr_p = NaN; icd_p = NaN; dsr_p = NaN; crms_p = NaN;
                    mean_rom_act = NaN; mean_p2p_act = NaN; hcr_a = NaN; icd_a = NaN; dsr_a = NaN; crms_a = NaN;
                end
                
                obj.RigidityStepData(k).level_mA           = lvl;
                obj.RigidityStepData(k).t_seg              = t_seg;
                obj.RigidityStepData(k).gy_seg             = gy_seg;
                obj.RigidityStepData(k).az_seg             = az_seg;
                obj.RigidityStepData(k).sm_act_seg         = sm_act_seg;
                obj.RigidityStepData(k).cycles             = cycles;
                obj.RigidityStepData(k).t_act_window       = t_act_window;
                obj.RigidityStepData(k).has_activation     = has_act;
                
                % The New Split Metrics
                obj.RigidityStepData(k).mean_rom_passive   = mean_rom_pass;
                obj.RigidityStepData(k).mean_p2p_pass      = mean_p2p_pass;
                obj.RigidityStepData(k).hcr_pass           = hcr_p;
                obj.RigidityStepData(k).icd_pass           = icd_p;
                obj.RigidityStepData(k).dsr_pass           = dsr_p;
                obj.RigidityStepData(k).crms_pass          = crms_p;
                
                obj.RigidityStepData(k).mean_rom_activated = mean_rom_act;
                obj.RigidityStepData(k).mean_p2p_act       = mean_p2p_act;
                obj.RigidityStepData(k).hcr_act            = hcr_a;
                obj.RigidityStepData(k).icd_act            = icd_a;
                obj.RigidityStepData(k).dsr_act            = dsr_a;
                obj.RigidityStepData(k).crms_act           = crms_a;
            end
        end

        function cycles = extractNativeRigidityCycles(~, gy_sig, az_sig, fs)
            cycles = struct('az_p_loc', {}, 'az_v_loc', {}, ...
                            'gy_pk', {}, 'gy_p_loc', {}, 'gy_vl', {}, 'gy_v_loc', {}, ...
                            'st_idx', {}, 'mid_idx', {}, 'en_idx', {}, ...
                            'gy_rom', {}, 'gy_p2p', {});
            
            if isempty(az_sig) || length(az_sig) < (3 * fs), return; end
            
            % --- Aggressive 2.5 Hz filter to isolate pure macro phases ---
            [b_mac, a_mac] = butter(2, 2.5 / (fs / 2), 'low');
            az_macro = filtfilt(b_mac, a_mac, double(az_sig));
            gy_macro = filtfilt(b_mac, a_mac, double(gy_sig)); 
            
            min_dist = max(5, round(0.3 * fs)); 
            
            % TWEAK 1: Restored prominence to ignore pure noise ripples
            min_prom = 0.10; 
            
            [~, az_p_locs] = findpeaks(az_macro, 'MinPeakDistance', min_dist, 'MinPeakProminence', min_prom);
            [~, az_v_locs] = findpeaks(-az_macro, 'MinPeakDistance', min_dist, 'MinPeakProminence', min_prom);
            
            valid_pairs = [];
            for i = 1:length(az_p_locs)
                p_loc = az_p_locs(i);
                
                % Windowed Deepest-Valley Search (Bypasses Cogwheel Rebounds)
                if i < length(az_p_locs)
                    search_end = az_p_locs(i+1);
                else
                    search_end = min(length(az_macro), p_loc + round(2.5 * fs)); 
                end
                
                valid_v_indices = find(az_v_locs > p_loc & az_v_locs < search_end);
                
                if ~isempty(valid_v_indices)
                    candidate_v_locs = az_v_locs(valid_v_indices);
                    [~, deepest_idx] = min(az_macro(candidate_v_locs));
                    v_loc = candidate_v_locs(deepest_idx);
                else
                    [~, min_rel_idx] = min(az_macro(p_loc:search_end));
                    v_loc = p_loc + min_rel_idx - 1;
                end
                
                % TWEAK 2: Restored gravity drop to 0.20g (filters weak half-sweeps)
                if (az_macro(p_loc) - az_macro(v_loc)) >= 0.20
                    valid_pairs = [valid_pairs; p_loc, v_loc]; %#ok<AGROW>
                end
            end
            
            cnt = 1;
            for i = 1:size(valid_pairs, 1)
                az_p = valid_pairs(i, 1);
                az_v = valid_pairs(i, 2);
                
                st_gy_p = max(1, az_p - round(0.5 * fs));
                en_gy_p = min(length(gy_sig), az_p + round(0.2 * fs));
                [gy_pk_val, gy_pk_rel] = max(gy_sig(st_gy_p:en_gy_p));
                gy_p_loc = st_gy_p + gy_pk_rel - 1;
                
                st_gy_v = max(1, az_p);
                en_gy_v = min(length(gy_sig), az_v + round(0.2 * fs));
                [gy_vl_val, gy_vl_rel] = min(gy_sig(st_gy_v:en_gy_v));
                gy_v_loc = st_gy_v + gy_vl_rel - 1;
                
                % =====================================================================
                % TWEAK 3: KINEMATIC QUALITY GATES (Matches your manual rejections!)
                % 1. Must pull up at least 100 deg/s
                % 2. Must push down at least -100 deg/s
                % 3. Total swing must be > 250 deg/s
                % =====================================================================
                if (gy_pk_val < 100.0) || (gy_vl_val > -100.0) || ((gy_pk_val - gy_vl_val) < 250.0)
                    continue; 
                end
                
                search_lim = round(1.0 * fs);
                z1_idx = find(gy_sig(max(1, gy_p_loc - search_lim) : gy_p_loc) <= 0, 1, 'last');
                if isempty(z1_idx), z1 = max(1, gy_p_loc - round(0.4*fs)); else, z1 = max(1, gy_p_loc - search_lim) + z1_idx - 1; end
                
                z2 = find(gy_sig(gy_p_loc:gy_v_loc) <= 0, 1, 'first') + gy_p_loc - 1;
                if isempty(z2), z2 = round((gy_p_loc + gy_v_loc)/2); end
                
                z3_idx = find(gy_sig(gy_v_loc : min(length(gy_sig), gy_v_loc + search_lim)) >= 0, 1, 'first');
                if isempty(z3_idx), z3 = min(length(gy_sig), gy_v_loc + round(0.4*fs)); else, z3 = gy_v_loc + z3_idx - 1; end
                
                if z3 > z1
                    cycles(cnt).az_p_loc = az_p; cycles(cnt).az_v_loc = az_v;
                    cycles(cnt).gy_pk = gy_pk_val; cycles(cnt).gy_p_loc = gy_p_loc;
                    cycles(cnt).gy_vl = gy_vl_val; cycles(cnt).gy_v_loc = gy_v_loc;
                    cycles(cnt).st_idx = z1; cycles(cnt).mid_idx = z2; cycles(cnt).en_idx = z3;
                    cycles(cnt).gy_rom = (trapz(gy_sig(z1:z2)) + trapz(abs(gy_sig(z2:z3)))) / fs;
                    cycles(cnt).gy_p2p = gy_pk_val - gy_vl_val;
                    cnt = cnt + 1;
                end
            end
            
            % --- TARGETED GYROSCOPE RESCUE PASS ---
            search_windows = [];
            if isempty(cycles)
                search_windows = [1, length(gy_sig)];
            else
                [~, sort_idx] = sort([cycles.st_idx]); cycles = cycles(sort_idx);
                
                if cycles(1).st_idx > (0.5 * fs)
                    search_windows = [search_windows; 1, cycles(1).st_idx];
                end
                
                for c = 1:numel(cycles)-1
                    if (cycles(c+1).st_idx - cycles(c).en_idx) > (0.5 * fs)
                        search_windows = [search_windows; cycles(c).en_idx, cycles(c+1).st_idx];
                    end
                end
                
                if (length(gy_sig) - cycles(end).en_idx) > (0.5 * fs)
                    search_windows = [search_windows; cycles(end).en_idx, length(gy_sig)];
                end
            end
            
            new_cycles = [];
            for w = 1:size(search_windows, 1)
                w_st = search_windows(w, 1);
                w_en = search_windows(w, 2);
                
                gy_gap_mac = gy_macro(w_st:w_en);
                min_gy_dist = round(0.3 * fs);
                
                % TWEAK 4: Rescue prominence returned to safe levels
                min_gy_prom = 60.0; 
                
                [~, gap_p_locs] = findpeaks(gy_gap_mac, 'MinPeakDistance', min_gy_dist, 'MinPeakProminence', min_gy_prom);
                [~, gap_v_locs] = findpeaks(-gy_gap_mac, 'MinPeakDistance', min_gy_dist, 'MinPeakProminence', min_gy_prom);
                
                for p = 1:length(gap_p_locs)
                    p_rel = gap_p_locs(p);
                    
                    if p < length(gap_p_locs)
                        search_end_rel = gap_p_locs(p+1);
                    else
                        search_end_rel = length(gy_gap_mac);
                    end
                    
                    valid_v_indices = find(gap_v_locs > p_rel & gap_v_locs < search_end_rel);
                    
                    if ~isempty(valid_v_indices)
                        candidate_v_locs = gap_v_locs(valid_v_indices);
                        [~, deepest_idx] = min(gy_gap_mac(candidate_v_locs));
                        v_rel = candidate_v_locs(deepest_idx);
                    else
                        [~, min_rel_idx] = min(gy_gap_mac(p_rel:search_end_rel));
                        v_rel = p_rel + min_rel_idx - 1;
                    end
                    
                    search_radius = round(0.2 * fs);
                    
                    st_p = max(w_st, w_st + p_rel - 1 - search_radius);
                    en_p = min(w_en, w_st + p_rel - 1 + search_radius);
                    [g_pk, raw_p_idx] = max(gy_sig(st_p:en_p));
                    g_p_loc = st_p + raw_p_idx - 1;
                    
                    st_v = max(w_st, w_st + v_rel - 1 - search_radius);
                    en_v = min(w_en, w_st + v_rel - 1 + search_radius);
                    [g_vl, raw_v_idx] = min(gy_sig(st_v:en_v));
                    g_v_loc = st_v + raw_v_idx - 1;
                    
                    % =====================================================================
                    % Apply the exact same Kinematic Quality Gates to the Rescue Pass
                    % =====================================================================
                    if (g_pk >= 100.0) && (g_vl <= -100.0) && ((g_pk - g_vl) >= 250.0)
                        
                        z1_idx = find(gy_sig(w_st:g_p_loc) <= 0, 1, 'last');
                        if isempty(z1_idx), z1 = w_st; else, z1 = w_st + z1_idx - 1; end
                        
                        z2 = find(gy_sig(g_p_loc:g_v_loc) <= 0, 1, 'first') + g_p_loc - 1;
                        if isempty(z2), z2 = round((g_p_loc + g_v_loc)/2); end
                        
                        z3_idx = find(gy_sig(g_v_loc:w_en) >= 0, 1, 'first');
                        if isempty(z3_idx), z3 = w_en; else, z3 = g_v_loc + z3_idx - 1; end
                        
                        if z3 > z1
                            [~, p_rel_az] = max(az_macro(z1:max(z1, z2))); az_res_p = z1 + p_rel_az - 1;
                            [~, v_rel_az] = min(az_macro(max(z1, z2):z3)); az_res_v = max(z1, z2) + v_rel_az - 1;
                            
                            rc = struct('az_p_loc', az_res_p, 'az_v_loc', az_res_v, ...
                                        'gy_pk', g_pk, 'gy_p_loc', g_p_loc, ...
                                        'gy_vl', g_vl, 'gy_v_loc', g_v_loc, ...
                                        'st_idx', z1, 'mid_idx', z2, 'en_idx', z3, ...
                                        'gy_rom', (trapz(gy_sig(z1:z2)) + trapz(abs(gy_sig(z2:z3)))) / fs, ...
                                        'gy_p2p', g_pk - g_vl);
                            
                            new_cycles = [new_cycles, rc];
                        end
                    end
                end
            end
            
            if ~isempty(new_cycles)
                cycles = [cycles, new_cycles];
            end
            
            % --- OVERLAP RESOLUTION & PERFECT ALIGNMENT ---
            if ~isempty(cycles)
                [~, sort_idx] = sort([cycles.st_idx]); cycles = cycles(sort_idx);
                for c = 1:numel(cycles)-1
                    if cycles(c).en_idx >= cycles(c+1).st_idx
                        cycles(c).en_idx = cycles(c+1).st_idx - 1;
                        cycles(c).mid_idx = min(cycles(c).mid_idx, max(cycles(c).st_idx, cycles(c).en_idx - 1));
                    end
                end
                for c = 1:numel(cycles)
                    z1 = cycles(c).st_idx; z2 = cycles(c).mid_idx; z3 = cycles(c).en_idx;
                    
                    if z2 > z1
                        [cycles(c).gy_pk, p_rel_gy] = max(gy_sig(z1:z2)); cycles(c).gy_p_loc = z1 + p_rel_gy - 1;
                        [~, p_rel_az] = max(az_macro(z1:z2)); cycles(c).az_p_loc = z1 + p_rel_az - 1;
                    end
                    
                    if z3 > z2
                        [cycles(c).gy_vl, v_rel_gy] = min(gy_sig(z2:z3)); cycles(c).gy_v_loc = z2 + v_rel_gy - 1;
                        [~, v_rel_az] = min(az_macro(z2:z3)); cycles(c).az_v_loc = z2 + v_rel_az - 1;
                    end
                    
                    cycles(c).gy_rom = (trapz(gy_sig(z1:z2)) + trapz(abs(gy_sig(z2:z3)))) / fs;
                    cycles(c).gy_p2p = cycles(c).gy_pk - cycles(c).gy_vl;
                end
            end
        end
        
        function [hcr, icd, dsr, ncrms] = computeAdvancedRigidityMetrics(obj, full_gy_seg, cycles, fs)
            if isempty(cycles)
                hcr = NaN; icd = NaN; dsr = NaN; ncrms = NaN;
                return;
            end
            
            % --- FILTERS ---
            % 1. Low-pass (15 Hz) for ICD and DSR 
            [b_lp, a_lp] = butter(2, 15 / (fs / 2), 'low');
            gy_filt = filtfilt(b_lp, a_lp, full_gy_seg);
            alpha_y = gradient(gy_filt) * fs;
            
            % 2. THE NEW SWEET SPOT: Bandpass (4.0 - 9.0 Hz) to isolate pure cogwheeling
            % This rejects both the clinician's 1Hz sweep AND the >9Hz floppy impact noise!
            [b_bp, a_bp] = butter(2, [4.0 9.0] / (fs / 2), 'bandpass');
            gy_cogwheel_band = filtfilt(b_bp, a_bp, full_gy_seg);
            
            num_cyc = numel(cycles);
            hcr_array   = NaN(1, num_cyc);
            icd_array   = NaN(1, num_cyc);
            dsr_array   = NaN(1, num_cyc);
            ncrms_array = NaN(1, num_cyc);
            
            for c = 1:num_cyc
                st = cycles(c).st_idx;
                en = cycles(c).en_idx;
                
                gy_cyc_raw   = full_gy_seg(st:en);
                gy_cyc_flt   = gy_filt(st:en);
                al_cyc       = alpha_y(st:en);
                bumps_4_9Hz  = gy_cogwheel_band(st:en); % Only the 4-9Hz data
                cyc_len      = length(gy_cyc_raw);
                
                if cyc_len < (fs * 0.5), continue; end 
                
                % ==============================================================
                % HCR (Harmonic Cogwheel Ratio) 
                % ==============================================================
                win = hann(cyc_len);
                gy_tapered = gy_cyc_raw .* win;
                p_carrier  = bandpower(gy_tapered, fs, [0.5 2.5]);
                p_cogwheel = bandpower(gy_tapered, fs, [4.0 9.0]);
                if p_carrier > 0, hcr_array(c) = p_cogwheel / p_carrier; end
                
                % ==============================================================
                % ICD (Inflection Catch Density)
                % ==============================================================
                pk_vel = max(abs(gy_cyc_flt));
                acc_std = std(al_cyc, 'omitnan');
                
                if pk_vel > 0 && acc_std > 0
                    vel_gate = abs(gy_cyc_flt) >= (0.10 * pk_vel);
                    prom_thresh = 0.50 * acc_std; 
                    
                    [pks, ~] = findpeaks(al_cyc, 'MinPeakProminence', prom_thresh);
                    [vls, ~] = findpeaks(-al_cyc, 'MinPeakProminence', prom_thresh);
                    
                    n_inflections = sum(vel_gate(al_cyc > 0 & ismember(al_cyc, pks))) + ...
                                    sum(vel_gate(al_cyc < 0 & ismember(-al_cyc, vls)));
                    
                    icd_array(c) = max(0, n_inflections - 2);
                end
                
                % ==============================================================
                % DSR (Directional Symmetry Ratio) 
                % ==============================================================
                true_pk = max(gy_cyc_flt);
                true_vl = abs(min(gy_cyc_flt));
                if true_pk > 0 && true_vl > 0, dsr_array(c) = true_vl / true_pk; end
                
                % ==============================================================
                % ncRMS (Targeted 4-9 Hz Normalized Cogwheel Energy)
                % ==============================================================
                total_energy    = rms(gy_cyc_raw);
                cogwheel_energy = rms(bumps_4_9Hz);
                
                if total_energy > 0
                    % Returns the targeted cogwheel jitter as a % of the total stroke energy
                    ncrms_array(c) = (cogwheel_energy / total_energy) * 100;
                end
            end
            
            % Compile final averaged metrics
            hcr   = mean(hcr_array, 'omitnan');
            icd   = mean(icd_array, 'omitnan');
            dsr   = median(dsr_array, 'omitnan'); 
            ncrms = mean(ncrms_array, 'omitnan');
        end
        
        function recalculateActiveStepMetrics(obj)
            k = obj.ActiveRigidityStepIdx;
            sdata = obj.RigidityStepData(k);
            cycles = sdata.cycles;
            
            pass_cycles = cycles(~[cycles.is_activated]);
            act_cycles  = cycles([cycles.is_activated]);
            
            % Resolve Sampling Rate safely
            if length(sdata.t_seg) >= 2
                fs = round(1 / seconds(sdata.t_seg(2) - sdata.t_seg(1)));
            else
                fs = 50; 
            end
            
            % --- PASSIVE METRICS ---
            if ~isempty(pass_cycles)
                sdata.mean_rom_passive = mean([pass_cycles.gy_rom], 'omitnan');
                sdata.mean_p2p_pass    = mean([pass_cycles.gy_p2p], 'omitnan');
            else
                sdata.mean_rom_passive = NaN; sdata.mean_p2p_pass = NaN;
            end
            [sdata.hcr_pass, sdata.icd_pass, sdata.dsr_pass, sdata.crms_pass] = obj.computeAdvancedRigidityMetrics(sdata.gy_seg, pass_cycles, fs);
            
            % --- ACTIVATED METRICS ---
            if ~isempty(act_cycles)
                sdata.mean_rom_activated = mean([act_cycles.gy_rom], 'omitnan');
                sdata.mean_p2p_act       = mean([act_cycles.gy_p2p], 'omitnan');
            else
                sdata.mean_rom_activated = NaN; sdata.mean_p2p_act = NaN;
            end
            [sdata.hcr_act, sdata.icd_act, sdata.dsr_act, sdata.crms_act] = obj.computeAdvancedRigidityMetrics(sdata.gy_seg, act_cycles, fs);
            
            % Save back to main object
            obj.RigidityStepData(k) = sdata;
            
            % Trigger UI Redraws
            obj.renderRigidityCanvas();
            obj.updateLogTextSummary();
        end

        % =========================================================================
        % DASHBOARD CANVAS RENDERING ENGINE (RIGIDITY)
        % =========================================================================
        function renderRigidityCanvas(obj)
            k = obj.ActiveRigidityStepIdx; 
            if isempty(obj.RigidityStepData) || k > numel(obj.RigidityStepData)
                return;
            end
            
            sdata = obj.RigidityStepData(k);
            
            % Unlink completely to prevent cross-axis limit pollution during redraw
            linkaxes([obj.AxTop, obj.AxBottom], 'off');
            
            % --- THE NUCLEAR OPTION: TOTAL DELETION ---
            legend(obj.AxTop, 'off');
            legend(obj.AxBottom, 'off');
            
            yyaxis(obj.AxTop, 'left');     cla(obj.AxTop);
            yyaxis(obj.AxTop, 'right');    cla(obj.AxTop);
            yyaxis(obj.AxBottom, 'left');  cla(obj.AxBottom);
            yyaxis(obj.AxBottom, 'right'); cla(obj.AxBottom);
            
            delete(findall(obj.AxTop, 'Type', 'Line'));
            delete(findall(obj.AxBottom, 'Type', 'Line'));
            delete(findall(obj.AxTop, 'Type', 'ConstantRegion'));
            delete(findall(obj.AxBottom, 'Type', 'ConstantRegion'));
            delete(findall(obj.AxTop, 'Type', 'ConstantLine'));
            delete(findall(obj.AxBottom, 'Type', 'ConstantLine'));
            % -----------------------------------------------------------
            
            
            % ===========================================================
            % --- TOP PLOT: GYROSCOPE (VELOCITY) ---
            % ===========================================================
            yyaxis(obj.AxTop, 'right'); 
            obj.AxTop.YAxis(2).Color = 'none'; % Hide the right axis scale
            
            yyaxis(obj.AxTop, 'left');  
            hold(obj.AxTop, 'on');
            
            % Plot Background
            plot(obj.AxTop, sdata.t_seg, sdata.gy_seg, 'Color', [0.8 0.8 0.8], 'LineWidth', 1.0, ...
                'LineStyle', '-', 'Marker', 'none', 'PickableParts', 'none', 'HitTest', 'off', 'DisplayName', 'g_y (Background)');
            
            if ~isempty(sdata.cycles)
                for c = 1:numel(sdata.cycles)
                    cyc = sdata.cycles(c);
                    t_cyc  = sdata.t_seg(cyc.st_idx:cyc.en_idx);
                    gy_cyc = sdata.gy_seg(cyc.st_idx:cyc.en_idx);
                    
                    if cyc.is_activated, cyc_color = [0.85 0.33 0.10]; 
                    else, cyc_color = [0.00 0.50 0.00]; end
                    
                    plot(obj.AxTop, t_cyc, gy_cyc, 'Color', cyc_color, 'LineWidth', 2.5, ...
                         'LineStyle', '-', 'Marker', 'none', 'HandleVisibility', 'off', 'PickableParts', 'none', 'HitTest', 'off');
                    
                    % Clickable Markers
                    hPos = plot(obj.AxTop, sdata.t_seg(cyc.gy_p_loc), cyc.gy_pk, 'rv', ...
                        'MarkerFaceColor', 'r', 'MarkerSize', 6, 'HandleVisibility', 'off', 'PickableParts', 'all');
                    set(hPos, 'ButtonDownFcn', @(src, ev) obj.cbPeakMarkerClicked(src, ev));
                    
                    hNeg = plot(obj.AxTop, sdata.t_seg(cyc.gy_v_loc), cyc.gy_vl, 'g^', ...
                        'MarkerFaceColor', 'g', 'MarkerSize', 6, 'HandleVisibility', 'off', 'PickableParts', 'all');
                    set(hNeg, 'ButtonDownFcn', @(src, ev) obj.cbPeakMarkerClicked(src, ev));
                end
                
                % Dummy lines for the pristine legend
                plot(obj.AxTop, NaN, NaN, 'Color', [0.00 0.50 0.00], 'LineWidth', 2.0, 'LineStyle', '-', 'Marker', 'none', 'DisplayName', 'Passive Cycles');
                plot(obj.AxTop, NaN, NaN, 'Color', [0.85 0.33 0.10], 'LineWidth', 2.0, 'LineStyle', '-', 'Marker', 'none', 'DisplayName', 'Activated Cycles (Froment''s)');
                
                % Background Shading
                if ~isempty(sdata.t_act_window)
                    xregion(obj.AxTop, sdata.t_act_window(1), sdata.t_act_window(end), 'FaceColor', [0.85 0.92 1.00], 'FaceAlpha', 0.4, 'HandleVisibility', 'off', 'HitTest', 'off', 'PickableParts', 'none');
                end
            end
            
            str_pass = 'N/A'; if ~isnan(sdata.mean_rom_passive), str_pass = sprintf('%.1f°', sdata.mean_rom_passive); end
            str_act  = 'N/A'; if ~isnan(sdata.mean_rom_activated), str_act = sprintf('%.1f°', sdata.mean_rom_activated); end
            
            str_p2p_p = 'N/A'; if ~isnan(sdata.mean_p2p_pass), str_p2p_p = sprintf('%.1f', sdata.mean_p2p_pass); end
            str_p2p_a = 'N/A'; if ~isnan(sdata.mean_p2p_act), str_p2p_a = sprintf('%.1f', sdata.mean_p2p_act); end
            
            title(obj.AxTop, sprintf('Evaluated Wrist Gyroscope [Step %.1f mA] | Passive ROM = %s | Act ROM = %s | P2P (P/A) = %s / %s deg/s', ...
                sdata.level_mA, str_pass, str_act, str_p2p_p, str_p2p_a), 'FontWeight', 'bold', 'FontSize', 10);
            ylabel(obj.AxTop, 'Angular Velocity (deg/s)');
            grid(obj.AxTop, 'on'); obj.AxTop.YAxis(1).Color = [0 0 0];
            
            % -- EXPLICIT DIRECT PROPERTY LIMITS (Immune to yyaxis bugs) --
            gy_min = min(sdata.gy_seg);
            gy_max = max(sdata.gy_seg);
            gy_range = gy_max - gy_min;
            if gy_range == 0 || isnan(gy_range), gy_range = 100; gy_min = -50; gy_max = 50; end
            
            obj.AxTop.YAxis(1).Limits = [gy_min - (gy_range * 0.10), gy_max + (gy_range * 0.35)]; % Left Axis
            obj.AxTop.YAxis(2).Limits = [0, 1]; % Right Axis (Hidden)
            
            legend(obj.AxTop, 'Location', 'northeast', 'Orientation', 'horizontal', 'Box', 'off', 'FontSize', 9);
            
            
            % ===========================================================
            % --- BOTTOM PLOT: ACCELEROMETER & CONTRA ENVELOPE ---
            % ===========================================================
            yyaxis(obj.AxBottom, 'left'); 
            hold(obj.AxBottom, 'on'); 
            obj.AxBottom.YColor = [0.00 0.35 0.85];
            
            plot(obj.AxBottom, sdata.t_seg, sdata.az_seg, 'Color', [0.00 0.35 0.85], 'LineWidth', 1.5, ...
                'LineStyle', '-', 'Marker', 'none', 'PickableParts', 'none', 'HitTest', 'off', 'DisplayName', 'a_z Evaluated Wrist');
            ylabel(obj.AxBottom, 'Acceleration (g)');
        
            yyaxis(obj.AxBottom, 'right'); 
            hold(obj.AxBottom, 'on'); 
            obj.AxBottom.YColor = [0.85 0.33 0.10];
            
            plot(obj.AxBottom, sdata.t_seg, sdata.sm_act_seg, 'Color', [0.85 0.33 0.10 0.7], 'LineWidth', 1.2, ...
                'LineStyle', ':', 'Marker', 'none', 'PickableParts', 'none', 'HitTest', 'off', 'DisplayName', 'Contra Smoothed Envelope');
            
            yline(obj.AxBottom, 0.1, 'r--', 'Activation Threshold (0.1g)', 'HandleVisibility', 'off', 'HitTest', 'off', 'LabelHorizontalAlignment', 'left');
            ylabel(obj.AxBottom, 'Contra Hand 3D Accel (g)');
            
            % -- EXPLICIT DIRECT PROPERTY LIMITS --
            az_min = min(sdata.az_seg);
            az_max = max(sdata.az_seg);
            az_range = az_max - az_min;
            if az_range == 0 || isnan(az_range), az_range = 2; az_min = -1; az_max = 1; end
            
            sm_min = min([min(sdata.sm_act_seg), 0]);
            sm_max = max([max(sdata.sm_act_seg), 0.12]); % Ensures threshold 0.1 is visible
            sm_range = sm_max - sm_min;
            if sm_range == 0 || isnan(sm_range), sm_range = 0.5; end
            
            obj.AxBottom.YAxis(1).Limits = [az_min - (az_range * 0.10), az_max + (az_range * 0.35)]; % Left Axis
            obj.AxBottom.YAxis(2).Limits = [sm_min - (sm_range * 0.05), sm_max + (sm_range * 0.35)]; % Right Axis
            
            if ~isempty(sdata.cycles)
                yyaxis(obj.AxBottom, 'left');
                for c = 1:numel(sdata.cycles)
                    cyc = sdata.cycles(c);
                    plot(obj.AxBottom, sdata.t_seg(cyc.az_p_loc), sdata.az_seg(cyc.az_p_loc), 'rv', 'MarkerFaceColor', 'r', 'MarkerSize', 6, 'HandleVisibility', 'off', 'PickableParts', 'none', 'HitTest', 'off');
                    plot(obj.AxBottom, sdata.t_seg(cyc.az_v_loc), sdata.az_seg(cyc.az_v_loc), 'g^', 'MarkerFaceColor', 'g', 'MarkerSize', 6, 'HandleVisibility', 'off', 'PickableParts', 'none', 'HitTest', 'off');
                end
                if ~isempty(sdata.t_act_window)
                    xregion(obj.AxBottom, sdata.t_act_window(1), sdata.t_act_window(end), 'FaceColor', [0.85 0.92 1.00], 'FaceAlpha', 0.4, 'HandleVisibility', 'off', 'HitTest', 'off', 'PickableParts', 'none');
                end
            end
            
            title(obj.AxBottom, sprintf('Gravity Phase Anchors & Contralateral Hand 3D Accel Envelope [Step %.1f mA]', sdata.level_mA), 'FontWeight', 'bold', 'FontSize', 10);
            grid(obj.AxBottom, 'on');
            
            legend(obj.AxBottom, 'Location', 'northeast', 'Orientation', 'horizontal', 'Box', 'off', 'FontSize', 9);
            
            % Restore X-axis linking exclusively
            linkaxes([obj.AxTop, obj.AxBottom], 'x');
            if ~isempty(sdata.t_act_window)
                pad_time = seconds(2.5);
                xlim(obj.AxTop, [max(sdata.t_seg(1), sdata.t_act_window(1) - pad_time), min(sdata.t_seg(end), sdata.t_act_window(end) + pad_time)]);
            else
                xlim(obj.AxTop, [sdata.t_seg(1), sdata.t_seg(end)]);
            end
        end

        % =========================================================================
        % BRADYKINESIA INTERACTIVE PEAK DETECTION & PERSISTENCE LOGIC
        % =========================================================================
        function initializeBradyPeakData(obj, forceResetStepIdx)
            if nargin < 2, forceResetStepIdx = -1; end
            
            obj.BradyStepData = struct();
            field_key = sprintf('titration_bounds_%s_synchronized', obj.CurrentSection);
            if ~isfield(obj.ParentApp.WorkspaceData, field_key), return; end
            
            saved_bounds = obj.ParentApp.WorkspaceData.(field_key);
            t_bottom = obj.TimeVectorBottom;
            
            % Compute sample rate dynamically from master clock
            if length(t_bottom) >= 2
                fs = round(1 / seconds(t_bottom(2) - t_bottom(1)));
            else
                fs = 50; % Default to Wearables fs
            end
            
            % =========================================================================
            % DSP CORRECTION: DIFFERENTIAL KINEMATICS & DRIFT REMOVAL
            % =========================================================================
            raw_finger_gx = obj.FingerGX;
            raw_hand_gx   = obj.HandGX;
            
            % Because the sensors are mounted on opposite sides (Palm vs. Dorsum),
            % their X-axes are inverted. We ADD them to cancel out common-mode 
            % wrist/arm rotation and isolate pure finger hinge kinematics.
            raw_relative_gx = raw_finger_gx + raw_hand_gx;
            
            % 1. Remove static baseline offset
            clean_gx = detrend(raw_relative_gx);
            
            % 2. Apply a 0.5 Hz High-Pass Filter to eliminate low-frequency integration drift
            try
                [b_hp, a_hp] = butter(2, 0.5 / (fs / 2), 'high');
                clean_gx = filtfilt(b_hp, a_hp, clean_gx);
            catch
                % Fallback if fs is too low/corrupt
            end
            
            obj.RelativeCleanGX = clean_gx; % Save for canvas rendering
            gx_signal = clean_gx;
            % =========================================================================
            
            task_key = sprintf('Task_%s', obj.CurrentSection);
            existing_data = [];
            if isfield(obj.ParentApp.WorkspaceData, 'validated_brady_peaks') && ...
               isfield(obj.ParentApp.WorkspaceData.validated_brady_peaks, task_key)
                existing_data = obj.ParentApp.WorkspaceData.validated_brady_peaks.(task_key);
            end
            
            for k = 1:size(saved_bounds, 1)
                lvl  = saved_bounds{k, 1};
                t_st = saved_bounds{k, 2};
                t_en = saved_bounds{k, 3};
                
                mask = (t_bottom >= t_st & t_bottom <= t_en);
                sig_step = gx_signal(mask);
                t_step   = t_bottom(mask);
                
                if isempty(sig_step)
                    obj.BradyStepData(k).level_mA   = lvl;
                    obj.BradyStepData(k).t_signal   = t_step;
                    obj.BradyStepData(k).signal     = sig_step;
                    obj.BradyStepData(k).cycles     = [];
                    obj.BradyStepData(k).t_active   = t_step;
                    obj.BradyStepData(k).rms_gx_1d  = 0;
                    obj.BradyStepData(k).mean_rom   = 0;
                    obj.BradyStepData(k).mean_ratio = NaN;
                    obj.BradyStepData(k).s_p2p      = 0;
                    obj.BradyStepData(k).s_rom      = 0;
                    continue;
                end
                
                % Standard Cycle Extraction
                cycles = obj.extractNativeCycles(sig_step, fs);
                
                % Check for existing user peak deletions
                if forceResetStepIdx ~= k && ~isempty(existing_data) && k <= numel(existing_data)
                    if existing_data(k).level_mA == lvl && isfield(existing_data(k), 'cycles')
                        cycles = existing_data(k).cycles;
                    end
                end
                
                % --- TRIMMED ACTIVE WINDOW & CORE METRICS ---
                if ~isempty(cycles)
                    z_start = cycles(1).z_start;
                    z_end   = cycles(end).z_end;
                    
                    sig_active = sig_step(z_start:z_end);
                    t_active   = t_step(z_start:z_end);
                    
                    % Now averages the pure opening phase RMS!
                    rms_gx_1d  = mean([cycles.rms_open]); 
                    mean_rom   = mean([cycles.rom_tot]);
                    mean_ratio = mean([cycles.ratio_oc], 'omitnan');
                else
                    t_active   = t_step;
                    rms_gx_1d  = 0;
                    mean_rom   = 0;
                    mean_ratio = NaN;
                end
                
                [s_p2p, s_rom] = obj.computeDecaySlope(cycles);
                
                obj.BradyStepData(k).level_mA   = lvl;
                obj.BradyStepData(k).t_signal   = t_step;
                obj.BradyStepData(k).signal     = sig_step;
                obj.BradyStepData(k).cycles     = cycles;
                obj.BradyStepData(k).t_active   = t_active;
                obj.BradyStepData(k).rms_gx_1d  = rms_gx_1d;
                obj.BradyStepData(k).mean_rom   = mean_rom;
                obj.BradyStepData(k).mean_ratio = mean_ratio;
                obj.BradyStepData(k).s_p2p      = s_p2p;
                obj.BradyStepData(k).s_rom      = s_rom;
            end
        end
        
        function cycles = extractNativeCycles(~, sig, fs)
            cycles = struct('pos_pk', {}, 'pos_loc', {}, 'neg_pk', {}, 'neg_loc', {}, ...
                            'rom_pos', {}, 'rom_neg', {}, 'rom_tot', {}, 'w_p2p', {}, 'ratio_oc', {}, ...
                            'z_start', {}, 'z_end', {}, 'rms_open', {});
            if isempty(sig), return; end
            
            % --- CLINICAL UPDATE: Forgiving Biomechanical Constraints ---
            min_dist = max(10, round(0.2 * fs)); 
            min_height_pos = 100; % Absolute minimum floor (100 deg/s is a very slow, but valid finger open)
            min_width = 1.5; 
            
            % Dynamic prominence relaxed to catch heavily decayed bradykinetic peaks
            sig_pos = sig(sig > 0);
            if isempty(sig_pos), min_prominence = 100; else
                % Lowered the absolute floor from 300 to 100, and percentile ratio to 20%
                min_prominence = max(100, 0.40 * prctile(sig_pos, 85)); 
            end
            
            try
                [pos_pks, pos_locs] = findpeaks(double(sig), ...
                    'MinPeakDistance', min_dist, 'MinPeakHeight', min_height_pos, ...
                    'MinPeakWidth', min_width, 'WidthReference', 'halfheight', ...
                    'MinPeakProminence', min_prominence);
            catch
                pos_pks = []; pos_locs = [];
            end
            
            if isempty(pos_locs), return; end
            
            cnt = 1;
            for i = 1:length(pos_locs)
                p_idx = pos_locs(i);
                p_val = pos_pks(i);
                
                if i < length(pos_locs)
                    search_end = pos_locs(i+1) - 1;
                else
                    search_end = min(length(sig), p_idx + round(0.8 * fs));
                end
                
                if search_end <= p_idx, continue; end
                
                search_win = sig(p_idx:search_end);
                [n_val, min_rel_idx] = min(search_win);
                n_idx = p_idx + min_rel_idx - 1;
                
                if n_val < 0
                    thresh_open = max(30, 0.05 * p_val); 
                    
                    z1 = p_idx;
                    while z1 > 1 && sig(z1) > thresh_open
                        z1 = z1 - 1;
                    end
                    
                    z2 = find(sig(p_idx:n_idx) <= 0, 1, 'first') + p_idx - 1;
                    if isempty(z2), z2 = round((p_idx + n_idx)/2); end
                    
                    thresh_close = min(-30, 0.05 * n_val); 
                    z3 = n_idx;
                    while z3 < length(sig) && sig(z3) < thresh_close
                        z3 = z3 + 1;
                    end
                    
                    r_pos = trapz(sig(z1:z2)) / fs;
                    r_neg = trapz(abs(sig(z2:z3))) / fs;
                    
                    cycles(cnt).pos_pk   = p_val;
                    cycles(cnt).pos_loc  = p_idx;
                    cycles(cnt).neg_pk   = n_val;
                    cycles(cnt).neg_loc  = n_idx;
                    cycles(cnt).rom_pos  = r_pos;
                    cycles(cnt).rom_neg  = r_neg;
                    cycles(cnt).rom_tot  = r_pos; 
                    cycles(cnt).rms_open = rms(sig(z1:z2));
                    cycles(cnt).w_p2p    = p_val - n_val;
                    cycles(cnt).ratio_oc = abs(p_val) / abs(n_val);
                    cycles(cnt).z_start  = z1;
                    cycles(cnt).z_end    = z3;
                    cnt = cnt + 1;
                end
            end
            
            % --- POST-DETECTION FILTER: Sequence-Effect Preserving ---
            if ~isempty(cycles)
                max_w_p2p = max([cycles.w_p2p]);
                max_pos   = max([cycles.pos_pk]);
                max_neg   = min([cycles.neg_pk]); 
                
                % Massively relaxed thresholds to allow for severe Parkinsonian decay.
                % The patient's cycles are now allowed to drop down to 20% of their 
                % original starting speed before the algorithm cuts them off.
                valid_mask = [cycles.rom_tot] >= 15.0 & ...
                             [cycles.w_p2p] >= (0.20 * max_w_p2p) & ...
                             [cycles.pos_pk] >= (0.15 * max_pos) & ...
                             abs([cycles.neg_pk]) >= (0.15 * abs(max_neg));
                             
                cycles = cycles(valid_mask);
            end
        end
        
        function [s_p2p, s_rom] = computeDecaySlope(~, cycles)
            num_cycles = numel(cycles);
            if num_cycles > 1
                cycle_idx = (1:num_cycles)';
                p_w = polyfit(cycle_idx, [cycles.w_p2p]', 1);
                s_p2p = p_w(1);
                
                p_r = polyfit(cycle_idx, [cycles.rom_tot]', 1);
                s_rom = p_r(1);
            else
                s_p2p = 0; s_rom = 0;
            end
        end
        
        % =========================================================================
        % DASHBOARD CANVAS RENDERING ENGINE
        % =========================================================================
        function renderBradykinesiaCanvas(obj)
            k = obj.ActiveBradyStepIdx;
            if isempty(obj.BradyStepData) || k > numel(obj.BradyStepData)
                return;
            end
            
            step_info = obj.BradyStepData(k);
            cycles    = step_info.cycles;
            num_cyc   = numel(cycles);
            
            % Unlink axes for independent scaling
            linkaxes([obj.AxTop, obj.AxBottom], 'off');
            
            % --- TOP PLOT: TRIMMED ACTIVE WINDOW & PEAKS ---
            yyaxis(obj.AxTop, 'right'); cla(obj.AxTop); obj.AxTop.YAxis(2).Color = 'none';
            yyaxis(obj.AxTop, 'left');  cla(obj.AxTop); hold(obj.AxTop, 'on');
            
            % 1. Full signal in light background gray (Uses Differential Signal)
            plot(obj.AxTop, obj.TimeVectorBottom, obj.RelativeCleanGX, 'Color', [0.75 0.75 0.75], 'LineWidth', 0.8);
            
            % 2. Active Window Shading & Active Signal
            if ~isempty(step_info.t_active)
                t_act_st = step_info.t_active(1);
                t_act_en = step_info.t_active(end);
                xregion(obj.AxTop, t_act_st, t_act_en, 'FaceColor', [0.85 0.92 1.00], 'FaceAlpha', 0.5, 'HandleVisibility', 'off');
            end
            plot(obj.AxTop, step_info.t_signal, step_info.signal, 'b-', 'LineWidth', 1.1);
            
            % 3. Plot Positive (red) and Negative (green) Peaks
            if num_cyc > 0
                pos_locs = [cycles.pos_loc]; pos_pks = [cycles.pos_pk];
                neg_locs = [cycles.neg_loc]; neg_pks = [cycles.neg_pk];
                
                t_step = step_info.t_signal;
                hPos = plot(obj.AxTop, t_step(pos_locs), pos_pks, 'rv', ...
                    'MarkerFaceColor', 'r', 'MarkerSize', 6, 'PickableParts', 'all');
                set(hPos, 'ButtonDownFcn', @(src, ev) obj.cbPeakMarkerClicked(src, ev));
                
                hNeg = plot(obj.AxTop, t_step(neg_locs), neg_pks, 'g^', ...
                    'MarkerFaceColor', 'g', 'MarkerSize', 6, 'PickableParts', 'all');
                set(hNeg, 'ButtonDownFcn', @(src, ev) obj.cbPeakMarkerClicked(src, ev));
                
                % NEW: Write the Opening ROM and Opening RMS explicitly above each red peak
                y_offset = max(pos_pks) * 0.15; % Slightly smaller offset to fit 2 lines
                for c = 1:num_cyc
                    text(obj.AxTop, t_step(pos_locs(c)), pos_pks(c) + y_offset, ...
                        sprintf('%.0f°\n(RMS: %.0f)', cycles(c).rom_tot, cycles(c).rms_open), 'FontSize', 8, 'FontWeight', 'bold', ...
                        'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom');
                end
            end
            
            % Update title to explicitly identify "Mean Opening RMS"
            title(obj.AxTop, sprintf('Differential Rel Vel g_x (Step %.1fmA) | Mean Opening RMS = %.1f deg/s | Mean Opening ROM = %.1f° | Mean R_{O/C} = %.2f', ...
                step_info.level_mA, step_info.rms_gx_1d, step_info.mean_rom, step_info.mean_ratio), 'FontWeight', 'bold', 'FontSize', 10);
            
            % Update title to specifically state "Opening ROM"
            title(obj.AxTop, sprintf('Differential Rel Vel g_x (Step %.1fmA) | RMS = %.1f deg/s | Mean Opening ROM = %.1f° | Mean R_{O/C} = %.2f', ...
                step_info.level_mA, step_info.rms_gx_1d, step_info.mean_rom, step_info.mean_ratio), 'FontWeight', 'bold', 'FontSize', 10);
            ylabel(obj.AxTop, 'Angular Velocity (deg/s)');
            obj.AxTop.YAxis(1).Color = [0 0 0];
            
            if ~isempty(step_info.t_signal)
                % REDUCED PADDING: Shrunk from 3 seconds down to 0.5 seconds
                t_pad = seconds(0.5); 
                t_start_pad = step_info.t_signal(1) - t_pad;
                t_end_pad   = step_info.t_signal(end) + t_pad;
                xlim(obj.AxTop, [t_start_pad, t_end_pad]);
                
                mask_pad = (obj.TimeVectorBottom >= t_start_pad) & (obj.TimeVectorBottom <= t_end_pad);
                local_sig = obj.RelativeCleanGX(mask_pad);
                if ~isempty(local_sig)
                    % Increased upper margin slightly to make room for the new text labels
                    y_margin = max(abs(local_sig)) * 0.15;
                    ylim(obj.AxTop, [min(local_sig) - y_margin, max(local_sig) + (y_margin * 2)]);
                end
            end
            grid(obj.AxTop, 'on');
            
            % --- BOTTOM PLOT: DECAY SLOPES & ASYMMETRY RATIO ---
            yyaxis(obj.AxBottom, 'left');  cla(obj.AxBottom); legend(obj.AxBottom, 'off');
            yyaxis(obj.AxBottom, 'right'); cla(obj.AxBottom);
            
            if num_cyc > 0
                w_p2p   = [cycles.w_p2p];
                rom_tot = [cycles.rom_tot];
                c_idx   = 1:num_cyc;
                
                yyaxis(obj.AxBottom, 'left');
                plot(obj.AxBottom, c_idx, w_p2p, 'b-o', 'LineWidth', 1.3, 'MarkerSize', 5, 'DisplayName', 'Wp2p Velocity'); hold(obj.AxBottom, 'on');
                if num_cyc > 1
                    p_w = polyfit(c_idx, w_p2p, 1);
                    plot(obj.AxBottom, c_idx, polyval(p_w, c_idx), 'b--', 'LineWidth', 1.5, 'DisplayName', 'Vel Fit');
                end
                ylabel(obj.AxBottom, 'Wp2p Velocity (deg/s)'); obj.AxBottom.YColor = [0 0.45 0.74];
                
                yyaxis(obj.AxBottom, 'right');
                plot(obj.AxBottom, c_idx, rom_tot, 'm-s', 'LineWidth', 1.3, 'MarkerSize', 5, 'DisplayName', 'Joint ROM'); hold(obj.AxBottom, 'on');
                if num_cyc > 1
                    p_r = polyfit(c_idx, rom_tot, 1);
                    plot(obj.AxBottom, c_idx, polyval(p_r, c_idx), 'm--', 'LineWidth', 1.5, 'DisplayName', 'ROM Fit');
                end
                ylabel(obj.AxBottom, 'Joint ROM (deg)'); obj.AxBottom.YColor = [0.75 0 0.75];
                
                title(obj.AxBottom, sprintf('Sequence Decay Slopes: Sp2p = %.2f deg/s/cyc | Srom = %.2f deg/cyc', ...
                    step_info.s_p2p, step_info.s_rom), 'FontWeight', 'bold', 'FontSize', 10);
                xlabel(obj.AxBottom, 'Cycle Index');
                xlim(obj.AxBottom, [0, max(2, num_cyc + 1)]);
            else
                yyaxis(obj.AxBottom, 'left');
                title(obj.AxBottom, 'Sequence Decay Slopes (No valid cycles remaining)', 'FontWeight', 'bold');
                xlabel(obj.AxBottom, 'Cycle Index');
            end
            grid(obj.AxBottom, 'on');
        end

        % =========================================================================
        % DYNAMIC UI INTERACTION CALLBACKS (Unified for Bradykinesia & Rigidity)
        % =========================================================================
        function cbPeakMarkerClicked(obj, ~, event)
            click_pt = event.IntersectionPoint;
            x_numeric = click_pt(1);
            t_click_dt = num2ruler(x_numeric, obj.AxTop.XAxis);
            
            % ---------------------------------------------------------------------
            % BRADYKINESIA BRANCH
            % ---------------------------------------------------------------------
            if obj.IsBradyTask
                k = obj.ActiveBradyStepIdx;
                step_info = obj.BradyStepData(k);
                cycles = step_info.cycles;
                if isempty(cycles), return; end
                
                % Check distance against BOTH positive and negative markers
                t_peaks_dt   = step_info.t_signal([cycles.pos_loc]);
                t_valleys_dt = step_info.t_signal([cycles.neg_loc]);
                
                [min_dist_p, min_idx_p] = min(abs(t_peaks_dt - t_click_dt));
                [min_dist_v, min_idx_v] = min(abs(t_valleys_dt - t_click_dt));
                
                if min_dist_p <= min_dist_v, min_idx = min_idx_p; else, min_idx = min_idx_v; end
                cycles(min_idx) = []; % Delete the accurately targeted cycle
                
                if ~isempty(cycles)
                    z_start = cycles(1).z_start;
                    z_end   = cycles(end).z_end;
                    step_info.t_active   = step_info.t_signal(z_start:z_end);
                    step_info.rms_gx_1d  = mean([cycles.rms_open]); 
                    step_info.mean_rom   = mean([cycles.rom_tot]);
                    step_info.mean_ratio = mean([cycles.ratio_oc], 'omitnan');
                else
                    step_info.t_active   = step_info.t_signal;
                    step_info.rms_gx_1d  = 0;
                    step_info.mean_rom   = 0;
                    step_info.mean_ratio = NaN;
                end
                
                [s_p2p, s_rom] = obj.computeDecaySlope(cycles);
                step_info.s_p2p  = s_p2p;
                step_info.s_rom  = s_rom;
                step_info.cycles = cycles;
                
                obj.BradyStepData(k) = step_info;
                renderBradykinesiaCanvas(obj);
                
                % Update log for Bradykinesia
                if ismethod(obj, 'updateLogTextSummary')
                    updateLogTextSummary(obj);
                end
            
            % ---------------------------------------------------------------------
            % RIGIDITY BRANCH
            % ---------------------------------------------------------------------
            elseif obj.IsRigidityTask
                k = obj.ActiveRigidityStepIdx;
                sdata = obj.RigidityStepData(k);
                cycles = sdata.cycles;
                if isempty(cycles), return; end
                
                % Check distance against BOTH red peaks and green valleys
                t_peaks_dt   = sdata.t_seg([cycles.gy_p_loc]);
                t_valleys_dt = sdata.t_seg([cycles.gy_v_loc]);
                
                [min_dist_p, min_idx_p] = min(abs(t_peaks_dt - t_click_dt));
                [min_dist_v, min_idx_v] = min(abs(t_valleys_dt - t_click_dt));
                
                if min_dist_p <= min_dist_v, min_idx = min_idx_p; else, min_idx = min_idx_v; end
                cycles(min_idx) = []; % Delete the accurately targeted cycle
                
                % Update the time window based on remaining cycles
                if ~isempty(cycles)
                    sdata.t_act_window = sdata.t_seg(cycles(1).st_idx : cycles(end).en_idx);
                else
                    sdata.t_act_window = [];
                end
                
                % Save the shortened cycle array back to the struct
                sdata.cycles = cycles;
                obj.RigidityStepData(k) = sdata;
                
                % FIRE THE RECALCULATOR
                % This dynamically computes ROM, P2P, HCR, ICD, and DSR, 
                % redraws the canvas, and updates the System Log!
                obj.recalculateActiveStepMetrics();
            end
        end

        function cbStepDropdownChanged(obj, ~, ~)
            selected_str = string(obj.DropdownStepSelect.Value);
            items_str = string(obj.DropdownStepSelect.Items);
            selected_idx = find(items_str == selected_str, 1);
            
            if obj.IsBradyTask
                obj.ActiveBradyStepIdx = selected_idx;
                renderBradykinesiaCanvas(obj);
            elseif obj.IsRigidityTask
                obj.ActiveRigidityStepIdx = selected_idx;
                renderRigidityCanvas(obj);

                % Force the system log to display the metrics for the newly selected step
                updateLogTextSummary(obj);
            end
        end
        
        function cbResetStepPeaks(obj, ~, ~)
            task_key = sprintf('Task_%s', obj.CurrentSection);
            
            if obj.IsBradyTask
                k = obj.ActiveBradyStepIdx;
                initializeBradyPeakData(obj, k);
                
                if isfield(obj.ParentApp.WorkspaceData, 'validated_brady_peaks') && ...
                   isfield(obj.ParentApp.WorkspaceData.validated_brady_peaks, task_key)
                   obj.ParentApp.WorkspaceData.validated_brady_peaks.(task_key)(k) = obj.BradyStepData(k);
                end
                renderBradykinesiaCanvas(obj);
                
            elseif obj.IsRigidityTask
                k = obj.ActiveRigidityStepIdx;
                initializeRigidityPeakData(obj, k);
                
                if isfield(obj.ParentApp.WorkspaceData, 'validated_rigidity_peaks') && ...
                   isfield(obj.ParentApp.WorkspaceData.validated_rigidity_peaks, task_key)
                   obj.ParentApp.WorkspaceData.validated_rigidity_peaks.(task_key)(k) = obj.RigidityStepData(k);
                end
                renderRigidityCanvas(obj);
            end
            
            if ismethod(obj, 'updateLogTextSummary')
                updateLogTextSummary(obj);
            end
        end
        
        % --- SEQUENTIAL STEP NAVIGATION CONTROLLER MECHANISMS ---
        function cbNavigateStep(obj, ~, ~, stepDirection)
            
            if stepDirection == 1
                if obj.CurrentUIMode == "IntervalSelection"
                    % 1. Save the intervals drawn on the screen
                    if ~isempty(obj.MarkerLines)
                        num_lines = numel(obj.MarkerLines);
                        saved_bounds = cell(num_lines/2, 3);
                        for i = 1:2:num_lines
                            pair_idx = (i+1)/2;
                            mIn = obj.MarkerLines(i); mOut = obj.MarkerLines(i+1);
                            saved_bounds{pair_idx, 1} = mIn.UserData.stepVal;            
                            saved_bounds{pair_idx, 2} = mIn.Value;                 
                            saved_bounds{pair_idx, 3} = mOut.Value;               
                        end
                        field_key = sprintf('titration_bounds_%s_synchronized', obj.CurrentSection);
                        obj.ParentApp.WorkspaceData.(field_key) = saved_bounds;
                    end
                    
                    % 2. INTERCEPT PHASE 2: BRADYKINESIA
                    if obj.IsBradyTask
                        obj.CurrentUIMode = "PeakValidation";
                        obj.BtnResetIntervals.Visible  = 'off';
                        obj.DropdownStepSelect.Visible = 'on';
                        obj.BtnResetMarkers.Visible      = 'on';
                        
                        step_items = arrayfun(@(v) sprintf('Inspect Step %.1fmA', v), obj.UniqueStimSteps, 'UniformOutput', false);
                        obj.DropdownStepSelect.Items = step_items;
                        obj.DropdownStepSelect.Value = step_items{1}; 
                        obj.ActiveBradyStepIdx = 1;
                        
                        obj.BtnBack.Enable = 'on';
                        if obj.CurrentSectionIdx == numel(obj.AuditedSections)
                            obj.BtnConfirmNext.Text = '🔒 Finalize Kinematics';
                        else
                            obj.BtnConfirmNext.Text = 'Confirm Peaks & Next ▶';
                        end
                        
                        initializeBradyPeakData(obj);
                        renderBradykinesiaCanvas(obj);
                        return; 
                        
                    % 3. INTERCEPT PHASE 2: RIGIDITY
                    elseif obj.IsRigidityTask
                        obj.CurrentUIMode = "PeakValidation";
                        obj.BtnResetIntervals.Visible  = 'off';
                        obj.DropdownStepSelect.Visible = 'on';
                        obj.BtnResetMarkers.Visible      = 'on';
                        
                        step_items = arrayfun(@(v) sprintf('Inspect Step %.1fmA', v), obj.UniqueStimSteps, 'UniformOutput', false);
                        obj.DropdownStepSelect.Items = step_items;
                        obj.DropdownStepSelect.Value = step_items{1}; 
                        obj.ActiveRigidityStepIdx = 1;
                        
                        obj.BtnBack.Enable = 'on';
                        if obj.CurrentSectionIdx == numel(obj.AuditedSections)
                            obj.BtnConfirmNext.Text = '🔒 Finalize Kinematics';
                        else
                            obj.BtnConfirmNext.Text = 'Confirm Cycles & Next ▶';
                        end
                        
                        initializeRigidityPeakData(obj);
                        renderRigidityCanvas(obj);
                        updateLogTextSummary(obj);
                        return; 
                    end
                    
                % 4. SAVE VALIDATED MARKERS ON EXITING PHASE 2
                elseif obj.CurrentUIMode == "PeakValidation" || obj.CurrentUIMode == "CycleValidation"
                    task_id = obj.AuditedSections(obj.CurrentSectionIdx);
                    if obj.IsBradyTask
                        obj.ParentApp.WorkspaceData.validated_brady_peaks.(sprintf('Task_%s', task_id)) = obj.BradyStepData;
                    elseif obj.IsRigidityTask
                        obj.ParentApp.WorkspaceData.validated_rigidity_peaks.(sprintf('Task_%s', task_id)) = obj.RigidityStepData;
                    end
                end
                
            elseif stepDirection == -1
                % GOING BACKWARDS: Save current markers, return to Interval Selection
                if obj.CurrentUIMode == "PeakValidation" || obj.CurrentUIMode == "CycleValidation"
                    task_id = obj.AuditedSections(obj.CurrentSectionIdx);
                    if obj.IsBradyTask
                        obj.ParentApp.WorkspaceData.validated_brady_peaks.(sprintf('Task_%s', task_id)) = obj.BradyStepData;
                    elseif obj.IsRigidityTask
                        obj.ParentApp.WorkspaceData.validated_rigidity_peaks.(sprintf('Task_%s', task_id)) = obj.RigidityStepData;
                    end
                    
                    evaluateAndOptimizeWindows(obj); % Resets UI back to Phase 1
                    return; 
                end
            end
            
            % Standard Navigation Progression (Moving to the next clinical task entirely)
            next_step = obj.CurrentSectionIdx + stepDirection;
            
            if next_step >= 1 && next_step <= numel(obj.AuditedSections)
                obj.CurrentSectionIdx = next_step;
                evaluateAndOptimizeWindows(obj);
            elseif next_step > numel(obj.AuditedSections)
                obj.ParentApp.updateStatus('✔ All active testing vs rest phases accurately defined and validated.');
                obj.ParentApp.IsKinIntervaled = true;
                obj.ParentApp.refreshStateEngine();
                delete(obj.UIFigure);
            end
        end
    end
end