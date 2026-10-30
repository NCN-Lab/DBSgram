classdef DBSgram_EcgCleanUI < handle
    % DBSgram_EcgCleanUI - On-Demand SVD ECG Space Filter Workstation
    
    properties
        ParentApp       DBSgram_MainUI
        UIFigure        matlab.ui.Figure
        MainGrid        matlab.ui.container.GridLayout
        ControlPanel    matlab.ui.container.Panel
        PlotPanel       matlab.ui.container.Panel
        
        % Dynamic Layout Inputs
        DropdownRec     matlab.ui.control.DropDown
        DropdownHemi    matlab.ui.control.DropDown
        DropdownSelComp matlab.ui.control.DropDown
        BtnAddComp      matlab.ui.control.Button
        BtnResetComp    matlab.ui.control.Button
        LblRejectedList matlab.ui.control.Label
        BtnCommit       matlab.ui.control.Button
        TxtLog          matlab.ui.control.TextArea
        
        % Multi-Axes Continuous Display Canvas
        MainTileGrid    matlab.graphics.layout.TiledChartLayout
        AxSignal        matlab.graphics.axis.Axes
        AxSpec          matlab.graphics.axis.Axes
    end
    
    properties (Access = private)
        Fs                  double = 250 
        DiagFigure          matlab.ui.Figure {mustBeScalarOrEmpty}
        
        % Mapping registries to decouple UI selections from raw data arrays
        ValidRunIndices     double       
        ValidRunLabels      string       
        
        % Multi-session Processing Structures
        RawDataCache        cell  
        CleanDataCache      cell  
        
        % Track changes per [BlockIndex, HemisphereIndex] to update the main log
        TrackingMap         struct
        ActiveRejectedComps double = [] 
        
        % High-Fidelity SVD Synchronized Component Cache
        Cached_U            double
        Cached_S            double
        Cached_V            double
        Cached_locs         double
        
        % Transient Signal Coordinates
        CurrentTimeVector   double
        CurrentRawSignal    double
        CurrentCleanSignal  double
        CurrentTemplate     double
        CurrentSvdVariance  double
    end
    
    methods
        function obj = DBSgram_EcgCleanUI(parentHandle)
            obj.ParentApp = parentHandle;
            
            % % --- DYNAMIC SAMPLING FREQUENCY CHECK ---
            % if isfield(obj.ParentApp.WorkspaceData.streaming_obj.streaming_parameters.time_domain, 'fs')
            %     obj.Fs = double(obj.ParentApp.WorkspaceData.streaming_obj.streaming_parameters.time_domain.fs);
            % elseif isfield(obj.ParentApp.WorkspaceData.streaming_obj.streaming_parameters.time_domain, 'sample_rate')
            %     obj.Fs = double(obj.ParentApp.WorkspaceData.streaming_obj.streaming_parameters.time_domain.sample_rate);
            % else
            %     obj.Fs = 250;
            % end
            
            % Ensure AlignedData exists before proceeding
            if ~isfield(obj.ParentApp.WorkspaceData, 'AlignedData') || isempty(obj.ParentApp.WorkspaceData.AlignedData)
                uialert(obj.ParentApp.UIFigure, 'AlignedData struct not found. Please complete the Alignment & Audit UIs first.', 'Data Error');
                return;
            end
            
            mapAlignedDataToProtocols(obj);
            
            % Extract telemetry cache frames directly from AlignedData
            num_blocks = numel(obj.ValidRunIndices);
            obj.RawDataCache = cell(1, num_blocks);
            obj.CleanDataCache = cell(1, num_blocks);
            
            for r = 1:num_blocks
                obj.RawDataCache{r} = obj.ParentApp.WorkspaceData.AlignedData(r).LFP.data;
                obj.CleanDataCache{r} = obj.RawDataCache{r};
            end
            
            buildInterface(obj);
            initializeTrackingMap(obj);
            loadSelectedSessionContext(obj);
            
            % Automatically open the SVD Diagnostics window on startup
            cbLaunchDiagnosticUI(obj);
        end
    end
    
    methods (Access = private)
        function mapAlignedDataToProtocols(obj)
            % Cleanly fetch exact labels from the unified struct
            a_data = obj.ParentApp.WorkspaceData.AlignedData;
            obj.ValidRunLabels = string({a_data.task_id});
            obj.ValidRunIndices = 1:numel(obj.ValidRunLabels); % 1:1 mapping with AlignedData array
        end
        
        function initializeTrackingMap(obj)
            num_runs = numel(obj.RawDataCache);
            obj.TrackingMap = struct();
            for r = 1:num_runs
                for h = 1:2
                    field_key = sprintf('Block_%d_Hemi_%d', r, h);
                    obj.TrackingMap.(field_key) = []; 
                end
            end
        end
        
        function buildInterface(obj)
            screensize = get(groot,'ScreenSize');
            w = screensize(3) * 0.9; h = screensize(4) * 0.85; 
            x = (screensize(3)-w)/2; y = (screensize(4)-h)/2;
            obj.UIFigure = uifigure('Name', 'Interactive SVD Cardiac Artifact Suppression', ...
                                   'Position', [x, y, w, h], ...
                                   'CloseRequestFcn', @(src, event) obj.cbCloseAllWindows(src, event));
            obj.MainGrid = uigridlayout(obj.UIFigure, [1, 2]);
            obj.MainGrid.ColumnWidth = {340, '1x'};
            
            % --- CONTROL INTERACTION PANEL ---
            obj.ControlPanel = uipanel(obj.MainGrid, 'Title', 'Control Panel');
            ctrlLayout = uigridlayout(obj.ControlPanel, [9, 1]);
            
            % Compacted top section heights and expanded log box area ('1x')
            ctrlLayout.RowHeight = {20, 28, 20, 28, 20, 30, 22, '1x', 40};
            ctrlLayout.Padding = [10 10 10 10];
            ctrlLayout.RowSpacing = 6;
            
            uilabel(ctrlLayout, 'Text', 'Select Protocol Target Step:', 'FontWeight', 'bold');
            displayItems = arrayfun(@(x) sprintf('Protocol Section: %s', obj.ValidRunLabels(x)), ...
                1:numel(obj.ValidRunLabels), 'UniformOutput', false);
            obj.DropdownRec = uidropdown(ctrlLayout, 'Items', displayItems, ...
                'ValueChangedFcn', @(src, event) obj.cbSessionContextChanged(src, event));
            
            uilabel(ctrlLayout, 'Text', 'Select Target Evaluation Hemisphere:', 'FontWeight', 'bold');
            obj.DropdownHemi = uidropdown(ctrlLayout, 'Items', {'Left', 'Right'}, ...
                'ValueChangedFcn', @(src, event) obj.cbSessionContextChanged(src, event));
            
            uilabel(ctrlLayout, 'Text', 'Select SVD Component to Reject:', 'FontWeight', 'bold');
            compGrid = uigridlayout(ctrlLayout, [1, 3]);
            compGrid.ColumnWidth = {'1x', 45, 55}; compGrid.Padding = [0 0 0 0];
            
            obj.DropdownSelComp = uidropdown(compGrid, 'Items', {'Component 1', 'Component 2', 'Component 3', 'Component 4', 'Component 5'});
            obj.BtnAddComp = uibutton(compGrid, 'Text', '+', 'FontWeight', 'bold', 'FontSize', 14, ...
                'ButtonPushedFcn', @(src, event) obj.cbAddRejectionComponent(src, event));
            obj.BtnResetComp = uibutton(compGrid, 'Text', 'Reset', 'FontSize', 11, ...
                'ButtonPushedFcn', @(src, event) obj.cbResetRejectionComponents(src, event));
            
            obj.LblRejectedList = uilabel(ctrlLayout, 'Text', 'Rejected Components: None', ...
                'FontWeight', 'bold', 'FontColor', [0.6 0.2 0.2]);
            
            obj.TxtLog = uitextarea(ctrlLayout, 'Editable', 'off', 'FontAngle', 'normal', 'FontSize', 11);
            
            obj.BtnCommit = uibutton(ctrlLayout, 'Text', '🔒 Lock Clean Workspace to Dashboard', ...
                'BackgroundColor', [0.76 0.89 0.76], 'FontWeight', 'bold', ...
                'ButtonPushedFcn', @(src, event) obj.cbCommitToParentDashboard(src, event));
            
            % --- TILED CHART CANVAS (AUTOMATIC 100% HORIZONTAL ALIGNMENT) ---
            obj.PlotPanel = uipanel(obj.MainGrid, 'Title', 'Continuous Signal Output Canvas');
            obj.MainTileGrid = tiledlayout(obj.PlotPanel, 3, 1, 'Padding', 'compact', 'TileSpacing', 'compact');
            
            % AxSignal occupies top 2 rows (2/3 height)
            obj.AxSignal = nexttile(obj.MainTileGrid, 1, [2, 1]); grid(obj.AxSignal, 'on'); hold(obj.AxSignal, 'on');
            
            % AxSpec occupies bottom row (1/3 height)
            obj.AxSpec   = nexttile(obj.MainTileGrid, 3, [1, 1]); grid(obj.AxSpec, 'on'); hold(obj.AxSpec, 'on');
            
            linkaxes([obj.AxSignal, obj.AxSpec], 'x');
        end
        
        function logStatusMessage(obj, messageText)
            timestamp = datestr(now, 'HH:MM:SS');
            formattedLine = sprintf('[%s] %s', timestamp, messageText);
            obj.TxtLog.Value = [string(formattedLine); obj.TxtLog.Value];
        end
        
        function loadSelectedSessionContext(obj)
            valIdx = find(strcmp(obj.DropdownRec.Items, obj.DropdownRec.Value), 1);
            if isempty(valIdx) || valIdx <= 0, return; end
            
            recIdx = obj.ValidRunIndices(valIdx);
            hemiIdx = find(strcmp(obj.DropdownHemi.Items, obj.DropdownHemi.Value), 1);
            
            field_key = sprintf('Block_%d_Hemi_%d', recIdx, hemiIdx);
            obj.ActiveRejectedComps = obj.TrackingMap.(field_key);
            
            updateRejectionLabelString(obj);
            
            sec_label  = obj.ValidRunLabels(valIdx);
            hemi_label = obj.DropdownHemi.Value;
            logStatusMessage(obj, sprintf('⌛ Calculating the multitaper spectrogram for section %s, %s hemisphere', sec_label, hemi_label));
            drawnow; % Force GUI refresh before computation
            
            processSvdFilterPipeline(obj);
        end
        
        function updateRejectionLabelString(obj)
            if isempty(obj.ActiveRejectedComps)
                obj.LblRejectedList.Text = 'Rejected Components: None';
            else
                comp_strs = arrayfun(@(x) num2str(x), obj.ActiveRejectedComps, 'UniformOutput', false);
                obj.LblRejectedList.Text = sprintf('Rejected Components: [%s]', strjoin(comp_strs, ', '));
            end
        end
        
        function processSvdFilterPipeline(obj)
            valIdx = find(strcmp(obj.DropdownRec.Items, obj.DropdownRec.Value), 1);
            recIdx = obj.ValidRunIndices(valIdx);
            hemiIdx = find(strcmp(obj.DropdownHemi.Items, obj.DropdownHemi.Value), 1);
            
            lfp_raw_full = obj.RawDataCache{recIdx};
            sig_in = lfp_raw_full(:, hemiIdx);
            
            % Generate relative timeline perfectly from the Master Datetime vector
            a_block = obj.ParentApp.WorkspaceData.AlignedData(recIdx);
            obj.CurrentTimeVector = seconds(a_block.CommonTime - a_block.CommonTime(1));
            
            % --- STAGE 1: BROAD ARTIFACT REJECTION AND SIGNAL RECOVERY ---
            fc_hp = 3; [b_hp, a_hp] = butter(4, fc_hp / (obj.Fs/2), 'high');
            lfp_hp = filtfilt(b_hp, a_hp, double(sig_in));
            
            lfp_notch = lfp_hp;
            harmonics = 50:50:(obj.Fs/2 - 1);
            for f_notch = harmonics
                wo = f_notch / (obj.Fs/2); bw = wo / 35;
                [B,A,sv] = designNotchPeakIIR(Response="notch", FilterOrder=2, CenterFrequency=wo, Bandwidth=bw, HasScaleValues=true);
                notchFilter = dsp.SOSFilter(Numerator=B, Denominator=A, ScaleValues=sv);
                lfp_notch = notchFilter(lfp_notch);
            end
            
            % --- STAGE 2: BANDPASS FILTER (3 - 45 Hz) FOR SVD EXTRACTION ONLY ---
            fc_lp = 45; [b_lp, a_lp] = butter(4, fc_lp / (obj.Fs/2), 'low');
            lfp_svd_clean = filtfilt(b_lp, a_lp, lfp_notch);
            
            obj.CurrentRawSignal  = lfp_notch;
            
            [final_locs, u_matrix, S_matrix, V_matrix, var_ex, template_qrst] = obj.runOnDemandBeatAnalysis(lfp_svd_clean);
            
            obj.CurrentTemplate = template_qrst;
            obj.CurrentSvdVariance = var_ex;
            
            obj.Cached_U = u_matrix;
            obj.Cached_S = S_matrix;
            obj.Cached_V = V_matrix;
            obj.Cached_locs = final_locs;
            
            if ~isempty(obj.ActiveRejectedComps) && length(final_locs) > 5
                art_pts_b4_peak = round(0.25 * obj.Fs);
                art_pts_after_peak = round(0.40 * obj.Fs);
                
                U_slice = obj.Cached_U(:, obj.ActiveRejectedComps);
                S_slice = obj.Cached_S(obj.ActiveRejectedComps, :);
                V_slice = obj.Cached_V; 
                
                proj = U_slice * S_slice * V_slice';
                
                sigout = lfp_notch;
                for i = 1:length(final_locs)
                    columnMeans = proj(:, i);
                    st_idx = final_locs(i) - art_pts_b4_peak; en_idx = final_locs(i) + art_pts_after_peak;
                    if st_idx > 0 && en_idx <= length(sigout)
                        y = sigout(st_idx:en_idx);
                        options = optimoptions(@lsqnonlin, 'Algorithm', 'trust-region-reflective', 'Display', 'off');
                        [parest,~,~,~,~] = lsqnonlin(@(p) (y - (columnMeans + p(1))), 2, -10, 10, options);
                        sigout(st_idx:en_idx) = y - (columnMeans + parest(1));
                    end
                end
                obj.CurrentCleanSignal = sigout;
            else
                obj.CurrentCleanSignal = lfp_notch;
            end
            
            obj.CleanDataCache{recIdx}(:, hemiIdx) = obj.CurrentCleanSignal;
            
            renderMainCanvas(obj);
            if ~isempty(obj.DiagFigure) && isvalid(obj.DiagFigure)
                renderDiagnosticCanvas(obj);
            end
            
            % Log completion report
            sec_label  = obj.ValidRunLabels(valIdx);
            hemi_label = obj.DropdownHemi.Value;
            logStatusMessage(obj, sprintf('✔ Multitaper spectrogram ready for section %s, %s hemisphere.', sec_label, hemi_label));
        end
        
        function renderMainCanvas(obj)
            cell_idx = find(strcmp(obj.DropdownRec.Items, obj.DropdownRec.Value), 1);
            recIdx = obj.ValidRunIndices(cell_idx);
            hemiIdx = find(strcmp(obj.DropdownHemi.Items, obj.DropdownHemi.Value), 1);
            
            % --- CONTINUOUS SIGNAL WAVEFORMS (DUAL-Y AXIS) ---
            yyaxis(obj.AxSignal, 'left'); cla(obj.AxSignal);
            
            % 1. Filtered LFP (SVD Clean): Purple dashed line on bottom layer
            pClean = plot(obj.AxSignal, obj.CurrentTimeVector, obj.CurrentCleanSignal, ...
                'Color', [0.49 0.18 0.55], 'LineStyle', '--', 'LineWidth', 1.2);
            
            % 2. LFP (Pre-Filtered Original): Blue solid line on top layer
            pRaw = plot(obj.AxSignal, obj.CurrentTimeVector, obj.CurrentRawSignal, ...
                'Color', [0 0.45 0.74], 'LineStyle', '-', 'LineWidth', 0.9);
            
            ylabel(obj.AxSignal, 'Potential (\muV)');
            obj.AxSignal.YAxis(1).Color = [0 0.45 0.74];
            
            % Right Y-Axis: Stimulation Intensity Overlay (Red Solid Line)
            a_block = obj.ParentApp.WorkspaceData.AlignedData(recIdx);
            stim_vector = a_block.Stim.data(:, hemiIdx);
            
            yyaxis(obj.AxSignal, 'right'); cla(obj.AxSignal);
            pStim = plot(obj.AxSignal, obj.CurrentTimeVector, stim_vector, ...
                'Color', [0.85 0.33 0.1], 'LineStyle', '-', 'LineWidth', 1.4);
            ylabel(obj.AxSignal, 'Stim (mA)');
            obj.AxSignal.YAxis(2).Color = [0.85 0.33 0.1];
            
            % Strictly fix bottom Y-limit at 0 mA
            max_stim = max(stim_vector);
            if isempty(max_stim) || isnan(max_stim) || max_stim <= 0
                ylim(obj.AxSignal, [0, 1.0]);
            else
                ylim(obj.AxSignal, [0, max_stim * 1.15]);
            end
            
            % Revert active state parameters to left axis coordinate frames
            yyaxis(obj.AxSignal, 'left');
            xlim(obj.AxSignal, [0, obj.CurrentTimeVector(end)]);
            
            % Legend placed outside graph in top-right corner
            legend(obj.AxSignal, [pRaw, pClean, pStim], ...
                {'LFP', 'Filtered LFP', 'Stimulation'}, ...
                'Location', 'northeastoutside', 'Box', 'off');
            title(obj.AxSignal, sprintf('Active Processing Viewport (Section %s)', obj.ValidRunLabels(cell_idx)));
            
            % --- BOTTOM TILE: MULTITAPER SPECTROGRAM ANALYSIS (0-50 Hz) ---
            cla(obj.AxSpec);
            obj.computeAndPlotMultitaper(obj.AxSpec, obj.CurrentCleanSignal, obj.CurrentTimeVector);
            title(obj.AxSpec, 'Multitaper Spectrogram (dB)');
            xlim(obj.AxSpec, [0, obj.CurrentTimeVector(end)]);
        end
        
        function computeAndPlotMultitaper(obj, targetAx, signalVector, timeVector)
            win_size = 1.0; 
            N_win = round(win_size * obj.Fs); 
            NW = 3; 
            step_size = 0.1; 
            hop = round(step_size * obj.Fs);
            nfft = 512;
            
            signal_detrend = double(signalVector - mean(signalVector));
            starts = 1:hop:(length(signal_detrend) - N_win);
            
            if isempty(starts)
                text(targetAx, 0.5, 0.5, 'Data Segment Too Short for MT analysis', 'HorizontalAlignment', 'center');
                return;
            end
            
            [~, f_mt] = pmtm(signal_detrend(1:N_win), NW, nfft, obj.Fs);
            Spec_MT = zeros(length(f_mt), length(starts));
            
            for k = 1:length(starts)
                Spec_MT(:, k) = pmtm(signal_detrend(starts(k) : starts(k) + N_win - 1), NW, nfft, obj.Fs);
            end
            
            time_axis_seconds = timeVector(1) + (starts + N_win/2) / obj.Fs;
            
            imagesc(targetAx, time_axis_seconds, f_mt, 10*log10(Spec_MT));
            axis(targetAx, 'xy'); colormap(targetAx, 'jet'); 
            ylim(targetAx, [0 50]); % Strict 0-50 Hz frequency cutoff
            ylabel(targetAx, 'Freq (Hz)'); xlabel(targetAx, 'Time (s)');       
            c = colorbar(targetAx); clim(targetAx, [-5 25]);
            c.Label.String = "Power/Frequency";
        end
        
        function renderDiagnosticCanvas(obj)
            axTemplate = findobj(obj.DiagFigure, 'Tag', 'DiagAxTemplate');
            axSvdVar   = findobj(obj.DiagFigure, 'Tag', 'DiagAxSvdVar');
            
            if isempty(axTemplate) || isempty(axSvdVar), return; end
            cla(axTemplate); cla(axSvdVar);
            
            pre_R  = round(0.25 * obj.Fs);
            post_R = round(0.40 * obj.Fs);
            art_width_pts = pre_R + post_R + 1;
            
            t_relative = ((1:art_width_pts) - (pre_R + 1)) / obj.Fs;
            
            plot(axTemplate, t_relative, obj.CurrentTemplate, 'Color', [0.46 0.67 0.18], 'LineWidth', 2.0);
            title(axTemplate, 'Peri-Peak Template P-QRS-T Profile'); ylabel(axTemplate, 'Amplitude (\muV)'); xlabel(axTemplate, 'Time relative to R-peak (s)');
            xline(axTemplate, 0, '--k', 'LineWidth', 1.1);
            xlim(axTemplate, [-0.25, 0.40]);
            
            numBars = min(10, numel(obj.CurrentSvdVariance));
            bar(axSvdVar, obj.CurrentSvdVariance(1:numBars) * 100, 'FaceColor', [0.2 0.2 0.2]);
            title(axSvdVar, 'Singular Values Variance Spectrum'); ylabel(axSvdVar, 'Energy (%)'); xlabel(axSvdVar, 'Rank Index');
            
            blues = [[0.05 0.20 0.45]; [0.10 0.35 0.65]; [0.20 0.50 0.85]; [0.40 0.65 0.95]];
            max_y = max(max(abs(obj.Cached_U(:, 1:4)))) * 1.15;
            
            for c = 1:4
                axComp = findobj(obj.DiagFigure, 'Tag', sprintf('DiagAxComp_%d', c));
                if isempty(axComp), continue; end
                cla(axComp);
                
                plot(axComp, t_relative, obj.Cached_U(:, c), 'Color', blues(c, :), 'LineWidth', 1.6);
                grid(axComp, 'on'); xline(axComp, 0, '--k', 'Alpha', 0.5);
                
                ylim(axComp, [-max_y, max_y]);
                xlim(axComp, [-0.25, 0.40]); 
                
                title(axComp, sprintf('Component %d', c));
                if c == 1, ylabel(axComp, 'Eigenvalue Shape'); end
                xlabel(axComp, 'Time relative to R-peak (s)');
            end
        end
        
        function cbLaunchDiagnosticUI(obj, ~, ~)
            if isempty(obj.DiagFigure) || ~isvalid(obj.DiagFigure)
                screensize = get(groot,'ScreenSize');
                w = screensize(3) * 0.75; h = screensize(4) * 0.65; 
                x = (screensize(3)-w)/2; y = (screensize(4)-h)/2;
                
                obj.DiagFigure = uifigure('Name', 'SVD Subspace Matrix Component Diagnostics', ...
                                          'Position', [x, y, w, h]);
                
                masterGrid = uigridlayout(obj.DiagFigure, [2, 2]);
                masterGrid.Padding = [12 12 12 12]; masterGrid.RowSpacing = 15; masterGrid.ColumnSpacing = 15;
                
                axT = uiaxes(masterGrid); axT.Tag = 'DiagAxTemplate'; grid(axT, 'on');
                axV = uiaxes(masterGrid); axV.Tag = 'DiagAxSvdVar'; grid(axV, 'on');
                
                compPanel = uipanel(masterGrid, 'Title', 'Orthogonal Singular U Vector Waves (Blue Palette)');
                compPanel.Layout.Row = 2; compPanel.Layout.Column = [1, 2];
                
                compGrid = uigridlayout(compPanel, [1, 4]);
                compGrid.Padding = [8 8 8 8]; compGrid.ColumnSpacing = 10;
                
                for c = 1:4
                    axC = uiaxes(compGrid);
                    axC.Tag = sprintf('DiagAxComp_%d', c);
                    grid(axC, 'on');
                end
            end
            
            figure(obj.DiagFigure); 
            renderDiagnosticCanvas(obj);
        end
        
        function cbAddRejectionComponent(obj, ~, ~)
            comp_idx = find(strcmp(obj.DropdownSelComp.Items, obj.DropdownSelComp.Value), 1);
            if ~ismember(comp_idx, obj.ActiveRejectedComps)
                obj.ActiveRejectedComps = sort([obj.ActiveRejectedComps, comp_idx]);
                
                valIdx = find(strcmp(obj.DropdownRec.Items, obj.DropdownRec.Value), 1);
                recIdx = obj.ValidRunIndices(valIdx);
                hemiIdx = find(strcmp(obj.DropdownHemi.Items, obj.DropdownHemi.Value), 1);
                field_key = sprintf('Block_%d_Hemi_%d', recIdx, hemiIdx);
                obj.TrackingMap.(field_key) = obj.ActiveRejectedComps;
                
                logStatusMessage(obj, sprintf('Section %s (%s): Added Component %d to rejection list.', ...
                    obj.ValidRunLabels(valIdx), obj.DropdownHemi.Value, comp_idx));
                
                updateRejectionLabelString(obj);
                
                % Re-run pipeline to update SVD signal & recalculate Multitaper
                logStatusMessage(obj, sprintf('⌛ Calculating the multitaper spectrogram for section %s, %s hemisphere', ...
                    obj.ValidRunLabels(valIdx), obj.DropdownHemi.Value));
                drawnow;
                
                processSvdFilterPipeline(obj);
            end
        end
        
        function cbResetRejectionComponents(obj, ~, ~)
            obj.ActiveRejectedComps = [];
            valIdx = find(strcmp(obj.DropdownRec.Items, obj.DropdownRec.Value), 1);
            recIdx = obj.ValidRunIndices(valIdx);
            hemiIdx = find(strcmp(obj.DropdownHemi.Items, obj.DropdownHemi.Value), 1);
            field_key = sprintf('Block_%d_Hemi_%d', recIdx, hemiIdx);
            obj.TrackingMap.(field_key) = [];
            
            logStatusMessage(obj, sprintf('Section %s (%s): Rejection criteria cleared.', ...
                obj.ValidRunLabels(valIdx), obj.DropdownHemi.Value));
            
            updateRejectionLabelString(obj);
            
            % Re-run pipeline to reset signal & recalculate Multitaper
            logStatusMessage(obj, sprintf('⌛ Calculating the multitaper spectrogram for section %s, %s hemisphere', ...
                obj.ValidRunLabels(valIdx), obj.DropdownHemi.Value));
            drawnow;
            
            processSvdFilterPipeline(obj);
        end
        
        function cbSessionContextChanged(obj, ~, ~)
            loadSelectedSessionContext(obj);
        end
        
        function cbCommitToParentDashboard(obj, ~, ~)
            % Backfill non-titration cache runs with pre-filtered baselines before saving
            for r = 1:numel(obj.CleanDataCache)
                if isempty(obj.CleanDataCache{r})
                    lfp_raw_full = obj.RawDataCache{r};
                    for h = 1:2
                        sig_in = lfp_raw_full(:, h);
                        fc_hp = 3; [b_hp, a_hp] = butter(4, fc_hp / (obj.Fs/2), 'high');
                        lfp_hp = filtfilt(b_hp, a_hp, double(sig_in));
                        lfp_notch = lfp_hp;
                        harmonics = 50:50:(obj.Fs/2 - 1);
                        for f_notch = harmonics
                            wo = f_notch / (obj.Fs/2); bw = wo / 35;
                            [B,A,sv] = designNotchPeakIIR(Response="notch", FilterOrder=2, CenterFrequency=wo, Bandwidth=bw, HasScaleValues=true);
                            notchFilter = dsp.SOSFilter(Numerator=B, Denominator=A, ScaleValues=sv);
                            lfp_notch = notchFilter(lfp_notch);
                        end
                        lfp_raw_full(:, h) = lfp_notch;
                    end
                    obj.CleanDataCache{r} = lfp_raw_full;
                end
                
                % INJECT CLEANED MATRIX DIRECTLY INTO ALIGNED DATA
                obj.ParentApp.WorkspaceData.AlignedData(r).LFP.data_clean = obj.CleanDataCache{r};
            end
            
            obj.ParentApp.IsLfpCleaned = true;
            
            modified_sections = string.empty;
            fn_keys = fieldnames(obj.TrackingMap);
            for f = 1:numel(fn_keys)
                if ~isempty(obj.TrackingMap.(fn_keys{f}))
                    tokens = strsplit(fn_keys{f}, '_');
                    r_idx = str2double(tokens{2});
                    h_idx = str2double(tokens{4});
                    match_pos = find(obj.ValidRunIndices == r_idx, 1);
                    if ~isempty(match_pos)
                        if h_idx == 1, h_str = "Left"; else, h_str = "Right"; end
                        modified_sections(end+1) = sprintf('Section %s (%s side)', obj.ValidRunLabels(match_pos), h_str);
                    end
                end
            end
            
            if isempty(modified_sections)
                obj.ParentApp.updateStatus('✔ SVD cleaning concluded: Cleaned data injected into AlignedData (No manual adjustments made).');
            else
                summary_str = strjoin(modified_sections, ', ');
                obj.ParentApp.updateStatus(sprintf('✔ SVD cleaning locked: Cleaned data injected into AlignedData. Adjustments applied to: %s.', summary_str));
            end
            
            if ~isempty(obj.DiagFigure) && isvalid(obj.DiagFigure)
                delete(obj.DiagFigure);
            end
            obj.ParentApp.refreshStateEngine();
            delete(obj.UIFigure);
        end
        
        function cbCloseAllWindows(obj, ~, ~)
            if ~isempty(obj.DiagFigure) && isvalid(obj.DiagFigure)
                delete(obj.DiagFigure);
            end
            delete(obj.UIFigure);
        end
        
        %% --- CORE MATH ENGINES ---
        function [valid_locs, U, S, V, var_ex, qrst] = runOnDemandBeatAnalysis(obj, lfp_notch)
            fc_proxy = [10 45]; [b_prox, a_prox] = butter(2, fc_proxy / (obj.Fs/2), 'bandpass');
            lfp_proxy = filtfilt(b_prox, a_prox, lfp_notch);
            
            teo_sig = lfp_proxy(2:end-1).^2 - lfp_proxy(1:end-2).*lfp_proxy(3:end); teo_sig = [0; teo_sig; 0];
            smooth_win = round(0.1 * obj.Fs); teo_smooth = filtfilt(ones(1,smooth_win)/smooth_win, 1, teo_sig);
            
            min_dist_samps = round(0.35 * obj.Fs); threshold_teo = 2.5 * median(teo_smooth); 
            [~, merged_locs] = findpeaks(teo_smooth, 'MinPeakHeight', threshold_teo, 'MinPeakDistance', min_dist_samps);
            
            art_pts_b4_peak = round(0.25 * obj.Fs); art_pts_after_peak = round(0.40 * obj.Fs);
            art_width_pts = art_pts_b4_peak + art_pts_after_peak + 1;
            
            valid_mask = false(size(merged_locs));
            allqrst = []; cnt = 1;
            for i = 1:length(merged_locs)
                st = merged_locs(i) - art_pts_b4_peak; en = merged_locs(i) + art_pts_after_peak;
                if st > 0 && en <= length(lfp_notch)
                    if ~any(isnan(lfp_notch(st:en)))
                        allqrst(cnt, :) = lfp_notch(st:en); 
                        cnt = cnt + 1;
                        valid_mask(i) = true;
                    end
                end
            end
            valid_locs = merged_locs(valid_mask);
            
            if isempty(allqrst)
                U = zeros(art_width_pts, 5); S = zeros(5, 5); V = zeros(5, 5); var_ex = zeros(5, 1); qrst = zeros(art_width_pts, 1); return;
            end
            
            qrst = mean(allqrst, 1)';
            [U, S, V] = svd(allqrst');
            var_ex = diag(S).^2 / sum(diag(S).^2);
        end
    end
end