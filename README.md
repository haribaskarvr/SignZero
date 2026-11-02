# SignZero

**E-signatures that live entirely inside Salesforce.**

Send a PDF for signature from any record, let people sign in their browser without a login, and get the signed
agreement, a Certificate of Completion and a tamper-evident audit trail filed back on the record. No third-party
signing service, no per-envelope fees, and your documents never leave your Salesforce org and the signer's browser.

## Why SignZero

- **Your data stays home.** Every line of code that touches a document runs in your own org. No documents are sent
  to an outside e-signature provider, which keeps security reviews and data-residency questions short.
- **No per-envelope pricing.** Send as many agreements as your org's email limits allow.
- **Built the Salesforce way.** Records, Flow, reports, dashboards, permission sets and Experience Cloud. Admins
  configure it with clicks; developers extend it with an invocable action.
- **Evidence you can rely on.** Every step is written to a hash-chained, append-only audit trail. Each envelope is
  sealed with a document hash and a Certificate of Completion.
- **Fast for signers.** A 50-page agreement opens in about 3 seconds, and signers are guided from one signature place
  to the next.

## How it works

1. **Send.** Click **Send for Signature** on an Account or Opportunity (or call it from any Flow), pick the PDF, and
   add the signers and their order.
2. **Sign.** Each signer gets a personal link, reviews the document, accepts the electronic records disclosure, and
   signs by typing, drawing or uploading their signature.
3. **Done.** When everyone has signed, SignZero seals the document, appends the Certificate of Completion, files it
   on the record and emails a copy to every signer.

## Features

- Multiple signers with routing order: sequential, parallel, or both
- Signature places set by tags in the document, such as `{{sig:Employer}}`, from a picklist of signer roles
- Typed, drawn or uploaded signatures
- ESIGN/UETA consent capture
- Decline to sign, delegate to someone else, resend invitations, and recall an envelope that is still out for signature
- Personal signing links that expire, and turn read-only once signed
- Executed PDF and certificate filed on the source record and any related records
- Automatic reminders on a schedule you set, with a final reminder that states when the link expires
- Bell notifications for the sender at every step, including when a signing link expires unsigned
- Reports and a dashboard for envelopes, turnaround and outstanding signatures
- Your branding: company name, logo and colours on the signing page and in emails
- Every signer-facing word in Custom Labels, ready to reword or translate

## Get started

You need a Salesforce org with Experience Cloud. Create the signing site, deploy SignZero, assign the permission sets
and publish the site. The [technical guide](docs/technical-guide.md) covers each step.

## Documentation

- [Technical guide](docs/technical-guide.md): how it works, components, setup, configuration and the security model
- [Architecture diagrams](docs/architecture/)

## License

SignZero is free and open source under the [Apache License 2.0](LICENSE). It bundles PDF.js (Apache-2.0) and pdf-lib
(MIT); see [NOTICE](NOTICE).
