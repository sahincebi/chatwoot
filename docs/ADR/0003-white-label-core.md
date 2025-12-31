# 0003 White Label Core

Date: 2025-12-27
Status: Accepted

## Context
The fork needs install-level white-label support that is driven by env variables and not hardcoded Chatwoot strings.
Key user-facing surfaces include login, manifest metadata, and outbound mailer defaults.

## Decision
- Add a BrandingConfig helper to read branding keys from ENV first and fall back to InstallationConfig.
- Introduce app title, manifest name/short name, and favicon URL as install-level config.
- Serve /manifest.json dynamically from Rails using BrandingConfig.
- Replace high-visibility Chatwoot strings with %{brand_name} interpolation in EN/TR and in mailer templates.

## Consequences
- Branding can be controlled from env without editing code.
- The manifest file is no longer a static public asset.
- Instances should set MAILER_SUPPORT_EMAIL and MAILER_SENDER_EMAIL to avoid generic defaults.
