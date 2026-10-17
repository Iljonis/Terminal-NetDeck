<div align="center">

# Terminal NetDeck

**The macOS terminal for people who live among routers, switches and jump hosts.**

Sessions with jump hosts, passwords that never end up on the wrong device, MultiExec, an SFTP/FTP browser
and 51 themes. Native, fast and in your language.

[![Download for macOS](https://img.shields.io/badge/Download-Terminal--NetDeck.dmg-ff2e88?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/Iljonis/Terminal-NetDeck/releases/latest)

Current version: **[v0.9.0](https://github.com/Iljonis/Terminal-NetDeck/releases/tag/v0.9.0)** · macOS 15 or later ·
free and open source

[![Tests](https://github.com/Iljonis/Terminal-NetDeck/actions/workflows/tests.yml/badge.svg)](https://github.com/Iljonis/Terminal-NetDeck/actions/workflows/tests.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138.svg?logo=swift&logoColor=white)](https://www.swift.org)
[![macOS 15+](https://img.shields.io/badge/macOS-15%2B-000000.svg?logo=apple&logoColor=white)](https://www.apple.com/macos/)

[Español](README.md) · **English**

![Terminal NetDeck](docs/capturas/portada-en.png)

</div>

## Why Terminal NetDeck

If you run a network, your day means opening twenty sessions behind a jump host, typing the same password again and
again, pasting configs while dreading a `reload`, and moving files between servers. Terminal NetDeck brings all of
that into one macOS app, built around one idea: **it should never play a trick on you.**

- Your sessions are the ones in your `ssh_config`: `ssh core-01` keeps working from any other terminal.
- Passwords live only in the Keychain and are only typed for the user and the device that really ask for them.
- When something goes wrong (a password fails, a server stops answering, a copy breaks off), the app stops, tells
  you, and never leaves anything half done.

## Install in two minutes

1. **Download** `Terminal-NetDeck.dmg` from the [latest release](https://github.com/Iljonis/Terminal-NetDeck/releases/latest).
2. **Open it** and drag **Terminal NetDeck** to **Applications**.
3. **The first time**, right-click the app → **Open** (it isn't signed by Apple, so macOS asks just once).
4. The setup assistant walks you through it: where your sessions are, theme, font, passwords and highlighting.

Your data stays on your Mac: settings in `~/Library/Application Support/Terminal NetDeck/`, sessions in `ssh_config`
format and passwords only in the macOS Keychain.

![Setup assistant](docs/capturas/asistente.png)

### Keeping it up to date

- **From the app itself.** Once a day it quietly checks for a new version. If there is one, a discreet notice shows
  up in the status bar: click **Update now** and it downloads, verifies it (the sha256 GitHub publishes, plus its
  signature) and reopens with your tabs. Nothing is ever installed without that click.
- **From the source, in a moment:**

  ```bash
  cd Terminal-NetDeck
  git pull
  ./actualizar.sh        # builds, replaces the app and reopens it with your tabs
  ```

<details>
<summary><b>Install from source</b> (macOS 15+ and Swift 6)</summary>

```bash
xcode-select --install          # if you have neither Xcode nor the Command Line Tools
git clone https://github.com/Iljonis/Terminal-NetDeck.git
cd Terminal-NetDeck
./install.sh                    # builds it and installs it in /Applications (or ~/Applications)
```

| Command | What for |
|---|---|
| `./install.sh --usuario` | Install it in `~/Applications` |
| `./install.sh --dmg` | Build `dist/Terminal-NetDeck.dmg` |
| `./install.sh --asistente` | Open the setup assistant without installing (to try it) |
| `./install.sh --fuente "Kode Mono"` | Install a font with Homebrew |
| `./desinstalar.sh [--todo]` | Remove the app (`--todo`: themes and settings too; the Keychain is never touched) |

</details>

## What it does for you

### 🔐 Passwords that never go to the wrong place

- **Only in the macOS Keychain:** never in files, arguments or logs.
- **Strict user rule:** a password is only typed automatically when it belongs to exactly the user being asked for.
- **And the right device:** a server that prints a fake `admin@core-01's password:` doesn't get core-01's password;
  only that tab's destination and jump hosts count.
- **A failed password is locked for 15 minutes in every tab**, so your Active Directory account doesn't get locked out.
- **The Keychain never freezes the app:** it's read in the background, with a 10-second limit.
- 🔑 menu to type any of them by hand, even at odd prompts the app doesn't recognise.

### 🛡️ Jump hosts without surprises

- Your sessions with chained `ProxyJump`, and telnet through the jump host.
- **A single connection to the bastion:** tabs that go through the same jump host share it (like SecureCRT; kept
  open for 2 min after the last one closes) and don't authenticate on it again. Turn it off in Settings → General → Connections.
- **Hardened manual hop:** if a jump host refuses forwarding (`-J`), the app asks before logging into it, and the
  destination password is only suggested, never typed automatically through the jump host's shell.
- **No injections:** a host or user starting with `-` never reaches ssh as an option, every command puts `--` before
  the destination, and imported sessions only keep safe ssh options (no `ProxyCommand`, no `Host *` blocks, no port
  forwarding…).

### 📂 An SFTP/FTP browser that never loses files

- Tree and list with sizes, permissions, owner and date; upload by dragging from the Finder, download, rename, delete.
- **Atomic copies:** files are written to a temporary file first and only replace the real one at the end. A copy that
  fails or that you cancel never leaves anything half written nor deletes the original, and its permissions are kept.
- **MD5 integrity:** each file is read back from the destination and its MD5 must match the source's.
- **Server to server** ("Send to…"), SFTP ↔ SFTP or SFTP ↔ FTP, in memory and without touching the Mac's disk.
- **Cancel is instant**, and a server that stops answering is cut off after 30 seconds instead of hanging the window.

![SFTP browser in split view](docs/capturas/explorador.png)

### ⚡ Working on many devices at once

- **MultiExec** and **split view:** what you type goes to several panes at once (exclude the ones you want).
- **Safe paste:** line by line, waiting for the prompt; it stops on CLI errors, pagers, unconfirmed dangerous commands
  (`reload`, `delete`…) or a password prompt.
- **Device lists:** the same command on many devices behind a jump host, trying the password one device at a time.
- **Button bar** with categories, F1–F12 keys and placeholders like `{{vlan=100}}`.

### 🗂️ Tabs that adapt

- They share the window's width and, when they don't fit, scroll while keeping the active one in view.
- The title is just the **destination device** (`core-02`, not `core-02 ⟵ bastion`); the full path shows on hover.
  If you hop from a session to another device, the tab shows it.
- The bar's buttons never get pushed out of the window, however many tabs you have.

![Adaptive tabs](docs/capturas/pestanas.png)

### 🧰 And also

- **Session types:** SSH, Telnet, SFTP, FTP, local shell and serial console (`screen`).
- **Session manager** with folders (`Clients/Madrid/Core`), favourites, recents and a **Connect** button to try one
  without saving.
- **Import** from SecureCRT, MobaXterm, PuTTY, electerm, CSV or another `ssh_config`; **export** to JSON or CSV.
  Never passwords.
- **ChromaTerm-style output highlighting** (IPs, MACs, interfaces, states, BGP, dBm, errors…) for Cisco, Juniper,
  Huawei, Nokia SR-OS (classic and MD-CLI prompts, `1/1/c1/1` ports, alarms) and Linux, in the theme's colours,
  editable with a live preview. You can pick the shade of each highlight colour, per theme, without touching the
  interface; if you have your own rules, each release's new ones are added with one click.
- **Session logging** to clean text and **search** across all logs (IPs, MACs in any format…).
- **No locale warnings** on Linux servers: ssh doesn't send the Mac's language unless you turn it on.
- **Spanish (Spain) and English**, switched instantly in Settings → General → Language.

![Output highlighting](docs/capturas/resaltado.png)

## 🎨 51 themes for every shift

From a 3 a.m. NOC shift to a presentation on a projector. Each one has its ANSI palette and font, can **follow the
Mac's light or dark mode**, and **every theme passes a WCAG contrast test** (text ≥ 4.5:1). Want your own? Copy a
`.tema` file from `Temas/`, change the colours and import it. There's also the built-in one, **NetDeck Cyberpunk**.

![Theme gallery](docs/capturas/temas.png)

<details>
<summary><b>See the full catalogue</b></summary>

| Group | Theme | What it looks like |
|---|---|---|
| **Cyberpunk** | **Cyber Neón** | Electric yellow, cyan and neon red on black. |
|  | **Corpo rojo** | Black, corporate red and white. Understated, with kanji labels. |
|  | **Neo-Tokyo** | Japanese cyberpunk: deep indigo, magenta and cyan. |
|  | **Synthwave** | Retrowave sunset: pink, violet and orange. |
|  | **Grid** | Pure black with electric cyan and orange (Tron style). |
|  | **Vaporwave** | Turquoise and pastel pink on violet, nineties aesthetic. |
| **Systems** | **Liquid Glass** | Like macOS 27: transparent, blurred glass with the system colours. |
|  | **Liquid Glass Claro** | macOS 27 by day: light blurred glass, crisp dark text. |
|  | **Windows 11** | Fluent and Mica: translucent dark grey, blue accent, Cascadia Mono and the Campbell palette. |
|  | **Windows 11 Claro** | Fluent by day: light Mica, blue accent and the "One Half Light" palette. |
| **Anime & film** | **Unidad-01** | Purple and neon green, warnings in orange (EVA-01 style). |
|  | **Unidad-02** | Intense red and orange with lime green (EVA-02 style). |
|  | **Neo-Tokio rojo** | Motorbike red, black and white with kanji (Akira style). |
|  | **Fantasma rojo** | Red, black and white with brutal contrast (Persona 5 style). |
|  | **Replicante** | Orange haze and petrol blue (Blade Runner style). |
|  | **Sección 9** | Sea green and white on slate (Ghost in the Shell style). |
|  | **Bosque** | Moss greens, sky and warm tones (Ghibli style). |
|  | **Andén** | Orange LED board of a Japanese train station. |
| **Kawaii** | **Kawaii futurista** | Dark lavender, pink, mint and lilac. ♡ ✧ touches. |
|  | **Sakura** | Light and soft, for a white background. |
|  | **Alba rosa** | Light dawn tones: cream, old rose, iris and pine (inspired by Rosé Pine Dawn). |
| **Retro** | **Fósforo** | Classic green phosphor monitor. |
|  | **Ámbar** | 80s amber terminal, warm for long hours. |
|  | **Otoño retro** | Warm with little blue, inspired by Gruvbox: good for night work. |
|  | **Monokai** | The editor classic: bright green, yellow and pink on olive grey. |
|  | **Trigo** | Cream paper with toasted ink (inspired by Gruvbox light): daytime partner of Otoño retro. |
| **Subdued** | **Ártico** | Understated but contrasted: ice, aurora and amber. |
|  | **Medianoche** | Soft blues and violets (Tokyo Night style). |
|  | **Vampiro** | Purple, pink and green on grey (Dracula style). |
|  | **Océano profundo** | Abyssal blue with aquamarine and coral highlights. |
|  | **Grafito** | Charcoal grey instead of black: no glare when switching from a light window. |
|  | **Solar oscuro** | The classic Solarized palette, dark: easy on the eyes for long shifts. |
|  | **Solar claro** | Solarized light: partner of Solar oscuro (ideal in Auto mode). |
|  | **Moca** | Soft pastels on a dark background, inspired by Catppuccin Mocha. |
|  | **Fiordo** | Arctic slate grey with frost blues (inspired by Nord): calm for long shifts. |
|  | **Café con leche** | Light and creamy (inspired by Catppuccin Latte): daytime partner of Moca. |
|  | **Gran ola** | Indigo ink, aged paper and Japanese woodblock blues (inspired by Kanagawa). |
|  | **Taiga** | Muted forest green with sage, sand and moss (inspired by Everforest). |
| **Practical** | **Accesible** | For colour blindness: good in blue, bad in orange. |
|  | **Alto contraste** | Pure white on black and colours at full strength. |
|  | **Pro** | macOS Terminal's "Pro" profile. |
|  | **Papel** | Light and very readable: bright offices, projectors or screen sharing. |
|  | **NOC** | For on-call screens: normal things muted, alarms jumping out. |
|  | **Guardia ámbar** | NOC console: amber on warm black, large type and unmistakable states. |
|  | **Guardia verde** | NOC console: soft green on black, alarms in red and warnings in amber. |
| **Corporate** | **DIGI** | DIGI Mobil blue (#1275B7) and the logo's red dot, on navy. |
|  | **Oracle** | Oracle red (#C74634) on Redwood's warm grey (#312D2A). |
|  | **Cisco** | Cisco blue (#049FD9) on night blue, with Cisco's status colours. |
|  | **Juniper** | Juniper green (#84B135) and lime (#CCDB2A) on slate grey. |
|  | **Huawei** | Huawei red (#CF0A2C) and its black (#232527). |
|  | **Ubuntu** | Ubuntu orange (#E95420) on aubergine (#300A24), like its terminal. |

</details>

## Gallery

| | |
|---|---|
| ![Home](docs/capturas/portada-en.png) **Home:** your sessions one click away, plus quick connect | ![Browser](docs/capturas/explorador.png) **SFTP browser** in split view |
| ![Themes](docs/capturas/temas.png) **Theme gallery** with live preview | ![Highlighting](docs/capturas/resaltado.png) **Editable highlighting rules** |
| ![Settings](docs/capturas/ajustes-en.png) **Settings** | ![Assistant](docs/capturas/asistente.png) **First-run assistant** |

![Adaptive tab bar](docs/capturas/pestanas.png)

## Shortcuts

| Shortcut | What it does |
|---|---|
| ⌘K | Connect (a session or `user@host[:port]`, direct or through a jump host) |
| ⌘T | New local terminal |
| ⌥⌘K | Open the startup session |
| ⇧⌘E | Session manager |
| ⇧⌘L | Device lists |
| ⇧⌘V | Safe paste |
| ⇧⌘M | MultiExec |
| ⌘F / ⇧⌘F | Find in the output / in all logs |
| Esc or ⌘. | Stop any automated sequence |
| ⌘, | Settings |

## Security and privacy

- Passwords only in the Keychain, with the user and device rules, and a 15-minute lock after a failure.
- MultiExec and safe paste only reach SSH/Telnet tabs: never a local terminal, SFTP or serial console.
- Your files (`ssh_config`, buttons, lists) are never overwritten when they can't be read, with a `.anterior` backup on
  every save; the app's folders and files are for your eyes only (0700/0600).
- Updates only from github.com, checked against their sha256 and signature, and nothing is installed without your click.
- Ad hoc signature with the hardened runtime.
- Every change goes through a privacy check (nothing personal in the code, the app or the `.dmg`) and, every week, a
  dependency audit against the OSV.dev vulnerability database.
- Errors go to `~/Library/Application Support/Terminal NetDeck/logs/error.log` (Help → Open the error log), never with
  passwords.

## For developers

```bash
swift build
swift run TerminalNetDeck -idioma en   # in English
./test.sh                              # privacy check + core tests
tools/capturas.sh                      # regenerates docs/capturas with sample data
tools/verificar_demo.sh                # functional pass on the demo before a commit or tag
```

| Module | Contents |
|---|---|
| `NetDeckCore/Sessions` | `ssh_config`, jump hosts, `ssh -J`, telnet through the jump host, importers |
| `NetDeckCore/Security` | Keychain, askpass, user rule, shared lock after a failure |
| `NetDeckCore/Remote` | SFTP and FTP, atomic copies with MD5, server to server |
| `NetDeckCore/Productivity` | Safe paste, MultiExec, device lists through a jump host, button bar |
| `NetDeckCore/Highlight` · `Themes` | ChromaTerm-style highlighting · `.tema` format and catalogue |
| `NetDeckCore/Support` | Paths, logs, updates, languages (`L("…")` + `Ingles.swift`) |
| `TerminalNetDeck` | The app (SwiftUI) |
| `Temas/` · `Resaltado/` | Theme catalogue and highlighting rules |

The code is written in Spanish (Spain) and the interface is translated into English. The project conventions
(translatable strings, sample data, passwords, security) and how review agents are used are in
[CLAUDE.md](CLAUDE.md). Tests run on GitHub Actions on every push.

## License

[MIT](LICENSE) © 2026 Jonay / Iljonis. Built with Swift 6, SwiftUI and [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm).
Dependency licences and colour-palette attributions are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), which
also ships inside the app.

## Trademarks

Cisco, Oracle, Juniper, Huawei, DIGI, Ubuntu, Apple, macOS, Liquid Glass, Microsoft, Windows and every other company,
product, work or palette name mentioned in this project are trademarks of their respective owners. They are cited only
to describe colour combinations or compatibility (for example, "inspired by" or "style"). Terminal NetDeck is an
independent project: it is not affiliated with, sponsored or endorsed by any of them, and it includes none of their
logos or official assets.
