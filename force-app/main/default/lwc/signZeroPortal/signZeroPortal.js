import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { loadScript } from 'lightning/platformResourceLoader';
import PDF_HOST_RESOURCE from '@salesforce/resourceUrl/signZeroPdfHost';
import initializeSession from '@salesforce/apex/SignZeroGatewayController.initializeSession';
import recordConsent from '@salesforce/apex/SignZeroGatewayController.recordConsent';
import submitExecutedDocument from '@salesforce/apex/SignZeroGatewayController.submitExecutedDocument';
import declineToSign from '@salesforce/apex/SignZeroGatewayController.declineToSign';
import reassign from '@salesforce/apex/SignZeroGatewayController.reassign';

// Signer-facing text lives in Custom Labels (category SignZero) so admins can reword and translate it.
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
 * PDF work (opening, drawing pages, stamping) runs in the SignZero PDF host: index.html of the signZeroPdfHost
 * static resource, loaded in a hidden iframe on the same site, outside Lightning Web Security, where PDF.js has its
 * Web Worker and canvas runs at full speed. If the host does not answer in time, the same engine files are loaded
 * into this component instead (slower, same result).
 */
const PDF_HOST_NAME = 'signZeroPdfHost';
const ENGINE_READY_TIMEOUT_MS = 8000;
// Opening reads every page of the document; drawing handles one page.
const ENGINE_REQUEST_TIMEOUT_MS = { open: 30000, renderPage: 10000, stamp: 20000, refreshPlainCopy: 30000 };

const INK = '#0b1f4d';
const SIGNATURE_IMAGE_WIDTH = 640;
const SIGNATURE_IMAGE_HEIGHT = 200;
const MAX_UPLOAD_BYTES = 1024 * 1024;

// Handwriting-style fonts found on most devices, with generic fallbacks; nothing is downloaded.
const TYPED_STYLES = [
    { family: "'Segoe Script', 'Brush Script MT', 'Snell Roundhand', cursive", italic: false },
    { family: "'Lucida Handwriting', 'Bradley Hand', 'Segoe Print', cursive", italic: false },
    { family: "Georgia, 'Times New Roman', serif", italic: true }
];

// Signature size in PDF points. The "Signed electronically by" caption goes just under the signature.
const SIG_WIDTH = 150;
const SIG_HEIGHT = 30;
const MIN_SIG_HEIGHT = 16;
const MAX_SIG_HEIGHT = 80;

/**
 * Where a signature goes relative to its tag. Template authors choose with options after the role:
 *   {{sig:Customer}}          the signature sits on the tag's line (the usual "sign here ____" case)
 *   {{sig:Customer|below}}    it hangs down from the tag, into empty space such as a blank table cell
 *   {{sig:Customer|h=40}}     signature height in points (16-80), combinable: {{sig:Customer|below|h=40}}
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

// Switched on by the Performance Logs checkbox on the SignZero Diagnostics custom setting.
let performanceLogs = false;

/** Step timings in the browser console, for diagnosing slow signing sessions. */
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

export default class SignZeroPortal extends LightningElement {
    labels = LABELS;
    rawToken;
    state = 'loading'; // loading | error | signing | submitting | done | declined
    loadingMessage = LABELS.loadingSession;
    isFinalSigner = false;
    errorMessage;
    toastMessage;
    isWorking = false;

    documentName = 'Agreement';
    envelopeNumber;
    recipientName = '';
    signerRole = 'Customer';
    consentAccepted = false;
    showSignatureModal = false;
    showDeclineModal = false;
    declineReason = '';

