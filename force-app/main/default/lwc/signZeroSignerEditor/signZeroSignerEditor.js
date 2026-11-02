import { LightningElement, api, wire } from 'lwc';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';
import RECIPIENT_OBJECT from '@salesforce/schema/SignZero_Recipient__c';
import SIGNER_ROLE_FIELD from '@salesforce/schema/SignZero_Recipient__c.Signer_Role__c';

const EMAIL = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;
let nextKey = 0;

function signature(name, email, role, routingOrder) {
    return JSON.stringify([name ?? '', email ?? '', role ?? '', Number(routingOrder) || 0]);
}

/** Flow screen component that collects signers as SignZeroSigner records for the Dispatch Document action. */
export default class SignZeroSignerEditor extends LightningElement {
    tagExample = '{{sig:Role}}';
    rows = [this.newRow(1)];
    roleOptions = [];
    errorMessage;

    @wire(getObjectInfo, { objectApiName: RECIPIENT_OBJECT })
    recipientInfo;

    /** From the Signer Role picklist, so senders can only pick roles templates are tagged with. */
    @wire(getPicklistValues, { recordTypeId: '$recipientInfo.data.defaultRecordTypeId', fieldApiName: SIGNER_ROLE_FIELD })
    wiredRoles({ data, error }) {
        if (data) {
            this.roleOptions = data.values.map(({ label, value }) => ({ label, value }));
        } else if (error) {
            this.errorMessage = 'Signer roles could not be loaded. Check your access to the Signer Role field.';
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
    }

    /** Called by the flow before it moves on. */
    @api
    validate() {
        const inputs = [...this.template.querySelectorAll('lightning-input, lightning-combobox')];
        const fieldsValid = inputs.reduce((ok, input) => input.reportValidity() && ok, true);
        const emails = this.rows.map((r) => (r.email || '').trim().toLowerCase());
        let message;
        if (!fieldsValid) {
            message = 'Complete every signer\u2019s name, email, role and routing order.';
        } else if (emails.some((e) => !EMAIL.test(e))) {
            message = 'One of the email addresses is not valid.';
        } else if (new Set(emails).size !== emails.length) {
            message = 'Each signer needs a different email address.';
        } else if (this.rows.some((r) => !(Number(r.routingOrder) >= 1))) {
            message = 'Routing order must be 1 or more.';
        }
        this.errorMessage = message;
        return message ? { isValid: false, errorMessage: message } : { isValid: true };
    }
}
