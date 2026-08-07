# Security Policy

## Never commit credentials

This project does not need API keys in any tracked file. Store provider keys in
Windows user environment variables only:

- `HONKNET_API_KEY`
- `DEEPSEEK_API_KEY`

Do not commit or share these files from `%USERPROFILE%\.codex`:

- `auth.json`
- `config.toml` when it contains an inline token
- `provider-switch-backups\`
- audit logs, screenshots, or terminal output containing credentials

## If a key was exposed

1. Revoke it immediately at the provider.
2. Create a replacement key.
3. Update the Windows user environment variable.
4. Remove the secret from Git history; deleting only the latest file is not enough.

## Reporting a vulnerability

Open a GitHub issue without including credentials or private configuration.
