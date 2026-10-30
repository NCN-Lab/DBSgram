classdef DBSgram_DataQualityUI < handle
    % DBSgram_DataQualityUI - Parallel Dual-Hemisphere Multitaper Quality Auditor
    
    properties
        ParentApp           DBSgram_MainUI
        UIFigure            matlab.ui.Figure
        MainGrid            matlab.ui.container.GridLayout
        ControlPanel        matlab.ui.container.Panel
        PlotPanel           matlab.ui.container.Panel
        
        % Sequential Ergonomic Workflow Controls
        LblSectionTitle     matlab.ui.control.Label
        CheckboxVerifyLeft  matlab.ui.control.CheckBox
        CheckboxVerifyRight matlab.ui.control.CheckBox
        BtnBack             matlab.ui.control.Button
        BtnConfirmNext      matlab.ui.control.Button
        TxtLog              matlab.ui.control.TextArea
        
        % 2x2 Parallel Dual-Hemisphere Canvas Grid
        TileGrid            matlab.graphics.layout.TiledChartLayout
        AxLeftSignal        matlab.graphics.axis.Axes
        AxRightSignal       matlab.graphics.axis.Axes
        AxLeftSpec          matlab.graphics.axis.Axes
        AxRightSpec         matlab.graphics.axis.Axes
    end
    
    properties (Access = private)
        Fs                  double = 250 
        CurrentStepIdx      double = 1   
        
        % De-coupled session coordinate lookup registries
        ValidRunLabels      string       
        
        % Parallel Analysis Inclusion Masks
        VerifiedLeftArray   logical      
        VerifiedRightArray  logical      
    end
    
    methods
        function obj = DBSgram_DataQualityUI(parentHandle)
            obj.ParentApp = parentHandle;
            
            % % Dynamically fetch Fs if available, default to 250
            % if isfield(obj.ParentApp.WorkspaceData.StreamingObj.streaming_parameters.time_domain, 'fs')
            %     obj.Fs = double(obj.ParentApp.WorkspaceData.StreamingObj.streaming_parameters.time_domain.fs);
            % else
            %     obj.Fs = double(obj.ParentApp.WorkspaceData.StreamingObj.streaming_parameters.time_domain.sample_rate);
            % end
            
            if ~isfield(obj.ParentApp.WorkspaceData, 'AlignedData') || isempty(obj.ParentApp.WorkspaceData.AlignedData)
                uialert(obj.ParentApp.UIFigure, 'AlignedData struct not found. Please complete the Alignment UI first.', 'Data Error');
                return;
            end
            
            mapCachesToProtocols(obj);
            
            obj.VerifiedLeftArray  = false(size(obj.ValidRunLabels));
            obj.VerifiedRightArray = false(size(obj.ValidRunLabels));
            
            buildInterface(obj);
            obj.TxtLog.Value = sprintf('[%s] --- Dual-Hemisphere Multitaper Auditor Initiated ---', datestr(now, 'HH:MM:SS'));
            
            % Initial status log for first block computation
            first_label = obj.ValidRunLabels(obj.CurrentStepIdx);
            logStatusMessage(obj, sprintf('⌛ Calculating the multitaper spectrogram for section %s...', first_label));
            drawnow;
            
            executeAuditingStationPass(obj);
        end
    end
    
    methods (Access = private)
        function mapCachesToProtocols(obj)
            % Pull deterministic labels directly from the AlignedData structure
            a_data = obj.ParentApp.WorkspaceData.AlignedData;
            obj.ValidRunLabels = string({a_data.task_id});
        end
        
        function buildInterface(obj)
            screensize = get(groot, 'ScreenSize');
            w = screensize(3) * 0.9; h = screensize(4) * 0.85; 
            x = (screensize(3) - w) / 2; y = (screensize(4) - h) / 2;
            obj.UIFigure = uifigure('Name', 'Clinical Parallel Multi-Modal Quality Audit Workspace (Part 1)', ...
                                   'Position', [x, y, w, h]);
            obj.MainGrid = uigridlayout(obj.UIFigure, [1, 2]);
            obj.MainGrid.ColumnWidth = {365, '1x'};
            
            % --- ERGONOMIC CONTROL PANEL ---
            obj.ControlPanel = uipanel(obj.MainGrid, 'Title', 'Clinical Audit Center');
            ctrlLayout = uigridlayout(obj.ControlPanel, [5, 1]);
            
            ctrlLayout.RowHeight = {40, 30, 30, 35, '1x'};
            ctrlLayout.Padding = [10 10 10 10];
            ctrlLayout.RowSpacing = 10;
            
            obj.LblSectionTitle = uilabel(ctrlLayout, 'Text', 'Protocol Step: INITIALIZING', ...
                'FontSize', 15, 'FontWeight', 'bold', 'FontColor', [0 0.45 0.74]);
            
            obj.CheckboxVerifyLeft = uicheckbox(ctrlLayout, 'Text', 'Include LEFT Hemisphere for Downstream Analytics', ...
                'FontWeight', 'bold', 'ValueChangedFcn', @(src, event) obj.cbLeftCheckboxToggled(src, event));
            
            obj.CheckboxVerifyRight = uicheckbox(ctrlLayout, 'Text', 'Include RIGHT Hemisphere for Downstream Analytics', ...
                'FontWeight', 'bold', 'ValueChangedFcn', @(src, event) obj.cbRightCheckboxToggled(src, event));
            
            navGrid = uigridlayout(ctrlLayout, [1, 2]);
            navGrid.Padding = [0 0 0 0]; navGrid.ColumnSpacing = 10;
            obj.BtnBack = uibutton(navGrid, 'Text', '◀ Back', ...
                'ButtonPushedFcn', @(src, event) obj.cbNavigateStep(src, event, -1));
            obj.BtnConfirmNext = uibutton(navGrid, 'Text', 'Confirm Section Data', ...
                'BackgroundColor', [0.85 0.95 0.85], 'FontWeight', 'bold', ...
                'ButtonPushedFcn', @(src, event) obj.cbNavigateStep(src, event, 1));
            
            obj.TxtLog = uitextarea(ctrlLayout, 'Editable', 'off', 'FontAngle', 'normal', 'FontSize', 11);
            
            % --- PARALLEL 2x2 STACKED GRID DIAGNOSTICS TIMELINE CANVAS ---
            obj.PlotPanel = uipanel(obj.MainGrid, 'Title', 'Bilateral Spectral Displacements Profile Workspace');
            obj.TileGrid = tiledlayout(obj.PlotPanel, 2, 2, 'Padding', 'compact', 'TileSpacing', 'compact');
            
            obj.AxLeftSignal  = nexttile(obj.TileGrid, 1); hold(obj.AxLeftSignal, 'on');
            obj.AxRightSignal = nexttile(obj.TileGrid, 2); hold(obj.AxRightSignal, 'on');
            obj.AxLeftSpec    = nexttile(obj.TileGrid, 3); hold(obj.AxLeftSpec, 'on');
            obj.AxRightSpec   = nexttile(obj.TileGrid, 4); hold(obj.AxRightSpec, 'on');
            
            linkaxes([obj.AxLeftSignal, obj.AxRightSignal, obj.AxLeftSpec, obj.AxRightSpec], 'x');
        end
        
        function logStatusMessage(obj, messageText)
            timestamp = datestr(now, 'HH:MM:SS');
            formattedLine = sprintf('[%s] %s', timestamp, messageText);
            obj.TxtLog.Value = [string(formattedLine); obj.TxtLog.Value];
        end
        
        function executeAuditingStationPass(obj)
            current_label = obj.ValidRunLabels(obj.CurrentStepIdx);
            a_block       = obj.ParentApp.WorkspaceData.AlignedData(obj.CurrentStepIdx);
            
            obj.LblSectionTitle.Text = sprintf('Protocol Section: %s (Block %d/%d)', ...
                current_label, obj.CurrentStepIdx, numel(obj.ValidRunLabels));
            
            obj.BtnBack.Enable = (obj.CurrentStepIdx > 1);
            
            % Read from AlignedData exactly
            stim_left = a_block.Stim.data(:, 1); 
            stim_right = a_block.Stim.data(:, 2);
            num_steps_left  = numel(unique(stim_left));
            num_steps_right = numel(unique(stim_right));
            
            is_any_stim_active = (max(stim_left) > 0) || (max(stim_right) > 0);
            
            error_msg = "";
            enable_left = true;
            enable_right = true;
            
            % Contextual Titration Validation Engine
            if ismember(current_label, ["0", "1"])
                if is_any_stim_active
                    error_msg = "Baseline Sections 0 and 1 must remain completely at 0mA.";
                end
            elseif current_label == "5"
                if max(stim_left) == 0 && max(stim_right) == 0
                    error_msg = "Section 5 requires active maintenance clinical stimulation.";
                end
            else 
                % Target Titration Safety Checks
                if endsWith(current_label, "L", 'IgnoreCase', true)
                    enable_right = false; % Exclude opposite hemisphere from audit
                    if num_steps_left < 4
                        error_msg = sprintf('Section %s expects active titration on Left hemisphere.', current_label);
                    end
                    if max(stim_right) > 0
                        error_msg = sprintf('CRITICAL: Section %s is a Left Titration, but Right Hemisphere Stim is NOT 0mA!', current_label);
                    end
                elseif endsWith(current_label, "R", 'IgnoreCase', true)
                    enable_left = false; % Exclude opposite hemisphere from audit
                    if num_steps_right < 4
                        error_msg = sprintf('Section %s expects active titration on Right hemisphere.', current_label);
                    end
                    if max(stim_left) > 0
                        error_msg = sprintf('CRITICAL: Section %s is a Right Titration, but Left Hemisphere Stim is NOT 0mA!', current_label);
                    end
                end
            end
            
            if error_msg == ""
                obj.CheckboxVerifyLeft.Enable  = matlab.lang.OnOffSwitchState(enable_left);
                obj.CheckboxVerifyRight.Enable = matlab.lang.OnOffSwitchState(enable_right);
                
                % Ensure disabled checkboxes are cleared
                if ~enable_left
                    obj.CheckboxVerifyLeft.Value = false;
                    obj.VerifiedLeftArray(obj.CurrentStepIdx) = false;
                else
                    obj.CheckboxVerifyLeft.Value = obj.VerifiedLeftArray(obj.CurrentStepIdx);
                end
                
                if ~enable_right
                    obj.CheckboxVerifyRight.Value = false;
                    obj.VerifiedRightArray(obj.CurrentStepIdx) = false;
                else
                    obj.CheckboxVerifyRight.Value = obj.VerifiedRightArray(obj.CurrentStepIdx);
                end
                
                logStatusMessage(obj, sprintf('Sec %s: Telemetry signals online. Review tracking plots.', current_label));
            else
                logStatusMessage(obj, sprintf('Compliance Fault -> %s', error_msg));
                obj.CheckboxVerifyLeft.Enable   = 'off';
                obj.CheckboxVerifyRight.Enable  = 'off';
                obj.CheckboxVerifyLeft.Value    = false;
                obj.CheckboxVerifyRight.Value   = false;
                obj.VerifiedLeftArray(obj.CurrentStepIdx)  = false;
                obj.VerifiedRightArray(obj.CurrentStepIdx) = false;
            end
            
            refreshNavigationGateButtonState(obj);
            renderDiagnosticPlots(obj);
        end
        
        function renderDiagnosticPlots(obj)
            % Clean Canvas
            yyaxis(obj.AxLeftSignal, 'left'); cla(obj.AxLeftSignal); yyaxis(obj.AxLeftSignal, 'right'); cla(obj.AxLeftSignal);
            yyaxis(obj.AxRightSignal, 'left'); cla(obj.AxRightSignal); yyaxis(obj.AxRightSignal, 'right'); cla(obj.AxRightSignal);
            cla(obj.AxLeftSpec); cla(obj.AxRightSpec);
            
            a_block = obj.ParentApp.WorkspaceData.AlignedData(obj.CurrentStepIdx);
            
            % Convert CommonTime to a relative seconds vector
            tms = seconds(a_block.CommonTime - a_block.CommonTime(1));
            
            % --- THE FIX: Create a uniform time grid that preserves exact gap durations ---
            idx_uniform = round(tms * obj.Fs) + 1;
            total_samples = idx_uniform(end);
            tms_uniform = (0:(total_samples-1))' / obj.Fs;
            
            % ----------------- LEFT HEMISPHERE PLOTS -----------------
            if obj.CheckboxVerifyLeft.Enable == 'on'
                L_LFP = double(a_block.LFP.data(:, 1));
                stim_vector_L = a_block.Stim.data(:, 1);
                
                % Map to uniform grid, leaving true missing data gaps as NaNs
                L_LFP_uniform = NaN(total_samples, 1);
                L_LFP_uniform(idx_uniform) = L_LFP;
                
                yyaxis(obj.AxLeftSignal, 'left'); 
                % Plot with uniform NaN padding so the line visually breaks when data drops
                plot(obj.AxLeftSignal, tms_uniform, L_LFP_uniform, 'Color', [0 0.45 0.74]); 
                ylabel(obj.AxLeftSignal, 'Neural LFP (\muV)'); obj.AxLeftSignal.YAxis(1).Color = [0 0.45 0.74];
                
                yyaxis(obj.AxLeftSignal, 'right'); 
                % Plot stim on original tms (draws straight line across connection drops)
                plot(obj.AxLeftSignal, tms, stim_vector_L, 'Color', [0.85 0.33 0.1], 'LineWidth', 1.6); 
                ylabel(obj.AxLeftSignal, 'Stim (mA)'); obj.AxLeftSignal.YAxis(2).Color = [0.85 0.33 0.1];
                ylim(obj.AxLeftSignal, [0, max(1.0, max(stim_vector_L) * 1.15)]);
                title(obj.AxLeftSignal, 'LEFT Hemisphere Signal & Intensity Track');
                
                % Pass the correctly padded grid to the spectrogram
                obj.computeAndPlotMultitaper(obj.AxLeftSpec, L_LFP_uniform, tms_uniform);
                title(obj.AxLeftSpec, 'LEFT Multitaper Spectrogram (dB)');
            else
                title(obj.AxLeftSignal, 'LEFT Hemisphere - Not Audited for this Task');
                title(obj.AxLeftSpec, 'LEFT Spectrogram - N/A');
                yyaxis(obj.AxLeftSignal, 'left'); obj.AxLeftSignal.YAxis(1).Color = [0 0 0];
                yyaxis(obj.AxLeftSignal, 'right'); obj.AxLeftSignal.YAxis(2).Color = [0 0 0];
            end
            
            % ----------------- RIGHT HEMISPHERE PLOTS -----------------
            if obj.CheckboxVerifyRight.Enable == 'on'
                R_LFP = double(a_block.LFP.data(:, 2));
                stim_vector_R = a_block.Stim.data(:, 2);
                
                % Map to uniform grid, leaving true missing data gaps as NaNs
                R_LFP_uniform = NaN(total_samples, 1);
                R_LFP_uniform(idx_uniform) = R_LFP;
                
                yyaxis(obj.AxRightSignal, 'left'); 
                % Plot with uniform NaN padding so the line visually breaks when data drops
                plot(obj.AxRightSignal, tms_uniform, R_LFP_uniform, 'Color', [0 0.55 0.3]); 
                ylabel(obj.AxRightSignal, 'Neural LFP (\muV)'); obj.AxRightSignal.YAxis(1).Color = [0 0.55 0.3];
                
                yyaxis(obj.AxRightSignal, 'right'); 
                plot(obj.AxRightSignal, tms, stim_vector_R, 'Color', [0.85 0.33 0.1], 'LineWidth', 1.6); 
                ylabel(obj.AxRightSignal, 'Stim (mA)'); obj.AxRightSignal.YAxis(2).Color = [0.85 0.33 0.1];
                ylim(obj.AxRightSignal, [0, max(1.0, max(stim_vector_R) * 1.15)]);
                title(obj.AxRightSignal, 'RIGHT Hemisphere Signal & Intensity Track');
                
                % Pass the correctly padded grid to the spectrogram
                obj.computeAndPlotMultitaper(obj.AxRightSpec, R_LFP_uniform, tms_uniform);
                title(obj.AxRightSpec, 'RIGHT Multitaper Spectrogram (dB)');
            else
                title(obj.AxRightSignal, 'RIGHT Hemisphere - Not Audited for this Task');
                title(obj.AxRightSpec, 'RIGHT Spectrogram - N/A');
                yyaxis(obj.AxRightSignal, 'left'); obj.AxRightSignal.YAxis(1).Color = [0 0 0];
                yyaxis(obj.AxRightSignal, 'right'); obj.AxRightSignal.YAxis(2).Color = [0 0 0];
            end
            
            xlim(obj.AxLeftSignal, [tms(1), tms(end)]);
        end

        function computeAndPlotMultitaper(obj, targetAx, signalVector, timeVector)
            win_size = 1.0; 
            N_win = round(win_size * obj.Fs); 
            NW = 3; 
            step_size = 0.1; 
            hop = round(step_size * obj.Fs);
            nfft = 512;
            
            % Detrend ONLY valid data to prevent mean() shifting from NaN gaps
            signal_detrend = signalVector;
            valid_mask = ~isnan(signalVector);
            if any(valid_mask)
                signal_detrend(valid_mask) = signalVector(valid_mask) - mean(signalVector(valid_mask));
            end
            
            starts = 1:hop:(length(signal_detrend) - N_win);
            
            if isempty(starts)
                text(targetAx, 0.5, 0.5, 'Data Segment Too Short for MT analysis', 'HorizontalAlignment', 'center');
                return;
            end
            
            % Pre-allocate the MT array using a dummy call to establish the frequency vector size
            [~, f_mt] = pmtm(randn(N_win,1), NW, nfft, obj.Fs);
            Spec_MT = NaN(length(f_mt), length(starts));
            
            for k = 1:length(starts)
                window_data = signal_detrend(starts(k) : starts(k) + N_win - 1);
                
                % If the window touches a disconnect gap, skip it (leave it as NaN)
                if ~any(isnan(window_data))
                    Spec_MT(:, k) = pmtm(window_data, NW, nfft, obj.Fs);
                end
            end
            
            time_axis_seconds = timeVector(1) + (starts + N_win/2) / obj.Fs;
            
            im = imagesc(targetAx, time_axis_seconds, f_mt, 10*log10(Spec_MT));
            
            % --- THE FIX: Make missing data windows transparent ---
            set(im, 'AlphaData', ~isnan(Spec_MT)); 
            
            colormap(targetAx, 'jet'); ylim(targetAx, [0 125]); 
            ylabel(targetAx, 'Freq (Hz)'); xlabel(targetAx, 'Time (s)');       
            c = colorbar(targetAx); clim(targetAx, [-5 25]);
            c.Label.String = "Power/Frequency";
            
            % Set axes background to a soft grey to make data gaps highly visible
            set(targetAx, 'Color', [0.85 0.85 0.85]); 
        end
        
        function refreshNavigationGateButtonState(obj)
            if obj.CurrentStepIdx == numel(obj.ValidRunLabels)
                obj.BtnConfirmNext.Text = '🔒 Finalize Audit Part 1';
                obj.BtnConfirmNext.BackgroundColor = [0.76 0.89 0.76];
            else
                obj.BtnConfirmNext.Text = 'Confirm & Next Section ▶';
                obj.BtnConfirmNext.BackgroundColor = [0.85 0.95 0.85];
            end
        end
        
        function cbLeftCheckboxToggled(obj, ~, ~)
            % Silently update array state without status log spam
            obj.VerifiedLeftArray(obj.CurrentStepIdx) = obj.CheckboxVerifyLeft.Value;
        end
        
        function cbRightCheckboxToggled(obj, ~, ~)
            % Silently update array state without status log spam
            obj.VerifiedRightArray(obj.CurrentStepIdx) = obj.CheckboxVerifyRight.Value;
        end
        
        function cbNavigateStep(obj, ~, ~, stepDirection)
            current_label = obj.ValidRunLabels(obj.CurrentStepIdx);
            
            % 1. Log refined audit status when moving forward/confirming
            if stepDirection > 0
                left_active  = strcmp(char(obj.CheckboxVerifyLeft.Enable), 'on');
                right_active = strcmp(char(obj.CheckboxVerifyRight.Enable), 'on');
                
                left_inc  = obj.VerifiedLeftArray(obj.CurrentStepIdx);
                right_inc = obj.VerifiedRightArray(obj.CurrentStepIdx);
                
                if left_active && right_active
                    if left_inc && right_inc
                        logStatusMessage(obj, sprintf('Left and Right hemisphere ✔ INCLUDED for section %s', current_label));
                    elseif ~left_inc && ~right_inc
                        logStatusMessage(obj, sprintf('Left and Right hemisphere ❌ EXCLUDED for section %s', current_label));
                    else
                        if left_inc, lStr = "✔ INCLUDED"; else, lStr = "❌ EXCLUDED"; end
                        if right_inc, rStr = "✔ INCLUDED"; else, rStr = "❌ EXCLUDED"; end
                        logStatusMessage(obj, sprintf('Left hemisphere %s, Right hemisphere %s for section %s', lStr, rStr, current_label));
                    end
                elseif left_active
                    if left_inc, lStr = "✔ INCLUDED"; else, lStr = "❌ EXCLUDED"; end
                    logStatusMessage(obj, sprintf('Left hemisphere %s for section %s', lStr, current_label));
                elseif right_active
                    if right_inc, rStr = "✔ INCLUDED"; else, rStr = "❌ EXCLUDED"; end
                    logStatusMessage(obj, sprintf('Right hemisphere %s for section %s', rStr, current_label));
                else
                    logStatusMessage(obj, sprintf('Section %s ❌ EXCLUDED (Compliance Fault)', current_label));
                end
            end
            
            next_step = obj.CurrentStepIdx + stepDirection;
            
            if next_step >= 1 && next_step <= numel(obj.ValidRunLabels)
                obj.CurrentStepIdx = next_step;
                next_label = obj.ValidRunLabels(obj.CurrentStepIdx);
                
                % 2. Log pre-calculation progress message and force immediate GUI update
                logStatusMessage(obj, sprintf('⌛ Calculating the multitaper spectrogram for section %s...', next_label));
                drawnow; % Flushes event queue to display message before heavy computation starts
                
                executeAuditingStationPass(obj);
            elseif next_step > numel(obj.ValidRunLabels)
                % Save results and launch Part 2
                obj.ParentApp.WorkspaceData.verified_left_mask  = obj.VerifiedLeftArray;
                obj.ParentApp.WorkspaceData.verified_right_mask = obj.VerifiedRightArray;
                obj.ParentApp.WorkspaceData.audited_run_labels  = obj.ValidRunLabels;
                
                obj.ParentApp.updateStatus('✔ Part 1 Complete. Advancing to Part 2: Cross-Modality Alignment Verification UI...');
                DBSgram_DataQualityPart2UI(obj.ParentApp);
                delete(obj.UIFigure);
            end
        end
        
        function cbCloseWindow(obj, ~, ~)
            delete(obj.UIFigure);
        end
    end
end