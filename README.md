# Control Horarios

Aplicacion web/PWA independiente para registrar, controlar y auditar tiempo de trabajo. Esta carpeta no comparte codigo, datos ni configuracion con RC Wallet.

## Estado

Fase 1 — Fundacion en curso. Ya estan definidos y versionados:

- arquitectura completa de las ocho fases;
- modelo multiempresa y multilocal;
- identidad, membresias, roles, permisos y alcance por local;
- empleados, asignaciones, contratos y tarifas historicas;
- politicas, feature flags y auditoria inmutable;
- RLS inicial y RPC atomica de onboarding;
- base i18n para español, polski y English;
- clientes Supabase para navegador y servidor.

No se han construido aun el panel administrativo, horarios ni kiosco. Es intencional: la especificacion exige asegurar primero base de datos, seguridad y pruebas.

## Documentos clave

- `docs/task-116-architecture.md`: respuesta completa a la tarea 116.
- `supabase/migrations/0001_foundation.sql`: primera migracion ordenada.
- `AGENTS.md`: reglas permanentes de mantenimiento.

## Preparacion local

Requisitos: Node.js 22+, pnpm y un proyecto Supabase de desarrollo.

1. Copiar `.env.example` a `.env.local` y añadir URL/anon key del proyecto de desarrollo.
2. Aplicar migraciones primero en Supabase local o staging, nunca directamente en produccion.
3. Ejecutar `pnpm test`, `pnpm run build` y las pruebas SQL/RLS de `supabase/tests`.
4. Iniciar con `pnpm run dev`.

La service role no debe guardarse en variables `NEXT_PUBLIC_*` ni llegar al navegador.

## Migraciones

Una migracion aplicada no se edita. Si cambia el esquema, se crea `0002_...sql` o posterior. La migracion `0001` permanece editable solamente mientras no haya sido aplicada en ningun entorno compartido; registrar esa aplicacion antes de continuar.

## Entornos y operacion

- `development`: datos ficticios y pruebas destructivas permitidas.
- `staging`: ensayo obligatorio de migraciones, RLS, concurrencia y restauracion.
- `production`: solo migraciones ya verificadas y con backup previo.

Backups: usar backups/PITR de Supabase segun el plan contratado, exportacion logica cifrada y prueba trimestral de restauracion en un proyecto aislado. Un backup no se considera valido hasta completar y documentar una restauracion.

