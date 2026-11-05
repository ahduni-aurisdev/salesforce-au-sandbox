import { LightningElement, api } from 'lwc';
import { RefreshEvent } from 'lightning/refresh';
import ZoomLeadSyncModal from 'c/zoomLeadSyncModal';

/**
 * Headless quick action "Sync Leads to Salesforce" on a Zoom Session. Opens the large zoomLeadSyncModal
 * (a quick-action screen cannot be resized) and refreshes the record page when a sync was started.
 */
export default class ZoomLeadSyncAction extends LightningElement {
    @api recordId;

    @api
    async invoke() {
        const result = await ZoomLeadSyncModal.open({
            size: 'large',
            description: 'Create or update Leads for the registrants and walk-ins of this Zoom session',
            recordId: this.recordId
        });
        if (result === 'synced') {
            this.dispatchEvent(new RefreshEvent());
        }
    }
}
