import { LightningElement, api, wire } from 'lwc';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';
import RECIPIENT_OBJECT from '@salesforce/schema/SignZero_Recipient__c';
import SIGNER_ROLE_FIELD from '@salesforce/schema/SignZero_Recipient__c.Signer_Role__c';
import { findAnchorTags } from 'c/signZeroAnchorTags';
import PdfEngine from 'c/signZeroPdfEngine';
import title from '@salesforce/label/c.SZ_Signers_Title';
import help from '@salesforce/label/c.SZ_Signers_Help';
import nameLabel from '@salesforce/label/c.SZ_Signers_Name';
import emailLabel from '@salesforce/label/c.SZ_Signers_Email';
import roleLabel from '@salesforce/label/c.SZ_Signers_Role';
import rolePlaceholder from '@salesforce/label/c.SZ_Signers_Role_Placeholder';
import routingOrderLabel from '@salesforce/label/c.SZ_Signers_Order';
import add from '@salesforce/label/c.SZ_Signers_Add';
import remove from '@salesforce/label/c.SZ_Signers_Remove';
import allTagged from '@salesforce/label/c.SZ_Signers_All_Tagged';
import untagged from '@salesforce/label/c.SZ_Signers_Untagged';
import errRoles from '@salesforce/label/c.SZ_Signers_Err_Roles';
import errIncomplete from '@salesforce/label/c.SZ_Signers_Err_Incomplete';
import errEmail from '@salesforce/label/c.SZ_Signers_Err_Email';
import errDuplicate from '@salesforce/label/c.SZ_Signers_Err_Duplicate';
import errOrder from '@salesforce/label/c.SZ_Signers_Err_Order';

const EMAIL = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;
let nextKey = 0;

const LABELS = {
    title,
    help,
    name: nameLabel,
    email: emailLabel,
    role: roleLabel,
    rolePlaceholder,
    routingOrder: routingOrderLabel,
    add,
    remove,
    allTagged,
    untagged,
    errRoles,
    errIncomplete,
    errEmail,
    errDuplicate,
    errOrder
};

/** Fills {0}, {1}, ... placeholders in a label. */
function format(label, ...args) {
    return label.replace(/\{(\d+)\}/g, (match, i) => (args[i] !== undefined ? args[i] : match));
}

function signature(name, email, role, routingOrder) {
    return JSON.stringify([name ?? '', email ?? '', role ?? '', Number(routingOrder) || 0]);
}

/**
 * Flow screen component that collects signers as SignZeroSigner records for the Dispatch Document action. It also
 * reads the PDF's {{sig:Role}} tags, so the flow can skip Place Signatures when every signer already has one.
 */
export default class SignZeroSignerEditor extends LightningElement {
    @api contentDocumentId;

    labels = LABELS;
    helpText = format(LABELS.help, '{{sig:Role}}');
    rows = [this.newRow(1)];
    roleOptions = [];
    errorMessage;
    taggedRoles; // lower-case roles with a tag in the PDF; undefined until read
    engineUrl;

    @wire(getObjectInfo, { objectApiName: RECIPIENT_OBJECT })
    recipientInfo;

    /** From the Signer Role picklist, so senders can only pick roles templates are tagged with. */
    @wire(getPicklistValues, { recordTypeId: '$recipientInfo.data.defaultRecordTypeId', fieldApiName: SIGNER_ROLE_FIELD })
    wiredRoles({ data, error }) {
        if (data) {
            this.roleOptions = data.values.map(({ label, value }) => ({ label, value }));
        } else if (error) {
            this.errorMessage = LABELS.errRoles;
        }
    }

    /** Output to the flow: List<SignZeroSigner>; also restores signers when the user comes back. */
    @api
    get signers() {
        return this.rows.map(({ name, email, role, routingOrder }) => ({
            name,
            email,
            role,
            routingOrder: Number(routingOrder)
        }));
    }
    set signers(value) {
        if (!Array.isArray(value) || !value.length) {
            return;
        }
        // The flow echoes each change back; skip values already on screen so inputs do not re-render mid-typing.
        const incoming = value.map((s) => signature(s.name, s.email, s.role, s.routingOrder));
        const current = this.rows.map((r) => signature(r.name, r.email, r.role, r.routingOrder));
        if (incoming.join('\n') === current.join('\n')) {
            return;
        }
        // Keep row keys so LWC updates the inputs instead of replacing them.
        this.rows = value.map((s, i) => ({
            ...this.newRow(s.routingOrder, s.role ?? '', s.name ?? '', s.email ?? ''),
            ...(this.rows[i] ? { key: this.rows[i].key } : {})
        }));
    }

