# Google Calendar credentials

Google's API *key* alone cannot read or write a private calendar. Writing
appointments requires an **OAuth 2.0 Client ID** of type **Desktop app**. The
app signs you in through your browser once and caches a refresh token.

Put the downloaded JSON in this directory (any `*.json` name; the app uses the
first one it finds that is not `token.json`). **`keys/*.json` is git-ignored.**

## Step by step

1. Go to <https://console.cloud.google.com/> and sign in.
2. Create a project (top bar -> project picker -> *New Project*), e.g. `gcal-access`.
3. Enable the API: *APIs & Services -> Library -> "Google Calendar API" -> Enable*.
4. Configure consent: *APIs & Services -> OAuth consent screen* (or *Google Auth Platform*).
   - User type **External** (or Internal on a Workspace domain).
   - Fill in app name and your email.
   - Add scope `https://www.googleapis.com/auth/calendar` (or `.../calendar.events`).
   - While the app is in *Testing*, add your Google account under **Test users**.
5. Create the credential: *APIs & Services -> Credentials -> Create Credentials ->
   OAuth client ID -> Application type: **Desktop app*** -> Create.
6. Click **Download JSON** on the new client.
7. Save it as `keys/credentials.json` in this project.
8. Run the app. On the first Schedule/calendar load a browser window opens;
   approve access. A `keys/token.json` is then written so you stay signed in.
   Delete `token.json` to sign in again.

## Expected JSON format

The file exactly as Google downloads it:

```json
{
  "installed": {
    "client_id": "1234567890-abcdefg.apps.googleusercontent.com",
    "project_id": "gcal-access",
    "auth_uri": "https://accounts.google.com/o/oauth2/auth",
    "token_uri": "https://oauth2.googleapis.com/token",
    "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
    "client_secret": "GOCSPX-xxxxxxxxxxxxxxxxxxxx",
    "redirect_uris": ["http://localhost"]
  }
}
```

The app only needs `installed.client_id` and `installed.client_secret`
(a top-level `web` key is also accepted, though Desktop app is recommended).

## Notes

- Never commit these files or paste the secret anywhere public.
- `token.json` (created by the app) holds your refresh token; treat it like a password.
