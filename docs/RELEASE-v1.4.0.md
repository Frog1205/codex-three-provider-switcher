# v1.4.0 Windows release validation

Display version: `V_1.4_261025.01`.

## Changes

- Rename the Windows app to Codex API Route Manager / Codex API 路由管理器.
- Separate Official OpenAI and Custom endpoints; include Honknet, DeepSeek and OpenDev.
- Inspect saved custom routes and test a connection before saving. Saving does not switch the active route.
- Package the app icon in the EXE and portable ZIP. Preserve the existing production installer AppId and use a separate AppId for integration tests.
- Read custom JSON metadata as UTF-8 and preserve array shape for zero, one or multiple routes. Reserve OpenDev's built-in ID.

## Local verification

Windows 11 x64, OS version `10.0.26200.0`, Windows PowerShell 5.1:

- `Test-Switcher.ps1`: built-in routes and aliases, model selection, unrelated config preservation and backups.
- `Test-CustomProviders.ps1`: Chinese metadata, singleton/empty arrays, save without switching, custom routing, credential isolation and exact backup contents.
- `Test-GuiSmoke.ps1`: construct the real WinForms code using an isolated config and registry; verify title/version/icon, route categories/list, both languages, editor bounds, masked API key and disabled untested save/switch actions. Only modal loops and network starts are replaced in the test fixture.
- `Test-Packages.ps1 -ArtifactsDir dist -ArtifactSuffix V_1.4_261025.01 -Integration`: install/uninstall exit 0, required files and icon present, installed/source SHA-256 match, portable status succeeds, existing config and credentials unchanged.
- `Test-MSIXPackaging.ps1`: manifest, generated assets and x64 launcher compilation. This does not publish a Microsoft Store package.
- macOS Python: 4 unit tests and `--self-test` pass locally; this does not establish Mac desktop behavior on Windows.

GitHub Actions runs Windows regression/package integration and native Apple Silicon checks for the pushed commit. Refer to its run result for CI status.

## Release boundary

- Public assets for v1.4.0 are Windows EXE, Windows portable ZIP and SHA-256 checksums.
- macOS remains on the separate v1.3 stable release; the Windows custom-route editor has not been ported.
- Tests use isolated config and offline fixtures. They do not establish real provider availability, credentials, balance accuracy or Codex tool-loop compatibility for arbitrary endpoints.
- Windows packages remain unsigned. The GUI preview contains fixture data, not live usage information.
- Historical local Mac analysis/preparation files and duplicate generated icons are not required by this release and remain preserved locally.
