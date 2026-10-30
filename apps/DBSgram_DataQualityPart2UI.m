classdef DBSgram_DataQualityPart2UI < handle
    % DBSgram_DataQualityPart2UI - 3x2 Multi-Modal Cross-Modality Timeline Auditor
    
    properties
        ParentApp           DBSgram_MainUI
        UIFigure            matlab.ui.Figure
        MainGrid            matlab.ui.container.GridLayout
        ControlPanel        matlab.ui.container.Panel
        PlotPanel           matlab.ui.container.Panel
        
        % Step-Locked Ergonomic Controls
        LblSectionTitle     matlab.ui.control.Label
        CheckboxVerify      matlab.ui.control.CheckBox
        BtnBack             matlab.ui.control.Button
        BtnConfirmNext      matlab.ui.control.Button
        TxtLog              matlab.ui.control.TextArea
        
        % 3x2 Contralateral Column Matrix Layout Canvas
        TileGrid            matlab.graphics.layout.TiledChartLayout
        AxLFPLeft           matlab.graphics.axis.Axes
        AxLFPRight          matlab.graphics.axis.Axes
        AxIHandURight       matlab.graphics.axis.Axes
        AxIHandULeft        matlab.graphics.axis.Axes
        AxFingerRight       matlab.graphics.axis.Axes
        AxFingerLeft        matlab.graphics.axis.Axes
    end
    
    properties (Access = private)
        CurrentStepIdx      double = 1   
        
        % Coordinate registries
        ValidRunLabels      string       
        
        % Data validation ticks for downstream analysis
        SectionVerifiedArray logical
    end
    
    methods
        function obj = DBSgram_DataQualityPart2UI(parentHandle)
            obj.ParentApp = parentHandle;
            
            % Dynamic inheritance out of memory structures parsed in Part 1
            obj.ValidRunLabels  = obj.ParentApp.WorkspaceData.audited_run_labels;
            obj.SectionVerifiedArray = false(size(obj.ValidRunLabels));
            
            buildInterface(obj);
            executeTimelineAuditingPass(obj);
        end
    end
    
    methods (Access = private)
        function buildInterface(obj)
            screensize = get(groot, 'ScreenSize');
            w = screensize(3) * 0.9; h = screensize(4) * 0.85; 
            x = (screensize(3) - w) / 2; y = (screensize(4) - h) / 2;
            
            obj.UIFigure = uifigure('Name', 'Multi-Modal Data Quality & Cross-Alignment Monitor (Part 2)', ...
                                   'Position', [x, y, w, h]);
            obj.MainGrid = uigridlayout(obj.UIFigure, [1, 2]);
            obj.MainGrid.ColumnWidth = {360, '1x'};
            
            % --- CONTROL INTERACTION PANEL ---
            obj.ControlPanel = uipanel(obj.MainGrid, 'Title', 'Alignment Verification Desk');
            ctrlLayout = uigridlayout(obj.ControlPanel, [4, 1]);
            
            ctrlLayout.RowHeight = {40, 30, 35, '1x'};
            ctrlLayout.Padding = [10 10 10 10];
            ctrlLayout.RowSpacing = 10;
            
            obj.LblSectionTitle = uilabel(ctrlLayout, 'Text', 'Protocol Step: INITIALIZING', ...
                'FontSize', 15, 'FontWeight', 'bold', 'FontColor', [0 0.45 0.74]);
            
            obj.CheckboxVerify = uicheckbox(ctrlLayout, 'Text', 'Verify: Cross-alignment checks passed', ...
                'FontWeight', 'bold', 'ValueChangedFcn', @(src, event) obj.cbCheckboxToggled(src, event));
            
            navGrid = uigridlayout(ctrlLayout, [1, 2]);
            navGrid.Padding = [0 0 0 0]; navGrid.ColumnSpacing = 10;
            obj.BtnBack = uibutton(navGrid, 'Text', '◀ Back', 'ButtonPushedFcn', @(src, event) obj.cbNavigateStep(src, event, -1));
            obj.BtnConfirmNext = uibutton(navGrid, 'Text', 'Verify Alignment', ...
                'BackgroundColor', [0.85 0.95 0.85], 'FontWeight', 'bold', ...
                'ButtonPushedFcn', @(src, event) obj.cbNavigateStep(src, event, 1));
            
            obj.TxtLog = uitextarea(ctrlLayout, 'Editable', 'off', 'FontAngle', 'normal', 'FontSize', 11);
            
            % --- 3X2 MULTI-MODAL DISPLAY CONTRALATERAL TILES ---
            obj.PlotPanel = uipanel(obj.MainGrid, 'Title', 'Synchronized Absolute Datetime Timelines Workspace');
            obj.TileGrid = tiledlayout(obj.PlotPanel, 3, 2, 'Padding', 'compact', 'TileSpacing', 'compact');
            
            obj.AxLFPLeft     = nexttile(obj.TileGrid); hold(obj.AxLFPLeft, 'on');
            obj.AxLFPRight    = nexttile(obj.TileGrid); hold(obj.AxLFPRight, 'on');
            obj.AxIHandURight = nexttile(obj.TileGrid); hold(obj.AxIHandURight, 'on'); grid(obj.AxIHandURight, 'on');
            obj.AxIHandULeft  = nexttile(obj.TileGrid); hold(obj.AxIHandULeft, 'on'); grid(obj.AxIHandULeft, 'on');
            obj.AxFingerRight = nexttile(obj.TileGrid); hold(obj.AxFingerRight, 'on'); grid(obj.AxFingerRight, 'on');
            obj.AxFingerLeft  = nexttile(obj.TileGrid); hold(obj.AxFingerLeft, 'on'); grid(obj.AxFingerLeft, 'on');
            
            linkaxes([obj.AxLFPLeft, obj.AxLFPRight, obj.AxIHandURight, obj.AxIHandULeft, obj.AxFingerRight, obj.AxFingerLeft], 'x');
        end
        
        function logStatusLine(obj, textString)
            timestamp = datestr(now, 'HH:MM:SS');
            obj.TxtLog.Value = [sprintf('[%s] %s', timestamp, textString); obj.TxtLog.Value];
        end
        
        function executeTimelineAuditingPass(obj)
            current_label = obj.ValidRunLabels(obj.CurrentStepIdx);
            
            obj.LblSectionTitle.Text = sprintf('Protocol Section: %s (Block %d/%d)', ...
                current_label, obj.CurrentStepIdx, numel(obj.ValidRunLabels));
            
            obj.BtnBack.Enable = (obj.CurrentStepIdx > 1);
            obj.CheckboxVerify.Value = obj.SectionVerifiedArray(obj.CurrentStepIdx);
            
            a_block = obj.ParentApp.WorkspaceData.AlignedData(obj.CurrentStepIdx);
            
            left_included  = obj.ParentApp.WorkspaceData.verified_left_mask(obj.CurrentStepIdx);
            right_included = obj.ParentApp.WorkspaceData.verified_right_mask(obj.CurrentStepIdx);
            
            logStatusLine(obj, sprintf('====== Integrity Audit: Section %s ======', current_label));
            
            % --- CONTEXT-AWARE KINEMATIC INTEGRITY AUDIT ---
            check_left = false;
            check_right = false;
            
            if endsWith(current_label, "L", 'IgnoreCase', true)
                % Left STN Titration -> Audit Contralateral Right Body Wearables
                check_right = true;
            elseif endsWith(current_label, "R", 'IgnoreCase', true)
                % Right STN Titration -> Audit Contralateral Left Body Wearables
                check_left = true;
            else
                % Non-titration section (0, 1, 5) -> Check both sides based on Part 1 verification
                check_left  = left_included;
                check_right = right_included;
            end
            
            % Audit Left Body Wearables (HandSensorL & FingerSensorL)
            if check_left
                missing_sensors = string.empty;
                if isempty(a_block.HandSensorL), missing_sensors(end+1) = "HandSensorL"; end
                if isempty(a_block.FingerSensorL), missing_sensors(end+1) = "FingerSensorL"; end
                
                if ~isempty(missing_sensors)
                    logStatusLine(obj, sprintf('⚠️ WARNING: Missing Left body kinematic data (%s) for Section %s!', ...
                        strjoin(missing_sensors, ", "), current_label));
                else
                    logStatusLine(obj, sprintf('✔ Section %s: Left body kinematic presence confirmed (Hand & Finger).', current_label));
                end
            end
            
            % Audit Right Body Wearables (HandSensorR & FingerSensorR)
            if check_right
                missing_sensors = string.empty;
                if isempty(a_block.HandSensorR), missing_sensors(end+1) = "HandSensorR"; end
                if isempty(a_block.FingerSensorR), missing_sensors(end+1) = "FingerSensorR"; end
                
                if ~isempty(missing_sensors)
                    logStatusLine(obj, sprintf('⚠️ WARNING: Missing Right body kinematic data (%s) for Section %s!', ...
                        strjoin(missing_sensors, ", "), current_label));
                else
                    logStatusLine(obj, sprintf('✔ Section %s: Right body kinematic presence confirmed (Hand & Finger).', current_label));
                end
            end
            
            refreshNavigationGateButtonState(obj);
            renderCrossAlignedPlots(obj, a_block);
        end
        
        function renderCrossAlignedPlots(obj, a_block)
            
            yyaxis(obj.AxLFPLeft, 'left'); cla(obj.AxLFPLeft); obj.AxLFPLeft.YAxis(1).Color = [0 0.45 0.74];
            yyaxis(obj.AxLFPLeft, 'right'); cla(obj.AxLFPLeft); obj.AxLFPLeft.YAxis(2).Color = [0.85 0.33 0.1];
            
            yyaxis(obj.AxLFPRight, 'left'); cla(obj.AxLFPRight); obj.AxLFPRight.YAxis(1).Color = [0 0.55 0.3];
            yyaxis(obj.AxLFPRight, 'right'); cla(obj.AxLFPRight); obj.AxLFPRight.YAxis(2).Color = [0.85 0.33 0.1];
            
            cla(obj.AxIHandURight); cla(obj.AxIHandULeft);
            cla(obj.AxFingerRight); cla(obj.AxFingerLeft);
            
            master_time = a_block.CommonTime;
            
            % --- ROW 1: DUAL-Y SIGNAL VIEWERS ---
            yyaxis(obj.AxLFPLeft, 'left'); 
            plot(obj.AxLFPLeft, master_time, a_block.LFP.data(:,1), 'Color', [0 0.45 0.74]); 
            ylabel(obj.AxLFPLeft, 'LFP (\muV)');
            
            yyaxis(obj.AxLFPLeft, 'right'); 
            plot(obj.AxLFPLeft, master_time, a_block.Stim.data(:,1), 'Color', [0.85 0.33 0.1], 'LineWidth', 1.5); 
            ylabel(obj.AxLFPLeft, 'Stim (mA)');
            title(obj.AxLFPLeft, 'LEFT Hemisphere LFP & Stimulation Tracing'); 
            
            max_stim1 = max(a_block.Stim.data(:,1)); if isempty(max_stim1) || isnan(max_stim1), max_stim1 = 0; end
            ylim(obj.AxLFPLeft, [0, max(1.0, max_stim1 * 1.15)]);
            
            % --- DYNAMIC RIGHT HEMISPHERE CHECK ---
            if size(a_block.LFP.data, 2) >= 2
                yyaxis(obj.AxLFPRight, 'left'); 
                plot(obj.AxLFPRight, master_time, a_block.LFP.data(:,2), 'Color', [0 0.55 0.3]); 
                ylabel(obj.AxLFPRight, 'LFP (\muV)');
            end
            
            if size(a_block.Stim.data, 2) >= 2
                yyaxis(obj.AxLFPRight, 'right'); 
                plot(obj.AxLFPRight, master_time, a_block.Stim.data(:,2), 'Color', [0.85 0.33 0.1], 'LineWidth', 1.5); 
                ylabel(obj.AxLFPRight, 'Stim (mA)');
            end
            
            title(obj.AxLFPRight, 'RIGHT Hemisphere LFP & Stimulation Tracing'); 
            if size(a_block.Stim.data, 2) >= 2
                max_stim2 = max(a_block.Stim.data(:,2)); if isempty(max_stim2) || isnan(max_stim2), max_stim2 = 0; end
                ylim(obj.AxLFPRight, [0, max(1.0, max_stim2 * 1.15)]);
            end
            
            % --- ROW 2 & 3: CONTRALATERAL WEARABLE PLOTS ---
            obj.plotKinTrack(obj.AxIHandURight, a_block.HandSensorR, 'HandSensor Kinematics (Right Body)', master_time);
            obj.plotKinTrack(obj.AxFingerRight, a_block.FingerSensorR, 'FingerSensor Kinematics (Right Body)', master_time);
            
            obj.plotKinTrack(obj.AxIHandULeft,  a_block.HandSensorL, 'HandSensor Kinematics (Left Body)', master_time);
            obj.plotKinTrack(obj.AxFingerLeft,  a_block.FingerSensorL, 'FingerSensor Kinematics (Left Body)', master_time);
            
            % --- RE-ENFORCE TIME AXIS LINKAGE AFTER PLOTTING ---
            linkaxes([obj.AxLFPLeft, obj.AxLFPRight, obj.AxIHandURight, obj.AxIHandULeft, obj.AxFingerRight, obj.AxFingerLeft], 'x');
            
            if ~isempty(master_time)
                xlim(obj.AxLFPLeft, [master_time(1), master_time(end)]);
            end
            
            % --- DYNAMIC PAIRWISE CONTRALATERAL Y-LIMIT CALCULATION ---
            
            % 1. HandSensors (Right Body vs Left Body)
            yLim_HandR = ylim(obj.AxIHandURight);
            yLim_HandL = ylim(obj.AxIHandULeft);
            
            jointMin_Hand = min(yLim_HandR(1), yLim_HandL(1));
            jointMax_Hand = max([3, yLim_HandR(2), yLim_HandL(2)]);
            
            ylim(obj.AxIHandURight, [jointMin_Hand, jointMax_Hand]);
            ylim(obj.AxIHandULeft,  [jointMin_Hand, jointMax_Hand]);
            linkaxes([obj.AxIHandURight, obj.AxIHandULeft], 'y');
            
            % 2. FingerSensors (Right Body vs Left Body)
            yLim_FingerR = ylim(obj.AxFingerRight);
            yLim_FingerL = ylim(obj.AxFingerLeft);
            
            jointMin_Finger = min(yLim_FingerR(1), yLim_FingerL(1));
            jointMax_Finger = max([3, yLim_FingerR(2), yLim_FingerL(2)]);
            
            ylim(obj.AxFingerRight, [jointMin_Finger, jointMax_Finger]);
            ylim(obj.AxFingerLeft,  [jointMin_Finger, jointMax_Finger]);
            linkaxes([obj.AxFingerRight, obj.AxFingerLeft], 'y');
        end
        
        function plotKinTrack(~, targetAxis, kinTable, titleStr, masterTimeVector)
            if ~isempty(kinTable)
                total_acc = sqrt(kinTable.ax.^2 + kinTable.ay.^2 + kinTable.az.^2);
                plot(targetAxis, masterTimeVector, total_acc, 'Color', [0.2 0.2 0.2], 'LineWidth', 1.0);
                ylim(targetAxis, 'auto'); % Allow MATLAB to calculate true natural limits
            else
                dummy_t = [masterTimeVector(1), masterTimeVector(end)];
                plot(targetAxis, dummy_t, [0, 0], 'Color', 'none');
                text(targetAxis, dummy_t(1) + (dummy_t(2)-dummy_t(1))/2, 0.5, 'Tracking Sensor Offline', ...
                    'HorizontalAlignment', 'center', 'Color', [0.6 0.6 0.6], 'FontWeight', 'bold');
                ylim(targetAxis, [0, 3]); % Standard fallback frame for offline sensors
            end
            ylabel(targetAxis, 'Total Accel (g)'); title(targetAxis, titleStr);
        end
        
        function refreshNavigationGateButtonState(obj)
            if obj.CurrentStepIdx == numel(obj.ValidRunLabels)
                obj.BtnConfirmNext.Text = '🔒 Finalize Audit Part 2';
                obj.BtnConfirmNext.BackgroundColor = [0.76 0.89 0.76];
            else
                obj.BtnConfirmNext.Text = 'Confirm & Next Section ▶';
                obj.BtnConfirmNext.BackgroundColor = [0.85 0.95 0.85];
            end
        end
        
        function cbCheckboxToggled(obj, ~, ~)
            % Silently store state changes without status log output
            obj.SectionVerifiedArray(obj.CurrentStepIdx) = obj.CheckboxVerify.Value;
        end
        
        function cbNavigateStep(obj, ~, ~, stepDirection)
            current_label = obj.ValidRunLabels(obj.CurrentStepIdx);
            
            % 1. Log verification status only when advancing forward
            if stepDirection > 0
                if obj.SectionVerifiedArray(obj.CurrentStepIdx)
                    logStatusLine(obj, sprintf('✔ Approved baseline tracking block profiles for Section %s.', current_label));
                else
                    logStatusLine(obj, sprintf('Section %s tracking block profiles UNVERIFIED / EXCLUDED.', current_label));
                end
            end
            
            next_step = obj.CurrentStepIdx + stepDirection;
            
            if next_step >= 1 && next_step <= numel(obj.ValidRunLabels)
                obj.CurrentStepIdx = next_step;
                executeTimelineAuditingPass(obj);
            elseif next_step > numel(obj.ValidRunLabels)
                obj.ParentApp.WorkspaceData.is_timeline_aligned   = true;
                obj.ParentApp.WorkspaceData.final_verified_blocks = obj.SectionVerifiedArray;
                obj.ParentApp.IsQualityAudited = true; 
                
                obj.ParentApp.updateStatus('✔ Part 2 Complete. Cross-Modality Data Quality verified');
                obj.ParentApp.refreshStateEngine();
                delete(obj.UIFigure);
            end
        end
    end
end