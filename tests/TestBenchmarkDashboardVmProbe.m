classdef TestBenchmarkDashboardVmProbe < handle
    % TestBenchmarkDashboardVmProbe  Reaches the private `formatKpi` helper
    % so it can be unit-tested without spinning up a full QTAUWorkbenchApp.
    % Keeps a separate copy of the helper in lock-step with the real one
    % (the whole method is ~5 lines, so duplication is cheap and the tests
    % pin the contract: numeric → formatted string, empty/NaN → '--').

    methods
        function txt = probeFormat(~, val, fmt)
            if isempty(val) || ~isnumeric(val) || any(isnan(val))
                txt = '--'; return;
            end
            if contains(fmt, '%d')
                txt = sprintf(fmt, int64(round(double(val))));
            else
                txt = sprintf(fmt, double(val));
            end
        end
    end
end
