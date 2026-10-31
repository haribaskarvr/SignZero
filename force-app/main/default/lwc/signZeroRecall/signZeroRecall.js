import { LightningElement, api } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import previewRecall from '@salesforce/apex/SignZeroRecallController.previewRecall';
import recall from '@salesforce/apex/SignZeroRecallController.recall';
// Text lives in Custom Labels (category SignZero) so admins can reword and translate it.
import header from '@salesforce/label/c.SZ_Recall_Header';
import loading from '@salesforce/label/c.SZ_Recall_Loading';
import intro from '@salesforce/label/c.SZ_Recall_Intro';
import notifyIntro from '@salesforce/label/c.SZ_Recall_Notify_Intro';
import reasonLabel from '@salesforce/label/c.SZ_Recall_Reason';
import reasonHelp from '@salesforce/label/c.SZ_Recall_Reason_Help';
import warning from '@salesforce/label/c.SZ_Recall_Warning';
import confirm from '@salesforce/label/c.SZ_Recall_Confirm';
import cancel from '@salesforce/label/c.SZ_Cancel';
import doneTitle from '@salesforce/label/c.SZ_Recall_Done_Title';
import doneNone from '@salesforce/label/c.SZ_Recall_Done_None';
import doneOne from '@salesforce/label/c.SZ_Recall_Done_One';
import doneMany from '@salesforce/label/c.SZ_Recall_Done_Many';

const LABELS = {
    header,
    loading,
    intro,
    notifyIntro,
    reason: reasonLabel,
    reasonHelp,
    warning,
    confirm,
    cancel
};

/** Quick action on a Signature Request: confirm, optionally give a reason, then recall (void) the envelope. */
export default class SignZeroRecall extends LightningElement {
    labels = LABELS;
    targets = [];
    reason = '';
    errorMessage;
    isLoading = true;
    isSending = false;
    canRecall = false;
    _recordId;

    // Quick actions receive recordId after construction, so load when it arrives.
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

    get recallDisabled() {
        return !this.canRecall || this.isSending;
    }

    async loadPreview() {
        this.isLoading = true;
        try {
            this.targets = await previewRecall({ recordId: this._recordId });
            this.canRecall = true;
        } catch (error) {
            this.errorMessage = error?.body?.message || error?.message;
        } finally {
            this.isLoading = false;
        }
    }

    handleReasonChange(event) {
        this.reason = event.target.value;
    }

    async handleRecall() {
        this.isSending = true;
        this.isLoading = true;
        try {
            const result = await recall({ recordId: this._recordId, reason: this.reason });
            const notified = result.notified;
            let sent = doneMany.replace('{0}', notified);
            if (notified === 0) {
                sent = doneNone;
            } else if (notified === 1) {
                sent = doneOne;
            }
            this.dispatchEvent(new ShowToastEvent({
                title: doneTitle,
                message: result.warning || sent,
                variant: result.warning ? 'warning' : 'success'
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
