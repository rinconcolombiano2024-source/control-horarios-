import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);
const migrationUrl = new URL("supabase/migrations/0001_foundation.sql", root);
const tables = [
  "organizations", "locations", "user_profiles", "permissions", "roles",
  "role_permissions", "organization_memberships", "membership_roles",
  "membership_location_access", "positions", "cost_centers", "work_areas",
  "employees", "employee_location_assignments", "contract_types",
  "employee_contracts", "employee_compensation_rates", "organization_policies",
  "feature_flags", "audit_log",
];

test("migration is transactional and creates every foundation table with RLS", async () => {
  const sql = await readFile(migrationUrl, "utf8");
  assert.match(sql, /^--[\s\S]*\nbegin;/i);
  assert.match(sql, /\ncommit;\s*$/i);
  for (const table of tables) {
    assert.match(sql, new RegExp(`create table public\\.${table} \\(`, "i"), table);
    assert.match(sql, new RegExp(`alter table public\\.${table} enable row level security`, "i"), `${table} RLS`);
  }
});

test("sensitive history is append-only from authenticated clients", async () => {
  const sql = await readFile(migrationUrl, "utf8");
  assert.doesNotMatch(sql, /grant\s+(?:[^;]*\s)?update[^;]*employee_compensation_rates/i);
  assert.doesNotMatch(sql, /grant\s+(?:[^;]*\s)?(?:update|delete)[^;]*audit_log/i);
  assert.match(sql, /audit_log_immutable before update or delete/i);
  assert.match(sql, /exclude using gist[\s\S]*compensation_type with =[\s\S]*daterange/i);
});

test("tenant authorization helpers and onboarding RPC are present", async () => {
  const sql = await readFile(migrationUrl, "utf8");
  for (const fn of ["is_active_org_member", "has_permission", "can_access_location", "employee_is_in_scope", "create_organization_with_owner"]) {
    assert.match(sql, new RegExp(`function public\\.${fn}\\(`, "i"), fn);
  }
  assert.match(sql, /security definer/g);
  assert.match(sql, /set search_path = public, pg_temp/g);
});

test("all dictionaries expose the same foundation keys", async () => {
  const files = await Promise.all(["es", "pl", "en"].map((lang) => readFile(new URL(`i18n/locales/${lang}.ts`, root), "utf8")));
  for (const key of ["phase", "summary", "database", "security", "languages", "next", "ready", "schedules"]) {
    for (const file of files) assert.match(file, new RegExp(`${key}:`), key);
  }
});
