# Control Horarios: reglas permanentes

La especificacion maestra y `docs/task-116-architecture.md` son las fuentes de verdad. Antes de cambiar datos o seguridad, revisar ambos documentos y el esquema existente.

- No cambiar la arquitectura sin una decision documentada.
- No renombrar tablas o columnas directamente; crear una migracion nueva.
- No editar una migracion aplicada. Las correcciones se hacen en otra migracion.
- No escribir textos de interfaz hardcoded; usar claves i18n para `es`, `pl` y `en`.
- No omitir ni relajar RLS para resolver errores.
- No borrar historia laboral, fichajes, contratos, tarifas ni auditoria.
- No permitir escritura directa en tablas sensibles cuando exista una RPC segura.
- No guardar PIN en claro, fotos biometricas crudas ni documentos en buckets publicos.
- No crear columnas duplicadas o equivalentes sin revisar primero el esquema.
- No asumir una sola organizacion, local, moneda, zona horaria o pais.
- Mantener TypeScript estricto, SQL `snake_case`, UUID y `timestamptz`.
- Separar identidad (`auth.users`), perfil (`user_profiles`) y empleado (`employees`).
- Conservar la hora real y la hora de servidor; nunca sustituir eventos originales.
- Toda operacion privilegiada debe comprobar organizacion, local y permiso en servidor.

