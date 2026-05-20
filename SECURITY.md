# Security Policy

## Reporting a vulnerability

If you believe you have found a security vulnerability in QTAU Connector Workbench, please report it privately so we can address it before public disclosure.

**Email**: [security@sqkcloud.com](mailto:security@sqkcloud.com)

Please include:

- A description of the vulnerability and its potential impact.
- Steps to reproduce (a minimal proof-of-concept is ideal).
- The affected version of the toolbox (`opts.ToolboxVersion` in `scripts/package_release.m`, or your installed MATLAB Add-On version).
- Your name and contact details if you would like to be credited in the changelog after the fix ships.

We aim to acknowledge reports within **3 business days** and to provide a remediation timeline within **10 business days**.

## Scope

This policy covers the client-side MATLAB toolbox in this repository, including:

- Authentication and credential handling (`AuthService`, `FastAPIClient` headers).
- Network transport guards (`FastAPIClient.assertSafeBaseUrl`).
- Local logging and redaction (`Logger.redact`).
- File-system access (file upload, report download, bundle export).

The QTAU FastAPI **backend** is operated separately. Vulnerabilities in the backend should be reported to your QTAU server operator.

## Out of scope

- Vulnerabilities in MATLAB itself or in third-party MATLAB toolboxes — please report those to The MathWorks.
- Vulnerabilities requiring physical access to a user's machine or pre-existing admin privileges.
- Social-engineering attacks against maintainers.

## Supported versions

| Version | Supported |
|---------|-----------|
| 1.0.x   | ✅        |

Older versions stop receiving security fixes when a new major version ships.

## Safe disclosure

Please **do not** open public GitHub issues for security reports. Public disclosure before a fix is available puts every installer at risk. We will publicly credit reporters in the changelog once a coordinated fix has shipped, with their permission.
