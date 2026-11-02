import { LightningElement, api } from 'lwc';
import saveImage from '@salesforce/apex/SignZeroBrandingAdmin.saveImage';
import removeImage from '@salesforce/apex/SignZeroBrandingAdmin.removeImage';
// Text is in Custom Labels (category SignZero) so admins can reword and translate it.
import logoHelp from '@salesforce/label/c.SZ_Logo_Help';
import logoRemove from '@salesforce/label/c.SZ_Logo_Remove';
import logoSaved from '@salesforce/label/c.SZ_Logo_Saved';
import logoNone from '@salesforce/label/c.SZ_Logo_None';
import logoErrType from '@salesforce/label/c.SZ_Logo_Err_Type';
import faviconHelp from '@salesforce/label/c.SZ_Favicon_Help';
import faviconRemove from '@salesforce/label/c.SZ_Favicon_Remove';
import faviconSaved from '@salesforce/label/c.SZ_Favicon_Saved';
import faviconNone from '@salesforce/label/c.SZ_Favicon_None';
import faviconErrType from '@salesforce/label/c.SZ_Favicon_Err_Type';
import saving from '@salesforce/label/c.SZ_Image_Saving';
import errSize from '@salesforce/label/c.SZ_Image_Err_Size';

const MAX_IMAGE_BYTES = 1024 * 1024;
// Accepted formats (matching SignZeroConstants) and wording, per kind.
const KINDS = {
    logo: {
        extensions: ['png', 'jpg', 'jpeg'],
        text: { help: logoHelp, remove: logoRemove, saved: logoSaved, none: logoNone, errType: logoErrType, saving }
    },
    favicon: {
        extensions: ['png', 'jpg', 'jpeg', 'ico'],
        text: {
            help: faviconHelp,
            remove: faviconRemove,
            saved: faviconSaved,
            none: faviconNone,
            errType: faviconErrType,
            saving
        }
    }
};

/** Uploads the logo or favicon to SignZero Branding and fires imagechange with its link. */
export default class SignZeroImageUpload extends LightningElement {
    /** logo or favicon */
    @api kind;
    @api label;
    @api value;

    isSaving = false;
    message;
    errorMessage;

    get config() {
        return KINDS[this.kind] || KINDS.logo;
    }

    get text() {
        return this.config.text;
    }

    get accept() {
        return this.config.extensions.map((extension) => `.${extension}`).join(',');
    }

    handleFile(event) {
        const file = event.detail.files && event.detail.files[0];
        this.message = null;
        this.errorMessage = null;
        if (!file) {
            return;
        }
        // Browsers report an empty type for some icons, so check the file name.
        const extension = file.name.split('.').pop().toLowerCase();
        if (!this.config.extensions.includes(extension)) {
            this.errorMessage = this.text.errType;
            return;
        }
        if (file.size > MAX_IMAGE_BYTES) {
            this.errorMessage = errSize;
            return;
        }
        const reader = new FileReader();
        reader.onload = () => this.upload(file.name, reader.result.split(',')[1]);
        reader.readAsDataURL(file);
    }

    async upload(fileName, base64Data) {
        this.isSaving = true;
        try {
            const url = await saveImage({ kind: this.kind, fileName, base64Data });
            this.publish(url);
            this.message = this.text.saved;
        } catch (error) {
            this.errorMessage = error?.body?.message || error?.message;
        } finally {
            this.isSaving = false;
        }
    }

    async handleRemove() {
        this.isSaving = true;
        this.message = null;
        this.errorMessage = null;
        try {
            await removeImage({ kind: this.kind });
            this.publish('');
        } catch (error) {
            this.errorMessage = error?.body?.message || error?.message;
        } finally {
            this.isSaving = false;
        }
    }

    publish(value) {
        this.dispatchEvent(new CustomEvent('imagechange', { detail: { value } }));
    }
}
