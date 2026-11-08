# Plan de trabajo 1.0.x

Listado para ir trabajando después de la 1.0.0. Sale de cuatro estudios de agentes (fuentes, temas Neon Glass, colores
a medida e ideas frente a otras apps) y de los puntos menores de la revisión de la 1.0.0, comprobados contra el
código el 2026-11-08. Esfuerzo: S (horas) · M (1-2 días) · L (más). Se marca con [x] lo que se haga.

## 1.0.1 — Fuentes: lo rápido y lo que falla

- [x] **El tamaño confunde y deja poner 1-7 pt.** Ajustes → Fuentes tiene un deslizador de 0 a 26 (0 = el del tema) y
      el terminal usa «tamaño del tema − 1»; `# @fuente` sólo acepta 8-36. Que vaya de 8 a 36, que enseñe el tamaño
      real y que la celda se mida por carácter, como SwiftTerm (la «W» por nombre de glifo descuadra con CJK).
      `SettingsView.swift` (Tamaño), `AppModel.terminalFont`, `TerminalSession.cellSize`. **S**
- [x] **⌘+ / ⌘- / ⌘0 por pestaña** (hoy no existen). Sobre el tamaño que ya se resuelve, dentro de 8-36.
      `App.swift` (menú Ver), `TerminalSession`, `AppModel.applyProfile`. **S**
- [x] **Interlineado** (0,9-1,5), en Ajustes y como `# @interlineado` por sesión. SwiftTerm ya tiene `lineSpacing`. **S**
- [x] **Trazo fino / suavizado** (SwiftTerm `fontSmoothing`). **S**
- [x] **Avisar si falta la fuente del tema**: «JetBrains Mono no instalada: se usa X · Instalar», en la galería, en
      Ajustes y en el asistente (hoy elige otra sin decir nada; el asistente ofrece fuentes no instaladas). **S**
      (Hecho en Ajustes y en el asistente; en la galería, pendiente.)

## 1.0.2 — Temas: Neon Glass y colores a tu gusto

- [ ] **Diez temas Neon Glass** (cristal de macOS 26 con alma de neón): Tokio (magenta/cian), Ámbar (2049), Ácido
      (verde), Ocaso (synthwave), Corpo (rojo), Hielo (azul), Unidad (estilo EVA-01), Zaibatsu (estilo Arasaka),
      Nocturna (estilo Night City) y Sección (estilo Ghost in the Shell). Archivos listos en
      `docs/propuestas/neon-glass/`; ya pasan `ThemeTests` (contraste WCAG) en una copia del repo. Faltan:
  - [ ] clave `brillo = sí`: el halo neón también en el estilo cristal (`Theme`, `glow()` en ThemeUI). **S**
  - [ ] clave `tinte = #rrggbbaa`: el cristal de pestañas y botones teñido del color del tema, no gris
        (`Glass.swift`, `NeonLabel`). **S**
  - [ ] grupo «Neon Glass» en `Theme.groups` y su inglés en `Ingles.swift`; README (62 temas, tabla) y CHANGELOG. **S**
  - [ ] mirarlos en la demo (capturas de cristal): cómo queda el halo sobre el `glassEffect`. **S**
- [ ] **Colores a tu gusto** (Ajustes → Temas → «Personalizar colores»). Una capa de cambios por tema encima del
      tema, como `highlightColors` del resaltado (lo mismo que hacen VS Code y Ghostty): acento, fondo, texto,
      selección, cursor, los 16 ANSI y, en los de cristal, tinte y opacidad. Vista previa en vivo, aviso de contraste
      con `RGB.contraste`, «Restablecer», «Guardar como tema nuevo…» y «Exportar .tema…». Se aplica a todas las
      pestañas (`core.allTabs`) y respeta «Reducir transparencia». Nuevo `ThemeOverrides` en NetDeckCore con tests.
      **M-L (unos 3 días)**

- [ ] **Familias nuevas** (maqueta enseñada el 2026-11-08; colores a mano, sin `.tema` ni contraste comprobado
      todavía; el autor elige cuáles):
  - Ordenadores clásicos: Terminal 3270, Comandante (Norton Commander), Commodore (C64), Workbench (Amiga).
  - Ciencia ficción: Puente de mando (LCARS), Nostromo (Alien), Imperio (Star Wars), HAL (2001).
  - Centro de datos: Rack (LEDs), Fibra óptica (código de colores de fibras), NORAD (WarGames), Consola de rescate.
  - Naturaleza, con versión clara y oscura: Aurora boreal, Desierto, Volcán, Arrecife.
  - Videojuegos retro: Portátil verde (Game Boy: up/down sólo por tono), Laboratorio (Portal), Arcade.
  - Ojo: en Comandante y Commodore el azul ANSI casi no se ve sobre su fondo azul.

