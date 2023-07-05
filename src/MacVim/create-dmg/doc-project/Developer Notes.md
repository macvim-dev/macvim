# create-dmg Developer Notes

## Repo layout

- `create-dmg` in the root of the repo is the main program
- `support/` contains auxiliary scripts used by `create-dmg`; it must be at that relative position to `create-dmg`
- `builder/` contains ????
- `examples/` contains user-facing examples
- `tests/` contains regression tests for developers
- `doc-project/` contains developer-facing documentation about this project

### tests/

The `tests/` folder contains regression tests for developers.

Each test is in its own subfolder.
Each subfolder name should start with a 3-digit number that is the number of the corresponding bug report in create-dmg's GitHub issue tracker.

The tests are to be run manually, with the results examined manually.
There's no automated script to run them as a suite and check their results.
That might be nice to have.

### examples/

Each example is in its own subfolder.
The subfolder prefix number is arbitrary; these numbers should roughly be in order of "advancedness" of examples, so it makes sense for users to go through them in order.

## Versioning

As of May 2020, we're using SemVer versioning.
The old version numbers were 4-parters, like "1.0.0.7".
Now we use 3-part SemVer versions, like "1.0.8".
This change happened after version 1.0.0.7; 1.0.8 is the next release after 1.0.0.7.

The suffix "-SNAPSHOT" is used to denote a version that is still under development.
