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
   *Signature Recipient* per signer, and emails the first routing order a personal signing link. When a signer's
   role has no tag in the PDF, the flow's **Place Signatures** screen lets the sender drag them onto the pages (see
   below).
   The flow also takes optional inputs for callers that already have the details: `contentVersionId` (the PDF) and
   `documentTitle` skip choosing or uploading the document, and `signers` also skips the signers and Place Signatures
   screens, so only the sent or error screen is shown. SignZero sends the latest version of that ContentVersion's file.
   On the signers screen the sender ticks signers in a table of the record's contacts: the record itself when it is a
   Contact, the contacts of any Account it is or looks up to, any Contact it looks up to, and an Opportunity's contact
   roles (`SignZeroContactPicker`, in user mode). A search box finds any other contact the sender can see, and **Add
   someone else** types in a signer who is not a contact. A chosen contact's name and email are read-only; the sender
   picks the role and routing order, and the signer keeps a link to the Contact (*Contact* on Signature Recipient).
   For a record that reaches its account only indirectly (say, a custom object that looks up an Opportunity), set the
   flow's optional `accountId` input, for example from a Get Records step: that account's contacts are offered too.
2. **Sign.** The signer opens `https://<site>/esign/?token=…`. The signing portal (`signZeroPortal`) shows the
   document, finds the signer's spots (placed by the sender, or from anchor tags in the PDF), asks for consent to sign electronically when they
   first start signing (or before showing the document, with *Require Consent Before Viewing*), and lets them type,
   draw or upload a signature. Their signature is stamped into the PDF in the browser and submitted.
   With *Require One-Time Passcode*, the signer first asks for a code emailed to them and enters it; nothing about
   the document reaches their browser before that (see Security model).
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
Signature screen offers exactly those roles, and the invocable action rejects any other. A signer with no tags and no
places from the sender places their own signature (below).

### Signers placing their own signature

When a signer has no `{{sig:Role}}` tag and no place set by the sender (for example, an untagged PDF sent from
automation), the signing page tells them so and **Place Your Signature** replaces Start Signing. The signer adopts a
signature (type, draw or upload), then clicks the page where they sign. They can drag a placed signature to move it,
remove it (its × button or the Delete key), and place more with **Add Another Signature**. Finish is available once at
least one is placed. The places are stamped like tagged ones, and recorded as evidence: the audit trail's *Signed* event
lists each page and position, and the signer's *Signature Method*, shown on the Certificate of Completion, ends in
"placed by the signer". Turn this off with *Allow Signer Placement*; signers then get one spot at the bottom right of
the last page.

### Placing signatures when sending

The **Place Signatures** screen (`signZeroFieldPlacer`) comes after the signers screen, unless every signer's role
already has a `{{sig:Role}}` tag in the PDF: the signers screen reads the tags while the sender fills it in, says so,
and Next then sends the document straight away. (If the tags cannot be read in time, the screen is shown.) It shows
the PDF with every signer role's tags already placed, and the sender can:

- drag a signer from the list onto a page (or select the signer, then click the page) to add a place;
- drag a place to move it, or select it and nudge it with the arrow keys (Shift for bigger steps);
- remove a place with its close button or the Delete key;
- go back to the document's tags with **Reset to document tags**.

