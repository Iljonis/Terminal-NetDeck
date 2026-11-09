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

## Ya en la 1.0.0 (antes previsto para la 1.0.2)

- [x] **Diez temas Neon Glass** (cristal de macOS 26 con neón): claves `brillo = sí` y `tinte = #rrggbbaa`, grupo
      «Neon Glass», README y CHANGELOG.
- [x] **Colores a tu gusto** (Ajustes → Temas → «Personalizar colores»): `ThemeOverrides`, vista previa, aviso de
      contraste, «Restablecer», «Guardar como tema nuevo…» y «Exportar .tema…».
- [x] **Familias nuevas:** Ordenadores clásicos, Ciencia ficción, Centro de datos, Naturaleza (claro y oscuro) y
      Videojuegos retro, con contraste comprobado por `ThemeTests`.
- [x] **Filtros de pantalla** (CRT, LCD, fósforo, holograma): en Ajustes → Terminal y Ver → Filtro de pantalla (⌥⌘F),
      con intensidad y apagados con la Accesibilidad del Mac.

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
