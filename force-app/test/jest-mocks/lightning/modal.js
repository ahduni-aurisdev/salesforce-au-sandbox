/** Jest stub for lightning/modal (not shipped with sfdx-lwc-jest). */
import { LightningElement, api } from 'lwc';

export default class LightningModal extends LightningElement {
    @api size;
    @api label;
    @api description;

    close(result) {
        this.dispatchEvent(new CustomEvent('modalclose', { detail: result }));
    }
}
