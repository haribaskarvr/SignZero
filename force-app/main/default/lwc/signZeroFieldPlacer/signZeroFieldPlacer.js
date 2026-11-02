import { LightningElement, api } from 'lwc';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';
import title from '@salesforce/label/c.SZ_Placer_Title';
import help from '@salesforce/label/c.SZ_Placer_Help';
import helpPlacing from '@salesforce/label/c.SZ_Placer_Help_Placing';
import noPlaces from '@salesforce/label/c.SZ_Placer_No_Places';
import onePlace from '@salesforce/label/c.SZ_Placer_One_Place';
import places from '@salesforce/label/c.SZ_Placer_Places';
import page from '@salesforce/label/c.SZ_Placer_Page';
import pageOf from '@salesforce/label/c.SZ_Page_Of';
import signers from '@salesforce/label/c.SZ_Signers_Title';
import noSigners from '@salesforce/label/c.SZ_Placer_No_Signers';
import reset from '@salesforce/label/c.SZ_Placer_Reset';
import loadingDocument from '@salesforce/label/c.SZ_Loading_Document';
import drawingPage from '@salesforce/label/c.SZ_Placer_Drawing_Page';
import remove from '@salesforce/label/c.SZ_Placer_Remove';
import place from '@salesforce/label/c.SZ_Placer_Place';
import noDocument from '@salesforce/label/c.SZ_Placer_Err_No_Document';
import loadError from '@salesforce/label/c.SZ_Placer_Err_Load';
import { SIG_WIDTH, SIG_HEIGHT, findAnchorTags } from 'c/signZeroAnchorTags';
import PdfEngine from 'c/signZeroPdfEngine';

// Sharp enough on high-density screens without drawing huge images.
const MAX_RENDER_SCALE = 3;
const LABELS = {
    title,
    help,
    helpPlacing,
    noPlaces,
    onePlace,
    places,
    page,
    pageOf,
    signers,
    noSigners,
    reset,
    loadingDocument,
    drawingPage,
    remove,
    place,
    noDocument,
    loadError
};

/** Fills {0}, {1}, ... placeholders in a label. */
function format(label, ...args) {
    return label.replace(/\{(\d+)\}/g, (match, i) => (args[i] !== undefined ? args[i] : match));
}

// Pointer travel that turns a press into a drag.
const DRAG_THRESHOLD_PX = 4;
const ROLE_COLORS = ['#0176d3', '#2e844a', '#9050e9', '#dd7a01', '#ba0517', '#0b827c', '#3e3e3c'];
let nextKey = 0;

function blobToDataUrl(blob) {
    return new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = () => resolve(reader.result);
        reader.onerror = () => reject(reader.error);
        reader.readAsDataURL(blob);
    });
}

function reduceError(error) {
    return (error && error.body && error.body.message) || (error && error.message) || '';
}

/** PDF point to page position at scale 1 (handles rotated pages). */
function toView(page, x, y) {
    const [a, b, c, d, e, f] = page.transform;
    return [a * x + c * y + e, b * x + d * y + f];
}

/** Page position at scale 1 back to a PDF point. */
function toPdf(page, u, v) {
    const [a, b, c, d, e, f] = page.transform;
    const det = a * d - b * c;
    return [(d * (u - e) - c * (v - f)) / det, (-b * (u - e) + a * (v - f)) / det];
}

/**
 * Flow screen component where the sender places each signer role's signatures on the PDF. The document's
 * {{sig:Role}} tags start out placed. Output fieldLayout is JSON for the Dispatch Document action, or blank when the
 * sender changed nothing, so the tags are used as they are.
 */
export default class SignZeroFieldPlacer extends LightningElement {
    @api contentDocumentId;
    @api signers;

    labels = LABELS;

    isLoading = true;
    errorMessage;
    engineUrl;
    pages = []; // [{ width, height, transform, view }] at scale 1, from the engine
    pageImages = {}; // page index to data URL
    fields = []; // [{ key, role, page, x, y, height }] in PDF points; x, y = bottom left
    changed = false;
    armedRole; // a role picked without dragging; the next click on a page places it
    selectedKey;
    ghost; // { role, left, top, width, height } while a new place is dragged from the list
    restoredLayout;

    /** In and out: the layout, so going back to this screen keeps the places. */
    @api
    get fieldLayout() {
        return this.changed
            ? JSON.stringify(this.fields.map(({ role, page, x, y, height }) => ({ role, page, x, y, height })))
            : '';
    }
    set fieldLayout(value) {
        this.restoredLayout = value;
    }

    connectedCallback() {
        this.load();
    }

    disconnectedCallback() {
        if (this.engine) {
            this.engine.stop();
        }
        this.stopDragListeners();
    }

