# Futsal — Attendance Tracker

A single-page attendance tracker for a futsal group: mark players Yes/No,
edit the venue and kick-off time, auto-split confirmed players into Group A
and Group B, and export the attendance sheet as a PDF.

No build step, no dependencies — it's one HTML file.

## Run it locally

Just open `index.html` in a browser. That's it.

## Deploy with GitHub Pages

1. Create a new repository on GitHub (or use an existing one) and push these
   files:
   ```bash
   git init
   git add .
   git commit -m "Add futsal attendance tracker"
   git branch -M main
   git remote add origin https://github.com/<your-username>/<your-repo>.git
   git push -u origin main
   ```
2. On GitHub, go to **Settings → Pages**.
3. Under **Build and deployment**, set **Source** to `Deploy from a branch`,
   pick the `main` branch and the `/ (root)` folder, then **Save**.
4. GitHub will publish the site at:
   `https://<your-username>.github.io/<your-repo>/`
   (this can take a minute or two the first time).

## Notes on data storage

Attendance data is saved with the browser's `localStorage`, so it's
**per-device, per-browser** — it won't automatically sync between different
players' phones. It's meant for one person (e.g. the organizer) to manage
attendance on their own device and share the results (via the PDF export)
with the group.

If you want everyone to tick their own name from their own phone and see
a shared, live-updating roster, that needs a small backend or a service
like Firebase/Supabase to store the data centrally — happy to help wire
that up if you'd like.

## Features

- Editable venue and date/kick-off time
- Add/remove players, mark each Yes / No
- Players marked "Yes" are auto-balanced into Group A / Group B (with a
  manual "move" option to swap someone between groups)
- "Download attendance PDF" opens the browser print dialog with a clean
  summary sheet — choose "Save as PDF" as the destination

## Login / Account

The app now requires signing in before use, via Supabase Auth:

- **Log In** — email + password.
- **Create Account** — email, display name, password, confirm password.

It's wired to this Supabase project:
- Project URL: `https://lnikyfsqoylfgwsvegsq.supabase.co`
- Publishable key: `sb_publishable_4PVeckKY4sIQQ_9W11cAFg_H9k1YMX6`

If email confirmation is enabled on the Supabase project (Authentication →
Settings), new users must click the confirmation link in their email before
they can log in. You can turn this off in the Supabase dashboard under
**Authentication → Providers → Email → Confirm email** if you want instant
sign-in without email verification.

Attendance data itself is still saved to `localStorage`, per browser — only
login/signup go through Supabase for now. Let me know if you'd like the
roster synced live across everyone's devices next.

## Roles

- **Admin** (`whitewalkerofnorth@gmail.com`, shown as "ARUN"): can edit venue/time, add guest players, remove any player, move any player between Group A/B, and reset attendance for everyone.
- **Everyone else**: automatically appears in the roster under their own signed-in display name, can mark only their own YES/NO, and can view the roster, groups, and download the attendance PDF — they cannot edit match info, add/remove players, or move anyone between groups.

Roles are determined by the logged-in email matching the admin address above, and enforced both in the UI and at the database level via Row Level Security (see the setup section below) — so the restriction holds even if someone bypasses the UI.

## Real-time shared roster (Supabase database)

Attendance, the roster, and match info now live in Supabase (Postgres +
Realtime) instead of `localStorage` — everyone signed in sees admin's
changes appear instantly, no refresh needed.

**One-time setup:** open your Supabase project's **SQL Editor** and run
`supabase-setup.sql` (included alongside this file). It creates two tables:

- `match_info` — a single row with `venue` and `kickoff_time`
- `players` — one row per player (a signed-in user or an admin-added guest),
  with `display_name`, `attend`, and `group_name`

It also sets up Row Level Security so that, even outside the app's UI, only
the admin account can edit match info, add/remove players, or move players
between groups — everyone else can only edit their own attendance. Realtime
broadcasting is enabled for both tables so every connected browser gets
live updates.

**How players show up:** when anyone logs in, they automatically get their
own row in the roster using their signed-in display name — there's no
separate "add yourself" step. The admin can additionally add guest players
who don't have an account.

**Reset button:** the admin has a "Reset all attendance" button that clears
everyone's YES/NO and group assignment (for starting a new match) without
deleting anyone from the roster.

