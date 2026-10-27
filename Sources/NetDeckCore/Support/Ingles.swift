// Textos en inglés de la interfaz. Clave: el texto en castellano tal como está en `L("…")`, con %@ en lugar de
// cada valor interpolado (y %% por cada %). Lo comprueba IdiomaTests: toda clave del código tiene que estar aquí.
enum Ingles {
    static let textos: [String: String] = [
        "Desconecta FTP y espera a que terminen las transferencias antes de renombrar": "Disconnect FTP and wait for transfers to finish before renaming",
        "Espera a que termine el renombrado de la credencial": "Wait for the credential rename to finish",
        "%@ (con nombre)": "%@ (named)",
        "%@ (equipo)": "%@ (device)",
        "; revisa estos archivos antes de borrar ninguna: %@": "; review these files before deleting either entry: %@",
        "; se han restaurado los archivos modificados": "; modified files have been restored",
        "Al renombrarla se actualizan sus asignaciones en sesiones, grupos, botones, listas y la predeterminada.": "Renaming updates its assignments in sessions, groups, buttons, lists and the default credential.",
        "Automática: propia del equipo": "Automatic: device credential",
        "Añade una credencial y selecciónala en Sesiones.": "Add a credential and select it in Sessions.",
        "Añadir…": "Add…",
        "Buscar credenciales": "Search credentials",
        "Con nombre · asignable a sesiones y grupos": "Named · assignable to sessions and groups",
        "Con nombre: reutiliza una credencial en las sesiones o grupos que elijas. Usuario y equipo: sólo para esa cuenta. Los secretos se guardan únicamente en el Llavero de macOS.": "Named: reuse a credential in the sessions or groups you choose. User and device: only for that account. Secrets are stored only in macOS Keychain.",
        "Contraseña nueva (opcional)": "New password (optional)",
        "Credencial de la sesión": "Session credential",
        "Credencial predeterminada": "Default credential",
        "Credencial renombrada: %@": "Credential renamed: %@",
        "Deja ambos campos vacíos para conservar la contraseña. Renombrar conserva también su bloqueo por fallo.": "Leave both fields empty to keep the password. Renaming also preserves its failure block.",
        "Editar credencial": "Edit credential",
        "Editar credencial…": "Edit credential…",
        "Editar nombre, usuario, equipo o contraseña": "Edit name, user, device or password",
        "El archivo %@ ha cambiado mientras se renombraba: no se sobrescribe": "File %@ changed during renaming: it will not be overwritten",
        "El nombre o la cuenta de la credencial no es válido": "The credential name or account is invalid",
        "Espera a que termine la autenticación pendiente antes de renombrar": "Wait for the pending authentication to finish before renaming",
        "Guarda y cierra los otros editores antes de renombrar una credencial": "Save and close the other editors before renaming a credential",
        "Guardada como «%@». Se conserva «%@» porque todavía la usa una sesión o configuración externa.": "Saved as “%@”. “%@” is kept because a session or external configuration still uses it.",
        "Guardada como «%@»; no se pudo borrar la entrada anterior: %@": "Saved as “%@”; could not delete the previous entry: %@",
        "Heredar del grupo: %@": "Inherit from group: %@",
        "Indica el usuario para activar la credencial predeterminada.": "Enter the user to enable the default credential.",
        "La credencial que quieres renombrar ya no está en el Llavero": "The credential you want to rename is no longer in Keychain",
        "La cuenta propia corresponde a ese usuario y equipo. Para contraseñas distintas según el servicio, usa credenciales con nombre.": "A device account belongs to that user and device. Use named credentials for different passwords on different services.",
        "Las asignaciones que la usen quedarán sin contraseña guardada.": "Assignments using it will have no stored password.",
        "Llavero de macOS": "macOS Keychain",
        "Ninguna (preguntar)": "None (ask)",
        "No se ha completado el renombrado: %@. Se conservan las dos entradas del Llavero": "Renaming was not completed: %@. Both Keychain entries are kept",
        "No se puede cambiar el tipo de una credencial al renombrarla": "A credential’s type cannot change when renaming it",
        "Nueva credencial": "New credential",
        "Nueva credencial con nombre…": "New named credential…",
        "Por ejemplo: Red principal": "For example: Main network",
        "Propia de este usuario y equipo": "Specific to this user and device",
        "Propia del equipo (ignorar grupo)": "Device credential (ignore group)",
        "Se guarda únicamente en el Llavero de macOS.": "Stored only in macOS Keychain.",
        "Se usa si el equipo no tiene otra asignada y pide exactamente ese usuario. Las sesiones guardadas usan su propia asignación.": "Used if the device has no other assigned credential and asks for that exact user. Saved sessions use their own assignment.",
        "Sin coincidencias": "No matches",
        "Una lista usa una cuenta compartida por dos tipos de credencial: revísala antes de renombrar": "A list uses an account shared by two credential types: review it before renaming",
        "Usuario exacto": "Exact user",
        "Usuario y equipo": "User and device",
        "Ya existe una contraseña con ese nombre o cuenta": "A password with that name or account already exists",
        "Ya existe una credencial con ese nombre o cuenta": "A credential with that name or account already exists",
        "Ya se está modificando una credencial": "A credential is already being modified",
        "el nombre o la cuenta lleva caracteres de control": "the name or account contains control characters",
        "falta el nombre o la cuenta de la contraseña": "the password name or account is missing",
        "la contraseña lleva un carácter nulo": "the password contains a null character",
        "la cuenta debe tener el formato usuario@equipo, sin espacios": "the account must use the user@device format, without spaces",
        "tu.usuario": "your.user",
        "«-» está reservado para la contraseña propia del equipo": "“−” is reserved for the device’s own password",
        "Este servidor no permite guardar una copia sin riesgo de sobrescribir otro archivo. Tu copia local se conserva.": "This server cannot save a copy without risking overwriting another file. Your local copy is preserved.",
        "⏳ La pestaña ya tiene una secuencia en marcha; pulsa Esc para cortarla": "⏳ This tab already has a sequence running; press Esc to stop it",
        "✗ El pegado seguro requiere una pestaña SSH/Telnet autenticada": "✗ Safe paste requires an authenticated SSH/Telnet tab",
        "⚠️ Confirmar guardado de «%@»": "⚠️ Confirm saving “%@”",

        "Hay dos túneles con el mismo identificador": "Two tunnels have the same identifier",
        "ssh -G ha devuelto una configuración incompleta o demasiado grande": "ssh -G returned an incomplete or oversized configuration",
        "El ssh_config añade LocalForward, RemoteForward o DynamicForward a esta conexión. Usa una sesión sin reenvíos heredados para iniciar sólo este túnel.": "The ssh_config adds LocalForward, RemoteForward or DynamicForward to this connection. Use a session without inherited forwarding to start only this tunnel.",
        "No se ha podido comprobar el ssh_config con ssh -G: %@": "Could not check ssh_config with ssh -G: %@",
        "ssh -G no ha contestado en %@ s": "ssh -G did not respond within %@ s",
        "No se puede escribir en el puerto: %@": "Cannot write to the port: %@",
        "No se puede enviar BREAK: %@": "Cannot send BREAK: %@",
        "grupos repetidos con alternativas o cuantificadores (pueden bloquear la app)": "repeated groups containing alternatives or quantifiers (they can freeze the app)",
        "Hay dos macros con el mismo identificador («%@»)": "Two macros have the same identifier (“%@”)",
        "No se ha podido confirmar la sustitución de «%@». Revisa el destino y las copias conservadas: anterior «%@»; nueva «%@».": "Couldn’t confirm the replacement of “%@”. Check the destination and preserved copies: previous “%@”; new “%@”.",
        "✗ No se ha podido subir «%@»: %@. Tu copia está en %@": "✗ Couldn’t upload “%@”: %@. Your copy is in %@",
        "✗ Copias de edición conservadas en %@. Puedes seguir guardándolas en el editor; ya no se subirán al servidor.": "✗ Editing copies preserved in %@. You can keep saving them in the editor; they will no longer be uploaded to the server.",
        "Enviar BREAK (consola serie)": "Send BREAK (serial console)",
        "El espacio necesita un nombre de 1 a 120 caracteres":
            "A workspace needs a name of 1 to 120 characters",
        "Un espacio necesita entre 1 y 64 pestañas":
            "A workspace needs 1 to 64 tabs",
        "Las referencias de las pestañas del espacio no son válidas":
            "The workspace tab references are invalid",
        "La distribución del espacio no es válida":
            "The workspace layout is invalid",
        "No se guardan conexiones de loopback en los espacios":
            "Loopback connections are not saved in workspaces",
        "No se guardan saltos escritos a mano en los espacios":
            "Manually typed jumps cannot be saved in workspaces",
        "El espacio contiene una conexión no válida":
            "The workspace contains an invalid connection",
        "Formato de espacios de otra versión: se conserva el archivo":
            "Workspace format from another version: the file is preserved",
        "Se permiten hasta 100 espacios":
            "Up to 100 workspaces are allowed",
        "Los nombres y los identificadores de los espacios deben ser únicos":
            "Workspace names and identifiers must be unique",
        "El archivo de espacios es demasiado grande":
            "The workspace file is too large",
        "✗ El espacio no tiene sesiones disponibles":
            "✗ The workspace has no available sessions",
        "Faltan sesiones del espacio":
            "Some workspace sessions are missing",
        "Abrir las disponibles":
            "Open available sessions",
        "¿Sustituir las pestañas abiertas?":
            "Replace open tabs?",
        "Se cerrarán las conexiones actuales. Las copias del editor remoto se conservan.":
            "Current connections will close. Remote editor copies are preserved.",
        "Sustituir pestañas":
            "Replace tabs",
        "✓ Espacio «%@» abierto (%@ pestañas)":
            "✓ Workspace “%@” opened (%@ tabs)",
        "Espacios de trabajo":
            "Workspaces",
        "Espacios de trabajo…":
            "Workspaces…",
        "Guarda las pestañas, su orden, la selección y la distribución. Abrir un espacio requiere tu confirmación; MultiExec queda apagado.":
            "Save tabs, order, selection and layout. Opening a workspace requires your confirmation; MultiExec stays off.",
        "%@ pestañas":
            "%@ tabs",
        "Nombre del espacio":
            "Workspace name",
        "Guardar disposición actual":
            "Save current layout",
        "¿Actualizar este espacio?":
            "Update this workspace?",
        "Se guardará la disposición actual de la ventana.":
            "The current window layout will be saved.",
        "✓ Espacio guardado":
            "✓ Workspace saved",
        "¿Borrar el espacio «%@»?":
            "Delete workspace “%@”?",
        "Las sesiones y las pestañas abiertas se conservan.":
            "Sessions and open tabs are preserved.",
        "Añadir pestañas":
            "Add tabs",
        "Separador de paneles":
            "Pane divider",
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
        "el equipo no ha contestado":
            "the device didn't respond",
        "%@%@ la contraseña guardada «%@» no ha funcionado en %@: ":
            "%@%@ the saved password “%@” didn't work on %@: ",
        "no se probará sola en 15 min%@\n":
            "it won't be tried automatically for 15 min%@\n",
        "%@%@ «%@» no ha funcionado en %@, pero se ha guardado otra vez después: no se bloquea%@\n":
            "%@%@ “%@” didn't work on %@, but it was saved again afterwards: it isn't blocked%@\n",
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
        "no se entiende la contraseña que devuelve": "can't understand the password it returns",
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
        " · en el salto: %@":
            " · on the jump host: %@",
        " · ahora en %@":
            " · now on %@",
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
        "Al abrir SSH o SFTP, usa sólo la contraseña asignada a esa sesión y a cada salto. Si falta, te la pide; Telnet se inicia a mano. ":
            "When opening SSH or SFTP, only the password assigned to that session and each jump host is used. If missing, you are asked; Telnet starts manually. ",
        "No espera a otras pestañas. Un rechazo confirmado bloquea esa contraseña durante 15 min.":
            "No waiting for other tabs. A confirmed rejection locks that password for 15 min.",
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
        "Sólo después de enviar «ssh equipo» o «telnet» desde una sesión. La salida del equipo y los banners no activan la detección. ":
            "Only after sending “ssh device” or “telnet” from a session. Device output and banners do not activate detection. ",
        "El usuario debe coincidir exactamente; los códigos de un solo uso y los cambios de contraseña se contestan a mano.":
            "The user must match exactly; one-time codes and password changes are answered manually.",
        "Equipos":
            "Devices",
        "Contraseña por defecto":
            "Default password",
        "Es del usuario":
            "Belongs to user",
        "Por defecto":
            "Default",
        "con nombre":
            "named",
        "usuario@equipo":
            "user@device",
        "Desbloquear":
            "Unlock",
        "Con nombre":
            "Named",
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
        "Usa: 🔑 %@ (la del grupo)":
            "Uses: 🔑 %@ (the group's)",
        "Usa: 🔑 %@":
            "Uses: 🔑 %@",
        "Usa: la de %@@%@":
            "Uses: the one for %@@%@",
        "Usa: ninguna (a mano)":
            "Uses: none (manual)",
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
        "Puerto serie no válido: «%@» (sólo /dev/cu.* o /dev/tty.*)":
            "Invalid serial port: “%@” (only /dev/cu.* or /dev/tty.*)",
        "Velocidad no admitida: %@": "Unsupported speed: %@",
        "Trama no admitida: «%@»": "Unsupported framing: “%@”",
        "No se puede abrir «%@»: %@": "Can't open “%@”: %@",
        "el puerto se ha cerrado": "the port has closed",
        "El puerto no admite configuración: %@": "The port can't be configured: %@",
        "El puerto no admite la velocidad %@": "The port doesn't support the speed %@",
        "El puerto no acepta %@ %@: %@": "The port doesn't accept %@ %@: %@",
        "El puerto no ha aceptado: %@": "The port hasn't accepted: %@",
        "velocidad %@ (queda %@)": "speed %@ (left at %@)",
        "%@ bits de datos": "%@ data bits",
        "paridad %@": "parity %@",
        "%@ bits de parada": "%@ stop bits",
        "sin control de flujo": "no flow control",
        "No está «%@»: ¿está conectado el adaptador USB-serie?":
            "“%@” is not there: is the USB-serial adapter plugged in?",
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
        "La app abre el puerto y le aplica velocidad, bits de datos, paridad y bits de parada (sin control de flujo); si el puerto no acepta algún valor, la pestaña lo dice y no se conecta. Para salir, cierra la pestaña.":
            "The app opens the port and applies speed, data bits, parity and stop bits (no flow control); if the port doesn't accept a value, the tab says so and doesn't connect. To quit, close the tab.",
        "✗ No hay sesiones que exportar":
            "✗ No sessions to export",
        "✓ %@ exportadas a %@ (sin contraseñas)":
            "✓ %@ exported to %@ (no passwords)",
        "CSV del inventario, un ssh_config o un JSON exportado desde aquí. Las carpetas pasan a ser grupos. Nunca se importa ninguna contraseña.":
            "an inventory CSV, an ssh_config or a JSON exported from here. Folders become groups. No password is ever imported.",
        "Queda una copia en ssh_config.anterior. Su contraseña del Llavero no se toca.":
            "A copy stays in ssh_config.anterior. Its Keychain password is not touched.",
        "Buscar sesión, equipo, IP, usuario o tipo":
            "Search session, device, IP, user or type",
        "Nueva sesión en este grupo…":
            "New session in this group…",
        "Copiar orden sftp":
            "Copy sftp command",
        "%@ a %@ %@ · para salir, cierra la pestaña":
            "%@ at %@ %@ · to quit, close the tab",
        "✗ «%@»: %@":
            "✗ “%@”: %@",
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
        "✓ %@ · %@ archivos":
            "✓ %@ · %@ files",
        "🔑 «%@» guardada en el Llavero":
            "🔑 “%@” saved in the Keychain",
        "✗ Nombre no válido":
            "✗ Invalid name",
        "⇅ TRANSFERENCIAS %@/%@":
            "⇅ TRANSFERS %@/%@",
        "%@ elegidos":
            "%@ selected",
        "%@ elementos":
            "%@ items",
        "%@ elementos · %@":
            "%@ items · %@",
        "«%@» no ha valido: bloqueada 15 min en todas las pestañas":
            "“%@” didn't work: blocked for 15 min in every tab",
        "Abre otra pestaña SFTP o FTP y conéctala":
            "Open another SFTP or FTP tab and connect it",
        "Abrir la consola":
            "Open the console",
        "Abrir también en el Finder":
            "Also open in Finder",
        "Actualizar":
            "Refresh",
        "Adelante":
            "Forward",
        "¿Borrar %@ elementos?":
            "Delete %@ items?",
        "¿Borrar «%@»?":
            "Delete “%@”?",
        "cancelada":
            "cancelled",
        "Cancelada":
            "Cancelled",
        "Carpeta de arriba":
            "Parent folder",
        "Carpeta vacía":
            "Empty folder",
        "Conexión cerrada":
            "Connection closed",
        "Consola":
            "Console",
        "Consola sftp":
            "sftp console",
        "Contraseña de %@@%@":
            "Password for %@@%@",
        "Copiando de «%@» a «%@»…":
            "Copying from “%@” to “%@”…",
        "Copiar directamente a otro servidor abierto (en memoria, sin pasar por el disco del Mac)":
            "Copy straight to another open server (in memory, never touching the Mac's disk)",
        "Copiar la ruta":
            "Copy path",
        "Crear":
            "Create",
        "Demasiados niveles de carpetas en «%@»":
            "Too many folder levels in “%@”",
        "Descargar…":
            "Download…",
        "Descargar al Mac":
            "Download to the Mac",
        "Descargar aquí":
            "Download here",
        "Desplegar aquí":
            "Expand here",
        "¿Dónde guardo %@?":
            "Where should %@ be saved?",
        "El servidor no lo admite":
            "The server doesn't support it",
        "Enviar a…":
            "Send to…",
        "Enviar a otro servidor":
            "Send to another server",
        "Error del servidor (%@)":
            "Server error (%@)",
        "Escribir la ruta":
            "Type the path",
        "Fin del archivo":
            "End of file",
        "FTP no tiene consola: macOS no trae cliente":
            "FTP has no console: macOS ships no client",
        "FTP no tiene consola: usa la vista gráfica":
            "FTP has no console: use the graphical view",
        "FTP no va cifrado: la contraseña viaja tal cual por la red.":
            "FTP isn't encrypted: the password travels in clear over the network.",
        "FTP: %@":
            "FTP: %@",
        "FTP: el servidor ha cerrado la conexión":
            "FTP: the server closed the connection",
        "FTP: listado demasiado grande":
            "FTP: listing too large",
        "FTP: modo pasivo no válido":
            "FTP: invalid passive mode",
        "FTP: respuesta demasiado larga":
            "FTP: reply too long",
        "FTP: respuesta no válida":
            "FTP: invalid reply",
        "FTP: sin cifrar":
            "FTP: unencrypted",
        "FTP: usuario o contraseña no válidos":
            "FTP: invalid user or password",
        "Guardarla en el Llavero como «%@»":
            "Save it in the Keychain as “%@”",
        "La consola sftp de siempre (put, get, ls…)":
            "The usual sftp console (put, get, ls…)",
        "Las carpetas se borran con todo lo que llevan dentro. No se puede deshacer.":
            "Folders are deleted with everything inside. This can't be undone.",
        "Más de %@ archivos: cópialos por partes":
            "More than %@ files: copy them in parts",
        "Modificado":
            "Modified",
        "Mostrar los archivos ocultos (.algo)":
            "Show hidden files (.something)",
        "No arranca %@: %@":
            "%@ doesn't start: %@",
        "No contesta (15 s)":
            "No answer (15 s)",
        "No existe":
            "Doesn't exist",
        "No se ha podido conectar":
            "Couldn't connect",
        "No se puede escribir en «%@»":
            "Can't write to “%@”",
        "Nombre no válido":
            "Invalid name",
        "Nueva carpeta":
            "New folder",
        "Nueva carpeta…":
            "New folder…",
        "Nueva carpeta en %@":
            "New folder in %@",
        "Permiso denegado":
            "Permission denied",
        "Permisos":
            "Permissions",
        "Plegar":
            "Collapse",
        "Propietario":
            "Owner",
        "Quitar las acabadas":
            "Clear finished",
        "Reintentar":
            "Retry",
        "Renombrar":
            "Rename",
        "Renombrar «%@»":
            "Rename “%@”",
        "Se borra del servidor. No se puede deshacer.":
            "It's deleted from the server. This can't be undone.",
        "Se ha cerrado la conexión":
            "The connection was closed",
        "Se ha perdido la conexión":
            "The connection was lost",
        "Se suben a %@":
            "They're uploaded to %@",
        "Se sustituirá lo que haya en el servidor de destino.":
            "Whatever is on the destination server will be replaced.",
        "Se sustituirá lo que haya en el servidor.":
            "Whatever is on the server will be replaced.",
        "servidor ↔ servidor en memoria · sin pasar por el disco del Mac":
            "server ↔ server in memory · never touching the Mac's disk",
        "SFTP: cifrado (ssh)":
            "SFTP: encrypted (ssh)",
        "SFTP: el servidor no habla SFTP":
            "SFTP: the server doesn't speak SFTP",
        "SFTP: paquete cortado":
            "SFTP: truncated packet",
        "SFTP: respuesta inesperada":
            "SFTP: unexpected reply",
        "sftp> put · get · ls · cd · help":
            "sftp> put · get · ls · cd · help",
        "Subir aquí…":
            "Upload here…",
        "Subir archivos o carpetas del Mac":
            "Upload files or folders from the Mac",
        "Suelta para subir a %@":
            "Drop to upload to %@",
        "TRANSFERENCIAS":
            "TRANSFERS",
        "Tu carpeta de inicio":
            "Your home folder",
        "Usuario o contraseña no válidos":
            "Invalid user or password",
        "Vista gráfica":
            "Graphical view",
        "Ya existe «%@»":
            "“%@” already exists",
        "Ya existe en %@: %@":
            "Already exists in %@: %@",
        "Se abre en el explorador gráfico (con el mismo alias, salto, puerto y usuario que ssh); la consola sftp, con un clic. La contraseña, como en ssh.":
            "Opens in the graphical browser (same alias, jump, port and user as ssh); the sftp console is one click away. The password works as in ssh.",
        "Se abre en el explorador gráfico de la app (subir, bajar, renombrar, borrar). FTP no va cifrado: si el equipo lo admite, mejor SFTP. La contraseña, del Llavero o se pide.":
            "Opens in the app's graphical browser (upload, download, rename, delete). FTP isn't encrypted: prefer SFTP if the device supports it. The password comes from the Keychain or is asked for.",
        "✗ Es la misma carpeta del mismo servidor: elige otra de destino":
            "✗ That's the same folder on the same server: pick another destination",
        "✗ «%@» es la misma carpeta que la de origen: no se copia nada encima del original":
            "✗ “%@” is the same folder as the source: nothing is copied over the original",
        "No se ha podido comprobar que «%@» no es la carpeta de origen: no se copia":
            "Couldn't check that “%@” isn't the source folder: nothing copied",
        "Calcular / ver MD5…":
            "Compute / show MD5…",
        "MD5 de «%@»":
            "MD5 of “%@”",
        "Leyendo del servidor… %@":
            "Reading from the server… %@",
        "Copiado":
            "Copied",
        "Copiar MD5":
            "Copy MD5",
        "Comparar con MD5 conocido":
            "Compare with a known MD5",
        "Pega el MD5 (o la línea de md5sum / verify /md5)":
            "Paste the MD5 (or the md5sum / verify /md5 line)",
        "✓ Coincide: el archivo es idéntico":
            "✓ Match: the file is identical",
        "✗ No coincide: el archivo no es el esperado":
            "✗ No match: this isn't the expected file",
        "Pega un MD5 para comprobar el archivo":
            "Paste an MD5 to check the file",
        "No hay un MD5 (32 caracteres hexadecimales) en lo pegado":
            "There's no MD5 (32 hex characters) in what you pasted",
        "Abre la sesión tal como está, sin guardar los cambios":
            "Opens the session as it is, without saving the changes",
        "Guarda los cambios sin abrir ninguna pestaña":
            "Saves the changes without opening a tab",
        "✗ No se encuentra «%@» en las sesiones guardadas":
            "✗ Can't find “%@” among the saved sessions",
        "✓ «%@» abierta sin guardar: los cambios siguen aquí":
            "✓ “%@” opened without saving: your changes are still here",
        "«%@»: saltos de línea o caracteres de control en un campo":
            "“%@”: line breaks or control characters in a field",
        "«%@»: «%@» no puede ir en las opciones (abriría otro bloque)":
            "“%@”: “%@” can't go in the options (it would open another block)",
        "«%@»: el equipo, el usuario o el salto no pueden empezar por «-»":
            "“%@”: the host, user or jump host can't start with “-”",
        "Conexión cancelada":
            "Connection cancelled",
        "no contesta en %@ s (¿está bloqueado?)":
            "no answer in %@ s (is it locked?)",
        "%@:%@ no contesta en %@ s (¿cortafuegos, VPN o puerto equivocado?)":
            "%@:%@ doesn't answer in %@ s (firewall, VPN or wrong port?)",
        "%@ rechaza la conexión en el puerto %@":
            "%@ refuses the connection on port %@",
        "No hay ruta hasta %@ (¿VPN desconectada?)":
            "No route to %@ (VPN disconnected?)",
        "No se encuentra el equipo «%@»":
            "Can't find host “%@”",
        "FTP: el servidor no contesta (%@ s)":
            "FTP: the server doesn't answer (%@ s)",
        "Comprobar MD5":
            "Check MD5",
        "Al acabar cada archivo se vuelve a leer del destino y su MD5 tiene que ser el de lo leído del origen; si no, no se guarda. Con destino remoto tarda más (se lee dos veces).":
            "When each file is done it's read back from the destination and its MD5 must match what was read from the source; otherwise it isn't saved. With a remote destination it takes longer (it's read twice).",
        " · MD5 ✓":
            " · MD5 ✓",
        "«%@»: el salto no deja reenviar (-J)":
            "“%@”: the jump host doesn't allow forwarding (-J)",
        "Para llegar, la app entraría en «%@» y escribiría allí «%@». Lo que escribas después (también la contraseña del destino) pasará por la shell de ese salto: hazlo sólo si confías en él. La contraseña del destino no se escribirá sola.":
            "To get there, the app would log into “%@” and type “%@” there. Whatever you type next (the destination password too) will go through that jump host's shell: only do it if you trust it. The destination password won't be typed automatically.",
        "Entrar por el salto":
            "Go through the jump host",
        "\r\n\u{1b}[38;5;204m[NetDeck] El salto no deja reenviar (-J) y no se ha entrado por él\u{1b}[0m":
            "\r\n\u{1b}[38;5;204m[NetDeck] The jump host doesn't allow forwarding (-J) and it wasn't used\u{1b}[0m",
        "\r\n\u{1b}[38;5;221m[NetDeck] El salto no deja reenviar (-J): entro en el salto y escribo «%@» (la contraseña del destino sólo se sugiere)\u{1b}[0m\r\n":
            "\r\n\u{1b}[38;5;221m[NetDeck] The jump host doesn't allow forwarding (-J): logging into it and typing “%@” (the destination password is only suggested)\u{1b}[0m\r\n",
        "MD5 distinto en «%@» (origen %@, copia %@): no se ha guardado":
            "MD5 mismatch for “%@” (source %@, copy %@): not saved",
        "Borrando «%@»…":
            "Deleting “%@”…",
        "Borrando %@ elementos…":
            "Deleting %@ items…",
        "ssh -G no ha contestado en %@ s (¿un Include o «Match exec» que no acaba?)":
            "ssh -G didn't answer in %@ s (an Include or “Match exec” that never ends?)",
        "El servidor no contesta (%@ s): se ha cancelado":
            "The server doesn't answer (%@ s): cancelled",
        "¿Abrir las %@ sesiones de «%@»?":
            "Open the %@ sessions in “%@”?",
        "Cada una en su pestaña (también las de sus subcarpetas).":
            "Each one in its own tab (subfolders included).",
        "Grupos":
            "Groups",
        "Abrir las %@ (si son varias, en la vista dividida)":
            "Open all %@ (several go into the split view)",
        "Cada equipo en su pestaña por el salto (tal como está, sin guardar)":
            "Each device in its own tab through the jump host (as it is, without saving)",
        "LISTAS":
            "LISTS",
        "%@ equipos":
            "%@ devices",
        "Pon los equipos, el salto y «Guardar lista»":
            "Enter the devices, the jump host and “Save list”",
        "La lista «%@» tiene cambios sin guardar":
            "The list “%@” has unsaved changes",
        "✗ Ponle un nombre a la lista":
            "✗ Give the list a name",
        "Reutilizar la conexión al salto":
            "Reuse the jump host connection",
        "Las pestañas que pasan por el mismo salto usan una sola conexión a él (abierta 2 min tras cerrar la última): no se vuelven a autenticar en el bastión.":
            "Tabs that go through the same jump host share a single connection to it (kept open for 2 min after the last one closes): they don't authenticate on the bastion again.",
        "Empezar con los de ejemplo":
            "Start with the sample ones",
        "Unos botones de muestra (show interfaces de Cisco, Juniper y Huawei, ping…) para editarlos a tu gusto":
            "A few sample buttons (Cisco, Juniper and Huawei show interfaces, ping…) to edit as you like",
        "Carpeta de destino no válida":
            "Invalid destination folder",
        "«%@» no se puede mover dentro de sí misma":
            "“%@” can't be moved into itself",
        "Ya hay «%@» en %@: no se mueve":
            "“%@” already exists in %@: not moved",
        "Mover a…":
            "Move to…",
        "Mover «%@» a…":
            "Move “%@” to…",
        "Mover %@ elementos a…":
            "Move %@ items to…",
        "Carpeta de destino en este servidor (ruta completa). Se mueve sin copiar: no se sustituye nada que ya exista.":
            "Destination folder on this server (full path). It's moved without copying: nothing that already exists is replaced.",
        "Mover":
            "Move",
        "Carpeta":
            "Folder",
        "Moviendo «%@»…":
            "Moving “%@”…",
        "Moviendo %@ elementos…":
            "Moving %@ items…",
        "Suelta para mover a %@":
            "Drop to move to %@",
        "✗ Carpeta de destino no válida":
            "✗ Invalid destination folder",
        "Elegir el color «%@»":
            "Choose the “%@” color",
        "Volver al color del tema":
            "Back to the theme color",
        "Colores del resaltado (tema «%@»)":
            "Highlight colors (theme “%@”)",
        "Volver a los del tema":
            "Back to the theme ones",
        "Sólo cambian el texto que colorea el resaltado en el terminal, y sólo con este tema: la interfaz y los demás temas siguen igual. Las reglas dicen el nombre («f.green»); aquí eliges qué verde es.":
            "Only the text the highlighting colors in the terminal changes, and only with this theme: the interface and the other themes stay as they are. Rules say the name (“f.green”); here you choose which green it is.",
        "Añadir las nuevas de serie (%@)":
            "Add the new built-in ones (%@)",
        "✓ Añadidas: %@":
            "✓ Added: %@",
        "Reglas que trae la app y no están en las tuyas; las tuyas no cambian":
            "Rules that come with the app and are not in yours; yours do not change",
        "Hay reglas que no se pueden leer (%@): arréglalas en el editor y pulsa Recargar; así no se pierden":
            "Some rules cannot be read (%@): fix them in the editor and press Reload, so they are not lost",
        "✗ Faltaba el archivo de sesiones: recuperadas %@ sesiones de %@":
            "✗ The sessions file was missing: %@ sessions recovered from %@",
        "✗ %@ no incluía tus sesiones: vuelto a incluir (copia del anterior junto a él)":
            "✗ %@ didn't include your sessions: included again (copy of the previous one next to it)",
        "✗ No se ha podido comprobar que %@ incluya tus sesiones: %@": "✗ Couldn't check that %@ includes your sessions: %@",
        "%@ líneas": "%@ lines",
        "Historial": "Scrollback",
        "Líneas guardadas por pestaña": "Lines kept per tab",
        "Las que puedes volver a ver subiendo con la rueda o la barra. Se aplica también a las pestañas abiertas: si bajas el número, se pierden las más antiguas que no quepan.":
            "The lines you can scroll back to with the wheel or the scroll bar. Also applies to open tabs: lowering it drops the oldest lines that no longer fit.",
        "Selección rectangular: mantén ⌥ y arrastra para elegir sólo unas columnas (p. ej. las IP de un «show ip interface brief»); ⌘C la copia.":
            "Rectangular selection: hold ⌥ and drag to pick just some columns (e.g. the IPs of a “show ip interface brief”); ⌘C copies it.",
        "no se puede ejecutar %@": "can't run %@",
        "no se puede ejecutar %@: %@": "can't run %@: %@",
        "ssh -G ha terminado con la señal %@": "ssh -G was ended by signal %@",
        "no se ha podido hacer la copia de seguridad de las sesiones (%@): no se ha guardado nada":
            "couldn't back up the sessions (%@): nothing has been saved",
        "no se ha podido añadir el Include a %@: no se ha guardado nada": "couldn't add the Include to %@: nothing has been saved",
        "Ya se están guardando las sesiones": "The sessions are already being saved",
        "Guardando…": "Saving…",
        "La clave que presenta el equipo no es la guardada en known_hosts. Puede que se haya reinstalado o cambiado, o que alguien esté interceptando la conexión (ataque «man in the middle»). Acepta sólo si sabes por qué ha cambiado.":
            "The key the host presents isn't the one saved in known_hosts. It may have been reinstalled or replaced, or someone may be intercepting the connection (a “man in the middle” attack). Accept only if you know why it changed.",
        "Huella de la clave nueva (%@): %@": "New key fingerprint (%@): %@",
        "Clave antigua en %@": "Old key in %@",
        "⚠️ La clave del equipo «%@» ha cambiado": "⚠️ The host key of “%@” has changed",
        "Aceptar y Actualizar Clave": "Accept and Update Key",
        "«%@» → «%@» no vale": "“%@” → “%@” isn't valid",
        "no se ha podido copiar la app nueva (sigue la de antes): %@": "couldn't copy the new app (the previous one stays): %@",
        "no se ha podido apartar la app de antes (sigue en su sitio): %@": "couldn't move the previous app aside (it stays in place): %@",
        "no se ha podido poner la app nueva (sigue la de antes): %@": "couldn't put the new app in place (the previous one stays): %@",
        "«%@» no es un equipo válido": "“%@” isn't a valid host",
        "\r\n\u{1b}[38;5;204m[NetDeck] La clave del equipo «%@» ha cambiado: no se ha conectado\u{1b}[0m\r\n":
            "\r\n\u{1b}[38;5;204m[NetDeck] The host key of “%@” has changed: not connected\u{1b}[0m\r\n",
        "\u{1b}[38;5;204m[NetDeck] known_hosts no se ha tocado\u{1b}[0m": "\u{1b}[38;5;204m[NetDeck] known_hosts left untouched\u{1b}[0m",
        "\u{1b}[38;5;204m[NetDeck] No se ha podido quitar la clave vieja: %@\u{1b}[0m":
            "\u{1b}[38;5;204m[NetDeck] Couldn't remove the old key: %@\u{1b}[0m",
        "\u{1b}[38;5;51m[NetDeck] Clave vieja de «%@» quitada de %@\u{1b}[0m": "\u{1b}[38;5;51m[NetDeck] Old key of “%@” removed from %@\u{1b}[0m",
        "\r\n\u{1b}[38;5;204m[NetDeck] ¡Ojo! La huella no es la que aceptaste: contesta tú\u{1b}[0m\r\n":
            "\r\n\u{1b}[38;5;204m[NetDeck] Careful! The fingerprint isn't the one you accepted: answer yourself\u{1b}[0m\r\n",
        "%@ · y %@ no ha vuelto a como estaba: tienes su copia en .anterior":
            "%@ · and %@ couldn't be put back as it was: its copy is in .anterior",
        "no se ha podido poner la app nueva ni volver a la de antes: las dos están en %@ (la anterior es «anterior.app»)":
            "couldn't put the new app in place nor restore the previous one: both are in %@ (the previous one is “anterior.app”)",
        "el aviso es de «%@», no de esta conexión (%@)": "the warning is about “%@”, not this connection (%@)",
        "ssh no ha dicho de qué equipo es la clave": "ssh didn't say which host the key belongs to",
        "ssh no ha dicho en qué known_hosts está la clave vieja": "ssh didn't say which known_hosts holds the old key",
        "«%@» no es un known_hosts de esta conexión": "“%@” isn't a known_hosts file of this connection",
        "«ssh -G» no ha dicho qué known_hosts usa esta conexión": "“ssh -G” didn't say which known_hosts this connection uses",
        "\u{1b}[38;5;204m[NetDeck] No se toca known_hosts: %@\u{1b}[0m": "\u{1b}[38;5;204m[NetDeck] known_hosts left untouched: %@\u{1b}[0m",
        "✓ Guardadas; los cambios de mientras se guardaba siguen sin guardar": "✓ Saved; the changes made while saving are still unsaved",
        "✓ «%@» abierta: los cambios sin guardar siguen aquí": "✓ “%@” opened: the unsaved changes are still here",
        "Espera a que terminen de guardarse": "Wait until saving finishes",
        "«%@» es una carpeta o un enlace en el destino: no se sustituye ni se toca": "“%@” is a folder or a link at the destination: it isn't replaced or touched",
        "No se ha podido poner «%@» ni devolver el de antes: el anterior está en «%@» y el nuevo en «%@»": "Couldn't put “%@” in place or bring back the previous one: the previous one is at “%@” and the new one at “%@”",
        "✗ No se graba «%@»: no se puede escribir en %@ (%@)": "✗ “%@” isn't being logged: can't write to %@ (%@)",
        "✗ Se ha dejado de grabar «%@»: %@": "✗ Logging of “%@” has stopped: %@",
        "Cerrar la pestaña": "Close the tab",
        "No se sabe qué es «%@» en el destino: no se sustituye": "It's unknown what “%@” is at the destination: it isn't replaced",
        "Cerrar «%@»": "Close “%@”",
        "fuente «%@» no válida": "invalid font “%@”",
        "tamaño de letra «%@»": "font size “%@”",
        "tema «%@» no válido": "invalid theme “%@”",
        "historial «%@» fuera de lo admitido": "scrollback “%@” out of the allowed range",
        "prompt: %@": "prompt: %@",
        "vacío": "empty",
        "más de %@ caracteres": "more than %@ characters",
        "saltos de línea o caracteres de control": "line breaks or control characters",
        "no es una expresión regular válida": "not a valid regular expression",
        "cuantificadores anidados, como «(a+)+» (pueden bloquear la app)": "nested quantifiers, like “(a+)+” (they can freeze the app)",
        "«%@»: «@%@» va en la sección Perfil, no en las notas": "“%@”: “@%@” belongs in the Profile section, not in the notes",
        "«%@»: %@": "“%@”: %@",
        "Heredar (%@)": "Inherit (%@)",
        "%@ (no está)": "%@ (missing)",
        "%@ (no instalada)": "%@ (not installed)",
        "Líneas guardadas": "Scrollback lines",
        "Tecla ⌥": "⌥ key",
        "escribe «@», «#», «|»…": "types “@”, “#”, “|”…",
        "Escribe «@», «#», «|»… (teclado español)": "Types “@”, “#”, “|”… (Spanish keyboard)",
        "Como Meta (Esc + tecla: emacs, readline)": "As Meta (Esc + key: emacs, readline)",
        "Retroceso": "Backspace",
        "Envía DEL (^?)": "Sends DEL (^?)",
        "Envía ^H (equipos antiguos, consolas)": "Sends ^H (old devices, consoles)",
        "Prompt (regex)": "Prompt (regex)",
        "Heredar (genérico)": "Inherit (generic)",
        "Prompt no válido: %@": "Invalid prompt: %@",
        "PERFIL": "PROFILE",
        "Lo que dejes en «Heredar» sigue a Ajustes. El prompt (p. ej. ^core-\\d+[#>]$) sustituye al genérico para saber que has entrado y para el pegado seguro; una línea que pide contraseña, passphrase u OTP nunca cuenta como prompt.": "Whatever you leave on “Inherit” follows Settings. The prompt (e.g. ^core-\\d+[#>]$) replaces the generic one to know you're logged in and for safe paste; a line asking for a password, passphrase or OTP never counts as a prompt.",
        "Esconder los ocultos": "Hide hidden files",
        "Mostrar los ocultos": "Show hidden files",
        "Más": "More",
        "Ocultar el explorador (⇧⌘B)": "Hide the browser (⇧⌘B)",
        "Editar en tu editor de texto: al guardar se sube al servidor": "Edit in your text editor: saving uploads it to the server",
        "Ocultar": "Hide",
        "Arrastra para cambiar el ancho del explorador": "Drag to change the browser's width",
        "El explorador se conecta cuando entre el terminal": "The browser connects once the terminal has logged in",
        "Explorador SFTP sin conectar": "SFTP browser not connected",
        "Conectar ya": "Connect now",
        "✗ «%@» es demasiado grande para editarlo (máximo %@)": "✗ “%@” is too large to edit (maximum %@)",
        "Bajando «%@» para editarlo…": "Downloading “%@” to edit it…",
        "✗ No se puede editar «%@»: %@": "✗ Can't edit “%@”: %@",
        "✗ No se puede abrir «%@» en el editor: %@": "✗ Can't open “%@” in the editor: %@",
        "✎ «%@» abierto en el editor: al guardarlo se sube al servidor": "✎ “%@” open in the editor: saving it uploads it to the server",
        "✗ «%@» guardado en el Mac pero sin conexión: se subirá al reconectar el explorador": "✗ “%@” saved on the Mac but there's no connection: it will be uploaded when the browser reconnects",
        "Subiendo «%@»…": "Uploading “%@”…",
        "✓ «%@» guardado en el servidor (MD5 comprobado)": "✓ “%@” saved on the server (MD5 verified)",
        "✗ No se ha podido subir «%@»: %@. El servidor sigue como estaba; tu copia está en %@": "✗ Couldn't upload “%@”: %@. The server is unchanged; your copy is in %@",
        "«%@» ya no está en el servidor.": "“%@” is no longer on the server.",
        "«%@» ha cambiado en el servidor desde que lo abriste (otro tamaño u otro MD5).": "“%@” has changed on the server since you opened it (different size or MD5).",
        "⚠️ «%@» ha cambiado en el servidor": "⚠️ “%@” has changed on the server",
        "No se ha sobrescrito nada. Tu copia sigue en %@.": "Nothing has been overwritten. Your copy is still in %@.",
        "Sobrescribir": "Overwrite",
        "Guardar como copia": "Save as a copy",
        "✗ Sin conexión: no se ha guardado la copia de «%@»": "✗ No connection: the copy of “%@” hasn't been saved",
        "✓ Guardado como «%@» junto al original (que no se ha tocado)": "✓ Saved as “%@” next to the original (left untouched)",
        "✗ No se ha podido guardar la copia de «%@»: %@": "✗ Couldn't save the copy of “%@”: %@",
        "«%@» no se ha subido: el servidor y tu copia siguen como estaban": "“%@” hasn't been uploaded: the server and your copy are unchanged",
        "✗ Quedan cambios sin subir en %@": "✗ Changes not uploaded remain in %@",
        "Mostrar/ocultar el explorador SFTP": "Show/hide the SFTP browser",
        "Explorador SFTP al lado del terminal ssh: mismo equipo, usuario y saltos (⇧⌘B)": "SFTP browser next to the ssh terminal: same host, user and jumps (⇧⌘B)",
        "Ocultar el explorador SFTP": "Hide the SFTP browser",
        "Explorador SFTP al lado (⇧⌘B)": "SFTP browser alongside (⇧⌘B)",
        "«%@» no es un archivo normal: no se edita": "“%@” isn't a regular file: it can't be edited",
        "«%@» no es un archivo de texto: no se edita": "“%@” isn't a text file: it can't be edited",
        "«%@» es demasiado grande para editarlo (máximo %@)": "“%@” is too large to edit (maximum %@)",
        "No se puede leer la copia local de «%@»": "Can't read the local copy of “%@”",
        "El explorador lateral sólo está en las pestañas ssh": "The side browser is only available in ssh tabs",
        "El salto no deja reenviar (-J): el explorador lateral no puede llegar a «%@»": "The jump host doesn't allow forwarding (-J): the side browser can't reach “%@”",
        "Macros guardadas (%@) en %@": "Macros saved (%@) in %@",
        "✗ Para grabar una macro, abre antes una pestaña de terminal": "✗ To record a macro, first open a terminal tab",
        "● Grabando una macro en «%@»: escribe las órdenes (las contraseñas no se graban)": "● Recording a macro in “%@”: type the commands (passwords aren't recorded)",
        "Grabación parada: no hay órdenes que guardar": "Recording stopped: no commands to save",
        "macro": "macro",
        "■ Grabadas %@ órdenes": "■ %@ commands recorded",
        " · %@ sin grabar (secretos)": " · %@ not recorded (secrets)",
        "✗ Macro «%@»: %@": "✗ Macro “%@”: %@",
        "⏳ Ya hay una macro en marcha (■ para pararla)": "⏳ A macro is already running (■ to stop it)",
        "✗ No hay ninguna pestaña donde reproducir «%@»": "✗ There's no tab to play “%@” in",
        "✗ Para la grabación antes de reproducir una macro en esa pestaña": "✗ Stop recording before playing a macro in that tab",
        "¿Reproducir «%@»?": "Play “%@”?",
        "%@ órdenes en %@": "%@ commands in %@",
        "Reproducir": "Play",
        "«%@» lleva órdenes peligrosas": "“%@” contains dangerous commands",
        "\n\nEn: %@": "\n\nIn: %@",
        "Reproducir igualmente": "Play anyway",
        "⎋ «%@» no se ha reproducido": "⎋ “%@” hasn't been played",
        "▶ «%@»": "▶ “%@”",
        " · Esc para cortar": " · Esc to stop",
        "«%@» en %@: ": "“%@” in %@: ",
        "✓ %@/%@ órdenes": "✓ %@/%@ commands",
        "⎋ parada en %@/%@": "⎋ stopped at %@/%@",
        "✗ error en el paso %@: %@": "✗ error at step %@: %@",
        "✗ paginador en el paso %@ (falta «terminal length 0»)": "✗ pager at step %@ (missing “terminal length 0”)",
        "✗ sin respuesta a tiempo en el paso %@": "✗ no response in time at step %@",
        "✗ paso %@ peligroso sin confirmar: %@": "✗ dangerous step %@ not confirmed: %@",
        "🔑 piden contraseña en el paso %@: paro (no escribo nada ahí)": "🔑 password requested at step %@: stopping (nothing is typed there)",
        "✗ macro no válida: %@": "✗ invalid macro: %@",
        "Macros…": "Macros…",
        "Grabar macro": "Record macro",
        "Parar la grabación": "Stop recording",
        "Macros: grabar, reproducir (en la pestaña o en MultiExec) y editar": "Macros: record, play (in the tab or in MultiExec) and edit",
        "MACROS": "MACROS",
        "%@ órdenes": "%@ commands",
        "Grabar una macro en la pestaña activa": "Record a macro in the active tab",
        "Confirmar antes de reproducir": "Confirm before playing",
        "Sin pasos: añade uno abajo o graba una macro (●)": "No steps: add one below or record a macro (●)",
        "Añadir:": "Add:",
        "⚠ Lleva órdenes peligrosas: se confirman antes de reproducirla (%@)": "⚠ Contains dangerous commands: they're confirmed before playing (%@)",
        "Se para si el equipo da error, pagina o pide una contraseña (nunca la escribe). Esc, Ctrl+C o ■ la cortan.": "It stops if the device returns an error, pages or asks for a password (it never types it). Esc, Ctrl+C or ■ stop it.",
        "orden, p. ej. show ip interface brief": "command, e.g. show ip interface brief",
        "regex, p. ej. ^\\[OK\\]": "regex, e.g. ^\\[OK\\]",
        "dura": "lasts",
        "máx.": "max.",
        "Quitar": "Remove",
        "Reproducir aquí": "Play here",
        "En «%@»": "In “%@”",
        "En MultiExec": "In MultiExec",
        "En todas las pestañas de MultiExec que no se están autenticando": "In every MultiExec tab that isn't authenticating",
        "ya hay una macro con ese nombre": "there's already a macro with that name",
        "%@ ignoradas: ": "%@ ignored: ",
        "La macro «%@» tiene cambios sin guardar": "The macro “%@” has unsaved changes",
        "✓ Macro «%@» guardada": "✓ Macro “%@” saved",
        "¿Borrar la macro «%@»?": "Delete the macro “%@”?",
        "Queda una copia en macros.json.anterior.": "A copy remains in macros.json.anterior.",
        "Esperar prompt": "Wait for prompt",
        "Esperar texto": "Wait for text",
        "Pausa": "Pause",
        "■ Parar la grabación": "■ Stop recording",
        "● Grabar macro en «%@»": "● Record macro in “%@”",
        "● Grabar macro": "● Record macro",
        "■ Parar la macro (Esc)": "■ Stop the macro (Esc)",
        "Reproducir en MultiExec (%@)": "Play in MultiExec (%@)",
        "Reproducir en «%@»": "Play in “%@”",
        "línea vacía": "empty line",
        "el tiempo de espera va de 1 a %@ s": "the timeout goes from 1 to %@ s",
        "la pausa va de 0,1 a %@ s": "the pause goes from 0.1 to %@ s",
        "sin nombre": "no name",
        "nombre de más de %@ caracteres": "name longer than %@ characters",
        "el nombre lleva caracteres de control": "the name contains control characters",
        "sin pasos": "no steps",
        "más de %@ pasos": "more than %@ steps",
        "no envía ninguna orden": "it doesn't send any command",
        "paso %@: %@": "step %@: %@",
        "%@ no se entiende (JSON roto): no lo sobrescribo hasta que guardes; entonces queda aparte en macros.json.ilegible": "%@ can't be understood (broken JSON): I won't overwrite it until you save; then it's set aside in macros.json.ilegible",
        "%@ es de otra versión (%@): no lo sobrescribo hasta que guardes; entonces queda aparte en macros.json.ilegible": "%@ is from another version (%@): I won't overwrite it until you save; then it's set aside in macros.json.ilegible",
        "macro %@: no se entiende; se ignora": "macro %@: can't be understood; ignored",
        "«%@»: %@; se ignora": "“%@”: %@; ignored",
        "«%@»: repetida; se ignora": "“%@”: duplicated; ignored",
        "Hay dos macros con el nombre «%@»": "There are two macros named “%@”",
        "Sesión no válida: «%@»": "Invalid session: “%@”",
        "elige una sesión o escribe el equipo": "choose a session or type the device",
        "Escucha no válida: «%@»": "Invalid listen address: “%@”",
        "el puerto de escucha va de 1 a 65535": "the listen port goes from 1 to 65535",
        "escuchar en «%@» abre el túnel a otros equipos: márcalo expresamente o deja 127.0.0.1": "listening on “%@” opens the tunnel to other machines: allow it explicitly or keep 127.0.0.1",
        "falta el destino (equipo y puerto)": "the destination is missing (device and port)",
        "Destino no válido: «%@»": "Invalid destination: “%@”",
        "el puerto de destino va de 1 a 65535": "the destination port goes from 1 to 65535",
        "puerto %@ por debajo de 1024: en el servidor sólo lo puede abrir root": "port %@ is below 1024: on the server only root can open it",
        "puerto %@ por debajo de 1024: reservado para servicios del sistema": "port %@ is below 1024: reserved for system services",
        "⚠ Escucha en «%@» del servidor: cualquiera que llegue a él entra por el túnel (y el servidor tiene que permitirlo con GatewayPorts)": "⚠ Listens on the server's “%@”: anyone who can reach it goes through the tunnel (and the server must allow it with GatewayPorts)",
        "⚠ Escucha en «%@»: cualquiera que llegue a este Mac por la red entra por el túnel": "⚠ Listens on “%@”: anyone who can reach this Mac over the network goes through the tunnel",
        "No está la sesión «%@» en el ssh_config": "The session “%@” isn't in the ssh_config",
        "«%@» no es una sesión ssh: los túneles van por ssh": "“%@” isn't an ssh session: tunnels go over ssh",
        "%@ no se entiende (JSON roto): no lo sobrescribo hasta que guardes; entonces queda aparte en tuneles.json.ilegible": "%@ can't be understood (broken JSON): I won't overwrite it until you save; then it's set aside in tuneles.json.ilegible",
        "%@ es de otra versión (%@): no lo sobrescribo hasta que guardes; entonces queda aparte en tuneles.json.ilegible": "%@ is from another version (%@): I won't overwrite it until you save; then it's set aside in tuneles.json.ilegible",
        "túnel %@: no se entiende; se ignora": "tunnel %@: can't be understood; ignored",
        "«%@»: repetido; se ignora": "“%@”: duplicated; ignored",
        "Hay dos túneles con el nombre «%@»": "There are two tunnels named “%@”",
        "no se encuentra la dirección «%@»": "the address “%@” can't be found",
        "el puerto %@ ya está en uso en %@": "port %@ is already in use on %@",
        "sin permiso para escuchar en el puerto %@": "no permission to listen on port %@",
        "«%@» no es una dirección de este Mac": "“%@” isn't an address of this Mac",
        "no se puede escuchar en %@:%@ (%@)": "can't listen on %@:%@ (%@)",
        "el puerto de escucha ya está en uso (Address already in use)": "the listen port is already in use (Address already in use)",
        "el servidor no deja abrir el puerto remoto (remote port forwarding failed: ¿ocupado, menor que 1024 o prohibido?)": "the server won't open the remote port (remote port forwarding failed: in use, below 1024 or forbidden?)",
        "el servidor o el salto no permiten reenviar puertos (administratively prohibited)": "the server or the jump host doesn't allow port forwarding (administratively prohibited)",
        "autenticación fallida (Permission denied)": "authentication failed (Permission denied)",
        "la clave del equipo no coincide con known_hosts (Host key verification failed)": "the host key doesn't match known_hosts (Host key verification failed)",
        "no se encuentra el equipo (Could not resolve hostname)": "the device can't be found (Could not resolve hostname)",
        "conexión rechazada (Connection refused)": "connection refused",
        "no responde (tiempo agotado)": "no response (timed out)",
        "ssh ha terminado (señal %@)": "ssh has ended (signal %@)",
        "ssh ha terminado (código %@)": "ssh has ended (code %@)",
        "Túneles guardados (%@) en %@": "Tunnels saved (%@) in %@",
        "Túnel «%@» activo": "Tunnel “%@” active",
        "✗ Túnel «%@»: %@": "✗ Tunnel “%@”: %@",
        "TÚNELES": "TUNNELS",
        "detenido": "stopped",
        "iniciando…": "starting…",
        "activo": "active",
        "error: %@": "error: %@",
        "(nuevo, sin guardar)": "(new, unsaved)",
        "Iniciar": "Start",
        "Por": "Via",
        "Sesión guardada": "Saved session",
        "Saltos": "Jump hosts",
        "bastion (opcional; varios, con comas)": "bastion (optional; several, comma-separated)",
        "Escucha en el servidor": "Listen on the server",
        "Escucha en este Mac": "Listen on this Mac",
        "Destino (desde este Mac)": "Destination (from this Mac)",
        "Destino (desde el servidor)": "Destination (from the server)",
        "Permitir conexiones de otros equipos (escuchar fuera de loopback)": "Allow connections from other machines (listen outside loopback)",
        "-L: lo que llega a la escucha de este Mac sale desde el servidor hacia el destino.": "-L: what reaches the listen address on this Mac goes out from the server to the destination.",
        "-R: lo que llega a la escucha del servidor viene a este Mac y sale hacia el destino.": "-R: what reaches the listen address on the server comes to this Mac and goes out to the destination.",
        "-D: proxy SOCKS en este Mac; las conexiones salen desde el servidor.": "-D: SOCKS proxy on this Mac; connections go out from the server.",
        "Guarda los cambios y lo inicia": "Saves the changes and starts it",
        "Inicia el túnel": "Starts the tunnel",
        "ya hay un túnel con ese nombre": "there's already a tunnel with that name",
        "%@ ignorados: ": "%@ ignored: ",
        "túnel": "tunnel",
        "El túnel «%@» tiene cambios sin guardar": "The tunnel “%@” has unsaved changes",
        "✓ Guardado: los cambios valen al pararlo e iniciarlo de nuevo": "✓ Saved: the changes apply when you stop and start it again",
        "✓ Túnel «%@» guardado": "✓ Tunnel “%@” saved",
        "¿Borrar el túnel «%@»?": "Delete the tunnel “%@”?",
        "Está en marcha: se para. Queda una copia en tuneles.json.anterior.": "It's running: it will be stopped. A copy stays in tuneles.json.anterior.",
        "Queda una copia en tuneles.json.anterior.": "A copy stays in tuneles.json.anterior.",
        "✓ Borrado": "✓ Deleted",
        "Local (-L)": "Local (-L)",
        "Remoto (-R)": "Remote (-R)",
        "SOCKS (-D)": "SOCKS (-D)",
        "Túneles SSH…": "SSH Tunnels…",
        "Túneles SSH: locales, remotos y SOCKS; iniciar, parar y su estado": "SSH tunnels: local, remote and SOCKS; start, stop and their status",
        "Los espacios ocuparían más de 5 MB: quita alguno o algunas pestañas (no se ha guardado)": "The workspaces would take more than 5 MB: remove some of them or some tabs (nothing was saved)",
        "Aún no hay espacios: abre las pestañas que quieras, ponle un nombre y pulsa «Guardar disposición actual».": "No workspaces yet: open the tabs you want, give it a name and press “Save current layout”.",
        "No se ha podido copiar %@ antes de cambiar la app: no se cambia nada": "Couldn't back up %@ before replacing the app: nothing was changed",
        "Importar…": "Import…",
        "Exportar…": "Export…",
        "Añade los botones de un botones.txt (p. ej. el de un compañero); no se guardan hasta pulsar «Guardar»": "Adds the buttons from a botones.txt (e.g. a colleague’s); nothing is saved until you press “Save”",
        "Guarda estos botones en un .txt para pasárselos a otro (las contraseñas no van: sólo su nombre en el Llavero)": "Saves these buttons to a .txt to share them (passwords aren’t included: only their Keychain name)",
        "Elige el botones.txt que quieres importar": "Choose the botones.txt you want to import",
        "✗ %@ es demasiado grande para ser un botones.txt": "✗ %@ is too large to be a botones.txt",
        "✗ No se ha podido leer %@ (¿es un texto UTF-8?)": "✗ Couldn’t read %@ (is it UTF-8 text?)",
        "✗ %@ no tiene botones (formato «Grupo :: modo :: Nombre :: comando»)": "✗ %@ has no buttons (format “Group :: mode :: Name :: command”)",
        " · %@ líneas mal escritas se han saltado": " · %@ malformed lines were skipped",
        "Importar %@ botones de %@": "Import %@ buttons from %@",
        "«Añadir» los junta con los tuyos (los repetidos no se duplican); «Sustituir» deja sólo los importados.": "“Add” merges them with yours (duplicates are skipped); “Replace” keeps only the imported ones.",
        "Añadir": "Add",
        "✓ %@ botones importados: «Guardar» para quedártelos": "✓ %@ buttons imported: “Save” to keep them",
        "✓ %@ añadidos, %@ ya los tenías: «Guardar» para quedártelos": "✓ %@ added, %@ you already had: “Save” to keep them",
        "✓ %@ botones exportados a %@": "✓ %@ buttons exported to %@",
        "Renombrar la pestaña…": "Rename Tab…",
        "Nombre de la pestaña (se queda hasta que entres en otro equipo)": "Tab name (it stays until you log into another device)",
        "Volver al nombre del equipo": "Back to the device name",
        "Reabrir las %@ de la última vez, en %@ ventanas: ": "Reopen the %@ from last time, in %@ windows: ",
        "✗ Para la grabación de la macro antes de mover la pestaña": "✗ Stop recording the macro before moving the tab",
        "⏳ Hay una secuencia en marcha: Esc para cortarla antes de mover la pestaña": "⏳ A sequence is running: press Esc to stop it before moving the tab",
        "¿Cerrar esta ventana y sus %@ pestañas?": "Close this window and its %@ tabs?",
        "Se cortan sus conexiones; las de las otras ventanas siguen abiertas.": "Its connections are closed; those in the other windows stay open.",
        "Cerrar la ventana": "Close Window",
        "Nueva ventana": "New Window",
        "Cerrar ventana": "Close Window",
        "Mover la pestaña a una ventana nueva": "Move Tab to New Window",
        "Mover a una ventana nueva": "Move to New Window",
        "Mover a la ventana": "Move to Window",
        "portada": "start page",
        "Ventana %@: %@ (%@)": "Window %@: %@ (%@)",
        "✗ Esto ya se está editando aquí: guárdalo o ciérralo antes de abrirlo en otra ventana": "✗ This is already being edited here: save or close it before opening it in another window",
        "✗ Cierra antes lo que tienes abierto en esta ventana para mover la pestaña": "✗ Close what's open in this window before moving the tab",
        "✗ La otra ventana tiene algo abierto (pegado, Ajustes…): ciérralo antes de llevarle la pestaña": "✗ The other window has something open (paste, Settings…): close it before moving the tab there",
        "«%@» queda fuera de MultiExec en esta ventana: inclúyela con clic derecho si quieres": "“%@” stays out of MultiExec in this window: right-click to include it if you want",
        "¿Cerrar la ventana y salir de Terminal NetDeck?": "Close the window and quit Terminal NetDeck?",
        "Se cortan sus %@ conexiones; al volver a abrir la app podrás reabrir sus pestañas.": "Its %@ connections are closed; when you open the app again you can reopen its tabs.",
        "la contraseña está vacía": "the password is empty",
        "%@%@ está vacía: escríbela o pulsa Esc para cancelar%@\n%@ %@'s password: ":
            "%@%@ it's empty: type it or press Esc to cancel%@\n%@ %@'s password: ",
        "\r\n\u{1b}[38;5;204m[NetDeck] La contraseña guardada «%@» no ha valido: no se probará sola en 15 min\u{1b}[0m":
            "\r\n\u{1b}[38;5;204m[NetDeck] The saved password “%@” didn’t work: it won’t be tried automatically for 15 min\u{1b}[0m",
        "Contraseña para %@": "Password for %@",
        "🔑 Otra autenticación con «%@» sigue pendiente; escríbela a mano o, si ya terminó, restablécela en Ajustes → Contraseñas → «Restablecer pendiente»":
            "🔑 Another authentication using “%@” is still pending; type it manually or, if it has ended, reset it in Settings → Passwords → “Reset pending attempt”",
        "otra autenticación con «%@» sigue pendiente; escríbela a mano o, si ya terminó, restablécela en Ajustes → Contraseñas → «Restablecer pendiente»":
            "another authentication using “%@” is still pending; type it manually or, if it has ended, reset it in Settings → Passwords → “Reset pending attempt”",
        "Restablecer pendiente": "Reset pending attempt",
        "Úsalo sólo si el login pendiente ya terminó. No cambia la contraseña guardada.": "Only use this when the pending login has ended. It does not change the saved password.",
]
}