    // ---------- view state ----------

    /** One entry per role on the signers screen, in signer order. */
    get roles() {
        const seen = new Map();
        (this.signers || []).forEach((signer) => {
            const role = signer && signer.role;
            if (!role) {
                return;
            }
            const key = role.toLowerCase();
            if (!seen.has(key)) {
                seen.set(key, { role, names: [] });
            }
            if (signer.name) {
                seen.get(key).names.push(signer.name);
            }
        });
        return [...seen.values()].map((entry, index) => ({ ...entry, color: ROLE_COLORS[index % ROLE_COLORS.length] }));
    }

    get roleItems() {
        return this.roles.map(({ role, names, color }) => {
            const count = this.fields.filter((f) => f.role === role).length;
            const armed = this.armedRole === role;
            return {
                role,
                names: names.join(', '),
                countText: count === 0 ? LABELS.noPlaces : count === 1 ? LABELS.onePlace : format(LABELS.places, count),
                className: `role-chip slds-box slds-box_x-small slds-m-bottom_x-small${armed ? ' armed' : ''}`,
                style: `--role-color: ${color};`,
                pressed: String(armed)
            };
        });
    }

    get hasRoles() {
        return this.roles.length > 0;
    }

    get showViewer() {
        return !this.isLoading && !this.errorMessage && this.pages.length > 0;
    }

    get viewerClass() {
        return this.armedRole ? 'viewer placing' : 'viewer';
    }

    get canNotReset() {
        return !this.changed;
    }

    get hint() {
        return this.armedRole
            ? format(LABELS.helpPlacing, this.armedRole)
            : LABELS.help;
    }

    get pageItems() {
        const colors = new Map(this.roles.map(({ role, color }) => [role, color]));
        return this.pages.map((page, index) => ({
            index,
            key: `page-${index}`,
            style: `aspect-ratio: ${page.width} / ${page.height};`,
            imageUrl: this.pageImages[index],
            alt: format(LABELS.pageOf, index + 1, this.pages.length),
            label: format(LABELS.page, index + 1),
            boxes: this.fields
                .filter((f) => f.page === index)
                .map((f) => ({
                    key: f.key,
                    role: f.role,
                    className: `field-box${f.key === this.selectedKey ? ' selected' : ''}`,
                    style: `${this.boxPosition(page, f)} --role-color: ${colors.get(f.role) || ROLE_COLORS[0]};`,
                    ariaLabel: format(LABELS.place, f.role, index + 1)
                }))
        }));
    }

    /** Position as percentages of the page, so the boxes follow the page at any width. */
    boxPosition(page, field) {
        const [u1, v1] = toView(page, field.x, field.y);
        const [u2, v2] = toView(page, field.x + SIG_WIDTH, field.y + field.height);
        const left = (Math.min(u1, u2) / page.width) * 100;
        const top = (Math.min(v1, v2) / page.height) * 100;
        const width = (Math.abs(u2 - u1) / page.width) * 100;
        const height = (Math.abs(v2 - v1) / page.height) * 100;
        return `left: ${left}%; top: ${top}%; width: ${width}%; height: ${height}%;`;
    }

    // ---------- loading ----------

    async load() {
        try {
            if (!this.contentDocumentId) {
                throw new Error(LABELS.noDocument);
            }
            this.engine = new PdfEngine(this);
            this.engineUrl = this.engine.hostUrl;
            const opened = await this.engine.openDocument(this.contentDocumentId);
            this.docId = opened.docId;
            this.pages = opened.pages;
            this.anchorTags = findAnchorTags(opened.tagItems);
            this.fields = this.initialFields(this.anchorTags);
            this.isLoading = false;
            // Let the pages lay out, then draw them at their shown width.
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            requestAnimationFrame(() => this.drawPages());
        } catch (error) {
            const detail = reduceError(error);
            this.errorMessage = detail ? `${LABELS.loadError} (${detail})` : LABELS.loadError;
            this.isLoading = false;
        }
    }

    /** The places from coming back to this screen, else this envelope's roles' tags. */
    initialFields(tags) {
        const roles = new Map(this.roles.map(({ role }) => [role.toLowerCase(), role]));
        if (this.restoredLayout) {
            try {
                const restored = JSON.parse(this.restoredLayout)
                    .filter((p) => roles.has(String(p.role).toLowerCase()) && p.page < this.pages.length)
                    .map((p) => this.newField(roles.get(p.role.toLowerCase()), p.page, p.x, p.y, p.height));
                this.changed = true;
                this.publish();
                return restored;
            } catch (error) {
                // An unreadable layout starts again from the tags.
            }
        }
        return tags
            .filter((tag) => roles.has(tag.role.toLowerCase()))
            .map((tag) => this.newField(roles.get(tag.role.toLowerCase()), tag.pageIndex, tag.pdfX, tag.pdfY, tag.height));
    }

