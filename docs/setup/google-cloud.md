# Google Cloud setup

Set up on 2026-10-20 under the owner's Google account. None of these values are secrets: iOS OAuth clients have no client secret.

| Item | Value |
|---|---|
| Project | `goodmail-ios` (number 847337870740), billing linked to "My Billing Account" |
| APIs enabled | Gmail, People, Pub/Sub |
| Pub/Sub topic | `projects/goodmail-ios/topics/gmail-push`, where `gmail-api-push@system.gserviceaccount.com` has `roles/pubsub.publisher` |
| Pub/Sub subscription | `gmail-push-worker`, pushing to `https://goodmail-push.goodmail-push-worker.workers.dev/v1/pubsub` with OIDC tokens for `gmail-push-invoker@goodmail-ios.iam.gserviceaccount.com` (created 2026-11-13) |
| OAuth audience | External, **In production**, unverified (published 2026-11-22, ADR-009). Never submitted for verification, so sign-in shows the "unverified app" warning and the 100-user cap applies. The test-user list (the owner's Google account and the dedicated test Gmail account, ADR-010) no longer limits who can sign in. |
| OAuth scopes | `https://mail.google.com/` (restricted, for Delete Forever, ADR-019), `gmail.settings.basic` (restricted); `contacts.readonly`, `contacts.other.readonly` (sensitive); `openid`, `userinfo.email` |
| iOS OAuth client | "Goodmail iOS", bundle ID `com.idanbirman.goodmail`, Team ID `72D8U72V55`, App Store ID `6834185190` (set 2026-11-17) |
| Client ID | `847337870740-fpj7hd07nfsueispeug4nell21pf3vi2.apps.googleusercontent.com` |
| Redirect scheme | `com.googleusercontent.apps.847337870740-fpj7hd07nfsueispeug4nell21pf3vi2:/oauthredirect` |

## Publishing status

The app was published to "In production" on 2026-11-22 (ADR-009), so refresh tokens no longer expire after 7 days. Publishing needed a home page, a privacy policy and an authorized domain, so with no domain of its own the Branding page points at the public repo: home page `https://github.com/shinycake/goodmail`, privacy policy `docs/release/privacy.md` on `main` there, authorized domain `github.com`. Keep that file at that path or update Branding. A token issued while the app was still in Testing keeps its 7-day life, so each Gmail account signed in before then had to sign in once more. Don't submit the app for verification: the restricted Gmail scopes would need a CASA assessment, and a personal app under 100 users doesn't need it.

## Reproducing with the CLI

```bash
gcloud projects create goodmail-ios --name=Goodmail
gcloud billing projects link goodmail-ios --billing-account=<ACCOUNT_ID>
gcloud services enable gmail.googleapis.com people.googleapis.com pubsub.googleapis.com --project=goodmail-ios
gcloud pubsub topics create gmail-push --project=goodmail-ios
gcloud pubsub topics add-iam-policy-binding gmail-push --project=goodmail-ios \
  --member=serviceAccount:gmail-api-push@system.gserviceaccount.com --role=roles/pubsub.publisher
```

The consent screen, the scopes and the iOS client are set up in the console only, under Google Auth Platform.
