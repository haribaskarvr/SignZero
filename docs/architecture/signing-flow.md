# Signing flow

How an envelope moves from sending to sealing, and where each piece runs.

```mermaid
sequenceDiagram
    autonumber
    actor Sender as Sender (Salesforce user)
    participant Flow as SignZero_Send_for_Signature<br/>(Flow)
    participant Orch as SignZeroOrchestrator
    participant Inv as SignZeroInvitationService
    actor Signer
    participant Portal as signZeroPortal<br/>(LWC, /esign site)
    participant Host as signZeroPdfHost<br/>(hidden iframe, outside LWS)
    participant Gateway as SignZeroGatewayController<br/>(guest Apex)
    participant Job as SignZeroProgressionJob
    participant Seal as SignZeroSealService

    Sender->>Flow: Send for Signature (PDF, signers)
    Flow->>Orch: Dispatch Document via SignZero
    Orch->>Orch: Create SignZero_Request__c and SignZero_Recipient__c records
    Orch->>Inv: Invite routing order 1
    Inv-->>Signer: Email with signing link (token)

    Signer->>Portal: Open /esign/?token=…
    par Load in parallel
        Portal->>Host: Load host page (plain address)
        Portal->>Gateway: initializeSession(token)
        Gateway-->>Portal: Document, signer details, host version
    end
    Host-->>Portal: ready (its version)
    Portal->>Host: open(PDF)
    Host-->>Portal: Page sizes, anchor tags
    loop Page in view first
        Portal->>Host: renderPage
        Host-->>Portal: Page image
    end
    Signer->>Portal: Consent, adopt signature, sign spots
    Portal->>Host: stamp(PDF, signature, spots)
    Host-->>Portal: Signed PDF
    Portal->>Gateway: submitExecutedDocument
    Gateway->>Gateway: Audit event, SignZero_Event__e

    Gateway--)Job: Platform event (async)
    alt More signers
        Job->>Inv: Invite next routing order
    else Everyone signed
        Job->>Seal: Seal envelope
        Seal->>Seal: Hash, Certificate of Completion, combined PDF, file on records
        Seal-->>Signer: Executed PDF and certificate by email
        Seal-->>Sender: Bell notification
    end
```

## Recall

While the envelope is out for signature, the sender can recall (void) it from the Signature Request.

```mermaid
sequenceDiagram
    autonumber
    actor Sender as Sender (Salesforce user)
    participant Action as signZeroRecall<br/>(Recall Envelope action)
    participant Recall as SignZeroRecallController
    participant Audit as SignZeroAuditService
    actor Signer
    participant Gateway as SignZeroGatewayController<br/>(guest Apex)

    Sender->>Action: Recall Envelope (optional reason)
    Action->>Recall: previewRecall: who will be emailed
    Action->>Recall: recall(reason)
    Recall->>Recall: Check status (out for signature) and edit access
    Recall->>Recall: Envelope and unsigned signers to Voided, every link expired
    Recall->>Audit: Recalled event per signer (who, why)
    Recall-->>Signer: Cancellation email (signers already sent a link)
    Signer->>Gateway: Opens an old link
    Gateway-->>Signer: "This signing request was recalled"
```

## Where things run

| Layer | Runs | Notes |
|---|---|---|
| Flow, Orchestrator, Invitation, Progression, Seal | Salesforce (Apex) | Progression and sealing run as the Automated Process user from the platform event |
| Gateway | Salesforce (Apex), as the site guest user | The only Apex the site can call; every method checks the token first |
| Portal | Signer's browser, inside Lightning Web Security | Layout, consent, signature capture, guided signing |
| PDF host page | Signer's browser, in a same-site iframe outside LWS | PDF.js with its Web Worker, and pdf-lib; no Salesforce access |
