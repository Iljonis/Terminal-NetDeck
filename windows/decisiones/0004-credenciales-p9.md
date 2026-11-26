# ADR-0004: Credenciales en Windows (Administrador de credenciales frente al Llavero)

**Fecha:** 2026-11-17
**Estado:** propuesta (describe lo ya implementado en P4d y fija lo que queda para P9)
**Deciden:** el autor (Jonay), con el contexto de P9
**Relacionado con:** ADR-0002 (nota de seguridad), ADR-0003 (paquete: la ruta estable del ejecutable)

## Contexto

NetDeck guarda dos clases de contraseña, siempre fuera de archivos y de registros (`DebugLog` y `ErrorLog` no escriben
secretos): la de una sesión (servicio `netdeck-ssh`, cuenta `usuario@equipo`) y las **con nombre** (servicio `netdeck`,
cuenta = el nombre: «AD», las de los botones…). `CredentialStore` es el contrato; `KeychainStore` lo cumple en cada sistema.

**macOS (hoy).** `KeychainStore` lee y guarda con `/usr/bin/security` (`find-generic-password -g`, alta por `security -i`).
Las contraseñas guardadas así confían en esa herramienta, por lo que **no sale el aviso por app** del Llavero. Comprobar que
existe y listar usan `SecItemCopyMatching` sin leer el secreto. El Llavero cifra con la sesión del usuario y se bloquea con ella.

**Windows (hoy, P4d).** La misma `KeychainStore` tiene su rama `#if os(Windows)` con el **Administrador de credenciales**:
`CredWriteW`, `CredReadW`, `CredDeleteW` y `CredEnumerateW`, tipo `CRED_TYPE_GENERIC`, persistencia
`CRED_PERSIST_LOCAL_MACHINE` (no viaja con el perfil de dominio). Nombre de destino `netdeck-ssh:usuario@equipo` o
`netdeck:nombre`, usuario = la cuenta, y el secreto como UTF-8 en el blob; la copia en memoria se pone a ceros tras escribir y
`CredentialValidation` se aplica antes. El sistema guarda el blob cifrado con **DPAPI** bajo el perfil del usuario.

## Equivalencias y diferencias

| | macOS (Llavero) | Windows (Administrador de credenciales) |
|---|---|---|
| Almacén | Llavero de inicio de sesión | Credenciales genéricas del usuario |
| Cifrado en reposo | clave ligada a la sesión del usuario | DPAPI, ligada al perfil del usuario |
| Otros usuarios del equipo | no leen | no leen |
| Otro proceso del mismo usuario | lo que permita la ACL del elemento (aquí, confía en `security`) | **lee sin aviso** (no hay ACL por app) |
| Aviso por app | no, por cómo se guarda (ver arriba) | no existe |
| Alta «sólo si no existe» | — | no es atómica: se mira antes con `exists` (comentado en el código) |
| Enumerar sin leer | `SecItemCopyMatching` | `CredEnumerateW` por prefijo |

La regla de seguridad equivalente es, por tanto, «**ningún otro usuario** del sistema ni nadie con el disco apagado» y no
«ningún otro programa»: en Windows la barrera es el perfil de usuario. Esto es lo que ya decía la ADR-0002; aquí se añade un
matiz: como en macOS las contraseñas confían en `/usr/bin/security`, cualquier proceso del usuario que lo ejecute con el
Llavero desbloqueado también las lee, así que **la distancia real entre las dos plataformas es menor** que «ACL por app frente a
nada». Conviene revisar esa frase de la ADR-0002.

## Bloqueo de 15 minutos

No depende del almacén y es **idéntico en las dos plataformas**: lo lleva `CredentialLedger` (`blockWindow = 15 * 60`). Si la
contraseña «por defecto» escrita sola por la app no vale, no se vuelve a escribir sola durante 15 minutos, para no bloquear
las cuentas de AD; las de las sesiones y las que elige el usuario no lo respetan. El estado (probando, fallo, confirmada)
son **marcas con fecha** compartidas entre pestañas y el askpass, sin secretos; no hay un temporizador que borre una caché de
contraseñas en memoria. `CredReadW` no tiene caducidad: una contraseña sigue guardada hasta que el usuario la borre (desde
NetDeck o desde Panel de control → Administrador de credenciales → Credenciales de Windows → Genéricas).

## Opciones consideradas

- **A. Administrador de credenciales, `CRED_TYPE_GENERIC`, `LOCAL_MACHINE` (elegida).** Es el almacén del sistema, lo ve y lo
  borra el usuario, y no hay que escribir criptografía propia.
- **B. Lo mismo con `CRED_PERSIST_SESSION`.** No sobrevive al cierre de sesión. Sirve sólo como un futuro «no recordar».
- **C. Archivo propio con `CryptProtectData` (DPAPI) y entropía.** La protección frente a otro proceso del usuario es la misma
  (la entropía va dentro del ejecutable), más código y más superficie, y el usuario no la ve en el Administrador. Se evalúa
  DPAPI sólo como capa adicional encima de A (ADR-0002), no como sustituto.
- **D. Confirmar cada lectura (Windows Hello / `KeyCredentialManager`).** Protegería de otros procesos del usuario, pero
  cada contraseña pediría atención: choca con el askpass desatendido. Queda como «modo estricto» opcional.
- **E. `CRED_PERSIST_ENTERPRISE`.** Copia las credenciales a otros equipos del dominio: no se ha pedido y es peor para el
  secreto.

## Decisión

1. Mantener **A** como almacén de contraseñas en Windows, con el contrato `CredentialStore` tal cual.
2. Ninguna contraseña se escribe fuera del Administrador de credenciales (ni en archivos, ni en registros, ni en la línea de
   órdenes de `ssh`).
3. El bloqueo de 15 minutos sigue siendo del `CredentialLedger`, sin cambios.
4. Decir la verdad en la interfaz: la pantalla de «Contraseñas» (P8/P9) explicará que en Windows la protección es la del
   perfil de usuario.

## Consecuencias

- **Hecho:** el almacén, el contrato y las marcas del bloqueo funcionan en Windows (P4d; `KeychainCredencialesWindowsTests`, `LedgerProcesosTests`).
- **Pendiente en P9:** el aviso de la pantalla de «Contraseñas»; evaluar DPAPI como capa extra (C) sin romper la
  compatibilidad con el Administrador del sistema; revisar la ADR-0002 con el matiz de arriba.
- **Pendiente de P4e/P10:** el flujo completo con askpass. `SSH_ASKPASS` y `SSH_ASKPASS_REQUIRE=force` apuntan al propio
  ejecutable de la app (`NETDECK_ASKPASS=1`), que necesita una ruta estable tras instalar (ADR-0003) y comprobarse con
  `ssh.exe`; mientras tanto sólo funcionan claves y agente. `TerminalEnvironment` ya quita de ssh las variables
  `SSH_ASKPASS*` heredadas para que no compitan con el askpass de la app.
- **Riesgo aceptado:** un proceso malicioso del mismo usuario puede leer las contraseñas guardadas. La mitigación es no
  guardarlas cuando importa (claves y agente), que sigue siendo la recomendación.
