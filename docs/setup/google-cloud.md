# Google Cloud setup

Set up on 2026-10-20 under idan.birman@gmail.com. None of these values are secrets: iOS OAuth clients have no client secret.

| Item | Value |
|---|---|
| Project | `goodmail-ios` (number 847337870740), billing linked to "My Billing Account" |
| APIs enabled | Gmail, People, Pub/Sub |
| Pub/Sub topic | `projects/goodmail-ios/topics/gmail-push`, where `gmail-api-push@system.gserviceaccount.com` has `roles/pubsub.publisher` |
| Pub/Sub subscription | Not created yet. It will be a push subscription to the Worker URL, created in M6 |
| OAuth audience | External, **Testing**. Test users: idan.birman@gmail.com, idanbirmandev@gmail.com (the dedicated test account for fixtures, ADR-010) |
| OAuth scopes | `gmail.modify`, `gmail.settings.basic` (restricted); `contacts.readonly`, `contacts.other.readonly` (sensitive); `openid`, `userinfo.email` |
| iOS OAuth client | "Goodmail iOS", bundle ID `com.idanbirman.goodmail` |
| Client ID | `847337870740-fpj7hd07nfsueispeug4nell21pf3vi2.apps.googleusercontent.com` |
| Redirect scheme | `com.googleusercontent.apps.847337870740-fpj7hd07nfsueispeug4nell21pf3vi2:/oauthredirect` |

## Still to do

- **Publish to "In production" (ADR-009).** The console requires a home page, a privacy policy and an authorized domain before it allows publishing. There is deliberately no domain for now (owner's decision, 2026-10-20). Until then, refresh tokens expire after 7 days.

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
