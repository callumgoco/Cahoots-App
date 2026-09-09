-- Table-level SELECT/UPDATE include every column, so REVOKE SELECT (apple_subject_id)
-- alone does not hide the column. Re-grant column privileges without apple_subject_id.

revoke select on table public.profiles from anon, authenticated;
grant select (
  id,
  display_name,
  avatar_path,
  timezone_identifier,
  shows_exact_totals,
  created_at,
  updated_at,
  deleted_at,
  appearance_preference
) on table public.profiles to anon, authenticated;

revoke update on table public.profiles from anon, authenticated;
grant update (
  display_name,
  avatar_path,
  timezone_identifier,
  shows_exact_totals,
  updated_at,
  deleted_at,
  appearance_preference
) on table public.profiles to anon, authenticated;
