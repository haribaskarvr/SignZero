import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { loadScript } from 'lightning/platformResourceLoader';
import PDF_HOST_RESOURCE from '@salesforce/resourceUrl/signZeroPdfHost';
import initializeSession from '@salesforce/apex/SignZeroGatewayController.initializeSession';
import recordConsent from '@salesforce/apex/SignZeroGatewayController.recordConsent';
import submitExecutedDocument from '@salesforce/apex/SignZeroGatewayController.submitExecutedDocument';
import declineToSign from '@salesforce/apex/SignZeroGatewayController.declineToSign';
import { extractInk } from './signatureInk';
import reassign from '@salesforce/apex/SignZeroGatewayController.reassign';

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
    errRecalled
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
const SIGNATURE_IMAGE_HEIGHT = 200;
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

// Signature size in PDF points; the "Signed electronically by" caption goes just under it.
const SIG_WIDTH = 150;
const SIG_HEIGHT = 30;
// A signature fills its area's width and may rise above it up to this many times its height.
// Keep in step with signZeroPdfHost/engine.js.
const SIG_OVERFLOW = 2;
const MIN_SIG_HEIGHT = 16;
const MAX_SIG_HEIGHT = 80;

/**
 * Where a signature goes relative to its tag:
 *   {{sig:Customer}}          on the tag's line
 *   {{sig:Customer|below}}    hanging below the tag, e.g. into an empty table cell
 *   {{sig:Customer|h=40}}     height in points (16-80); options combine: {{sig:Customer|below|h=40}}
 */
function placementFor(tagText, tagX, tagY, fontHeight) {
    const options = (tagText.match(/\|([^}]*)\}\}$/) || [null, ''])[1].toLowerCase().split('|').map((o) => o.trim());
    const heightOption = options.find((o) => /^h\s*=\s*\d+$/.test(o));
    const height = heightOption
        ? Math.min(MAX_SIG_HEIGHT, Math.max(MIN_SIG_HEIGHT, Number(heightOption.split('=')[1])))
        : SIG_HEIGHT;
    const imageY = options.includes('below')
        ? tagY + fontHeight * 0.8 - height // top of the signature level with the top of the tag
        : tagY - fontHeight * 0.2; // bottom of the signature on the tag's baseline
    return { pdfX: tagX, pdfY: imageY, height };
}
const VIEWER_PADDING = 16;
const CSS_PX_PER_PT = 96 / 72; // 100% zoom
const ZOOM_STEP = 1.25;
const MIN_ZOOM = 0.25 * CSS_PX_PER_PT;
const MAX_ZOOM = 4 * CSS_PX_PER_PT;

