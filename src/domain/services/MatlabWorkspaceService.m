classdef MatlabWorkspaceService < handle
    % MatlabWorkspaceService  Safe bridge between QTAU and MATLAB Workspace.
    %
    % Supports CircuitModel, quantumCircuit, struct, table, timetable,
    % numeric/logical arrays, and strings without using unrestricted eval.
    methods
        function rows = listSupportedVariables(~)
            % WHOS reports package-qualified class names differently across
            % MATLAB releases (for example quantumCircuit versus
            % quantum.gate.QuantumCircuit). Inspect both metadata and the
            % actual base-workspace value before deciding whether it can be
            % imported into Composer.
            vars = evalin('base', 'whos');
            accepted = false(size(vars));
            displayClass = strings(size(vars));

            for i = 1:numel(vars)
                className = string(vars(i).class);
                normalizedClass = lower(className);
                metadataMatch = className == "CircuitModel" || ...
                    contains(normalizedClass, "quantumcircuit");

                valueMatch = false;
                try
                    value = evalin('base', vars(i).name);
                    valueMatch = isa(value, 'CircuitModel') || ...
                        MatlabQuantumService.isQuantumCircuit(value);
                    if valueMatch
                        displayClass(i) = string(class(value));
                    end
                catch
                    % A workspace value can disappear while the dialog is
                    % opening. Ignore it instead of failing the whole list.
                    valueMatch = false;
                end

                accepted(i) = metadataMatch || valueMatch;
                if strlength(displayClass(i)) == 0
                    displayClass(i) = className;
                end
            end

            vars = vars(accepted);
            displayClass = displayClass(accepted);
            rows = cell(numel(vars), 4);
            for i = 1:numel(vars)
                rows{i,1} = vars(i).name;
                rows{i,2} = char(displayClass(i));
                rows{i,3} = mat2str(vars(i).size);
                rows{i,4} = vars(i).bytes;
            end
        end

        function value = importVariable(~, variableName)
            name = MatlabWorkspaceService.validateName(variableName);
            value = evalin('base', name);
            if ~MatlabWorkspaceService.isSupportedValue(value)
                error('MatlabWorkspaceService:UnsupportedType', ...
                    'Workspace variable "%s" has unsupported class %s.', name, class(value));
            end
        end

        function exportVariable(~, variableName, value)
            name = MatlabWorkspaceService.validateName(variableName);
            assignin('base', name, value);
        end

        function path = saveMatFile(~, path, variableName, value)
            name = MatlabWorkspaceService.validateName(variableName);
            if nargin < 2 || isempty(path)
                [f,p] = uiputfile('*.mat', 'Save MATLAB data');
                if isequal(f,0); path = ''; return; end
                path = fullfile(p,f);
            end
            payload = struct(); payload.(name) = value;
            save(path, '-struct', 'payload');
        end
    end

    methods (Static)
        function tf = isSupportedValue(value)
            tf = isa(value,'CircuitModel') || MatlabQuantumService.isQuantumCircuit(value) || ...
                isstruct(value) || istable(value) || istimetable(value) || ...
                isnumeric(value) || islogical(value) || isstring(value) || ischar(value) || iscell(value);
        end

        function tf = isSupportedClass(className)
            className = char(className);
            tf = any(strcmp(className, {'CircuitModel','quantumCircuit','struct','table','timetable', ...
                'double','single','logical','string','char','cell','int8','int16','int32','int64', ...
                'uint8','uint16','uint32','uint64'})) || ...
                contains(lower(string(className)), 'quantumcircuit');
        end

        function name = validateName(variableName)
            name = char(strtrim(string(variableName)));
            if isempty(name) || ~isvarname(name)
                error('MatlabWorkspaceService:InvalidVariableName', ...
                    '"%s" is not a valid MATLAB variable name.', name);
            end
        end
    end
end
