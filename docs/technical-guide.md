# SignZero technical guide

How SignZero works, what it is made of, and how to install and configure it. For an overview, see the
[README](../README.md).

SignZero is native e-signature for Salesforce. SignZero sends a PDF from Salesforce Files to one or more signers, who sign it in
the browser on a public Experience Cloud page without logging in. The signed PDF, a Certificate of Completion and a
hash-chained audit trail are stored back in Salesforce. No third-party e-signature service is involved, and every
piece of code that touches the document is deployed in the customer's own org.

Architecture diagrams live in [architecture](architecture/).

## How it works

1. **Send.** A user runs the **Send for Signature** Flow (a quick action on Account and Opportunity) or calls the
   **Dispatch Document via SignZero** invocable action. SignZero creates a *Signature Request* (the envelope), one
   *Signature Recipient* per signer, and emails the first routing order a personal signing link.
   The flow also takes optional inputs for callers that already have the details: `contentVersionId` (the PDF) and
   `documentTitle` skip choosing or uploading the document, and `signers` also skips the signers screen, so only
   the sent or error screen is shown. SignZero sends the latest version of that ContentVersion's file.
2. **Sign.** The signer opens `https://<site>/esign/?token=…`. The signing portal (`signZeroPortal`) shows the
   document, asks for consent, finds the signer's spots from anchor tags in the PDF, and lets them type, draw or upload
   a signature. Their signature is stamped into the PDF in the browser and submitted.
3. **Progress.** Each submission raises a `SignZero_Event__e` platform event. `SignZeroProgressionJob` invites the next
   routing order, or, when everyone has signed, seals the envelope.
4. **Seal.** `SignZeroSealService` hashes the executed PDF, renders the Certificate of Completion, appends it as a
   final page (`SignZeroPdfAppender`), files the outputs on the source record (and any extra records), and emails
   every signer. The sender gets a bell notification at each step.
5. **Recall (optional).** While an envelope is out for signature, the sender can cancel it with the **Recall Envelope**
   action on the Signature Request, optionally giving a reason. `SignZeroRecallController` sets the envelope to
   *Voided* and signers who had not signed yet to *Voided*, closes every signing link, writes a *Recalled* event per
   signer to the audit trail (who recalled it and why), and emails a cancellation notice to everyone who was already
   sent a link. The signing page then tells signers the request was recalled, and the progression job leaves the
   envelope alone. Completed, sealing, declined and already recalled envelopes cannot be recalled, and the sender needs
   edit access to the envelope. If the cancellation email fails, the recall still stands and the error is kept in
   *Error Message*.

### Anchor tags

Put tags in the document's text where signatures go. They are hidden from signers and removed from the final PDF.

| Tag | Meaning |
|---|---|
| `{{sig:Customer}}` | The *Customer* role signs here, resting on the tag's baseline |
| `{{sig:Customer\|below}}` | Signature hangs below the tag (for a tag above a signature line) |
| `{{sig:Customer\|h=40}}` | Signature box height in points (16–80, default 30) |

A role's name must match the signer's **Signer Role**, a picklist backed by the global value set **SignZero Signer
Role** (Customer, Vendor, Employer, Employee). Add a value there for each new role used in your templates; the Send for
Signature screen offers exactly those roles, and the invocable action rejects any other. If a signer has no tags, they
get one spot at the bottom right of the last page.

### Signing portal and the PDF host page

Lightning Web Security (LWS) blocks Web Workers in components and makes canvas calls 8–12 times slower, which made
large documents slow to open. So the PDF work runs in a small HTML page shipped as the `signZeroPdfHost` static
resource, which the portal loads in a hidden iframe on the same site, outside LWS:

- `index.html` loads `pdf.min.js`, `engine.js` and `pdf-lib.min.js` from the same resource. `engine.js` is SignZero's
  own code: it opens the document (a display copy without tags, page sizes, tag positions), draws pages as images, and
  stamps signatures. PDF.js 3.11.174 (Apache-2.0) and pdf-lib 1.17.1 (MIT) are bundled, not loaded from a CDN; their licences ship
  in the resource (`LICENSE-pdfjs.txt`, `LICENSE-pdf-lib.txt`) and are listed in [NOTICE](../NOTICE).
