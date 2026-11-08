# Changelog

All notable changes to Terminal NetDeck are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). Downloads are on the
[Releases page](https://github.com/Iljonis/Terminal-NetDeck/releases).

> **En castellano:** este es el historial de cambios de cada versión. Las novedades de la versión actual están
> también, en castellano, al principio del [README](README.md). Cada versión enlaza a sus cambios en GitHub.

## [Unreleased]

## [1.0.0] - 2026-11-08

### Added
- Liquid Glass is the default theme for new users (Liquid Glass Light in automatic mode); the setup assistant suggests
  the classic NetDeck neon themes separately. Existing users keep their theme, even if they never picked one.
- macOS 26 Liquid Glass on toolbar buttons, tabs, the «+» menu and chips (never over the terminal; selected and active
  items stay opaque for contrast).
- Accessibility: opaque themes with «Reduce transparency» / «Increase contrast», VoiceOver labels and button traits for
  tabs, sessions and folders, keyboard navigation in themed menus, status dot shapes with «Differentiate without colour».
- ⌘1…⌘9 to jump to a tab; ⌘Q asks about unsaved Settings.
- Demo cases for the paste review sheet, Settings → Paste and the Liquid Glass themes.
- CHANGELOG, contributing guide, code of conduct, security policy, issue and PR templates, social preview image.

### Changed
- The terminal reads only the screen and new rows instead of the whole scrollback (Return with 100,000 lines:
  ~250 ms → under 1 ms; leaving vi/less/tmux no longer rereads the scrollback).
- Swift 6.2 with approachable concurrency: SFTP copies, MD5 and remote edits run off the main thread (`@concurrent`).
- SwiftTerm 1.99.3, swift-png 4.5.2, `actions/upload-artifact` v7.
- The themes' orange is computed to be a real orange with WCAG contrast.
- Favourites are saved with a backup; recents are capped; log search streams grep output with a limit.

### Fixed
- The paste review copies exactly the pasted text (the ⚠ marks live in a ruler).
- The SFTP panel resize cursor no longer sticks; a button password with a newline is rejected.

## [0.9.13] - 2026-11-08

### Fixed
- «Update now» no longer gets stuck when GitHub answers `504 Gateway Time-out` on the usual `.dmg` link: it only
  accepts an HTTP 200 and falls back to the GitHub API asset download, still checking the published sha256, the app
  id, the version and the signature. Users on 0.9.11 or 0.9.12 install 0.9.13 by hand once.

## [0.9.12] - 2026-11-07

### Added
- **Review before pasting:** pasting more than 3 lines (or anything with dangerous commands) opens a window to review
  the text. Return pastes it whole, in one go; Esc cancels. Turn it off or change the line count in
  Settings → Terminal → Paste. It does not show up while the device is asking for a password.
- **Colours show their real name:** in Settings and in the rule editor, each colour shows the name of the colour you
  actually see in the theme, with its swatch.

### Changed
- **Safer MultiExec and buttons:** a `reload`, `clear ip bgp *` or `write erase` typed with MultiExec asks before it
  goes to several tabs, and buttons with dangerous commands ask for confirmation.
- **Better dangerous-command detection:** commands are checked from their start and without the prompt, including IOS
  abbreviations (`reloa`, `wr er`, `shu`) and Junos, Huawei, Nokia SR-OS and Linux commands. `show`, `no shutdown`,
  `clear counters` and `clear ip bgp * soft` no longer ask.
- **Finer highlighting:** IOS error counters in red only when not 0, BGP `Active`/`Idle` in red, intentional shutdowns
  (`administratively down`, `Idle (Admin)`) in grey, IOS-XR and Huawei syslog, more interface types and fewer false
  positives. The interface rule is up to 5 times faster.

## [0.9.11] - 2026-11-04

### Added
- **One-click unlock:** when the default password is locked, **🔒 “…” · Unlock** shows in the bottom bar.

### Changed
- **A device without your user no longer locks you out:** if the password got in less than 5 minutes ago and another
  device rejects it, it is not locked; you type it that one time. Device lists still lock on the first rejection.
- No offer to save the password of an `ssh` started from inside a session (jump hops).
- Password notices at the top right disappear after 20 seconds without interrupting the login.

## [0.9.10] - 2026-10-31

### Changed
- **Smooth typing:** each key no longer re-reads the whole scrollback; with 2,500 lines the echo drops from 16–30 ms
  to about 3 ms.
- ⌘Q asks when connections are open.

### Fixed
- Return no longer presses “Overwrite” or “Quit”, and Esc no longer accepts a changed host key.
- With Settings open, typing no longer reaches the device underneath (or MultiExec).
- Reopened windows no longer end up under the Dock; a button password keeps its spaces.

## [0.9.9] - 2026-10-30

### Added
- **Group submenus in “+”:** hover a folder to open one of its sessions, or **Open all**.

### Fixed
- **More reliable autopass:** copes with a full scrollback, `clear`, the alternate screen of tmux, screen, less or vi
  and dropped connections; a lone Esc no longer eats the next key.
- Askpass: Return saves, it always says whether the password was saved, and a Keychain error is no longer taken as
  “not there”.

## [0.9.8] - 2026-10-27

### Added
- **Passwords like SecureCRT:** one list of named passwords, picked by name in sessions, groups, buttons and device
  lists, with **New…** next to every selector.
- **Save it?** If you type a password yourself and get in, the app offers to save it in the Keychain.
- **Buttons with the password written in:** typed only at “Password:”, never shown or logged, left out when exporting.

### Changed
- Device lists retry once the devices left at the jump host before any password prompt.

### Removed
- Third-party SSH dependencies: the app only uses macOS's own `ssh`.

## [0.9.7] - 2026-10-27

### Changed
- Password and login buttons and the 🔑 menu also type while the session is connecting.
- Command buttons type nothing at a password prompt and say why.
- Split view: the keyboard stays on the pane you click.
- **The 15-minute block applies only to the default password** auto-typed after ssh/telnet from a session.

## [0.9.6] - 2026-10-27

Includes the work of the unreleased 0.9.4 and 0.9.5.

### Added
- **Multiple windows:** ⌘N opens another; tabs move between windows without dropping the connection.
- Rename a tab; export and import buttons (passwords never travel).
- Editable credential manager and a searchable Keychain catalogue.

### Changed
- Autopass recognises SSH/Telnet commands picked from history or with Tab; a `show run` or banner cannot start a login.
- Keychain access runs in the background.
- Saved sessions use their own password and each jump host's without waiting for other tabs.

### Fixed
- Full screen: the top gap and the tab bar covering the first terminal line.

## [0.9.3] - 2026-10-21

Includes the features of 0.9.2, which was withdrawn.

### Added
- **SFTP beside the SSH terminal**, same host and jumps.
- **Remote editing** of text files up to 5 MB with conflict checks.
- **Workspaces**, **macros**, **SSH tunnels** (`-L`, `-R`, `-D`) and **per-session profiles** (`# @tema`, `# @fuente`,
  `# @prompt`…).
- **Native serial console** with BREAK.

### Fixed
- Tab mouse handling (select, close and drag) that 0.9.2 had broken.
- Keychain passwords with ñ, €, º, accents or `\` were typed wrong.
- Validation of the distributed `.app`, not just the local build.

## [0.9.2] - 2026-10-20 [WITHDRAWN]

Withdrawn: tabs could not be selected or closed with the mouse. Fixed in 0.9.3.

## [0.9.1] - 2026-10-19

### Added
- Rectangular selection (⌥ + drag) and configurable scrollback.
- Backup of sessions before every update, and recovery if the sessions file or its `Include` goes missing.

## [0.9.0] - 2026-10-17

### Added
- Nokia SR-OS highlighting (classic and MD-CLI prompts, ports, alarms) and highlight colours per theme.
- Users with their own rules can add each release's new built-in rules with one click.

## [0.8.12] - 2026-10-16

Nested right-click menus no longer lose the click. Earlier 0.8 releases (0.8.1 – 0.8.11, 2026-10-14 to 2026-10-16)
added the SFTP/FTP browser with atomic copies, MD5 checks, moves on the server and server-to-server copies; adaptive
tabs titled with just the destination; a shared jump-host connection; hardened session import; and the bundled
third-party licences.

## [0.7.0] - 2026-10-14

PuTTY-style mouse, sessions as a tree and one-click updates. 0.7.1 – 0.7.4 fixed the first-run assistant, accented
banners over ssh and drag-to-reorder for tabs and buttons.

## [0.6.0] - 2026-10-14

Paths shown with `~`, private permissions (0700/0600) for the app's data, and documentation.

## [0.5.0] - 2026-10-13

First public release: background update checks (never installs without a click), standard `.dmg` install and
rejection of names, hosts and users starting with `-`.

[Unreleased]: https://github.com/Iljonis/Terminal-NetDeck/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/Iljonis/Terminal-NetDeck/compare/v0.9.13...v1.0.0
[0.9.13]: https://github.com/Iljonis/Terminal-NetDeck/compare/v0.9.12...v0.9.13
[0.9.12]: https://github.com/Iljonis/Terminal-NetDeck/compare/v0.9.11...v0.9.12
[0.9.11]: https://github.com/Iljonis/Terminal-NetDeck/compare/v0.9.10...v0.9.11
[0.9.10]: https://github.com/Iljonis/Terminal-NetDeck/compare/v0.9.9...v0.9.10
[0.9.9]: https://github.com/Iljonis/Terminal-NetDeck/compare/v0.9.8...v0.9.9
[0.9.8]: https://github.com/Iljonis/Terminal-NetDeck/compare/v0.9.7...v0.9.8
[0.9.7]: https://github.com/Iljonis/Terminal-NetDeck/compare/v0.9.6...v0.9.7
[0.9.6]: https://github.com/Iljonis/Terminal-NetDeck/compare/v0.9.3...v0.9.6
[0.9.3]: https://github.com/Iljonis/Terminal-NetDeck/compare/v0.9.1...v0.9.3
[0.9.2]: https://github.com/Iljonis/Terminal-NetDeck/compare/v0.9.1...v0.9.3
[0.9.1]: https://github.com/Iljonis/Terminal-NetDeck/compare/v0.9.0...v0.9.1
[0.9.0]: https://github.com/Iljonis/Terminal-NetDeck/compare/v0.8.12...v0.9.0
[0.8.12]: https://github.com/Iljonis/Terminal-NetDeck/compare/v0.7.4...v0.8.12
[0.7.0]: https://github.com/Iljonis/Terminal-NetDeck/compare/v0.6.0...v0.7.4
[0.6.0]: https://github.com/Iljonis/Terminal-NetDeck/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/Iljonis/Terminal-NetDeck/releases/tag/v0.5.0
