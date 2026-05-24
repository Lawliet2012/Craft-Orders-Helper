# Releasing CraftOrdersHelper

Releases are created from annotated Git tags. A tag runs the release workflow, which validates the addon, lints Lua, builds a local package smoke test, then publishes the packaged zip to GitHub Releases and CurseForge.

## One-time setup

1. Create the CurseForge project manually and copy its numeric project ID from the project's About box.
2. In GitHub, add a repository variable named `CURSEFORGE_PROJECT_ID` with that numeric ID.
3. In GitHub, add an Actions secret named `CF_API_KEY` with a CurseForge API token. If a token was pasted into chat, an issue, or logs, revoke it and create a fresh token first.
4. In GitHub repository settings, allow GitHub Actions to create releases by giving the workflow token read and write contents permissions.

Do not commit API keys, put them in `.pkgmeta`, or paste them into workflow YAML.

## Release checklist

1. Update `## Version` in `CraftOrdersHelper/CraftOrdersHelper.toc`.
2. Commit the version change.
3. Create an annotated tag whose value matches the TOC version:

   ```bash
   git tag -a v1.4.3 -m "v1.4.3"
   git push origin main --tags
   ```

The release workflow rejects tags that do not match the TOC version.

## Addon packaging notes

- The addon folder and TOC file must both be named `CraftOrdersHelper`.
- The TOC currently targets current Retail/Midnight only. Add more interface/game flavors only after testing those clients.
- Development files are excluded from the shipped package through `.pkgmeta`.
