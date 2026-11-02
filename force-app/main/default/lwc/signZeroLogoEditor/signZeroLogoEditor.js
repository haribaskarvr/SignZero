import { LightningElement, api } from 'lwc';

/** Experience Builder property editor for the SignZero Header logo; passes the uploaded link back to Builder. */
export default class SignZeroLogoEditor extends LightningElement {
    // Property editor contract: Experience Builder sets these.
    @api label;
    @api description;
    @api required;
    @api value;
    @api errors = [];
    @api schema;

    handleImageChange(event) {
        this.value = event.detail.value;
        this.dispatchEvent(new CustomEvent('valuechange', { detail: { value: this.value } }));
    }
}
