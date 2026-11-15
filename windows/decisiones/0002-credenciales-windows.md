# Nota de seguridad: CredReadW frente al Llavero de macOS

**Fecha:** 2026-11-15
**Relacionado con:** ADR-0001, paso P4d, revisión P9

## Problema

En macOS, el Llavero asigna una ACL por app a cada credencial: sólo el ejecutable que la creó puede leerla sin
mostrar un diálogo al usuario. En Windows, `CredReadW` con `CRED_TYPE_GENERIC` **no tiene ACL por app**: cualquier
proceso del mismo usuario puede leer la credencial sin confirmación.

## Consecuencias

- Un proceso malicioso con los mismos permisos del usuario puede leer las contraseñas de Terminal NetDeck sin
  intervención del usuario.
- Esto es más débil que macOS pero igual que el comportamiento habitual de los administradores de credenciales de
  Windows (1Password, Bitwarden nativo, el Administrador de credenciales del sistema).

## Mitigación en P9

- Documentar la diferencia en la pantalla de «Contraseñas» de la interfaz (P8), con un aviso si hay más de N
  credenciales guardadas.
- Evaluar si `CryptProtectData` (DPAPI) como capa adicional añade defensa en profundidad sin romper la
  compatibilidad con el Administrador de credenciales del sistema.
- Comprobar que `DebugLog` y `ErrorLog` siguen sin escribir secretos (invariante ya aplicado en P4d).