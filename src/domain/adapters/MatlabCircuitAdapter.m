classdef MatlabCircuitAdapter
    % MatlabCircuitAdapter  Converts MATLAB quantumCircuit and QTAU CircuitModel.
    % The compatibility report is explicit: unsupported OpenQASM 3 constructs
    % are reported before conversion rather than silently discarded.
    methods (Static)
        function model = toCircuitModel(value)
            if isa(value,'CircuitModel'); model=value; return; end
            if ~MatlabQuantumService.isQuantumCircuit(value)
                error('MatlabCircuitAdapter:UnsupportedInput', ...
                    'Expected CircuitModel or MATLAB quantumCircuit, got %s.', class(value));
            end
            qasm3 = char(generateQASM(value));
            report = MatlabCircuitAdapter.analyzeQasm(qasm3);
            if ~report.compatible
                error('MatlabCircuitAdapter:UnsupportedQASM','%s',report.message);
            end
            model = CircuitModel.fromQasm(MatlabCircuitAdapter.normalizeQasm3ForModel(qasm3));
        end

        function qc = toQuantumCircuit(model)
            if ~isa(model,'CircuitModel')
                error('MatlabCircuitAdapter:InvalidModel','Input must be CircuitModel.');
            end
            if ~MatlabQuantumService.isAvailable()
                error('MatlabCircuitAdapter:SupportPackageMissing', ...
                    'MATLAB Support Package for Quantum Computing is unavailable.');
            end
            qasm = string(model.toQasm3());
            errors = strings(0,1);
            try
                qc = quantumCircuit(qasm); return;
            catch ME
                errors(end+1)=string(ME.message);
            end
            tmp=[tempname '.qasm']; cleanup=onCleanup(@()MatlabCircuitAdapter.deleteIfExists(tmp)); %#ok<NASGU>
            fid=fopen(tmp,'w');
            if fid<0; error('MatlabCircuitAdapter:TempFile','Unable to create temporary QASM file.'); end
            fwrite(fid,char(qasm)); fclose(fid);
            try
                qc=quantumCircuit(tmp);
            catch ME
                errors(end+1)=string(ME.message);
                error('MatlabCircuitAdapter:QuantumCircuitImportFailed', ...
                    'MATLAB could not import QTAU OpenQASM. %s',strjoin(errors,' | '));
            end
        end

        function report = compatibility(value)
            report=struct('compatible',false,'sourceClass',class(value), ...
                'numQubits',0,'numGates',0,'unsupportedConstructs',strings(0,1), ...
                'message','');
            try
                if isa(value,'CircuitModel')
                    qasm=char(value.toQasm3());
                elseif MatlabQuantumService.isQuantumCircuit(value)
                    qasm=char(generateQASM(value));
                elseif ischar(value)||isstring(value)
                    qasm=char(value);
                else
                    error('Unsupported input class %s.',class(value));
                end
                analysis=MatlabCircuitAdapter.analyzeQasm(qasm);
                report.compatible=analysis.compatible;
                report.unsupportedConstructs=analysis.unsupportedConstructs;
                report.message=analysis.message;
                try
                    model=CircuitModel.fromQasm(MatlabCircuitAdapter.normalizeQasm3ForModel(qasm));
                    report.numQubits=model.NumQubits; report.numGates=numel(model.Gates);
                catch ME
                    if report.compatible
                        report.compatible=false; report.message=ME.message;
                    end
                end
            catch ME
                report.message=ME.message;
            end
        end

        function report = analyzeQasm(qasm)
            text=char(qasm);
            unsupported=strings(0,1);
            checks={ ...
                '(?m)^\s*gate\s+','custom gate definitions'; ...
                '(?m)^\s*def\s+','OpenQASM subroutines'; ...
                '(?m)^\s*reset\b','reset operations'; ...
                '(?m)^\s*if\s*\(','classical conditionals'; ...
                '(?m)^\s*while\s*\(','loops'; ...
                '(?m)^\s*for\s+','loops'; ...
                '\binput\b|\bconst\b','symbolic/runtime parameters'; ...
                '\bdelay\s*\[','timing delays'};
            for i=1:size(checks,1)
                if ~isempty(regexp(text,checks{i,1},'once','ignorecase'))
                    unsupported(end+1)=string(checks{i,2}); %#ok<AGROW>
                end
            end
            unsupported=unique(unsupported,'stable');
            ok=isempty(unsupported);
            if ok
                msg='Compatible with the QTAU common-gate OpenQASM subset.';
            else
                msg=['Unsupported constructs: ' char(strjoin(unsupported,', ')) '.'];
            end
            report=struct('compatible',ok,'unsupportedConstructs',unsupported,'message',msg);
        end
    end
    methods (Static, Access=private)
        function qasm=normalizeQasm3ForModel(qasm)
            % Normalize MATLAB generateQASM OpenQASM 3 output to the
            % QASM2-compatible subset accepted by CircuitModel.fromQasm.
            qasm = char(qasm);
            qasm=regexprep(qasm,'OPENQASM\s+3(?:\.0)?','OPENQASM 2.0','ignorecase');
            qasm=regexprep(qasm,'qubit\s*\[\s*(\d+)\s*\]\s+(\w+)\s*;','qreg $2[$1];','ignorecase');
            qasm=regexprep(qasm,'bit\s*\[\s*(\d+)\s*\]\s+(\w+)\s*;','creg $2[$1];','ignorecase');
            qasm=regexprep(qasm,'include\s+"stdgates.inc"\s*;','include "qelib1.inc";','ignorecase');

            % OpenQASM 3 individual measurement:
            %   c[0] = measure q[0];
            % QTAU/QASM2 form:
            %   measure q[0] -> c[0];
            qasm=regexprep(qasm, ...
                '(?m)^\s*(\w+)\s*\[\s*(\d+)\s*\]\s*=\s*measure\s+(\w+)\s*\[\s*(\d+)\s*\]\s*;\s*$', ...
                'measure $3[$4] -> $1[$2];', 'ignorecase');

            % MATLAB generateQASM commonly emits bulk register measurement:
            %   c = measure q;
            % Expand it into one QASM2 measurement statement per qubit.
            bulk = regexp(qasm, ...
                '(?m)^\s*(\w+)\s*=\s*measure\s+(\w+)\s*;\s*$', ...
                'tokens');
            for i = 1:numel(bulk)
                cName = bulk{i}{1};
                qName = bulk{i}{2};
                qTok = regexp(qasm, ['(?m)^\s*qreg\s+' regexptranslate('escape',qName) ...
                    '\s*\[\s*(\d+)\s*\]\s*;'], 'tokens', 'once');
                cTok = regexp(qasm, ['(?m)^\s*creg\s+' regexptranslate('escape',cName) ...
                    '\s*\[\s*(\d+)\s*\]\s*;'], 'tokens', 'once');
                if isempty(qTok)
                    error('MatlabCircuitAdapter:MeasurementRegister', ...
                        'Unable to resolve measured quantum register "%s".', qName);
                end
                nQ = str2double(qTok{1});
                if isempty(cTok)
                    nC = nQ;
                else
                    nC = str2double(cTok{1});
                end
                n = min(nQ,nC);
                lines = strings(n,1);
                for k = 1:n
                    lines(k) = sprintf('measure %s[%d] -> %s[%d];', ...
                        qName,k-1,cName,k-1);
                end
                pattern = ['(?m)^\s*' regexptranslate('escape',cName) ...
                    '\s*=\s*measure\s+' regexptranslate('escape',qName) '\s*;\s*$'];
                qasm = regexprep(qasm, pattern, char(strjoin(lines,newline)), ...
                    'once','ignorecase');
            end

            qasm=regexprep(qasm,'(?m)^\s*barrier\b[^;]*;\s*$','','ignorecase');
        end
        function deleteIfExists(path)
            if exist(path,'file'); delete(path); end
        end
    end
end
