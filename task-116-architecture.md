# Tarea 116 — arquitectura de Control Horarios

Estado: aprobado como linea base de arquitectura, antes de las fases funcionales. La especificacion maestra de 118 apartados prevalece sobre este documento; este archivo concreta las decisiones necesarias para implementarla sin ambiguedades.

## 1. Principios y limites

1. PostgreSQL/Supabase es la fuente de verdad. El cliente no decide identidad, permisos, hora oficial, transiciones laborales ni cierres.
2. Todo dato empresarial lleva `organization_id`; todo dato fisicamente localizado lleva ademas `location_id`.
3. Identidad, perfil de acceso y relacion laboral son conceptos distintos: `auth.users` → `user_profiles` → `employees.user_id` opcional.
4. Los eventos laborales, auditoria, contratos y tarifas son historicos. Se agregan versiones o correcciones; no se sobrescriben.
5. Las acciones sensibles se exponen mediante RPC `security definer` de superficie minima, con validacion y auditoria atomicas.
6. RLS se habilita desde la primera migracion. No se otorga escritura sensible directa a `authenticated`.
7. Los instantes se guardan como `timestamptz`; `work_date` conserva el dia laboral local y la zona del local determina la presentacion.
8. Los catalogos que el negocio debe poder ampliar (tipos de contrato, pausas, ausencias, documentos) son tablas, no enums.
9. Los estados cerrados y snapshots incluyen la version de reglas para que los informes sean reproducibles.
10. La Fase 1 crea solamente la base transversal y de personal. El resto se cataloga ahora pero se migra en su fase.

## 2. Arquitectura de carpetas

```text
app/                         rutas y composicion, sin reglas de negocio
components/                  componentes compartidos pequeños
features/
  auth/                      sesion y contexto de organizacion
  organizations/             organizacion y locales
  employees/                 empleados, asignaciones y ficha
  contracts/                 historial contractual
  compensation/              historial salarial protegido
  attendance/                fases 3–4; cliente de RPC, nunca insert directo
  schedules/                 fase 2
  payroll/                   fase 6
i18n/
  config.ts
  locales/{es,pl,en}.ts      todo texto visible
lib/
  supabase/{browser,server}.ts
  authorization/             tipos y comprobaciones de interfaz (no autoridad)
  time/                      zonas, DST y work_date
services/                    adaptadores de API/RPC por dominio
types/                       tipos compartidos y generados desde Supabase
supabase/
  migrations/               append-only, orden cronologico
  seed.sql                   solo datos ficticios de desarrollo
  tests/                     pruebas SQL, RLS y concurrencia
docs/                        decisiones, modelo y operacion
tests/                       pruebas unitarias/contratos estaticos
public/                      manifest e iconos PWA; nunca documentos privados
```

Las reglas de calculo viven en SQL/servicios de dominio, nunca en componentes. El almacenamiento privado usa Supabase Storage con metadatos en PostgreSQL.

## 3. Catalogo completo de tablas por fase

### Fase 1 — Fundacion (incluidas en migracion 0001)

| Tabla | Proposito |
|---|---|
| `organizations` | Tenant, idioma/moneda/zona por defecto y estado. |
| `locations` | Locales del tenant, pais, moneda, zona y configuracion. |
| `user_profiles` | Perfil de aplicacion 1:1 con `auth.users`; no es empleado. |
| `roles` | Roles base o personalizados por organizacion. |
| `permissions` | Catalogo global y estable de permisos granulares. |
| `role_permissions` | Permisos efectivos de cada rol. |
| `organization_memberships` | Acceso de un usuario a una organizacion y vigencia temporal. |
| `membership_roles` | Multiples roles por membresia, tambien temporales. |
| `membership_location_access` | Limita una membresia a locales; ausencia significa todos solo si el rol lo autoriza. |
| `positions` | Puestos por organizacion. |
| `cost_centers` | Centros de coste por organizacion. |
| `work_areas` | Areas opcionales de trabajo por local/organizacion. |
| `employees` | Persona laboral; `user_id` es opcional y unico cuando existe. |
| `employee_location_assignments` | Relacion historica empleado-local-puesto-area-centro. |
| `contract_types` | Catalogo configurable de tipos contractuales. |
| `employee_contracts` | Versiones contractuales historicas, nunca sobrescritas. |
| `employee_compensation_rates` | Tarifas historicas, intervalos sin solapamiento por tipo. |
| `organization_policies` | Politicas centralizadas, versionadas y con JSON validado por servicio. |
| `feature_flags` | Funciones activables por organizacion o local. |
| `audit_log` | Registro inmutable de acciones sensibles. |