- The portal and the host page talk only through same-origin `postMessage`. The host page has no Salesforce access;
  it only transforms the bytes it is given.
- The portal loads `/<site>/sfsites/c/resource/signZeroPdfHost/index.html`. The host reports its version
  (`Last-Modified`), and the portal compares it with `SignZeroSettings.pdfHostVersion()`. A copy cached before a deploy
  is reloaded once at the versioned URL, then refreshed in the browser cache for next time.
- If the host page does not answer, the portal loads the same files inside the component (slower, same result).

On a 50-page document: page 1 shows about 2.5–4 s after the link opens, all pages are drawn about 2–4 s later, and
signing (50 spots) stamps in about 1–2 s and saves in about 2 s.

## Components

All API names use the SignZero prefix (`SignZero`, `SignZero_`, or `signZero` for Lightning web components and static
resources). Object labels stay business-friendly: *Signature Request*, *Signature Recipient*, *Signature Audit Trail*.

| Area | Components |
|---|---|
| Objects | `SignZero_Request__c` (envelope), `SignZero_Recipient__c` (signer), `SignZero_Audit_Trail__c` (append-only ledger) |
| Configuration | `SignZero_Setting__mdt` (record `Default`), `SignZero_Diagnostics__c` (hierarchy custom setting), global value set `SignZero_Signer_Role` |
| Events | `SignZero_Event__e` |
| Apex | `SignZeroOrchestrator`, `SignZeroGatewayController`, `SignZeroInvitationService`, `SignZeroProgressionJob`, `SignZeroSealService`, `SignZeroPdfAppender`, `SignZeroAuditService`, `SignZeroNotifier`, `SignZeroRecordGuard`, `SignZeroResendController`, `SignZeroRecallController`, `SignZeroCertificateController`, `SignZeroSettings`, `SignZeroSigner`, `SignZeroTest` |
| Triggers | `SignZeroRequestTrigger`, `SignZeroRecipientTrigger`, `SignZeroAuditTrailTrigger`, `SignZeroEventTrigger` |
| Lightning web components | `signZeroPortal` (public signing page), `signZeroSignerEditor` (Flow screen for signers), `signZeroResend` (Resend Invitation action), `signZeroRecall` (Recall Envelope action) |
| Visualforce | `SignZeroCertificate` (Certificate of Completion, also rendered with `Blob.toPdf`) |
| Static resource | `signZeroPdfHost` (host page, engine, PDF.js, pdf-lib) |
| Flow | `SignZero_Send_for_Signature`, exposed as quick action `SignZero_Send_for_Signature` on Account and Opportunity |
| Quick actions | `SignZero_Resend` on Signature Request and Signature Recipient, `SignZero_Recall` on Signature Request |
| App and UI | Lightning app `SignZero`, home page `SignZero_Home`, record page `SignZero_Recipient_Record_Page`, reports in `SignZero_Reports`, dashboard `SignZero_Overview` |
| Permission sets | `SignZero_User` (internal users), `SignZero_Guest` (site guest user) |
| Labels | 124 Custom Labels (`SZ_…`, category *SignZero*) for all signer-facing text, the rich text on the Send for Signature flow screens and the errors people see in Salesforce. The flow's other text (screen titles, field labels, buttons) is translated with Translation Workbench. |
| Notifications | Custom notification type `SignZero_Status_Update` |
| Experience site | `SignZero` at `/esign`. Its content bundle is `digitalExperiences/site/SignZero1`: Salesforce adds the `1` because the site's underlying `CustomSite` already holds the name `SignZero`. |

## Setup

Requirements: Salesforce CLI, a Dev Hub, and an org with Experience Cloud (the scratch definition enables
`Communities`).

```bash
sf org create scratch -f config/project-scratch-def.json -a signzero -y 30
```

Create the signing site. It must use the LWR template and the `/esign` path:

```bash
sf community create --name "SignZero" --template-name "Build Your Own (LWR)" --url-path-prefix esign --target-org signzero
```

