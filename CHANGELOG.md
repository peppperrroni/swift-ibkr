# Changelog

The format follows [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/) and [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Public memberwise initializers on all models.
- iOS 16 as a supported platform, next to macOS 13.
- CI on every push and pull request: tests on macOS, Linux (Swift 6.0 and the latest) and Windows, and an iOS build.

### Changed
- A write that finds the peer gone throws `.connectionClosed`, not `.transport("send: ...")`, whether or not the
  reader has seen the close yet.