### Fase 2 — Horarios

`schedule_templates`, `schedule_template_slots`, `schedule_publications`, `schedule_shifts`, `schedule_shift_versions`, `employee_availability`, `shift_swap_requests`, `shift_swap_participants`, `notifications`.

### Fase 3 — Fichaje

`devices`, `employee_credentials`, `authentication_attempts`, `attendance_evidence_photos`, `attendance_sessions`, `attendance_events`, `break_types`, `attendance_breaks`, `offline_event_receipts`, `device_health_checks`.

`attendance_sessions` es una proyeccion transaccional del turno real (abierto/cerrado); la evidencia autoritativa sigue siendo `attendance_events`. Permite un indice unico de un turno abierto por empleado y bloqueo de fila en RPC.

### Fase 4 — Administracion y revision

`attendance_anomalies`, `attendance_correction_requests`, `attendance_event_corrections`, `overtime_requests`, `incidents`.

Las correcciones apuntan al evento original y crean una version efectiva; nunca ejecutan `UPDATE` destructivo sobre `attendance_events`.

### Fase 5 — Ausencias y documentos

`absence_types`, `employee_absences`, `holiday_calendars`, `holidays`, `document_types`, `employee_documents`, `document_expiration_alerts`, `policy_documents`, `policy_acceptances`, `retention_policies`, `legal_holds`.

### Fase 6 — Calculo, informes y nomina

`calculation_rule_versions`, `daily_attendance_calculations`, `payroll_periods`, `payroll_period_versions`, `payroll_employee_snapshots`, `payroll_daily_snapshots`, `report_exports`, `employee_report_confirmations`.

### Fase 7 — Offline

`offline_sync_batches`, `offline_sync_items`, `sync_conflicts`. La cola local cifrada no es tabla servidor; al sincronizar se registra cada recepcion con idempotencia.

### Fase 8 — Hardware

`device_integrations`, `biometric_credential_references`, `hardware_diagnostics`. Solo se guardan referencias/templates del proveedor cifrados, nunca imagenes crudas de huella.

### Transversales futuras

`system_logs`, `data_import_jobs`, `data_import_rows`, `bulk_action_previews`, `purge_jobs`, `backup_restore_tests`, `app_releases`.

## 4. Relaciones principales

- `organizations 1—N locations`, roles, membresias, empleados, catalogos, politicas, flags y toda entidad de negocio.
- `auth.users 1—1 user_profiles`; `auth.users 1—N organization_memberships`.
- `organization_memberships N—N roles` mediante `membership_roles` y `N—N locations` mediante `membership_location_access`.
- `roles N—N permissions` mediante `role_permissions`.
- `employees N—0..1 auth.users`; un usuario puede vincularse como empleado en distintas organizaciones, pero una vez por organizacion.
- `employees N—N locations` historicamente mediante `employee_location_assignments`; cada asignacion puede referir `positions`, `work_areas` y `cost_centers` de la misma organizacion.
- `employees 1—N employee_contracts` y `1—N employee_compensation_rates`.
- `schedule_publications 1—N schedule_shift_versions`; `schedule_shifts` identifica el turno logico y su version publicada vigente.
- `employees 1—N attendance_sessions 1—N attendance_events`; un evento puede enlazar un `schedule_shift`, `device` y foto de evidencia.
- `attendance_events 1—N attendance_event_corrections`; solicitudes, aprobaciones y auditoria conservan actor y motivo.
- `attendance_sessions 1—N attendance_breaks`; cada pausa referencia `break_types` y sus eventos de inicio/fin.
- `payroll_periods 1—N payroll_period_versions 1—N payroll_employee_snapshots 1—N payroll_daily_snapshots`.
- `policy_documents 1—N policy_acceptances`; una aceptacion siempre referencia una version concreta.
- Todas las referencias entre tablas de tenant se validan con claves foraneas compuestas `(organization_id, id)` cuando cruzan entidades de negocio, evitando referencias entre organizaciones.

