// Textos en inglés de la interfaz. Clave: el texto en castellano tal como está en `L("…")`, con %@ en lugar de
// cada valor interpolado (y %% por cada %). Lo comprueba IdiomaTests: toda clave del código tiene que estar aquí.
enum Ingles {
    static let textos: [String: String] = [
        "regla %@":
            "rule %@",
        "%@: falta regex o color":
            "%@: missing regex or color",
        "%@: expresión no válida":
            "%@: invalid expression",
        "Ejecutar":
            "Run",
        "Escribir":
            "Type",
        "Contraseña":
            "Password",
        "Sesión":
            "Session",
        "línea %@: el formato es «Grupo :: modo :: Nombre :: comando»":
            "line %@: the format is “Group :: mode :: Name :: command”",
        "línea %@: modo «%@» (usa run, type, pass, login o sesion)":
            "line %@: mode “%@” (use run, type, pass, login or sesion)",
        "línea %@: la tecla %@ ya la usa otro botón (éste se queda sin ella)":
            "line %@: key %@ is already used by another button (this one goes without it)",
        "en cola":
            "queued",
        "esperando al salto":
            "waiting for the jump host",
        "conectando":
            "connecting",
        "contraseña enviada":
            "password sent",
        "dentro ✓":
            "in ✓",
        "denegada: %@":
            "denied: %@",
        "fallo: %@":
            "failed: %@",
        "sin intentar: %@":
            "not attempted: %@",
        "no se ha podido abrir la pestaña":
            "couldn't open the tab",
        "nombre no válido para la shell del salto":
            "invalid name for the jump host's shell",
        "el salto no ha llegado a su prompt":
            "the jump host didn't reach its prompt",
        "«%@» no ha valido: no se prueba en más equipos (15 min)":
            "“%@” didn't work: not trying it on more devices (15 min)",
        "«%@» denegada":
            "“%@” denied",
        "no se ha podido conectar desde el salto":
            "couldn't connect from the jump host",
        "«%@» falló hace poco: la escribes tú":
            "“%@” failed recently: type it yourself",
        "contraseña a mano (%@)":
            "manual password (%@)",
        "no está en el Llavero":
            "not in the Keychain",
        "sin respuesta a «%@»":
            "no answer to “%@”",
        "el equipo no ha contestado":
            "the device didn't respond",
        "%@%@ la contraseña guardada «%@» no ha funcionado en %@: ":
            "%@%@ the saved password “%@” didn't work on %@: ",
        "no se probará sola en 15 min%@\n":
            "it won't be tried automatically for 15 min%@\n",
        "%@%@ otra pestaña está probando «%@»: espero a ver si vale…%@\n":
            "%@%@ another tab is trying “%@”: waiting to see if it works…%@\n",
        "%@%@ «%@» falló hace poco: no la escribo (cuenta AD)%@\n":
            "%@%@ “%@” failed recently: not typing it (AD account)%@\n",
        "piden una contraseña nueva o repetida: escríbela tú":
            "a new or repeated password is requested: type it yourself",
        "ninguna guardada es de «%@»: escríbela tú":
            "none of the saved ones belongs to “%@”: type it yourself",
        "la orden dice «%@» y el prompt «%@»: escríbela tú":
            "the command says “%@” and the prompt “%@”: type it yourself",
        "«%@» falló hace poco: no se escribe sola (cuenta AD)":
            "“%@” failed recently: not typed automatically (AD account)",
        "no se sabe qué usuario la pide: escríbela tú":
            "unknown which user is asking: type it yourself",
        "no hay ninguna guardada":
            "no saved password",
        "%@%@ Esc = cancelar%@\n%@ %@'s password: ":
            "%@%@ Esc = cancel%@\n%@ %@'s password: ",
        "%@%@ cancelado%@\n":
            "%@%@ cancelled%@\n",
        "¿Guardarla como «%@»?":
            "Save it as “%@”?",
        "¿Guardar la %@contraseña de %@ en el Llavero?":
            "Save the %@password for %@ in the Keychain?",
        "nueva ":
            "new ",
        "%@%@ guardada ✓%@\n":
            "%@%@ saved ✓%@\n",
        "%@%@ %@ %@ (Esc = no)%@ ":
            "%@%@ %@ %@ (Esc = no)%@ ",
        "[S/n]":
            "[Y/n]",
        "[s/N]":
            "[y/N]",
        "la contraseña lleva un salto de línea":
            "the password contains a line break",
        "Llavero: %@":
            "Keychain: %@",
        "Los saltos de «%@» forman un bucle":
            "The jump hosts of “%@” form a loop",
        "Salto no válido: «%@»":
            "Invalid jump host: “%@”",
        "Equipo no válido: «%@»":
            "Invalid device: “%@”",
        "«%@»: el nombre no puede llevar espacios ni * ? !":
            "“%@”: the name can't contain spaces or * ? !",
        "«%@» está repetida":
            "“%@” is duplicated",
        "«%@»: puerto «%@»":
            "“%@”: port “%@”",
        "«%@»: equipo «%@»":
            "“%@”: device “%@”",
        "«%@»: usuario «%@»":
            "“%@”: user “%@”",
        "«%@» salta por sí misma":
            "“%@” jumps through itself",
        "ssh no lo entiende: %@":
            "ssh doesn't understand it: %@",
        "código %@":
            "code %@",
        "SecureCRT de este Mac":
            "SecureCRT on this Mac",
        "no reconozco el formato":
            "unrecognized format",
        "tipo %@":
            "type %@",
        "sin host":
            "no host",
        "host, usuario o puerto no válidos":
            "invalid host, user or port",
        "ya la tienes como «%@»":
            "you already have it as “%@”",
        "No se puede leer %@: %@":
            "Can't read %@: %@",
        "falta o está mal el color «%@» (formato #rrggbb)":
            "color “%@” is missing or wrong (format #rrggbb)",
        "SSH nativo: pendiente (fase 2); se usa /usr/bin/ssh":
            "Native SSH: pending (phase 2); using /usr/bin/ssh",
        "Conectar / Salto…":
            "Connect / Jump…",
        "Sesiones…":
            "Sessions…",
        "Cerrar pestaña":
            "Close Tab",
        "Ajustes…":
            "Settings…",
        "Asistente de instalación…":
            "Setup Assistant…",
        "Buscar actualizaciones…":
            "Check for Updates…",
        "Actualizar desde el código…":
            "Update from Source…",
        "Buscar en la salida…":
            "Find in Output…",
        "Buscar en todos los registros…":
            "Find in All Logs…",
        "Abrir el registro de depuración":
            "Open Debug Log",
        "Carpeta de registros":
            "Logs Folder",
        "Terminal":
            "Terminal",
        "Pegado seguro…":
            "Safe Paste…",
        "MultiExec":
            "MultiExec",
        "Resaltado":
            "Highlighting",
        "Reconectar":
            "Reconnect",
        "Clonar pestaña":
            "Clone Tab",
        "Pestaña siguiente":
            "Next Tab",
        "Pestaña anterior":
            "Previous Tab",
        "Mostrar/ocultar sesiones":
            "Show/Hide Sessions",
        "Cancelar lo automático (Esc)":
            "Cancel Automation (Esc)",
        "Recargar ssh_config":
            "Reload ssh_config",
        "Sesiones guardadas (%@)":
            "Sessions saved (%@)",
        "Conectando a %@…":
            "Connecting to %@…",
        "✗ «%@» no es una sesión ni usuario@equipo":
            "✗ “%@” is neither a session nor user@device",
        "🔑 «%@» escrita en %@":
            "🔑 “%@” typed in %@",
        "⎋ Contraseña cancelada":
            "⎋ Password cancelled",
        "🔑 «%@» no ha valido: bloqueada 15 min en todas las pestañas":
            "🔑 “%@” didn't work: locked for 15 min in all tabs",
        "🔑 «%@» falló hace poco: no la escribo (cuenta AD) · desbloquéala en Ajustes":
            "🔑 “%@” failed recently: not typing it (AD account) · unlock it in Settings",
        "🔑 Ahí no piden contraseña ahora":
            "🔑 No password is being requested there right now",
        "🔑 «%@» no está en el Llavero":
            "🔑 “%@” is not in the Keychain",
        "Pegado en %@: ":
            "Pasted in %@: ",
        "%@: %@/%@ dentro":
            "%@: %@/%@ in",
        "✓ %@/%@ líneas":
            "✓ %@/%@ lines",
        "⎋ parado en %@/%@":
            "⎋ stopped at %@/%@",
        "✗ error en la línea %@: %@":
            "✗ error on line %@: %@",
        "✗ paginador en la línea %@ (falta «terminal length 0»)":
            "✗ pager on line %@ (missing “terminal length 0”)",
        "✗ sin prompt tras la línea %@":
            "✗ no prompt after line %@",
        "✗ línea %@ peligrosa sin confirmar: %@":
            "✗ line %@ is dangerous and not confirmed: %@",
        "🔑 piden contraseña: no pego nada ahí":
            "🔑 a password is being requested: not pasting anything there",
        "🔑 piden contraseña tras la línea %@: paro (la siguiente iría como contraseña)":
            "🔑 password requested after line %@: stopping (the next line would be sent as the password)",
        "⎋ Cancelado: no se envía nada más":
            "⎋ Cancelled: nothing else is sent",
        "⏳ Enviando… Esc para cortar (lo que tecleas no se envía)":
            "⏳ Sending… Esc to stop (what you type is not sent)",
        "Botones guardados (%@) en %@":
            "Buttons saved (%@) in %@",
        "✗ Botón «%@»: el login es «usuario / nombre-de-la-contraseña»":
            "✗ Button “%@”: the login is “user / password-name”",
        "🔑 Login «%@»: %@":
            "🔑 Login “%@”: %@",
        "✗ Sin repositorio de actualizaciones (NETDECK_REPO al instalar)":
            "✗ No update repository (NETDECK_REPO at install time)",
        "⬆ Buscando actualizaciones…":
            "⬆ Checking for updates…",
        "Terminal NetDeck %@ disponible":
            "Terminal NetDeck %@ available",
        "Tienes la %@. ":
            "You have %@. ",
        "Se descarga de GitHub, se comprueba y se vuelve a abrir con tus pestañas. ":
            "It is downloaded from GitHub, verified and reopened with your tabs. ",
        "Descarga el .dmg y sustituye la app. ":
            "Download the .dmg and replace the app. ",
        "Tus sesiones, ajustes y el Llavero se conservan.":
            "Your sessions, settings and Keychain are kept.",
        "Actualizar ahora":
            "Update Now",
        "Ver qué cambia":
            "What's New",
        "⬆ Descargando la %@…":
            "⬆ Downloading %@…",
        "el .dmg no trae la app":
            "the .dmg does not contain the app",
        "la app del .dmg no es Terminal NetDeck":
            "the app in the .dmg is not Terminal NetDeck",
        "la app del .dmg no es la versión %@":
            "the app in the .dmg is not version %@",
        "el .dmg no coincide con el publicado (sha256)":
            "the .dmg does not match the published one (sha256)",
        "no se ha podido abrir el .dmg":
            "could not open the .dmg",
        "la firma de la app del .dmg no es válida":
            "the signature of the app in the .dmg is not valid",
        "no se ha podido copiar la app nueva":
            "could not copy the new app",
        "Abrir la página":
            "Open Page",
        "Descargar":
            "Download",
        "Más tarde":
            "Later",
        "⬆ Hay una versión nueva: %@":
            "⬆ A new version is available: %@",
        "⬆ Estás al día (%@)":
            "⬆ You're up to date (%@)",
        "✗ No se ha podido comprobar: %@":
            "✗ Couldn't check: %@",
        "✗ No encuentro el código (actualizar.sh) en este Mac":
            "✗ Can't find the source code (actualizar.sh) on this Mac",
        "⬆ Actualizando: compilando… (se cerrará y se abrirá sola con tus pestañas)":
            "⬆ Updating: building… (it will close and reopen with your tabs)",
        "✗ No se ha podido actualizar: %@":
            "✗ Couldn't update: %@",
        "2 lado a lado":
            "2 side by side",
        "2 arriba y abajo":
            "2 top and bottom",
        "3 columnas":
            "3 columns",
        "Todas (cuadrícula)":
            "All (grid)",
        "Cambiar de grupo de botones":
            "Switch button group",
        "Sin botones · ✎ para crear":
            "No buttons · ✎ to create",
        "Editar los botones":
            "Edit buttons",
        "contraseña «%@»":
            "password “%@”",
        " · en todas (MultiExec)":
            " · on all (MultiExec)",
        "Editar…":
            "Edit…",
        "Copiar la orden":
            "Copy Command",
        "✗ botones.txt tiene líneas mal escritas: arréglalas en Ajustes → Botones para poder ordenar arrastrando":
            "✗ botones.txt has malformed lines: fix them in Settings → Buttons to reorder by dragging",
        "Cancelar":
            "Cancel",
        "Enviar a todas (MultiExec)":
            "Send to All (MultiExec)",
        "Enviar":
            "Send",
        "Barra":
            "Bar",
        "Arriba":
            "Top",
        "Abajo":
            "Bottom",
        "Oculta":
            "Hidden",
        "Por grupos (☰)":
            "By groups (☰)",
        "Elige un botón o crea uno":
            "Pick a button or create one",
        "Recargar":
            "Reload",
        "Guardar":
            "Save",
        "✓ Guardados":
            "✓ Saved",
        "Nuevo botón":
            "New button",
        "Borrar":
            "Delete",
        "Subir":
            "Move Up",
        "Bajar":
            "Move Down",
        "Grupo":
            "Group",
        "Nombre":
            "Name",
        "Modo":
            "Mode",
        "Tecla rápida":
            "Shortcut key",
        "(ninguna)":
            "(none)",
        "La tecla %@ la usa otro botón":
            "Key %@ is used by another button",
        "Probar en la pestaña activa":
            "Try in the active tab",
        "Orden (varias con « ;; »)":
            "Command (several with “ ;; ”)",
        "Texto a escribir":
            "Text to type",
        "Nombre de la contraseña del Llavero":
            "Keychain password name",
        "usuario / nombre-de-la-contraseña":
            "user / password-name",
        "Sesión del ssh_config":
            "ssh_config session",
        "Escribe la orden y pulsa Intro. Varias: una a una esperando al equipo (se para si da error). Huecos: {{interfaz}}, {{vlan=100}}.":
            "Types the command and presses Return. Several: one by one, waiting for the device (stops on error). Placeholders: {{interface}}, {{vlan=100}}.",
        "Sólo la escribe, para que la completes tú. También admite huecos {{…}}.":
            "Only types it, so you can finish it. Placeholders {{…}} also work.",
        "Escribe esa contraseña del Llavero + Intro, sólo si la línea pide «Password:» (si no, no hace nada).":
            "Types that Keychain password + Return, only if the line asks for “Password:” (otherwise does nothing).",
        "Escribe el usuario cuando pidan «Username:/login:» y luego su contraseña cuando la pidan.":
            "Types the user when asked “Username:/login:” and then its password when asked.",
        "Abre una pestaña con esa sesión.":
            "Opens a tab with that session.",
        "Botones de ejemplo: «Guardar» para crear el archivo":
            "Sample buttons: “Save” to create the file",
        "Nuevo":
            "New",
        "Pegado seguro: revisa líneas peligrosas antes de enviarlas (⇧⌘V)":
            "Safe paste: checks dangerous lines before sending them (⇧⌘V)",
        "Volver a pestañas sueltas":
            "Back to separate tabs",
        "Dividir la pantalla":
            "Split the screen",
        "Escribir en «%@»":
            "Type in “%@”",
        "Contraseñas y Llavero…":
            "Passwords & Keychain…",
        "Escribir una contraseña del Llavero en la pestaña actual":
            "Type a Keychain password in the current tab",
        "MultiExec: lo que escribes va a la vez a los paneles (⇧⌘M). Clic derecho en un panel → excluirlo":
            "MultiExec: what you type goes to all panes at once (⇧⌘M). Right-click a pane → exclude it",
        "Corta cualquier secuencia automática (Esc o Ctrl+C en el terminal, ⌘.)":
            "Stops any automatic sequence (Esc or Ctrl+C in the terminal, ⌘.)",
        "Mostrar/ocultar sesiones (⌃⌘S)":
            "Show/hide sessions (⌃⌘S)",
        "Ajustes (⌘,)":
            "Settings (⌘,)",
        "NetDeck":
            "NetDeck",
        "NETDECK":
            "NETDECK",
        "TERMINAL":
            "TERMINAL",
        "%@ · en el salto: %@":
            "%@ · on the jump host: %@",
        "Clonar (otra pestaña igual)":
            "Clone (another identical tab)",
        "Quitar de la vista dividida":
            "Remove from split view",
        "Añadir a la vista dividida":
            "Add to split view",
        "Incluir en MultiExec":
            "Include in MultiExec",
        "Excluir de MultiExec":
            "Exclude from MultiExec",
        "Buscar… (⌘F)":
            "Find… (⌘F)",
        "● Grabar registro":
            "● Record log",
        "■ Parar el registro":
            "■ Stop recording",
        "Abrir el registro":
            "Open log",
        "Cerrar":
            "Close",
        "Mostrar en Finder":
            "Show in Finder",
        "Parar el registro":
            "Stop recording",
        "REC":
            "REC",
        "Grabando en %@":
            "Recording to %@",
        "VISTA ×%@":
            "VIEW ×%@",
        "Pantalla dividida · clic derecho: volver a pestañas sueltas":
            "Split screen · right-click: back to separate tabs",
        "Escribir «%@»":
            "Type “%@”",
        "Piden contraseña: «%@» es de ese usuario":
            "Password requested: “%@” belongs to that user",
        "Piden contraseña: %@ · o elígela en 🔑":
            "Password requested: %@ · or pick it in 🔑",
        "«%@» no ha valido: bloqueada 15 min en todas las pestañas (cuenta AD)":
            "“%@” didn't work: locked for 15 min in all tabs (AD account)",
        "Listo":
            "Ready",
        "MULTIEXEC ×%@":
            "MULTIEXEC ×%@",
        "🔑 SESIÓN %@ · EQUIPOS %@":
            "🔑 SESSION %@ · DEVICES %@",
        "AUTO":
            "AUTO",
        "SUGERIR":
            "SUGGEST",
        "NO":
            "OFF",
        "IP, MAC (cualquier formato), interfaz, texto…":
            "IP, MAC (any format), interface, text…",
        "Buscar":
            "Search",
        "%@%@ líneas en %@":
            "%@%@ lines in %@",
        "%@ importadas: revísalas y pulsa «Guardar»":
            "%@ imported: review them and press “Save”",
        "SESIONES":
            "SESSIONS",
        "● sin guardar":
            "● unsaved",
        "Filtrar":
            "Filter",
        "Nueva sesión":
            "New session",
        "Duplicar":
            "Duplicate",
        "Importar":
            "Import",
        "Contraseña del grupo: %@":
            "Group password: %@",
        "Nueva sesión en «%@»":
            "New session in “%@”",
        "Renombrar grupo…":
            "Rename group…",
        "Contraseña del grupo":
            "Group password",
        "Quitar el grupo (sus sesiones pasan a General)":
            "Remove the group (its sessions move to General)",
        "Elige una sesión o crea una nueva":
            "Pick a session or create a new one",
        "core-01 (sin espacios)":
            "core-01 (no spaces)",
        "Sin espacios ni * ? ! (es el nombre que usa ssh)":
            "No spaces or * ? ! (it's the name ssh uses)",
        "Descripción":
            "Description",
        "SESIÓN":
            "SESSION",
        "Protocolo":
            "Protocol",
        "SSH":
            "SSH",
        "Telnet":
            "Telnet",
        "Equipo (nombre o IP)":
            "Device (name or IP)",
        "Usuario":
            "User",
        "Puerto":
            "Port",
        "Saltar por":
            "Jump via",
        "Directo":
            "Direct",
        "Si el salto no deja reenviar (-J), la app entra en él y escribe «ssh equipo».":
            "If the jump host doesn't allow forwarding (-J), the app logs into it and types “ssh device”.",
        "Clave privada":
            "Private key",
        "Elegir…":
            "Choose…",
        "Equipo antiguo (algoritmos ssh viejos)":
            "Legacy device (old ssh algorithms)",
        "CONEXIÓN":
            "CONNECTION",
        "Automática (la de %@@%@ o la por defecto)":
            "Automatic (the one for %@@%@ or the default)",
        "La propia del equipo (-)":
            "The device's own (-)",
        "%@ (no está en el Llavero)":
            "%@ (not in the Keychain)",
        "Del grupo «%@»":
            "From group “%@”",
        "Guardar una para %@@%@":
            "Save one for %@@%@",
        "Al Llavero":
            "To Keychain",
        "✓ Hay una guardada para %@@%@":
            "✓ There's one saved for %@@%@",
        "CONTRASEÑA (LLAVERO)":
            "PASSWORD (KEYCHAIN)",
        "Nunca se escribe sola la de otro usuario: sólo la de ese mismo usuario.":
            "Another user's password is never typed automatically: only that same user's.",
        "OPCIONES DE SSH (AVANZADO)":
            "SSH OPTIONS (ADVANCED)",
        "Una por línea: LocalForward 8080 192.0.2.1:80 · ServerAliveInterval 30 · …":
            "One per line: LocalForward 8080 192.0.2.1:80 · ServerAliveInterval 30 · …",
        "Guardar y conectar":
            "Save and Connect",
        "¿Borrar la sesión «%@»?":
            "Delete the session “%@”?",
        "Se quita al pulsar «Guardar» (queda una copia en ssh_config.anterior). Su contraseña del Llavero no se toca.":
            "It's removed when you press “Save” (a copy stays in ssh_config.anterior). Its Keychain password is not touched.",
        "Renombrar el grupo «%@»":
            "Rename the group “%@”",
        "✓ Contraseña de %@@%@ guardada en el Llavero":
            "✓ Password for %@@%@ saved in the Keychain",
        "✓ Guardadas":
            "✓ Saved",
        "Hay cambios sin guardar":
            "There are unsaved changes",
        "Descartar":
            "Discard",
        "Aceptar":
            "OK",
        "IMPORTAR SESIONES":
            "IMPORT SESSIONS",
        "SecureCRT (la carpeta Sessions o un .ini), MobaXterm (.mxtsessions), PuTTY (.reg), electerm (.json), ":
            "SecureCRT (the Sessions folder or an .ini), MobaXterm (.mxtsessions), PuTTY (.reg), electerm (.json), ",
        "Elegir archivo o carpeta…":
            "Choose file or folder…",
        "%@: %@ nuevas":
            "%@: %@ new",
        "· %@ saltadas":
            "· %@ skipped",
        "Ninguna":
            "None",
        "Todas":
            "All",
        "Saltadas":
            "Skipped",
        "Añadir %@ al gestor":
            "Add %@ to the manager",
        "Contraseñas":
            "Passwords",
        "Temas":
            "Themes",
        "Fuentes":
            "Fonts",
        "Botones":
            "Buttons",
        "Registro":
            "Logging",
        "General":
            "General",
        "AJUSTES":
            "SETTINGS",
        "Ajustes":
            "Settings",
        "Escribir sola la contraseña al abrir una sesión":
            "Type the password automatically when opening a session",
        "La de la sesión y la de sus saltos (-J), con el askpass de la app: no se teclea en el terminal. ":
            "The session's and its jump hosts' (-J), via the app's askpass: it's not typed in the terminal. ",
        "Un solo intento: si falla, queda bloqueada 15 min en todas las pestañas y te la pide ahí mismo.":
            "One attempt only: if it fails, it's locked for 15 min in all tabs and you're asked right there.",
        "Sesiones":
            "Sessions",
        "Cuando un equipo pide contraseña":
            "When a device asks for a password",
        "Escribirla sola":
            "Type it automatically",
        "Sugerirla (un clic)":
            "Suggest it (one click)",
        "Nada":
            "Nothing",
        "Al hacer «ssh equipo» o «telnet» desde una sesión. Nunca la de otro usuario: con «ssh root@…» o ":
            "When running “ssh device” or “telnet” from a session. Never another user's: with “ssh root@…” or ",
        "«Username: pepe», sólo una guardada de ese mismo usuario.":
            "“Username: pepe”, only one saved for that same user.",
        "Equipos":
            "Devices",
        "Contraseña por defecto":
            "Default password",
        "Es del usuario":
            "Belongs to user",
        "Por defecto":
            "Default",
        "Sólo se escribe sola cuando piden exactamente ese usuario.":
            "Only typed automatically when exactly that user is requested.",
        "con nombre":
            "named",
        "usuario@equipo":
            "user@device",
        "Desbloquear":
            "Unlock",
        "Ha fallado hace poco: ahora no se escribe sola (para no bloquear la cuenta AD)":
            "Failed recently: not typed automatically for now (to avoid locking the AD account)",
        "Con nombre":
            "Named",
        "Nombre (p. ej. AD)":
            "Name (e.g. AD)",
        "tu.usuario@192.0.2.1":
            "your.user@192.0.2.1",
        "Llavero":
            "Keychain",
        "Guardada ✓ (%@)":
            "Saved ✓ (%@)",
        "¿Borrar «%@» del Llavero?":
            "Delete “%@” from the Keychain?",
        "No se puede deshacer.":
            "This can't be undone.",
        "Seguir al Mac (claro / oscuro)":
            "Follow the Mac (light / dark)",
        "Claro":
            "Light",
        "Oscuro":
            "Dark",
        "Importar .tema…":
            "Import .tema…",
        "Fuente":
            "Font",
        "Automática: la del tema (%@)":
            "Automatic: the theme's (%@)",
        "monoespaciada del sistema":
            "system monospaced",
        "Tamaño":
            "Size",
        "del tema (%@)":
            "theme's (%@)",
        "%@ pt":
            "%@ pt",
        "core-01(config)# interface xe-0/0/1\nadmin@core-01> show bgp summary | match Estab":
            "core-01(config)# interface xe-0/0/1\nadmin@core-01> show bgp summary | match Estab",
        "Interfaz":
            "Interface",
        "La del tema (%@)":
            "The theme's (%@)",
        "Monoespaciada del sistema":
            "System monospaced",
        "oficial de %@":
            "official for %@",
        "Instalar":
            "Install",
        "Fuentes de los temas":
            "Theme fonts",
        "Se instalan mediante Homebrew (brew install --cask font-…).":
            "Installed via Homebrew (brew install --cask font-…).",
        "Instalando «%@»…":
            "Installing “%@”…",
        "«%@» instalada ✓":
            "“%@” installed ✓",
        "No se ha podido instalar «%@» (¿falta Homebrew?)":
            "Couldn't install “%@” (is Homebrew missing?)",
        "Resaltar la salida de los equipos":
            "Highlight device output",
        "Reglas":
            "Rules",
        "Automático":
            "Automatic",
        "Reglas incluidas (chromaterm.yml)":
            "Built-in rules (chromaterm.yml)",
        "Las de la app":
            "The app's",
        "Personalizadas":
            "Custom",
        "Con los colores del tema":
            "With the theme's colors",
        "No se han podido leer: ":
            "Couldn't read: ",
        "Resaltado tipo ChromaTerm":
            "ChromaTerm-style highlighting",
        "Mismo formato que ChromaTerm (description, regex, color «f.cyan bold», exclusive). ":
            "Same format as ChromaTerm (description, regex, color “f.cyan bold”, exclusive). ",
        "No toca los colores que ya pone el equipo ni las pantallas completas (vi, less, top).":
            "It doesn't touch colors the device already sets, nor full-screen programs (vi, less, top).",
        "Vista previa":
            "Preview",
        "Reglas (%@)":
            "Rules (%@)",
        "Grabar todas las sesiones a un archivo":
            "Record all sessions to a file",
        "Elegir carpeta…":
            "Choose folder…",
        "Abrir":
            "Open",
        "Volver a la predeterminada (~/Documents/netdeck-logs)":
            "Back to the default (~/Documents/netdeck-logs)",
        "Registro de las sesiones":
            "Session logging",
        "Texto limpio: sin colores y con los paginadores borrados, en CARPETA/AAAA-MM-DD/sesión_HH-MM-SS.log. ":
            "Clean text: no colors and with pagers removed, in FOLDER/YYYY-MM-DD/session_HH-MM-SS.log. ",
        "Mientras graba sale ● REC en la esquina; clic derecho en una pestaña para grabar o parar sólo esa.":
            "While recording, ● REC shows in the corner; right-click a tab to record or stop just that one.",
        "Ahora":
            "Now",
        "Ninguna pestaña grabando":
            "No tab recording",
        "Parar":
            "Stop",
        "Registro de depuración":
            "Debug log",
        "Depuración":
            "Debugging",
        "Qué hace la app (pestañas, saltos, MultiExec, decisiones de contraseña…), nunca contraseñas.":
            "What the app does (tabs, jump hosts, MultiExec, password decisions…), never passwords.",
        "Idioma":
            "Language",
        "Idioma de la interfaz":
            "Interface language",
        "%@ sesiones · anotaciones: # @grupo, # @clave, # @clave-grupo, # @desc, # @telnet":
            "%@ sessions · annotations: # @grupo, # @clave, # @clave-grupo, # @desc, # @telnet",
        "Ventana":
            "Window",
        "Mostrar la lista de sesiones":
            "Show the session list",
        "Efecto CRT en la portada (rejilla y líneas de barrido)":
            "CRT effect on the home screen (grid and scan lines)",
        "Bienvenida":
            "Welcome",
        "Ubicación":
            "Location",
        "✓ App instalada en %@":
            "✓ App installed in %@",
        "✗ No se ha podido copiar la app: %@":
            "✗ Couldn't copy the app: %@",
        "… fuente «%@»":
            "… font “%@”",
        "✓ Fuente «%@» instalada":
            "✓ Font “%@” installed",
        "✗ Fuente «%@»: no se ha podido (Homebrew)":
            "✗ Font “%@”: failed (Homebrew)",
        "✓ Ajustes guardados · tema «%@»":
            "✓ Settings saved · theme “%@”",
        "Probar sin instalar":
            "Try without installing",
        "Atrás":
            "Back",
        "Abrir Terminal NetDeck":
            "Open Terminal NetDeck",
        "Empezar":
            "Get Started",
        "Instalando…":
            "Installing…",
        "Siguiente":
            "Next",
        "Terminal nativo para ingenieros de red":
            "Native terminal for network engineers",
        "Dónde se instala la app":
            "Where the app is installed",
        "Todos vienen con la app: pasa por encima para verlo, clic para usarlo (se cambia cuando quieras)":
            "All of them come with the app: hover to preview, click to use it (change it whenever you like)",
        "Aparte de los temas: se pueden cambiar cuando quieras en Ajustes → Fuentes":
            "Separate from themes: you can change them anytime in Settings → Fonts",
        "Siempre en el Llavero de macOS":
            "Always in the macOS Keychain",
        "Colores en la salida de los equipos, como ChromaTerm":
            "Colors in device output, like ChromaTerm",
        "Revisa y pulsa «Instalar»":
            "Review and press “Install”",
        "Sesiones de tu ssh_config, con saltos y contraseña automática":
            "Sessions from your ssh_config, with jump hosts and automatic password",
        "Todas las temáticas incluidas, con vista previa":
            "All themes included, with preview",
        "Resaltado de la salida tipo ChromaTerm":
            "ChromaTerm-style output highlighting",
        "MultiExec, pegado seguro y listas por salto":
            "MultiExec, safe paste and lists via jump host",
        "Configuración existente encontrada":
            "Existing configuration found",
        "Omitir":
            "Skip",
        "Sesiones de este Mac":
            "Sessions on this Mac",
        "%@ sesiones leídas de %@ ":
            "%@ sessions read from %@ ",
        "(y lo que incluye): son las tuyas, la app no trae ninguna.":
            "(and what it includes): they are yours, the app ships none.",
        "Se respetan el Llavero, el ssh_config, los temas y los ajustes que ya tenías ":
            "Your existing Keychain, ssh_config, themes and settings are kept ",
        "(%@ sesiones · tema «%@»).":
            "(%@ sessions · theme “%@”).",
        "Desde «swift run»":
            "From “swift run”",
        "No hay .app que copiar: para instalarla usa ./install.sh (o ./install.sh --dmg). ":
            "There's no .app to copy: to install it use ./install.sh (or ./install.sh --dmg). ",
        "Puedes seguir para elegir temas y ajustes.":
            "You can continue to pick themes and settings.",
        "Ya instalada":
            "Already installed",
        "Para todos los usuarios del Mac":
            "For all users of this Mac",
        "Sólo para ti":
            "Just for you",
        "Si ya había una versión instalada, se sustituye. Tus temas, ajustes y contraseñas se conservan.":
            "If a version was already installed, it's replaced. Your themes, settings and passwords are kept.",
        "Automática (la del tema)":
            "Automatic (the theme's)",
        "La del tema":
            "The theme's",
        "RECOMENDADAS POR TUS TEMAS":
            "RECOMMENDED BY YOUR THEMES",
        "se instalará con Homebrew":
            "will be installed with Homebrew",
        "falta Homebrew":
            "Homebrew missing",
        "Contraseña de las sesiones automática":
            "Automatic session password",
        "Al abrir una sesión (y sus saltos) entra sola, con el askpass de la app. Un solo intento: si falla, ":
            "When opening a session (and its jump hosts) it logs in by itself, via the app's askpass. One attempt only: if it fails, ",
        "queda bloqueada 15 min y te la pide en la pestaña.":
            "it's locked for 15 min and you're asked in the tab.",
        "EQUIPOS (ssh / telnet desde una sesión)":
            "DEVICES (ssh / telnet from a session)",
        "Sugerirla":
            "Suggest it",
        "Nunca la de otro usuario: con «ssh root@…» o «Username: pepe», sólo una guardada de ese usuario.":
            "Never another user's: with “ssh root@…” or “Username: pepe”, only one saved for that user.",
        "Resaltar la salida":
            "Highlight output",
        "Reglas incluidas (o las tuyas): interfaces, IPs, estados, dBm, errores, prompts…":
            "Built-in rules (or yours): interfaces, IPs, states, dBm, errors, prompts…",
        "sin copiar":
            "not copied",
        "Tema":
            "Theme",
        "ninguna nueva":
            "no new ones",
        "sesión %@ · equipos: %@":
            "session %@ · devices: %@",
        "automática":
            "automatic",
        "a mano":
            "manual",
        "escribirla sola":
            "type it automatically",
        "sugerirla":
            "suggest it",
        "nada":
            "nothing",
        "sin permiso de escritura":
            "no write permission",
        "Equipo":
            "Device",
        "192.0.2.5 · admin@core-01 · core-01:2222":
            "192.0.2.5 · admin@core-01 · core-01:2222",
        "Salto":
            "Jump host",
        "(el del equipo o el de la sesión)":
            "(the device's or the session's)",
        "Conectar":
            "Connect",
        "Una a una, esperando al equipo. Se para si da error, si pagina o con Esc.":
            "One by one, waiting for the device. Stops on error, on a pager or with Esc.",
        "Confirmo %@ peligrosa(s): %@":
            "I confirm %@ dangerous line(s): %@",
        "A todas las pestañas (MultiExec)":
            "To all tabs (MultiExec)",
        "Enviar %@ líneas":
            "Send %@ lines",
        "Usuario en los equipos":
            "User on the devices",
        "(a mano)":
            "(manual)",
        "%@ equipos · una sola pestaña prueba la contraseña a la vez; si falla, no se escribe en las demás":
            "%@ devices · only one tab tries the password at a time; if it fails, it isn't typed in the others",
        "Buscar sesión, equipo o IP":
            "Search session, device or IP",
        "Gestionar sesiones y grupos":
            "Manage sessions and groups",
        "Importar de SecureCRT, MobaXterm, PuTTY, CSV…":
            "Import from SecureCRT, MobaXterm, PuTTY, CSV…",
        "sin sesiones todavía":
            "no sessions yet",
        "sesiones de ejemplo":
            "sample sessions",
        "Recargar el ssh_config (⇧⌘R)":
            "Reload ssh_config (⇧⌘R)",
        "Abrir las %@":
            "Open the %@",
        "Abrir las %@ en vista dividida":
            "Open the %@ in split view",
        "Gestionar el grupo…":
            "Manage group…",
        "Abierta":
            "Open",
        "Conectar en la vista dividida":
            "Connect in split view",
        "Quitar de ★ favoritas":
            "Remove from ★ favorites",
        "★ Favorita":
            "★ Favorite",
        "Duplicar…":
            "Duplicate…",
        "Copiar orden ssh":
            "Copy ssh command",
        "EXCLUIDA":
            "EXCLUDED",
        "⧉ MULTIEXEC":
            "⧉ MULTIEXEC",
        "Excluir de MultiExec (lo que escribas no le llegará)":
            "Exclude from MultiExec (what you type won't reach it)",
        "Ver sola (la vista sigue en «⊞ VISTA»)":
            "View alone (the view stays in “⊞ VIEW”)",
        "Sacar de la vista (sigue abierta en su pestaña)":
            "Take out of the view (stays open in its tab)",
        "Cerrar esta sesión":
            "Close this session",
        "PANEL LIBRE":
            "EMPTY PANE",
        "Pestaña abierta":
            "Open tab",
        "Clonar «%@»":
            "Clone “%@”",
        "Abrir sesión":
            "Open session",
        "\r\n\u{1b}[38;5;51m[NetDeck] Reconectando…\u{1b}[0m\r\n":
            "\r\n\u{1b}[38;5;51m[NetDeck] Reconnecting…\u{1b}[0m\r\n",
        "\r\n\u{1b}[38;5;204m[NetDeck] El salto no ha llegado a su prompt: escribe tú «%@»\u{1b}[0m\r\n":
            "\r\n\u{1b}[38;5;204m[NetDeck] The jump host didn't reach its prompt: type “%@” yourself\u{1b}[0m\r\n",
        "\r\n\u{1b}[38;5;204m[NetDeck] Sesión cerrada%@\u{1b}[0m":
            "\r\n\u{1b}[38;5;204m[NetDeck] Session closed%@\u{1b}[0m",
        " (código %@)":
            " (code %@)",
        " · \u{1b}[1mIntro\u{1b}[0m reconectar · \u{1b}[1mEsc\u{1b}[0m cerrar la pestaña\r\n":
            " · \u{1b}[1mReturn\u{1b}[0m reconnect · \u{1b}[1mEsc\u{1b}[0m close the tab\r\n",
        "\r\n\u{1b}[38;5;221m[NetDeck] El salto no deja reenviar (-J): entro en el salto y escribo «%@»\u{1b}[0m\r\n":
            "\r\n\u{1b}[38;5;221m[NetDeck] The jump host doesn't allow forwarding (-J): logging into it and typing “%@”\u{1b}[0m\r\n",
        "OTROS":
            "OTHERS",
        "Usar «%@»":
            "Use “%@”",
        "Quitar (importado)":
            "Remove (imported)",
        "importado":
            "imported",
        "local":
            "local",
        "Tema «%@» importado":
            "Theme “%@” imported",
        "TERMINAL NATIVO PARA INGENIEROS DE RED":
            "NATIVE TERMINAL FOR NETWORK ENGINEERS",
        "Reabrir las %@ de la última vez: ":
            "Reopen the %@ from last time: ",
        "sesión · usuario@equipo[:puerto]":
            "session · user@device[:port]",
        "CONECTAR":
            "CONNECT",
        "COINCIDEN":
            "MATCHES",
        "Pegado seguro":
            "Safe paste",
        "Esc":
            "Esc",
        "directo":
            "direct",
        "Sí":
            "Yes",
        "No":
            "No",
        "Cyberpunk":
            "Cyberpunk",
        "Sistemas":
            "Systems",
        "Anime y cine":
            "Anime & film",
        "Kawaii":
            "Kawaii",
        "Retro":
            "Retro",
        "Sobrias":
            "Understated",
        "Prácticas":
            "Practical",
        "Corporativas":
            "Corporate",
        "Sin grupo":
            "No group",
        "Importadas":
            "Imported",
        "Actualizaciones":
            "Updates",
        "Buscar versiones nuevas automáticamente (una vez al día)":
            "Check for new versions automatically (once a day)",
        "Versión %@":
            "Version %@",
        "Buscar ahora":
            "Check Now",
        "⬆ Versión %@ disponible":
            "⬆ Version %@ available",
        "Hay una versión nueva de Terminal NetDeck: clic para verla":
            "A new version of Terminal NetDeck is available: click to see it",
        "No se puede leer %@: no lo sobrescribo (¿no es UTF-8?). Revísalo o muévelo y vuelve a probar.":
            "Can't read %@: not overwriting it (is it not UTF-8?). Check or move it and try again.",
        "Cambiar la contraseña guardada":
            "Change the saved password",
        "sesiones: %@%@":
            "sessions: %@%@",
        "grupos: %@":
            "groups: %@",
        "por defecto":
            "default",
        "La usan: ":
            "Used by: ",
        "Contraseña nueva":
            "New password",
        "Repítela":
            "Repeat it",
        "No coinciden":
            "They don't match",
        "Cambiar «%@»":
            "Change “%@”",
        "Guardar «%@»":
            "Save “%@”",
        "Se guarda sólo en el Llavero y se olvida su bloqueo por fallo.":
            "It's saved only in the Keychain and its failure lock is cleared.",
        "Sustituir":
            "Replace",
        "Categoría: renombrar, ordenar, borrar…":
            "Category: rename, reorder, delete…",
        "Nueva categoría":
            "New category",
        "Renombrar…":
            "Rename…",
        "Subir la categoría":
            "Move category up",
        "Bajar la categoría":
            "Move category down",
        "Nuevo botón aquí":
            "New button here",
        "Borrar y pasar sus botones a…":
            "Delete and move its buttons to…",
        "Borrar con sus botones…":
            "Delete with its buttons…",
        " (copia)":
            " (copy)",
        "Mover a la categoría":
            "Move to category",
        "Nueva categoría…":
            "New category…",
        "Nombre de la categoría nueva":
            "Name of the new category",
        "Categoría":
            "Category",
        "Ya hay una categoría «%@»":
            "There's already a category “%@”",
        "Nombre no válido (sin «::» ni «#» delante)":
            "Invalid name (no “::” and no leading “#”)",
        "Renombrar la categoría «%@»":
            "Rename category “%@”",
        "Ya hay una categoría «%@»: ¿juntarlas?":
            "There's already a category “%@”: merge them?",
        "Juntar":
            "Merge",
        "¿Borrar la categoría «%@» y sus %@ botones?":
            "Delete category “%@” and its %@ buttons?",
        "No se guarda hasta que pulses «Guardar» (queda copia en botones.txt.anterior).":
            "Nothing is saved until you press “Save” (a copy stays in botones.txt.anterior).",
        "Sustituir la de %@@%@":
            "Replace the one for %@@%@",
        "Usa: la propia del equipo (la escribes tú)":
            "Uses: the device's own (you type it)",
        "Usa: 🔑 %@ (la del grupo)":
            "Uses: 🔑 %@ (the group's)",
        "Usa: 🔑 %@":
            "Uses: 🔑 %@",
        "Usa: la de %@@%@":
            "Uses: the one for %@@%@",
        "Usa: la por defecto o ninguna (a mano)":
            "Uses: the default one or none (manual)",
        "(no está en el Llavero)":
            "(not in the Keychain)",
        "Cambiar contraseña…":
            "Change Password…",
        "Guardarla…":
            "Save It…",
        "¿Escribir «%@» en «%@»?":
            "Type “%@” into “%@”?",
        "Va como texto al terminal aunque no pidan contraseña: si no es un prompt de contraseña, se verá en pantalla (y puede quedar en el historial del equipo).":
            "It goes to the terminal as text even if no password is being asked for: if it isn't a password prompt, it will show on screen (and may stay in the device's history).",
        "«%@» ha fallado hace poco":
            "“%@” failed recently",
        "Si es una cuenta AD, otro intento fallido puede bloquearla. ¿Escribirla igualmente?":
            "If it's an AD account, another failed attempt may lock it. Type it anyway?",
        "Escribir igualmente":
            "Type Anyway",
        "Escribir sin esperar a que la pida":
            "Type Without Waiting for the Prompt",
        "Sin Intro":
            "Without Return",
        "Con Intro":
            "With Return",
        "Lista guardada":
            "Saved list",
        "(nueva, sin guardar)":
            "(new, unsaved)",
        "Nueva":
            "New",
        "Importar equipos de un .txt/.csv…":
            "Import Devices from a .txt/.csv…",
        "Borrar…":
            "Delete…",
        "No valen (se ignoran): %@":
            "Not valid (ignored): %@",
        "Guardar lista":
            "Save List",
        "✓ Lista «%@» guardada":
            "✓ List “%@” saved",
        "✓ Copia «%@»":
            "✓ Copy “%@”",
        "Renombrar la lista «%@»":
            "Rename list “%@”",
        "✓ Renombrada":
            "✓ Renamed",
        "¿Borrar la lista «%@»?":
            "Delete list “%@”?",
        "Queda una copia en listas.json.anterior. Las contraseñas del Llavero no se tocan.":
            "A copy stays in listas.json.anterior. Keychain passwords are not touched.",
        "✓ Borrada":
            "✓ Deleted",
        "%@ equipos importados de %@":
            "%@ devices imported from %@",
        " · %@ no valen (se ignoran)":
            " · %@ not valid (ignored)",
        "Conexiones":
            "Connections",
        "Enviar el idioma del Mac a los servidores (LANG, LC_*)":
            "Send the Mac's language to servers (LANG, LC_*)",
        "Desactivado, los servidores usan su propio idioma y no salen avisos como «setlocale: LC_CTYPE». Se aplica a las conexiones nuevas.":
            "When off, servers use their own language and warnings like “setlocale: LC_CTYPE” don't appear. Applies to new connections.",
        "Terminal local":
            "Local terminal",
        "✗ No hay sesión de inicio: márcala con clic derecho en una sesión":
            "✗ No startup session: set one by right-clicking a session",
        "Nueva terminal local":
            "New Local Terminal",
        "Abrir la sesión de inicio":
            "Open Startup Session",
        "Herramientas":
            "Tools",
        "Listas de equipos…":
            "Device Lists…",
        "Listas de equipos: la misma orden en muchos equipos por un salto (⇧⌘L)":
            "Device lists: the same command on many devices via a jump host (⇧⌘L)",
        "Se abre al arrancar (⌥⌘K)":
            "Opens at startup (⌥⌘K)",
        "No abrir al arrancar":
            "Don't open at startup",
        "⏻ Abrir al arrancar":
            "⏻ Open at startup",
        "⏻ Abrir al arrancar (sólo una; ⌥⌘K la abre cuando quieras)":
            "⏻ Open at startup (only one; ⌥⌘K opens it any time)",
        "Al arrancar":
            "At startup",
        "Sesión de inicio":
            "Startup session",
        "%@ (ya no existe)":
            "%@ (no longer exists)",
        "Abrir una terminal local al arrancar si no hay otras pestañas":
            "Open a local terminal at startup if there are no other tabs",
        "La sesión de inicio también se marca con clic derecho en la lista y se abre con ⌥⌘K; la terminal local, con ⌘T.":
            "The startup session can also be set by right-clicking it in the list and opened with ⌥⌘K; the local terminal, with ⌘T.",
        "Listas":
            "Lists",
        "puerto serie no válido":
            "invalid serial port",
        "«%@»: puerto serie «%@»":
            "“%@”: serial port “%@”",
        "«%@»: saltos de línea en el grupo o las notas":
            "“%@”: line breaks in the group or the notes",
        "«%@»: una nota no puede empezar por @grupo ni @clave-grupo":
            "“%@”: a note can't start with @grupo or @clave-grupo",
        "Puerto serie no válido: «%@»":
            "Invalid serial port: “%@”",
        "No está /usr/bin/screen en este Mac: hace falta para el puerto serie":
            "/usr/bin/screen is not on this Mac: it's needed for the serial port",
        "No está «%@»: ¿está conectado el adaptador USB-serie?":
            "“%@” is not there: is the USB-serial adapter plugged in?",
        "FTP se abre en el Finder, no en una pestaña":
            "FTP opens in the Finder, not in a tab",
        "No está %@ en este Mac":
            "%@ is not on this Mac",
        "Serie":
            "Serial",
        "Local":
            "Local",
        "Subir (dentro de su grupo)":
            "Move up (within its group)",
        "Bajar (dentro de su grupo)":
            "Move down (within its group)",
        "Todas (JSON)…":
            "All (JSON)…",
        "Todas (CSV)…":
            "All (CSV)…",
        "Grupo «%@» (JSON)…":
            "Group “%@” (JSON)…",
        "Exportar (sin contraseñas)":
            "Export (no passwords)",
        "SecureCRT, MobaXterm, PuTTY, electerm, CSV, un ssh_config o un JSON exportado":
            "SecureCRT, MobaXterm, PuTTY, electerm, CSV, an ssh_config or an exported JSON",
        "Exportar el grupo (JSON)…":
            "Export the group (JSON)…",
        "Exportar el grupo (CSV)…":
            "Export the group (CSV)…",
        "Este Mac":
            "This Mac",
        "Tipo":
            "Type",
        "Abre /usr/bin/sftp con el mismo alias, salto, puerto y usuario que ssh; la contraseña, como en ssh.":
            "Opens /usr/bin/sftp with the same alias, jump host, port and user as ssh; the password works as in ssh.",
        "macOS no trae cliente FTP: se abre en el Finder, sólo lectura (para subir archivos, usa SFTP). La contraseña la pide el Finder.":
            "macOS has no FTP client: it opens in the Finder, read-only (to upload files, use SFTP). The Finder asks for the password.",
        "Tu shell de inicio en este Mac (como ⌘T): sin contraseñas ni MultiExec.":
            "Your login shell on this Mac (like ⌘T): no passwords and no MultiExec.",
        "NOTAS":
            "NOTES",
        "Una por línea; se guardan como comentarios «# …» de la sesión (p. ej. «@proyecto despliegue»).":
            "One per line; saved as “# …” comments of the session (e.g. “@proyecto rollout”).",
        "Puerto serie":
            "Serial port",
        "(elige uno)":
            "(choose one)",
        "%@ (no conectado)":
            "%@ (not connected)",
        "Volver a buscar puertos":
            "Look for ports again",
        "Ruta del puerto":
            "Port path",
        "Sólo /dev/cu.* o /dev/tty.*, sin espacios ni símbolos":
            "Only /dev/cu.* or /dev/tty.*, no spaces or symbols",
        "Velocidad":
            "Speed",
        "Bits de datos":
            "Data bits",
        "Paridad":
            "Parity",
        "Par":
            "Even",
        "Impar":
            "Odd",
        "Bits de parada":
            "Stop bits",
        "Se abre con /usr/bin/screen (para salir: Ctrl-A y luego k). screen sólo aplica la velocidad y los bits de datos: la paridad y los bits de parada quedan como los deje el sistema.":
            "Opens with /usr/bin/screen (to quit: Ctrl-A then k). screen only applies the speed and data bits: parity and stop bits stay as the system leaves them.",
        "Este Mac no tiene /usr/bin/screen: la pestaña no podrá abrir el puerto.":
            "This Mac has no /usr/bin/screen: the tab won't be able to open the port.",
        "✗ No hay sesiones que exportar":
            "✗ No sessions to export",
        "✓ %@ exportadas a %@ (sin contraseñas)":
            "✓ %@ exported to %@ (no passwords)",
        "CSV del inventario, un ssh_config o un JSON exportado desde aquí. Las carpetas pasan a ser grupos. Nunca se importa ninguna contraseña.":
            "an inventory CSV, an ssh_config or a JSON exported from here. Folders become groups. No password is ever imported.",
        "FTP «%@»: se abre en el Finder (sólo lectura)":
            "FTP “%@”: opening in the Finder (read-only)",
        "Queda una copia en ssh_config.anterior. Su contraseña del Llavero no se toca.":
            "A copy stays in ssh_config.anterior. Its Keychain password is not touched.",
        "Buscar sesión, equipo, IP, usuario o tipo":
            "Search session, device, IP, user or type",
        "Nueva sesión en este grupo…":
            "New session in this group…",
        "Copiar orden sftp":
            "Copy sftp command",
        "screen: para salir, Ctrl-A y luego k":
            "screen: to quit, Ctrl-A then k",
        "(elige una)":
            "(choose one)",
        "%@ (no está en tus sesiones)":
            "%@ (not in your sessions)",
        "Contraseña del Llavero":
            "Keychain password",
        "Su contraseña del Llavero":
            "Its Keychain password",
        "Gestionar…":
            "Manage…",
        "Guardar o cambiar contraseñas del Llavero (Ajustes → Contraseñas)":
            "Save or change Keychain passwords (Settings → Passwords)",
        "No hay contraseñas con nombre en el Llavero: guárdala primero en Ajustes → Contraseñas.":
            "There are no named passwords in the Keychain: save it first in Settings → Passwords.",
            "Abrir en el editor…":
            "Open in Editor…",
        "Crea una copia personalizada (si no la hay) y la abre en tu editor de texto":
            "Creates a custom copy (if there isn't one) and opens it in your text editor",
        "No encuentro las reglas de la app":
            "Can't find the app's rules",
        "Editar la regla":
            "Edit Rule",
        "Nueva regla…":
            "New Rule…",
        "Restaurar las de serie…":
            "Restore Defaults…",
        "Van por orden: la primera que encaja colorea. Al cambiar algo se guardan en tu archivo personalizado.":
            "Rules apply in order: the first one that matches colors. Any change is saved to your custom file.",
        "✓ Regla «%@» guardada":
            "✓ Rule “%@” saved",
        "✓ Duplicada: «%@»":
            "✓ Duplicated: “%@”",
        "¿Borrar la regla «%@»?":
            "Delete the rule “%@”?",
        "Queda una copia del archivo anterior (resaltado.yml.anterior).":
            "A copy of the previous file is kept (resaltado.yml.anterior).",
        "✓ Borrada «%@»":
            "✓ Deleted “%@”",
        "¿Volver a las reglas de serie?":
            "Go back to the default rules?",
        "Tus reglas personalizadas se sustituyen (queda copia en resaltado.yml.anterior) y se encienden todas.":
            "Your custom rules are replaced (a copy is kept in resaltado.yml.anterior) and all of them are turned on.",
        "Restaurar":
            "Restore",
        "✓ Reglas de serie restauradas":
            "✓ Default rules restored",
        "Falta la descripción":
            "Description is missing",
        "Ya hay otra regla con esa descripción":
            "Another rule already has that description",
        "p. ej. VLAN":
            "e.g. VLAN",
        "Expresión regular":
            "Regular expression",
        "✓ Válida · %@ grupos":
            "✓ Valid · %@ groups",
        "Exclusiva: lo que colorea ya no lo colorea ninguna regla de después":
            "Exclusive: what it colors is not colored by any later rule",
        "Nueva regla":
            "New Rule",
        "Sintaxis de ChromaTerm/Python: (?i) sin distinguir mayúsculas, \\b borde de palabra, (…) grupos.":
            "ChromaTerm/Python syntax: (?i) case-insensitive, \\b word boundary, (…) groups.",
        "Añadir color para un grupo":
            "Add Color for a Group",
        "Colores":
            "Colors",
        "Grupo 0 = todo el acierto. Los colores con nombre siguen al tema (si está activado «Con los colores del tema»).":
            "Group 0 = the whole match. Named colors follow the theme (if “With the theme colors” is on).",
        "Vista previa (sólo esta regla)":
            "Preview (this rule only)",
        "Colorea %@ líneas de la muestra":
            "Colors %@ lines of the sample",
        "todo":
            "all",
        "Texto":
            "Text",
        "Fondo":
            "Background",
        "Negrita":
            "Bold",
        "Cursiva":
            "Italic",
        "Subrayado":
            "Underline",
        "Quitar este color":
            "Remove this color",
        "Ninguno":
            "None",
        "%@: otro color (#rrggbb)":
            "%@: another color (#rrggbb)",
        "Abrir el registro de errores":
            "Open Error Log",
        "Conectar, terminal local, sesión nueva o una favorita":
            "Connect, local terminal, new session or a favorite",
        "Nueva sesión…":
            "New Session…",
        "Nueva sesión SFTP…":
            "New SFTP Session…",
        "Nueva sesión serie…":
            "New Serial Session…",
        "Favoritas":
            "Favorites",
        "Falta la expresión":
            "Expression is missing",
        "La expresión no puede llevar saltos de línea":
            "The expression can't contain line breaks",
        "Expresión no válida (revisa paréntesis, corchetes y escapes)":
            "Invalid expression (check parentheses, brackets and escapes)",
        "Encaja con el texto vacío: no colorearía nada":
            "Matches empty text: it would color nothing",
        // Ratón, barra superior y lista de sesiones
        "Ratón":
            "Mouse",
        "Copiar al seleccionar":
            "Copy on select",
        "Pegar con clic derecho":
            "Paste on right-click",
        "Como en PuTTY o SecureCRT. El clic derecho pega igual que ⌘V; con ⌃ o ⌥ abre el menú de siempre.":
            "Like PuTTY or SecureCRT. Right-click pastes just like ⌘V; with ⌃ or ⌥ it opens the usual menu.",
        "Copiar":
            "Copy",
        "Pegar":
            "Paste",
        "Seleccionar todo":
            "Select All",
        "Nueva terminal local: tu shell en este Mac (⌘T)":
            "New local terminal: your shell on this Mac (⌘T)",
        "al arrancar":
            "at launch",
        "Recientes":
            "Recent",
        "Nada coincide con «%@»":
            "Nothing matches “%@”",
]
}
