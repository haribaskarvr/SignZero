/*
 * The PDF engine for SignZero screens in Lightning Experience (signZeroSignerEditor, signZeroFieldPlacer). The work
 * runs in the signZeroPdfHost page in a hidden iframe, outside Lightning Web Security, as on the signing page; if the
 * page does not answer, the same engine runs in the component. The component renders the iframe at hostUrl.
 */
import { loadScript } from 'lightning/platformResourceLoader';
import PDF_HOST_RESOURCE from '@salesforce/resourceUrl/signZeroPdfHost';
import loadDocument from '@salesforce/apex/SignZeroFieldLayout.loadDocument';

const READY_TIMEOUT_MS = 8000;
const REQUEST_TIMEOUT_MS = { open: 30000, renderPage: 10000 };

function base64ToBytes(base64) {
    const binary = atob(base64);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) {
        bytes[i] = binary.charCodeAt(i);
    }
    return bytes;
}

export default class PdfEngine {
    /** The resource URL carries its deploy version, so no stale copy is served. */
    hostUrl = `${PDF_HOST_RESOURCE}/index.html`;

    /** @param component the LightningElement using the engine, for loadScript */
    constructor(component) {
        this.component = component;
        this.pending = new Map();
        this.requestId = 0;
        this.ready = new Promise((resolve) => {
            this.resolveReady = resolve;
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => resolve(false), READY_TIMEOUT_MS);
        });
        this.boundMessage = (event) => this.handleMessage(event);
        window.addEventListener('message', this.boundMessage);
    }

    stop() {
        window.removeEventListener('message', this.boundMessage);
    }

    /**
     * Loads a PDF from Salesforce Files and opens it.
     * @returns { docId, pages, tagItems } from the engine
     */
    async openDocument(contentDocumentId) {
        this.pdfBytes = base64ToBytes(await loadDocument({ documentId: contentDocumentId }));
        return this.run('open', { pdfBytes: this.pdfBytes.slice() });
    }

    handleMessage(event) {
        const data = event.data;
        if (event.origin !== window.location.origin || !data || !data.signZeroEngine) {
            return;
        }
        if (data.signZeroEngine === 'ready') {
            this.hostWindow = event.source;
            this.resolveReady(true);
        } else if (data.signZeroEngine === 'response' && this.pending.has(data.id)) {
            const { resolve, reject } = this.pending.get(data.id);
            this.pending.delete(data.id);
            if (data.error) {
                reject(new Error(data.error));
            } else {
                resolve(data.result);
            }
        }
    }

    requestFromHost(op, payload) {
        this.requestId += 1;
        const id = this.requestId;
        return new Promise((resolve, reject) => {
            this.pending.set(id, { resolve, reject });
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => {
                if (this.pending.delete(id)) {
                    reject(new Error('no answer'));
                }
            }, REQUEST_TIMEOUT_MS[op]);
            this.hostWindow.postMessage({ signZeroEngine: 'request', id, op, payload }, window.location.origin);
        });
    }

    /** Runs an engine operation in the host page, or in the component when the page is unavailable. */
    async run(op, payload) {
        if (!this.inComponent && (await this.ready)) {
            try {
                return await this.requestFromHost(op, payload);
            } catch (error) {
                // eslint-disable-next-line no-console
                console.warn(`[SignZero] PDF host page failed (${error.message}); continuing in the component`);
                this.inComponent = true;
                if (op === 'renderPage') {
                    // The document was opened in the host page; open it here too.
                    await this.loadInComponent();
                    this.componentDocId = (await window.SignZeroPdfEngine.open({ pdfBytes: this.pdfBytes.slice() })).docId;
                }
            }
        }
        this.inComponent = true;
        await this.loadInComponent();
        const request = op === 'renderPage' && this.componentDocId ? { ...payload, docId: this.componentDocId } : payload;
        const result = await window.SignZeroPdfEngine[op](request);
        if (op === 'open') {
            this.componentDocId = result.docId;
        }
        return result;
    }

    async loadInComponent() {
        if (window.SignZeroPdfEngine) {
            return;
        }
        await loadScript(this.component, PDF_HOST_RESOURCE + '/pdf-lib.min.js');
        await loadScript(this.component, PDF_HOST_RESOURCE + '/pdf.min.js');
        // Loading the worker script in the page avoids a Web Worker, which Lightning Web Security blocks.
        await loadScript(this.component, PDF_HOST_RESOURCE + '/pdf.worker.min.js');
        window.pdfjsLib.GlobalWorkerOptions.workerSrc = PDF_HOST_RESOURCE + '/pdf.worker.min.js';
        await loadScript(this.component, PDF_HOST_RESOURCE + '/engine.js');
    }
}
