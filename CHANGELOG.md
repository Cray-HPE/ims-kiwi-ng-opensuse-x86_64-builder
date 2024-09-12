# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]
### Dependencies
- Resolves CVEs
  - Moved Docker base image from OpenSUSE 15.4 to 15.6
  - Updated `xalan-j2` package to >= 2.7.3

## [1.8.1] - 2024-07-25
### Dependencies
- Bumped `certifi` from 2019.11.28 to 2023.7.22 to resolve CVE

## [1.8.0] - 2024-05-20
### Added
- CASMCMS-8976 - add new DST signing key to recipe build process.

## [1.7.0] - 2024-03-01
### Changed
- CASMCMS-8795 - Updated for remote builds.
- CASMCMS-8818 - ssh key injection into jobs.
- CASMCMS-8897 - changes for aarch64 remote build.
- Hotfix for ims-python-helper version bump.

## [1.6.0] - 2023-09-15
### Changed
- Disabled concurrent Jenkins builds on same branch/commit
- Added build timeout to avoid hung builds
- CASMCMS-8801 - changed the image volume mounts to ude PVC's instead of ephemeral storage.

### Dependencies
- CASMCMS-8722: Use `update_external_versions` to get latest patch version of `ims-python-helper` Python module.
- Bumped dependency patch versions:
| Package                  | From     | To       |
|--------------------------|----------|----------|
| `boto3`                  | 1.12.9   | 1.12.49  |
| `botocore`               | 1.15.9   | 1.15.49  |
| `jmespath`               | 0.9.4    | 0.9.5    |
| `python-dateutil`        | 2.8.1    | 2.8.2    |
| `s3transfer`             | 0.3.0    | 0.3.7    |
| `urllib3`                | 1.25.8   | 1.25.11  |

## [1.5.6] - 2023-07-11
### Changed
- CASMCMS-8708: Rework multi-image build to include build metadata for nightly rebuilds.

## [1.5.5] - ????
### Changed
- CASMCMS-8590: pull base images from algol60.

## [1.5.4] - 2023-06-15
### Changed
- CASM-8590: Utilize artifactory image for Dockerfile 

## [1.5.3] - 2023-06-18
### Changed
- CASM-4232: Require at least version 2.14.0 of `ims-python-helper` in order to get associated logging enhancements.

## [1.5.2] - 2023-05-18
### Changed
- CASMCMS-8566 - utilize podman vfs storage driver for kata runtime

## [1.5.1] - 2023-05-16
### Changed
- CASMCMS-8365 - tweaks to get arm64 recipes to build.

## [1.5.0] - 2023-05-03
### Added
- CASMCMS-8366 - add support for arm64 to the docker image.
- CASMCMS-8459 - more arm64 support.
- CASMCMS-8595 - rename platform to arch, fix permissions.

### Removed
- Removed defunct files leftover from previous versioning system

## [1.4.2] - 2022-12-20
### Added
- Add Artifactory authentication to Jenkinsfile

## [1.4.1] - 2022-12-02
### Added
- Authenticate to CSM's artifactory

## [1.4.0] - 2022-08-02
### Changed
- CASMCMS-7970 - update dev.cray.com addresses.

## [1.3.0] - 2022-06-29
### Changed
- Updated ims-python-helper to require v2.9.0 or above.

## [1.0.0] - (no date)
