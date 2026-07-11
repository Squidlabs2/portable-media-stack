# Bootstrap data

This directory is for automation seed data used to make fresh installs behave like your current working stack without copying full app configs.

Expected local-only export path:
- `bootstrap-data/local/bootstrap-data.json`

What the export contains:
- Prowlarr indexer definitions
- one Sonarr Prowlarr application template
- one Radarr Prowlarr application template
- Sonarr SABnzbd download client template
- Radarr SABnzbd download client template

Why it is local-only:
- it can contain API keys and indexer credentials
- it should not be committed to a public repo

Typical workflow:
1. On the current working machine, run `./scripts/export-bootstrap-data.sh`
2. Copy `bootstrap-data/local/bootstrap-data.json` to the new machine or create it there
3. Set `AUTO_APPLY_BOOTSTRAP_DATA=true` in the new stack's `.env`
4. Run `./scripts/install.sh`

You can also apply it manually after install:
- `./scripts/apply-bootstrap-data.sh`
