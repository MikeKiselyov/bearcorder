# Contributing

Changes go to `main` only through pull requests, and every pull request that changes the app is a
new release:

1. Work in a branch.
2. Add a release on top of `Sources/AppCore/Support/WhatsNewCatalog.swift` with the next id and a
   higher version: a patch (`0.5.1`) for fixes, a minor (`0.6.0`) for new features. Write the items
   for people, the way they appear in "What's new". The app's version comes from this entry.
3. Open a pull request. [CI](.github/workflows/ci.yml) checks that the release is there
   (`scripts/check/release.sh origin/main`), runs the unit tests and the self-test. Changes only to
   docs or CI need no release.
4. After the merge CI tags the commit `v<version>` and publishes a GitHub release with the same notes.
   Installed apps see the new version within 6 hours.

The suites that need permissions (`e2e`, `features`, `perf`) can't run on GitHub's Macs; run
`scripts/test/all.sh` before opening the pull request.


More for developers:

- [Build from a clone, signing, project layout](docs/development.md)
- [Tests and checks](docs/testing.md)
