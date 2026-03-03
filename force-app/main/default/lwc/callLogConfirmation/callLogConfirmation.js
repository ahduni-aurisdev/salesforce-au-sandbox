import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import updateLeadAndCreateTask from '@salesforce/apex/CallLogController.updateLeadAndCreateTask';

export default class LeadCallConfirmation extends LightningElement {
    @api recordId;
    selectedValue = '';
    commentValue = '';
    showAdditionalInfo = false;
    isSaveDisabled = true;
    isLoading = false;

    get isYesSelected() {
        return this.selectedValue === 'Yes';
    }

    get isNoSelected() {
        return this.selectedValue === 'No';
    }

    get isNotInterestedSelected() {
        return this.selectedValue === 'Not Interested';
    }

    get isInterestedSelected() {
        return this.selectedValue === 'Interested';
    }

    handleYesClick(event) {
        event.preventDefault();
        this.updateSelection('Yes');
    }

    handleNoClick(event) {
        event.preventDefault();
        this.updateSelection('No');
    }

    handleNotInterestedClick(event) {
        event.preventDefault();
        this.updateSelection('Not Interested');
    }

    handleInterestedClick(event) {
        event.preventDefault();
        this.updateSelection('Interested');
    }

    handleCommentChange(event) {
        this.commentValue = event.target.value;
    }

    updateSelection(value) {
        this.selectedValue = value;
        this.isSaveDisabled = false;
        this.showAdditionalInfo = true;
    }

    handleSave() {
        if (!this.selectedValue) {
            this.showToast('Error', 'Please select a call status', 'error');
            return;
        }

        // Show spinner
        this.isLoading = true;

        // Call Apex method to update Lead and create Task
        updateLeadAndCreateTask({
            leadId: this.recordId,
            callStatus: this.selectedValue,
            comments: this.commentValue
        })
            .then(() => {
                this.isLoading = false;
                this.showToast(
                    'Success', 
                    'Lead updated and call log task created successfully!', 
                    'success'
                );
                this.closeQuickAction();
            })
            .catch(error => {
                this.isLoading = false;
                let errorMessage = 'An error occurred while updating the lead';
                if (error.body && error.body.message) {
                    errorMessage = error.body.message;
                }
                this.showToast('Error', errorMessage, 'error');
            });
    }

    handleCancel() {
        this.closeQuickAction();
    }

    closeQuickAction() {
        // For Quick Actions
        this.dispatchEvent(new CloseActionScreenEvent());
        
        // Fallback for custom implementations
        this.dispatchEvent(new CustomEvent('close'));
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: message,
                variant: variant
            })
        );
    }
}