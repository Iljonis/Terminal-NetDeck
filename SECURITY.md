# Security policy

> **En castellano:** si encuentras un fallo de seguridad, **no abras un issue público**. Avisa en privado desde
> [Security → Report a vulnerability](https://github.com/Iljonis/Terminal-NetDeck/security/advisories/new), con la
> versión, la de macOS y los pasos para reproducirlo, sin datos reales (usa `192.0.2.x`, `tu.usuario`, `core-01`).
> Recibirás respuesta en unos 7 días y el arreglo saldrá en una versión nueva, con tu nombre si quieres.

## Supported versions

Terminal NetDeck is updated often and the app offers each new version itself. Security fixes go into the latest
release only.

| Version | Supported |
|---|---|
| Latest release ([Releases](https://github.com/Iljonis/Terminal-NetDeck/releases/latest)) | ✅ |
| Anything older | ❌ please update (Settings → General → Updates) |

## Reporting a vulnerability

**Please do not open a public issue.** Report it privately through GitHub:
[Security → Report a vulnerability](https://github.com/Iljonis/Terminal-NetDeck/security/advisories/new).

Include, if you can:

- the Terminal NetDeck version (Settings → General) and your macOS version;
- what an attacker could do, and the steps to reproduce it;
- a proof of concept with **sample data only**: `192.0.2.x`, `198.51.100.x`, `203.0.113.x` (RFC 5737),
  `tu.usuario`, `core-01`, `bastion`. Never send real hosts, users, passwords or keys.

What to expect:

- an acknowledgement within about 7 days;
- a fix in a new release as soon as it is ready, published through the app's own updater;
- credit in the release notes and the security advisory, if you want it.

## Scope

Especially welcome:

- passwords leaving the macOS Keychain, reaching the wrong user or device, or showing up in logs or arguments;
- MultiExec or paste reaching a tab it shouldn't (local shell, SFTP, serial) or bypassing the confirmation of
  dangerous commands;
- ssh option injection through session names, hosts, users or imported files;
- the updater accepting anything other than a verified `.dmg` from github.com;
- user files (`ssh_config`, buttons, lists) being overwritten or lost.

Out of scope: vulnerabilities in macOS's own `ssh`, in the devices you connect to, or in a build you modified.

## How the app protects you

The design rules are listed in the README ([Spanish](README.md#seguridad-y-privacidad),
[English](README.en.md#security-and-privacy)). Every change runs a privacy check and the core tests, and a weekly job
audits the dependencies against [OSV.dev](https://osv.dev).
