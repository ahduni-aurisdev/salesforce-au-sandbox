import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { RefreshEvent } from 'lightning/refresh';
import { getPicklistValuesByRecordType } from 'lightning/uiObjectInfoApi';
import LEAD_OBJECT from '@salesforce/schema/Lead';
import getSyncContext from '@salesforce/apex/ZoomLeadSyncController.getSyncContext';
import getSyncProgress from '@salesforce/apex/ZoomLeadSyncController.getSyncProgress';
import startSync from '@salesforce/apex/ZoomLeadSyncController.startSync';

const PHASE_FORM = 'form';
const PHASE_RUNNING = 'running';
const PHASE_DONE = 'done';
const POLL_INTERVAL_MS = 3000;
const MAX_POLLS = 200; // 10 minutes
const STATUS_ENDED = 'Ended';
const FIELD_ADMISSION_YEAR = 'Admission_Year__c';
const FIELD_PROGRAMME = 'Preferred_Programme__c';
const GENERIC_ERROR = 'Something went wrong. Try again, or contact your Salesforce admin if it keeps happening.';

const BASE_COLUMNS = [
    { label: 'Name', fieldName: 'name', type: 'text', wrapText: true },
    { label: 'Email', fieldName: 'email', type: 'email' },
    { label: 'Phone', fieldName: 'phone', type: 'phone' },
    {
        label: 'Joined as',
        fieldName: 'participation',
        type: 'text',
        initialWidth: 125,
        cellAttributes: { iconName: { fieldName: 'participationIcon' }, iconAlternativeText: 'Joined as' }
    },
    {
        label: 'Status',
        fieldName: 'statusLabel',
        type: 'text',
        initialWidth: 135,
        cellAttributes: { iconName: { fieldName: 'statusIcon' }, iconAlternativeText: 'Status', class: { fieldName: 'statusClass' } }
    }
];
const PROGRAMME_COLUMN = { label: 'Preferred programme', fieldName: 'programme', type: 'text', wrapText: true };

/** Readable message from an Apex / UI API error; never the raw error object. */
function messageOf(error) {
    if (!error) {
        return GENERIC_ERROR;
    }
    if (Array.isArray(error.body)) {
        const messages = error.body.map((item) => item && item.message).filter(Boolean);
        return messages.length ? messages.join(' ') : GENERIC_ERROR;
    }
    if (error.body && typeof error.body.message === 'string' && error.body.message) {
        return error.body.message;
    }
    return GENERIC_ERROR;
}

export default class ZoomLeadSync extends LightningElement {
    _recordId;
    _requested = false;

    isLoading = true;
    loadError;
    context;
    progress = {};
    phase = PHASE_FORM;

    department;
    admissionYear;
    yearOptions = [];
    programmeOptions = [];
    yearDefault;
    picklistError;
    picklistsLoaded = false;

    programmeById = {};
    selectedIds = [];
    bulkProgramme;
    searchTerm = '';