If the sender changes nothing, nothing is stored and signers sign at their tags as usual. Otherwise the places are
saved on the envelope as *Field Layout* (`Field_Layout__c`: JSON of `role`, `page` from 0, `x`, `y` for the bottom
left of the signature area, and `height`, in PDF points), and the signing page uses them instead of the tags. The PDF
itself is never changed; tags are still hidden and removed from the signed copy. A signer with no places places their own signature (below). Callers of the **Dispatch Document via SignZero** action can pass the same JSON
as *Field Layout*; each role must belong to one of the signers. *Field Layout* is protected evidence like the hashes.

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
| Apex | `SignZeroOrchestrator`, `SignZeroFieldLayout` (loads the PDF for Place Signatures, checks and serves field layouts), `SignZeroGatewayController`, `SignZeroInvitationService`, `SignZeroProgressionJob`, `SignZeroSealService`, `SignZeroPdfAppender`, `SignZeroPdfSealer`, `SignZeroAuditService`, `SignZeroNotifier`, `SignZeroRecordGuard`, `SignZeroResendController`, `SignZeroRecallController`, `SignZeroCertificateController`, `SignZeroEmailCheck`, `SignZeroEmailTemplates` (signer emails from email templates), `SignZeroContactPicker` (contacts offered as signers), `SignZeroReminderJob`, `SignZeroTokenVault`, `SignZeroSettings`, `SignZeroConstants` (statuses, event names, defaults and other fixed values shared by every class), `SignZeroSigner`, `SignZeroTest` |
| Triggers | `SignZeroRequestTrigger`, `SignZeroRecipientTrigger`, `SignZeroAuditTrailTrigger`, `SignZeroEventTrigger` |
| Lightning web components | `signZeroPortal` (public signing page), `signZeroFieldPlacer` (Flow screen for placing signatures), `signZeroAnchorTags` (anchor tag reading shared by both), `signZeroPdfEngine` (the PDF host page for the Salesforce screens), `signZeroHeader` (site header: logo and company name), `signZeroLogoEditor` and `signZeroFaviconEditor` (Experience Builder editors that upload the logo and favicon, through the shared `signZeroImageUpload`), `signZeroSignerEditor` (Flow screen for signers: tick the record's contacts or add someone by hand), `signZeroResend` (Resend Invitation action), `signZeroRecall` (Recall Envelope action), `signZeroEmailCheck` (email setup status, in the flow and on SignZero Home). All are built from SLDS classes and `lightning-*` components; custom CSS is kept to what SLDS has no class for (the document viewer and signature pad) |
| Visualforce | `SignZeroCertificate` (Certificate of Completion, also rendered with `Blob.toPdf`) |
| Static resource | `signZeroPdfHost` (host page, engine, PDF.js, pdf-lib) |
| Flow | `SignZero_Send_for_Signature`, exposed as quick action `SignZero_Send_for_Signature` on Account and Opportunity |
| Quick actions | `SignZero_Resend` on Signature Request and Signature Recipient, `SignZero_Recall` on Signature Request |
| App and UI | Lightning app `SignZero`, home page `SignZero_Home`, record page `SignZero_Recipient_Record_Page`, reports in `SignZero_Reports`, dashboard `SignZero_Overview` |
| Permission sets | `SignZero_User` (internal users), `SignZero_Guest` (site guest user) |
| Labels | 255 Custom Labels (`SZ_…`, category *SignZero*) for all signer-facing text, the Add Signers and Place Signatures screens, the rich text on the Send for Signature flow screens and the errors people see in Salesforce. The flow's own text (screen titles, field labels, buttons) is translated with Translation Workbench. |
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

Schedule the reminder job. It runs on the *Reminder Schedule* cron expression (daily at 9:00 by default) as the
user who schedules it, so use an admin whose emails can be delivered (see the email setup check below). Running this again
replaces the job:

```bash
echo "SignZeroReminderJob.schedule();" | sf apex run --target-org signzero
```

Run the tests:

```bash
sf apex run test --class-names SignZeroTest --code-coverage --result-format human --target-org signzero
```

## Configuration

**`SignZero_Setting__mdt.Default`** (Setup → Custom Metadata Types):

| Field | Purpose |
|---|---|
| Company Name | Shown on the signing site header, in signer emails and on the Certificate of Completion |
| Primary Color, Primary Hover Color, Accent Color | Signing page colours (`#rgb` or `#rrggbb`); blank uses the site theme |
| Token Validity Days | How long a signing link works (default 7) |
| Reminder First After (Days) | Days without a signature before the first automatic reminder (default record: 3). Blank or 0 turns reminders off |
| Reminder Repeat (Days) | Days between later reminders (default record: 3). Blank sends only one |
| Reminder Limit | Most reminders per invitation (default 3); the last is marked as the final reminder |
| Reminder Schedule | When the reminder job runs, as a Salesforce cron expression in the scheduling user's time zone (default `0 0 9 * * ?`, daily at 9:00; `0 0 9,15 * * ?` runs at 9:00 and 15:00). An invalid expression keeps the previous schedule |
| Max Document Size KB | Largest PDF accepted (default 2000) |
| Allow Reassignment | Lets signers delegate to someone else (default on) |
| Allow Signer Placement | A signer with no tag and no place from the sender drags their signature onto the document (default on). Off: they sign at the bottom right of the last page |
| Require Consent Before Viewing | Off (default): signers read the document first and accept the electronic record disclosure when they first start signing. On: the disclosure comes first, and the document is not sent to the signer's browser until they accept it; it then loads with a progress indicator. Use it for consumer documents that a law requires to be provided in writing (US ESIGN Act) |
| Require One-Time Passcode | Off (default). On: signers must enter a 6-digit code emailed to them before the document is shown, including when they reopen a signed copy. Applies to envelopes sent after it is switched on, and to anyone they delegate to; the Certificate of Completion records it as their authentication |
| Certificate Name | Org certificate used to sign the document hash at sealing (optional) |
| Seal Certificate | Public part of that certificate, as PEM text. With both set, the combined PDF gets a digital seal (below) |
| Site Base Url | Signing site URL, when it cannot be found automatically |

The portal's colours can also be set per page in Experience Builder; those win over the custom metadata.

**`SignZero_Branding__c`** (Setup → Custom Settings → SignZero Branding → Manage, org default). A protected hierarchy
custom setting: it is data, not metadata, so deployments never overwrite it.

| Field | Purpose |
|---|---|
| Logo Url | Logo on the signing site header, in signer emails and on the Certificate of Completion. Upload it from Experience Builder (below) rather than typing the URL |
| Favicon Url | Icon in the signing site's browser tab; blank uses the logo. Upload it from Experience Builder |
| Org Wide Email Address | Sender address for SignZero emails. Set it: emails sent in the background (later signers, completed agreements) run as the Automated Process user and need a verified org-wide address |

**Site header and logo.** The site's theme header region holds the **SignZero Header** (`signZeroHeader`): the logo
and company name, above the signing page. In Experience Builder, select the header and use its
**Logo** property to upload a PNG or JPG (up to 1 MB). SignZero stores it as a Salesforce File with a public link
(`ContentDistribution`, so signers and email clients can load it without a login) and saves that link in SignZero
Branding → *Logo URL* in the same transaction (`SignZeroBrandingAdmin`). From then on the site header, signer
emails and the Certificate of Completion all show it. The header's **Favicon** property works the same way (PNG, JPG
or ICO, saved in *Favicon URL*) and sets the icon in the browser tab; without a favicon, the logo is used. Uploading
needs an admin with *Customize Application* and the SignZero User permission set; the site's guest user only reads
the branding (`SignZeroBrandingController`). A `<style>` block in the site's head markup (Experience
Builder → Settings → Advanced → Head Markup) and a zero Column Spacer Size in the theme remove the default spacing around
sections and the theme's 1800px cap on section width, so the header and signing page fill the window at any size.

