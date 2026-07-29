classdef MatlabResultAdapter
    % MatlabResultAdapter  Normalizes API/local results for MATLAB analysis.
    methods (Static)
        function out = toStruct(value)
            if isstruct(value); out = value;
            elseif istable(value) || istimetable(value); out = table2struct(value);
            else; out = struct('value', value);
            end
        end

        function out = toTable(value)
            if istable(value); out = value; return; end
            if istimetable(value); out = timetable2table(value); return; end
            if isstruct(value)
                try
                    out = struct2table(value, 'AsArray', true);
                catch
                    out = table({value}, 'VariableNames', {'Result'});
                end
                return;
            end
            if iscell(value); out = cell2table(value); return; end
            if isnumeric(value) || islogical(value); out = array2table(value); return; end
            out = table({value}, 'VariableNames', {'Result'});
        end

        function exportToWorkspace(value, variableName, format)
            if nargin < 3; format = 'struct'; end
            switch lower(char(format))
                case 'table'; value = MatlabResultAdapter.toTable(value);
                case 'struct'; value = MatlabResultAdapter.toStruct(value);
            end
            MatlabWorkspaceService().exportVariable(variableName, value);
        end
    end
end