function escapeRegExp(value) {
    return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

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
    state = 'loading'; // loading | error | signing | submitting | done | declined
    loadingMessage = LABELS.loadingSession;
    isFinalSigner = false;
    errorMessage;
    toastMessage;
    toastIsError = true;
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
    signatureMode = 'type'; // type | draw | upload
    typedName = '';
    typedStyle = 0;
    uploadedSignature; // PNG data URL
    uploadError;
    isProcessingUpload = false;
    adoptedMethod; // Drawn | Typed | Uploaded
    started = false;

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
        return this.isSigning ? 'document-container' : 'document-container hidden';
    }

    get remainingSpots() {
        return this.signatureLocations.filter((loc) => !loc.signed).length;
    }

    get guideButtonLabel() {
        if (this.isSubmitting) {
            return LABELS.submitting;
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
            let session = await initializeSession({ rawToken: this.rawToken, userAgent: navigator.userAgent });
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
                session = await initializeSession({ rawToken: this.rawToken, userAgent: navigator.userAgent });
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
        performanceLogs = res.performanceLogs === true;
        this.pdfBytes = res.pdfBase64 ? base64ToBytes(res.pdfBase64) : null;
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
        this.toastIsError = isError;
        this.toastMessage = message;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            this.toastMessage = null;
        }, 5000);
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
            await recordConsent({ rawToken: this.rawToken, userAgent: navigator.userAgent });
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
            this.openedDoc = await this.runPdfEngine('open', { pdfBytes: this.pdfBytes.slice() });
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
        this.watchWidth();
        this.drawPages(scales);
    }

    /** Remembers every anchor tag (stamping covers them); this signer's become signing spots. */
    findSignatureSpots() {
        const { pages, tagItems } = this.openedDoc;
        const anyTag = /\{\{\s*sig\s*:[^}]*\}\}/gi;
        const ownTag = new RegExp(`^\\{\\{\\s*sig\\s*:\\s*${escapeRegExp(this.signerRole)}\\s*(?:\\|[^}]*)?\\}\\}$`, 'i');
        const tagRects = [];
        const locations = [];
        tagItems.forEach((item) => {
            anyTag.lastIndex = 0;
            let match;
            while ((match = anyTag.exec(item.str)) !== null) {
                const charWidth = item.str.length ? item.width / item.str.length : 0;
                const fontHeight = Math.hypot(item.transform[2], item.transform[3]) || 10;
                const tagX = item.transform[4] + match.index * charWidth;
                const tagY = item.transform[5];
                const tagRect = { x: tagX, y: tagY - fontHeight * 0.3, width: match[0].length * charWidth, height: fontHeight * 1.3 };
                tagRects.push({ pageIndex: item.pageIndex, rect: tagRect });
                if (this.readOnly || !ownTag.test(match[0])) {
                    continue;
                }
                locations.push({
                    id: `spot_${item.pageIndex + 1}_${item.itemIndex}_${match.index}`,
                    pageIndex: item.pageIndex,
                    ...placementFor(match[0], tagX, tagY, fontHeight),
                    tagRect,
                    signed: false
                });
            }
        });
        if (locations.length === 0 && !this.readOnly) {
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
        this.tagRects = tagRects;
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
        this.drawGeneration += 1;
        this.releasePageImages();
        window.removeEventListener('resize', this.boundFitToWindow);
        window.removeEventListener('message', this.boundEngineMessage);
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
        const [a, b, c, d, e, f] = page.transform.map((value) => value * scale);
        const toScreen = (x, y) => [a * x + c * y + e, b * x + d * y + f];
        const [left, top] = toScreen(spot.pdfX, spot.pdfY);
        const [right, bottom] = toScreen(spot.pdfX + SIG_WIDTH, spot.pdfY + spot.height);
        const hotspot = document.createElement('div');
        hotspot.className = 'signature-hotspot';
        hotspot.dataset.spotId = spot.id;
        hotspot.setAttribute('role', 'button');
        hotspot.setAttribute('tabindex', '0');
        hotspot.setAttribute('aria-label', LABELS.signHere);
        hotspot.style.left = `${Math.min(left, right)}px`;
        hotspot.style.top = `${Math.min(top, bottom)}px`;
        hotspot.style.width = `${Math.abs(right - left)}px`;
        hotspot.style.height = `${Math.abs(bottom - top)}px`;
        hotspot.textContent = LABELS.signHere;
        hotspot.addEventListener('click', () => this.handleSpotClick(spot.id));
        hotspot.addEventListener('keydown', (event) => {
            if (event.key === 'Enter' || event.key === ' ') {
                event.preventDefault();
                this.handleSpotClick(spot.id);
            }
        });
        wrapper.appendChild(hotspot);
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
        if (!spot) {
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

    /** Typed signature: the name in the chosen font, as a PNG. */
    renderTypedSignature() {
        const style = TYPED_STYLES[this.typedStyle];
        const canvas = document.createElement('canvas');
        canvas.width = SIGNATURE_IMAGE_WIDTH;
        canvas.height = SIGNATURE_IMAGE_HEIGHT;
        const ctx = canvas.getContext('2d');
        const text = this.typedName.trim();
        let size = 110;
        do {
            ctx.font = `${style.italic ? 'italic ' : ''}${size}px ${style.family}`;
            size -= 4;
        } while (ctx.measureText(text).width > canvas.width - 40 && size > 24);
        ctx.fillStyle = INK;
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        ctx.fillText(text, canvas.width / 2, canvas.height / 2);
        return trimToInk(canvas).toDataURL('image/png');
    }

    get toastClass() {
        return `slds-notify slds-notify_toast ${this.toastIsError ? 'slds-theme_error' : 'slds-theme_info'}`;
    }
    get toastIcon() {
        return this.toastIsError ? 'utility:error' : 'utility:info';
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
        this.closeSignatureModal();
    }

    // ---------- submit / decline ----------

    async handleFinalSubmission() {
        if (this.remainingSpots > 0 || !this.adoptedSignature) {
            return;
        }
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
                userAgent: navigator.userAgent
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
                userAgent: navigator.userAgent
            });
            this.showReassignModal = false;
            this.state = 'reassigned';
        } catch (error) {
            this.showToast(reduceError(error));
        } finally {
            this.isWorking = false;
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
            await declineToSign({ rawToken: this.rawToken, reason: this.declineReason, userAgent: navigator.userAgent });
            this.showDeclineModal = false;
            this.state = 'declined';
        } catch (error) {
            this.showToast(reduceError(error));
        } finally {
            this.isWorking = false;
        }
    }
}