## 5. Enums de dominio

Enums iniciales de Fase 1:

- `supported_language`: `es`, `pl`, `en`.
- `organization_status`: `active`, `suspended`, `archived`.
- `membership_status`: `invited`, `active`, `suspended`, `revoked`.
- `employee_status`: `pending`, `active`, `suspended`, `terminated`, `archived`.
- `contract_status`: `draft`, `active`, `ended`, `cancelled`.
- `compensation_type`: `hourly`, `monthly`.
- `policy_scope`: `organization`, `location`.

Enums previstos por fases:

- Horarios: `schedule_shift_status` (`draft`, `published`, `changed`, `cancelled`, `completed`), `availability_kind` (`available`, `unavailable`, `preferred`), `request_status`, `swap_status`.
- Fichaje: `attendance_event_type` (`CLOCK_IN`, `BREAK_START`, `BREAK_END`, `CLOCK_OUT`), `attendance_state` (`OFF_DUTY`, `WORKING`, `ON_BREAK`), `attendance_event_status` (`accepted`, `pending_review`, `conflict`, `rejected`, `superseded`), `attendance_source` (`kiosk`, `web`, `mobile`, `offline_sync`, `admin_rpc`, `integration`), `authentication_method` (`fingerprint`, `pin`, `qr`, `nfc`, `admin_override`), `device_status` (`pending`, `active`, `suspended`, `revoked`), `sync_status` (`pending`, `synced`, `conflict`, `rejected`).
- Revision: `correction_status` y `overtime_status`; ambos incluyen `pending`, `approved`, `rejected`, `cancelled` (overtime agrega `detected`).
- Ausencias: `absence_status` (`requested`, `approved`, `rejected`, `cancelled`).
- Nomina: `payroll_period_status` (`open`, `reviewing`, `approved`, `closed`, `reopened`).

No son enums: pais ISO, moneda ISO-4217, zona IANA, tipos de contrato/pausa/ausencia/documento, acciones de auditoria ni permisos; necesitan evolucionar sin migrar tipos PostgreSQL.

## 6. Roles, permisos y alcance

Los roles son conjuntos editables; la autorizacion real consulta permisos y alcance, no el nombre. Roles base:

| Capacidad | owner | admin | manager | payroll | employee |
|---|:---:|:---:|:---:|:---:|:---:|
| Gestion global y seguridad | ✓ | segun delegacion | — | — | — |
| Empleados | total | ver/editar | locales asignados | solo datos de nomina | propio |
| Salarios | ✓ | permiso explicito | no por defecto | ✓ | solo si politica+permiso |
| Horarios/fichajes | ✓ | ✓ | locales asignados | lectura necesaria | propios |
| Aprobar/corregir | ✓ | permiso | permiso y locales | no por defecto | nunca propio |
| Cerrar nomina | ✓ | permiso | — | permiso | — |
| Auditoria/exportar | ✓ | permiso | permiso | exportacion de nomina | — |

