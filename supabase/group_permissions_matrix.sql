-- Add a configurable admin/member permission matrix to groups.
-- Run in the PRIMARY Supabase project's SQL Editor, after group_member_admin_role.sql.

alter table public.groups
  add column if not exists permissions jsonb not null default '{
    "admin": {
      "delete_group": true,
      "manage_member_roles": false,
      "edit_others_tasks": true,
      "delete_others_tasks": true
    },
    "member": {
      "delete_group": false,
      "manage_member_roles": false,
      "edit_others_tasks": true,
      "delete_others_tasks": true
    }
  }'::jsonb;
