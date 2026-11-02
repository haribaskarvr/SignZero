import { LightningElement, api, wire } from 'lwc';
import getBranding from '@salesforce/apex/SignZeroBrandingController.getBranding';

/** Signing site header: logo (SignZero Branding) and company name (SignZero Settings). */
export default class SignZeroHeader extends LightningElement {
    /** Set by the logo editor in Experience Builder. */
    @api logoUrl;
    /** Set by the favicon editor in Experience Builder. */
    @api faviconUrl;
    @api showCompanyName = false;

    branding = {};
    appliedFavicon;

    @wire(getBranding)
    wiredBranding({ data }) {
        if (data) {
            this.branding = data;
        }
    }

    get logo() {
        return this.logoUrl || this.branding.logoUrl;
    }

    /** The browser tab icon: the favicon, else the logo. */
    get favicon() {
        return this.faviconUrl || this.branding.faviconUrl || this.logo;
    }

    renderedCallback() {
        this.applyFavicon();
    }

    // The site has no favicon of its own, so add one link and keep it current.
    applyFavicon() {
        const href = this.favicon;
        if (!href || href === this.appliedFavicon) {
            return;
        }
        let link = document.head.querySelector('link[rel="icon"][data-signzero]');
        if (!link) {
            link = document.createElement('link');
            link.rel = 'icon';
            link.dataset.signzero = 'true';
            document.head.appendChild(link);
        }
        link.href = href;
        this.appliedFavicon = href;
    }

    get companyName() {
        return this.branding.companyName;
    }

    get showName() {
        return this.showCompanyName && !!this.companyName;
    }

    get brandStyle() {
        return this.branding.primaryColor ? `--signzero-brand: ${this.branding.primaryColor};` : '';
    }
}
