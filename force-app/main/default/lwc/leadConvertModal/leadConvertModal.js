import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import { CloseActionScreenEvent } from 'lightning/actions';
import getLeadDetails from '@salesforce/apex/LeadConvertController.getLeadDetails';
import convertLead    from '@salesforce/apex/LeadConvertController.convertLead';

export default class LeadConvertModal extends NavigationMixin(LightningElement) {

    // ── @api recordId as a setter so we react the moment the platform sets it ─
    _recordId;
    _dataLoaded = false;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        // Platform sets recordId AFTER connectedCallback on Quick Actions.
        // Load data here so we always have the Id in hand.
        if (value && !this._dataLoaded) {
            this._dataLoaded = true;
            this.loadLeadDetails();
        }
    }

    // ── UI State ──────────────────────────────────────────────────────────────
    @track isModalOpen  = true;   // Quick Action opens directly — no extra button needed
    @track isLoading    = true;
    @track isConverting = false;
    @track errorMessage = '';

    // ── Lead Summary (flat primitives — safe in template) ─────────────────────
    @track leadFirstName  = '';
    @track leadLastName   = '';
    @track leadCompany    = '';
    @track leadEmail      = '';
    @track leadPhone      = '';
    @track leadSource     = '';
    @track leadRecordType = '';

    // ── Conversion Fields ─────────────────────────────────────────────────────
    @track selectedAccountId   = null;
    @track selectedAccountName = '';
    @track selectedContactId   = null;
    @track selectedContactName = '';
    @track opportunityName     = '';
    @track createOpportunity   = true;
    @track selectedStatus      = 'Closed Won';
    @track statusOptions       = [];

    // Filter: exclude Person Accounts from the Account picker
    accountFilter = {
        criteria: [
            { fieldPath: 'IsPersonAccount', operator: 'eq', value: false }
        ]
    };

    // ── Data Loading ──────────────────────────────────────────────────────────

    loadLeadDetails() {
        // Extra guard — should never be null here but safety first
        if (!this._recordId) {
            this.errorMessage = 'Record Id is not available. Please close and reopen this action.';
            this.isLoading    = false;
            return;
        }

        this.isLoading    = true;
        this.errorMessage = '';

        getLeadDetails({ leadId: this._recordId })
            .then(result => {
                const lead = result.lead || {};

                // Flatten all fields — never chain deeper than one level in template
                this.leadFirstName  = lead.FirstName  || '';
                this.leadLastName   = lead.LastName   || '';
                this.leadCompany    = lead.Company    || '';
                this.leadEmail      = lead.Email      || '';
                this.leadPhone      = lead.Phone      || '';
                this.leadSource     = lead.LeadSource || '';
                this.leadRecordType = (lead.RecordType && lead.RecordType.Name)
                                        ? lead.RecordType.Name : '';

                // Pre-populate Account & Contact from custom Lead fields
                this.selectedAccountId   = result.accountId   || null;
                this.selectedAccountName = result.accountName || '';
                this.selectedContactId   = result.contactId   || null;
                this.selectedContactName = result.contactName || '';
                this.opportunityName     = result.opportunityName || '';

                // Status options
                if (result.convertedStatuses && result.convertedStatuses.length > 0) {
                    this.statusOptions  = result.convertedStatuses;
                    this.selectedStatus = result.convertedStatuses[0].value;
                }

                this.isLoading = false;
            })
            .catch(error => {
                this.errorMessage = 'Error loading lead details: ' + this.extractError(error);
                this.isLoading    = false;
            });
    }

    // ── Modal Control ─────────────────────────────────────────────────────────

    closeModal() {
        this.isModalOpen = false;
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    // ── Event Handlers ────────────────────────────────────────────────────────

    handleAccountChange(event) {
        this.selectedAccountId   = event.detail.recordId || null;
        this.selectedAccountName = this.selectedAccountId
            ? (event.detail.displayInfo?.label || '')
            : '';
    }

    handleContactChange(event) {
        this.selectedContactId   = event.detail.recordId || null;
        this.selectedContactName = this.selectedContactId
            ? (event.detail.displayInfo?.label || '')
            : '';
    }

    handleOppToggle(event) {
        this.createOpportunity = event.target.checked;
    }

    handleOppNameChange(event) {
        this.opportunityName = event.target.value;
    }

    handleStatusChange(event) {
        this.selectedStatus = event.detail.value;
    }

    // ── Conversion ────────────────────────────────────────────────────────────

    handleConvert() {
        this.errorMessage = '';

        if (!this.selectedStatus) {
            this.errorMessage = 'Please select a converted status.';
            return;
        }
        if (this.createOpportunity && !this.opportunityName.trim()) {
            this.errorMessage = 'Please enter an opportunity name.';
            return;
        }

        this.isConverting = true;

        convertLead({
            leadId:            this._recordId,
            accountId:         this.selectedAccountId,
            contactId:         this.selectedContactId,
            opportunityName:   this.opportunityName,
            createOpportunity: this.createOpportunity,
            convertedStatus:   'Closed Won'
        })
        .then(result => {
            this.isConverting = false;

            this.dispatchEvent(new ShowToastEvent({
                title:   'Lead Converted Successfully!',
                message: 'The lead has been converted to an Organization Account.',
                variant: 'success',
                mode:    'sticky'
            }));

            // Navigate to the converted Account
            if (result.accountId) {
                this[NavigationMixin.Navigate]({
                    type: 'standard__recordPage',
                    attributes: { recordId: result.accountId, actionName: 'view' }
                });
            }

            this.dispatchEvent(new CloseActionScreenEvent());
        })
        .catch(error => {
            this.isConverting = false;
            this.errorMessage = 'Conversion failed: ' + this.extractError(error);
        });
    }

    // ── Getters ───────────────────────────────────────────────────────────────

    get convertButtonLabel() {
        return this.isConverting ? 'Converting...' : 'Convert Lead';
    }

    get leadFullName() {
        return `${this.leadFirstName} ${this.leadLastName}`.trim();
    }

    // ── Utilities ─────────────────────────────────────────────────────────────

    extractError(error) {
        if (error?.body?.message) return error.body.message;
        if (error?.message)       return error.message;
        return 'Unknown error occurred.';
    }
}