    isStarting = false;
    startCount = 0;
    pollTimer;
    pollCount = 0;
    pollWarning;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        // Quick actions set recordId after connectedCallback; load as soon as it arrives.
        if (value && !this._requested) {
            this._requested = true;
            this.loadContext();
        }
    }

    disconnectedCallback() {
        this.stopPolling();
    }

    // ── Data loading ──────────────────────────────────────────────────────────────────────────────────────────────

    async loadContext() {
        this.isLoading = true;
        this.loadError = undefined;
        try {
            const context = await getSyncContext({ sessionId: this._recordId });
            this.context = context;
            this.progress = context.progress || {};
            this.department = context.department || undefined;
            this.admissionYear = context.admissionYear || undefined;
            const programmes = {};
            (context.students || []).forEach((student) => {
                if (student.programme) {
                    programmes[student.registrationId] = student.programme;
                }
            });
            this.programmeById = programmes;
            this.selectedIds = [];
            if (this.progress.isRunning) {
                this.startCount = this.openCount;
                this.phase = PHASE_RUNNING;
                this.startPolling();
            } else {
                this.phase = PHASE_FORM;
            }
        } catch (error) {
            this.loadError = messageOf(error);
        } finally {
            this.isLoading = false;
        }
    }

    @wire(getPicklistValuesByRecordType, { objectApiName: LEAD_OBJECT, recordTypeId: '$recordTypeId' })
    wiredPicklists({ data, error }) {
        if (data) {
            this.picklistError = undefined;
            const years = data.picklistFieldValues[FIELD_ADMISSION_YEAR];
            this.yearOptions = years ? years.values.map((item) => ({ label: item.label, value: item.value })) : [];
            this.yearDefault = years && years.defaultValue ? years.defaultValue.value : undefined;
            this.programmeOptions = this.programmesFor(data.picklistFieldValues[FIELD_PROGRAMME]);
            this.picklistsLoaded = true;
            this.applyYearDefault();
            this.dropInvalidProgrammes();
        } else if (error) {
            this.yearOptions = [];
            this.programmeOptions = [];
            this.picklistsLoaded = false;
            this.picklistError = 'Admission years and programmes could not be loaded. ' + messageOf(error);
        }
    }

    /** Programme values of the record type; when the field depends on Department, only those valid for it. */
    programmesFor(field) {
        if (!field) {
            return [];
        }
        const controllerIndex = field.controllerValues ? field.controllerValues[this.departmentLabel] : undefined;
        return field.values
            .filter((item) => controllerIndex === undefined || !item.validFor || item.validFor.includes(controllerIndex))
            .map((item) => ({ label: item.label, value: item.value }));
    }

    /**
     * Preselects the Zoom Config default year (e.g. Admission Year - 2027), else the Lead picklist default; keeps a
     * still-valid choice. A locked session keeps its year.
     */
    applyYearDefault() {
        if (this.context && this.context.isLocked) {
            return;
        }
        const values = this.yearOptions.map((option) => option.value);
        if (this.admissionYear && values.includes(this.admissionYear)) {
            return;
        }
        const configured = this.context ? this.context.defaultAdmissionYear : undefined;
        if (configured && values.includes(configured)) {
            this.admissionYear = configured;
            return;
        }
        this.admissionYear = this.yearDefault && values.includes(this.yearDefault) ? this.yearDefault : undefined;
    }

    dropInvalidProgrammes() {
        const valid = new Set(this.programmeOptions.map((option) => option.value));
        const kept = {};
        Object.keys(this.programmeById).forEach((id) => {
            if (valid.has(this.programmeById[id])) {
                kept[id] = this.programmeById[id];
            }
        });
        this.programmeById = kept;
        if (this.bulkProgramme && !valid.has(this.bulkProgramme)) {
            this.bulkProgramme = undefined;
        }
    }

    // ── Derived state ─────────────────────────────────────────────────────────────────────────────────────────────

    get departmentOptions() {
        return ((this.context && this.context.departments) || []).map((item) => ({ label: item.label, value: item.value }));
    }

    get selectedDepartment() {
        return ((this.context && this.context.departments) || []).find((item) => item.value === this.department);
    }

    get recordTypeId() {
        return this.selectedDepartment ? this.selectedDepartment.recordTypeId : undefined;
    }

    get departmentLabel() {
        return this.selectedDepartment ? this.selectedDepartment.label : undefined;
    }

    get isUndergraduation() {
        return Boolean(this.selectedDepartment && this.selectedDepartment.isUndergraduation);
    }

    get isFormPhase() {
        return this.phase === PHASE_FORM && !this.isLoading && !this.loadError && Boolean(this.context);
    }

    get isRunningPhase() {
        return this.phase === PHASE_RUNNING;
    }

    get isDonePhase() {
        return this.phase === PHASE_DONE;
    }

    get students() {
        return (this.context && this.context.students) || [];
    }

    get hasStudents() {
        return this.students.length > 0;
    }

    get openCount() {
        return this.students.length;
    }

    get attendanceToLog() {
        return this.progress.hasEnded ? this.progress.attendancePending || 0 : 0;
    }

    get isDetailsDisabled() {
        return Boolean(this.context.isLocked) || this.isStarting || Boolean(this.context.blockedReason);
    }

    get isYearDisabled() {
        return this.isDetailsDisabled || !this.department || !this.picklistsLoaded;
    }

    get yearPlaceholder() {
        return this.department ? 'Select an admission year' : 'Select a department first';
    }

    get showProgrammeTools() {
        return Boolean(this.department) && !this.isUndergraduation;
    }

    get hideCheckboxes() {
        return !this.showProgrammeTools;
    }

    get isProgrammeToolsDisabled() {
        return this.isStarting || !this.picklistsLoaded || Boolean(this.context.blockedReason);
    }

    get isApplyDisabled() {
        return this.isProgrammeToolsDisabled || !this.bulkProgramme || this.selectedIds.length === 0;
    }

    get isClearDisabled() {
        return this.isProgrammeToolsDisabled || this.selectedIds.length === 0;
    }

    get applyLabel() {
        return this.selectedIds.length ? `Apply to ${this.selectedIds.length} Selected` : 'Apply to Selected';
    }

    get selectionText() {
        const withProgramme = Object.keys(this.programmeById).length;
        const selected = this.selectedIds.length;
        const selectionPart = selected
            ? `${selected} selected.`
            : 'Select students in the table, choose a programme and apply it.';
        return `${selectionPart} ${withProgramme} of ${this.openCount} have a programme (optional).`;
    }

    get columns() {
        return this.showProgrammeTools ? [...BASE_COLUMNS, PROGRAMME_COLUMN] : BASE_COLUMNS;
    }

    get rows() {
        return this.students.map((student) => ({
            registrationId: student.registrationId,
            name: student.name,
            email: student.email,
            phone: student.phone,
            participation: student.participation,
            participationIcon: student.participation === 'Walk-in' ? 'utility:change_record_type' : 'utility:edit_form',
            statusLabel: student.hasError ? 'Retry (failed)' : 'Not synced',
            statusIcon: student.hasError ? 'utility:warning' : 'utility:clock',
            statusClass: student.hasError ? 'slds-text-color_error' : '',
            programme: this.programmeById[student.registrationId] || ''
        }));
    }

    get visibleRows() {
        const term = (this.searchTerm || '').trim().toLowerCase();
        if (!term) {
            return this.rows;
        }
        return this.rows.filter((row) =>
            [row.name, row.email, row.phone].some((value) => value && value.toLowerCase().includes(term))
        );
    }

    get hasVisibleRows() {
        return this.visibleRows.length > 0;
    }

    get visibleSelectedIds() {
        const visible = new Set(this.visibleRows.map((row) => row.registrationId));
        return this.selectedIds.filter((id) => visible.has(id));
    }

    get studentsHeading() {
        return this.hasStudents ? `2. Students to Sync (${this.openCount})` : '2. Students to Sync';
    }

    get emptyIcon() {
        return this.attendanceToLog > 0 ? 'utility:event' : 'utility:success';
    }

    get emptyTitle() {
        return this.attendanceToLog > 0 ? 'Attendance Ready to Log' : 'All Students Are Synced';
    }

    get emptyMessage() {
        if (this.attendanceToLog > 0) {
            return `Every student has a Lead. Click "Log Attendance" to add the Attended / Did Not Attend activity for ${this.attendanceToLog} of them.`;
        }
        if (this.progress.total === 0) {
            return 'No registrations or walk-ins have arrived from Zoom yet. Come back after people register or join.';
        }
        return 'There is nothing new to sync. New registrations, walk-ins and attendance can be synced when they arrive.';
    }

    get submitLabel() {
        if (this.isStarting) {
            return 'Starting…';
        }
        if (this.openCount > 0) {
            return this.openCount === 1 ? 'Sync 1 Student' : `Sync ${this.openCount} Students`;
        }
        return 'Log Attendance';
    }

    get isSubmitDisabled() {
        if (!this.context || this.context.blockedReason || this.isStarting) {
            return true;
        }
        if (!this.department || !this.admissionYear || !this.picklistsLoaded) {
            return true;
        }
        if (this.isUndergraduation && !this.context.undergraduationOwnerName) {
            return true;
        }
        return this.openCount === 0 && this.attendanceToLog === 0;
    }

    get statusBadgeClass() {
        return this.context && this.context.sessionStatus === STATUS_ENDED ? 'slds-theme_success' : 'slds-theme_info';
    }

    get statusBadgeIcon() {
        return this.context && this.context.sessionStatus === STATUS_ENDED ? 'utility:check' : 'utility:clock';
    }

    get lastSyncText() {
        return Boolean(this.progress.lastSyncAt || (this.context && this.context.lastSyncByName));
    }

    get statTiles() {
        const progress = this.progress || {};
        return [
            { key: 'open', label: 'Not synced', value: (progress.notSynced || 0) + (progress.errors || 0), icon: 'standard:waits' },
            { key: 'created', label: 'Leads created', value: progress.created || 0, icon: 'standard:lead' },
            { key: 'updated', label: 'Leads updated', value: progress.updated || 0, icon: 'standard:record_update' },
            { key: 'attention', label: 'Need attention', value: (progress.errors || 0) + (progress.noContact || 0), icon: 'standard:incident' }
        ];
    }

    get sessionTypeLabel() {
        return (this.context && this.context.sessionType) || 'Session';
    }

    get sessionNameLabel() {
        return (this.context && this.context.sessionName) || 'Zoom session';
    }

    get showPath() {
        return Boolean(this.context) && !this.context.blockedReason;
    }

    get currentStep() {
        if (this.phase !== PHASE_FORM) {
            return 'sync';
        }
        return this.department && this.admissionYear ? 'students' : 'details';
    }

    get ownerInitials() {
        const name = (this.context && this.context.undergraduationOwnerName) || '';
        return name
            .split(' ')
            .filter(Boolean)
            .slice(0, 2)
            .map((part) => part.charAt(0).toUpperCase())
            .join('');
    }

    get footerSummary() {
        if (!this.isFormPhase || !this.department || !this.admissionYear) {
            return '';
        }
        const label = this.departmentLabel || this.department;
        const year = this.admissionYear.replace('Admission Year - ', '');
        return `${label} · ${year}`;
    }

    get doneIconVariant() {
        return this.progress.errors ? 'warning' : 'success';
    }

    get progressPercent() {
        if (!this.startCount) {
            return this.progress.isRunning ? 50 : 100;
        }
        const remaining = (this.progress.notSynced || 0);
        const done = Math.max(0, this.startCount - remaining);
        return Math.min(100, Math.round((done / this.startCount) * 100));
    }

    get progressText() {
        if (!this.startCount) {
            return 'Logging attendance…';
        }
        const done = Math.max(0, this.startCount - (this.progress.notSynced || 0));
        return `${done} of ${this.startCount} students`;
    }

    get doneIcon() {
        return this.progress.errors ? 'utility:warning' : 'utility:success';
    }

    get doneTitle() {
        return this.progress.errors ? 'Sync Finished With Problems' : 'Sync Complete';
    }

    get doneMessage() {
        const progress = this.progress;
        const parts = [`${progress.created || 0} Leads created and ${progress.updated || 0} existing Leads updated on this session.`];
        if (progress.noContact) {
            parts.push(`${progress.noContact} without email or phone were skipped.`);
        }
        if (progress.errors) {
            parts.push(`${progress.errors} could not be synced; click Sync Leads to Salesforce again to retry. Details are in the API Log.`);
        }
        return parts.join(' ');
    }

    get closeLabel() {
        if (this.isRunningPhase) {
            return 'Close and Continue in Background';
        }
        return this.isDonePhase ? 'Done' : 'Close';
    }

    // ── Handlers ──────────────────────────────────────────────────────────────────────────────────────────────────

    handleRetryLoad() {
        this.loadContext();
    }

    handleDepartmentChange(event) {
        this.department = event.detail.value;
        this.picklistsLoaded = false;
        this.yearOptions = [];
        this.programmeOptions = [];
        this.bulkProgramme = undefined;
        this.admissionYear = undefined;
        if (this.isUndergraduation) {
            this.programmeById = {};
            this.selectedIds = [];
        }
    }

    handleYearChange(event) {
        this.admissionYear = event.detail.value;
    }

    handleBulkProgrammeChange(event) {
        this.bulkProgramme = event.detail.value;
    }

    handleSearch(event) {
        this.searchTerm = event.target.value;
    }

    handleRowSelection(event) {
        const visible = new Set(this.visibleRows.map((row) => row.registrationId));
        const hiddenSelected = this.selectedIds.filter((id) => !visible.has(id));
        const visibleSelected = event.detail.selectedRows.map((row) => row.registrationId);
        this.selectedIds = [...hiddenSelected, ...visibleSelected];
    }

    handleApplyProgramme() {
        const updated = { ...this.programmeById };
        this.selectedIds.forEach((id) => {
            updated[id] = this.bulkProgramme;
        });
        const count = this.selectedIds.length;
        this.programmeById = updated;
        this.selectedIds = [];
        this.toast('Programme applied', `${this.bulkProgramme} set for ${count} ${count === 1 ? 'student' : 'students'}.`, 'success');
    }

    handleClearProgramme() {
        const updated = { ...this.programmeById };
        this.selectedIds.forEach((id) => {
            delete updated[id];
        });
        this.programmeById = updated;
        this.selectedIds = [];
    }

    async handleSync() {
        this.isStarting = true;
        try {
            const programmes = this.isUndergraduation
                ? []
                : Object.keys(this.programmeById).map((id) => ({ registrationId: id, programme: this.programmeById[id] }));
            const result = await startSync({
                sessionId: this._recordId,
                department: this.department,
                admissionYear: this.admissionYear,
                programmes
            });
            if (!result.started) {
                this.toast('Sync not started', result.message || GENERIC_ERROR, 'error');
                return;
            }
            this.startCount = this.openCount;
            this.progress = result.progress || this.progress;
            this.phase = PHASE_RUNNING;
            this.toast('Sync started', 'Leads are being created and updated in the background.', 'info');
            this.startPolling();
        } catch (error) {
            this.toast('Sync not started', messageOf(error), 'error');
        } finally {
            this.isStarting = false;
        }
    }

    handleClose() {
        this.stopPolling();
        if (this.isDonePhase) {
            this.dispatchEvent(new RefreshEvent());
        }
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    // ── Progress polling ──────────────────────────────────────────────────────────────────────────────────────────

    startPolling() {
        this.stopPolling();
        this.pollCount = 0;
        this.pollWarning = undefined;
        this.schedulePoll();
    }

    schedulePoll() {
        // The background job reports progress only through record counts, so the popup polls them.
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.pollTimer = setTimeout(() => this.poll(), POLL_INTERVAL_MS);
    }

    stopPolling() {
        if (this.pollTimer) {
            clearTimeout(this.pollTimer);
            this.pollTimer = undefined;
        }
    }

    async poll() {
        this.pollTimer = undefined;
        try {
            const progress = await getSyncProgress({ sessionId: this._recordId });
            this.progress = progress;
            this.pollWarning = undefined;
            if (!progress.isRunning) {
                this.finishSync();
                return;
            }
        } catch (error) {
            this.pollWarning = 'Progress could not be refreshed. Retrying… ' + messageOf(error);
        }
        this.pollCount += 1;
        if (this.pollCount >= MAX_POLLS) {
            this.pollWarning = 'The sync is taking longer than expected. It continues in the background; check the session later.';
            return;
        }
        this.schedulePoll();
    }

    finishSync() {
        this.phase = PHASE_DONE;
        const progress = this.progress;
        if (progress.errors) {
            this.toast('Sync finished with problems',
                `${progress.errors} students could not be synced. Click Sync Leads to Salesforce again to retry.`, 'warning');
        } else {
            this.toast('Sync complete', `${progress.created || 0} Leads created and ${progress.updated || 0} updated.`, 'success');
        }
        this.dispatchEvent(new RefreshEvent());
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}