Catalogo inicial de permisos: `organizations.view`, `organizations.manage`, `locations.view`, `locations.manage`, `memberships.view`, `memberships.manage`, `roles.view`, `roles.manage`, `employees.view`, `employees.create`, `employees.edit`, `employees.archive`, `employees.salary.view`, `employees.salary.manage`, `employees.documents.view`, `employees.documents.manage`, `attendance.view`, `attendance.edit`, `attendance.approve`, `overtime.approve`, `schedules.view`, `schedules.create`, `schedules.publish`, `reports.view`, `reports.export`, `payroll.view`, `payroll.close_period`, `payroll.reopen_period`, `settings.manage`, `devices.manage`, `audit.view`.

Las concesiones temporales usan `valid_from`/`valid_until` en membresias, roles y acceso a locales. Una solicitud nunca puede aprobarse por su solicitante cuando la politica de separacion esta activa.

## 7. Estrategia RLS

1. Todas las tablas `public` tienen RLS habilitada y sin acceso anonimo.
2. Funciones privadas `security definer` con `search_path` fijo calculan: membresia activa, permiso vigente, alcance de local y empleado vinculado. Se revoca `EXECUTE` de `public` y se concede solo lo necesario.
3. Las politicas filtran siempre por `organization_id`; para manager agregan alcance de local; para employee comparan `employees.user_id = auth.uid()`.
4. Datos salariales tienen politicas independientes y requieren `employees.salary.view`; nunca se exponen mediante una vista de empleado general.
5. `audit_log` solo permite `SELECT` con `audit.view`. Nadie cliente tiene `INSERT`, `UPDATE` o `DELETE`; triggers/RPC escriben como propietario de funcion.
6. Tablas sensibles (`attendance_events`, correcciones aprobadas, snapshots, credenciales, fotos) no admiten inserts/updates directos. Solo RPC valida estado, dispositivo, politica, idempotencia y cierre.
7. Storage usa buckets privados separados (`employee-profile-photos`, `attendance-evidence`, `employee-documents`, `report-exports`) y politicas que consultan metadatos/permiso. El path no es autorizacion.
8. Las pruebas RLS usan usuarios de dos organizaciones y cubren lectura cruzada, salario, escritura de eventos, autoaprobacion y auditoria.
9. Service role queda solo en procesos backend; nunca llega al navegador.

## 8. Flujo exacto CLOCK_IN

1. Kiosco obtiene un desafio efimero y autentica el dispositivo revocable.
2. Empleado se identifica por metodo permitido; el backend verifica credencial, bloqueo, estado activo y asignacion vigente al local.
3. Backend calcula acciones disponibles bloqueando la fila/proyeccion de sesion del empleado. Debe estar `OFF_DUTY` y no existir sesion abierta.
4. Busca turno planificado aplicable y evalua politica de entrada temprana/sin horario. Bloquea, marca revision o exige autorizacion segun configuracion; nunca redondea el evento.
5. Si la politica requiere foto/Ready to Work, valida evidencia en vivo asociada al desafio, dispositivo y local, y confirmacion versionada.
6. El cliente llama `clock_in(p_employee_id, p_device_id, p_idempotency_key, p_declared_event_time, p_evidence_id, ...)`.
7. La RPC usa `clock_timestamp()` como `server_time` y `received_at`; conserva la hora declarada del dispositivo como dato no autoritativo. Para online, `event_time` efectivo es servidor; para offline pasa por RPC de sincronizacion y puede quedar `pending_review/conflict`.
8. En una transaccion crea `attendance_session` abierta y evento `CLOCK_IN`, enlaza foto, registra anomalias y `audit_log`.
9. Restricciones/indice unico e idempotency key impiden doble clic, doble entrada y carreras.
10. Devuelve hora oficial, sesion, estado `WORKING` y avisos; el kiosco muestra confirmacion, borra sesion local y vuelve al inicio.

## 9. Flujo exacto CLOCK_OUT

