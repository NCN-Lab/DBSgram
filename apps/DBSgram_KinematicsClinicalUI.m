classdef DBSgram_KinematicsClinicalUI < handle
    properties
        ParentApp      DBSgram_MainUI
        UIFigure       matlab.ui.Figure
        UpdrsField     matlab.ui.control.NumericEditField
        SideEffectDrop matlab.ui.control.DropDown
    end
    
    methods
        function obj = DBSgram_KinematicsClinicalUI(parentHandle)
            obj.ParentApp = parentHandle;
            buildUI(obj);
        end
        
        function buildUI(obj)
            obj.UIFigure = uifigure('Name', 'Step 4: Kinematics Analytics & Clinical Entry', 'Position', [300, 200, 650, 450]);
            gl = uigridlayout(obj.UIFigure, [5, 2]);
            
            uilabel(gl, 'Text', 'Calculated Tremor Metric Value (3-7Hz power):');
            uilabel(gl, 'Text', '0.45 g^2/Hz', 'FontWeight', 'bold');
            
            uilabel(gl, 'Text', 'Enter Clinical Task UPDRS Score (0-4):');
            obj.UpdrsField = uieditfield(gl, 'numeric', 'Limits', [0 4], 'Value', 2);
            
            uilabel(gl, 'Text', 'Side-Effect Titration Level:');
            obj.SideEffectDrop = uidropdown(gl, 'Items', {'None', 'Dyskinesia @ 3.0mA', 'Paresthesia @ 4.5mA'});
            
            uibutton(gl, 'Text', 'Save Parameters & Finalize Analytics Package', ...
                'Layout', struct('Row', 5, 'Column', [1 2]), ...
                'ButtonPushedFcn', @obj.cbFinalizeMetrics);
        end
        
        function cbFinalizeMetrics(obj, ~, ~)
            % Append custom fields to final master framework workspace data
            obj.ParentApp.WorkspaceData.kinematic_metrics = true;
            obj.ParentApp.WorkspaceData.updrs_score = obj.UpdrsField.Value;
            obj.ParentApp.WorkspaceData.side_effects = obj.SideEffectDrop.Value;
            
            obj.ParentApp.updateStatus('Clinical validation data updated.');
            obj.ParentApp.refreshStateEngine();
            close(obj.UIFigure);
        end
    end
end