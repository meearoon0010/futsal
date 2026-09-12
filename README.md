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