1. Repite autenticacion de dispositivo y empleado; obtiene la sesion abierta con `FOR UPDATE`.
2. Rechaza si no hay sesion, si ya existe `CLOCK_OUT` o si el periodo esta cerrado. Un cierre administrativo usa otra RPC y motivo obligatorio.
3. Si el estado es `ON_BREAK`, la politica decide bloquear o crear anomalia; nunca inventa silenciosamente `BREAK_END`.
4. Valida foto de salida cuando corresponda y consume idempotency key.
5. Inserta evento `CLOCK_OUT` con tiempos declarados/recibidos/servidor, cierra la sesion y calcula una proyeccion explicable: bruto, pausas pagadas/no pagadas, trabajado y pagado. Los eventos permanecen intactos.
6. Detecta salida temprana, turno largo, overtime, foto ausente o incoherencia y crea anomalias/solicitud segun politica.
7. Audita atomicamente. Devuelve entrada, salida oficial, pausas y tiempo trabajado; el kiosco muestra el resumen y se limpia.
8. Si llega posteriormente una salida offline para una sesion cerrada administrativamente, no sobrescribe: crea `sync_conflict` y revision.

## 10. Contradicciones y resoluciones

| Tension en la especificacion | Resolucion |
|---|---|
| Stack “recomendado” vs seguridad Supabase obligatoria | React/TypeScript/Vite se mantienen; Supabase/PostgreSQL/Auth/Storage/RLS son obligatorios. La capa Sites solo empaqueta la web y no reemplaza Supabase. |
| Entidad `users` vs separacion de `auth.users` | Se usa `user_profiles`; evita duplicar identidad y deja clara la relacion opcional del empleado. |
| `primary_location_id` del empleado vs no guardar restaurante unico | Es solo preferencia/ubicacion primaria y debe corresponder a una asignacion; autorizacion y trabajo real usan `employee_location_assignments`. |
| Tipos de contrato “configurables” con ejemplos fijos | Tabla `contract_types`, no enum. |
| `event_time`, `received_at`, `server_time` parecen redundantes | `event_time` es instante efectivo, `received_at` recepcion inicial y `server_time` hora oficial de la decision. Para online pueden coincidir; no se eliminan por trazabilidad offline. |
| Foto debe guardarse junto al evento, pero la subida puede fallar | Primero se crea evidencia temporal privada; la RPC la consume y enlaza atomicamente. Si la politica exige foto, no crea evento sin evidencia valida. |
| Correccion de un evento vs prohibicion de modificarlo | Tabla de correcciones versionadas y vista/proyeccion efectiva; el original no cambia. |
| Un empleado puede recontratarse sin duplicarse | La persona permanece; nuevos contratos/asignaciones. Fechas generales de alta/baja son resumen, no reemplazan historial. |
| Roles base vs no depender del rol | Los roles solo preconfiguran permisos; RLS consulta permisos y alcance vigentes. |
| RLS de manager por local cuando empleados tienen varios locales | Visibilidad si existe asignacion vigente en un local autorizado; datos globales/salariales exigen permiso adicional. |
| Offline y hora controlada por servidor | Se conserva hora declarada y recepcion; eventos offline no confiables pueden requerir revision. La sincronizacion nunca finge que la hora de recepcion fue la del trabajo. |
| Auditoria inmutable vs necesidad operativa de correccion | No se corrige el log; se agrega otro evento de auditoria que referencia la accion previa. |
| Campos de configuracion con nombres distintos (`photo_required_*` / `photo_on_*`) | Se canonizan como claves documentadas versionadas: `attendance.photo_required.clock_in/out/break`; alias de entrada solo en importacion. |

## 11. Orden de la migracion inicial

`0001_foundation.sql` se organiza en: extensiones → enums → tablas tenant/identidad → RBAC → catalogos → empleados → contratos/tarifas → politicas/flags → auditoria → indices/constraints → funciones auxiliares → RLS → seeds de permisos/roles. La migracion no se considera aplicada hasta ejecutarse en un entorno Supabase local/staging y pasar pruebas; una vez aplicada queda inmutable.

Fase 1 no implementa todavia la UI grande, el kiosco ni las RPC de fichaje. Deja los limites y permisos listos para que las fases siguientes no reconstruyan la base.

