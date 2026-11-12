# Changelog

The format follows [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/) and [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Public memberwise initializers on all models.

### Changed
- A write that finds the peer gone throws `.connectionClosed`, not `.transport("send: ...")`, whether or not the
  reader has seen the close yet.
