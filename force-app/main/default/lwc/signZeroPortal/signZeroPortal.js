import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { loadScript } from 'lightning/platformResourceLoader';
import Toast from 'lightning/toast';
import PDF_HOST_RESOURCE from '@salesforce/resourceUrl/signZeroPdfHost';
import initializeSession from '@salesforce/apex/SignZeroGatewayController.initializeSession';
import recordConsent from '@salesforce/apex/SignZeroGatewayController.recordConsent';
import submitExecutedDocument from '@salesforce/apex/SignZeroGatewayController.submitExecutedDocument';
import declineToSign from '@salesforce/apex/SignZeroGatewayController.declineToSign';
import { extractInk } from './signatureInk';
import { SIG_WIDTH, SIG_HEIGHT, findAnchorTags } from 'c/signZeroAnchorTags';
import reassign from '@salesforce/apex/SignZeroGatewayController.reassign';
import sendPasscode from '@salesforce/apex/SignZeroGatewayController.sendPasscode';
import verifyPasscode from '@salesforce/apex/SignZeroGatewayController.verifyPasscode';

// Text is in Custom Labels (category SignZero) so admins can reword and translate it.
import loadingSession from '@salesforce/label/c.SZ_Loading_Session';
import loadingDocument from '@salesforce/label/c.SZ_Loading_Document';
import errorTitle from '@salesforce/label/c.SZ_Error_Title';
import missingToken from '@salesforce/label/c.SZ_Missing_Token';
import doneTitle from '@salesforce/label/c.SZ_Done_Title';
import donePendingMessage from '@salesforce/label/c.SZ_Done_Pending_Message';
import doneFinalTitle from '@salesforce/label/c.SZ_Done_Final_Title';
import doneFinalMessage from '@salesforce/label/c.SZ_Done_Final_Message';
import declinedTitle from '@salesforce/label/c.SZ_Declined_Title';
import declinedMessage from '@salesforce/label/c.SZ_Declined_Message';
import consentTitle from '@salesforce/label/c.SZ_Consent_Title';
import consentGreeting from '@salesforce/label/c.SZ_Consent_Greeting';
import consentBody from '@salesforce/label/c.SZ_Consent_Body';
import consentPaperOption from '@salesforce/label/c.SZ_Consent_Paper_Option';
import consentAccept from '@salesforce/label/c.SZ_Consent_Accept';
import consentNotNow from '@salesforce/label/c.SZ_Consent_Not_Now';
import decline from '@salesforce/label/c.SZ_Decline';
import declineTitle from '@salesforce/label/c.SZ_Decline_Title';
import declineReason from '@salesforce/label/c.SZ_Decline_Reason';
import back from '@salesforce/label/c.SZ_Back';
import changeSignature from '@salesforce/label/c.SZ_Change_Signature';
import signHere from '@salesforce/label/c.SZ_Sign_Here';
import padTitle from '@salesforce/label/c.SZ_Pad_Title';
import padHelp from '@salesforce/label/c.SZ_Pad_Help';
import clear from '@salesforce/label/c.SZ_Clear';
import cancel from '@salesforce/label/c.SZ_Cancel';
import adoptSign from '@salesforce/label/c.SZ_Adopt_Sign';
import guideStartOne from '@salesforce/label/c.SZ_Guide_Start_One';
import guideStartMany from '@salesforce/label/c.SZ_Guide_Start_Many';
import guideNext from '@salesforce/label/c.SZ_Guide_Next';
import guideFinish from '@salesforce/label/c.SZ_Guide_Finish';
import submitting from '@salesforce/label/c.SZ_Submitting';
import noTagsNotice from '@salesforce/label/c.SZ_No_Tags_Notice';
import stampCaption from '@salesforce/label/c.SZ_Stamp_Caption';
import genericError from '@salesforce/label/c.SZ_Generic_Error';
import tabType from '@salesforce/label/c.SZ_Tab_Type';
import tabDraw from '@salesforce/label/c.SZ_Tab_Draw';
import tabUpload from '@salesforce/label/c.SZ_Tab_Upload';
import typeLabel from '@salesforce/label/c.SZ_Type_Label';
import typeStyle from '@salesforce/label/c.SZ_Type_Style';
import drawHelp from '@salesforce/label/c.SZ_Draw_Help';
import uploadLabel from '@salesforce/label/c.SZ_Upload_Label';
import uploadHelp from '@salesforce/label/c.SZ_Upload_Help';
import uploadInvalid from '@salesforce/label/c.SZ_Upload_Invalid';
import uploadNoInk from '@salesforce/label/c.SZ_Upload_No_Ink';
import uploadProcessing from '@salesforce/label/c.SZ_Upload_Processing';
import pageOf from '@salesforce/label/c.SZ_Page_Of';
import prevPage from '@salesforce/label/c.SZ_Prev_Page';
import nextPage from '@salesforce/label/c.SZ_Next_Page';
import zoomIn from '@salesforce/label/c.SZ_Zoom_In';
import zoomOut from '@salesforce/label/c.SZ_Zoom_Out';
import fitPage from '@salesforce/label/c.SZ_Fit_Page';
import fitWidth from '@salesforce/label/c.SZ_Fit_Width';
import readOnlySigned from '@salesforce/label/c.SZ_ReadOnly_Signed';
import readOnlyCompleted from '@salesforce/label/c.SZ_ReadOnly_Completed';
import readOnlyPending from '@salesforce/label/c.SZ_ReadOnly_Pending';
import readOnlyDeclined from '@salesforce/label/c.SZ_ReadOnly_Declined';
import reassignAction from '@salesforce/label/c.SZ_Reassign_Action';
import reassignHelp from '@salesforce/label/c.SZ_Reassign_Help';
import reassignName from '@salesforce/label/c.SZ_Reassign_Name';
import reassignEmail from '@salesforce/label/c.SZ_Reassign_Email';
import reassignReason from '@salesforce/label/c.SZ_Reassign_Reason';
import reassignConfirm from '@salesforce/label/c.SZ_Reassign_Confirm';
import reassignedTitle from '@salesforce/label/c.SZ_Reassigned_Title';
import reassignedMessage from '@salesforce/label/c.SZ_Reassigned_Message';
import recalledTitle from '@salesforce/label/c.SZ_Recalled_Title';
import errRecalled from '@salesforce/label/c.SZ_Err_Recalled';
import placeOwnNotice from '@salesforce/label/c.SZ_Place_Own_Notice';
import placeStart from '@salesforce/label/c.SZ_Place_Start';
import placeHint from '@salesforce/label/c.SZ_Place_Hint';
import placeCancel from '@salesforce/label/c.SZ_Place_Cancel';
import placeAnother from '@salesforce/label/c.SZ_Place_Another';
import placeRemove from '@salesforce/label/c.SZ_Place_Remove';
import passcodeTitle from '@salesforce/label/c.SZ_Passcode_Title';
import passcodeIntro from '@salesforce/label/c.SZ_Passcode_Intro';
import passcodeSend from '@salesforce/label/c.SZ_Passcode_Send';
import passcodeSent from '@salesforce/label/c.SZ_Passcode_Sent';
import passcodeLabel from '@salesforce/label/c.SZ_Passcode_Label';
import passcodeVerify from '@salesforce/label/c.SZ_Passcode_Verify';
import passcodeResend from '@salesforce/label/c.SZ_Passcode_Resend';
import passcodeResendWait from '@salesforce/label/c.SZ_Passcode_Resend_Wait';
import passcodeWrong from '@salesforce/label/c.SZ_Err_Passcode_Wrong';
import passcodeExpired from '@salesforce/label/c.SZ_Err_Passcode_Expired';
import errPasscodeRequired from '@salesforce/label/c.SZ_Err_Passcode_Required';
import moreActions from '@salesforce/label/c.SZ_More_Actions';

const LABELS = {
    loadingSession,
    loadingDocument,
    errorTitle,
    missingToken,
    doneTitle,
    donePendingMessage,
    doneFinalTitle,
    doneFinalMessage,
    declinedTitle,
    declinedMessage,
    consentTitle,
    consentGreeting,
    consentBody,
    consentPaperOption,
    consentAccept,
    consentNotNow,
    decline,
    declineTitle,
    declineReason,
    back,
    changeSignature,
    signHere,
    padTitle,
    padHelp,
    clear,
    cancel,
    adoptSign,
    guideStartOne,
    guideStartMany,
    guideNext,
    guideFinish,
    submitting,
    noTagsNotice,
    stampCaption,
    genericError,
    tabType,
    tabDraw,
    tabUpload,
    typeLabel,
    typeStyle,
    drawHelp,
    uploadLabel,
    uploadHelp,
    uploadInvalid,
    uploadNoInk,
    uploadProcessing,
    pageOf,
    prevPage,
    nextPage,
    zoomIn,
    zoomOut,
    fitPage,
    fitWidth,
    readOnlySigned,
    readOnlyCompleted,
    readOnlyPending,
    readOnlyDeclined,
    reassignAction,
    reassignHelp,
    reassignName,
    reassignEmail,
    reassignReason,
    reassignConfirm,
    reassignedTitle,
    reassignedMessage,
    recalledTitle,
    errRecalled,
    placeOwnNotice,
    placeStart,
    placeHint,
    placeCancel,
    placeAnother,
    placeRemove,
    passcodeTitle,
    passcodeIntro,
    passcodeSend,
    passcodeSent,
    passcodeLabel,
    passcodeVerify,
    passcodeResend,
    passcodeResendWait,
    passcodeWrong,
    passcodeExpired,
    errPasscodeRequired,
    moreActions
};

