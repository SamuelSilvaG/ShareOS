# Releasing ShareOS

1. Everything for the release is merged into `main` (CI green).
2. **Docs are up to date in the same merge:**
   - `CHANGELOG.md`: section `## <version>` with the changes (it is attached to the GitHub release automatically)
   - `README.md`: status and feature list
   - `docs/TESTEN.md` / `docs/TESTING.md`: test steps for new functions
   - `docs/ENTWICKLUNG.md` / `docs/DEVELOPMENT.md`: timeline, screenshots
3. On GitHub: *Releases → Draft a new release*, tag `v<version>` (new) on `main`,
   tick **pre-release** for test versions, publish. A short text is enough –
   the CHANGELOG section is appended by the build.
4. GitHub Actions builds the firmware (about 45 minutes) and attaches the
   `.sysupgrade.tar`, `.bin` and checksums. Boxes see the release on their next
   check (every 6 hours) or with *Check now*.

Apps are released from [ShareOS-Apps](https://github.com/UniqueDroid/ShareOS-Apps)
by raising `version` in `apps/<id>/app.json` (see its README).