Wait until the site exists (`SELECT Status FROM BackgroundOperation ORDER BY CreatedDate DESC LIMIT 1` shows
`Complete`), then deploy everything:

```bash
sf project deploy start --manifest manifest/package.xml --target-org signzero
```

The `CustomSite` and `Network` records are not in the project: `sf community create` makes them, and their files hold
org-specific usernames. Activate the site and assign permissions:

```bash
sf data update record -s Network -w "Name=SignZero" -v "Status=Live" --target-org signzero
```

```bash
sf org assign permset --name SignZero_User --target-org signzero
```

```bash
sf org assign permset --name SignZero_Guest --on-behalf-of <site guest username> --target-org signzero
```

The guest username is `SELECT Username FROM User WHERE UserType = 'Guest' AND Profile.Name LIKE 'SignZero%'`.
Then publish:

```bash
sf community publish --name SignZero --target-org signzero
```

Run the tests:

```bash
sf apex run test --class-names SignZeroTest --code-coverage --result-format human --target-org signzero
```

## Configuration

**`SignZero_Setting__mdt.Default`** (Setup → Custom Metadata Types):

| Field | Purpose |
|---|---|
| Company Name, Logo Url | Branding on the signing page and in emails |
| Primary Color, Primary Hover Color, Accent Color | Signing page colours (`#rgb` or `#rrggbb`); blank uses the site theme |
| Token Validity Days | How long a signing link works (default 7) |
| Max Document Size KB | Largest PDF accepted (default 2000) |
| Allow Reassignment | Lets signers delegate to someone else (default on) |
| Org Wide Email Address | Sender address for SignZero emails. Set it: emails sent in the background (later signers, completed agreements) run as the Automated Process user and need a verified org-wide address |
| Certificate Name | Org certificate used to sign the document hash at sealing (optional) |
| Site Base Url | Signing site URL, when it cannot be found automatically |

The portal's colours, logo and company name can also be set per page in Experience Builder; those win over the
custom metadata.

**Email setup check.** Salesforce accepts an email from an unverified sender and drops it later without an error,
so SignZero checks for the usual causes: deliverability off, the org-wide address missing or unverified, or (with no
org-wide address) the sender's own email unverified. Send for Signature shows a warning screen before sending when
invitations would not arrive, and the SignZero Home page shows the current status (`SignZeroEmailCheck`,
`signZeroEmailCheck`).

**`SignZero_Diagnostics__c`** (Setup → Custom Settings): **Performance Logs** writes the signing page's step timings
to the browser console. Set it org-wide, or only on the site guest profile to diagnose signers.

**`SignZero_Signer_Role`** (Setup → Picklist Value Sets): the signer roles. Each value's API name must match the
`{{sig:Role}}` tags in your PDFs (matching ignores case).

**Custom Labels** (category *SignZero*): reword or translate everything signers read.

## Security model

- The site guest user has no object access. It can call only `SignZeroGatewayController`, which checks the signer's
  256-bit token (stored only as a SHA-256 hash, with an expiry) before doing anything, and raise `SignZero_Event__e`.
  Once the signer has signed, the same link opens a read-only copy; it can no longer change anything.
- `SignZeroRecordGuard` blocks manual edits and deletes of evidence fields (hashes, tokens, timestamps, signer
  status) from the UI, API and Data Loader; only SignZero's own processing may change them. Envelope status cannot be
  edited by hand either: to cancel an envelope, use **Recall Envelope**, so the links are closed, the signers told and
  the recall recorded.
- `SignZero_Audit_Trail__c` is append-only. Each event's hash covers its fields and the previous event's hash, so a
  gap or edit breaks the chain.
- An uploaded signature image stays in the browser; it reaches Salesforce only inside the signed PDF.
- API version 68 runs Apex in user mode by default; SignZero uses `WITH SYSTEM_MODE` and `as system` only where the
  token check or internal processing requires it.

## Project layout

```
force-app/main/default/     Salesforce metadata (all of SignZero)
  staticresources/signZeroPdfHost/   PDF host page: index.html, engine.js, PDF.js, pdf-lib
manifest/package.xml        Every component, for deploying the whole project
config/                     Scratch org definition
docs/architecture/          Architecture diagrams
```