/** Fills {0}, {1}, ... placeholders in a label. */
function format(label, ...args) {
    return label.replace(/\{(\d+)\}/g, (match, i) => (args[i] !== undefined ? args[i] : match));
}

/*
 * PDF work runs in the signZeroPdfHost page, loaded in a hidden iframe outside Lightning Web Security so PDF.js gets
 * its Web Worker. If the host does not answer in time, the engine runs in this component instead (slower).
 */
const PDF_HOST_NAME = 'signZeroPdfHost';
const ENGINE_READY_TIMEOUT_MS = 8000;
// Opening reads every page of the document; drawing handles one page.
const ENGINE_REQUEST_TIMEOUT_MS = { open: 30000, renderPage: 10000, stamp: 20000, refreshPlainCopy: 30000 };

const INK = '#0b1f4d';
const SIGNATURE_IMAGE_WIDTH = 640;
// Line height of a typed signature, in font sizes above and below the baseline: the letters fill about half of it.
const TYPED_ASCENT = 1.0;
const TYPED_DESCENT = 0.4;
// Phone photos are large; the image never leaves the browser.
const MAX_UPLOAD_BYTES = 10 * 1024 * 1024;
// Uploaded images are processed at most this wide.
const UPLOAD_WORK_SIZE = 1200;
// Adopted signatures are cropped to their ink at most this tall (about 7 px per point in a 30 pt box).
const SIGNATURE_MAX_HEIGHT = 200;
// Padding around the ink so anti-aliased edges survive.
const INK_EDGE = 2;

// Handwriting fonts found on most devices; nothing is downloaded.
const TYPED_STYLES = [
    { family: "'Segoe Script', 'Brush Script MT', 'Snell Roundhand', cursive", italic: false },
    { family: "'Lucida Handwriting', 'Bradley Hand', 'Segoe Print', cursive", italic: false },
    { family: "Georgia, 'Times New Roman', serif", italic: true }
];

// A signature fills its area's width and may rise above it up to this many times its height.
// Keep in step with signZeroPdfHost/engine.js.
const SIG_OVERFLOW = 1.25;
// Pointer travel that turns a press on a placed signature into a drag.
const DRAG_THRESHOLD_PX = 4;
const VIEWER_PADDING = 16;
const CSS_PX_PER_PT = 96 / 72; // 100% zoom
const ZOOM_STEP = 1.25;
const MIN_ZOOM = 0.25 * CSS_PX_PER_PT;
const MAX_ZOOM = 4 * CSS_PX_PER_PT;

function base64ToBytes(base64) {
    const binary = atob(base64);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) {
        bytes[i] = binary.charCodeAt(i);
    }
    return bytes;
}

function bytesToBase64(bytes) {
    let binary = '';
    const chunk = 0x8000;
    for (let i = 0; i < bytes.length; i += chunk) {
        binary += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk));
    }
    return btoa(binary);
}

// Set by Performance Logs on the SignZero Diagnostics custom setting.
let performanceLogs = false;

/** Step timings in the browser console. */
function timing(step, startedAt, endedAt = performance.now()) {
    if (performanceLogs) {
        // eslint-disable-next-line no-console
        console.info(`[SignZero] ${step} in ${Math.round(endedAt - startedAt)} ms`);
    }
}

/*
 * The key from a correct passcode is kept for this browser tab only, so a reload does not ask for another code.
 * Storage can be blocked (private windows, site settings); the signer then verifies again after a reload.
 */
const PASSCODE_STORAGE_PREFIX = 'signZeroPasscode:';

function readPasscodeSession(rawToken) {
    try {
        return window.sessionStorage.getItem(PASSCODE_STORAGE_PREFIX + rawToken);
    } catch (e) {
        return null;
    }
}

function storePasscodeSession(rawToken, passcodeSession) {
    try {
        if (passcodeSession) {
            window.sessionStorage.setItem(PASSCODE_STORAGE_PREFIX + rawToken, passcodeSession);
        } else {
            window.sessionStorage.removeItem(PASSCODE_STORAGE_PREFIX + rawToken);
        }
    } catch (e) {
        // not kept; see above
    }
}

function reduceError(error) {
    if (error && error.body && error.body.message) {
        return error.body.message;
    }
    return (error && error.message) || LABELS.genericError;
}

/** Sizes a signature in its box as the stamp does in the PDF: full width, rising above the box when taller. */
function sizeSignatureImage(img, box) {
    const scale = Math.min(
        box.offsetWidth / img.naturalWidth,
        (SIG_OVERFLOW * box.offsetHeight) / img.naturalHeight
    );
    img.style.maxWidth = 'none';
    img.style.maxHeight = 'none';
    img.style.flexShrink = '0';
    img.style.width = `${img.naturalWidth * scale}px`;
    img.style.height = `${img.naturalHeight * scale}px`;
}

/** Crops a signature canvas to its ink so the stamp can scale the strokes to the box; unchanged when blank. */
function trimToInk(canvas) {
    const { width, height } = canvas;
    const alpha = canvas.getContext('2d').getImageData(0, 0, width, height).data;
    let left = width;
    let top = height;
    let right = -1;
    let bottom = -1;
    for (let y = 0; y < height; y++) {
        for (let x = 0; x < width; x++) {
            if (alpha[(y * width + x) * 4 + 3] > 8) {
                left = Math.min(left, x);
                right = Math.max(right, x);
                top = Math.min(top, y);
                bottom = Math.max(bottom, y);
            }
        }
    }
    if (right < 0) {
        return canvas;
    }
    left = Math.max(0, left - INK_EDGE);
    top = Math.max(0, top - INK_EDGE);
    right = Math.min(width - 1, right + INK_EDGE);
    bottom = Math.min(height - 1, bottom + INK_EDGE);
    const cropWidth = right - left + 1;
    const cropHeight = bottom - top + 1;
    const fit = Math.min(1, SIGNATURE_MAX_HEIGHT / cropHeight);
    const trimmed = document.createElement('canvas');
    trimmed.width = Math.max(1, Math.round(cropWidth * fit));
    trimmed.height = Math.max(1, Math.round(cropHeight * fit));
    trimmed.getContext('2d').drawImage(canvas, left, top, cropWidth, cropHeight, 0, 0, trimmed.width, trimmed.height);
    return trimmed;
}

export default class SignZeroPortal extends LightningElement {
    labels = LABELS;
    rawToken;
    passcodeSession; // key from a correct one-time passcode, sent with every call; null when none is needed
    // The passcode screen: where the code goes, whether one was sent, what the signer typed.
    passcode = { maskedEmail: '', sent: false, digits: 6, validMinutes: 10, code: '', error: null };
    afterPasscode;
    resendIn = 0; // seconds until another code can be asked for
    resendTimer;
    state = 'loading'; // loading | error | passcode | signing | submitting | done | declined
    loadingMessage = LABELS.loadingSession;
    isFinalSigner = false;
    errorMessage;
    isWorking = false;

    documentName = 'Agreement';
    envelopeNumber;
    recipientName = '';
    signerRole = 'Customer';
    consentAccepted = false;
    // The disclosure opens when the signer first tries to sign, or on load with Require Consent Before Viewing.
    consentRequested = false;
    consentFirst = false;
    afterConsent; // what to carry on with once they agree
    showSignatureModal = false;
    showDeclineModal = false;
    declineReason = '';

    // Experience Builder overrides; they win over SignZero Settings, which win over the site theme.
    @api primaryColor;
    @api primaryHoverColor;
    @api accentColor;

    sessionBranding = {};

    pdfBytes; // original bytes the signer was shown; pdf-lib stamps these
    signatureLocations = [];
    adoptedSignature; // PNG data URL
    activeSpotId;
    guidedIndex = -1;

    sigCtx;
    isDrawing = false;
    padIsEmpty = true;
    zoomMode = 'page'; // page | width | custom
    zoomScale; // used when zoomMode is custom
    renderedScale; // scale of the first page as drawn, for the zoom label
    renderedArea;
    currentPage = 1;
    pageCount = 0;
    pdfEngineUrl;
    openedDoc; // { docId, pages: [{ width, height, transform, view }], tagItems }
    pageImageUrls = []; // released on redraw
    drawGeneration = 0; // bumped per redraw so an older pass stops
    engineInComponent = false; // the host page failed
    readOnly = false; // reopened after signing
    envelopeStatus;
    signedAt;
    isLastSigner = false;
    allowReassign = false;
    showReassignModal = false;
    reassignTo = { name: '', email: '', reason: '' };
    tagRects = []; // every anchor tag, any role: { pageIndex, rect }
    placements; // places chosen by the sender, used instead of this signer's tags; null when there are none
    allowSignerPlacement = false;
    signerPlaces = false; // no tag and no place from the sender: the signer puts their signature where they sign
    placingSignature = false; // the next click on a page places the adopted signature
    placeAfterAdopt = false;
    ownPlaceCount = 0;
    signatureMode = 'type'; // type | draw | upload
    typedName = '';
    typedStyle = 0;
    uploadedSignature; // PNG data URL
    uploadError;
    isProcessingUpload = false;
    adoptedMethod; // Drawn | Typed | Uploaded
    started = false;
    openingDocument = false; // the engine is reading the document; no page outlines to show yet

