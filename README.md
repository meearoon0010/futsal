# Futsal — Attendance Tracker

A single-page attendance tracker for a futsal group: sign up / log in,
mark players Yes/No, edit the venue and kick-off time, auto-split confirmed
players into Group A and Group B, and export the attendance sheet as a PDF.
The roster is stored in Supabase, so it's shared and stays in sync live
across everyone who's signed in.

No build step, no framework — it's one HTML file plus Supabase.

## 1. Create a Supabase project

1. Go to [supabase.com](https://supabase.com), sign in, and create a new
   project (the free tier is enough for this).
2. Once it's ready, open **Project Settings → API**. You'll need:
   - **Project URL**
   - **anon public** key

## 2. Create the shared roster table

In your Supabase project, open the **SQL Editor** and run:

```sql
create table if not exists public.futsal_state (
  id text primary key default 'main',
  venue text not null default 'Central Futsal Arena',
  match_time text not null default 'Fri, 7:00 PM',
  players jsonb not null default '[]',
  updated_at timestamptz not null default now()
);

alter table public.futsal_state enable row level security;

create policy "Authenticated users can read state"
on public.futsal_state for select
to authenticated
using (true);

create policy "Authenticated users can insert state"
on public.futsal_state for insert
to authenticated
with check (true);

create policy "Authenticated users can update state"
on public.futsal_state for update
to authenticated
using (true);
```

This creates one shared row (`id = 'main'`) that holds the venue, time, and
full player list, plus policies so any **logged-in** user can read and write
it. (There's no policy for anonymous/public access, so signed-out visitors
can't see or change anything.)

Also turn on Realtime for the table so changes sync live: **Database →
Replication** (or **Table Editor** → the table's menu) → enable Realtime for
`futsal_state`.

## 3. Turn on email/password auth

Auth → Providers → **Email** is enabled by default in new Supabase
projects, so sign-up/login will work out of the box. Two settings worth
knowing about, under **Auth → Providers → Email**:

- **Confirm email** is on by default — new users get a confirmation email
  before they can log in. Turn it off there if you want people to be able
  to sign up and use the app immediately, with no email step.

## 4. Connect the app to your project

Open `index.html` and near the top of the `<script>` block, replace:

```js
const SUPABASE_URL = 'YOUR_SUPABASE_URL';
const SUPABASE_ANON_KEY = 'YOUR_SUPABASE_ANON_KEY';
```

with the **Project URL** and **anon public** key from step 1. Save the
file — that's the only code change needed.

## 5. Run it locally

Just open `index.html` in a browser. Create an account (or log in), and
you're in.

## 6. Deploy with GitHub Pages

1. Push these files to a GitHub repository:
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

Your `SUPABASE_ANON_KEY` is meant to be public-facing (it's safe to ship in
client-side code as long as your row-level security policies are correct,
which the SQL above sets up) — so it's fine that it ends up visible in the
deployed page's source.

## Features

- Create an account or log in with email + password (Supabase Auth)
- Editable venue and date/kick-off time
- Add/remove players, mark each Yes / No
- Players marked "Yes" are auto-balanced into Group A / Group B (with a
  manual "move" option to swap someone between groups)
- Roster is stored in Supabase and synced live across every signed-in
  device — no more per-browser copies
- "Download attendance PDF" opens the browser print dialog with a clean
  summary sheet — choose "Save as PDF" as the destination

## Notes

- Anyone who creates an account can add, edit, or clear the whole roster —
  there's no per-player permission model. That's fine for a small trusted
  group; if you need finer-grained control (e.g. only the organizer can
  edit venue/time), that's a further step on top of this.
