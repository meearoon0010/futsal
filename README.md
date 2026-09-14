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

- **Log In** — email + password, with a "Remember me" checkbox. Checking it
  saves the email and password in that browser's `localStorage` and
  pre-fills them next time, so returning players don't have to retype their
  password. Leaving it unchecked (or unticking it on a later login) clears
  any previously saved credentials on that browser. Since this stores the
  password in plain text in the browser, only use it on a personal device.
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

- **Admin** (`whitewalkerofnorth@gmail.com`, shown as "ARUN"): can edit venue/time, add guest players, remove any player, and reset attendance for everyone.
- **Everyone else**: automatically appears in the roster under their own signed-in display name, can mark only their own YES/NO, and can view the roster, groups, and download the attendance PDF — they cannot edit match info or add/remove players.
- **Moving players between Group A / Group B** is open to anyone signed in (not just the admin) — tap a player's group tag in the roster, or use the "move →" / "← move" buttons in the Teams section.

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

## Adding a player straight into a group

Next to "Add player name," the admin now has a group dropdown
("No group yet" / "Group A" / "Group B"). Choosing a group and clicking
"Add" marks that player YES and places them directly into that group —
useful for guests the admin already knows are playing and knows which
side they should be on. Leaving it as "No group yet" behaves as before:
the player sits in the roster unassigned until someone marks them YES,
at which point they're auto-balanced into whichever group is smaller.

## "Are you playing?" prompt

Right after logging in, if a player hasn't answered yet for the current
match, a small modal asks "Are you playing?" with YES / NO buttons. This
uses the same attendance mechanism as the roster toggles, so answering
here immediately places them in a group if they say YES. Choosing
"Decide later" dismisses it for now — they can still answer anytime from
their row in the roster. If the admin uses "Reset all attendance," the
prompt will show again for everyone next time they interact with the app,
since their attendance is cleared back to unanswered.

## Admin "Add player" fix

The admin's "Add player" insert was hardened against a silent RLS
failure: the database policies now compare the admin's email
case-insensitively, and any insert error is now shown in the status
line (open the browser console for the full message) instead of failing
silently. Re-run the latest `supabase-setup.sql` in the SQL Editor to pick
up this fix — it's safe to run again even if you've already run an
earlier version. Guest players added this way still never need an
account — user_id is simply left blank for them.

## Group moves opened up to everyone

Previously only the admin could move a player between Group A and Group B.
The database policy and its guard trigger were updated so any signed-in
user can change a player's `group_name` (attendance and profile fields are
still admin/owner-only). Re-run the latest `supabase-setup.sql` in the SQL
Editor to pick up this change — it's safe to run again.

## Balance table

The homepage now shows every player's balance (in Rs.), right below the
roster:

- **Everyone** can see everyone's balance.
- **Only the admin** can change a balance — tap the amount to set it to an
  exact figure, or use "+ Add" to top it up by an amount you type in.
- **Only the admin** can send a **"Send renew payment"** reminder for a
  player. Doing so pops a "Renew payment" message for that player — shown
  exactly once per reminder (it won't re-pop on a page reload, closing and
  reopening the app, or "remember me" auto-login), and never at the same
  time as the "Are you playing?" prompt. The player's own "Got it" button
  only closes that popup for them — it does **not** clear the reminder.
  The shared "Renew payment" tag next to that player's balance stays
  visible to everyone until the admin either taps "Reminder sent" again to
  cancel it, or updates that player's balance (setting/adding an amount
  automatically clears the reminder too, since that's how the admin
  records a payment coming in). If the admin cancels a reminder and later
  sends a genuinely new one, the popup shows again once for that new
  reminder.
- Balances at or below zero are shown in red. When the admin sends a
  reminder for a player, a small **"Renew payment"** tag appears next to
  that player's balance — visible to everyone, not just the admin — until
  the player dismisses the popup (or the admin cancels it).
- **"Download balance PDF"**, below the balance table, works the same way
  as the attendance PDF — it opens the browser's print dialog with a clean
  player/balance/status sheet; choose "Save as PDF" as the destination.
  Any signed-in user can do this, not just the admin.

This is enforced at the database level too: only the admin can change a
`balance` value, and only the admin can raise or clear a `payment_reminder`
— not even the row's own owner can touch it, so the shared status can't be
dismissed by anyone but the admin (or cleared automatically by an admin
balance update). Re-run the latest `supabase-setup.sql` to pick up the new
`balance` / `payment_reminder` columns and policies.

