classdef TestCircuitCuttingVmProbe < handle
    % TestCircuitCuttingVmProbe  Exposes the private helpers used by
    % CircuitCuttingViewModel (formatOverhead, formatPerSub) so they can
    % be unit-tested without spinning up a full QTAUWorkbenchApp instance.
    %
    %   Keep these copies in lock-step with the real helpers —
    %   contract: numeric → formatted string, empty/NaN → '--'.

    methods
        function s = probeFormatOverhead(~, v)
            if isempty(v) || ~isnumeric(v) || any(isnan(v))
                s = '--'; return;
            end
            s = sprintf('%.1fx', double(v));
        end

        function s = probeFormatPerSub(~, per)
            if isempty(per); s = '(unknown)'; return; end
            if iscell(per)
                parts = cellfun(@(x) sprintf('%d', int32(x)), per, ...
                    'UniformOutput', false);
            else
                parts = arrayfun(@(x) sprintf('%d', int32(x)), per, ...
                    'UniformOutput', false);
            end
            s = ['(' strjoin(parts, '+') ')'];
        end

        function m = probeDefaultMode(~)
            m = 'assisted';
        end
    end
end
