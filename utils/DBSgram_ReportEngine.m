classdef DBSgram_ReportEngine < handle
    % DBSgram_ReportEngine - Generates a 2-Page Vector DBSgram Report Workbook
    
    properties
        ParentApp   DBSgram_MainUI
        CanvasFig   matlab.ui.Figure
    end
    
    properties (Access = private)
        Fs          double = 250
        Radius      double = 10
        Spacing     double = 25
    end
    
    methods
        function obj = DBSgram_ReportEngine(parentHandle)
            obj.ParentApp = parentHandle;
            obj.Fs = 250; % Safe fallback
            
            ws = obj.ParentApp.WorkspaceData;
            
            % Dynamically calculate Fs directly from the absolute Master Clock
            if isfield(ws, 'AlignedData') && ~isempty(ws.AlignedData)
                a_data = ws.AlignedData(1);
                if length(a_data.CommonTime) >= 2
                    dt = seconds(a_data.CommonTime(2) - a_data.CommonTime(1));
                    obj.Fs = round(1 / dt);
                end
            elseif isfield(ws, 'StreamingObj') && isfield(ws.StreamingObj.streaming_parameters.time_domain, 'fs')
                obj.Fs = double(ws.StreamingObj.streaming_parameters.time_domain.fs);
            elseif isfield(ws, 'streaming_obj') && isfield(ws.streaming_obj.streaming_parameters.time_domain, 'fs')
                obj.Fs = double(ws.streaming_obj.streaming_parameters.time_domain.fs);
            end
        end
        
        function generateDBSgramPDF(obj, targetPdfPath)
            % Initialize an absolute A4 portrait standard print-space canvas
            obj.CanvasFig = figure('Visible', 'off', ...
                                   'Units', 'centimeters', ...
                                   'Position', [0, 0, 21.0, 29.7], ...
                                   'Color', 'w');
                               
            set(obj.CanvasFig, 'PaperUnits', 'centimeters');
            set(obj.CanvasFig, 'PaperSize', [21.0, 29.7]);
            set(obj.CanvasFig, 'PaperPositionMode', 'manual');
            set(obj.CanvasFig, 'PaperPosition', [0, 0, 21.0, 29.7]);
            
            if exist(targetPdfPath, 'file'), delete(targetPdfPath); end
            
            % --- EXTRACT HARDWARE CONFIGURATION METADATA ---
            [left_info, right_info] = obj.parseHardwareParams();
            
            % --- SEQUENTIAL 1-HEMISPHERE-PER-PAGE GENERATION PIPELINE ---
            for hemiIdx = 1:2
                clf(obj.CanvasFig);
                
                if hemiIdx == 1
                    hemiLabel   = "Left STN";
                    bodySide    = "Right Body";
                    hemi_info   = left_info;
                else
                    hemiLabel   = "Right STN";
                    bodySide    = "Left Body";
                    hemi_info   = right_info;
                end
                
                % 1. Render Demographics Title Header Block (Y: 0.90 to 0.97)
                obj.drawStylizedDemographicsHeader(hemiLabel);
                
                % 2. Render In-Clinic & Post-Clinic Electrode Maps + Parameters (Y: 0.81 to 0.88)
                obj.drawStimulationBlock(hemi_info);
                
                % 3. Render Calibration & Titration PSD Row (Y: 0.66 to 0.78)
                obj.drawCalibrationAndTitrationRow(0.66, hemiIdx);
                
                % 4. Render 3 Vertical Symptom Columns (Y: 0.02 to 0.62)
                obj.drawSymptomColumn('Tremor',       0.06, hemiIdx, bodySide);
                obj.drawSymptomColumn('Rigidity',     0.37, hemiIdx, bodySide);
                obj.drawSymptomColumn('Bradykinesia', 0.68, hemiIdx, bodySide);
                
                % Append current page canvas out to target file stream
                exportgraphics(obj.CanvasFig, targetPdfPath, 'Units', 'centimeters', ...
                    'ContentType', 'vector', 'Width', 21, 'Height', 29.7, 'Append', true, 'Padding', 0.5);
            end
            
            close(obj.CanvasFig);
        end
    end
    
    methods (Access = private)
        function drawStylizedDemographicsHeader(obj, hemiLabel)
            axLogo = axes(obj.CanvasFig, 'Position', [0.05, 0.90, 0.15, 0.07]);
            text(axLogo, 0.00, 0.70, 'DBS', 'FontSize', 22, 'FontWeight', 'bold', 'FontAngle', 'italic');
            text(axLogo, 0.00, 0.20, 'Gram', 'FontSize', 22, 'FontWeight', 'bold');
            xlim(axLogo, [0 1]); ylim(axLogo, [0 1]); axis(axLogo, 'off');
            
            axText = axes(obj.CanvasFig, 'Position', [0.23, 0.90, 0.63, 0.07]);
            hold(axText, 'on');
            
            ws = obj.ParentApp.WorkspaceData;
            
            % --- DYNAMIC FIELD EXTRACTION ---
            if isfield(ws, 'PatientName') && ~isempty(ws.PatientName)
                pName = string(ws.PatientName);
            else
                pName = "N/A";
            end
            
            if isfield(ws, 'PatientKey') && ~isempty(ws.PatientKey)
                pID = string(ws.PatientKey);
            else
                pID = "N/A";
            end
            
            if isfield(ws, 'PatientSex') && ~isempty(ws.PatientSex)
                pSex = string(ws.PatientSex);
            else
                pSex = "N/A";
            end
            
            if isfield(ws, 'DeviceModel') && ~isempty(ws.DeviceModel)
                dModel = string(ws.DeviceModel);
            else
                dModel = "N/A";
            end
            
            if isfield(ws, 'SessionDate') && ~isempty(ws.SessionDate)
                sDate = string(ws.SessionDate);
            else
                sDate = "N/A";
            end
            
            % --- NEW: AGE EXTRACTION ---
            if isfield(ws, 'PatientAge') && ~isempty(ws.PatientAge)
                pAge = string(ws.PatientAge);
            else
                pAge = "N/A";
            end
            
            % --- TEXT RENDERING (Adjusted X-Coordinates for Wider Column 1) ---
            % Column 1: 0.00 | Column 2: 0.42 | Column 3: 0.73
            
            text(axText, 0.00, 0.80, sprintf('Name: %s', pName), 'FontSize', 8.5, 'Interpreter', 'none');
            text(axText, 0.40, 0.80, sprintf('Device: %s', dModel), 'FontSize', 8.5, 'Interpreter', 'none');
            text(axText, 0.75, 0.80, sprintf('Patient ID: %s', pID), 'FontSize', 8.5, 'Interpreter', 'none');
            
            text(axText, 0.00, 0.45, sprintf('Sex: %s', pSex), 'FontSize', 8.5, 'Interpreter', 'none');
            text(axText, 0.40, 0.45, sprintf('Session Date: %s', sDate), 'FontSize', 8.5, 'Interpreter', 'none');
            text(axText, 0.75, 0.45, 'Clinician: _________________', 'FontSize', 8.5, 'Interpreter', 'none');
            
            text(axText, 0.00, 0.10, sprintf('Age: %s', pAge), 'FontSize', 8.5, 'Interpreter', 'none');
            text(axText, 0.40, 0.10, sprintf('Active Target: %s', hemiLabel), 'FontSize', 8.5, 'FontWeight', 'bold', 'Interpreter', 'none');
            text(axText, 0.75, 0.10, 'Data Analyst: _____________', 'FontSize', 8.5, 'Interpreter', 'none');
          
            xlim(axText, [0 1]); ylim(axText, [0 1]); axis(axText, 'off');
            
            axLine = axes(obj.CanvasFig, 'Position', [0.03, 0.89, 0.90, 0.003]);
            plot(axLine, [0 1], [0.5 0.5], 'k-', 'LineWidth', 1.0);
            xlim(axLine, [0 1]); ylim(axLine, [0 1]); axis(axLine, 'off');
        end

        function drawStimulationBlock(obj, info)
            % In-Clinic Parameters Box
            axTxtIn = axes(obj.CanvasFig, 'Position', [0.03, 0.81, 0.16, 0.07]);
            hold(axTxtIn, 'on');
            text(axTxtIn, 0.00, 0.88, 'In-Clinic Set Stimulation', 'FontSize', 8.0, 'FontWeight', 'bold', 'Interpreter', 'none');
            text(axTxtIn, 0.05, 0.62, sprintf('Rate: %s Hz', info.proto_rate), 'FontSize', 7.0, 'Color', [0.25 0.25 0.25], 'Interpreter', 'none');
            text(axTxtIn, 0.05, 0.38, sprintf('Pulse Width: %s us', info.proto_pw), 'FontSize', 7.0, 'Color', [0.25 0.25 0.25], 'Interpreter', 'none');
            text(axTxtIn, 0.05, 0.14, sprintf('Amplitude: %s mA', info.proto_amp), 'FontSize', 7.0, 'Color', [0.25 0.25 0.25], 'Interpreter', 'none');
            xlim(axTxtIn, [0 1]); ylim(axTxtIn, [0 1]); axis(axTxtIn, 'off');
            
            axProto = axes(obj.CanvasFig, 'Position', [0.21, 0.81, 0.25, 0.07]);
            obj.drawContactRings(axProto, info.proto_rings);
            
            % Vertical Separator Line
            axVert = axes(obj.CanvasFig, 'Position', [0.475, 0.815, 0.01, 0.06]);
            plot(axVert, [0.5 0.5], [0 1], ':', 'Color', [0.75 0.75 0.75], 'LineWidth', 0.8);
            xlim(axVert, [0 1]); ylim(axVert, [0 1]); axis(axVert, 'off');
            
            % Post-Clinic Parameters Box
            axTxtPost = axes(obj.CanvasFig, 'Position', [0.50, 0.81, 0.16, 0.07]);
            hold(axTxtPost, 'on');
            text(axTxtPost, 0.00, 0.88, 'Post-Clinic Set Stimulation', 'FontSize', 8.0, 'FontWeight', 'bold', 'Interpreter', 'none');
            text(axTxtPost, 0.05, 0.62, sprintf('Rate: %s Hz', info.post_rate), 'FontSize', 7.0, 'Color', [0.25 0.25 0.25], 'Interpreter', 'none');
            text(axTxtPost, 0.05, 0.38, sprintf('Pulse Width: %s us', info.post_pw), 'FontSize', 7.0, 'Color', [0.25 0.25 0.25], 'Interpreter', 'none');
            text(axTxtPost, 0.05, 0.14, sprintf('Amplitude: %s mA', info.post_amp), 'FontSize', 7.0, 'Color', [0.25 0.25 0.25], 'Interpreter', 'none');
            xlim(axTxtPost, [0 1]); ylim(axTxtPost, [0 1]); axis(axTxtPost, 'off');
            
            axPost = axes(obj.CanvasFig, 'Position', [0.66, 0.81, 0.25, 0.07]);
            obj.drawContactRings(axPost, info.post_rings);
            
            % Section Divider Dashed Line
            axLine = axes(obj.CanvasFig, 'Position', [0.03, 0.8025, 0.90, 0.003]);
            plot(axLine, [0 1], [0.5 0.5], '--', 'Color', [0.65 0.65 0.65], 'LineWidth', 0.8);
            xlim(axLine, [0 1]); ylim(axLine, [0 1]); axis(axLine, 'off');
        end

       function drawCalibrationAndTitrationRow(obj, yOffset, hemiIdx)
            titleAx = axes(obj.CanvasFig, 'Position', [0.03, yOffset + 0.115, 0.90, 0.018]);
            text(titleAx, 0.01, 0.50, 'Baseline Calibration & Rest Titration Electrophysiology (PSD Profiles)', ...
                'FontSize', 8.0, 'FontWeight', 'bold', 'BackgroundColor', [0.91 0.93 0.95], 'Interpreter', 'none');
            xlim(titleAx, [0 1]); ylim(titleAx, [0 1]); axis(titleAx, 'off');
            
            ws = obj.ParentApp.WorkspaceData;
            a_data = ws.AlignedData;
            
            active_ch_str = "";
            if ~isempty(a_data) && isfield(a_data(1).LFP, 'channel_names')
                c_names = a_data(1).LFP.channel_names;
                if numel(c_names) >= hemiIdx
                    active_ch_str = string(c_names{hemiIdx});
                end
            end
            
            if hemiIdx == 1
                target_hemi    = "LEFT";
                hemi_title_str = "Left";
                steps_field    = "Tremor_Left";
                task_id        = "2L";
            else
                target_hemi    = "RIGHT";
                hemi_title_str = "Right";
                steps_field    = "Tremor_Right";
                task_id        = "2R";
            end
            
            % =========================================================================
            % PLOT 1: CALIBRATION TESTS (SURVEY vs SETUP OFF vs SETUP ON)
            % =========================================================================
            ax1 = axes(obj.CanvasFig, 'Position', [0.08, yOffset, 0.36, 0.10]);
            hold(ax1, 'on'); grid(ax1, 'off');
            set(ax1, 'YScale', 'log');
            
            has_calib_plots = false;
            
            % --- A) STIM OFF (SURVEY OBJ) ---
            if isfield(obj.ParentApp.WorkspaceData, 'SurveyObj')
               survey_obj = obj.ParentApp.WorkspaceData.SurveyObj;
            end
            if exist('survey_obj', 'var') && ~isempty(survey_obj) && (isprop(survey_obj, 'survey_parameters') || isfield(survey_obj, 'survey_parameters'))
                td_surv = survey_obj.survey_parameters.time_domain;
                if isfield(td_surv, 'channel_names') && isfield(td_surv, 'data')
                    [surv_names, surv_data] = obj.unpackHemiChannelData(td_surv.channel_names, td_surv.data, hemiIdx);
                    if ~isempty(surv_names) && ~isempty(surv_data)
                        idx_surv = obj.findChannelIndex(surv_names, active_ch_str, target_hemi);
                        if ~isempty(idx_surv) && size(surv_data, 2) >= idx_surv
                            sig_surv = surv_data(:, idx_surv);
                            fs_surv  = 250;
                            if isfield(td_surv, 'fs'), fs_surv = td_surv.fs; end
                            [f_surv, psd_surv] = obj.calculateSignalFFT(sig_surv, fs_surv);
                            if ~isempty(psd_surv)
                                plot(ax1, f_surv, psd_surv, 'Color', [0.85 0.33 0.10], 'LineWidth', 1.2, 'DisplayName', 'Stim OFF');
                                has_calib_plots = true;
                            end
                        end
                    end
                end
            end
            
            % --- B) STIM 0mA (SETUP OFF OBJ) ---
            if isfield(obj.ParentApp.WorkspaceData, 'SetupObj')
               setup_obj = obj.ParentApp.WorkspaceData.SetupObj;
            end
            if exist('setup_obj', 'var') && ~isempty(setup_obj) && (isprop(setup_obj, 'setup_parameters') || isfield(setup_obj, 'setup_parameters'))
                sp_off = setup_obj.setup_parameters.stim_off;
                if isfield(sp_off, 'channel_names') && isfield(sp_off, 'data')
                    [off_names, off_data] = obj.unpackHemiChannelData(sp_off.channel_names, sp_off.data, hemiIdx);
                    if ~isempty(off_names) && ~isempty(off_data)
                        idx_off = obj.findChannelIndex(off_names, active_ch_str, target_hemi);
                        if ~isempty(idx_off) && size(off_data, 2) >= idx_off
                            sig_off = off_data(:, idx_off);
                            fs_off  = 250;
                            if isfield(sp_off, 'fs'), fs_off = sp_off.fs; end
                            [f_off, psd_off] = obj.calculateSignalFFT(sig_off, fs_off);
                            if ~isempty(psd_off)
                                plot(ax1, f_off, psd_off, 'Color', [0.40 0.40 0.40], 'LineWidth', 1.2, 'DisplayName', 'Stim 0mA');
                                has_calib_plots = true;
                            end
                        end
                    end
                end
            end
            
            % --- C) STIM CLINICAL (SETUP ON OBJ) ---
            if exist('setup_obj', 'var') && ~isempty(setup_obj) && (isprop(setup_obj, 'setup_parameters') || isfield(setup_obj, 'setup_parameters'))
                sp_on = setup_obj.setup_parameters.stim_on;
                if isfield(sp_on, 'channel_names') && isfield(sp_on, 'data')
                    [on_names, on_data] = obj.unpackHemiChannelData(sp_on.channel_names, sp_on.data, hemiIdx);
                    if ~isempty(on_names) && ~isempty(on_data)
                        idx_on = obj.findChannelIndex(on_names, active_ch_str, target_hemi);
                        if ~isempty(idx_on) && size(on_data, 2) >= idx_on
                            sig_on = on_data(:, idx_on);
                            fs_on  = 250;
                            if isfield(sp_on, 'fs'), fs_on = sp_on.fs; end
                            [f_on, psd_on] = obj.calculateSignalFFT(sig_on, fs_on);
                            if ~isempty(psd_on)
                                plot(ax1, f_on, psd_on, 'Color', [0.00 0.45 0.74], 'LineWidth', 1.2, 'DisplayName', 'Stim Clinical');
                                has_calib_plots = true;
                            end
                        end
                    end
                end
            end
            
            % Formatting or Placeholder for Plot 1
            if has_calib_plots
                % Draw Beta Patch in background
                p_patch = patch(ax1, [13 35 35 13], [0.001 0.001 100 100], [0.85 0.85 0.85], ...
                    'EdgeColor', 'none', 'HandleVisibility', 'off', 'PickableParts', 'none');
                uistack(p_patch, 'bottom');
                
                set(ax1, 'YMinorTick', 'off', 'LineWidth', 1.2, 'Box', 'off', 'TickDir', 'out');
                xlim(ax1, [0 60]); ylim(ax1, [0.1 10]);
                set(ax1, 'XTick', [0, 13, 35, 60], 'XTickLabel', {'0', '13', '35', '60'});
                set(ax1, 'YTick', [0.1, 1, 10], 'YTickLabel', {'10^{-1}', '10^{0}', '10^{1}'});
                
                title(ax1, sprintf('%s Hemisphere Calibration', hemi_title_str), 'FontSize', 7.5, 'FontWeight', 'bold', 'Interpreter', 'none');
                xlabel(ax1, 'Frequency (Hz)', 'FontSize', 7.0, 'FontWeight', 'bold', 'Interpreter', 'none');
                ylabel(ax1, 'Amplitude (log(\muVp))', 'FontSize', 7.0, 'FontWeight', 'bold', 'Interpreter', 'tex');
                set(ax1, 'FontSize', 7.0, 'FontWeight', 'bold');
                
                lgd1 = legend(ax1, 'Location', 'northeast', 'FontSize', 6.0, 'Box', 'off');
                lgd1.ItemTokenSize = [12 6];
            else
                cla(ax1);
                set(ax1, 'YScale', 'linear');
                p_patch = patch(ax1, 'XData', [0 1 1 0], 'YData', [0 0 1 1], 'FaceColor', [0.96 0.96 0.96], 'EdgeColor', [0.8 0.8 0.8], 'LineWidth', 1.5, 'LineStyle', '--');
                text(ax1, 0.5, 0.5, sprintf('Calibration data\nnot available.'), 'FontSize', 9, 'FontWeight', 'bold', 'Color', [0.5 0.5 0.5], 'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle');
                uistack(p_patch, 'bottom');
                xlim(ax1, [0 1]); ylim(ax1, [0 1]); axis(ax1, 'off');
                title(ax1, sprintf('%s Hemisphere Calibration', hemi_title_str), 'FontSize', 7.5, 'FontWeight', 'bold', 'Interpreter', 'none', 'Visible', 'on');
            end
            
            % =========================================================================
            % PLOT 2: STIMULATION LEVEL TITRATION AT REST
            % =========================================================================
            ax2 = axes(obj.CanvasFig, 'Position', [0.54, yOffset, 0.36, 0.10]);
            hold(ax2, 'on'); grid(ax2, 'off');
            set(ax2, 'YScale', 'log');
            
            steps = [];
            if isfield(ws, 'clinical_overview_updrs') && isfield(ws.clinical_overview_updrs, 'levels_storage_struct') ...
               && isfield(ws.clinical_overview_updrs.levels_storage_struct, steps_field)
                steps = ws.clinical_overview_updrs.levels_storage_struct.(steps_field)(:)';
            end
            
            block_idx = find(string({a_data.task_id}) == task_id, 1);
            if isempty(steps) && ~isempty(block_idx)
                stim_target = round(a_data(block_idx).Stim.data(:, hemiIdx), 1);
                raw_st = unique(stim_target);
                steps = raw_st(raw_st >= 0)';
            end
            
            has_titr_plots = false;
            
            if ~isempty(block_idx) && ~isempty(steps)
                a_block = a_data(block_idx);
                
                if isfield(a_block.LFP, 'data_clean') && ~isempty(a_block.LFP.data_clean)
                    lfp_target = a_block.LFP.data_clean(:, hemiIdx);
                else
                    lfp_target = a_block.LFP.data(:, hemiIdx);
                end
                
                stim_target = round(a_block.Stim.data(:, hemiIdx), 1);
                color_map = [0.43 0.69 0.84; 0.32 0.58 0.73; 0.22 0.46 0.63; 0.11 0.35 0.53; 0.00 0.22 0.42];
                
                for s = 1:numel(steps)
                    target_val = steps(s);
                    
                    valid_idx = find(stim_target == target_val);
                    if numel(valid_idx) > (obj.Fs * 5) 
                        split_pts = find(diff(valid_idx) > 1);
                        c_starts = [valid_idx(1); valid_idx(split_pts + 1)];
                        c_ends   = [valid_idx(split_pts); valid_idx(end)];
                        [~, best_chunk] = max(c_ends - c_starts);
                        
                        l_seg = lfp_target(c_starts(best_chunk) : c_ends(best_chunk));
                        
                        [f_step, psd_step] = obj.calculateSignalFFT(l_seg, obj.Fs);
                        if ~isempty(psd_step)
                            c_idx = min(s, size(color_map, 1));
                            disp_str = sprintf('%.1fmA', target_val);
                            plot(ax2, f_step, psd_step, 'Color', color_map(c_idx, :), ...
                                'LineWidth', 1.2, 'DisplayName', disp_str);
                            has_titr_plots = true;
                        end
                    end
                end
            end
            
            % Formatting or Placeholder for Plot 2
            if has_titr_plots
                p_patch2 = patch(ax2, [13 35 35 13], [0.001 0.001 100 100], [0.85 0.85 0.85], ...
                    'EdgeColor', 'none', 'HandleVisibility', 'off', 'PickableParts', 'none');
                uistack(p_patch2, 'bottom');
                
                set(ax2, 'YMinorTick', 'off', 'LineWidth', 1.2, 'Box', 'off', 'TickDir', 'out');
                xlim(ax2, [0 60]); ylim(ax2, [0.1 10]);
                set(ax2, 'XTick', [0, 13, 35, 60], 'XTickLabel', {'0', '13', '35', '60'});
                set(ax2, 'YTick', [0.1, 1, 10], 'YTickLabel', {'10^{-1}', '10^{0}', '10^{1}'});
                
                title(ax2, 'Stimulation Titration at Rest', 'FontSize', 7.5, 'FontWeight', 'bold', 'Interpreter', 'none');
                xlabel(ax2, 'Frequency (Hz)', 'FontSize', 7.0, 'FontWeight', 'bold', 'Interpreter', 'none');
                ylabel(ax2, 'Amplitude (log(\muVp))', 'FontSize', 7.0, 'FontWeight', 'bold', 'Interpreter', 'tex');
                set(ax2, 'FontSize', 7.0, 'FontWeight', 'bold');
                
                lgd2 = legend(ax2, 'Location', 'northeast', 'FontSize', 6.0, 'Box', 'off');
                lgd2.ItemTokenSize = [12 6];
            else
                cla(ax2);
                set(ax2, 'YScale', 'linear');
                patch(ax2, 'XData', [0 1 1 0], 'YData', [0 0 1 1], 'FaceColor', [0.96 0.96 0.96], 'EdgeColor', [0.8 0.8 0.8], 'LineWidth', 1.5, 'LineStyle', '--');
                text(ax2, 0.5, 0.5, sprintf('Titration hasn''t passed\ndata quality requirements.'), 'FontSize', 9, 'FontWeight', 'bold', 'Color', [0.5 0.5 0.5], 'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle');
                xlim(ax2, [0 1]); ylim(ax2, [0 1]); axis(ax2, 'off');
                title(ax2, 'Stimulation Titration at Rest', 'FontSize', 7.5, 'FontWeight', 'bold', 'Interpreter', 'none', 'Visible', 'on');
            end
            
            % Section Separator Line
            axLine = axes(obj.CanvasFig, 'Position', [0.03, yOffset - 0.035, 0.90, 0.003]);
            plot(axLine, [0 1], [0.5 0.5], '--', 'Color', [0.65 0.65 0.65], 'LineWidth', 0.8);
            xlim(axLine, [0 1]); ylim(axLine, [0 1]); axis(axLine, 'off');
       end
       
       function idx = findChannelIndex(obj, names_list, active_str, target_hemi)
            idx = [];
            if isempty(names_list), return; end
            
            if iscell(names_list)
                if numel(names_list) > 0 && iscell(names_list{1})
                    names_list = names_list{1};
                end
            elseif isstring(names_list)
                names_list = cellstr(names_list);
            end
            
            num_ch = numel(names_list);
            if num_ch == 0, return; end
            
            active_str  = upper(string(active_str));
            target_hemi = upper(string(target_hemi));
            
            digit_map = containers.Map({'ZERO','0','ONE','1','TWO','2','THREE','3'}, ...
                                      {'0','0','1','1','2','2','3','3'});
            
            req_digits = string.empty;
            words_check = ["ZERO", "0", "ONE", "1", "TWO", "2", "THREE", "3"];
            for w = words_check
                if contains(active_str, w)
                    req_digits(end+1) = string(digit_map(char(w))); %#ok<AGROW>
                end
            end
            req_digits = unique(req_digits);
            
            scores = -ones(1, num_ch);
            for i = 1:num_ch
                c_name = upper(string(names_list{i}));
                
                if contains(c_name, target_hemi) || (~contains(c_name, "RIGHT") && ~contains(c_name, "LEFT"))
                    score = 1;
                    if contains(c_name, target_hemi)
                        score = score + 2;
                    end
                    
                    for d = req_digits
                        if contains(c_name, d) || contains(c_name, obj.digitToWord(d))
                            score = score + 3;
                        end
                    end
                    scores(i) = score;
                end
            end
            
            [max_score, best_i] = max(scores);
            if max_score > 0
                idx = best_i;
            end
        end

        function w = digitToWord(~, d)
            switch string(d)
                case "0", w = "ZERO";
                case "1", w = "ONE";
                case "2", w = "TWO";
                case "3", w = "THREE";
                otherwise, w = "";
            end
        end

        function [hemi_names, hemi_data] = unpackHemiChannelData(~, c_names, c_data, hemiIdx)
            hemi_names = {};
            hemi_data  = [];
            
            if isempty(c_names) || isempty(c_data), return; end
            
            if iscell(c_names)
                if numel(c_names) >= hemiIdx && iscell(c_names{hemiIdx})
                    hemi_names = c_names{hemiIdx};
                elseif numel(c_names) >= hemiIdx && (ischar(c_names{1}) || isstring(c_names{1}))
                    hemi_names = c_names;
                else
                    hemi_names = c_names{1};
                end
            end
            
            if iscell(c_data)
                if numel(c_data) >= hemiIdx
                    hemi_data = c_data{hemiIdx};
                else
                    hemi_data = c_data{1};
                end
            elseif isnumeric(c_data)
                hemi_data = c_data;
            end
        end
        
        function [freqs, fft_mag] = calculateSignalFFT(~, signal, fs_raw)
            freqs = []; fft_mag = [];
            if isempty(signal) || length(signal) < 250
                return;
            end
            
            fs = 250;
            if ~isempty(fs_raw)
                if iscell(fs_raw), fs = double(fs_raw{1}); else, fs = double(fs_raw); end
            end
            signal = signal(:);
            n = 250;
            window_overlap = 2;
            window_welch   = hann(n);
            
            m_len = length(signal) - mod(length(signal), n);
            num_windows = window_overlap * m_len / n - (window_overlap - 1);
            if num_windows < 1, return; end
            L_out = (n + 6) / 2;
            window_fft = zeros(num_windows, L_out);
            L_half = L_out;
            for i = 1:num_windows
                idx_st = (i-1)*n/window_overlap + 1;
                idx_en = idx_st + n - 1;
                if idx_en > length(signal), break; end
                y_clean = detrend(signal(idx_st:idx_en));
                Y = fft([y_clean .* window_welch; zeros(6, 1)]);
                L_half = round(length(Y) / 2);
                window_fft(i, :) = abs(Y(1:L_half)) / L_half;
            end
            Nyquist = 0.5 * fs;
            freqs   = linspace(Nyquist / L_half, Nyquist, L_half) - Nyquist / L_half;
            fft_mag = 2.3 * mean(window_fft, 1);
        end
        
        function drawContactRings(obj, axTarget, stim_cell)
            hold(axTarget, 'on');
            segment_angles = [-20 80; 100 200; 220 320];
            
            for i = 0:3
                x_center = i * (2 * obj.Radius + obj.Spacing);
                y_center = 0;
                
                if i == 1 || i == 2
                    for j = 1:3
                        ang_start = segment_angles(j, 1) * pi / 180;
                        ang_end   = segment_angles(j, 2) * pi / 180;
                        
                        theta = linspace(ang_start, ang_end, 50);
                        x = obj.Radius * cos(theta) + x_center;
                        y = obj.Radius * sin(theta) + y_center;
                        
                        plot(axTarget, x, y, 'k-', 'LineWidth', 1.2);
                        
                        mid_ang = (ang_start + ang_end) / 2;
                        tx = x_center + 1.6 * obj.Radius * cos(mid_ang);
                        ty = y_center + 1.6 * obj.Radius * sin(mid_ang);
                        
                        val_str = stim_cell{i+1}{j};
                        if ~isempty(val_str) && ~strcmp(val_str, '0') && ~strcmp(val_str, '')
                            rot_ang = rad2deg(mid_ang - pi/2);
                            if j == 3, rot_ang = rad2deg(mid_ang + pi/2); end
                            text(axTarget, tx, ty, [val_str, ' mA'], 'FontSize', 5.0, ...
                                'FontWeight', 'bold', 'HorizontalAlignment', 'center', 'Rotation', rot_ang, 'Interpreter', 'none');
                        end
                    end
                else
                    theta = linspace(0, 2*pi, 100);
                    x = obj.Radius * cos(theta) + x_center;
                    y = obj.Radius * sin(theta) + y_center;
                    plot(axTarget, x, y, 'k-', 'LineWidth', 1.0);
                    
                    val_str = stim_cell{i+1};
                    if ~isempty(val_str) && ~strcmp(val_str, '0') && ~strcmp(val_str, '')
                        text(axTarget, x_center, y_center - 1.7 * obj.Radius, [val_str, ' mA'], ...
                            'FontSize', 5.0, 'FontWeight', 'bold', 'HorizontalAlignment', 'center', 'Interpreter', 'none');
                    end
                end
                
                text(axTarget, x_center, y_center, num2str(i), 'FontSize', 8.0, ...
                    'FontWeight', 'bold', 'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', 'Interpreter', 'none');
            end
            
            axis(axTarget, 'equal'); 
            axis(axTarget, 'off');
            xlim(axTarget, [-15, 3 * (2 * obj.Radius + obj.Spacing) + 15]);
            ylim(axTarget, [-22, 22]);
        end
        
        function drawSymptomColumn(obj, symptomName, xOffset, hemiIdx, bodySide)
            ws = obj.ParentApp.WorkspaceData;
            
            % Determine task suffix and the appropriate validation mask
            if hemiIdx == 1
                hemi_char = 'L';
                alt_char  = 'a';
                mask = ws.verified_left_mask;
            else
                hemi_char = 'R';
                alt_char  = 'b';
                mask = ws.verified_right_mask;
            end
            
            % Map the Symptom Name to its core Protocol Task IDs
            task_ids = string.empty;
            if contains(lower(symptomName), 'tremor')
                task_ids = ["2" + hemi_char];
            elseif contains(lower(symptomName), 'rigidity')
                task_ids = ["3" + hemi_char];
            elseif contains(lower(symptomName), 'bradykinesia')
                task_ids = ["4" + hemi_char, "4" + alt_char];
            end
            
            % Validate against the Data Quality Auditor masks
            is_valid = true; % Default true for unmapped/generic symptoms
            if ~isempty(task_ids) && isfield(ws, 'audited_run_labels')
                is_valid = false; % Assume false unless explicitly found and verified
                for k = 1:length(task_ids)
                    idx = find(string(ws.audited_run_labels) == task_ids(k), 1);
                    if ~isempty(idx) && mask(idx) == true
                        is_valid = true;
                        break;
                    end
                end
            end
            
            % Route to the renderer, or display the invalid placeholder
            if ~is_valid
                obj.drawInvalidColumn(symptomName, xOffset, bodySide);
            else
                if contains(lower(symptomName), 'tremor')
                    tremData = obj.computeTremorMetrics(hemiIdx);
                    obj.drawTremorColumn(xOffset, bodySide, tremData);
                elseif contains(lower(symptomName), 'rigidity')
                    rigData = obj.computeRigidityMetrics(hemiIdx);
                    obj.drawRigidityColumn(xOffset, bodySide, rigData);
                elseif contains(lower(symptomName), 'bradykinesia')
                    bradyData = obj.computeBradykinesiaMetrics(hemiIdx);
                    obj.drawBradykinesiaColumn(xOffset, bodySide, bradyData);
                else
                    obj.drawGenericSymptomColumn(symptomName, xOffset, hemiIdx, bodySide);
                end
            end
        end
        
       function drawTremorColumn(obj, xOffset, bodySide, tremData)
            num_steps = numel(tremData.steps);
            formatted_labels = cell(1, num_steps);
            for i = 1:num_steps
                lbl = tremData.step_labels{i};
                if ismember(tremData.steps(i), tremData.therapeutic_steps)
                    formatted_labels{i} = sprintf('\\color[rgb]{0,0.6,0}%s^*', lbl); 
                else
                    formatted_labels{i} = sprintf('\\color{black}%s', lbl);
                end
            end
            plotWidth = 0.22; plotHeight = 0.14;
            y_ax3 = 0.03; y_ax2 = 0.23; y_ax1 = 0.43;
            
            titleAx = axes('Parent', obj.CanvasFig, 'Position', [xOffset + 0.015, 0.58, plotWidth, 0.025]);
            text(titleAx, 0.50, 0.50, sprintf('Tremor Profile\n(%s)', bodySide), ...
                'FontSize', 7.5, 'FontWeight', 'bold', 'HorizontalAlignment', 'center', ...
                'BackgroundColor', [0.93 0.93 0.93], 'Interpreter', 'none');
            xlim(titleAx, [0 1]); ylim(titleAx, [0 1]); axis(titleAx, 'off');
            
            % =========================================================================
            % PLOT 1: UPDRS vs RMS Acceleration
            % =========================================================================
            ax1 = axes('Parent', obj.CanvasFig, 'Position', [xOffset + 0.015, y_ax1, plotWidth, plotHeight]);
            hold(ax1, 'on'); grid(ax1, 'off');
            
            % 1. Right Y-Axis: RMS Acceleration (DRAWN FIRST)
            yyaxis(ax1, 'right');
            raw_rms = tremData.rms_accel;
            p1 = plot(ax1, 1:num_steps, raw_rms, ':o', 'Color', 'r', 'LineWidth', 1.5, 'MarkerSize', 4, 'MarkerFaceColor', 'r');
            ylim(ax1, [-0.05, 0.45]);
            yticks(ax1, [0, 0.1, 0.2, 0.3, 0.4]);
            ylabel(ax1, 'RMS Acceleration [m/s^2]', 'Color', 'r', 'FontSize', 6.5, 'FontWeight', 'bold');
            ax1.YColor = 'r';
            
            % 2. Left Y-Axis: UPDRS (DRAWN SECOND - WILL OVERLAY)
            yyaxis(ax1, 'left');
            p2 = plot(ax1, 1:num_steps, tremData.updrs_scores, '-^', 'Color', [0.5 0.5 0.5], 'LineWidth', 1.2, 'MarkerSize', 5, 'MarkerFaceColor', [0.5 0.5 0.5]);
            ylim(ax1, [-0.5, 4.5]); yticks(ax1, 0:1:4);
            ylabel(ax1, sprintf('UPDRS %s', bodySide), 'Color', 'k', 'FontSize', 6.5, 'FontWeight', 'bold', 'Interpreter', 'none');
            ax1.YColor = 'k';
            
            xlim(ax1, [0.5, num_steps + 0.5]);
            set(ax1, 'LineWidth', 1.0, 'Box', 'off', 'TickDir', 'out', 'XTick', 1:num_steps);
            ax1.XTickLabels = formatted_labels; ax1.TickLabelInterpreter = 'tex'; ax1.XTickLabelRotation = 0; 
            set(ax1, 'FontSize', 7.0, 'FontWeight', 'bold');
            
            % 3. Force rendering engine to respect plotting order
            z1 = zeros(size(p1.XData)); z1(isnan(p1.YData)) = NaN; p1.ZData = z1;
            z2 = ones(size(p2.XData));  z2(isnan(p2.YData)) = NaN; p2.ZData = z2;
            set(ax1, 'SortMethod', 'depth');
            
            % =========================================================================
            % PLOT 2: TIME SPENT IN STATE (BAR CHART)
            % =========================================================================
            ax2 = axes('Parent', obj.CanvasFig, 'Position', [xOffset + 0.015, y_ax2, plotWidth, plotHeight]);
            hold(ax2, 'on'); grid(ax2, 'off');
            
            b = bar(ax2, 1:num_steps, tremData.state_pct_matrix', 'stacked', 'EdgeColor', 'k');
            if length(b) >= 1, b(1).FaceColor = [0 0.447 0.741]; end     % Rest (Blue)
            if length(b) >= 2, b(2).FaceColor = [0.929 0.694 0.125]; end % Movement (Yellow)
            if length(b) >= 3, b(3).FaceColor = [0.85 0.15 0.15]; end    % Tremor (Pure Red)
            
            ylim(ax2, [0, 100]); yticks(ax2, [0, 50, 100]);
            yticklabels(ax2, {'0%', '50%', '100%'});
            ylabel(ax2, 'Time Spent in State (%)', 'Color', 'k', 'FontSize', 6.5, 'FontWeight', 'bold');
            xlim(ax2, [0.5, num_steps + 0.5]);
            
            set(ax2, 'LineWidth', 1.0, 'Box', 'off', 'TickDir', 'out', 'XTick', 1:num_steps);
            ax2.XTickLabels = formatted_labels; ax2.TickLabelInterpreter = 'tex'; ax2.XTickLabelRotation = 0; 
            set(ax2, 'FontSize', 7.0, 'FontWeight', 'bold');
            
            hRest = plot(ax2, NaN, NaN, 's', 'MarkerSize', 7, 'MarkerFaceColor', [0 0.447 0.741], 'MarkerEdgeColor', 'k', 'LineStyle', 'none');
            hMov  = plot(ax2, NaN, NaN, 's', 'MarkerSize', 7, 'MarkerFaceColor', [0.929 0.694 0.125], 'MarkerEdgeColor', 'k', 'LineStyle', 'none');
            hTrem = plot(ax2, NaN, NaN, 's', 'MarkerSize', 7, 'MarkerFaceColor', [0.85 0.15 0.15], 'MarkerEdgeColor', 'k', 'LineStyle', 'none');
            lgd2 = legend(ax2, [hRest, hMov, hTrem], {'Rest', 'Movement', 'Tremor'}, 'Box', 'off', 'FontSize', 6.5, 'Orientation', 'horizontal');
            lgd2.Position = [xOffset + 0.015, y_ax2 - 0.05, plotWidth, 0.02];
            
            % =========================================================================
            % PLOT 3: RELATIVE BETA BAND POWER
            % =========================================================================
            ax3 = axes('Parent', obj.CanvasFig, 'Position', [xOffset + 0.015, y_ax3, plotWidth, plotHeight]);
            hold(ax3, 'on'); grid(ax3, 'off');
            tbl = tremData.beta_table; max_beta = 2.1; 
            if ~isempty(tbl)
                bc = boxchart(ax3, tbl.StepIdx, tbl.BetaPower, 'GroupByColor', tbl.State, 'Notch', 'on', 'MarkerStyle', 'none');
                if length(bc) >= 1, bc(1).BoxFaceColor = [0.6 0.85 0.95]; bc(1).MarkerColor = [0 0.4470 0.7410]; end
                if length(bc) >= 2, bc(2).BoxFaceColor = [0.95 0.70 0.70]; bc(2).MarkerColor = [0.85 0.15 0.15]; end
                max_beta = max(2.1, max(tbl.BetaPower) * 1.1);
            end
            ylim(ax3, [0 max_beta]); yticks(ax3, 0:0.5:10); xlim(ax3, [0.5, num_steps + 0.5]);
            ylabel(ax3, 'Relative Beta Band Power', 'FontSize', 6.5, 'FontWeight', 'bold');
            set(ax3, 'LineWidth', 1.0, 'Box', 'off', 'TickDir', 'out', 'XTick', 1:num_steps);
            ax3.XTickLabels = formatted_labels; ax3.TickLabelInterpreter = 'tex'; ax3.XTickLabelRotation = 0; 
            set(ax3, 'FontSize', 7.0, 'FontWeight', 'bold'); 
            
            h1 = plot(ax3, NaN, NaN, 's', 'MarkerSize', 7, 'MarkerFaceColor', [0.6 0.85 0.95], 'MarkerEdgeColor', [0 0.4470 0.7410], 'LineStyle', 'none');
            h2 = plot(ax3, NaN, NaN, 's', 'MarkerSize', 7, 'MarkerFaceColor', [0.95 0.70 0.70], 'MarkerEdgeColor', [0.85 0.15 0.15], 'LineStyle', 'none');
            h3 = plot(ax3, NaN, NaN, '*', 'MarkerSize', 6, 'Color', [0 0.6 0], 'LineStyle', 'none'); 
            lgd3 = legend(ax3, [h1, h2, h3], {'Rest', 'Tremor', 'Therapeutic window'}, 'Box', 'off', 'FontSize', 7.5, 'Interpreter', 'none');
            lgd3.Position = [xOffset + 0.10, y_ax3 + 0.10, 0.13, 0.05];
       end

       function drawRigidityColumn(obj, xOffset, bodySide, rigData)
            num_steps = numel(rigData.steps);
            formatted_labels = cell(1, num_steps);
            for i = 1:num_steps
                lbl = rigData.step_labels{i};
                if ismember(rigData.steps(i), rigData.therapeutic_steps)
                    formatted_labels{i} = sprintf('\\color[rgb]{0,0.6,0}%s^*', lbl); 
                else
                    formatted_labels{i} = sprintf('\\color{black}%s', lbl);
                end
            end
            plotWidth = 0.22; plotHeight = 0.14;
            y_ax3 = 0.03; y_ax2 = 0.23; y_ax1 = 0.43;
            
            titleAx = axes('Parent', obj.CanvasFig, 'Position', [xOffset + 0.015, 0.58, plotWidth, 0.025]);
            text(titleAx, 0.50, 0.50, sprintf('Rigidity Profile\n(%s)', bodySide), ...
                'FontSize', 7.5, 'FontWeight', 'bold', 'HorizontalAlignment', 'center', ...
                'BackgroundColor', [0.93 0.93 0.93], 'Interpreter', 'none');
            xlim(titleAx, [0 1]); ylim(titleAx, [0 1]); axis(titleAx, 'off');
            
            % ==============================================================
            % PLOT 1: UPDRS vs ROM (Passive & Activated)
            % ==============================================================
            ax1 = axes('Parent', obj.CanvasFig, 'Position', [xOffset + 0.015, y_ax1, plotWidth, plotHeight]);
            hold(ax1, 'on'); grid(ax1, 'off');
            
            % 1. Right Y-Axis: ROM 
            yyaxis(ax1, 'right');
            
            raw_rom_p = rigData.mean_rom_passive;
            raw_rom_p(raw_rom_p > 280) = 280; raw_rom_p(raw_rom_p < 100) = 100;
            mapped_rom_p = (280 - raw_rom_p) / 45; 
            
            raw_rom_a = rigData.mean_rom_activated;
            raw_rom_a(raw_rom_a > 280) = 280; raw_rom_a(raw_rom_a < 100) = 100;
            mapped_rom_a = (280 - raw_rom_a) / 45; 
            
            % PLOT DUMMIES FOR LEGEND (NO ZDATA APPLIED TO THESE)
            plot(ax1, NaN, NaN, ':o', 'Color', [0 0.6 0], 'LineWidth', 1.5, 'MarkerSize', 4, 'MarkerFaceColor', [0 0.6 0], 'DisplayName', 'Passive');
            plot(ax1, NaN, NaN, ':s', 'Color', [0 0.6 0], 'LineWidth', 1.5, 'MarkerSize', 5, 'MarkerFaceColor', 'none', 'DisplayName', 'Activated');
            
            % PLOT SAFE 3D SEGMENTS
            obj.plotSafe3DLine(ax1, 1:num_steps, mapped_rom_p, ':o', [0 0.6 0], 1.5, 4, [0 0.6 0], 0);
            obj.plotSafe3DLine(ax1, 1:num_steps, mapped_rom_a, ':s', [0 0.6 0], 1.5, 5, 'none', 1);
            
            ylim(ax1, [-0.5, 4.5]); 
            yticks(ax1, [0, 1, 2, 3, 4]); 
            yticklabels(ax1, {'280^\circ', '235^\circ', '190^\circ', '145^\circ', '100^\circ'}); 
            ylabel(ax1, 'Range of Motion (deg)', 'Color', [0 0.6 0], 'FontSize', 6.5, 'FontWeight', 'bold');
            ax1.YColor = [0 0.6 0]; xlim(ax1, [0.5, num_steps + 0.5]); 
            
            % 2. Left Y-Axis: UPDRS 
            yyaxis(ax1, 'left'); 
            
            % PLOT SAFE 3D UPDRS SEGMENT
            obj.plotSafe3DLine(ax1, 1:num_steps, rigData.updrs_scores, '-^', [0.5 0.5 0.5], 1.2, 5, [0.5 0.5 0.5], 2);
            
            ylim(ax1, [-0.5, 4.5]); yticks(ax1, 0:1:4);
            ylabel(ax1, sprintf('UPDRS %s', bodySide), 'Color', 'k', 'FontSize', 6.5, 'FontWeight', 'bold', 'Interpreter', 'none');
            ax1.YColor = 'k';
            
            set(ax1, 'LineWidth', 1.0, 'Box', 'off', 'TickDir', 'out', 'XTick', 1:num_steps);
            ax1.XTickLabels = formatted_labels; ax1.TickLabelInterpreter = 'tex'; ax1.XTickLabelRotation = 0; 
            set(ax1, 'FontSize', 7.0, 'FontWeight', 'bold'); 
            
            % SAFE DEPTH SORTING IS NOW ACTIVE
            set(ax1, 'SortMethod', 'depth');
            legend(ax1, 'Location', 'northeast', 'Box', 'off', 'FontSize', 6, 'TextColor', [0 0.6 0]);
            
            % ==============================================================
            % PLOT 2: UPDRS vs ncRMS (Passive & Activated)
            % ==============================================================
            ax2 = axes('Parent', obj.CanvasFig, 'Position', [xOffset + 0.015, y_ax2, plotWidth, plotHeight]);
            hold(ax2, 'on'); grid(ax2, 'off');
            
            % 1. Right Y-Axis: ncRMS 
            yyaxis(ax2, 'right');
            
            raw_nc_p = rigData.crms_pass;
            raw_nc_p(raw_nc_p > 40) = 40; raw_nc_p(raw_nc_p < 0) = 0;
            mapped_nc_p = raw_nc_p / 10; 
            
            raw_nc_a = rigData.crms_act;
            raw_nc_a(raw_nc_a > 40) = 40; raw_nc_a(raw_nc_a < 0) = 0;
            mapped_nc_a = raw_nc_a / 10; 
            
            % PLOT DUMMIES FOR LEGEND
            plot(ax2, NaN, NaN, ':o', 'Color', [0 0.6 0], 'LineWidth', 1.5, 'MarkerSize', 4, 'MarkerFaceColor', [0 0.6 0], 'DisplayName', 'Passive');
            plot(ax2, NaN, NaN, ':s', 'Color', [0 0.6 0], 'LineWidth', 1.5, 'MarkerSize', 5, 'MarkerFaceColor', 'none', 'DisplayName', 'Activated');
            
            % PLOT SAFE 3D SEGMENTS
            obj.plotSafe3DLine(ax2, 1:num_steps, mapped_nc_p, ':o', [0 0.6 0], 1.5, 4, [0 0.6 0], 0);
            obj.plotSafe3DLine(ax2, 1:num_steps, mapped_nc_a, ':s', [0 0.6 0], 1.5, 5, 'none', 1);
            
            ylim(ax2, [-0.5, 4.5]); 
            yticks(ax2, [0, 1, 2, 3, 4]); 
            yticklabels(ax2, {'0%', '10%', '20%', '30%', '40%'}); 
            ylabel(ax2, 'Cogwheel RMS Ratio (%)', 'Color', [0 0.6 0], 'FontSize', 6.5, 'FontWeight', 'bold');
            ax2.YColor = [0 0.6 0]; xlim(ax2, [0.5, num_steps + 0.5]);
            
            % 2. Left Y-Axis: UPDRS
            yyaxis(ax2, 'left'); 
            
            % PLOT SAFE 3D UPDRS SEGMENT
            obj.plotSafe3DLine(ax2, 1:num_steps, rigData.updrs_scores, '-^', [0.5 0.5 0.5], 1.2, 5, [0.5 0.5 0.5], 2);
            
            ylim(ax2, [-0.5, 4.5]); yticks(ax2, 0:1:4);
            ylabel(ax2, sprintf('UPDRS %s', bodySide), 'Color', 'k', 'FontSize', 6.5, 'FontWeight', 'bold', 'Interpreter', 'none');
            ax2.YColor = 'k';
            
            set(ax2, 'LineWidth', 1.0, 'Box', 'off', 'TickDir', 'out', 'XTick', 1:num_steps);
            ax2.XTickLabels = formatted_labels; ax2.TickLabelInterpreter = 'tex'; ax2.XTickLabelRotation = 0; 
            set(ax2, 'FontSize', 7.0, 'FontWeight', 'bold');
            
            % SAFE DEPTH SORTING IS NOW ACTIVE
            set(ax2, 'SortMethod', 'depth');
            legend(ax2, 'Location', 'northeast', 'Box', 'off', 'FontSize', 6, 'TextColor', [0 0.6 0]);
            
            % ==============================================================
            % PLOT 3: LFP BETA POWER
            % ==============================================================
            ax3 = axes('Parent', obj.CanvasFig, 'Position', [xOffset + 0.015, y_ax3, plotWidth, plotHeight]);
            hold(ax3, 'on'); grid(ax3, 'off');
            tbl = rigData.beta_table; max_beta = 2.1; 
            
            % THE FIX: Protect the boxchart vectorizer by filtering out pure NaNs
            if ~isempty(tbl) && ~all(isnan(tbl.BetaPower))
                % Remove the rows that are NaN to prevent empty category notches crashing
                tbl(isnan(tbl.BetaPower), :) = [];
                
                bc = boxchart(ax3, tbl.StepIdx, tbl.BetaPower, 'GroupByColor', tbl.State, 'Notch', 'on', 'MarkerStyle', 'none');
                
                % Dynamically assign colors based on surviving categories
                cats = categories(tbl.State);
                for c = 1:length(bc)
                    if strcmp(string(bc(c).SeriesIndex), '1') || strcmp(cats{1}, 'Rest') && c==1
                        bc(c).BoxFaceColor = [0.6 0.85 0.95]; bc(c).MarkerColor = [0 0.4470 0.7410];
                    else
                        bc(c).BoxFaceColor = [0.15 0.40 0.60]; bc(c).MarkerColor = [0.05 0.25 0.45];
                    end
                end
                max_beta = max(2.1, max(tbl.BetaPower) * 1.1);
            end
            
            ylim(ax3, [0 max_beta]); yticks(ax3, 0:0.5:10); xlim(ax3, [0.5, num_steps + 0.5]);
            ylabel(ax3, 'Relative Beta Band Power', 'FontSize', 6.5, 'FontWeight', 'bold');
            set(ax3, 'LineWidth', 1.0, 'Box', 'off', 'TickDir', 'out', 'XTick', 1:num_steps);
            ax3.XTickLabels = formatted_labels; ax3.TickLabelInterpreter = 'tex'; ax3.XTickLabelRotation = 0; 
            set(ax3, 'FontSize', 7.0, 'FontWeight', 'bold'); 
            
            h1 = plot(ax3, NaN, NaN, 's', 'MarkerSize', 7, 'MarkerFaceColor', [0.6 0.85 0.95], 'MarkerEdgeColor', [0 0.4470 0.7410], 'LineStyle', 'none');
            h2 = plot(ax3, NaN, NaN, 's', 'MarkerSize', 7, 'MarkerFaceColor', [0.15 0.40 0.60], 'MarkerEdgeColor', [0.05 0.25 0.45], 'LineStyle', 'none');
            h3 = plot(ax3, NaN, NaN, '*', 'MarkerSize', 6, 'Color', [0 0.6 0], 'LineStyle', 'none'); 
            lgd3 = legend(ax3, [h1, h2, h3], {'Rest', 'Testing', 'Therapeutic window'}, 'Box', 'off', 'FontSize', 7.5, 'Interpreter', 'none');
            lgd3.Position = [xOffset + 0.10, y_ax3 + 0.10, 0.13, 0.05];
       end
       
       function drawBradykinesiaColumn(obj, xOffset, bodySide, bradyData)
            num_steps = numel(bradyData.steps);
            formatted_labels = cell(1, num_steps);
            for i = 1:num_steps
                lbl = bradyData.step_labels{i};
                if ismember(bradyData.steps(i), bradyData.therapeutic_steps)
                    formatted_labels{i} = sprintf('\\color[rgb]{0,0.6,0}%s^*', lbl); 
                else
                    formatted_labels{i} = sprintf('\\color{black}%s', lbl);
                end
            end
            plotWidth = 0.22; plotHeight = 0.14;
            y_ax3 = 0.03; y_ax2 = 0.23; y_ax1 = 0.43;
            
            titleAx = axes('Parent', obj.CanvasFig, 'Position', [xOffset + 0.015, 0.58, plotWidth, 0.025]);
            text(titleAx, 0.50, 0.50, sprintf('Bradykinesia Profile\n(%s)', bodySide), ...
                'FontSize', 7.5, 'FontWeight', 'bold', 'HorizontalAlignment', 'center', ...
                'BackgroundColor', [0.93 0.93 0.93], 'Interpreter', 'none');
            xlim(titleAx, [0 1]); ylim(titleAx, [0 1]); axis(titleAx, 'off');
            
            % =========================================================================
            % PLOT 1: MEAN OPENING JOINT ROM (deg)
            % =========================================================================
            ax1 = axes('Parent', obj.CanvasFig, 'Position', [xOffset + 0.015, y_ax1, plotWidth, plotHeight]);
            hold(ax1, 'on'); grid(ax1, 'off');
            
            % 1. Right Y-Axis: ROM (DRAWN FIRST)
            yyaxis(ax1, 'right');
            rom_vals = bradyData.mean_rom;
            rom_vals(isnan(rom_vals) | rom_vals == 0) = 40; % Safety fallback
            rom_vals(rom_vals > 200) = 200;
            rom_vals(rom_vals < 40) = 40;
            mapped_rom = (200 - rom_vals) / 40;
            
            p1 = plot(ax1, 1:num_steps, mapped_rom, ':o', 'Color', [0 0.6 0], 'LineWidth', 1.5, 'MarkerSize', 4, 'MarkerFaceColor', [0 0.6 0]);
            
            ylim(ax1, [-0.5, 4.5]); yticks(ax1, 0:4); 
            yticklabels(ax1, {'200^\circ', '160^\circ', '120^\circ', '80^\circ', '40^\circ'}); 
            ylabel(ax1, 'Mean Opening ROM (deg)', 'Color', [0 0.6 0], 'FontSize', 6.5, 'FontWeight', 'bold');
            ax1.YColor = [0 0.6 0]; xlim(ax1, [0.5, num_steps + 0.5]); 
            
            % 2. Left Y-Axis: UPDRS (DRAWN SECOND - WILL OVERLAY)
            yyaxis(ax1, 'left'); 
            p2 = plot(ax1, 1:num_steps, bradyData.updrs_scores, '-^', 'Color', [0.5 0.5 0.5], 'LineWidth', 1.2, 'MarkerSize', 5, 'MarkerFaceColor', [0.5 0.5 0.5]);
            ylim(ax1, [-0.5, 4.5]); yticks(ax1, 0:1:4);
            ylabel(ax1, sprintf('UPDRS %s', bodySide), 'Color', 'k', 'FontSize', 6.5, 'FontWeight', 'bold', 'Interpreter', 'none');
            ax1.YColor = 'k';
            
            set(ax1, 'LineWidth', 1.0, 'Box', 'off', 'TickDir', 'out', 'XTick', 1:num_steps);
            ax1.XTickLabels = formatted_labels; ax1.TickLabelInterpreter = 'tex'; ax1.XTickLabelRotation = 0; 
            set(ax1, 'FontSize', 7.0, 'FontWeight', 'bold'); 
            
            % 3. Force rendering engine to respect plotting order safely
            z1 = zeros(size(p1.XData)); z1(isnan(p1.YData)) = NaN; p1.ZData = z1;
            z2 = ones(size(p2.XData));  z2(isnan(p2.YData)) = NaN; p2.ZData = z2;
            
            % Use ax1 for Plot 1, and ax2 for Plot 2 (do not use gca)
            set(ax1, 'SortMethod', 'depth');
            
            % =========================================================================
            % PLOT 2: OPENING / CLOSING ASYMMETRY RATIO 
            % =========================================================================
            ax2 = axes('Parent', obj.CanvasFig, 'Position', [xOffset + 0.015, y_ax2, plotWidth, plotHeight]);
            hold(ax2, 'on'); grid(ax2, 'off');
            
            % 1. Right Y-Axis: Asymmetry Ratio (DRAWN FIRST)
            yyaxis(ax2, 'right');
            raw_ratio = bradyData.mean_ratio; 
            raw_ratio(isnan(raw_ratio)) = 0.5; % Safety fallback
            raw_ratio(raw_ratio > 1.3) = 1.3;
            raw_ratio(raw_ratio < 0.5) = 0.5;
            mapped_ratio = (1.3 - raw_ratio) / 0.2; 
            
            p1 = plot(ax2, 1:num_steps, mapped_ratio, ':o', 'Color', [0 0.6 0], 'LineWidth', 1.5, 'MarkerSize', 4, 'MarkerFaceColor', [0 0.6 0]);
            
            ylim(ax2, [-0.5, 4.5]); yticks(ax2, 0:4); 
            yticklabels(ax2, {'1.3', '1.1', '0.9', '0.7', '0.5'}); 
            ylabel(ax2, 'Asymmetry Ratio (R_{open/close})', 'Color', [0 0.6 0], 'FontSize', 6.5, 'FontWeight', 'bold', 'Interpreter', 'tex');
            ax2.YColor = [0 0.6 0]; xlim(ax2, [0.5, num_steps + 0.5]);
            
            % 2. Left Y-Axis: UPDRS (DRAWN SECOND - WILL OVERLAY)
            yyaxis(ax2, 'left'); 
            p2 = plot(ax2, 1:num_steps, bradyData.updrs_scores, '-^', 'Color', [0.5 0.5 0.5], 'LineWidth', 1.2, 'MarkerSize', 5, 'MarkerFaceColor', [0.5 0.5 0.5]);
            ylim(ax2, [-0.5, 4.5]); yticks(ax2, 0:1:4);
            ylabel(ax2, sprintf('UPDRS %s', bodySide), 'Color', 'k', 'FontSize', 6.5, 'FontWeight', 'bold', 'Interpreter', 'none');
            ax2.YColor = 'k';
            
            set(ax2, 'LineWidth', 1.0, 'Box', 'off', 'TickDir', 'out', 'XTick', 1:num_steps);
            ax2.XTickLabels = formatted_labels; ax2.TickLabelInterpreter = 'tex'; ax2.XTickLabelRotation = 0; 
            set(ax2, 'FontSize', 7.0, 'FontWeight', 'bold');
            
            % 3. Force rendering engine to respect plotting order safely
            z1 = zeros(size(p1.XData)); z1(isnan(p1.YData)) = NaN; p1.ZData = z1;
            z2 = ones(size(p2.XData));  z2(isnan(p2.YData)) = NaN; p2.ZData = z2;
            
            % Use ax1 for Plot 1, and ax2 for Plot 2 (do not use gca)
            set(ax2, 'SortMethod', 'depth');
            
            % =========================================================================
            % PLOT 3: RELATIVE BETA BAND POWER
            % =========================================================================
            ax3 = axes('Parent', obj.CanvasFig, 'Position', [xOffset + 0.015, y_ax3, plotWidth, plotHeight]);
            hold(ax3, 'on'); grid(ax3, 'off');
            tbl = bradyData.beta_table; max_beta = 2.1; 
            if ~isempty(tbl)
                bc = boxchart(ax3, tbl.StepIdx, tbl.BetaPower, 'GroupByColor', tbl.State, 'Notch', 'on', 'MarkerStyle', 'none');
                if length(bc) >= 1, bc(1).BoxFaceColor = [0.6 0.85 0.95]; bc(1).MarkerColor = [0 0.4470 0.7410]; end
                if length(bc) >= 2, bc(2).BoxFaceColor = [0.15 0.40 0.60]; bc(2).MarkerColor = [0.05 0.25 0.45]; end
                max_beta = max(2.1, max(tbl.BetaPower) * 1.1);
            end
            ylim(ax3, [0 max_beta]); yticks(ax3, 0:0.5:10); xlim(ax3, [0.5, num_steps + 0.5]);
            ylabel(ax3, 'Relative Beta Band Power', 'FontSize', 6.5, 'FontWeight', 'bold');
            set(ax3, 'LineWidth', 1.0, 'Box', 'off', 'TickDir', 'out', 'XTick', 1:num_steps);
            ax3.XTickLabels = formatted_labels; ax3.TickLabelInterpreter = 'tex'; ax3.XTickLabelRotation = 0; 
            set(ax3, 'FontSize', 7.0, 'FontWeight', 'bold'); 
            
            h1 = plot(ax3, NaN, NaN, 's', 'MarkerSize', 7, 'MarkerFaceColor', [0.6 0.85 0.95], 'MarkerEdgeColor', [0 0.4470 0.7410], 'LineStyle', 'none');
            h2 = plot(ax3, NaN, NaN, 's', 'MarkerSize', 7, 'MarkerFaceColor', [0.15 0.40 0.60], 'MarkerEdgeColor', [0.05 0.25 0.45], 'LineStyle', 'none');
            h3 = plot(ax3, NaN, NaN, '*', 'MarkerSize', 6, 'Color', [0 0.6 0], 'LineStyle', 'none'); 
            lgd3 = legend(ax3, [h1, h2, h3], {'Rest', 'Testing', 'Therapeutic window'}, 'Box', 'off', 'FontSize', 7.5, 'Interpreter', 'none');
            lgd3.Position = [xOffset + 0.10, y_ax3 + 0.10, 0.13, 0.05];
       end

       function drawInvalidColumn(obj, symptomName, xOffset, bodySide)
            plotWidth = 0.22; 
            
            % Generate the exact same title block for visual consistency
            titleAx = axes('Parent', obj.CanvasFig, 'Position', [xOffset + 0.015, 0.58, plotWidth, 0.025]);
            text(titleAx, 0.50, 0.50, sprintf('%s Profile\n(%s)', symptomName, bodySide), ...
                'FontSize', 7.5, 'FontWeight', 'bold', 'HorizontalAlignment', 'center', ...
                'BackgroundColor', [0.93 0.93 0.93], 'Interpreter', 'none');
            xlim(titleAx, [0 1]); ylim(titleAx, [0 1]); axis(titleAx, 'off');
            
            % Span one large axis across the space normally occupied by the 3 sub-plots
            invalidAx = axes('Parent', obj.CanvasFig, 'Position', [xOffset + 0.015, 0.03, plotWidth, 0.54]);
            hold(invalidAx, 'on');
            
            % =========================================================================
            % THE FIX: Use 'patch' instead of 'rectangle' to prevent Vector Export crashes
            % =========================================================================
            x_box = [0 1 1 0];
            y_box = [0 0 1 1];
            patch(invalidAx, 'XData', x_box, 'YData', y_box, ...
                'FaceColor', [0.96 0.96 0.96], 'EdgeColor', [0.8 0.8 0.8], ...
                'LineWidth', 1.5, 'LineStyle', '--');
            
            % Print the rejection message
            text(invalidAx, 0.5, 0.5, sprintf('Titration hasn''t passed\ndata quality requirements.'), ...
                'FontSize', 9, 'FontWeight', 'bold', 'Color', [0.5 0.5 0.5], ...
                'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle');
                
            xlim(invalidAx, [0 1]); ylim(invalidAx, [0 1]);
            axis(invalidAx, 'off');
       end
       
       function drawGenericSymptomColumn(obj, symptomName, xOffset, hemiIdx, bodySide)
            plotWidth = 0.22;
            titleAx = axes('Parent', obj.CanvasFig, 'Position', [xOffset + 0.015, 0.58, plotWidth, 0.025]);
            text(titleAx, 0.50, 0.50, sprintf('%s Profile\n(%s)', symptomName, bodySide), ...
                'FontSize', 7.5, 'FontWeight', 'bold', 'HorizontalAlignment', 'center', ...
                'BackgroundColor', [0.93 0.93 0.93], 'Interpreter', 'none');
            xlim(titleAx, [0 1]); ylim(titleAx, [0 1]); axis(titleAx, 'off');
            v_steps = [0, 0.7, 1.4, 2.1, 2.8];
            
            % Plot 1
            ax1 = axes('Parent', obj.CanvasFig, 'Position', [xOffset + 0.015, 0.45, plotWidth, 0.09]);
            hold(ax1, 'on'); grid(ax1, 'off');
            patch(ax1, [13 35 35 13], [0.05 0.05 30 30], [0.85 0.85 0.85], 'EdgeColor', 'none', 'PickableParts', 'none');
            plot(ax1, 1:60, 8./(1 + ((1:60)-21).^2/12), 'Color', [0 0.45 0.74], 'LineWidth', 1.0);
            set(ax1, 'YScale', 'log', 'YMinorTick', 'off', 'LineWidth', 1.0, 'Box', 'off', 'TickDir', 'out');
            xlim(ax1, [0 60]); ylim(ax1, [0.1 20]);
            set(ax1, 'XTick', [0, 13, 35, 60], 'YTick', [0.1, 1, 10], 'YTickLabel', {'10^{-1}', '10^{0}', '10^{1}'});
            ylabel(ax1, 'Amplitude (log(\muVp))', 'FontSize', 5.5, 'FontWeight', 'bold', 'Interpreter', 'tex'); 
            xlabel(ax1, 'Frequency (Hz)', 'FontSize', 5.5, 'FontWeight', 'bold', 'Interpreter', 'none');
            set(ax1, 'FontSize', 5.5, 'FontWeight', 'bold');
            
            % Plot 2
            ax2 = axes('Parent', obj.CanvasFig, 'Position', [xOffset + 0.015, 0.32, plotWidth, 0.085]);
            hold(ax2, 'on'); grid(ax2, 'off');
            yyaxis(ax2, 'left'); plot(ax2, v_steps, [3 2 1 1 0], '-^', 'Color', [0.4 0.4 0.4], 'LineWidth', 1.0, 'MarkerSize', 3.0);
            ylabel(ax2, sprintf('%s', bodySide), 'FontSize', 5.5, 'FontWeight', 'bold', 'Interpreter', 'none');
            ylim(ax2, [-0.5 4.5]); ax2.YAxis(1).Color = 'k';
            yyaxis(ax2, 'right'); plot(ax2, v_steps, [0.3 0.2 0.1 0.05 0.02], ':r', 'LineWidth', 1.0);
            ylim(ax2, [-0.05 0.4]); ax2.YAxis(2).Color = 'r';
            set(ax2, 'LineWidth', 1.0, 'Box', 'off', 'TickDir', 'out', 'XTick', v_steps, 'XTickLabel', {});
            set(ax2, 'FontSize', 5.5, 'FontWeight', 'bold');
            
            % Plot 3
            ax3 = axes('Parent', obj.CanvasFig, 'Position', [xOffset + 0.015, 0.18, plotWidth, 0.085]);
            hold(ax3, 'on'); grid(ax3, 'off');
            b3 = bar(ax3, v_steps, [80 15 5; 40 45 15; 20 60 20; 10 80 10; 5 92 3], 'stacked', 'BarWidth', 0.4);
            b3(1).FaceColor = [0.00 0.45 0.74]; b3(2).FaceColor = [0.93 0.69 0.13]; b3(3).FaceColor = [0.85 0.33 0.10];
            ylabel(ax3, 'Time Spent in State (%)', 'FontSize', 5.5, 'FontWeight', 'bold', 'Interpreter', 'none'); 
            ylim(ax3, [0 100]); set(ax3, 'LineWidth', 1.0, 'Box', 'off', 'TickDir', 'out', 'XTick', v_steps, 'XTickLabel', {});
            set(ax3, 'FontSize', 5.5, 'FontWeight', 'bold');
            
            % Plot 4
            ax4 = axes('Parent', obj.CanvasFig, 'Position', [xOffset + 0.015, 0.04, plotWidth, 0.085]);
            hold(ax4, 'on'); grid(ax4, 'off');
            box_data = [normrnd(1.1, 0.1, 1, 30); normrnd(0.7, 0.1, 1, 30); normrnd(0.4, 0.05, 1, 30); normrnd(0.2, 0.03, 1, 30); normrnd(0.1, 0.02, 1, 30)]';
            boxplot(ax4, box_data, 'Positions', 1:5, 'Widths', 0.4);
            ylabel(ax4, 'Relative Beta Band Power', 'FontSize', 5.5, 'FontWeight', 'bold', 'Interpreter', 'none'); 
            ylim(ax4, [0 1.6]); set(ax4, 'LineWidth', 1.0, 'Box', 'off', 'TickDir', 'out');
            set(ax4, 'XTick', 1:5, 'XTickLabel', {'0mA','0.7mA','1.4mA*','2.1mA*','2.8mA*'}, 'FontSize', 5.5, 'FontWeight', 'bold');
    end

        function tremData = computeTremorMetrics(obj, hemiIdx)
            ws = obj.ParentApp.WorkspaceData;
            if hemiIdx == 1
                hemi_name   = 'Left';
                task_id     = '2L';
                lfp_col     = 1;
                target_side_str = 'R'; 
                steps_field = 'Tremor_Left';
            else
                hemi_name   = 'Right';
                task_id     = '2R';
                lfp_col     = 2;
                target_side_str = 'L';  
                steps_field = 'Tremor_Right';
            end
            
            % --- 1. EXTRACT TITRATION STEPS ---
            steps = [];
            if isfield(ws, 'clinical_overview_updrs') && isfield(ws.clinical_overview_updrs, 'levels_storage_struct')
                ls = ws.clinical_overview_updrs.levels_storage_struct;
                if isfield(ls, steps_field)
                    steps = ls.(steps_field)(:)';
                end
            end
            if isempty(steps), steps = [0, 1.1, 2.2, 3.3, 4.4]; end
            num_steps = numel(steps);
            step_strs = cell(1, num_steps);
            for s = 1:num_steps
                step_strs{s} = sprintf('%.1fmA', steps(s));
            end
            
            % --- 2. EXTRACT CLINICAL SCORES, SIDEFX, & THERAPEUTIC WINDOW ---
            updrs_tremor = zeros(1, num_steps);
            updrs_total  = zeros(1, num_steps);
            side_effects = false(1, num_steps);
            if isfield(ws, 'clinical_overview_updrs') && isfield(ws.clinical_overview_updrs, 'score_storage_struct')
                ss = ws.clinical_overview_updrs.score_storage_struct;
                h_str = sprintf('Hemi_%d', hemiIdx);
                
                t_score = zeros(1, num_steps); r_score = zeros(1, num_steps); b_score = zeros(1, num_steps);
                
                if isfield(ss, ['Tremor_' h_str]) 
                    if isfield(ss.(['Tremor_' h_str]), 'scores')
                        t_score = ss.(['Tremor_' h_str]).scores(:)';
                        updrs_tremor = t_score;
                    end
                    if isfield(ss.(['Tremor_' h_str]), 'sidefx'), side_effects = side_effects | ss.(['Tremor_' h_str]).sidefx(:)'; end
                end
                if isfield(ss, ['Rigidity_' h_str]) 
                    if isfield(ss.(['Rigidity_' h_str]), 'scores'), r_score = ss.(['Rigidity_' h_str]).scores(:)'; end
                    if isfield(ss.(['Rigidity_' h_str]), 'sidefx'), side_effects = side_effects | ss.(['Rigidity_' h_str]).sidefx(:)'; end
                end
                if isfield(ss, ['Bradykinesia_' h_str])
                    if isfield(ss.(['Bradykinesia_' h_str]), 'scores'), b_score = ss.(['Bradykinesia_' h_str]).scores(:)'; end
                    if isfield(ss.(['Bradykinesia_' h_str]), 'sidefx'), side_effects = side_effects | ss.(['Bradykinesia_' h_str]).sidefx(:)'; end
                end
                
                min_len = min([numel(t_score), numel(r_score), numel(b_score), num_steps]);
                updrs_total(1:min_len) = t_score(1:min_len) + r_score(1:min_len) + b_score(1:min_len);
            end
            base_total = updrs_total(1);
            lower_idx  = find(updrs_total < base_total & steps > 0, 1, 'first');
            first_sidefx_idx = find(side_effects, 1, 'first');
            if isempty(first_sidefx_idx), upper_idx = num_steps; else, upper_idx = first_sidefx_idx - 1; end
            if ~isempty(lower_idx) && lower_idx <= upper_idx, therapeutic_steps = steps(lower_idx:upper_idx); else, therapeutic_steps = []; end
            
            % --- 3. FETCH PRE-ALIGNED DATA ---
            rms_accel = zeros(1, num_steps);
            state_pct_matrix = zeros(3, num_steps); 
            class_segments = cell(1, num_steps);
            
            a_data = ws.AlignedData;
            block_idx = find(string({a_data.task_id}) == task_id, 1);
            
            steps_idx_col = []; beta_col = []; state_col = [];
            resting_beta_lowest = [];
            
            if ~isempty(block_idx)
                a_block = a_data(block_idx);
                
                % LFP and Timelines
                master_time = a_block.CommonTime;
                if isfield(a_block.LFP, 'data_clean') && ~isempty(a_block.LFP.data_clean)
                    LFP_sig = a_block.LFP.data_clean(:, lfp_col);
                else
                    LFP_sig = a_block.LFP.data(:, lfp_col);
                end
                stim_vector = round(a_block.Stim.data(:, lfp_col), 1);
                
                % Kinematics (Already matched to master_time and Fs!)
                wearable_signal = zeros(size(master_time));
                sensor_name = sprintf('HandSensor%s', target_side_str);
                has_kin = isfield(a_block, sensor_name) && ~isempty(a_block.(sensor_name));
                
                if has_kin
                    w_kin = a_block.(sensor_name);
                    
                    % 1. Smoothly bridge gaps in the 250Hz grid using linear interpolation
                    % This prevents 0g cliffs and strictly maintains the uniform sampling 
                    % rate required by filtfilt, replicating your old contiguous arrays.
                    clean_ax = fillmissing(double(w_kin.ax), 'linear', 'EndValues', 'nearest');
                    clean_ay = fillmissing(double(w_kin.ay), 'linear', 'EndValues', 'nearest');
                    clean_az = fillmissing(double(w_kin.az), 'linear', 'EndValues', 'nearest');
                    
                    % 2. Filter axes independently (Exactly like your old code)
                    % Since the data is now on the master_time grid, we use obj.Fs (250Hz)
                    [b_filt, a_filt] = butter(3, [2 8] / (obj.Fs / 2), "bandpass");
                    filt_ax = filtfilt(b_filt, a_filt, clean_ax);
                    filt_ay = filtfilt(b_filt, a_filt, clean_ay);
                    filt_az = filtfilt(b_filt, a_filt, clean_az);
                    
                    % 3. Calculate magnitude AFTER filtering (Exactly like your old code)
                    wearable_signal = sqrt(filt_ax.^2 + filt_ay.^2 + filt_az.^2);
                end
                                   
                % Overwrite boundaries if user locked them in the UI
                bounds_var = sprintf('titration_bounds_%s_synchronized', task_id);
                if isfield(ws, bounds_var), bounds_table = ws.(bounds_var); else, bounds_table = []; end
                
                for i = 1:num_steps
                    step_val = round(steps(i), 1);
                    t_start = NaT; t_end = NaT;
                    
                    if ~isempty(bounds_table) && i <= size(bounds_table, 1) && bounds_table{i, 1} == step_val
                        t_start = bounds_table{i, 2}; t_end = bounds_table{i, 3};
                        if ischar(t_start), t_start = datetime(t_start); end
                        if ischar(t_end), t_end = datetime(t_end); end
                    else
                        % Auto-detect largest chunk perfectly mapped to stim vector
                        matching_indices = find(stim_vector == step_val);
                        if numel(matching_indices) > (5 * obj.Fs)
                            split_pts = find(diff(matching_indices) > 1);
                            c_starts = [matching_indices(1); matching_indices(split_pts + 1)];
                            c_ends   = [matching_indices(split_pts); matching_indices(end)];
                            [~, best_chunk] = max(c_ends - c_starts);
                            t_start = master_time(c_starts(best_chunk));
                            t_end = master_time(c_ends(best_chunk));
                        end
                    end
                    
                    if isnat(t_start) || isnat(t_end)
                        state_pct_matrix(1, i) = 100;
                        continue; 
                    end
                    
                    % 4. CLASSIFICATION & LFP ANALYSIS LOOP
                    mask = (master_time >= t_start & master_time <= t_end);
                    w_seg = wearable_signal(mask);
                    l_seg = LFP_sig(mask);
                    
                    if isempty(w_seg), state_pct_matrix(1, i) = 100; continue; end
                    
                    segment_duration = 3; overlap_ratio = 0.5;
                    window_size  = segment_duration * obj.Fs;
                    overlap_size = round(window_size * overlap_ratio);
                    
                    if length(w_seg) >= window_size
                        [~, ~, T] = spectrogram(w_seg, hamming(window_size), overlap_size, [], obj.Fs);
                        num_epochs = length(T);
                        
                        updated_labels = zeros(1, num_epochs) - 1; % Default Rest
                        ep_rms_all = zeros(1, num_epochs);
                        
                        if has_kin
                            low_freq_power    = zeros(1, num_epochs);
                            tremor_band_power = zeros(1, num_epochs);
                            all_freq_power    = zeros(1, num_epochs);
                            ratio_power       = zeros(1, num_epochs);
                            tremor_dominance  = zeros(1, num_epochs);
                            aux_class         = zeros(1, num_epochs);
                            
                            % =========================================================================
                            % CALIBRATED TREMOR THRESHOLDS (WITH MACRO-MOVEMENT CEILING)
                            % =========================================================================
                            thresh_rest              = 0.003; 
                            thresh_tremor_min_rms    = 0.032;  % Floor: Must be larger than micro-jitters
                            thresh_macro_pkpk        = 0.50;   % NEW CEILING: Max-Min > 0.5g is a Macro-Movement
                            thresh_volitional_secure = 0.7;   
                            thresh_volitional_mid    = 0.5;   
                            
                            for j = 1:num_epochs
                                st_i = max(1, (j-1) * (window_size - overlap_size) + 1);
                                en_i = min(length(w_seg), st_i + window_size - 1);
                                ep_sig = w_seg(st_i:en_i);
                                
                                low_freq_power(j)    = bandpower(ep_sig, obj.Fs, [2 3]);
                                tremor_band_power(j) = bandpower(ep_sig, obj.Fs, [4 7]);
                                all_freq_power(j)    = bandpower(ep_sig, obj.Fs, [2 8]);
                                
                                if low_freq_power(j) > 0, ratio_power(j) = tremor_band_power(j) / low_freq_power(j); else, ratio_power(j) = NaN; end
                                if all_freq_power(j) > 0, tremor_dominance(j) = tremor_band_power(j) / all_freq_power(j); else, tremor_dominance(j) = NaN; end
                                
                                ep_rms = rms(ep_sig);
                                ep_rms_all(j) = ep_rms;
                                
                                % 1. Check for Absolute Rest
                                if ep_rms < thresh_rest
                                    aux_class(j) = -1; % Rest
                                    
                                % 2. Signal is physically large enough to be evaluated as Tremor
                                elseif ep_rms >= thresh_tremor_min_rms
                                    
                                    % NEW: MACRO-MOVEMENT CEILING
                                    if (max(ep_sig) - min(ep_sig)) > thresh_macro_pkpk
                                        aux_class(j) = 0; % Violent Macro-Movement (Disqualifies Action Tremors)
                                        
                                    % BRANCH 1: High Ratio Detection
                                    elseif ratio_power(j) > thresh_volitional_secure
                                        aux_class(j) = 1; % Tremor
                                        
                                    % BRANCH 2: Mid Ratio + Dominance Detection
                                    elseif tremor_dominance(j) >= 0.10 && ratio_power(j) > thresh_volitional_mid
                                        aux_class(j) = 1; % Tremor
                                        
                                    % BRANCH 3: Strong signal, but fails spectral ratios
                                    else
                                        aux_class(j) = 0; % Movement
                                    end
                                    
                                % 3. Signal is too small for Tremor, but too large for Absolute Rest
                                else
                                    if (max(ep_sig) - min(ep_sig)) < 0.03
                                        aux_class(j) = -1; % Rest
                                    else
                                        aux_class(j) = 0; % Movement (Catches micro-jitters)
                                    end
                                end
                            end
                            
                            % Smoothing logic (Unchanged from original math)
                            updated_labels = aux_class;
                            min_tremor_length = 4;
                            n_lbl = length(updated_labels);
                            c_idx = 1;
                            while c_idx <= n_lbl
                                if updated_labels(c_idx) == 1
                                    seg_st = c_idx;
                                    while c_idx <= n_lbl && updated_labels(c_idx) == 1, c_idx = c_idx + 1; end
                                    seg_en = c_idx - 1;
                                    if (seg_en - seg_st + 1) >= min_tremor_length
                                        gap_st = seg_en + 1;
                                        if gap_st <= n_lbl && aux_class(gap_st) ~= 1
                                            gap_en = gap_st;
                                            while gap_en <= n_lbl && aux_class(gap_en) ~= 1, gap_en = gap_en + 1; end
                                            gap_en = gap_en - 1;
                                            if (gap_en - gap_st + 1) < min_tremor_length && gap_en < n_lbl && aux_class(gap_en + 1) == 1
                                                updated_labels(gap_st:gap_en) = 1;
                                            end
                                        end
                                        gap_end = seg_st - 1;
                                        if gap_end > 0 && aux_class(gap_end) ~= 1
                                            gap_start = gap_end;
                                            while gap_start > 0 && aux_class(gap_start) ~= 1, gap_start = gap_start - 1; end
                                            gap_start = gap_start + 1;
                                            if (gap_end - gap_start + 1) < min_tremor_length && gap_start > 1 && aux_class(gap_start - 1) == 1
                                                updated_labels(gap_start:gap_end) = 1;
                                            end
                                        end
                                    else
                                        if seg_st-1 > 0 && updated_labels(seg_st-1) ~= 1 && round(tremor_dominance(seg_st-1),2) >= 0.40 && ratio_power(seg_st-1) > 2, updated_labels(seg_st-1) = 1; end
                                        if seg_st+1 <= n_lbl && updated_labels(seg_st+1) ~= 1 && round(tremor_dominance(seg_st+1),2) >= 0.40 && ratio_power(seg_st+1) > 2, updated_labels(seg_st+1) = 1; end
                                        c_idx = seg_st + 1;
                                    end
                                else
                                    c_idx = c_idx + 1;
                                end
                            end
                            c_idx = 1;
                            while c_idx <= length(updated_labels)
                                if updated_labels(c_idx) == 1
                                    seg_st = c_idx; while c_idx <= length(updated_labels) && updated_labels(c_idx) == 1, c_idx = c_idx + 1; end
                                    seg_en = c_idx - 1;
                                    if (seg_en - seg_st + 1) < min_tremor_length
                                        rep_lbl = 0; if seg_st > 1, rep_lbl = updated_labels(seg_st - 1); elseif seg_en < length(updated_labels), rep_lbl = updated_labels(seg_en + 1); end
                                        updated_labels(seg_st:seg_en) = rep_lbl;
                                    end
                                else, c_idx = c_idx + 1; end
                            end
                            c_idx = 1;
                            while c_idx <= length(updated_labels)
                                if updated_labels(c_idx) == 1
                                    seg_st = c_idx; while c_idx <= length(updated_labels) && updated_labels(c_idx) == 1, c_idx = c_idx + 1; end
                                    seg_en = c_idx - 1;
                                    if (seg_st > 1 && updated_labels(seg_st - 1) == 0) && (seg_en < length(updated_labels) && updated_labels(seg_en + 1) == 0), updated_labels(seg_st:seg_en) = 0; end
                                else, c_idx = c_idx + 1; end
                            end
                            c_idx = 1;
                            while c_idx <= length(updated_labels)
                                if updated_labels(c_idx) == 0
                                    seg_st = c_idx; while c_idx <= length(updated_labels) && updated_labels(c_idx) == 0, c_idx = c_idx + 1; end
                                    seg_en = c_idx - 1;
                                    if (seg_en - seg_st + 1) < min_tremor_length
                                        rep_lbl = 0; if seg_st > 1, rep_lbl = updated_labels(seg_st - 1); elseif seg_en < length(updated_labels), rep_lbl = updated_labels(seg_en + 1); end
                                        if rep_lbl == 1, updated_labels(seg_st:seg_en) = 1; end
                                    end
                                else, c_idx = c_idx + 1; end
                            end
                        end
                        
                        tremor_mask = (updated_labels == 1);
                        if any(tremor_mask), rms_accel(i) = max(ep_rms_all(tremor_mask)); else, rms_accel(i) = 0; end
                        class_segments{i} = updated_labels;
                        state_pct_matrix(1, i) = sum(updated_labels == -1) / num_epochs * 100;
                        state_pct_matrix(2, i) = sum(updated_labels == 0)  / num_epochs * 100;
                        state_pct_matrix(3, i) = sum(updated_labels == 1)  / num_epochs * 100;
                        
                        % --- EXTRACT LFP BETA POWERS MATCHING EXACT KINEMATIC EPOCHS ---
                        for e = 1:num_epochs
                            % CLINICAL UPDATE: Skip voluntary movement artifacts (class 0) 
                            % so they do not pollute the Resting Beta baseline.
                            if updated_labels(e) == 0
                                continue; 
                            end
                            
                            st_i = (e-1) * (window_size - overlap_size) + 1;
                            en_i = st_i + window_size - 1;
                            p_beta = bandpower(l_seg(st_i:en_i), obj.Fs, [13 35]);
                            
                            % Explicitly assign the surviving classes (-1 = Rest, 1 = Tremor)
                            if updated_labels(e) == 1
                                st_lbl = 'Tremor'; 
                            else
                                st_lbl = 'Rest'; 
                            end
                            
                            steps_idx_col = [steps_idx_col; i]; %#ok<AGROW>
                            beta_col      = [beta_col; p_beta]; %#ok<AGROW>
                            state_col     = [state_col; {st_lbl}]; %#ok<AGROW>
                          
                        end
                    else
                        state_pct_matrix(1, i) = 100;
                    end
                end

               
                % =========================================================================
                % NEW: DYNAMIC BETA NORMALIZATION
                % =========================================================================
                rest_idx = find(strcmp(state_col, 'Rest'));
                if ~isempty(rest_idx)
                    % Find the lowest step index that actually has 'Rest' data
                    first_rest_step = min(steps_idx_col(rest_idx)); 
                    
                    % Isolate the Beta powers for 'Rest' during that specific step
                    baseline_mask = strcmp(state_col, 'Rest') & (steps_idx_col == first_rest_step);
                    median_base = median(beta_col(baseline_mask), 'omitnan');
                else
                    % Failsafe: If the entire titration has zero rest (100% tremor everywhere)
                    median_base = median(beta_col, 'omitnan'); 
                end
                
                if ~isempty(median_base) && median_base > 0 && ~isnan(median_base)
                    beta_col = beta_col ./ median_base; 
                end
                % =========================================================================
            end
            
            % --- INJECT NAN PLACEHOLDERS FOR SPACING ---
            state_col_cat = categorical(state_col, {'Rest', 'Tremor'});
            for s_idx = 1:num_steps
                steps_idx_col = [steps_idx_col; s_idx; s_idx]; %#ok<AGROW>
                beta_col      = [beta_col; NaN; NaN]; %#ok<AGROW>
                state_col_cat = [state_col_cat; categorical({'Rest'}, {'Rest', 'Tremor'}); categorical({'Tremor'}, {'Rest', 'Tremor'})]; %#ok<AGROW>
            end
            beta_table = table(steps_idx_col, beta_col, state_col_cat, 'VariableNames', {'StepIdx', 'BetaPower', 'State'});
            
            % --- 5. ASSEMBLE OUTPUT STRUCTURE ---
            tremData = struct('hemi_name', hemi_name, ...
                              'steps', steps, ...
                              'step_labels', {step_strs}, ...
                              'updrs_scores', updrs_tremor, ...
                              'rms_accel', rms_accel, ...
                              'state_pct_matrix', state_pct_matrix, ...
                              'beta_table', beta_table, ...
                              'therapeutic_steps', therapeutic_steps);
        end
        
        function rigData = computeRigidityMetrics(obj, hemiIdx)
            ws = obj.ParentApp.WorkspaceData;
            if hemiIdx == 1
                hemi_name   = 'Left';
                task_id     = '3L';
                task_alt    = '3a';
                lfp_col     = 1;
                target_side_str = 'R'; 
                steps_field = 'Rigidity_Left';
            else
                hemi_name   = 'Right';
                task_id     = '3R';
                task_alt    = '3b';
                lfp_col     = 2;
                target_side_str = 'L';  
                steps_field = 'Rigidity_Right';
            end
            
            % --- 1. EXTRACT TITRATION STEPS ---
            steps = [];
            if isfield(ws, 'clinical_overview_updrs') && isfield(ws.clinical_overview_updrs, 'levels_storage_struct')
                ls = ws.clinical_overview_updrs.levels_storage_struct;
                if isfield(ls, steps_field), steps = ls.(steps_field)(:)'; end
            end
            if isempty(steps), steps = [0, 1.1, 2.2, 3.3, 4.4]; end
            num_steps = numel(steps);
            step_strs = cell(1, num_steps);
            for s = 1:num_steps, step_strs{s} = sprintf('%.1fmA', steps(s)); end
            
            % --- 2. EXTRACT CLINICAL SCORES & THERAPEUTIC WINDOW ---
            updrs_rigidity = zeros(1, num_steps);
            updrs_total  = zeros(1, num_steps);
            side_effects = false(1, num_steps);
            h_str = sprintf('Hemi_%d', hemiIdx);
            
            if isfield(ws, 'clinical_overview_updrs') && isfield(ws.clinical_overview_updrs, 'score_storage_struct')
                ss = ws.clinical_overview_updrs.score_storage_struct;
                t_score = zeros(1, num_steps); r_score = zeros(1, num_steps); b_score = zeros(1, num_steps);
                
                if isfield(ss, ['Tremor_' h_str]) 
                    if isfield(ss.(['Tremor_' h_str]), 'scores'), t_score = ss.(['Tremor_' h_str]).scores(:)'; end
                    if isfield(ss.(['Tremor_' h_str]), 'sidefx'), side_effects = side_effects | ss.(['Tremor_' h_str]).sidefx(:)'; end
                end
                if isfield(ss, ['Rigidity_' h_str]) 
                    if isfield(ss.(['Rigidity_' h_str]), 'scores'), r_score = ss.(['Rigidity_' h_str]).scores(:)'; updrs_rigidity = r_score; end
                    if isfield(ss.(['Rigidity_' h_str]), 'sidefx'), side_effects = side_effects | ss.(['Rigidity_' h_str]).sidefx(:)'; end
                end
                if isfield(ss, ['Bradykinesia_' h_str])
                    if isfield(ss.(['Bradykinesia_' h_str]), 'scores'), b_score = ss.(['Bradykinesia_' h_str]).scores(:)'; end
                    if isfield(ss.(['Bradykinesia_' h_str]), 'sidefx'), side_effects = side_effects | ss.(['Bradykinesia_' h_str]).sidefx(:)'; end
                end
                min_len = min([numel(t_score), numel(r_score), numel(b_score), num_steps]);
                updrs_total(1:min_len) = t_score(1:min_len) + r_score(1:min_len) + b_score(1:min_len);
            end
            
            base_total = updrs_total(1);
            lower_idx  = find(updrs_total < base_total & steps > 0, 1, 'first');
            first_sidefx_idx = find(side_effects, 1, 'first');
            if isempty(first_sidefx_idx), upper_idx = num_steps; else, upper_idx = first_sidefx_idx - 1; end
            if ~isempty(lower_idx) && lower_idx <= upper_idx, therapeutic_steps = steps(lower_idx:upper_idx); else, therapeutic_steps = []; end
            
            % --- 3. DYNAMIC KINEMATIC ROM & ncRMS EXTRACTION ---
            mean_rom_passive   = NaN(1, num_steps);
            mean_rom_activated = NaN(1, num_steps);
            crms_pass          = NaN(1, num_steps);
            crms_act           = NaN(1, num_steps);
            
            task_key = sprintf('Task_%s', task_id);
            if isfield(ws, 'validated_rigidity_peaks') && isfield(ws.validated_rigidity_peaks, task_key)
                val_data = ws.validated_rigidity_peaks.(task_key);
                for s = 1:num_steps
                    % Find the specific step data in the validated struct array
                    idx = find([val_data.level_mA] == steps(s), 1);
                    if ~isempty(idx)
                        mean_rom_passive(s)   = val_data(idx).mean_rom_passive;
                        mean_rom_activated(s) = val_data(idx).mean_rom_activated;
                        
                        % --- NEW: Extracting the ncRMS metrics for the PDF ---
                        if isfield(val_data(idx), 'crms_pass')
                            crms_pass(s) = val_data(idx).crms_pass;
                        end
                        if isfield(val_data(idx), 'crms_act')
                            crms_act(s) = val_data(idx).crms_act;
                        end
                    end
                end
            end
            
            % --- 4. PRE-ALIGNED DATA FETCH & EPOCHING (BETA BAND) ---
            a_data = ws.AlignedData;
            block_idx = find(string({a_data.task_id}) == task_id | string({a_data.task_id}) == task_alt, 1);
            
            steps_idx_col = []; beta_col = []; state_col = [];
            resting_beta_lowest = [];
            
            if ~isempty(block_idx)
                a_block = a_data(block_idx);
                master_time = a_block.CommonTime;
                if isfield(a_block.LFP, 'data_clean') && ~isempty(a_block.LFP.data_clean)
                    LFP_sig = a_block.LFP.data_clean(:, lfp_col);
                else
                    LFP_sig = a_block.LFP.data(:, lfp_col);
                end
                stim_vector = round(a_block.Stim.data(:, lfp_col), 1);
                
                % Setup kinematics for Rest thresholding
                wearable_signal = zeros(size(master_time));
                sensor_name = sprintf('HandSensor%s', target_side_str);
                has_kin = isfield(a_block, sensor_name) && ~isempty(a_block.(sensor_name));
                
                if has_kin
                    w_kin = a_block.(sensor_name);
                    [b_filt, a_filt] = butter(3, [2 8] / (obj.Fs / 2), "bandpass");
                    clean_ax = fillmissing(w_kin.ax, 'constant', 0);
                    clean_ay = fillmissing(w_kin.ay, 'constant', 0);
                    clean_az = fillmissing(w_kin.az, 'constant', 0);
                    filt_ax = filtfilt(b_filt, a_filt, clean_ax);
                    filt_ay = filtfilt(b_filt, a_filt, clean_ay);
                    filt_az = filtfilt(b_filt, a_filt, clean_az);
                    wearable_signal = sqrt(filt_ax.^2 + filt_ay.^2 + filt_az.^2);
                end
                
                bounds_var = sprintf('titration_bounds_%s_synchronized', task_id);
                if isfield(ws, bounds_var), bounds_table = ws.(bounds_var); else, bounds_table = []; end
                
                for i = 1:num_steps
                    step_val = round(steps(i), 1);
                    t_test_start = NaT; t_test_end = NaT; t_next_start = NaT;
                    
                    if ~isempty(bounds_table) && i <= size(bounds_table, 1) && bounds_table{i, 1} == step_val
                        t_test_start = bounds_table{i, 2}; t_test_end = bounds_table{i, 3};
                        if i < size(bounds_table, 1), t_next_start = bounds_table{i+1, 2}; end
                        
                        if ischar(t_test_start), t_test_start = datetime(t_test_start); end
                        if ischar(t_test_end), t_test_end = datetime(t_test_end); end
                        if ischar(t_next_start), t_next_start = datetime(t_next_start); end
                    else
                        matching_indices = find(stim_vector == step_val);
                        if numel(matching_indices) > (5 * obj.Fs)
                            split_pts = find(diff(matching_indices) > 1);
                            c_starts = [matching_indices(1); matching_indices(split_pts + 1)];
                            c_ends   = [matching_indices(split_pts); matching_indices(end)];
                            [~, best_chunk] = max(c_ends - c_starts);
                            t_test_start = master_time(c_starts(best_chunk));
                            t_test_end = master_time(c_ends(best_chunk));
                            
                            if i < num_steps
                                next_matching = find(stim_vector == round(steps(i+1), 1));
                                if ~isempty(next_matching)
                                    t_next_start = master_time(next_matching(1));
                                end
                            end
                        end
                    end
                    
                    if isnat(t_test_start) || isnat(t_test_end), continue; end
                    
                    ep_samples = 3 * obj.Fs;
                    step_samples = round(ep_samples * 0.5); 
                    
                    % Epoch TESTING Period
                    mask_test = (master_time >= t_test_start & master_time <= t_test_end);
                    l_seg_test  = LFP_sig(mask_test);
                    
                    num_test_eps  = floor((length(l_seg_test) - ep_samples) / step_samples) + 1;
                    if num_test_eps < 1 && length(l_seg_test) >= obj.Fs
                        p_beta = bandpower(l_seg_test, obj.Fs, [13 35]);
                        steps_idx_col = [steps_idx_col; i]; beta_col = [beta_col; p_beta]; state_col = [state_col; {'Testing'}]; %#ok<AGROW>
                    else
                        for e = 1:num_test_eps
                            st_i = (e-1)*step_samples + 1; en_i = st_i + ep_samples - 1;
                            p_beta = bandpower(l_seg_test(st_i:en_i), obj.Fs, [13 35]);
                            steps_idx_col = [steps_idx_col; i]; beta_col = [beta_col; p_beta]; state_col = [state_col; {'Testing'}]; %#ok<AGROW>
                        end
                    end
                    
                    % Epoch REST Gap Period
                    t_rest_start = t_test_end;
                    if isnat(t_next_start), t_rest_end = t_rest_start + seconds(60); else, t_rest_end = t_next_start; end
                    
                    mask_rest = (master_time > t_rest_start & master_time < t_rest_end);
                    l_seg_rest = LFP_sig(mask_rest);
                    w_seg_rest = wearable_signal(mask_rest);
                    
                    num_rest_eps  = floor((length(l_seg_rest) - ep_samples) / step_samples) + 1;
                    for e = 1:num_rest_eps
                        st_i = (e-1)*step_samples + 1; en_i = st_i + ep_samples - 1;
                        is_rest = false;
                        if has_kin && max(w_seg_rest(st_i:en_i)) < 0.25
                            is_rest = true; 
                        end
                        if is_rest
                            p_beta = bandpower(l_seg_rest(st_i:en_i), obj.Fs, [13 35]);
                            steps_idx_col = [steps_idx_col; i]; beta_col = [beta_col; p_beta]; state_col = [state_col; {'Rest'}]; %#ok<AGROW>
                            if i == 1, resting_beta_lowest = [resting_beta_lowest; p_beta]; end %#ok<AGROW>
                        end
                    end
                end
                
                % Normalize Beta Powers
                median_base = median(resting_beta_lowest, 'omitnan');
                if isempty(median_base) || median_base == 0 || isnan(median_base), median_base = median(beta_col, 'omitnan'); end
                if ~isempty(median_base) && median_base > 0, beta_col = beta_col ./ median_base; end
            end
            
            % Generate Struct Output
            state_col_cat = categorical(state_col, {'Rest', 'Testing'});
            for s_idx = 1:num_steps
                steps_idx_col = [steps_idx_col; s_idx; s_idx]; %#ok<AGROW>
                beta_col      = [beta_col; NaN; NaN]; %#ok<AGROW>
                state_col_cat = [state_col_cat; categorical({'Rest'}, {'Rest', 'Testing'}); categorical({'Testing'}, {'Rest', 'Testing'})]; %#ok<AGROW>
            end
            beta_table = table(steps_idx_col, beta_col, state_col_cat, 'VariableNames', {'StepIdx', 'BetaPower', 'State'});
            
            rigData = struct('hemi_name', hemi_name, ...
                             'steps', steps, ...
                             'step_labels', {step_strs}, ...
                             'updrs_scores', updrs_rigidity, ...
                             'mean_rom_passive', mean_rom_passive, ...
                             'mean_rom_activated', mean_rom_activated, ...
                             'crms_pass', crms_pass, ...      % <--- OFFICIALLY ADDED
                             'crms_act', crms_act, ...        % <--- OFFICIALLY ADDED
                             'beta_table', beta_table, ...
                             'therapeutic_steps', therapeutic_steps);
        end
        
        function bradyData = computeBradykinesiaMetrics(obj, hemiIdx)
            ws = obj.ParentApp.WorkspaceData;
            if hemiIdx == 1
                hemi_name   = 'Left';
                task_id     = '4L';
                task_alt    = '4a';
                lfp_col     = 1;
                target_side_str = 'R'; 
                steps_field = 'Bradykinesia_Left';
            else
                hemi_name   = 'Right';
                task_id     = '4R';
                task_alt    = '4b';
                lfp_col     = 2;
                target_side_str = 'L';  
                steps_field = 'Bradykinesia_Right';
            end
            
            % --- 1. EXTRACT TITRATION STEPS ---
            steps = [];
            if isfield(ws, 'clinical_overview_updrs') && isfield(ws.clinical_overview_updrs, 'levels_storage_struct')
                ls = ws.clinical_overview_updrs.levels_storage_struct;
                if isfield(ls, steps_field), steps = ls.(steps_field)(:)'; end
            end
            if isempty(steps), steps = [0, 1.1, 2.2, 3.3, 4.4]; end
            num_steps = numel(steps);
            step_strs = cell(1, num_steps);
            for s = 1:num_steps, step_strs{s} = sprintf('%.1fmA', steps(s)); end
            
            % --- 2. EXTRACT CLINICAL SCORES & THERAPEUTIC WINDOW ---
            updrs_brady = zeros(1, num_steps);
            updrs_total = zeros(1, num_steps);
            side_effects = false(1, num_steps);
            h_str = sprintf('Hemi_%d', hemiIdx);
            
            % =========================================================================
            % NEW DYNAMIC FIX: Map final_verified_blocks dynamically using AlignedData task_id
            % =========================================================================
            use_tremor = true; use_rigidity = true; use_brady = true;
            if isfield(ws, 'AlignedData') && isfield(ws, 'final_verified_blocks')
                a_data = ws.AlignedData;
                fvb = ws.final_verified_blocks;
                
                if isfield(a_data, 'task_id')
                    task_ids = string({a_data.task_id});
                    
                    if hemiIdx == 1
                        idx_t = find(task_ids == '2L', 1);
                        idx_r = find(task_ids == '3L', 1);
                        idx_b = find(task_ids == '4L' | task_ids == '4a', 1);
                    else
                        idx_t = find(task_ids == '2R', 1);
                        idx_r = find(task_ids == '3R', 1);
                        idx_b = find(task_ids == '4R' | task_ids == '4b', 1);
                    end
                    
                    if ~isempty(idx_t) && length(fvb) >= idx_t, use_tremor = fvb(idx_t); end
                    if ~isempty(idx_r) && length(fvb) >= idx_r, use_rigidity = fvb(idx_r); end
                    if ~isempty(idx_b) && length(fvb) >= idx_b, use_brady = fvb(idx_b); end
                end
            end
            % =========================================================================
            
            if isfield(ws, 'clinical_overview_updrs') && isfield(ws.clinical_overview_updrs, 'score_storage_struct')
                ss = ws.clinical_overview_updrs.score_storage_struct;
                
                % Initialize perfectly sized empty arrays
                t_score = zeros(1, num_steps); 
                r_score = zeros(1, num_steps); 
                b_score = zeros(1, num_steps);
                
                % Safely extract and map scores ONLY if verified, forcing them to 1xNumSteps
                if use_tremor && isfield(ss, ['Tremor_' h_str]) 
                    if isfield(ss.(['Tremor_' h_str]), 'scores')
                        tmp = ss.(['Tremor_' h_str]).scores(:)';
                        v_len = min(length(tmp), num_steps);
                        t_score(1:v_len) = tmp(1:v_len);
                    end
                    if isfield(ss.(['Tremor_' h_str]), 'sidefx')
                        tmp_fx = ss.(['Tremor_' h_str]).sidefx(:)';
                        v_len = min(length(tmp_fx), num_steps);
                        side_effects(1:v_len) = side_effects(1:v_len) | tmp_fx(1:v_len);
                    end
                end
                
                if use_rigidity && isfield(ss, ['Rigidity_' h_str]) 
                    if isfield(ss.(['Rigidity_' h_str]), 'scores')
                        tmp = ss.(['Rigidity_' h_str]).scores(:)';
                        v_len = min(length(tmp), num_steps);
                        r_score(1:v_len) = tmp(1:v_len);
                    end
                    if isfield(ss.(['Rigidity_' h_str]), 'sidefx')
                        tmp_fx = ss.(['Rigidity_' h_str]).sidefx(:)';
                        v_len = min(length(tmp_fx), num_steps);
                        side_effects(1:v_len) = side_effects(1:v_len) | tmp_fx(1:v_len);
                    end
                end
                
                if use_brady && isfield(ss, ['Bradykinesia_' h_str])
                    if isfield(ss.(['Bradykinesia_' h_str]), 'scores')
                        tmp = ss.(['Bradykinesia_' h_str]).scores(:)'; 
                        v_len = min(length(tmp), num_steps);
                        b_score(1:v_len) = tmp(1:v_len); 
                        updrs_brady(1:v_len) = tmp(1:v_len); 
                    end
                    if isfield(ss.(['Bradykinesia_' h_str]), 'sidefx')
                        tmp_fx = ss.(['Bradykinesia_' h_str]).sidefx(:)'; 
                        v_len = min(length(tmp_fx), num_steps);
                        side_effects(1:v_len) = side_effects(1:v_len) | tmp_fx(1:v_len);
                    end
                end
                
                % Because all arrays are perfectly padded to 1xnum_steps, simple addition is now 100% safe
                updrs_total = t_score + r_score + b_score;
            end
            
            base_total = updrs_total(1);
            lower_idx  = find(updrs_total < base_total & steps > 0, 1, 'first');
            first_sidefx_idx = find(side_effects, 1, 'first');
            if isempty(first_sidefx_idx), upper_idx = num_steps; else, upper_idx = first_sidefx_idx - 1; end
            if ~isempty(lower_idx) && lower_idx <= upper_idx, therapeutic_steps = steps(lower_idx:upper_idx); else, therapeutic_steps = []; end
            
            % --- 3. FETCH VALIDATED METRICS DIRECTLY FROM KINEMATIC SELECTOR CACHE ---
            mean_rom   = zeros(1, num_steps);
            mean_ratio = zeros(1, num_steps);
            
            task_key1 = sprintf('Task_%s', task_id);
            task_key2 = sprintf('Task_%s', task_alt);
            
            cached_struct = [];
            if isfield(ws, 'validated_brady_peaks')
                if isfield(ws.validated_brady_peaks, task_key1)
                    cached_struct = ws.validated_brady_peaks.(task_key1);
                elseif isfield(ws.validated_brady_peaks, task_key2)
                    cached_struct = ws.validated_brady_peaks.(task_key2);
                end
            end
            
            if ~isempty(cached_struct)
                for i = 1:num_steps
                    target_lvl = round(steps(i), 1);
                    for k = 1:numel(cached_struct)
                        if round(cached_struct(k).level_mA, 1) == target_lvl
                            if isfield(cached_struct(k), 'mean_rom')
                                mean_rom(i) = cached_struct(k).mean_rom;
                            end
                            if isfield(cached_struct(k), 'mean_ratio') && ~isnan(cached_struct(k).mean_ratio)
                                mean_ratio(i) = cached_struct(k).mean_ratio;
                            end
                            break;
                        end
                    end
                end
            end
            
            % --- 4. PRE-ALIGNED DATA FETCH & EPOCHING (FOR BETA POWER) ---
            a_data = ws.AlignedData;
            block_idx = find(string({a_data.task_id}) == task_id | string({a_data.task_id}) == task_alt, 1);
            
            steps_idx_col = []; beta_col = []; state_col = [];
            resting_beta_lowest = [];
            
            if ~isempty(block_idx)
                a_block = a_data(block_idx);
                
                master_time = a_block.CommonTime;
                if isfield(a_block.LFP, 'data_clean') && ~isempty(a_block.LFP.data_clean)
                    LFP_sig = a_block.LFP.data_clean(:, lfp_col);
                else
                    LFP_sig = a_block.LFP.data(:, lfp_col);
                end
                stim_vector = round(a_block.Stim.data(:, lfp_col), 1);
                
                % Setup kinematics
                wearable_signal = zeros(size(master_time));
                sensor_name = sprintf('FingerSensor%s', target_side_str);
                has_kin = isfield(a_block, sensor_name) && ~isempty(a_block.(sensor_name));
                
                if has_kin
                    w_kin = a_block.(sensor_name);
                    [b_filt, a_filt] = butter(3, [1 12] / (obj.Fs / 2), "bandpass");
                    
                    clean_ax = fillmissing(w_kin.ax, 'constant', 0);
                    clean_ay = fillmissing(w_kin.ay, 'constant', 0);
                    clean_az = fillmissing(w_kin.az, 'constant', 0);
                    
                    filt_ax = filtfilt(b_filt, a_filt, clean_ax);
                    filt_ay = filtfilt(b_filt, a_filt, clean_ay);
                    filt_az = filtfilt(b_filt, a_filt, clean_az);
                    wearable_signal = sqrt(filt_ax.^2 + filt_ay.^2 + filt_az.^2);
                end
                
                bounds_var = sprintf('titration_bounds_%s_synchronized', task_id);
                if isfield(ws, bounds_var), bounds_table = ws.(bounds_var); else, bounds_table = []; end
                
                for i = 1:num_steps
                    step_val = round(steps(i), 1);
                    t_test_start = NaT; t_test_end = NaT; t_next_start = NaT;
                    
                    if ~isempty(bounds_table) && i <= size(bounds_table, 1) && bounds_table{i, 1} == step_val
                        t_test_start = bounds_table{i, 2}; t_test_end = bounds_table{i, 3};
                        if i < size(bounds_table, 1), t_next_start = bounds_table{i+1, 2}; end
                        
                        if ischar(t_test_start) || isstring(t_test_start), t_test_start = datetime(t_test_start); end
                        if ischar(t_test_end) || isstring(t_test_end), t_test_end = datetime(t_test_end); end
                        if ischar(t_next_start) || isstring(t_next_start), t_next_start = datetime(t_next_start); end
                    else
                        matching_indices = find(stim_vector == step_val);
                        if numel(matching_indices) > (5 * obj.Fs)
                            split_pts = find(diff(matching_indices) > 1);
                            c_starts = [matching_indices(1); matching_indices(split_pts + 1)];
                            c_ends   = [matching_indices(split_pts); matching_indices(end)];
                            [~, best_chunk] = max(c_ends - c_starts);
                            t_test_start = master_time(c_starts(best_chunk));
                            t_test_end = master_time(c_ends(best_chunk));
                            
                            if i < num_steps
                                next_matching = find(stim_vector == round(steps(i+1), 1));
                                if ~isempty(next_matching), t_next_start = master_time(next_matching(1)); end
                            end
                        end
                    end
                    
                    if isnat(t_test_start) || isnat(t_test_end), continue; end
                    
                    ep_samples = 3 * obj.Fs;
                    step_samples = round(ep_samples * 0.5); 
                    
                    % Epoch TESTING Period
                    mask_test = (master_time >= t_test_start & master_time <= t_test_end);
                    l_seg_test  = LFP_sig(mask_test);
                    
                    num_test_eps  = floor((length(l_seg_test) - ep_samples) / step_samples) + 1;
                    if num_test_eps < 1 && length(l_seg_test) >= obj.Fs
                        p_beta = bandpower(l_seg_test, obj.Fs, [13 35]);
                        steps_idx_col = [steps_idx_col; i]; beta_col = [beta_col; p_beta]; state_col = [state_col; {'Testing'}]; %#ok<AGROW>
                    else
                        for e = 1:num_test_eps
                            st_i = (e-1)*step_samples + 1; en_i = st_i + ep_samples - 1;
                            p_beta = bandpower(l_seg_test(st_i:en_i), obj.Fs, [13 35]);
                            steps_idx_col = [steps_idx_col; i]; beta_col = [beta_col; p_beta]; state_col = [state_col; {'Testing'}]; %#ok<AGROW>
                        end
                    end
                    
                    % Epoch REST Gap Period
                    t_rest_start = t_test_end;
                    if isnat(t_next_start), t_rest_end = t_rest_start + seconds(60); else, t_rest_end = t_next_start; end
                    
                    mask_rest = (master_time > t_rest_start & master_time < t_rest_end);
                    l_seg_rest = LFP_sig(mask_rest);
                    w_seg_rest = wearable_signal(mask_rest);
                    
                    num_rest_eps  = floor((length(l_seg_rest) - ep_samples) / step_samples) + 1;
                    for e = 1:num_rest_eps
                        st_i = (e-1)*step_samples + 1; en_i = st_i + ep_samples - 1;
                        
                        is_rest = false;
                        if has_kin
                            if max(w_seg_rest(st_i:en_i)) < 0.20
                                is_rest = true; 
                            end
                        end
                        
                        if is_rest
                            p_beta = bandpower(l_seg_rest(st_i:en_i), obj.Fs, [13 35]);
                            steps_idx_col = [steps_idx_col; i]; beta_col = [beta_col; p_beta]; state_col = [state_col; {'Rest'}]; %#ok<AGROW>
                            if i == 1, resting_beta_lowest = [resting_beta_lowest; p_beta]; end %#ok<AGROW>
                        end
                    end
                end
                
                median_base = median(resting_beta_lowest, 'omitnan');
                if isempty(median_base) || median_base == 0 || isnan(median_base), median_base = median(beta_col, 'omitnan'); end
                if ~isempty(median_base) && median_base > 0, beta_col = beta_col ./ median_base; end
            end
            
            % Generate Struct Output
            state_col_cat = categorical(state_col, {'Rest', 'Testing'});
            for s_idx = 1:num_steps
                steps_idx_col = [steps_idx_col; s_idx; s_idx]; %#ok<AGROW>
                beta_col      = [beta_col; NaN; NaN]; %#ok<AGROW>
                state_col_cat = [state_col_cat; categorical({'Rest'}, {'Rest', 'Testing'}); categorical({'Testing'}, {'Rest', 'Testing'})]; %#ok<AGROW>
            end
            beta_table = table(steps_idx_col, beta_col, state_col_cat, 'VariableNames', {'StepIdx', 'BetaPower', 'State'});
            
            bradyData = struct('hemi_name', hemi_name, ...
                             'steps', steps, ...
                             'step_labels', {step_strs}, ...
                             'updrs_scores', updrs_brady, ...
                             'mean_rom', mean_rom, ...
                             'mean_ratio', mean_ratio, ...
                             'beta_table', beta_table, ...
                             'therapeutic_steps', therapeutic_steps);
        end
        
        function [left_info, right_info] = parseHardwareParams(obj)
            left_info  = struct('proto_rings', {{'', {'','',''}, {'','',''}, ''}}, ...
                                'proto_rate', '--', 'proto_pw', '--', 'proto_amp', '--', ...
                                'post_rings',  {{'', {'','',''}, {'','',''}, ''}}, ...
                                'post_rate', '--', 'post_pw', '--', 'post_amp', '--');
                            
            right_info = struct('proto_rings', {{'', {'','',''}, {'','',''}, ''}}, ...
                                'proto_rate', '--', 'proto_pw', '--', 'proto_amp', '--', ...
                                'post_rings',  {{'', {'','',''}, {'','',''}, ''}}, ...
                                'post_rate', '--', 'post_pw', '--', 'post_amp', '--');
                                
            try
                % --- IN-CLINIC PARAMS (BrainSenseLfpObj) ---
                if isfield(obj.ParentApp.WorkspaceData, 'BrainSenseLfpObj')
                   bsLfp = obj.ParentApp.WorkspaceData.BrainSenseLfpObj;
                end
                
                if exist('bsLfp', 'var') && ~isempty(bsLfp)
                    if iscell(bsLfp), lastRec = bsLfp{end}; else, lastRec = bsLfp(end); end
                    if isfield(lastRec, 'TherapySnapshot')
                        ts = lastRec.TherapySnapshot;
                        
                        if isfield(ts, 'Left') && ~isempty(ts.Left)
                            [rings, rate, pw, amp] = obj.unpackTherapySnapshot(ts.Left);
                            left_info.proto_rings = rings;
                            if ~isempty(rate), left_info.proto_rate = sprintf('%g', rate); end
                            if ~isempty(pw),   left_info.proto_pw   = sprintf('%g', pw); end
                            if ~isempty(amp),  left_info.proto_amp  = sprintf('%.1f', amp); end
                        end
                        
                        if isfield(ts, 'Right') && ~isempty(ts.Right)
                            [rings, rate, pw, amp] = obj.unpackTherapySnapshot(ts.Right);
                            right_info.proto_rings = rings;
                            if ~isempty(rate), right_info.proto_rate = sprintf('%g', rate); end
                            if ~isempty(pw),   right_info.proto_pw   = sprintf('%g', pw); end
                            if ~isempty(amp),  right_info.proto_amp  = sprintf('%.1f', amp); end
                        end
                    end
                    
                    % CLINICAL OVERRIDE: Fetch actual delivered mA from Protocol Section 5
                    if isfield(obj.ParentApp.WorkspaceData, 'AlignedData')
                        ad = obj.ParentApp.WorkspaceData.AlignedData;
                        idx_5 = find(string({ad.task_id}) == "5", 1);
                        
                        if ~isempty(idx_5) && numel(bsLfp) >= idx_5
                            if iscell(bsLfp), rec5 = bsLfp{idx_5}; else, rec5 = bsLfp(idx_5); end
                            if isfield(rec5, 'LfpData') && ~isempty(rec5.LfpData)
                                lfp_1 = rec5.LfpData(1);
                                if isfield(lfp_1, 'Left') && isfield(lfp_1.Left, 'mA')
                                    left_info.proto_amp = sprintf('%.1f', lfp_1.Left.mA);
                                end
                                if isfield(lfp_1, 'Right') && isfield(lfp_1.Right, 'mA')
                                    right_info.proto_amp = sprintf('%.1f', lfp_1.Right.mA);
                                end
                            end
                        end
                    end
                end
                
                % --- POST-CLINIC PARAMS (GroupsObj) ---
                if isfield(obj.ParentApp.WorkspaceData, 'GroupsObj')
                   groups_data = obj.ParentApp.WorkspaceData.GroupsObj;
                end
                
                if exist('groups_data', 'var') && ~isempty(groups_data)
                    act_idx = 1;
                    for g = 1:numel(groups_data)
                        g_item = groups_data(g);
                        if iscell(g_item), g_item = g_item{1}; end
                        
                        if (isfield(g_item, 'active') && (g_item.active == 1 || isequal(g_item.active, true))) || ...
                           (isfield(g_item, 'ActiveGroup') && (g_item.ActiveGroup == 1 || isequal(g_item.ActiveGroup, true)))
                            act_idx = g;
                            break;
                        end
                    end
                    
                    active_group = groups_data(act_idx);
                    if iscell(active_group), active_group = active_group{1}; end
                    
                    l_post_state = obj.getElectrodeStateFromGroup(active_group, 'left');
                    r_post_state = obj.getElectrodeStateFromGroup(active_group, 'right');
                    
                    calc_l_amp = 0; calc_r_amp = 0;
                    if ~isempty(l_post_state)
                        [left_info.post_rings, calc_l_amp]  = obj.unpackElectrodeState(l_post_state); 
                    end
                    if ~isempty(r_post_state)
                        [right_info.post_rings, calc_r_amp] = obj.unpackElectrodeState(r_post_state); 
                    end
                    
                    if isfield(active_group, 'stimulation') && isstruct(active_group.stimulation) && ...
                       isfield(active_group.stimulation, 'hemispheres')
                        hemis = active_group.stimulation.hemispheres;
                        for h = 1:numel(hemis)
                            if iscell(hemis), h_item = hemis{h}; else, h_item = hemis(h); end
                            loc_str = upper(string(h_item.location));
                            
                            if contains(loc_str, 'LEFT')
                                if isfield(h_item, 'frequency'),   left_info.post_rate = sprintf('%g', h_item.frequency); end
                                if isfield(h_item, 'pulse_width'), left_info.post_pw   = sprintf('%g', h_item.pulse_width); end
                                
                                if isfield(h_item, 'amplitude') && ~isempty(h_item.amplitude) && h_item.amplitude > 0
                                    left_info.post_amp = sprintf('%.1f', h_item.amplitude);
                                elseif calc_l_amp > 0
                                    left_info.post_amp = sprintf('%.1f', calc_l_amp);
                                end
                                
                            elseif contains(loc_str, 'RIGHT')
                                if isfield(h_item, 'frequency'),   right_info.post_rate = sprintf('%g', h_item.frequency); end
                                if isfield(h_item, 'pulse_width'), right_info.post_pw   = sprintf('%g', h_item.pulse_width); end
                                
                                if isfield(h_item, 'amplitude') && ~isempty(h_item.amplitude) && h_item.amplitude > 0
                                    right_info.post_amp = sprintf('%.1f', h_item.amplitude);
                                elseif calc_r_amp > 0
                                    right_info.post_amp = sprintf('%.1f', calc_r_amp);
                                end
                            end
                        end
                    end
                end
                
            catch ME
                warning('DBSgram:HeaderParsingWarning', 'Error unpacking hardware parameters: %s', ME.message);
            end
        end
        
        function [rings, rate, pw, total_amp] = unpackTherapySnapshot(obj, hemi_snap)
            rings = {'', {'','',''}, {'','',''}, ''};
            rate = []; pw = []; total_amp = [];
            
            if isempty(hemi_snap), return; end
            if isfield(hemi_snap, 'RateInHertz'), rate = hemi_snap.RateInHertz; end
            if isfield(hemi_snap, 'PulseWidthInMicroSecond'), pw = hemi_snap.PulseWidthInMicroSecond; end
            
            if isfield(hemi_snap, 'ElectrodeState')
                e_state = hemi_snap.ElectrodeState;
                
                % Extract rings and the true floored fractional amplitude
                [rings, calc_amp] = obj.unpackElectrodeState(e_state);
                
                if calc_amp > 0
                    total_amp = calc_amp;
                end
            end
            
            % Safe Fallback if calculation yields 0
            if isempty(total_amp) || total_amp == 0
                if isfield(hemi_snap, 'SuspendAmplitudeInMilliAmps') && ~isempty(hemi_snap.SuspendAmplitudeInMilliAmps)
                    total_amp = hemi_snap.SuspendAmplitudeInMilliAmps;
                elseif isfield(hemi_snap, 'UpperLimitInMilliAmps') && ~isempty(hemi_snap.UpperLimitInMilliAmps)
                    total_amp = hemi_snap.UpperLimitInMilliAmps;
                elseif isfield(hemi_snap, 'LowerLimitInMilliAmps') && ~isempty(hemi_snap.LowerLimitInMilliAmps)
                    total_amp = hemi_snap.LowerLimitInMilliAmps;
                end
                
                if ~isempty(total_amp)
                    total_amp = floor(total_amp * 10) / 10;
                end
            end
        end
        
        function elec_state = getElectrodeStateFromGroup(~, group_item, hemi_side)
            elec_state = [];
            if isempty(group_item) || ~isstruct(group_item), return; end
            
            target = [];
            if isfield(group_item, 'ProgrammSettings'),     target = group_item.ProgrammSettings;
            elseif isfield(group_item, 'ProgramSettings'),  target = group_item.ProgramSettings;
            elseif isfield(group_item, 'programm_settings'), target = group_item.programm_settings;
            elseif isfield(group_item, 'program_settings'),  target = group_item.program_settings;
            elseif isfield(group_item, 'stimulation'),      target = group_item.stimulation;
            else, target = group_item;
            end
            
            if isempty(target) || ~isstruct(target), return; end
            
            is_left = contains(lower(hemi_side), 'left');
            if is_left, search_keys = ["LEFT", "LLE"]; else, search_keys = ["RIGHT", "RLE"]; end
            
            hemi_struct = [];
            
            % ROUTE 1: Standard Medtronic Format (Sensing OFF)
            fn = fieldnames(target);
            for f = 1:numel(fn)
                fn_upper = upper(string(fn{f}));
                for k = search_keys
                    if contains(fn_upper, k)
                        hemi_struct = target.(fn{f});
                        break;
                    end
                end
                if ~isempty(hemi_struct), break; end
            end
            
            % ROUTE 2: Buried Medtronic Format (Sensing ON)
            if isempty(hemi_struct) && isfield(target, 'SensingChannel')
                sc = target.SensingChannel;
                if iscell(sc), num_items = numel(sc); else, num_items = length(sc); end
                for i = 1:num_items
                    if iscell(sc), item = sc{i}; else, item = sc(i); end
                    loc_str = "";
                    if isfield(item, 'HemisphereLocation'), loc_str = string(item.HemisphereLocation);
                    elseif isfield(item, 'ProgramId'), loc_str = string(item.ProgramId); end
                    
                    loc_upper = upper(loc_str);
                    for k = search_keys
                        if contains(loc_upper, k)
                            hemi_struct = item;
                            break;
                        end
                    end
                    if ~isempty(hemi_struct), break; end
                end
            end
            
            if isempty(hemi_struct), return; end
            
            % Drill down to the actual ElectrodeState array
            if isstruct(hemi_struct) && isfield(hemi_struct, 'Programs')
                hemi_struct = hemi_struct.Programs;
            elseif isstruct(hemi_struct) && isfield(hemi_struct, 'programs')
                hemi_struct = hemi_struct.programs;
            end
            
            if iscell(hemi_struct) && ~isempty(hemi_struct)
                hemi_struct = hemi_struct{1};
            end
            
            if isstruct(hemi_struct)
                if isfield(hemi_struct, 'ElectrodeState')
                    elec_state = hemi_struct.ElectrodeState;
                elseif isfield(hemi_struct, 'electrode_state')
                    elec_state = hemi_struct.electrode_state;
                else
                    elec_state = hemi_struct;
                end
            elseif iscell(hemi_struct)
                elec_state = hemi_struct;
            end
        end

        function [stim_profile, total_calc_amp] = unpackElectrodeState(~, state_data)
            stim_profile = {'', {'','',''}, {'','',''}, ''};
            aux_stim_1 = {'','',''};
            aux_stim_2 = {'','',''};
            total_calc_amp = 0; % Track true calculated amplitude
            
            if isempty(state_data), return; end
            if iscell(state_data), num_items = numel(state_data); else, num_items = length(state_data); end
            
            for i = 1:num_items
                if iscell(state_data), item = state_data{i}; else, item = state_data(i); end
                if iscell(item), item = item{1}; end
                
                elec_field = '';
                if isfield(item, 'Electrode'),      elec_field = char(item.Electrode);
                elseif isfield(item, 'electrode'),  elec_field = char(item.electrode);
                end
                
                if isempty(elec_field) || contains(elec_field, 'Case', 'IgnoreCase', true), continue; end
                
                amp_num = [];
                if isfield(item, 'ElectrodeAmplitudeInMilliAmps'),         amp_num = item.ElectrodeAmplitudeInMilliAmps;
                elseif isfield(item, 'electrode_amplitude_in_milli_amps'), amp_num = item.electrode_amplitude_in_milli_amps;
                elseif isfield(item, 'amplitude_ma'),                      amp_num = item.amplitude_ma;
                end
                
                frac_num = 0;
                if isfield(item, 'ElectrodeFractionOf64'),         frac_num = item.ElectrodeFractionOf64;
                elseif isfield(item, 'electrode_fraction_of_64'),  frac_num = item.electrode_fraction_of_64;
                elseif isfield(item, 'fraction_of_64'),            frac_num = item.fraction_of_64;
                end
                if ischar(frac_num) || isstring(frac_num), frac_num = str2double(frac_num); end
                frac_val = abs(frac_num);
                
                if isempty(amp_num) || amp_num == 0
                    amp_val = ''; 
                else
                    amp_val = sprintf('%g', round(amp_num, 2)); 
                    
                    % Calculate exact total via Fractional Math floored to the first decimal
                    if frac_val > 0 && total_calc_amp == 0
                        total_calc_amp = floor(amp_num * (64 / frac_val) * 10) / 10;
                    end
                end
                
                num_elec = str2double(regexp(elec_field, '\d+', 'match', 'once'));
                seg_match = regexp(elec_field, '[a-cA-C]$', 'match', 'once');
                
                if isempty(seg_match)
                    seg_char = ''; 
                elseif iscell(seg_match)
                    seg_char = lower(seg_match{1}); 
                else
                    seg_char = lower(seg_match(1)); 
                end
                
                if isnan(num_elec), continue; end
                
                if num_elec == 0
                    stim_profile{1} = amp_val;
                elseif num_elec == 3
                    stim_profile{4} = amp_val;
                elseif num_elec == 1
                    switch seg_char
                        case 'b', aux_stim_1{1} = amp_val;
                        case 'a', aux_stim_1{2} = amp_val;
                        case 'c', aux_stim_1{3} = amp_val;
                        otherwise, aux_stim_1{2} = amp_val;
                    end
                elseif num_elec == 2
                    switch seg_char
                        case 'b', aux_stim_2{1} = amp_val;
                        case 'a', aux_stim_2{2} = amp_val;
                        case 'c', aux_stim_2{3} = amp_val;
                        otherwise, aux_stim_2{2} = amp_val;
                    end
                end
            end
            
            stim_profile{2} = aux_stim_1;
            stim_profile{3} = aux_stim_2;
            
            for c = 1:4
                if isempty(stim_profile{c})
                    stim_profile{c} = '';
                elseif iscell(stim_profile{c})
                    for sub = 1:3
                        if isempty(stim_profile{c}{sub}), stim_profile{c}{sub} = ''; end
                    end
                end
            end
        end
    
        function plotSafe3DLine(~, axTarget, xData, yData, lStyle, clr, lWidth, mSize, fColor, zLevel)
            % Slices arrays to remove NaNs and prevent 3D vector export crashes
            is_val = ~isnan(yData) & ~isnan(xData); 
            d_val = diff([0, is_val, 0]);
            st = find(d_val == 1);
            en = find(d_val == -1) - 1;
            
            for k = 1:length(st)
                idx = st(k):en(k);
                p_tmp = plot(axTarget, xData(idx), yData(idx), lStyle, 'Color', clr, ...
                    'LineWidth', lWidth, 'MarkerSize', mSize, ...
                    'MarkerFaceColor', fColor, 'HandleVisibility', 'off');
                
                % Safely apply Z-depth to pure geometric numbers
                p_tmp.ZData = zLevel * ones(size(p_tmp.XData));
            end
        end
    end
end