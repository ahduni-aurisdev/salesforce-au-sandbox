import { LightningElement, api, track, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import getLines          from '@salesforce/apex/CDCProgramLinesController.getLines';
import getProgramOptions from '@salesforce/apex/CDCProgramLinesController.getProgramOptions';
import getAllAOIOptions   from '@salesforce/apex/CDCProgramLinesController.getAllAOIOptions';
import saveLines         from '@salesforce/apex/CDCProgramLinesController.saveLines';
import deleteLine        from '@salesforce/apex/CDCProgramLinesController.deleteLine';
import DRIVE_TYPE_FIELD  from '@salesforce/schema/Opportunity.Drive_Type__c';

let rowCounter = 0;
const newKey = () => 'row-' + (++rowCounter);

const PROG_CARD_BASE     = 'prog-card';
const PROG_CARD_SELECTED = 'prog-card prog-card--selected';
const AOI_CARD_BASE      = 'aoi-card';
const AOI_CARD_SELECTED  = 'aoi-card aoi-card--selected';

export default class CdcProgramLines extends LightningElement {

    @api recordId;

    @track lines          = [];
    @track isLoading      = true;
    @track isSaving       = false;
    @track isReadOnly     = true;
    @track errorMessage   = '';
    @track successMessage = '';
    @track showDeleteModal = false;
    @track driveType       = '';

    // ── Bulk Add modal state ─────────────────────────────────────────────
    @track showBulkModal   = false;
    @track bulkStep        = 1;
    @track bulkPrograms    = [];   // [{label, value, selected, cardClass}]
    @track bulkAOISections = [];   // [{program, aois:[{label, value, selected, cardClass}]}]
    @track bulkModalError  = '';

    programOptions = [];
    aoiMap         = {};   // { CSE:[{label,value},...], MBA:[...], ... } — from Apex wire
    _wiredResult;
    _pendingDeleteKey  = null;
    _pendingDeleteSfId = null;
    _linesLoaded  = false;
    _aoiMapLoaded = false;

    // ── Wires ────────────────────────────────────────────────────────────
    @wire(getLines, { opportunityId: '$recordId' })
    wiredLines(result) {
        this._wiredResult = result;
        this.isLoading = false;
        if (result.data) {
            this.lines = result.data.map(rec => this._toRow(rec));
            this._linesLoaded = true;
            this._enrichLinesWithAOI();
            this.errorMessage = '';
        } else if (result.error) {
            this.errorMessage = 'Failed to load lines: ' + this._parseError(result.error);
        }
    }

    @wire(getProgramOptions)
    wiredPrograms({ data }) {
        if (data) this.programOptions = data.map(o => ({ label: o.label, value: o.value }));
    }

    // Drive Type on the parent Opportunity decides whether CTC_Offered__c
    // is read as CTC (Placement) or Stipend (Internship)
    @wire(getRecord, { recordId: '$recordId', fields: [DRIVE_TYPE_FIELD] })
    wiredOpportunity({ data }) {
        if (data) this.driveType = getFieldValue(data, DRIVE_TYPE_FIELD) || '';
    }

    // Loads full Program→AOI map once; used by bulk modal AND per-row program change
    @wire(getAllAOIOptions)
    wiredAOIMap({ data, error }) {
        if (data) {
            this.aoiMap = data;
            this._aoiMapLoaded = true;
            this._enrichLinesWithAOI();
        }
        if (error) {
            console.error('getAllAOIOptions failed:', error);
        }
    }

    // ── Getters: table ───────────────────────────────────────────────────
    get hasNoLines()       { return !this.isLoading && this.lines.length === 0; }
    get totalExpected()    { return this._sum('Expected_Students__c'); }
    get totalRegistered()  { return this._sum('Registered_Students__c'); }
    get totalAppeared()    { return this._sum('Appeared_Students__c'); }
    get totalShortlisted() { return this._sum('Shortlisted_Students__c'); }
    get totalSelected()    { return this._sum('Selected_Students__c'); }
    get totalOffers()      { return this._sum('Offer_Accepted__c'); }
    get maxCTC() {
        const vals = this.lines.map(l => Number(l.CTC_Offered__c) || 0);
        return vals.length ? Math.max(...vals) : 0;
    }

    // ── Getters: CTC/Stipend label (depends on Opportunity Drive Type) ────
    get isInternshipDrive()  { return this.driveType === 'Internship'; }
    get ctcColumnLabel()     { return this.isInternshipDrive ? 'Stipend (LPA)' : 'CTC (LPA)'; }
    get ctcSummaryCaption()  { return this.isInternshipDrive ? 'Max Stipend' : 'Max CTC'; }

    // ── Getters: bulk modal ──────────────────────────────────────────────
    get isStep1() { return this.bulkStep === 1; }
    get isStep2() { return this.bulkStep === 2; }

    get step1Class() {
        return this.isStep1 ? 'step-pill step-pill--active' : 'step-pill step-pill--done';
    }
    get step2Class() {
        return this.isStep2 ? 'step-pill step-pill--active' : 'step-pill';
    }

    get bulkSelectedCount() {
        return this.bulkPrograms.filter(p => p.selected).length;
    }

    get bulkAddCount() {
        return this.bulkAOISections.reduce(
            (acc, s) => acc + s.aois.filter(a => a.selected).length, 0
        );
    }

    get bulkAddButtonLabel() {
        const c = this.bulkAddCount;
        return 'Add ' + c + ' Line' + (c !== 1 ? 's' : '');
    }

    get isBulkAddDisabled() { return this.bulkAddCount === 0; }

    // ── Single Add Row ───────────────────────────────────────────────────
    handleAddRow() {
        this.isReadOnly = false;
        this.successMessage = '';
        this.lines = [...this.lines, {
            rowKey: newKey(), Id: null,
            Program__c: '', AOI__c: '',
            Expected_Students__c: 0, Registered_Students__c: 0,
            Appeared_Students__c: 0, Shortlisted_Students__c: 0,
            Selected_Students__c: 0, Offer_Accepted__c: 0,
            CTC_Offered__c: 0, Remarks__c: '',
            aoiOptions: [], aoiDisabled: true,
            rowClass: 'new-row'
        }];
    }

    handleToggleEdit() {
        this.isReadOnly = false;
        this.successMessage = '';
    }

    // ── Bulk Add: open modal ─────────────────────────────────────────────
    handleBulkAdd() {
        this.bulkStep       = 1;
        this.bulkModalError = '';
        this.bulkPrograms   = this.programOptions.map(p => ({
            label: p.label, value: p.value,
            selected: false, cardClass: PROG_CARD_BASE
        }));
        this.bulkAOISections = [];
        this.showBulkModal   = true;
    }

    // ── Bulk Add: Step 1 — program selection ─────────────────────────────
    handleBulkProgramToggle(event) {
        const val        = event.currentTarget.dataset.value;
        this.bulkPrograms = this.bulkPrograms.map(p => {
            if (p.value !== val) return p;
            const sel = !p.selected;
            return { ...p, selected: sel, cardClass: sel ? PROG_CARD_SELECTED : PROG_CARD_BASE };
        });
        this.bulkModalError = '';
    }

    handleBulkSelectAllPrograms() {
        this.bulkPrograms = this.bulkPrograms.map(p => ({
            ...p, selected: true, cardClass: PROG_CARD_SELECTED
        }));
    }

    handleBulkClearAllPrograms() {
        this.bulkPrograms = this.bulkPrograms.map(p => ({
            ...p, selected: false, cardClass: PROG_CARD_BASE
        }));
    }

    // Advance to Step 2: build AOI sections for selected programs
    handleBulkNext() {
        const selected = this.bulkPrograms.filter(p => p.selected);
        if (selected.length === 0) {
            this.bulkModalError = 'Please select at least one Program to continue.';
            return;
        }
        this.bulkModalError  = '';
        this.bulkAOISections = selected.map(p => ({
            program: p.value,
            aois: (this.aoiMap[p.value] || []).map(a => ({
                label: a.label, value: a.value,
                selected: false, cardClass: AOI_CARD_BASE
            }))
        }));
        this.bulkStep = 2;
    }

    // ── Bulk Add: Step 2 — AOI selection ─────────────────────────────────
    handleBulkAOIToggle(event) {
        const program         = event.currentTarget.dataset.program;
        const aoi             = event.currentTarget.dataset.aoi;
        this.bulkAOISections  = this.bulkAOISections.map(s => {
            if (s.program !== program) return s;
            return {
                ...s,
                aois: s.aois.map(a => {
                    if (a.value !== aoi) return a;
                    const sel = !a.selected;
                    return { ...a, selected: sel, cardClass: sel ? AOI_CARD_SELECTED : AOI_CARD_BASE };
                })
            };
        });
        this.bulkModalError = '';
    }

    handleBulkSelectAllAOI(event) {
        const program        = event.currentTarget.dataset.program;
        this.bulkAOISections = this.bulkAOISections.map(s =>
            s.program !== program ? s : {
                ...s, aois: s.aois.map(a => ({ ...a, selected: true, cardClass: AOI_CARD_SELECTED }))
            }
        );
    }

    handleBulkClearAllAOI(event) {
        const program        = event.currentTarget.dataset.program;
        this.bulkAOISections = this.bulkAOISections.map(s =>
            s.program !== program ? s : {
                ...s, aois: s.aois.map(a => ({ ...a, selected: false, cardClass: AOI_CARD_BASE }))
            }
        );
    }

    handleBulkBack() {
        this.bulkStep       = 1;
        this.bulkModalError = '';
    }

    // ── Bulk Add: confirm — validate duplicates, then inject rows ────────
    handleBulkAddLines() {
        if (this.bulkAddCount === 0) {
            this.bulkModalError = 'Please select at least one Area of Interest.';
            return;
        }

        // Collect all existing Program+AOI keys (saved + unsaved rows)
        const existingKeys = new Set(
            this.lines
                .filter(l => l.Program__c && l.AOI__c)
                .map(l => l.Program__c + '|' + l.AOI__c)
        );

        const duplicates = [];
        for (const section of this.bulkAOISections) {
            for (const aoi of section.aois) {
                if (aoi.selected && existingKeys.has(section.program + '|' + aoi.value)) {
                    duplicates.push(section.program + ' – ' + aoi.value);
                }
            }
        }

        if (duplicates.length > 0) {
            this.bulkModalError =
                'These combinations already exist: ' + duplicates.join(', ') +
                '. Please deselect them or remove the existing lines first.';
            return;
        }

        // Build and inject new rows into the table
        const newLines = [];
        for (const section of this.bulkAOISections) {
            for (const aoi of section.aois) {
                if (!aoi.selected) continue;
                newLines.push({
                    rowKey: newKey(), Id: null,
                    Program__c: section.program,
                    AOI__c:     aoi.value,
                    Expected_Students__c: 0, Registered_Students__c: 0,
                    Appeared_Students__c: 0, Shortlisted_Students__c: 0,
                    Selected_Students__c: 0, Offer_Accepted__c: 0,
                    CTC_Offered__c: 0, Remarks__c: '',
                    aoiOptions: (this.aoiMap[section.program] || []).map(
                        a => ({ label: a.label, value: a.value })
                    ),
                    aoiDisabled: false,
                    rowClass: 'new-row'
                });
            }
        }

        this.lines         = [...this.lines, ...newLines];
        this.isReadOnly    = false;
        this.showBulkModal = false;
        this.successMessage = '';
        this._fireToast(
            'success', 'Lines Added',
            newLines.length + ' line(s) added to the table. Click Save All to save.'
        );
    }

    handleBulkCancel() {
        this.showBulkModal  = false;
        this.bulkModalError = '';
    }

    // ── Program changed in table row (uses local aoiMap — no Apex call) ──
    handleProgramChange(event) {
        const key  = event.target.dataset.id;
        const prog = event.detail.value;
        this.successMessage = '';

        const aoiOpts = (this.aoiMap[prog] || []).map(
            o => ({ label: o.label, value: o.value })
        );

        this.lines = this.lines.map(line => {
            if (line.rowKey !== key) return line;
            return {
                ...line,
                Program__c:  prog,
                AOI__c:      '',
                aoiOptions:  aoiOpts,
                aoiDisabled: aoiOpts.length === 0
            };
        });
    }

    // ── Generic field change ─────────────────────────────────────────────
    handleFieldChange(event) {
        const key   = event.target.dataset.id;
        const field = event.target.dataset.field;
        const val   = event.detail.value;
        this.successMessage = '';
        this.lines = this.lines.map(line => {
            if (line.rowKey !== key) return line;
            return { ...line, [field]: val };
        });
    }

    // ── Save all lines ───────────────────────────────────────────────────
    handleSaveAll() {
        for (const line of this.lines) {
            if (!line.Program__c) {
                this.errorMessage = 'Program is required on all lines.';
                return;
            }
            if (!line.AOI__c) {
                this.errorMessage = 'Area of Interest is required on all lines.';
                return;
            }
        }

        const keys = new Set();
        for (const line of this.lines) {
            const k = line.Program__c + '|' + line.AOI__c;
            if (keys.has(k)) {
                this.errorMessage =
                    'Duplicate: ' + line.Program__c + ' – ' + line.AOI__c +
                    '. Each Program + AOI must be unique.';
                return;
            }
            keys.add(k);
        }

        this.isSaving     = true;
        this.errorMessage = '';

        const toSave = this.lines.map(
            ({ rowKey, aoiOptions, aoiDisabled, rowClass, ...rest }) => rest
        );

        saveLines({ opportunityId: this.recordId, lines: toSave })
            .then(() => {
                this.isSaving       = false;
                this.isReadOnly     = true;
                this.successMessage = '✅ ' + this.lines.length + ' line(s) saved successfully.';
                this._fireToast('success', 'Saved', 'Program lines saved successfully.');
                return refreshApex(this._wiredResult);
            })
            .then(() => {
                if (this._wiredResult && this._wiredResult.data) {
                    this.lines = this._wiredResult.data.map(rec => this._toRow(rec));
                    this._enrichLinesWithAOI();
                }
            })
            .catch(err => {
                this.isSaving     = false;
                this.errorMessage = this._parseError(err);
            });
    }

    // ── Delete row ───────────────────────────────────────────────────────
    handleDeleteRow(event) {
        this._pendingDeleteKey  = event.currentTarget.dataset.id;
        this._pendingDeleteSfId = event.currentTarget.dataset.sfid;
        if (this._pendingDeleteSfId) {
            this.showDeleteModal = true;
        } else {
            this.lines = this.lines.filter(l => l.rowKey !== this._pendingDeleteKey);
            this._pendingDeleteKey = null;
        }
    }

    cancelDelete() {
        this.showDeleteModal    = false;
        this._pendingDeleteKey  = null;
        this._pendingDeleteSfId = null;
    }

    confirmDelete() {
        this.showDeleteModal = false;
        deleteLine({ lineId: this._pendingDeleteSfId })
            .then(() => {
                this.lines = this.lines.filter(l => l.rowKey !== this._pendingDeleteKey);
                this._pendingDeleteKey  = null;
                this._pendingDeleteSfId = null;
                this._fireToast('success', 'Deleted', 'Line deleted.');
                return refreshApex(this._wiredResult);
            })
            .catch(err => { this.errorMessage = this._parseError(err); });
    }

    clearError() { this.errorMessage = ''; }

    // ── Helpers ──────────────────────────────────────────────────────────
    _toRow(rec) {
        return {
            ...rec,
            rowKey:     newKey(),
            aoiOptions: [],
            aoiDisabled: false,
            rowClass:   ''
        };
    }

    // Populate aoiOptions on all rows once both wires have loaded
    _enrichLinesWithAOI() {
        if (!this._linesLoaded || !this._aoiMapLoaded) return;
        this.lines = this.lines.map(line => ({
            ...line,
            aoiOptions:  (this.aoiMap[line.Program__c] || []).map(
                o => ({ label: o.label, value: o.value })
            ),
            aoiDisabled: !line.Program__c
        }));
    }

    _sum(field) {
        return this.lines.reduce((acc, l) => acc + (Number(l[field]) || 0), 0);
    }

    _parseError(err) {
        if (typeof err === 'string') return err;
        if (err && err.body && err.body.message) return err.body.message;
        if (err && err.message) return err.message;
        return 'An unexpected error occurred.';
    }

    _fireToast(variant, title, message) {
        this.dispatchEvent(new ShowToastEvent({ variant, title, message }));
    }
}