    // Experience Builder properties. When set they win over SignZero_Setting__mdt, which wins over the site theme.
    @api primaryColor;
    @api primaryHoverColor;
    @api accentColor;
    @api logoUrl;
    @api companyName;

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
    openedDoc; // from the engine: { docId, pages: [{ width, height, transform, view }], tagItems }
    pageImageUrls = []; // object URLs of the drawn pages, released on redraw
    drawGeneration = 0; // bumped by every redraw, so an older drawing pass stops
    engineInComponent = false; // the host page failed, so the engine runs inside this component from now on
    readOnly = false; // reopened after signing: view only
    envelopeStatus;
    signedAt;
    isLastSigner = false;
    allowReassign = false;
    showReassignModal = false;
    reassignTo = { name: '', email: '', reason: '' };
    tagRects = []; // every anchor tag found, any role: { pageIndex, rect }
    signatureMode = 'type'; // type | draw | upload
    typedName = '';
    typedStyle = 0;
    uploadedSignature; // PNG data URL
    uploadError;
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
        // Fallback for containers that never provide a page reference.
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
        return this.isSigning && !this.consentAccepted && !this.showDeclineModal && !this.showReassignModal;
    }
    get showGuide() {
        return this.isSigning && this.consentAccepted;
    }

    get branding() {
        const org = this.sessionBranding;
        return {
            logoUrl: this.logoUrl || org.logoUrl,
            companyName: this.companyName || org.companyName,
            primaryColor: this.primaryColor || org.primaryColor,
            primaryHoverColor: this.primaryHoverColor || org.primaryHoverColor,
            accentColor: this.accentColor || org.accentColor
        };
    }

    // Only emit overrides that are configured, so the site theme shows through for the rest.
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
        return this.consentAccepted ? 'document-container' : 'document-container document-blurred';
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

    // The last signer completes the envelope, so they get a "complete" message rather than "waiting on others".
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
            // The host page loads while Salesforce prepares the session; neither waits for the other.
            this.startPdfEngine();
            const session = await initializeSession({ rawToken: this.rawToken, userAgent: navigator.userAgent });
            this.applySession(session);
            timing('session loaded', loadStarted);
            this.confirmEngineVersion(session.pdfHostVersion);
            this.loadingMessage = LABELS.loadingDocument;
            this.state = this.readOnly ? 'viewing' : 'signing';
            // Let the template show the document area before measuring and drawing into it. Browsers hold back
            // animation frames for pages they treat as in the background (seen at 8-22 s), so don't wait past 100 ms.
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
            // Pages and signing spots are in place; page images keep arriving in the background.
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
        this.pdfBytes = base64ToBytes(res.pdfBase64);
        this.sessionBranding = res.branding || {};
    }

    fail(message) {
        this.errorMessage = message;
        this.state = 'error';
    }

    showToast(message) {
        // The sender recalled the envelope while it was open: leave the document for the recalled notice.
        if (message === LABELS.errRecalled) {
            this.fail(message);
            return;
        }
        this.toastMessage = message;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            this.toastMessage = null;
        }, 5000);
    }

    // ---------- consent ----------

    async handleAcceptConsent() {
        this.isWorking = true;
        try {
            await recordConsent({ rawToken: this.rawToken, userAgent: navigator.userAgent });
            this.consentAccepted = true;
        } catch (error) {
            this.showToast(reduceError(error));
        } finally {
            this.isWorking = false;
        }
    }

    // ---------- rendering & tag detection ----------

    /**
     * Lays out every page at its final size with its signing spots, then draws the page images in the background,
     * so the signer can read page 1 and start signing before the rest are drawn.
     */
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
            wrapper.className = 'page-container';
            wrapper.dataset.scale = String(scales[pageIndex]);
            wrapper.style.width = `${page.width * scales[pageIndex]}px`;
            wrapper.style.height = `${page.height * scales[pageIndex]}px`;
            container.appendChild(wrapper);
        });
        this.pageCount = pages.length;
        this.renderedScale = scales[0];

        // Redrawing (after a resize or zoom) keeps the signatures already applied.
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

    /** Every anchor tag, whatever its role, is remembered (stamping covers them); this signer's become signing spots. */
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
            // No {{sig:role}} tag for this signer: offer one spot at the bottom right of the last page.
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
            this.showToast(LABELS.noTagsNotice);
        }
        this.tagRects = tagRects;
        this.signatureLocations = locations;
    }

    /** Draws the page images one by one, starting with the page in view. A newer redraw stops this pass. */
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
                // Draw at device resolution so text stays sharp on high-density screens.
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

    /** Space the pages can use inside the scrolling area, in CSS pixels. */
    viewerArea() {
        const viewportEl = this.template.querySelector('.pdf-scroll-viewport');
        const width = (viewportEl && viewportEl.clientWidth) || window.innerWidth;
        const height = (viewportEl && viewportEl.clientHeight) || window.innerHeight;
        return { width: Math.max(240, width - VIEWER_PADDING * 2), height: Math.max(240, height - VIEWER_PADDING * 2) };
    }

    /** PDF points to CSS pixels for one page, by zoom mode. Each page is fitted on its own (landscape pages too). */
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
    get fitPageClass() {
        return this.zoomMode === 'page' ? 'tool-button active' : 'tool-button';
    }
    get fitWidthClass() {
        return this.zoomMode === 'width' ? 'tool-button active' : 'tool-button';
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

    /** The current page is the last one whose top has scrolled into the upper third of the viewer. */
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

    /**
     * Fit-to modes depend on the viewer's size, which changes: the site's layout can still be settling when
     * the document first draws, and signers resize windows or rotate phones. Redraw when it really changes.
     */
    watchWidth() {
        if (this.resizeObserver) {
            return;
        }
        const viewportEl = this.template.querySelector('.pdf-scroll-viewport');
        this.resizeObserver = new ResizeObserver(() => this.scheduleWidthCheck());
        this.resizeObserver.observe(viewportEl);
        viewportEl.addEventListener('scroll', () => this.handleViewerScroll(), { passive: true });
        // The layout may have settled while the first pages were drawing.
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

    /**
     * The site adds space above the component, so a 100vh portal would run below the fold and "fit page"
     * would cut off the bottom of the page. Size the portal to the window height that is left instead.
     */
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

    /** Loads the PDF host page in a hidden iframe on this site, at its plain address. */
    startPdfEngine() {
        this.enginePending = new Map();
        this.engineReady = new Promise((resolve) => {
            this.resolveEngineReady = resolve;
        });
        this.boundEngineMessage = (event) => this.handleEngineMessage(event);
        window.addEventListener('message', this.boundEngineMessage);
        this.loadEnginePage(`/${PDF_HOST_NAME}/index.html`);
    }

    /** @param path the host page under the site's resource path, with or without a version */
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
     * The plain address can be served from a browser cache filled before the last deploy (the site lets browsers
     * keep it for weeks). Once both the host's version and the current one from Salesforce are known, a stale host
     * is reloaded once at the address with the version in it, which is never stale.
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
            // A late announcement from the stale copy after the reload is ignored; the timeout covers the rest.
            if (!this.reloadedEngine) {
                this.reloadedEngine = true;
                this.loadEnginePage(`/${this.currentHostVersion}/${PDF_HOST_NAME}/index.html`);
            }
            return;
        }
        this.resolveEngineReady(true);
    }

    /**
     * After a stale host was replaced, the current host refreshes the browser's cached copies at the plain address,
     * so the next visit needs no reload. Runs once the pages are drawn, so it never competes with them.
     */
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

    /** One request to the host page; rejects if it does not answer in time, so a stuck page cannot hang signing. */
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

    /** Runs a PDF engine operation in the host page, or in this component if the page is not available. */
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
                    // The document was opened in the host page; open it here as well.
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
        // Loading the worker script in the page lets PDF.js run without spawning a Web Worker,
        // which Lightning Web Security does not allow.
        await loadScript(this, PDF_HOST_RESOURCE + '/pdf.worker.min.js');
        window.pdfjsLib.GlobalWorkerOptions.workerSrc = PDF_HOST_RESOURCE + '/pdf.worker.min.js';
        await loadScript(this, PDF_HOST_RESOURCE + '/engine.js');
    }

    /** @param page page size and PDF-to-screen transform at scale 1, from the engine */
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
        const pending = this.signatureLocations.filter((loc) => !loc.signed);
        if (pending.length === 0) {
            this.handleFinalSubmission();
            return;
        }
        // guidedIndex is a position in document order, so signing a spot never shifts where "next" lands.
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
        if (!this.consentAccepted || this.isSubmitting) {
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
            img.src = this.adoptedSignature;
            img.alt = `Signature of ${this.recipientName}`;
            element.appendChild(img);
            element.classList.add('signed');
            element.setAttribute('aria-label', 'Signed');
        }
        // Reassign so getters that count remaining spots re-render.
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
    get modeTabs() {
        return [
            { id: 'type', label: LABELS.tabType },
            { id: 'draw', label: LABELS.tabDraw },
            { id: 'upload', label: LABELS.tabUpload }
        ].map((tab) => ({
            ...tab,
            selected: tab.id === this.signatureMode,
            className: tab.id === this.signatureMode ? 'mode-tab active' : 'mode-tab'
        }));
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
        // Like most e-signature services, start on a typed signature with the signer's name filled in.
        this.signatureMode = 'type';
        this.typedName = this.typedName || this.recipientName;
        this.uploadError = null;
        this.showSignatureModal = true;
    }

    handleModeChange(event) {
        this.signatureMode = event.currentTarget.dataset.mode;
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

    /** Typed signature: the name in the chosen handwriting-style font, rendered to a PNG. */
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
        return canvas.toDataURL('image/png');
    }

    /** Uploaded signature: scaled to fit, with a white or near-white background made transparent. */
    handleUpload(event) {
        const file = event.target.files && event.target.files[0];
        this.uploadError = null;
        this.uploadedSignature = null;
        if (!file || !['image/png', 'image/jpeg'].includes(file.type) || file.size > MAX_UPLOAD_BYTES) {
            this.uploadError = LABELS.uploadInvalid;
            return;
        }
        const reader = new FileReader();
        reader.onload = () => {
            const img = new Image();
            img.onload = () => {
                const canvas = document.createElement('canvas');
                canvas.width = SIGNATURE_IMAGE_WIDTH;
                canvas.height = SIGNATURE_IMAGE_HEIGHT;
                const ctx = canvas.getContext('2d');
                const scale = Math.min(canvas.width / img.width, canvas.height / img.height, 1);
                const w = img.width * scale;
                const h = img.height * scale;
                ctx.drawImage(img, (canvas.width - w) / 2, (canvas.height - h) / 2, w, h);
                const pixels = ctx.getImageData(0, 0, canvas.width, canvas.height);
                for (let i = 0; i < pixels.data.length; i += 4) {
                    if (pixels.data[i] > 235 && pixels.data[i + 1] > 235 && pixels.data[i + 2] > 235) {
                        pixels.data[i + 3] = 0;
                    }
                }
                ctx.putImageData(pixels, 0, 0);
                this.uploadedSignature = canvas.toDataURL('image/png');
            };
            img.onerror = () => {
                this.uploadError = LABELS.uploadInvalid;
            };
            img.src = reader.result;
        };
        reader.readAsDataURL(file);
    }

    confirmSignaturePlacement() {
        if (this.adoptDisabled) {
            return;
        }
        if (this.isDrawMode) {
            this.adoptedSignature = this.template.querySelector('.sig-pad').toDataURL('image/png');
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
                // An uploaded image stays in the browser: it reaches Salesforce only inside the signed PDF.
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

    /** Writes the adopted signature into the PDF itself (in the PDF engine) and returns it as base64. */
    async stampSignatures() {
        const signedAt = new Date().toISOString().replace('T', ' ').substring(0, 19) + ' UTC';
        const stamped = await this.runPdfEngine('stamp', {
            pdfBytes: this.pdfBytes.slice(),
            pngBytes: base64ToBytes(this.adoptedSignature.split(',')[1]),
            spots: this.signatureLocations.map(({ pageIndex, pdfX, pdfY, height }) => ({ pageIndex, pdfX, pdfY, height })),
            tagRects: this.tagRects.map(({ pageIndex, rect }) => ({ pageIndex, rect: { ...rect } })),
            signerRole: this.signerRole,
            // The last signer also clears tags left for roles nobody signed as.
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