**Automatic reminders.** `SignZeroReminderJob` runs on the *Reminder Schedule* cron expression, and
reschedules itself when it changes. A signer whose turn it is gets a reminder once the
configured days have passed since their last email. A reminder re-sends the link the signer already has, with its
expiry pushed out, so links in every email keep working. (If that link cannot be recovered, the reminder carries a new
one and says so.) Resend Invitation, by contrast, always issues a new link and closes the old one. Reminders are
logged in the audit trail and counted on the signer (*Reminders Sent*). A manual resend starts the schedule again.
When no more reminders are due and the link expires unsigned, the sender gets a bell notification (once; *Expiry
Notified At*) suggesting Resend Invitation.

**PDF digital seal.** With *Certificate Name* and *Seal Certificate* set, the *Executed with Certificate* PDF gets a
PAdES digital signature (baseline B-B, `ETSI.CAdES.detached`) when the envelope is sealed, the last change to the file.
PDF readers then report if a byte changes afterwards. It is invisible on the pages and shows in Adobe's Signature
Panel. *Executed* and *Certificate of Completion* stay unsealed, so *Executed* still matches *Post Sign Hash*.

To set it up, create or import a certificate in Setup → Certificate and Key Management, download its `.crt`, then put
its unique name in *Certificate Name* and paste the file's text into *Seal Certificate*. The private key stays in
Salesforce (`SignZeroPdfSealer` signs through `Crypto.signWithCertificate`). The name readers show comes from the
certificate, so use one issued to your company rather than a self-signed one where you can.

What readers report about the signer depends on the certificate. With a self-signed certificate, tamper detection
works everywhere, but Adobe says the signer's identity is unknown unless the reader has added it as trusted. A green
tick for everyone needs a certificate Adobe already trusts (Adobe Approved Trust List), and those normally require the
key to be on certified hardware. The signing time comes from Salesforce's clock, not a trusted timestamp service.

A seal that fails (for example, a certificate that expired) does not hold up the envelope: it completes unsealed, the
reason is kept in *Error Message*, and the sender's bell notification says so. Renew the certificate before it expires,
and update *Seal Certificate* with the new one.

**Email setup check.** Salesforce accepts an email from an unverified sender and drops it later without an error,
so SignZero checks for the usual causes: deliverability off, the org-wide address missing or unverified, or (with no
org-wide address) the sender's own email unverified. Send for Signature shows a warning screen before sending when
invitations would not arrive, and the SignZero Home page shows the current status (`SignZeroEmailCheck`,
`signZeroEmailCheck`).

**Signer email templates.** Every email a signer gets comes from a Classic email template in the **SignZero Emails**
folder (Setup → Classic Email Templates): `SignZero_Invitation`, `SignZero_Reminder`, `SignZero_Final_Reminder`,
`SignZero_Passcode`, `SignZero_Recall` and `SignZero_Completed`. Edit their subject, HTML and text as you like, or
build your own and point **`SignZero_Email_Template__mdt`** (Setup → Custom Metadata Types → SignZero Email Template)
at it: one record per email, whose *Template Name* is the template's unique name. SignZero reads the template as it is
and fills in these placeholders by plain text replacement (`SignZeroEmailTemplates`), so it also works for the site
guest user, who sends passcodes:

