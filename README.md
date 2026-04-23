# Messenger Chat

Messenger Chat is now configured for **Vercel + Supabase**.

## 1. Set up Supabase

1. Create a Supabase project.
2. In Supabase SQL Editor, run:
   - `supabase/schema.sql`
   - If the app is already deployed, re-run the updated `supabase/schema.sql` to add `display_name` support plus admin moderation RPCs/policies (`invite_to_group`, `ban_user`).
3. In Supabase Auth:
   - Enable Email sign-in.
   - (Optional) disable email confirmation for faster testing.
   - If confirmation emails are not arriving, check:
     - **Auth → URL Configuration** includes your deployed app URL.
     - **Auth → Email** provider is enabled.
     - For reliable delivery, configure custom SMTP in Supabase Auth Email settings.
     - Spam/junk folder and any provider rate limits.
4. Copy:
   - Project URL
   - Anon public key

## 2. Add Supabase keys in this repo

Edit `static/config.js`:

```js
window.MESSENGER_CONFIG = {
  supabaseUrl: "https://YOUR_PROJECT_ID.supabase.co",
  supabaseAnonKey: "YOUR_SUPABASE_ANON_KEY"
};
```

Commit and push.

## Admin moderation access

- The app now shows an **Admin** message-audit panel only for:
  - `cburdick28@brewstermadrid.com`
- Admin panel includes banning users; banned users are blocked from chat reads/writes/group interactions.
- Re-run `supabase/schema.sql` in your Supabase project so admin moderation policies/functions are applied.

## 3. Deploy on Vercel

Deploy this repo on Vercel normally.

- Root path serves `index.html`
- App UI is `/static/index.html`
- Vercel config is static-only (`vercel.json`)

## Local preview

You can still run the old local Python server:

```bash
pip install -r requirements.txt
python server.py
```

For Vercel behavior, use static hosting and Supabase config.
