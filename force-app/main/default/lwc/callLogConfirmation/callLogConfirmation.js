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

    get isNotConnectedSelected() {
        return this.selectedValue === 'Not Connected';
    }

    get isConnectedFollowUpRequiredSelected() {
        return this.selectedValue === 'Connected Follow-Up Required';
    }

    get isConnectedInterestedSelected() {
        return this.selectedValue === 'Connected Interested';
    }

    get isConnectedNotInterestedSelected() {
        return this.selectedValue === 'Connected Not Interested';
    }

    get isConvertedSelected() {
        return this.selectedValue === 'Converted';
    }

    get isClosedSelected() {
        return this.selectedValue === 'Closed';
    }

    handleNotConnectedClick(event) {
        event.preventDefault();
        this.updateSelection('Not Connected');
    }

    handleConnectedFollowUpRequiredClick(event) {
        event.preventDefault();
        this.updateSelection('Connected Follow-Up Required');
    }

    handleConnectedInterestedClick(event) {
        event.preventDefault();
        this.updateSelection('Connected Interested');
    }

    handleConnectedNotInterestedClick(event) {
        event.preventDefault();
        this.updateSelection('Connected Not Interested');
    }

    handleConvertedClick(event) {
        event.preventDefault();
        this.updateSelection('Converted');
    }

    handleClosedClick(event) {
        event.preventDefault();
        this.updateSelection('Closed');
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