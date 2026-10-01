# Changelog

All notable changes to this project are documented here. Format: [Keep a Changelog](https://keepachangelog.com/), versioning: [SemVer](https://semver.org/).

## [1.0.0] - 2026-10-01

### Changed
- Module manifest prepared for the PowerShell Gallery (description, tags, release notes). No functional changes.
- README: installation from the PowerShell Gallery (`Install-PSResource` / `Install-Module`).

## [0.1.0] - 2026-09-30

### Added
- `Invoke-SDOffboarding`: disable account, revoke sessions, convert mailbox to shared, optional FullAccess/forwarding/auto reply, remove groups (Graph and Exchange Online) and direct licenses. JSON backup before changes, `-WhatIf`/`-Confirm`, per-step result.
- `Get-SDIntuneNoncompliantReport`: non-compliant (optionally grace period) Intune devices as CSV and HTML, stale check-in detection, optional policy details.
- `Get-SDMailboxPermissionAudit`: FullAccess, SendAs and SendOnBehalf permissions as CSV and HTML, orphaned SID detection.
- `Test-SDToolkit`: offline self-test of the core logic.
- Pester 5 test suite with mocked Graph/Exchange cmdlets, contract tests against the real modules, PSScriptAnalyzer settings and GitHub Actions workflow.