    newField(role, page, x, y, height) {
        nextKey += 1;
        return { key: `field-${nextKey}`, role, page, x, y, height: height || SIG_HEIGHT };
    }

    async drawPages() {
        const pageEls = this.template.querySelectorAll('.page');
        const ratio = window.devicePixelRatio || 1;
        try {
            for (let index = 0; index < this.pages.length; index++) {
                const shownWidth = (pageEls[index] && pageEls[index].clientWidth) || 600;
                const scale = Math.min(MAX_RENDER_SCALE, (shownWidth / this.pages[index].width) * ratio);
                // eslint-disable-next-line no-await-in-loop
                const { image } = await this.engine.run('renderPage', { docId: this.docId, pageIndex: index, scale });
                // eslint-disable-next-line no-await-in-loop
                const url = await blobToDataUrl(image);
                this.pageImages = { ...this.pageImages, [index]: url };
            }
        } catch (error) {
            this.errorMessage = `${LABELS.loadError} (${reduceError(error)})`;
        }
    }

    // ---------- placing, moving and removing ----------

    publish() {
        this.dispatchEvent(new FlowAttributeChangeEvent('fieldLayout', this.fieldLayout));
    }

    setFields(fields) {
        this.fields = fields;
        this.changed = true;
        this.publish();
    }

    /** The page under a screen point, with its on-screen box. */
    pageAt(clientX, clientY) {
        const pageEls = this.template.querySelectorAll('.page');
        for (let index = 0; index < pageEls.length; index++) {
            const rect = pageEls[index].getBoundingClientRect();
            if (clientX >= rect.left && clientX <= rect.right && clientY >= rect.top && clientY <= rect.bottom) {
                return { index, rect };
            }
        }
        return null;
    }

    /** A field of this height centred on a screen point, kept inside the page. */
    positionAt(hit, clientX, clientY, height) {
        const page = this.pages[hit.index];
        const u = ((clientX - hit.rect.left) / hit.rect.width) * page.width;
        const v = ((clientY - hit.rect.top) / hit.rect.height) * page.height;
        const [cx, cy] = toPdf(page, u, v);
        const [x0, y0, x1, y1] = page.view;
        return {
            page: hit.index,
            x: Math.round(Math.min(Math.max(cx - SIG_WIDTH / 2, x0), x1 - SIG_WIDTH) * 100) / 100,
            y: Math.round(Math.min(Math.max(cy - height / 2, y0), y1 - height) * 100) / 100
        };
    }

    addFieldAt(role, hit, clientX, clientY) {
        const { page, x, y } = this.positionAt(hit, clientX, clientY, SIG_HEIGHT);
        const field = this.newField(role, page, x, y, SIG_HEIGHT);
        this.selectedKey = field.key;
        this.setFields([...this.fields, field]);
    }

    handleRolePointerDown(event) {
        if (event.button !== 0) {
            return;
        }
        event.preventDefault();
        this.startDrag(event, { kind: 'new', role: event.currentTarget.dataset.role });
    }