    /** Output to the flow: true when every signer's role has a tag in the PDF; false until the tags are read. */
    @api
    get allRolesTagged() {
        return Boolean(this.taggedRoles) && this.rows.every((r) => r.role && this.taggedRoles.has(r.role.toLowerCase()));
    }

    get tagNotice() {
        if (!this.taggedRoles || this.taggedRoles.size === 0 || this.rows.every((r) => !r.role)) {
            return null;
        }
        if (this.allRolesTagged) {
            return LABELS.allTagged;
        }
        const untagged = [...new Set(this.rows.filter((r) => r.role && !this.taggedRoles.has(r.role.toLowerCase())).map((r) => r.role))];
        return untagged.length
            ? format(LABELS.untagged, untagged.join(', '))
            : null;
    }

    connectedCallback() {
        if (this.contentDocumentId) {
            this.readTags();
        }
    }

    disconnectedCallback() {
        if (this.engine) {
            this.engine.stop();
        }
    }

    /** Reads the PDF's tags while the sender adds signers. If this fails, Place Signatures is shown. */
    async readTags() {
        try {
            this.engine = new PdfEngine(this);
            this.engineUrl = this.engine.hostUrl;
            const opened = await this.engine.openDocument(this.contentDocumentId);
            this.taggedRoles = new Set(findAnchorTags(opened.tagItems).map((tag) => tag.role.toLowerCase()));
            this.publish();
        } catch (error) {
            // eslint-disable-next-line no-console
            console.warn(`[SignZero] Signature tags could not be read: ${error.message || error.body?.message}`);
        } finally {
            this.engine.stop();
            this.engineUrl = null;
        }
    }

    get isSingleRow() {
        return this.rows.length === 1;
    }

    newRow(routingOrder, role = '', name = '', email = '') {
        nextKey += 1;
        return { key: `signer-${nextKey}`, name, email, role, routingOrder };
    }

    addRow() {
        const lastOrder = Math.max(...this.rows.map((r) => Number(r.routingOrder) || 1));
        this.rows = [...this.rows, this.newRow(lastOrder + 1)];
        this.publish();
    }

    removeRow(event) {
        const index = Number(event.currentTarget.dataset.index);
        this.rows = this.rows.filter((row, i) => i !== index);
        this.publish();
    }

    handleChange(event) {
        const { index, field } = event.target.dataset;
        const rows = [...this.rows];
        rows[Number(index)] = { ...rows[Number(index)], [field]: event.target.value };
        this.rows = rows;
        this.errorMessage = null;
        this.publish();
    }

    publish() {
        this.dispatchEvent(new FlowAttributeChangeEvent('signers', this.signers));
        this.dispatchEvent(new FlowAttributeChangeEvent('allRolesTagged', this.allRolesTagged));
    }

    /** Called by the flow before it moves on. */
    @api
    validate() {
        const inputs = [...this.template.querySelectorAll('lightning-input, lightning-combobox')];
        const fieldsValid = inputs.reduce((ok, input) => input.reportValidity() && ok, true);
        const emails = this.rows.map((r) => (r.email || '').trim().toLowerCase());
        let message;
        if (!fieldsValid) {
            message = LABELS.errIncomplete;
        } else if (emails.some((e) => !EMAIL.test(e))) {
            message = LABELS.errEmail;
        } else if (new Set(emails).size !== emails.length) {
            message = LABELS.errDuplicate;
        } else if (this.rows.some((r) => !(Number(r.routingOrder) >= 1))) {
            message = LABELS.errOrder;
        }
        this.errorMessage = message;
        return message ? { isValid: false, errorMessage: message } : { isValid: true };
    }
}
