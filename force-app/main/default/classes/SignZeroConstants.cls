/**
 * @description Fixed values shared across SignZero: statuses, event names, metadata names, defaults and limits.
 *   Statuses and event names must match their picklist values.
 */
public inherited sharing class SignZeroConstants {
  // ---------- Signature Recipient: Status__c ----------
  public static final String SIGNER_PENDING = 'Pending';
  public static final String SIGNER_SENT = 'Sent';
  public static final String SIGNER_VIEWED = 'Viewed';
  public static final String SIGNER_CONSENTED = 'Consented';
  public static final String SIGNER_SIGNED = 'Signed';
  public static final String SIGNER_DECLINED = 'Declined';
  public static final String SIGNER_REASSIGNED = 'Reassigned';
  public static final String SIGNER_VOIDED = 'Voided';

  /** @description Signer statuses that still owe a signature, invited or not. */
  public static final Set<String> SIGNER_AWAITING = new Set<String>{
    SIGNER_PENDING,
    SIGNER_SENT,
    SIGNER_VIEWED,
    SIGNER_CONSENTED
  };
  /** @description Signer statuses whose turn it is: they have a link and have not signed, declined or delegated. */
  public static final Set<String> SIGNER_OPEN = new Set<String>{
    SIGNER_SENT,
    SIGNER_VIEWED,
    SIGNER_CONSENTED
  };

  // ---------- Signature Request: Status__c ----------
  public static final String ENVELOPE_OUT_FOR_SIGNATURE = 'Out for Signature';
  public static final String ENVELOPE_SEALING = 'Sealing';
  public static final String ENVELOPE_COMPLETED = 'Completed';
  public static final String ENVELOPE_DECLINED = 'Declined';
  public static final String ENVELOPE_VOIDED = 'Voided';

  /** @description Envelope statuses after sending; their signers can no longer change. */
  public static final Set<String> ENVELOPE_SENT = new Set<String>{
    ENVELOPE_OUT_FOR_SIGNATURE,
    ENVELOPE_SEALING,
    ENVELOPE_COMPLETED,
    ENVELOPE_DECLINED
  };

  // ---------- Signature Audit Trail: Event_Type__c ----------
  public static final String EVENT_SENT = 'Sent';
  public static final String EVENT_VIEWED = 'Viewed';
  public static final String EVENT_CONSENT_ACCEPTED = 'Consent Accepted';
  public static final String EVENT_SIGNED = 'Signed';
  public static final String EVENT_DECLINED = 'Declined';
  public static final String EVENT_REASSIGNED = 'Reassigned';
  public static final String EVENT_COMPLETED = 'Completed';
  public static final String EVENT_RECALLED = 'Recalled';
  public static final String EVENT_PASSCODE_SENT = 'Passcode Sent';
  public static final String EVENT_PASSCODE_VERIFIED = 'Passcode Verified';
  public static final String EVENT_PASSCODE_FAILED = 'Passcode Failed';

  // ---------- SignZero_Event__e: Action__c ----------
  public static final String ACTION_SIGNED = 'SIGNED';
  public static final String ACTION_DECLINED = 'DECLINED';
  public static final String ACTION_REASSIGNED = 'REASSIGNED';

  // ---------- Signature_Method__c, as named by the signing page ----------
  public static final String METHOD_TYPED = 'Typed';
  public static final String METHOD_DRAWN = 'Drawn';
  public static final String METHOD_UPLOADED = 'Uploaded';
  /** @description Each signature method as shown on the Certificate of Completion. */
  public static final Map<String, String> METHOD_DESCRIPTIONS = new Map<String, String>{
    METHOD_TYPED => 'Typed in a selected style',
    METHOD_DRAWN => 'Drawn on device',
    METHOD_UPLOADED => 'Uploaded image'
  };
  /** @description Added to the method when the signer chose where their signature goes. */
  public static final String PLACED_BY_SIGNER = ', placed by the signer';

  /** @description Auth_Method__c value: the signing link alone. */
  public static final String AUTH_TOKEN_LINK = 'Single-use emailed token link';
  /** @description Auth_Method__c value: the signing link and a one-time passcode emailed on request. */
  public static final String AUTH_LINK_AND_PASSCODE = 'Single-use emailed token link and one-time emailed passcode';

  // ---------- One-time passcodes ----------
  public static final Integer PASSCODE_DIGITS = 6;
  public static final Integer PASSCODE_VALID_MINUTES = 10;
  /** @description Wrong entries allowed per code; after that the signer needs a new code. */
  public static final Integer PASSCODE_MAX_ATTEMPTS = 5;
  /** @description Codes one signing link can ask for; a resend from the sender starts again. */
  public static final Integer PASSCODE_MAX_SENDS = 10;
  public static final Integer PASSCODE_RESEND_SECONDS = 60;
  /** @description How long a correct code keeps the signer verified in that browser tab. */
  public static final Integer PASSCODE_SESSION_HOURS = 12;

  // ---------- Names of related metadata ----------
  /** @description The SignZero_Setting__mdt record SignZero reads. */
  public static final String SETTINGS_RECORD = 'Default';
  /** @description CustomNotificationType for the sender's bell notifications. */
  public static final String NOTIFICATION_TYPE = 'SignZero_Status_Update';
  /** @description Static resource holding the PDF host page. */
  public static final String PDF_HOST_RESOURCE = 'signZeroPdfHost';
  /** @description Name of the scheduled reminder job. */
  public static final String REMINDER_JOB_NAME = 'SignZero reminders';

  // ---------- Defaults when a setting is blank ----------
  public static final Integer DEFAULT_TOKEN_VALIDITY_DAYS = 7;
  public static final Integer DEFAULT_MAX_DOCUMENT_KB = 2000;
  public static final Integer DEFAULT_REMINDER_LIMIT = 3;
  /** @description Reminder job cron expression when none is set: daily at 9:00. */
  public static final String DEFAULT_REMINDER_SCHEDULE = '0 0 9 * * ?';
  /** @description Role for a signer sent without one. */
  public static final String DEFAULT_SIGNER_ROLE = 'Customer';

  // ---------- Logo and favicon ----------
  public static final String IMAGE_LOGO = 'logo';
  public static final String IMAGE_FAVICON = 'favicon';
  public static final String LOGO_TITLE = 'SignZero Logo';
  public static final String FAVICON_TITLE = 'SignZero Favicon';
  /** @description Logo formats every email client and the PDF certificate can show. */
  public static final Set<String> LOGO_EXTENSIONS = new Set<String>{ 'png', 'jpg', 'jpeg' };
  /** @description Favicon formats browsers show in the tab. */
  public static final Set<String> FAVICON_EXTENSIONS = new Set<String>{ 'png', 'jpg', 'jpeg', 'ico' };
  public static final Integer MAX_IMAGE_BYTES = 1024 * 1024;

  // ---------- Limits and formats ----------
  public static final String PDF_CONTENT_TYPE = 'application/pdf';
  public static final Pattern EMAIL_PATTERN = Pattern.compile(
    '^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$'
  );
  /** @description Signature area heights in PDF points, as for {{sig:Role|h=40}} tags. */
  public static final Integer MIN_SIGNATURE_HEIGHT = 16;
  public static final Integer MAX_SIGNATURE_HEIGHT = 80;
  public static final Integer DEFAULT_SIGNATURE_HEIGHT = 30;
  /** @description Most signature places one envelope's field layout may hold. */
  public static final Integer MAX_FIELD_PLACEMENTS = 500;
  /** @description Longest recall reason kept. */
  public static final Integer MAX_RECALL_REASON = 1000;
  /** @description Signers per reminder batch; small because each expiry notice runs a query. */
  public static final Integer REMINDER_BATCH_SIZE = 20;
  /** @description An indirect object reference in a PDF, such as "12 0 R". */
  public static final Pattern PDF_REFERENCE = Pattern.compile(
    '(\\d+)\\s+(\\d+)\\s+R(?![A-Za-z0-9])'
  );

  // ---------- Email check severities (read by signZeroEmailCheck) ----------
  public static final String SEVERITY_ERROR = 'error';
  public static final String SEVERITY_WARNING = 'warning';

  // ---------- Fields only SignZero may change (SignZeroRecordGuard) ----------
  public static final List<String> GUARDED_REQUEST_FIELDS = new List<String>{
    'Source_Record_Id__c',
    'Content_Document_Id__c',
    'Related_Record_Ids__c',
    'Field_Layout__c',
    'Pre_Sign_Hash__c',
    'Post_Sign_Hash__c',
    'Working_Copy_Hash__c',
    'Working_Copy_Id__c',
    'PKI_Signature__c',
    'Final_Document_Version_Id__c',
    'Certificate_Version_Id__c',
    'Combined_Document_Version_Id__c',
    'Completed_At__c',
    'Error_Message__c',
    'Recall_Reason__c'
  };
  public static final List<String> GUARDED_RECIPIENT_FIELDS = new List<String>{
    'Token_Hash__c',
    'Token_Encrypted__c',
    'Token_Expires_At__c',
    'Status__c',
    'Auth_Method__c',
    'Signature_Method__c',
    'Last_Known_IP__c',
    'User_Agent__c',
    'Reassigned_To__c',
    'Reassign_Reason__c',
    'Delegated_From__c',
    'List_Order__c',
    'Sent_At__c',
    'Reminders_Sent__c',
    'Expiry_Notified_At__c',
    'Viewed_At__c',
    'Consented_At__c',
    'Signed_At__c',
    'Decline_Reason__c',
    'Passcode_Hash__c',
    'Passcode_Expires_At__c',
    'Passcode_Attempts__c',
    'Passcode_Sends__c',
    'Passcode_Sent_At__c',
    'Passcode_Session_Hash__c',
    'Passcode_Verified_At__c'
  };
  /** @description Who signs: these fields can only change before the invitation goes out. */
  public static final List<String> SIGNER_IDENTITY_FIELDS = new List<String>{
    'Name',
    'Email__c',
    'Signer_Role__c',
    'Routing_Order__c',
    'SignZero_Request__c'
  };
}