    @wire(CurrentPageReference)
    setPageRef(pageRef) {
        const fromState = pageRef && pageRef.state ? pageRef.state.token : null;
        const token = fromState || new URLSearchParams(window.location.search).get('token');
        if (token && !this.started) {
            this.started = true;
            this.rawToken = token;
            this.start();
        }
    }

    connectedCallback() {
        // For containers that never provide a page reference.
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            if (!this.started) {
                const token = new URLSearchParams(window.location.search).get('token');
                if (token) {
                    this.started = true;
                    this.rawToken = token;
                    this.start();
                } else {
                    this.fail(LABELS.missingToken);
                }
            }
        }, 0);
    }

    // ---------- view state ----------

    get isLoading() {
        return this.state === 'loading';
    }
    get isError() {
        return this.state === 'error';
    }
    get errorTitle() {
        return this.errorMessage === LABELS.errRecalled ? LABELS.recalledTitle : LABELS.errorTitle;
    }
    get isDone() {
        return this.state === 'done';
    }
    get isPasscode() {
        return this.state === 'passcode';
    }
    get passcodeIntroMessage() {
        return format(LABELS.passcodeIntro, this.passcode.maskedEmail);
    }
    get passcodeSentMessage() {
        return format(LABELS.passcodeSent, this.passcode.digits, this.passcode.maskedEmail, this.passcode.validMinutes);
    }
    get resendLabel() {
        return this.resendIn > 0 ? format(LABELS.passcodeResendWait, this.resendIn) : LABELS.passcodeResend;
    }
    get resendDisabled() {
        return this.isWorking || this.resendIn > 0;
    }
    get verifyDisabled() {
        return this.isWorking || this.passcode.code.length !== this.passcode.digits;
    }
    get isDeclined() {
        return this.state === 'declined';
    }
    get isSigning() {
        return this.state === 'signing' || this.state === 'submitting';
    }
    get isReassigned() {
        return this.state === 'reassigned';
    }
    get reassignedTitle() {
        return format(LABELS.reassignedTitle, this.reassignTo.name);
    }
    get reassignedMessage() {
        return format(LABELS.reassignedMessage, this.reassignTo.name);
    }
    get isViewing() {
        return this.state === 'viewing';
    }
    get showViewer() {
        return this.isSigning || this.isViewing;
    }
    get viewingMessage() {
        const signedOn = this.signedAt ? new Date(this.signedAt).toLocaleString() : '';
        const signed = format(LABELS.readOnlySigned, signedOn);
        if (this.envelopeStatus === 'Completed') {
            return `${signed} ${LABELS.readOnlyCompleted}`;
        }
        if (this.envelopeStatus === 'Declined') {
            return `${signed} ${LABELS.readOnlyDeclined}`;
        }
        return `${signed} ${LABELS.readOnlyPending}`;
    }
    get isSubmitting() {
        return this.state === 'submitting';
    }
    get showConsentModal() {
        return (
            this.isSigning &&
            this.consentRequested &&
            !this.consentAccepted &&
            !this.showDeclineModal &&
            !this.showReassignModal
        );
    }
    get showGuide() {
        return this.isSigning && !this.consentFirst;
    }
    // With consent first there is nothing to read until it is accepted, so it cannot be put off.
    get canPostponeConsent() {
        return !this.consentFirst;
    }

    get branding() {
        const org = this.sessionBranding;
        return {
            primaryColor: this.primaryColor || org.primaryColor,
            primaryHoverColor: this.primaryHoverColor || org.primaryHoverColor,
            accentColor: this.accentColor || org.accentColor
        };
    }

    // Only configured overrides, so the site theme shows through for the rest.
    get dynamicBrandStyles() {
        const b = this.branding;
        return [
            ['--brand-primary', b.primaryColor],
            ['--brand-primary-hover', b.primaryHoverColor],
            ['--brand-accent', b.accentColor]
        ]
            .filter(([, value]) => value)
            .map(([name, value]) => `${name}: ${value};`)
            .join(' ');
    }

    get documentContainerClass() {
        if (this.isViewing) {
            return 'document-container';
        }
        if (!this.isSigning) {
            return 'document-container hidden';
        }
        return this.placingSignature ? 'document-container placing' : 'document-container';
    }

    get remainingSpots() {
        return this.signatureLocations.filter((loc) => !loc.signed).length;
    }

    get guideButtonLabel() {
        if (this.isSubmitting) {
            return LABELS.submitting;
        }
        if (this.signerPlaces) {
            if (this.placingSignature) {
                return LABELS.placeCancel;
            }
            return this.signatureLocations.length ? LABELS.guideFinish : LABELS.placeStart;
        }
        const remaining = this.remainingSpots;
        if (remaining === 0) {
            return LABELS.guideFinish;
        }
        if (this.guidedIndex === -1) {
            return remaining === 1 ? LABELS.guideStartOne : format(LABELS.guideStartMany, remaining);
        }
        return format(LABELS.guideNext, remaining);
    }

    get consentGreeting() {
        return format(LABELS.consentGreeting, this.recipientName);
    }

    // The last signer completes the envelope rather than waiting on others.
    get doneTitle() {
        return this.isFinalSigner ? LABELS.doneFinalTitle : format(LABELS.doneTitle, this.recipientName);
    }

    get doneMessage() {
        return this.isFinalSigner ? format(LABELS.doneFinalMessage, this.recipientName) : LABELS.donePendingMessage;
    }

    // ---------- startup ----------

    async start() {
        try {
            const loadStarted = performance.now();
            // The host page and the session load in parallel.
            this.startPdfEngine();
            this.passcodeSession = readPasscodeSession(this.rawToken);
            let session = await this.loadSession();
            if (session.passcodeRequired) {
                // The document arrives only after the signer enters the code emailed to them.
                this.sessionBranding = session.branding || {};
                performanceLogs = session.performanceLogs === true;
                await new Promise((resolve) => this.askPasscode(session, resolve));
                this.loadingMessage = LABELS.loadingSession;
                this.state = 'loading';
                session = await this.loadSession();
            }
            this.applySession(session);
            timing('session loaded', loadStarted);
            this.confirmEngineVersion(session.pdfHostVersion);
            if (session.consentBeforeViewing) {
                // The document arrives only after the signer accepts the disclosure.
                this.consentFirst = true;
                this.state = 'signing';
                await new Promise((resolve) => this.askConsent(resolve));
                this.consentFirst = false;
                this.loadingMessage = LABELS.loadingDocument;
                this.state = 'loading';
                session = await this.loadSession();
                this.applySession(session);
            }
            this.loadingMessage = LABELS.loadingDocument;
            this.state = this.readOnly ? 'viewing' : 'signing';
            // Let the document area render before drawing. Background pages throttle animation frames (seen at
            // 8-22 s), so wait at most 100 ms.
            await new Promise((resolve) => {
                requestAnimationFrame(resolve);
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                setTimeout(resolve, 100);
            });
            this.boundFitToWindow = () => this.fitToWindow();
            window.addEventListener('resize', this.boundFitToWindow);
            this.fitToWindow();
            timing('viewer laid out', loadStarted);
            this.isRendering = true;
            await this.renderAllPages();
            // Pages and signing spots are ready; images keep arriving in the background.
            timing('document ready', loadStarted);
            this.isRendering = false;
        } catch (error) {
            this.fail(reduceError(error));
        }
    }

    loadSession() {
        return initializeSession({
            rawToken: this.rawToken,
            userAgent: navigator.userAgent,
            passcodeSession: this.passcodeSession
        });
    }

    applySession(res) {
        this.documentName = res.documentName;
        this.envelopeNumber = res.envelopeNumber;
        this.recipientName = res.recipientName;
        this.signerRole = res.signerRole || 'Customer';
        this.consentAccepted = res.consentAccepted === true;
        this.readOnly = res.readOnly === true;
        this.envelopeStatus = res.envelopeStatus;
        this.signedAt = res.signedAt;
        this.isLastSigner = res.isLastSigner === true;
        this.allowReassign = res.allowReassign === true;
        this.allowSignerPlacement = res.allowSignerPlacement === true;
        performanceLogs = res.performanceLogs === true;
        this.pdfBytes = res.pdfBase64 ? base64ToBytes(res.pdfBase64) : null;
        this.placements = Array.isArray(res.placements) ? res.placements : null;
        this.sessionBranding = res.branding || {};
    }

    fail(message) {
        this.errorMessage = message;
        this.state = 'error';
    }

    /** Shows a message at the top of the page for a few seconds; isError defaults to true. */
    showToast(message, isError = true) {
        // Recalled mid-session: keep the recalled notice instead.
        if (message === LABELS.errRecalled) {
            this.fail(message);
            return;
        }
        // The passcode verification ran out: a reload asks for a new code.
        if (message === LABELS.errPasscodeRequired) {
            storePasscodeSession(this.rawToken, null);
            this.fail(message);
            return;
        }
        // The standard toast fits phone screens and is announced by screen readers.
        Toast.show({ label: message, variant: isError ? 'error' : 'info', mode: 'dismissible' }, this);
    }

    // ---------- one-time passcode ----------

    /** Shows the passcode screen, then carries on once the signer enters a correct code. */
    askPasscode(challenge, then) {
        this.passcode = {
            maskedEmail: challenge.maskedEmail,
            sent: challenge.passcodeSent === true,
            digits: challenge.passcodeDigits || 6,
            validMinutes: challenge.passcodeValidMinutes || 10,
            code: '',
            error: null
        };
        this.recipientName = challenge.recipientName;
        this.afterPasscode = then;
        this.startResendCountdown(challenge.resendSeconds || 0);
        this.state = 'passcode';
    }

    startResendCountdown(seconds) {
        clearInterval(this.resendTimer);
        this.resendIn = seconds;
        if (seconds > 0) {
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            this.resendTimer = setInterval(() => {
                this.resendIn -= 1;
                if (this.resendIn <= 0) {
                    clearInterval(this.resendTimer);
                }
            }, 1000);
        }
    }

    async handleSendPasscode() {
        this.isWorking = true;
        try {
            const res = await sendPasscode({ rawToken: this.rawToken, userAgent: navigator.userAgent });
            this.passcode = { ...this.passcode, maskedEmail: res.maskedEmail, sent: true, code: '', error: null };
            this.startResendCountdown(res.resendSeconds);
        } catch (error) {
            this.passcode = { ...this.passcode, error: reduceError(error) };
        } finally {
            this.isWorking = false;
        }
    }

    handlePasscodeInput(event) {
        const code = (event.target.value || '').replace(/\D/g, '').slice(0, this.passcode.digits);
        this.passcode = { ...this.passcode, code, error: null };
    }

    handlePasscodeKeyup(event) {
        if (event.key === 'Enter' && !this.verifyDisabled) {
            this.handleVerifyPasscode();
        }
    }

    async handleVerifyPasscode() {
        this.isWorking = true;
        try {
            const res = await verifyPasscode({
                rawToken: this.rawToken,
                code: this.passcode.code,
                userAgent: navigator.userAgent
            });
            if (res.verified) {
                this.passcodeSession = res.passcodeSession;
                storePasscodeSession(this.rawToken, res.passcodeSession);
                clearInterval(this.resendTimer);
                const then = this.afterPasscode;
                this.afterPasscode = null;
                then();
            } else {
                const triesLeft = res.triesLeft || 0;
                // No tries left: back to asking for a new code.
                this.passcode = {
                    ...this.passcode,
                    sent: triesLeft > 0,
                    code: '',
                    error: triesLeft > 0 ? format(LABELS.passcodeWrong, triesLeft) : LABELS.passcodeExpired
                };
            }
        } catch (error) {
            const message = reduceError(error);
            this.passcode = {
                ...this.passcode,
                sent: this.passcode.sent && message !== LABELS.passcodeExpired,
                code: '',
                error: message
            };
        } finally {
            this.isWorking = false;
        }
    }

    // ---------- consent ----------

    /** Asks for consent once, then carries on with what the signer started. */
    askConsent(then) {
        this.afterConsent = then;
        this.consentRequested = true;
    }

    closeConsentModal() {
        this.consentRequested = false;
        this.afterConsent = null;
    }

    async handleAcceptConsent() {
        this.isWorking = true;
        try {
            await recordConsent({
                rawToken: this.rawToken,
                userAgent: navigator.userAgent,
                passcodeSession: this.passcodeSession
            });
            this.consentAccepted = true;
            const then = this.afterConsent;
            this.closeConsentModal();
            if (then) {
                then();
            }
        } catch (error) {
            this.showToast(reduceError(error));
        } finally {
            this.isWorking = false;
        }
    }

    // ---------- rendering & tag detection ----------

    /** Lays out every page and signing spot at final size, then draws page images in the background. */
    async renderAllPages() {
        if (!this.openedDoc) {
            const openStarted = performance.now();
            this.openingDocument = true;
            try {
                this.openedDoc = await this.runPdfEngine('open', { pdfBytes: this.pdfBytes.slice() });
            } finally {
                this.openingDocument = false;
            }
            timing('document opened', openStarted);
            this.findSignatureSpots();
        }
        const pages = this.openedDoc.pages;
        const container = this.template.querySelector('.pages-wrapper');
        container.textContent = '';
        this.releasePageImages();

        const area = this.viewerArea();
        this.renderedArea = area;
        const scales = pages.map((page) => this.scaleFor(page, area));
        pages.forEach((page, pageIndex) => {
            const wrapper = document.createElement('div');
            // Spins until the page image is drawn into it.
            wrapper.className = 'page-container page-loading';
            wrapper.dataset.scale = String(scales[pageIndex]);
            wrapper.style.width = `${page.width * scales[pageIndex]}px`;
            wrapper.style.height = `${page.height * scales[pageIndex]}px`;
            container.appendChild(wrapper);
        });
        this.pageCount = pages.length;
        this.renderedScale = scales[0];

        // Keeps signatures already applied.
        const wrappers = container.children;
        this.signatureLocations.forEach((spot) => {
            this.addHotspot(spot, wrappers[spot.pageIndex], pages[spot.pageIndex], scales[spot.pageIndex]);
            if (spot.signed) {
                this.applySignature(spot);
            }
        });
        if (!this.pagesClickBound) {
            this.pagesClickBound = true;
            container.addEventListener('click', (event) => this.handlePagesClick(event));
        }
        this.watchWidth();
        this.drawPages(scales);
    }

    /**
     * Remembers every anchor tag (stamping covers them). This signer's tags become signing spots, or, when the sender
     * placed the signatures, those places do.
     */
    findSignatureSpots() {
        const { pages, tagItems } = this.openedDoc;
        const tags = findAnchorTags(tagItems);
        let locations = [];
        if (this.readOnly) {
            // Nothing to sign.
        } else if (this.placements) {
            locations = this.placements
                .filter((place) => place.page < pages.length)
                .map((place, index) => ({
                    id: `spot_${place.page + 1}_placed_${index}`,
                    pageIndex: place.page,
                    pdfX: place.x,
                    pdfY: place.y,
                    height: place.height || SIG_HEIGHT,
                    tagRect: null,
                    signed: false
                }));
        } else {
            const role = this.signerRole.toLowerCase();
            locations = tags
                .filter((tag) => tag.role.toLowerCase() === role)
                .map(({ id, pageIndex, pdfX, pdfY, height, tagRect }) => ({ id, pageIndex, pdfX, pdfY, height, tagRect, signed: false }));
        }
        if (locations.length === 0 && !this.readOnly && this.allowSignerPlacement) {
            // No tag and no place from the sender: the signer chooses where to sign.
            this.signerPlaces = true;
            this.showToast(LABELS.placeOwnNotice, false);
        } else if (locations.length === 0 && !this.readOnly) {
            // No tag for this signer: one spot at the bottom right of the last page.
            const lastIndex = pages.length - 1;
            const [, y0, x1] = pages[lastIndex].view;
            locations.push({
                id: `spot_${pages.length}_fallback`,
                pageIndex: lastIndex,
                pdfX: x1 - SIG_WIDTH - 40,
                pdfY: y0 + 50,
                height: SIG_HEIGHT,
                tagRect: null,
                signed: false
            });
            this.showToast(LABELS.noTagsNotice, false);
        }
        this.tagRects = tags.map(({ pageIndex, tagRect }) => ({ pageIndex, rect: tagRect }));
        this.signatureLocations = locations;
    }

    /** Draws page images one by one from the page in view; a newer redraw stops this pass. */
    async drawPages(scales) {
        this.drawGeneration += 1;
        const generation = this.drawGeneration;
        const pageCount = scales.length;
        const ratio = window.devicePixelRatio || 1;
        const first = Math.min(Math.max(this.currentPage, 1), pageCount) - 1;
        const order = [...Array(pageCount).keys()];
        order.push(...order.splice(0, first));
        const drawStarted = performance.now();
        try {
            for (const pageIndex of order) {
                // Device resolution keeps text sharp on high-density screens.
                // eslint-disable-next-line no-await-in-loop
                const { image } = await this.runPdfEngine('renderPage', {
                    docId: this.openedDoc.docId,
                    pageIndex,
                    scale: scales[pageIndex] * ratio
                });
                if (generation !== this.drawGeneration) {
                    return;
                }
                const url = URL.createObjectURL(image);
                this.pageImageUrls.push(url);
                const img = document.createElement('img');
                img.className = 'page-image';
                img.alt = format(LABELS.pageOf, pageIndex + 1, pageCount);
                img.src = url;
                const wrapper = this.template.querySelectorAll('.page-container')[pageIndex];
                wrapper.insertBefore(img, wrapper.firstChild);
                wrapper.classList.remove('page-loading');
                if (pageIndex === first) {
                    timing('first page shown', drawStarted);
                }
            }
            timing(`${pageCount} pages drawn`, drawStarted);
            if (this.reloadedEngine && !this.hostCacheRefreshed) {
                this.hostCacheRefreshed = true;
                this.refreshHostCache();
            }
        } catch (error) {
            if (generation === this.drawGeneration) {
                this.showToast(reduceError(error));
            }
        }
    }

    releasePageImages() {
        this.pageImageUrls.forEach((url) => URL.revokeObjectURL(url));
        this.pageImageUrls = [];
    }

    // ---------- viewer: fit page / fit width / zoom, and page navigation ----------

    /** Usable space inside the scrolling area, in CSS pixels. */
    viewerArea() {
        const viewportEl = this.template.querySelector('.pdf-scroll-viewport');
        const width = (viewportEl && viewportEl.clientWidth) || window.innerWidth;
        const height = (viewportEl && viewportEl.clientHeight) || window.innerHeight;
        return { width: Math.max(240, width - VIEWER_PADDING * 2), height: Math.max(240, height - VIEWER_PADDING * 2) };
    }

    /** PDF points to CSS pixels for one page, by zoom mode; each page is fitted on its own. */
    scaleFor(base, area) {
        if (this.zoomMode === 'custom') {
            return this.zoomScale;
        }
        const fitWidth = area.width / base.width;
        return this.zoomMode === 'width' ? fitWidth : Math.min(fitWidth, area.height / base.height);
    }

    get zoomLabel() {
        return this.renderedScale ? `${Math.round((this.renderedScale / CSS_PX_PER_PT) * 100)}%` : '';
    }
    get pageIndicator() {
        return format(LABELS.pageOf, this.currentPage, this.pageCount);
    }
    get isFirstPage() {
        return this.currentPage <= 1;
    }
    get isLastPage() {
        return this.currentPage >= this.pageCount;
    }
    get isFitPage() {
        return this.zoomMode === 'page';
    }
    get isFitWidth() {
        return this.zoomMode === 'width';
    }
    get fitPageVariant() {
        return this.isFitPage ? 'brand' : 'neutral';
    }
    get fitWidthVariant() {
        return this.isFitWidth ? 'brand' : 'neutral';
    }

    handleZoomIn() {
        this.setZoom('custom', this.renderedScale * ZOOM_STEP);
    }
    handleZoomOut() {
        this.setZoom('custom', this.renderedScale / ZOOM_STEP);
    }
    handleFitPage() {
        this.setZoom('page');
    }
    handleFitWidth() {
        this.setZoom('width');
    }

    setZoom(mode, scale) {
        if (this.isRendering) {
            return;
        }
        this.zoomMode = mode;
        if (scale) {
            this.zoomScale = Math.min(MAX_ZOOM, Math.max(MIN_ZOOM, scale));
        }
        this.redraw();
    }

    redraw() {
        const keepPage = this.currentPage;
        this.isRendering = true;
        this.renderAllPages()
            .then(() => this.goToPage(keepPage, false))
            .catch((error) => this.showToast(reduceError(error)))
            .finally(() => {
                this.isRendering = false;
            });
    }

    handlePrevPage() {
        this.goToPage(this.currentPage - 1, true);
    }
    handleNextPage() {
        this.goToPage(this.currentPage + 1, true);
    }

    goToPage(pageNum, smooth) {
        const pages = this.template.querySelectorAll('.page-container');
        const target = pages[Math.min(Math.max(pageNum, 1), pages.length) - 1];
        const viewportEl = this.template.querySelector('.pdf-scroll-viewport');
        if (target && viewportEl) {
            const offset = target.getBoundingClientRect().top - viewportEl.getBoundingClientRect().top;
            viewportEl.scrollTo({ top: viewportEl.scrollTop + offset - VIEWER_PADDING, behavior: smooth ? 'smooth' : 'auto' });
        }
    }

    /** The last page whose top has scrolled into the upper third of the viewer. */
    handleViewerScroll() {
        const viewportEl = this.template.querySelector('.pdf-scroll-viewport');
        const limit = viewportEl.getBoundingClientRect().top + viewportEl.clientHeight / 3;
        let current = 1;
        this.template.querySelectorAll('.page-container').forEach((page, index) => {
            if (page.getBoundingClientRect().top <= limit) {
                current = index + 1;
            }
        });
        this.currentPage = current;
    }

    /** Redraws fit-to modes when the viewer really changes size (layout settling, resizing, rotating). */
    watchWidth() {
        if (this.resizeObserver) {
            return;
        }
        const viewportEl = this.template.querySelector('.pdf-scroll-viewport');
        this.resizeObserver = new ResizeObserver(() => this.scheduleWidthCheck());
        this.resizeObserver.observe(viewportEl);
        viewportEl.addEventListener('scroll', () => this.handleViewerScroll(), { passive: true });
        // The layout may have settled while the first pages drew.
        this.scheduleWidthCheck();
    }

    scheduleWidthCheck() {
        clearTimeout(this.resizeTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.resizeTimer = setTimeout(() => {
            if (this.isRendering || !this.showViewer || this.zoomMode === 'custom') {
                return;
            }
            const area = this.viewerArea();
            const widthChanged = Math.abs(area.width - this.renderedArea.width) > 24;
            const heightChanged = this.zoomMode === 'page' && Math.abs(area.height - this.renderedArea.height) > 24;
            if (widthChanged || heightChanged) {
                this.redraw();
            }
        }, 200);
    }

    /** Fits the portal to the window height left below the site's header, so "fit page" shows the whole page. */
    fitToWindow() {
        const root = this.template.querySelector('.portal-root');
        if (root) {
            const top = root.getBoundingClientRect().top + window.scrollY;
            root.style.height = `${Math.max(420, window.innerHeight - top)}px`;
        }
    }

    disconnectedCallback() {
        clearInterval(this.resendTimer);
        this.drawGeneration += 1;
        this.releasePageImages();
        window.removeEventListener('resize', this.boundFitToWindow);
        window.removeEventListener('message', this.boundEngineMessage);
        this.stopPlacing();
        if (this.resizeObserver) {
            this.resizeObserver.disconnect();
        }
    }

    // ---------- PDF engine ----------

    /** Loads the PDF host page in a hidden iframe. */
    startPdfEngine() {
        this.enginePending = new Map();
        this.engineReady = new Promise((resolve) => {
            this.resolveEngineReady = resolve;
        });
        this.boundEngineMessage = (event) => this.handleEngineMessage(event);
        window.addEventListener('message', this.boundEngineMessage);
        this.loadEnginePage(`/${PDF_HOST_NAME}/index.html`);
    }

    loadEnginePage(path) {
        this.engineAttempt = (this.engineAttempt || 0) + 1;
        const attempt = this.engineAttempt;
        this.engineWindow = null;
        this.hostVersion = undefined;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            if (attempt === this.engineAttempt) {
                this.resolveEngineReady(false);
            }
        }, ENGINE_READY_TIMEOUT_MS);
        const site = window.location.pathname.split('/')[1];
        this.pdfEngineUrl = `/${site}/sfsites/c/resource${path}`;
    }

    /**
     * The plain host address may come from a cache filled before the last deploy. Once both versions are known, a
     * stale host is reloaded once at the versioned address.
     */
    confirmEngineVersion(currentVersion) {
        this.currentHostVersion = currentVersion || null;
        this.settleEngine();
    }

    settleEngine() {
        if (this.hostVersion === undefined || this.currentHostVersion === undefined) {
            return;
        }
        // Last-Modified has whole seconds; the stored version has milliseconds.
        const stale = this.currentHostVersion && this.hostVersion < Math.floor(this.currentHostVersion / 1000) * 1000;
        if (stale) {
            // Ignore late messages from the stale copy; the timeout covers the rest.
            if (!this.reloadedEngine) {
                this.reloadedEngine = true;
                this.loadEnginePage(`/${this.currentHostVersion}/${PDF_HOST_NAME}/index.html`);
            }
            return;
        }
        this.resolveEngineReady(true);
    }

    /** After replacing a stale host, refreshes the cached copy at the plain address once the pages are drawn. */
    refreshHostCache() {
        const site = window.location.pathname.split('/')[1];
        const plainPage = `${window.location.origin}/${site}/sfsites/c/resource/${PDF_HOST_NAME}/index.html`;
        this.requestFromEnginePage('refreshPlainCopy', { plainPage }).catch(() => {});
    }

    handleEngineMessage(event) {
        const data = event.data;
        if (event.origin !== window.location.origin || !data || !data.signZeroEngine) {
            return;
        }
        if (data.signZeroEngine === 'ready') {
            this.engineWindow = event.source; // repeated announcements are harmless
            this.hostVersion = Number(data.version) || 0;
            this.settleEngine();
        } else if (data.signZeroEngine === 'response' && this.enginePending.has(data.id)) {
            const { resolve, reject } = this.enginePending.get(data.id);
            this.enginePending.delete(data.id);
            if (data.error) {
                reject(new Error(data.error));
            } else {
                resolve(data.result);
            }
        }
    }

    /** One request to the host page; rejects on timeout so a stuck page cannot hang signing. */
    requestFromEnginePage(op, payload) {
        this.engineRequestId = (this.engineRequestId || 0) + 1;
        const id = this.engineRequestId;
        return new Promise((resolve, reject) => {
            this.enginePending.set(id, { resolve, reject });
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => {
                if (this.enginePending.delete(id)) {
                    reject(new Error('no answer'));
                }
            }, ENGINE_REQUEST_TIMEOUT_MS[op]);
            this.engineWindow.postMessage({ signZeroEngine: 'request', id, op, payload }, window.location.origin);
        });
    }

    /** Runs an engine operation in the host page, or in this component when the page is unavailable. */
    async runPdfEngine(op, payload) {
        let request = payload;
        if (!this.engineInComponent && (await this.engineReady)) {
            try {
                return await this.requestFromEnginePage(op, payload);
            } catch (error) {
                // eslint-disable-next-line no-console
                console.warn(`[SignZero] PDF host page failed (${error.message}); continuing in the component`);
                this.engineInComponent = true;
                if (op === 'renderPage') {
                    // The document was opened in the host page; open it here too.
                    await this.loadEngineInComponent();
                    const reopened = await window.SignZeroPdfEngine.open({ pdfBytes: this.pdfBytes.slice() });
                    this.openedDoc = { ...this.openedDoc, docId: reopened.docId };
                    request = { ...payload, docId: reopened.docId };
                }
            }
        }
        this.engineInComponent = true;
        await this.loadEngineInComponent();
        return window.SignZeroPdfEngine[op](request);
    }

    async loadEngineInComponent() {
        if (window.SignZeroPdfEngine) {
            return;
        }
        await loadScript(this, PDF_HOST_RESOURCE + '/pdf-lib.min.js');
        await loadScript(this, PDF_HOST_RESOURCE + '/pdf.min.js');
        // Loading the worker script in the page avoids a Web Worker, which Lightning Web Security blocks.
        await loadScript(this, PDF_HOST_RESOURCE + '/pdf.worker.min.js');
        window.pdfjsLib.GlobalWorkerOptions.workerSrc = PDF_HOST_RESOURCE + '/pdf.worker.min.js';
        await loadScript(this, PDF_HOST_RESOURCE + '/engine.js');
    }

    /** @param page page size and PDF-to-screen transform at scale 1 */
    addHotspot(spot, wrapper, page, scale) {
        const hotspot = document.createElement('div');
        hotspot.className = spot.placedBySigner ? 'signature-hotspot own-place' : 'signature-hotspot';
        hotspot.dataset.spotId = spot.id;
        hotspot.setAttribute('role', 'button');
        hotspot.setAttribute('tabindex', '0');
        hotspot.setAttribute('aria-label', LABELS.signHere);
        this.positionHotspot(hotspot, spot, page, scale);
        hotspot.textContent = LABELS.signHere;
        if (spot.placedBySigner) {
            hotspot.addEventListener('pointerdown', (event) => this.handleOwnPlacePointerDown(event, spot));
        }
        hotspot.addEventListener('click', () => this.handleSpotClick(spot.id));
        hotspot.addEventListener('keydown', (event) => {
            if (event.key === 'Enter' || event.key === ' ') {
                event.preventDefault();
                this.handleSpotClick(spot.id);
            }
        });
        wrapper.appendChild(hotspot);
    }

    /** Sets a hotspot's box on its page from the spot's PDF position. */
    positionHotspot(hotspot, spot, page, scale) {
        const [a, b, c, d, e, f] = page.transform.map((value) => value * scale);
        const toScreen = (x, y) => [a * x + c * y + e, b * x + d * y + f];
        const [left, top] = toScreen(spot.pdfX, spot.pdfY);
        const [right, bottom] = toScreen(spot.pdfX + SIG_WIDTH, spot.pdfY + spot.height);
        hotspot.style.left = `${Math.min(left, right)}px`;
        hotspot.style.top = `${Math.min(top, bottom)}px`;
        hotspot.style.width = `${Math.abs(right - left)}px`;
        hotspot.style.height = `${Math.abs(bottom - top)}px`;
    }

    // ---------- placing their own signature, when the signer has no tag ----------

    startPlacing() {
        if (!this.adoptedSignature) {
            // Adopt a signature first, then place it.
            this.activeSpotId = null;
            this.openSignaturePad();
            this.placeAfterAdopt = true;
            return;
        }
        this.placingSignature = true;
        if (!this.boundPlacingKeyDown) {
            this.boundPlacingKeyDown = (event) => {
                if (event.key === 'Escape') {
                    this.stopPlacing();
                }
            };
        }
        window.addEventListener('keydown', this.boundPlacingKeyDown);
    }

    stopPlacing() {
        this.placingSignature = false;
        if (this.boundPlacingKeyDown) {
            window.removeEventListener('keydown', this.boundPlacingKeyDown);
        }
    }

    handleAddAnotherSignature() {
        this.startPlacing();
    }

    get showAddAnother() {
        return this.signerPlaces && !this.placingSignature && this.signatureLocations.length > 0 && !this.isSubmitting;
    }

    get placingHint() {
        return this.placingSignature ? LABELS.placeHint : null;
    }

    /** Page wrappers in the viewer, and the one under a screen point. */
    pageWrapperAt(clientX, clientY) {
        const wrappers = [...this.template.querySelectorAll('.page-container')];
        const index = wrappers.findIndex((wrapper) => {
            const rect = wrapper.getBoundingClientRect();
            return clientX >= rect.left && clientX <= rect.right && clientY >= rect.top && clientY <= rect.bottom;
        });
        return index === -1 ? null : { index, wrapper: wrappers[index] };
    }

    /** The bottom left PDF point of a signature centred on a screen point, kept inside the page. */
    pdfPositionAt(hit, clientX, clientY, height) {
        const page = this.openedDoc.pages[hit.index];
        const scale = Number(hit.wrapper.dataset.scale);
        const rect = hit.wrapper.getBoundingClientRect();
        const u = (clientX - rect.left) / scale;
        const v = (clientY - rect.top) / scale;
        const [a, b, c, d, e, f] = page.transform;
        const det = a * d - b * c;
        const cx = (d * (u - e) - c * (v - f)) / det;
        const cy = (-b * (u - e) + a * (v - f)) / det;
        const [x0, y0, x1, y1] = page.view;
        return {
            pdfX: Math.min(Math.max(cx - SIG_WIDTH / 2, x0), x1 - SIG_WIDTH),
            pdfY: Math.min(Math.max(cy - height / 2, y0), y1 - height)
        };
    }

    handlePagesClick(event) {
        if (!this.placingSignature || this.suppressPageClick || event.target.closest('.signature-hotspot')) {
            return;
        }
        const hit = this.pageWrapperAt(event.clientX, event.clientY);
        if (!hit) {
            return;
        }
        this.ownPlaceCount += 1;
        const spot = {
            id: `spot_own_${this.ownPlaceCount}`,
            pageIndex: hit.index,
            ...this.pdfPositionAt(hit, event.clientX, event.clientY, SIG_HEIGHT),
            height: SIG_HEIGHT,
            tagRect: null,
            signed: false,
            placedBySigner: true
        };
        this.signatureLocations = [...this.signatureLocations, spot];
        this.addHotspot(spot, hit.wrapper, this.openedDoc.pages[hit.index], Number(hit.wrapper.dataset.scale));
        this.applySignature(spot);
        this.stopPlacing();
    }

    addRemoveButton(element, spot) {
        const remove = document.createElement('button');
        remove.type = 'button';
        remove.className = 'own-place-remove';
        remove.textContent = '\u00d7';
        remove.title = LABELS.placeRemove;
        remove.setAttribute('aria-label', LABELS.placeRemove);
        remove.addEventListener('pointerdown', (event) => event.stopPropagation());
        remove.addEventListener('click', (event) => {
            event.stopPropagation();
            this.removeOwnPlace(spot);
        });
        element.appendChild(remove);
        element.addEventListener('keydown', (event) => {
            if (event.key === 'Delete' || event.key === 'Backspace') {
                event.preventDefault();
                this.removeOwnPlace(spot);
            }
        });
    }

    removeOwnPlace(spot) {
        if (this.isSubmitting) {
            return;
        }
        const element = this.hotspotElement(spot.id);
        if (element) {
            element.remove();
        }
        this.signatureLocations = this.signatureLocations.filter((loc) => loc !== spot);
    }

    handleOwnPlacePointerDown(event, spot) {
        if (event.button !== 0 || this.isSubmitting) {
            return;
        }
        event.preventDefault();
        const element = event.currentTarget;
        element.focus({ preventScroll: true });
        const rect = element.getBoundingClientRect();
        // Where the box was grabbed, from its centre, so it does not jump under the pointer.
        const drag = {
            startX: event.clientX,
            startY: event.clientY,
            offsetX: event.clientX - (rect.left + rect.width / 2),
            offsetY: event.clientY - (rect.top + rect.height / 2),
            moved: false
        };
        const move = (e) => {
            if (!drag.moved && Math.hypot(e.clientX - drag.startX, e.clientY - drag.startY) < DRAG_THRESHOLD_PX) {
                return;
            }
            drag.moved = true;
            const x = e.clientX - drag.offsetX;
            const y = e.clientY - drag.offsetY;
            const hit = this.pageWrapperAt(x, y);
            if (!hit) {
                return;
            }
            Object.assign(spot, { pageIndex: hit.index, ...this.pdfPositionAt(hit, x, y, spot.height) });
            if (element.parentElement !== hit.wrapper) {
                hit.wrapper.appendChild(element);
            }
            this.positionHotspot(element, spot, this.openedDoc.pages[hit.index], Number(hit.wrapper.dataset.scale));
        };
        const up = () => {
            window.removeEventListener('pointermove', move);
            window.removeEventListener('pointerup', up);
            window.removeEventListener('pointercancel', up);
            if (drag.moved) {
                // The click that may follow a drag must not place another signature.
                this.suppressPageClick = true;
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                setTimeout(() => {
                    this.suppressPageClick = false;
                }, 0);
                this.signatureLocations = [...this.signatureLocations];
            }
        };
        window.addEventListener('pointermove', move);
        window.addEventListener('pointerup', up);
        window.addEventListener('pointercancel', up);
    }

    hotspotElement(spotId) {
        return this.template.querySelector(`[data-spot-id="${spotId}"]`);
    }

    // ---------- guided navigation ----------

    handleJumpToNextField() {
        if (!this.consentAccepted) {
            this.askConsent(() => this.handleJumpToNextField());
            return;
        }
        if (this.signerPlaces) {
            if (this.placingSignature) {
                this.stopPlacing();
            } else if (this.signatureLocations.length === 0) {
                this.startPlacing();
            } else {
                this.handleFinalSubmission();
            }
            return;
        }
        const pending = this.signatureLocations.filter((loc) => !loc.signed);
        if (pending.length === 0) {
            this.handleFinalSubmission();
            return;
        }
        // guidedIndex is in document order, so signing a spot never shifts where "next" lands.
        const locations = this.signatureLocations;
        const next = pending.find((loc) => locations.indexOf(loc) > this.guidedIndex) || pending[0];
        this.guidedIndex = locations.indexOf(next);
        const element = this.hotspotElement(next.id);
        if (element) {
            element.scrollIntoView({ behavior: 'smooth', block: 'center' });
            element.classList.add('active-target');
            element.focus({ preventScroll: true });
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => element.classList.remove('active-target'), 2000);
        }
    }

    handleSpotClick(spotId) {
        if (this.isSubmitting) {
            return;
        }
        if (!this.consentAccepted) {
            this.askConsent(() => this.handleSpotClick(spotId));
            return;
        }
        const spot = this.signatureLocations.find((loc) => loc.id === spotId);
        if (!spot || spot.placedBySigner) {
            return;
        }
        this.guidedIndex = this.signatureLocations.indexOf(spot);
        if (this.adoptedSignature && !spot.signed) {
            this.applySignature(spot);
            return;
        }
        this.activeSpotId = spotId;
        this.openSignaturePad();
    }

    applySignature(spot) {
        spot.signed = true;
        const element = this.hotspotElement(spot.id);
        if (element) {
            element.textContent = '';
            const img = document.createElement('img');
            // Resized once loaded and whenever a new signature replaces it.
            img.onload = () => sizeSignatureImage(img, element);
            img.src = this.adoptedSignature;
            img.alt = `Signature of ${this.recipientName}`;
            element.appendChild(img);
            element.classList.add('signed');
            element.setAttribute('aria-label', 'Signed');
            if (spot.placedBySigner) {
                this.addRemoveButton(element, spot);
            }
        }
        // Reassign so counts re-render.
        this.signatureLocations = [...this.signatureLocations];
    }

    // ---------- adopting a signature: type, draw or upload ----------

    get isDrawMode() {
        return this.signatureMode === 'draw';
    }
    get isTypeMode() {
        return this.signatureMode === 'type';
    }
    get isUploadMode() {
        return this.signatureMode === 'upload';
    }
    get typedStyleOptions() {
        const name = this.typedName || this.recipientName;
        return TYPED_STYLES.map((style, index) => ({
            index,
            text: name,
            inlineStyle: `font-family: ${style.family}; font-style: ${style.italic ? 'italic' : 'normal'};`,
            selected: index === this.typedStyle,
            className: index === this.typedStyle ? 'typed-option selected' : 'typed-option'
        }));
    }
    get adoptDisabled() {
        if (this.isDrawMode) {
            return this.padIsEmpty;
        }
        if (this.isTypeMode) {
            return !(this.typedName && this.typedName.trim());
        }
        return !this.uploadedSignature;
    }

    openSignaturePad() {
        this.sigCtx = null;
        this.padIsEmpty = true;
        // Start on a typed signature with the signer's name filled in.
        this.signatureMode = 'type';
        this.typedName = this.typedName || this.recipientName;
        this.uploadError = null;
        this.showSignatureModal = true;
    }

    handleModeChange(event) {
        this.signatureMode = event.target.value;
        this.sigCtx = null; // the draw canvas is set up again when its tab is shown
        this.padIsEmpty = true;
    }

    handleTypedNameChange(event) {
        this.typedName = event.target.value;
    }

    handleTypedStyleChange(event) {
        this.typedStyle = Number(event.currentTarget.dataset.index);
    }

    handleChangeSignature() {
        this.activeSpotId = null;
        this.openSignaturePad();
    }

    closeSignatureModal() {
        this.showSignatureModal = false;
        this.activeSpotId = null;
        this.sigCtx = null;
        this.placeAfterAdopt = false;
    }

    renderedCallback() {
        if (this.showSignatureModal && this.isDrawMode && !this.sigCtx) {
            const canvas = this.template.querySelector('.sig-pad');
            if (canvas) {
                const ratio = window.devicePixelRatio || 1;
                const rect = canvas.getBoundingClientRect();
                canvas.width = Math.floor(rect.width * ratio);
                canvas.height = Math.floor(rect.height * ratio);
                this.sigCtx = canvas.getContext('2d');
                this.sigCtx.scale(ratio, ratio);
                this.sigCtx.lineWidth = 2.5;
                this.sigCtx.lineCap = 'round';
                this.sigCtx.lineJoin = 'round';
                this.sigCtx.strokeStyle = INK;
            }
        }
    }

    pointFrom(event) {
        const rect = event.currentTarget.getBoundingClientRect();
        return { x: event.clientX - rect.left, y: event.clientY - rect.top };
    }

    startDrawing(event) {
        if (!this.sigCtx) {
            return;
        }
        event.preventDefault();
        event.currentTarget.setPointerCapture(event.pointerId);
        this.isDrawing = true;
        const { x, y } = this.pointFrom(event);
        this.sigCtx.beginPath();
        this.sigCtx.moveTo(x, y);
    }

    draw(event) {
        if (!this.isDrawing) {
            return;
        }
        event.preventDefault();
        const { x, y } = this.pointFrom(event);
        this.sigCtx.lineTo(x, y);
        this.sigCtx.stroke();
        if (this.padIsEmpty) {
            this.padIsEmpty = false;
        }
    }

    stopDrawing() {
        this.isDrawing = false;
    }

    clearSignaturePad() {
        if (this.isUploadMode) {
            this.uploadedSignature = null;
            return;
        }
        if (this.isTypeMode) {
            this.typedName = '';
            return;
        }
        const canvas = this.template.querySelector('.sig-pad');
        if (this.sigCtx && canvas) {
            this.sigCtx.clearRect(0, 0, canvas.width, canvas.height);
        }
        this.padIsEmpty = true;
    }

    /**
     * Typed signature: the name in the chosen font, as a PNG. Cropped to the ink across, but to the font's full line
     * height down, so the letters sit at handwriting size in the signature area instead of filling it.
     */
    renderTypedSignature() {
        const style = TYPED_STYLES[this.typedStyle];
        const text = this.typedName.trim();
        const canvas = document.createElement('canvas');
        const ctx = canvas.getContext('2d');
        let size = 110;
        let font;
        let metrics;
        do {
            font = `${style.italic ? 'italic ' : ''}${size}px ${style.family}`;
            ctx.font = font;
            metrics = ctx.measureText(text);
            size -= 4;
        } while (metrics.width > SIGNATURE_IMAGE_WIDTH - 40 && size > 24);
        // The same line height for every style (fonts report very different ones); flourishes past it are kept.
        const fontSize = size + 4;
        const ascent = Math.max(TYPED_ASCENT * fontSize, metrics.actualBoundingBoxAscent);
        const descent = Math.max(TYPED_DESCENT * fontSize, metrics.actualBoundingBoxDescent);
        canvas.width = Math.ceil(metrics.actualBoundingBoxLeft + metrics.actualBoundingBoxRight) + INK_EDGE * 2;
        canvas.height = Math.ceil(ascent + descent) + INK_EDGE * 2;
        // Resizing the canvas resets its drawing state.
        ctx.font = font;
        ctx.fillStyle = INK;
        ctx.textAlign = 'left';
        ctx.textBaseline = 'alphabetic';
        ctx.fillText(text, metrics.actualBoundingBoxLeft + INK_EDGE, ascent + INK_EDGE);
        return canvas.toDataURL('image/png');
    }


    /** Uploaded signature: only the ink is kept. */
    handleUpload(event) {
        this.processUpload(event.detail.files && event.detail.files[0]);
    }

    processUpload(file) {
        this.uploadError = null;
        this.uploadedSignature = null;
        if (!file || !['image/png', 'image/jpeg'].includes(file.type) || file.size > MAX_UPLOAD_BYTES) {
            this.uploadError = LABELS.uploadInvalid;
            return;
        }
        this.isProcessingUpload = true;
        const reader = new FileReader();
        reader.onload = () => {
            const img = new Image();
            img.onload = () => {
                // Let the spinner paint before the pixel work blocks the page.
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                setTimeout(() => {
                    const signature = this.extractUploadedSignature(img);
                    if (signature) {
                        this.uploadedSignature = signature;
                    } else {
                        this.uploadError = LABELS.uploadNoInk;
                    }
                    this.isProcessingUpload = false;
                }, 50);
            };
            img.onerror = () => {
                this.uploadError = LABELS.uploadInvalid;
                this.isProcessingUpload = false;
            };
            img.src = reader.result;
        };
        reader.onerror = () => {
            this.uploadError = LABELS.uploadInvalid;
            this.isProcessingUpload = false;
        };
        reader.readAsDataURL(file);
    }

    /**
     * Keeps just the signature from a photo or scan, as PDF readers do: paper becomes transparent, shadows are ignored
     * and the image is cropped to the strokes. Returns a PNG data URL, or null when no ink was found.
     */
    extractUploadedSignature(img) {
        const scale = Math.min(UPLOAD_WORK_SIZE / Math.max(img.width, img.height), 1);
        const width = Math.max(1, Math.round(img.width * scale));
        const height = Math.max(1, Math.round(img.height * scale));
        const work = document.createElement('canvas');
        work.width = width;
        work.height = height;
        const workCtx = work.getContext('2d');
        // A transparent PNG is read as ink on white paper.
        workCtx.fillStyle = '#ffffff';
        workCtx.fillRect(0, 0, width, height);
        workCtx.drawImage(img, 0, 0, width, height);
        const result = extractInk(workCtx.getImageData(0, 0, width, height));
        if (!result) {
            return null;
        }
        const pixels = workCtx.createImageData(width, height);
        pixels.data.set(result.data);
        workCtx.putImageData(pixels, 0, 0);

        const { crop } = result;
        const fit = Math.min(1, SIGNATURE_MAX_HEIGHT / crop.height);
        const canvas = document.createElement('canvas');
        canvas.width = Math.max(1, Math.round(crop.width * fit));
        canvas.height = Math.max(1, Math.round(crop.height * fit));
        canvas.getContext('2d').drawImage(work, crop.x, crop.y, crop.width, crop.height, 0, 0, canvas.width, canvas.height);
        return canvas.toDataURL('image/png');
    }

    confirmSignaturePlacement() {
        if (this.adoptDisabled) {
            return;
        }
        if (this.isDrawMode) {
            this.adoptedSignature = trimToInk(this.template.querySelector('.sig-pad')).toDataURL('image/png');
            this.adoptedMethod = 'Drawn';
        } else if (this.isTypeMode) {
            this.adoptedSignature = this.renderTypedSignature();
            this.adoptedMethod = 'Typed';
        } else {
            this.adoptedSignature = this.uploadedSignature;
            this.adoptedMethod = 'Uploaded';
        }

        // Re-signing replaces the image on every spot already signed.
        this.signatureLocations
            .filter((loc) => loc.signed)
            .forEach((loc) => {
                const img = this.hotspotElement(loc.id)?.querySelector('img');
                if (img) {
                    img.src = this.adoptedSignature;
                }
            });
        const spot = this.signatureLocations.find((loc) => loc.id === this.activeSpotId);
        if (spot && !spot.signed) {
            this.applySignature(spot);
        }
        const placeNext = this.placeAfterAdopt;
        this.closeSignatureModal();
        if (placeNext) {
            this.startPlacing();
        }
    }

    // ---------- submit / decline ----------

    async handleFinalSubmission() {
        if (this.remainingSpots > 0 || !this.adoptedSignature || this.signatureLocations.length === 0) {
            return;
        }
        this.stopPlacing();
        this.state = 'submitting';
        try {
            const stampStarted = performance.now();
            const stamped = await this.stampSignatures();
            timing('signatures stamped', stampStarted);
            const submitStarted = performance.now();
            const result = await submitExecutedDocument({
                rawToken: this.rawToken,
                executedPdfBase64: stamped,
                // An uploaded image reaches Salesforce only inside the signed PDF.
                signatureImageBase64: this.adoptedMethod === 'Uploaded' ? null : this.adoptedSignature.split(',')[1],
                signatureMethod: this.adoptedMethod,
                userAgent: navigator.userAgent,
                // Recorded as evidence that the signer chose where to sign.
                signerPlacements: this.signerPlaces
                    ? JSON.stringify(
                          this.signatureLocations.map(({ pageIndex, pdfX, pdfY }) => ({
                              page: pageIndex,
                              x: Math.round(pdfX * 100) / 100,
                              y: Math.round(pdfY * 100) / 100
                          }))
                      )
                    : null,
                passcodeSession: this.passcodeSession
            });
            timing('submitted to Salesforce', submitStarted);
            this.isFinalSigner = result && result.isFinalSigner === true;
            this.state = 'done';
        } catch (error) {
            this.state = 'signing';
            this.showToast(reduceError(error));
        }
    }

    /** Stamps the adopted signature into the PDF and returns it as base64. */
    async stampSignatures() {
        const signedAt = new Date().toISOString().replace('T', ' ').substring(0, 19) + ' UTC';
        const stamped = await this.runPdfEngine('stamp', {
            pdfBytes: this.pdfBytes.slice(),
            pngBytes: base64ToBytes(this.adoptedSignature.split(',')[1]),
            spots: this.signatureLocations.map(({ pageIndex, pdfX, pdfY, height }) => ({ pageIndex, pdfX, pdfY, height })),
            tagRects: this.tagRects.map(({ pageIndex, rect }) => ({ pageIndex, rect: { ...rect } })),
            signerRole: this.signerRole,
            // The last signer also clears tags for roles nobody signed as.
            clearAllTags: this.isLastSigner,
            caption: format(LABELS.stampCaption, this.recipientName, signedAt)
        });
        return bytesToBase64(stamped);
    }

    // ---------- assign to someone else ----------

    openReassignModal() {
        this.showReassignModal = true;
    }

    closeReassignModal() {
        this.showReassignModal = false;
    }

    handleReassignInput(event) {
        this.reassignTo = { ...this.reassignTo, [event.target.dataset.field]: event.target.value };
    }

    async confirmReassign() {
        this.isWorking = true;
        try {
            await reassign({
                rawToken: this.rawToken,
                name: this.reassignTo.name,
                email: this.reassignTo.email,
                reason: this.reassignTo.reason,
                userAgent: navigator.userAgent,
                passcodeSession: this.passcodeSession
            });
            this.showReassignModal = false;
            this.state = 'reassigned';
        } catch (error) {
            this.showToast(reduceError(error));
        } finally {
            this.isWorking = false;
        }
    }

    /** The phone menu in the document bar runs the same actions as the buttons. */
    handleDocAction(event) {
        const action = event.detail.value;
        if (action === 'changeSignature') {
            this.handleChangeSignature();
        } else if (action === 'reassign') {
            this.openReassignModal();
        } else if (action === 'decline') {
            this.openDeclineModal();
        }
    }

    openDeclineModal() {
        this.showDeclineModal = true;
    }

    closeDeclineModal() {
        this.showDeclineModal = false;
    }

    handleReasonChange(event) {
        this.declineReason = event.target.value;
    }

    async confirmDecline() {
        this.isWorking = true;
        try {
            await declineToSign({
                rawToken: this.rawToken,
                reason: this.declineReason,
                userAgent: navigator.userAgent,
                passcodeSession: this.passcodeSession
            });
            this.showDeclineModal = false;
            this.state = 'declined';
        } catch (error) {
            this.showToast(reduceError(error));
        } finally {
            this.isWorking = false;
        }
    }
}