## 1.0.3 — Fuentes: lo de fondo

- [x] **Lista de monoespaciadas fiable y en caché** (por rasgo de ancho fijo, no por nombre; se vacía al instalar una
      fuente) y muestra con cajas, Powerline, «ñ» y una tabla tipo `show int`. Hoy `Theme.ui` consulta NSFontManager
      en cada repintado. **S-M** (Hechas la caché y la lista por rasgo; la muestra, pendiente.)
- [ ] **Símbolos de Nerd Font / Powerline y CJK de reserva** (`glyphFallbackProvider` de SwiftTerm 1.99.3 y lista de
      reserva de CoreText). **M**
- [ ] **Ligaduras opcionales**, apagadas por defecto: SwiftTerm 1.99.3 ya coloca cada glifo en su celda; hay que
      probarlo en la demo con Fira Code y Share Tech Mono. **M**
- [ ] **Elegir el grosor** (Light / Regular / Medium). **S**
- [ ] **Instalar fuentes con más cuidado**: tiempo límite, error de brew a `ErrorLog`, volver a comprobar y, sin
      Homebrew, enlace a la página de la fuente. **M**
- No se puede sin tocar SwiftTerm: negrita/cursiva de otra familia, negrita simulada, espaciado entre letras.

## Ideas grandes (por prioridad; ★ = las primeras)

- [ ] ★ **Capturas de configuración antes/después y diff en color** por equipo (`show run` / `show configuration`,
      versionadas en un git local). Ninguna app de terminal lo trae; oxidized/RANCID lo hacen en servidor. **M**
- [ ] ★ **Firma Developer ID, notarización y cask de Homebrew.** Quita el «clic derecho → Abrir» y hace que el
      actualizador compruebe quién firma, no sólo que no esté roto. Necesita la cuenta de desarrollador de Apple
      (99 $/año): decisión del autor. Mientras tanto, otra opción: firmar el .dmg con una clave ed25519 cuya parte
      pública vaya en la app. **S** (+ la cuenta)
- [ ] ★ **Plantillas de comandos con formulario**: los huecos `{{vlan=100}}` con desplegables, valores por defecto y un
      CSV de variables por equipo para las listas (SecureCRT Command Manager, Warp workflows). **M**
- [ ] ★ **Servidor TFTP (y SCP) integrado**, encendido a mano, con carpeta raíz cerrada y la interfaz elegida, para
      `copy tftp: flash:` y ROMMON (MobaXterm, SecureCRT). **M**
- [ ] ★ **Ping / TCP 22 / traceroute desde las sesiones y las listas**: punto vivo arriba/abajo antes de conectar o
      tras un `reload` (MobaXterm, Royal TSX). **S**
- [ ] **Buscar en el historial vivo de todas las pestañas** y saltar entre prompts con marcas (iTerm2, Warp). **M**
- [ ] **Importar de Royal TSX y Termius** y el XML de SecureCRT 9.6. **S**
- [ ] **Notas por equipo y aviso de PRODUCCIÓN** (`# @nota`, pestaña marcada «PROD»). **S**
- [ ] **Registros por equipo**: carpeta por equipo, nombre con parámetros (%H, fecha) y hora en cada línea. **S**
- [ ] **Consola serie**: elegir el adaptador al enchufarlo, autodetectar los baudios y XMODEM/YMODEM. **M**
- [ ] **Sincronizar sesiones entre Macs** (iCloud Drive / git; las contraseñas siguen sólo en el Llavero). **M-L**
- [ ] **Enlaces `ssh://` y `telnet://`, Atajos de macOS y AppleScript** (abrir sesiones desde NetBox o scripts). **M**
- [ ] **Grabar y reproducir una sesión** (asciicast o rebobinar). **M**
- [ ] **Terminal rápido con una tecla global** y ⌘K que busque por nombre, IP o carpeta. **S**

## Pendiente menor de la revisión de la 1.0.0

- [ ] Los menús con tema recalculan todas las filas al mover el ratón o las flechas (`ThemedMenus.swift`, `MenuKeyRow`);
      y si la acción cambia con el menú abierto, Intro ejecuta la vieja. **S**
- [ ] Con «Navegación con teclado» del Mac, Tab llega a lo que hay detrás de Ajustes (ya pasaba en la 0.9.13). **S**
- [ ] GitHub Actions: `permissions: contents: read` en tests.yml y seguridad.yml, y acciones fijadas por SHA. **S**
- [ ] Si la actualización no se puede completar, decirlo al reabrir (hoy queda sólo en `actualizar.log`). **S**
