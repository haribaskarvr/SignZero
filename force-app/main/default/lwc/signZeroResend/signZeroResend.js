import { LightningElement, api } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import previewResend from '@salesforce/apex/SignZeroResendController.previewResend';
import resend from '@salesforce/apex/SignZeroResendController.resend';

/** Resend Invitation quick action: confirm, then re-send the signing link. */
export default class SignZeroResend extends LightningElement {
    targets = [];
    errorMessage;
    isLoading = true;
    isSending = false;
    _recordId;

    // recordId arrives after construction.
    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        if (value) {
            this.loadPreview();
        }
    }

    get hasTargets() {
        return this.targets.length > 0;
    }

    get resendDisabled() {
        return !this.hasTargets || this.isSending;
    }

    async loadPreview() {
        this.isLoading = true;
        try {
            this.targets = await previewResend({ recordId: this._recordId });
        } catch (error) {
            this.errorMessage = error?.body?.message || error?.message;
        } finally {
            this.isLoading = false;
        }
    }

    async handleResend() {
        this.isSending = true;
        this.isLoading = true;
        try {
            const count = await resend({ recordId: this._recordId });
            this.dispatchEvent(new ShowToastEvent({
                title: 'Invitation sent',
                message: `${count} signing ${count === 1 ? 'link was' : 'links were'} emailed.`,
                variant: 'success'
            }));
            await notifyRecordUpdateAvailable([{ recordId: this._recordId }]);
            this.close();
        } catch (error) {
            this.errorMessage = error?.body?.message || error?.message;
        } finally {
            this.isSending = false;
            this.isLoading = false;
        }
    }

    close() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }
}
