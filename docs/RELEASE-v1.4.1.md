# v1.4.1 Windows bug fixes

Display version: `V_1.4_261026.01`.

- Explain the unique ID as a user-chosen internal route code, with `my-api` as an example and length/character/uniqueness guidance.
- Label the model field as model ID and instruct users to copy the real ID from their provider's model list. Both connection protocols and route configuration preserve that ID.
- Make the environment variable name optional. If present, read only that variable from Process, User or Machine, in that order. A missing/empty variable is an error, never a fallback to a pasted key. The direct-key input is disabled while a variable name is present, and saving never overwrites a named variable.
- Without a variable name, use the pasted API key. Save it under an automatically managed, per-route Windows user variable. Metadata contains only the variable reference and `credential_source=api_key`. Saved direct-key routes can be tested again without exposing or re-entering the key, and can switch from a fresh process.
- Keep existing environment-based routes compatible. Changing credentials or protocol, or failing a repeated test, disables saving and switching until a successful test.

## Verification

- Windows PowerShell 5.1 built-in/custom routing, registry round trips and config backup tests pass.
- Credential regression covers environment plus key, variable missing with a key present, both missing, direct-key save/reload/fresh-process switch, collision-resistant generated names, exact model IDs, and no secret values in JSON/TOML. Persistent writes are mocked in this test.
- The real WinForms editor is constructed and rendered. Mock HTTP requests confirm the expected credential and exact model ID for both `/responses` and `/chat/completions`; no real provider is contacted. Field hints, masked keys, bounds, input enablement and test invalidation are checked.
- EXE/ZIP package integration checks installation/uninstallation, installed/source hashes, portable status and preservation of existing configuration/credentials.
- MSIX static/compilation checks and Mac Python logic tests remain part of regression. GitHub Actions records CI results for this commit.

## Scope

This is a Windows bug-fix release; macOS stays on v1.3. No live-provider compatibility or balance claim is made by the offline tests. The EXE remains unsigned.
