import { LightningElement } from 'lwc';
import check from '@salesforce/apex/SignZeroEmailCheck.check';
import title from '@salesforce/label/c.SZ_Email_Check_Title';
import loading from '@salesforce/label/c.SZ_Email_Check_Loading';
import ok from '@salesforce/label/c.SZ_Email_Check_Ok';
import intro from '@salesforce/label/c.SZ_Email_Check_Intro';

const LABELS = { title, loading, ok, intro };

/** Email setup problems and how to fix them; on the Send for Signature warning screen and SignZero Home. */
export default class SignZeroEmailCheck extends LightningElement {
    labels = LABELS;
    issues = [];
    errorMessage;
    isLoading = true;

    connectedCallback() {
        this.load();
    }

    async load() {
        try {
            const issues = await check();
            this.issues = issues.map((issue, index) => ({
                key: `issue-${index}`,
                message: issue.message,
                iconName: issue.severity === 'error' ? 'utility:error' : 'utility:warning',
                iconVariant: issue.severity === 'error' ? 'error' : 'warning',
                alternativeText: issue.severity
            }));
        } catch (error) {
            this.errorMessage = error?.body?.message || error?.message;
        } finally {
            this.isLoading = false;
        }
    }

    get isOk() {
        return !this.isLoading && !this.errorMessage && this.issues.length === 0;
    }

    get hasIssues() {
        return this.issues.length > 0;
    }
}
