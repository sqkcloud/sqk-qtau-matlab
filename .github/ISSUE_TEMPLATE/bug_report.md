---
name: Bug report
about: Something in the workbench isn't working as expected
title: "[Bug] "
labels: bug, triage
assignees: ''
---

## Summary

<!-- One sentence: what is broken? -->

## Environment

- **QTAU Connector Workbench version**: <!-- e.g. 1.2.0 - check Add-Ons > Manage Add-Ons -->
- **MATLAB release**: <!-- e.g. R2025b, R2026a -->
- **Operating system**: <!-- macOS 14.x / Windows 11 / Ubuntu 22.04 / MATLAB Online -->
- **QTAU FastAPI backend URL pattern**: <!-- e.g. https://internal.example.com:5715 (sanitize the host) -->
- **Backend version / commit**: <!-- if known -->

## Steps to reproduce

1.
2.
3.

## Expected behaviour

<!-- What should have happened? -->

## Actual behaviour

<!-- What did happen? Paste the error message or screenshot. -->

## Logger output

Run this in the MATLAB Command Window BEFORE reproducing, then paste the output captured during the failure:

```matlab
>> Logger.setLevel('DEBUG');
% reproduce the bug ...
```

```
<paste log output here, redacting any tokens or PII>
```

## Additional context

<!-- Anything else? Screenshots, related issues, workarounds tried. -->