    handleRoleKeyDown(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            const role = event.currentTarget.dataset.role;
            this.armedRole = this.armedRole === role ? null : role;
        }
    }

    handleFieldPointerDown(event) {
        if (event.button !== 0) {
            return;
        }
        event.preventDefault();
        event.stopPropagation();
        const key = event.currentTarget.dataset.key;
        const rect = event.currentTarget.getBoundingClientRect();
        this.selectedKey = key;
        this.armedRole = null;
        event.currentTarget.focus();
        // Where the box was grabbed, from its centre, so it does not jump under the pointer.
        this.startDrag(event, {
            kind: 'move',
            key,
            offsetX: event.clientX - (rect.left + rect.width / 2),
            offsetY: event.clientY - (rect.top + rect.height / 2)
        });
    }

    startDrag(event, drag) {
        this.drag = { ...drag, startX: event.clientX, startY: event.clientY, moved: false };
        this.boundPointerMove = (e) => this.handlePointerMove(e);
        this.boundPointerUp = (e) => this.handlePointerUp(e);
        window.addEventListener('pointermove', this.boundPointerMove);
        window.addEventListener('pointerup', this.boundPointerUp);
        window.addEventListener('pointercancel', this.boundPointerUp);
    }

    stopDragListeners() {
        if (this.boundPointerMove) {
            window.removeEventListener('pointermove', this.boundPointerMove);
            window.removeEventListener('pointerup', this.boundPointerUp);
            window.removeEventListener('pointercancel', this.boundPointerUp);
        }
    }

    handlePointerMove(event) {
        const drag = this.drag;
        if (!drag) {
            return;
        }
        if (!drag.moved && Math.hypot(event.clientX - drag.startX, event.clientY - drag.startY) < DRAG_THRESHOLD_PX) {
            return;
        }
        drag.moved = true;
        if (drag.kind === 'new') {
            // Shown at the size it will have on the page under the pointer.
            const hit = this.pageAt(event.clientX, event.clientY);
            const pxPerPt = hit ? hit.rect.width / this.pages[hit.index].width : 1;
            const width = SIG_WIDTH * pxPerPt;
            const height = SIG_HEIGHT * pxPerPt;
            // Relative to this component: in a flow modal, a transformed ancestor makes position: fixed land elsewhere.
            const root = this.template.querySelector('.placer-root').getBoundingClientRect();
            this.ghost = {
                role: drag.role,
                style: `left: ${event.clientX - root.left - width / 2}px; top: ${event.clientY - root.top - height / 2}px; width: ${width}px; height: ${height}px; --role-color: ${this.colorOf(drag.role)};`
            };
            return;
        }
        const hit = this.pageAt(event.clientX - drag.offsetX, event.clientY - drag.offsetY);
        if (!hit) {
            return;
        }
        this.fields = this.fields.map((f) =>
            f.key === drag.key ? { ...f, ...this.positionAt(hit, event.clientX - drag.offsetX, event.clientY - drag.offsetY, f.height) } : f
        );
    }

    handlePointerUp(event) {
        const drag = this.drag;
        this.drag = null;
        this.ghost = null;
        this.stopDragListeners();
        if (!drag) {
            return;
        }
        // The click that may follow a drag must not place another field; none follows a drag between elements.
        this.suppressClick = drag.moved;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            this.suppressClick = false;
        }, 0);
        if (drag.kind === 'new') {
            if (!drag.moved) {
                this.armedRole = this.armedRole === drag.role ? null : drag.role;
                return;
            }
            const hit = this.pageAt(event.clientX, event.clientY);
            if (hit) {
                this.armedRole = null;
                this.addFieldAt(drag.role, hit, event.clientX, event.clientY);
            }
        } else if (drag.moved) {
            this.setFields([...this.fields]);
        }
    }

    handlePageClick(event) {
        if (this.suppressClick) {
            return;
        }
        if (!this.armedRole) {
            this.selectedKey = null;
            return;
        }
        const hit = this.pageAt(event.clientX, event.clientY);
        if (hit) {
            const role = this.armedRole;
            this.armedRole = null;
            this.addFieldAt(role, hit, event.clientX, event.clientY);
        }
    }

    handleViewerKeyDown(event) {
        if (event.key === 'Escape' && this.armedRole) {
            this.armedRole = null;
        }
    }

    handleFieldKeyDown(event) {
        const key = event.currentTarget.dataset.key;
        if (event.key === 'Delete' || event.key === 'Backspace') {
            event.preventDefault();
            this.removeField(key);
            return;
        }
        const step = event.shiftKey ? 10 : 2;
        const moves = { ArrowLeft: [-step, 0], ArrowRight: [step, 0], ArrowUp: [0, step], ArrowDown: [0, -step] };
        if (!moves[event.key]) {
            return;
        }
        event.preventDefault();
        const [dx, dy] = moves[event.key];
        this.setFields(
            this.fields.map((f) => {
                if (f.key !== key) {
                    return f;
                }
                const [x0, y0, x1, y1] = this.pages[f.page].view;
                return {
                    ...f,
                    x: Math.min(Math.max(f.x + dx, x0), x1 - SIG_WIDTH),
                    y: Math.min(Math.max(f.y + dy, y0), y1 - f.height)
                };
            })
        );
    }

    handleFieldFocus(event) {
        this.selectedKey = event.currentTarget.dataset.key;
    }

    stopEvent(event) {
        event.stopPropagation();
    }

    handleRemoveClick(event) {
        event.stopPropagation();
        this.removeField(event.currentTarget.dataset.key);
    }

    removeField(key) {
        if (this.selectedKey === key) {
            this.selectedKey = null;
        }
        this.setFields(this.fields.filter((f) => f.key !== key));
    }

    /** Back to the document's tags; the layout output is cleared so the tags are used as they are. */
    handleReset() {
        this.restoredLayout = null;
        this.selectedKey = null;
        this.armedRole = null;
        this.fields = this.initialFields(this.anchorTags);
        this.changed = false;
        this.publish();
    }

    colorOf(role) {
        const entry = this.roles.find((r) => r.role === role);
        return entry ? entry.color : ROLE_COLORS[0];
    }
}
