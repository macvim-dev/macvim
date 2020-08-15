# Release Checklist

- Update the version in `create-dmg`'s `pure_version` function
  - Remove the "-SNAPSHOT" suffix
- Commit
- Tag the release as `vX.X.X`
- `git push --tags`
- Create a release on the GitHub project page
- Open development on the next release
  - Bump the version number and add a "-SNAPSHOT" suffix to it
