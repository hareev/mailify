# Mailify — connecting Gmail

The app talks to Gmail directly over its REST API using your own Google OAuth
client — there's no backend server involved, and no SDK is used (just
`URLSession` + `AuthenticationServices`). This is a one-time, manual setup you
do yourself in Google Cloud Console, because it requires your own Google
account and can't be done on your behalf.

## 1. Create a Google Cloud project

Go to [console.cloud.google.com](https://console.cloud.google.com), create a
new project (any name — e.g. "Mailify").

## 2. Configure the OAuth consent screen

APIs & Services → OAuth consent screen:

- User type: **External** (unless you have Google Workspace, in which case
  Internal is simpler and skips the "unverified" warning entirely).
- App name: "Mailify" (or anything).
- Scopes: add exactly these two —
  - `https://www.googleapis.com/auth/gmail.readonly`
  - `https://www.googleapis.com/auth/gmail.compose`

  Deliberately **not** `gmail.modify` — that scope additionally grants
  label/delete/archive rights the app doesn't need. Least privilege.
- Under **Test users**, add your own Google account. This is required —
  since the app stays unpublished/unverified, only accounts explicitly
  listed as test users can complete the OAuth flow.

## 3. Enable the Gmail API

APIs & Services → Library → search "Gmail API" → **Enable**.

## 4. Create an OAuth client ID

APIs & Services → Credentials → Create Credentials → OAuth client ID.

- Application type: **Desktop app** — not "Web application". Desktop app is
  the client type that supports the PKCE flow this app uses (no server-side
  redirect, no confidential backend).
- Name it anything.
- After creation, copy both the **Client ID** and **Client Secret** shown.

(Google still issues a client secret for Desktop-app clients, and the token
exchange does require sending it even though PKCE is in use — Google
classifies this value as non-confidential for installed apps, which is why
it's safe to embed directly in the app's source rather than needing a real
backend to hold it.)

## 5. Paste your credentials into the app

`Sources/Mailify/Gmail/GmailOAuthManager.swift` is gitignored (it holds a
real Google OAuth client secret once filled in) — a fresh clone only has the
template at
[Sources/Mailify/Gmail/GmailOAuthManager.swift.example](Sources/Mailify/Gmail/GmailOAuthManager.swift.example).
Copy it into place first:

```sh
cp Sources/Mailify/Gmail/GmailOAuthManager.swift.example Sources/Mailify/Gmail/GmailOAuthManager.swift
```

Then open the copy and replace the two placeholder constants near the top:

```swift
private let clientID = "YOUR_CLIENT_ID.apps.googleusercontent.com"
private let clientSecret = "YOUR_CLIENT_SECRET"
```

with the values from step 4. Rebuild (`swift build` or `./build-app.sh`).

## 6. First connect

In the app, go to **Settings → Accounts** and click **Connect** on the Gmail
card. A system sign-in sheet will appear.

You'll see an **"unverified app"** warning the first time — this is expected
for a Test-User-only app that hasn't gone through Google's verification
review. Click **Advanced → Go to Mailify (unsafe)** to continue. This is safe:
it's your own OAuth client, requesting only read + compose-draft access to
your own mailbox.

Once connected, the Accounts pane will show your connected Gmail address, and
**Sync Now** (toolbar or menu bar) will start pulling mail.

## Reminder: what this app will never do

It can read your mail and create drafts in your Gmail **Drafts** folder. It
will **never** send anything — there is no send code path anywhere in the
app. Every AI-drafted reply sits in Suggestions for you to Accept (creates a
real Gmail draft, ready for you to review and send yourself) or Dismiss.
