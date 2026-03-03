import { LightningElement, api, track } from 'lwc';
import saveCallLog from '@salesforce/apex/CallLogController.saveCallLog';

export default class CallLogModal extends LightningElement {

    @api recordId;
    @track isOpen = true;
    @track selectedValue;

    options = [
        { label: 'Recieved', value: 'Recieved' },
        { label: 'Not Received', value: 'Not Received' },
        { label: 'Not Interested', value: 'Not Interested' }
    ];

    handleChange(event) {
        this.selectedValue = event.detail.value;
    }

    closeModal() {
        this.isOpen = false;
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleSubmit() {
        saveCallLog({
            leadId: this.recordId,
            result: this.selectedValue
        }).then(() => {
            this.closeModal();
        });
    }
}