| Placeholder | Value | Emails |
|---|---|---|
| `[[SignerName]]` | Signer's name | all but Completed |
| `[[DocumentName]]` | Document title | all |
| `[[CompanyName]]` | Company Name from SignZero Settings | all |
| `[[Logo]]` | The logo as an image, or nothing (HTML only) | all |
| `[[SigningLink]]` | The signer's personal link. **Required**: without it the built-in email is sent | Invitation, Reminder, Final Reminder |
| `[[ValidDays]]` | Days a new link works | Invitation, reminders |
| `[[ExpiresOn]]` | Date the link stops working, e.g. 9 November 2026 | Invitation, reminders |
| `[[NewLinkNote]]` | "This is a new link…" on a reminder whose link replaced the old one; otherwise nothing | Reminders |
| `[[Passcode]]` | The six-digit code. **Required** | Passcode |
| `[[PasscodeMinutes]]` | Minutes the code works | Passcode |
| `[[RecallReason]]` | "Reason: …" when the sender gave one; otherwise nothing | Recall |
| `[[EnvelopeNumber]]` | e.g. SZ-000012 | Completed |

Values are HTML-escaped in the HTML body. Salesforce merge fields (`{!…}`, `{{{…}}}`) are not filled in, because
SignZero does not render templates through Salesforce. A blank *Template Name*, a template that is missing or
inactive, or one without its required placeholder falls back to the built-in email worded by the Custom Labels below,
and the reason is written to the debug log. Templates hold one language; the built-in emails follow the Custom Label
translations. The sender's own notices are not templated.

**`SignZero_Diagnostics__c`** (Setup → Custom Settings): **Performance Logs** writes the signing page's step timings
to the browser console. Set it org-wide, or only on the site guest profile to diagnose signers.

**`SignZero_Signer_Role`** (Setup → Picklist Value Sets): the signer roles. Each value's API name must match the
`{{sig:Role}}` tags in your PDFs (matching ignores case).

**Custom Labels** (category *SignZero*): reword or translate everything signers read on the signing page, the built-in
signer emails (used when no template applies) and the notices senders get. Labels that take values use `{0}`, `{1}`…
placeholders; write apostrophes as ’ rather than ', because Apex drops a plain apostrophe from text with placeholders.

## Security model

- The site guest user has no object access. It can call only `SignZeroGatewayController`, which checks the signer's
  256-bit token before doing anything, and raise `SignZero_Event__e`. Links are checked against the token's SHA-256
  hash, with an expiry.
  Once the signer has signed, the same link opens a read-only copy; it can no longer change anything.
- So that reminders can re-send the same link, the token is also stored encrypted (AES-256, `Token_Encrypted__c`,
  on no layout or permission set) with a key SignZero generates in the protected custom setting
  `SignZero_Encryption__c`. The encrypted copy is cleared as soon as the link can no longer be reminded (signed,
  declined, delegated, recalled). Reading the database alone is not enough to build a link; reading it together with
  the key is, so treat the key like a password. Once SignZero is installed as a managed package, the protected
  setting is readable only by SignZero's code; in an unpackaged deploy, admins can read it. Deleting the key makes
  later reminders send new links.
- **One-time passcode** (with *Require One-Time Passcode*). The choice is kept on each signer's *Auth Method* when the
  envelope is sent. The signing page asks for a code with a button rather than on load, so email scanners that open
  links do not trigger codes. `sendPasscode` emails a 6-digit code that works once, for 10 minutes; only an HMAC of
  it, keyed with the `SignZero_Encryption__c` key and tied to the signer's current link, is stored. Five wrong
  entries end the code; a link can ask for 10 codes, one a minute, and a resend from the sender starts again.
  `verifyPasscode` answers a correct code with a random 256-bit session key, kept in the browser tab's
  `sessionStorage` and sent with every later call; only its SHA-256 hash is stored, and it works for 12 hours. Every
  request, sent code, wrong entry and verification is written to the audit trail.
- `SignZeroRecordGuard` blocks manual edits and deletes of evidence fields (hashes, tokens, timestamps, signer
  status) from the UI, API and Data Loader; only SignZero's own processing may change them. Envelope status cannot be
  edited by hand either: to cancel an envelope, use **Recall Envelope**, so the links are closed, the signers told and
  the recall recorded.
- `SignZero_Audit_Trail__c` is append-only. Each event's hash covers its fields and the previous event's hash, so a
  gap or edit breaks the chain.
- An uploaded signature image stays in the browser; it reaches Salesforce only inside the signed PDF. Before use,
  the portal keeps just the ink (`signZeroPortal/signatureInk.js`), as PDF readers do: the paper is estimated with a
  morphological closing, so shadows and uneven light in a photo become transparent while pen strokes keep soft
  edges, and the result is cropped to the signature (distant specks are left out). Photos and scans up to 10 MB work.
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
