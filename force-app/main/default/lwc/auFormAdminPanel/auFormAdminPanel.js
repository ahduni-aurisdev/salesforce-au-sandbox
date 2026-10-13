import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getDashboardData from '@salesforce/apex/AU_FormAdminController.getDashboardData';
import getLeadCountsByForm from '@salesforce/apex/AU_FormAdminController.getLeadCountsByForm';
import saveForm from '@salesforce/apex/AU_FormAdminController.saveForm';
import deleteForm from '@salesforce/apex/AU_FormAdminController.deleteForm';
import getProgrammeBrochures from '@salesforce/apex/AU_FormAdminController.getProgrammeBrochures';
import saveProgrammeBrochures from '@salesforce/apex/AU_FormAdminController.saveProgrammeBrochures';

export default class AuFormAdminPanel extends LightningElement {
    @track isLoading = false;
    @track totalLeadsCount = 0;
    @track isLeadCountsLoaded = false;
    @track rawData = {
        departments: [],
        forms: [],
        leadRecordTypes: [],
        availableLeadFields: [],
        leadSourceOptions: [],
        siteBaseUrl: ''
    };

    @track selectedDeptFilter = '';
    @track searchKey = '';

    // Form Editor State
    @track isEditorOpen = false;
    @track isEditing = false;
    @track activeEditorTab = 'tab-details';
    @track currentForm = {
        developerName: '',
        masterLabel: '',
        departmentCode: 'UG',
        formName: '',
        formSubtitle: '',
        formIcon: '📋',
        formSlug: '',
        sectionLabel: 'Programme Details',
        leadRecordTypeName: 'Undergraduation',
        typeOfForm: 'Admission_Form',
        sortOrder: 10,
        fields: []
    };

    // Delete Confirmation Modal State
    @track isDeleteModalOpen = false;
    @track formToDelete = {};

    // Add Field Modal State
    @track isAddFieldModalOpen = false;
    @track fieldSearchKey = '';

    // Advanced Field Config State
    @track isFieldConfigModalOpen = false;
    @track activeFieldConfigIndex = -1;
    @track activeFieldConfig = {};

    // Campaign URL Generator State
    @track isUrlModalOpen = false;
    @track selectedFormForUrl = {};
    @track urlParams = {
        utmSource: 'webinar',
        utmMedium: 'social',
        utmCampaign: '',
        utmContent: '',
        isEmbed: false
    };

    // Programme Brochures State
    @track isBrochureModalOpen = false;
    @track isBrochureLoading = false;
    @track isBrochureSaving = false;
    @track brochureSearchKey = '';
    @track brochureRows = [];

    get filteredBrochureRows() {
        const key = (this.brochureSearchKey || '').toLowerCase().trim();
        return this.brochureRows.filter(r => !key
            || r.programmeName.toLowerCase().includes(key)
            || (r.departmentCode || '').toLowerCase().includes(key));
    }

    get brochureLinkedCount() {
        return this.brochureRows.filter(r => r.brochureUrl).length;
    }

    handleOpenBrochures() {
        this.isBrochureModalOpen = true;
        this.brochureSearchKey = '';
        this.isBrochureLoading = true;
        getProgrammeBrochures()
            .then(rows => {
                this.brochureRows = (rows || []).map((r, i) => ({
                    ...r,
                    key: `${i}-${r.programmeName}`,
                    brochureUrl: r.brochureUrl || '',
                    originalUrl: r.brochureUrl || ''
                }));
                this.isBrochureLoading = false;
            })
            .catch(error => {
                this.isBrochureLoading = false;
                this.showToast('Error Loading Programmes', error.body?.message || error.message, 'error');
            });
    }

    handleCloseBrochures() {
        this.isBrochureModalOpen = false;
    }

    handleBrochureSearch(event) {
        this.brochureSearchKey = event.target.value;
    }

    handleBrochureUrlChange(event) {
        const key = event.target.dataset.key;
        const value = event.target.value;
        this.brochureRows = this.brochureRows.map(r => r.key === key ? { ...r, brochureUrl: value } : r);
    }

    handleSaveBrochures() {
        const changed = this.brochureRows.filter(r => (r.brochureUrl || '').trim() !== r.originalUrl);
        if (!changed.length) {
            this.showToast('No Changes', 'No brochure links were changed.', 'info');
            return;
        }
        const bad = changed.find(r => r.brochureUrl.trim() && !/^https:\/\//i.test(r.brochureUrl.trim()));
        if (bad) {
            this.showToast('Invalid Link', `Link for "${bad.programmeName}" must start with https://`, 'error');
            return;
        }
        this.isBrochureSaving = true;
        const payload = changed.map(r => ({
            programmeName: r.programmeName,
            brochureUrl: r.brochureUrl.trim(),
            developerName: r.developerName
        }));
        saveProgrammeBrochures({ rowsJSON: JSON.stringify(payload) })
            .then(result => {
                this.isBrochureSaving = false;
                if (result && result.success) {
                    this.showToast('Brochures Saved',
                        `${result.count || 0} programme brochure link(s) queued for deployment. Changes go live in about a minute.`,
                        'success');
                    this.isBrochureModalOpen = false;
                } else {
                    this.showToast('Save Error', (result && result.error) || 'Failed to save brochure links', 'error');
                }
            })
            .catch(error => {
                this.isBrochureSaving = false;
                this.showToast('Save Error', error.body?.message || error.message, 'error');
            });
    }

    connectedCallback() {
        this.loadDashboard();
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // DATA LOADING (ASYNC / NON-BLOCKING)
    // ─────────────────────────────────────────────────────────────────────────────

    loadDashboard() {
        this.isLoading = true;
        getDashboardData()
            .then(data => {
                if (data && data.forms) {
                    data.forms = data.forms.map(f => ({
                        ...f,
                        leadCount: 0,
                        isLeadCountLoading: true
                    }));
                }
                this.rawData = data;
                this.isLoading = false;
                // Fetch lead counts asynchronously in background (no page load delay)
                this.loadLeadCountsAsync();
            })
            .catch(error => {
                this.isLoading = false;
                this.showToast('Error Loading Data', error.body?.message || error.message, 'error');
            });
    }

    loadLeadCountsAsync() {
        getLeadCountsByForm()
            .then(countMap => {
                if (this.rawData.forms && countMap) {
                    let total = 0;
                    this.rawData.forms = this.rawData.forms.map(f => {
                        const devName = (f.developerName || '').toLowerCase().trim();
                        const slug = (f.formSlug || '').toLowerCase().trim();
                        const tof = (f.typeOfForm || '').toLowerCase().trim();
                        const formName = (f.formName || '').toLowerCase().trim();

                        let count = 0;
                        if (tof && countMap[tof] !== undefined) count = countMap[tof];
                        else if (slug && countMap[slug] !== undefined) count = countMap[slug];
                        else if (devName && countMap[devName] !== undefined) count = countMap[devName];
                        else if (formName && countMap[formName] !== undefined) count = countMap[formName];

                        total += count;
                        return {
                            ...f,
                            leadCount: count,
                            isLeadCountLoading: false
                        };
                    });
                    this.totalLeadsCount = total;
                    this.isLeadCountsLoaded = true;
                }
            })
            .catch(err => {
                console.warn('Async lead count fetch completed with non-fatal notice:', err);
                if (this.rawData.forms) {
                    this.rawData.forms = this.rawData.forms.map(f => ({
                        ...f,
                        isLeadCountLoading: false
                    }));
                }
            });
    }

    handleRefresh() {
        this.loadDashboard();
        this.showToast('Refreshed', 'Form configurations and lead metrics reloaded', 'info');
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // GETTERS & COMPUTED PROPERTIES
    // ─────────────────────────────────────────────────────────────────────────────

    get totalLeadsDisplay() {
        return this.isLeadCountsLoaded ? this.totalLeadsCount : '...';
    }
    // ─────────────────────────────────────────────────────────────────────────────

    get totalForms() {
        return this.rawData.forms?.length || 0;
    }

    get totalDepartments() {
        return this.rawData.departments?.length || 0;
    }

    get totalFields() {
        return this.rawData.totalFields || 0;
    }

    get departmentFilterOptions() {
        const opts = [{ label: 'All Departments', value: '' }];
        if (this.rawData.departments) {
            this.rawData.departments.forEach(d => {
                opts.push({ label: `${d.iconEmoji || ''} ${d.masterLabel} (${d.developerName})`, value: d.developerName });
            });
        }
        return opts;
    }

    get departmentOptions() {
        if (!this.rawData.departments) return [];
        return this.rawData.departments.map(d => ({
            label: `${d.iconEmoji || ''} ${d.masterLabel} (${d.developerName})`,
            value: d.developerName
        }));
    }

    get recordTypeOptions() {
        if (!this.rawData.leadRecordTypes) return [];
        const opts = [{ label: '-- Use Department Default --', value: '' }];
        this.rawData.leadRecordTypes.forEach(rt => {
            opts.push({ label: rt.label, value: rt.developerName });
        });
        return opts;
    }

    get iconOptions() {
        return [
            { label: '📋 Clipboard', value: '📋' },
            { label: '🎓 Graduation Cap', value: '🎓' },
            { label: '💻 Laptop / Webinar', value: '💻' },
            { label: '🚀 Rocket', value: '🚀' },
            { label: '🏛️ University / Building', value: '🏛️' },
            { label: '📝 Note / Registration', value: '📝' },
            { label: '📊 Chart / Stats', value: '📊' },
            { label: '🌐 Globe / International', value: '🌐' },
            { label: '✨ Sparkles / Featured', value: '✨' },
            { label: '🤝 Handshake / Executive', value: '🤝' }
        ];
    }

    get fieldTypeOptions() {
        return [
            { label: 'Text', value: 'text' },
            { label: 'Email', value: 'email' },
            { label: 'Phone / Tel', value: 'tel' },
            { label: 'Number', value: 'number' },
            { label: 'Date', value: 'date' },
            { label: 'Dropdown / Picklist', value: 'picklist' },
            { label: 'Programme Picklist', value: 'programme_picklist' },
            { label: 'Textarea (Multi-line)', value: 'textarea' }
        ];
    }

    get utmSourceOptions() {
        const set = new Set();
        const opts = [];

        // 1. Common marketing & channel presets
        const presets = [
            { label: 'Webinar (Online Session)', value: 'webinar' },
            { label: 'Virtual Webinar', value: 'Virtual Webinar' },
            { label: 'Roadshow Event (City Tour)', value: 'Roadshow Event' },
            { label: 'Career Fair / Education Fair', value: 'Career Fair' },
            { label: 'Open House / Campus Visit', value: 'Open House' },
            { label: 'Wonderchat Bot / Chatbot', value: 'wonderchat' },
            { label: 'Website (Direct / Organic)', value: 'website' },
            { label: 'Instagram Ads / Bio', value: 'Instagram' },
            { label: 'Facebook / Meta Ads', value: 'Facebook' },
            { label: 'LinkedIn / LinkedIn Ads', value: 'LinkedIn Ads' },
            { label: 'Google Search / Google Ads', value: 'Google_ads' },
            { label: 'Email Campaign / Newsletter', value: 'Email' },
            { label: 'Campus QR Code', value: 'qr_campus' },
            { label: 'Alumni / Referral', value: 'Referral' },
            { label: 'Shiksha / Collegedunia', value: 'Shiksha' }
        ];

        presets.forEach(p => {
            if (!set.has(p.value.toLowerCase())) {
                set.add(p.value.toLowerCase());
                opts.push(p);
            }
        });

        // 2. Active LeadSource picklist values from Salesforce
        if (this.rawData.leadSourceOptions) {
            this.rawData.leadSourceOptions.forEach(ls => {
                if (!set.has(ls.value.toLowerCase())) {
                    set.add(ls.value.toLowerCase());
                    opts.push({ label: `${ls.label} (LeadSource)`, value: ls.value });
                }
            });
        }

        return opts;
    }

    get utmMediumOptions() {
        return [
            { label: 'Social (Instagram, LinkedIn, Facebook)', value: 'social' },
            { label: 'CPC / Paid Search / Paid Ads', value: 'cpc' },
            { label: 'Event / Offline Roadshow', value: 'event' },
            { label: 'Email / Newsletter', value: 'email' },
            { label: 'Referral / Partner / Direct', value: 'referral' },
            { label: 'Organic / Website Link', value: 'organic' },
            { label: 'Banner / Display Ad', value: 'display' },
            { label: 'WhatsApp Broadcast', value: 'whatsapp' },
            { label: 'QR Code / Print Brochure', value: 'qr_code' }
        ];
    }

    get filteredForms() {
        if (!this.rawData.forms) return [];
        return this.rawData.forms.filter(f => {
            const matchesDept = !this.selectedDeptFilter || f.departmentCode === this.selectedDeptFilter;
            const term = (this.searchKey || '').toLowerCase();
            const matchesSearch = !term ||
                (f.formName && f.formName.toLowerCase().includes(term)) ||
                (f.formSlug && f.formSlug.toLowerCase().includes(term)) ||
                (f.departmentCode && f.departmentCode.toLowerCase().includes(term));
            return matchesDept && matchesSearch;
        });
    }

    get filteredFormsCount() {
        return this.filteredForms.length;
    }

    get hasFilteredForms() {
        return this.filteredForms.length > 0;
    }

    get editorModalTitle() {
        return this.isEditing ? `Edit Form: ${this.currentForm.formName}` : 'Create New Dynamic Form';
    }

    get hasCurrentFields() {
        return this.currentForm.fields && this.currentForm.fields.length > 0;
    }

    get filteredAvailableFields() {
        if (!this.rawData.availableLeadFields) return [];
        const existingApis = new Set((this.currentForm.fields || []).map(f => f.sfApiName));
        const search = (this.fieldSearchKey || '').toLowerCase();

        return this.rawData.availableLeadFields
            .filter(af => {
                if (!search) return true;
                return af.label.toLowerCase().includes(search) || af.apiName.toLowerCase().includes(search);
            })
            .map(af => ({
                ...af,
                isAlreadyAdded: existingApis.has(af.apiName)
            }));
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // FILTERING & SEARCH
    // ─────────────────────────────────────────────────────────────────────────────

    handleDeptFilterChange(event) {
        this.selectedDeptFilter = event.detail.value;
    }

    handleSearchChange(event) {
        this.searchKey = event.detail.value;
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // FORM CREATOR / EDITOR
    // ─────────────────────────────────────────────────────────────────────────────

    handleOpenCreateModal() {
        const deptCode = this.selectedDeptFilter || 'UG';
        const deptObj = (this.rawData.departments || []).find(d => d.developerName === deptCode);
        const autoRtName = deptObj && deptObj.leadRecordType ? deptObj.leadRecordType : 'Undergraduation';

        this.isEditing = false;
        this.activeEditorTab = 'tab-details';
        this.currentForm = {
            developerName: '',
            masterLabel: '',
            departmentCode: deptCode,
            formName: '',
            formSubtitle: '',
            formIcon: '📋',
            formSlug: '',
            sectionLabel: 'Programme Details',
            leadRecordTypeName: autoRtName,
            typeOfForm: 'Admission_Form',
            sortOrder: (this.rawData.forms?.length || 0) + 1,
            fields: []
        };
        this.updateFieldOrderFlags();
        this.isEditorOpen = true;
    }

    handleEditForm(event) {
        const formDevName = event.currentTarget.dataset.formName;
        const target = this.rawData.forms.find(f => f.developerName === formDevName);
        if (!target) return;

        this.isEditing = true;
        this.activeEditorTab = 'tab-details';
        this.currentForm = JSON.parse(JSON.stringify(target));
        if (!this.currentForm.fields) this.currentForm.fields = [];
        this.currentForm.typeOfForm = 'Admission_Form';

        this.updateFieldOrderFlags();
        this.isEditorOpen = true;
    }

    handleCloneForm(event) {
        const formDevName = event.currentTarget.dataset.formName;
        const target = this.rawData.forms.find(f => f.developerName === formDevName);
        if (!target) return;

        this.isEditing = false;
        this.activeEditorTab = 'tab-details';
        this.currentForm = JSON.parse(JSON.stringify(target));
        this.currentForm.developerName = '';
        this.currentForm.formName = `${this.currentForm.formName} (Copy)`;
        this.currentForm.formSlug = `${this.currentForm.formSlug}-copy`;
        this.currentForm.typeOfForm = 'Admission_Form';

        if (this.currentForm.fields) {
            this.currentForm.fields.forEach(f => {
                f.developerName = ''; // clear developerName so new records are generated
            });
        }
        this.updateFieldOrderFlags();
        this.isEditorOpen = true;
        this.showToast('Form Cloned', 'Adjust slug and name then save to create a new form', 'info');
    }

    handleCloseEditor() {
        this.isEditorOpen = false;
    }

    handleGoToFieldsTab() {
        if (!this.currentForm.formName || !this.currentForm.formSlug || !this.currentForm.departmentCode) {
            this.showToast('Validation Error', 'Please complete Department, Form Name, and URL Slug before proceeding to configure fields.', 'error');
            return;
        }
        this.activeEditorTab = 'tab-fields';
    }

    handleGoToDetailsTab() {
        this.activeEditorTab = 'tab-details';
    }

    handleTabSelect(event) {
        this.activeEditorTab = event.target.value;
    }

    handleDepartmentChange(event) {
        const deptCode = event.detail.value;
        this.currentForm.departmentCode = deptCode;
        const deptObj = (this.rawData.departments || []).find(d => d.developerName === deptCode);
        if (deptObj && deptObj.leadRecordType) {
            this.currentForm.leadRecordTypeName = deptObj.leadRecordType;
        }
    }

    handleFormInputChange(event) {
        const field = event.target.name;
        this.currentForm[field] = event.target.value;
    }

    handleFormNameChange(event) {
        this.currentForm.formName = event.target.value;
        // Auto-generate slug if not editing or slug was empty
        if (!this.isEditing || !this.currentForm.formSlug) {
            this.currentForm.formSlug = this.slugify(event.target.value);
        }
    }

    slugify(text) {
        if (!text) return '';
        return text
            .toString()
            .toLowerCase()
            .trim()
            .replace(/\s+/g, '-')
            .replace(/[^\w-]+/g, '')
            .replace(/--+/g, '-');
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // VISUAL FIELD BUILDER ACTIONS
    // ─────────────────────────────────────────────────────────────────────────────

    updateFieldOrderFlags() {
        if (!this.currentForm.fields) return;
        const len = this.currentForm.fields.length;
        this.currentForm.fields.forEach((f, idx) => {
            f.sortOrder = idx + 1;
            f.isFirst = idx === 0;
            f.isLast = idx === len - 1;
        });
    }

    handleMoveFieldUp(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        if (index > 0) {
            const temp = this.currentForm.fields[index];
            this.currentForm.fields[index] = this.currentForm.fields[index - 1];
            this.currentForm.fields[index - 1] = temp;
            this.updateFieldOrderFlags();
        }
    }

    handleMoveFieldDown(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        if (index < this.currentForm.fields.length - 1) {
            const temp = this.currentForm.fields[index];
            this.currentForm.fields[index] = this.currentForm.fields[index + 1];
            this.currentForm.fields[index + 1] = temp;
            this.updateFieldOrderFlags();
        }
    }

    handleFieldPropertyChange(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        const prop = event.currentTarget.dataset.field;
        const val = event.target.type === 'checkbox' ? event.target.checked : event.target.value;
        this.currentForm.fields[index][prop] = val;
    }

    handleRemoveField(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        this.currentForm.fields.splice(index, 1);
        this.updateFieldOrderFlags();
    }

    // Add Field Drawer
    handleOpenAddFieldDrawer() {
        this.fieldSearchKey = '';
        this.isAddFieldModalOpen = true;
    }

    handleCloseAddFieldModal() {
        this.isAddFieldModalOpen = false;
    }

    handleFieldSearchChange(event) {
        this.fieldSearchKey = event.target.value;
    }

    handleAddFieldToForm(event) {
        const apiName = event.currentTarget.dataset.apiName;
        const meta = this.rawData.availableLeadFields.find(f => f.apiName === apiName);
        if (!meta) return;

        let detectedType = 'text';
        if (meta.type === 'email') detectedType = 'email';
        else if (meta.type === 'phone') detectedType = 'tel';
        else if (meta.type === 'double' || meta.type === 'integer' || meta.type === 'currency') detectedType = 'number';
        else if (meta.type === 'date' || meta.type === 'datetime') detectedType = 'date';
        else if (meta.type === 'picklist') detectedType = 'picklist';
        else if (meta.type === 'textarea') detectedType = 'textarea';

        if (apiName === 'Preferred_Programme__c' || apiName === 'Programme_Interested_in__c') {
            detectedType = 'programme_picklist';
        }

        let picklistOptionsStr = '';
        if (meta.picklistValues && meta.picklistValues.length > 0) {
            picklistOptionsStr = meta.picklistValues.map(p => p.label).join('\n');
        }

        this.currentForm.fields.push({
            developerName: '',
            sfApiName: meta.apiName,
            formLabel: meta.label,
            fieldType: detectedType,
            isRequired: false,
            placeholderText: meta.inlineHelp || '',
            helpText: '',
            fieldOptions: picklistOptionsStr,
            fullWidth: detectedType === 'textarea',
            isNumeric: detectedType === 'number',
            isInteger: meta.type === 'integer',
            isHidden: false,
            defaultValue: '',
            sortOrder: this.currentForm.fields.length + 1
        });

        this.updateFieldOrderFlags();
        this.showToast('Field Added', `Added ${meta.label} to form fields`, 'success');
    }

    // Advanced Field Config Modal
    handleOpenFieldConfigModal(event) {
        this.activeFieldConfigIndex = parseInt(event.currentTarget.dataset.index, 10);
        this.activeFieldConfig = JSON.parse(JSON.stringify(this.currentForm.fields[this.activeFieldConfigIndex]));
        this.isFieldConfigModalOpen = true;
    }

    handleCloseFieldConfigModal() {
        if (this.activeFieldConfigIndex >= 0) {
            this.currentForm.fields[this.activeFieldConfigIndex] = this.activeFieldConfig;
        }
        this.isFieldConfigModalOpen = false;
    }

    handleActiveFieldPropChange(event) {
        const prop = event.currentTarget.dataset.field;
        const val = event.target.type === 'checkbox' ? event.target.checked : event.target.value;
        this.activeFieldConfig[prop] = val;
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // SAVE & METADATA DEPLOY
    // ─────────────────────────────────────────────────────────────────────────────

    handleSaveForm() {
        if (!this.currentForm.formName || !this.currentForm.formSlug || !this.currentForm.departmentCode) {
            this.showToast('Validation Error', 'Please enter Department, Form Name, and URL Slug', 'error');
            return;
        }

        this.isLoading = true;

        const formJSON = JSON.stringify({
            developerName: this.currentForm.developerName,
            masterLabel: this.currentForm.formName,
            departmentCode: this.currentForm.departmentCode,
            formName: this.currentForm.formName,
            formSubtitle: this.currentForm.formSubtitle,
            formIcon: this.currentForm.formIcon,
            formSlug: this.currentForm.formSlug,
            sectionLabel: this.currentForm.sectionLabel,
            leadRecordTypeName: this.currentForm.leadRecordTypeName,
            typeOfForm: this.currentForm.typeOfForm,
            sortOrder: this.currentForm.sortOrder
        });

        const fieldsJSON = JSON.stringify(this.currentForm.fields);

        saveForm({ formJSON, fieldsJSON })
            .then(result => {
                this.isLoading = false;
                if (result.success) {
                    this.isEditorOpen = false;
                    this.showToast(
                        'Deployment Enqueued',
                        'Form metadata and field configurations are being deployed. Updating list...',
                        'success'
                    );
                    this.loadDashboard();
                    // eslint-disable-next-line @lwc/lwc/no-async-operation
                    setTimeout(() => {
                        this.loadDashboard();
                    }, 2500);
                } else {
                    this.showToast('Deploy Error', result.error || 'Failed to save metadata', 'error');
                }
            })
            .catch(error => {
                this.isLoading = false;
                this.showToast('Server Error', error.body?.message || error.message, 'error');
            });
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // CAMPAIGN URL & QR GENERATOR
    // ─────────────────────────────────────────────────────────────────────────────

    handleOpenUrlModal(event) {
        const formDevName = event.currentTarget.dataset.formName;
        const target = this.rawData.forms.find(f => f.developerName === formDevName);
        if (!target) return;

        this.selectedFormForUrl = target;
        this.urlParams = {
            utmSource: 'webinar',
            utmMedium: 'social',
            utmCampaign: target.formSlug ? target.formSlug.replace(/-/g, '_') : '',
            utmContent: '',
            isEmbed: false
        };
        this.isUrlModalOpen = true;
    }

    handleCloseUrlModal() {
        this.isUrlModalOpen = false;
    }

    handlePresetSourceSelect(event) {
        this.urlParams = {
            ...this.urlParams,
            utmSource: event.detail.value
        };
    }

    handlePresetMediumSelect(event) {
        this.urlParams = {
            ...this.urlParams,
            utmMedium: event.detail.value
        };
    }

    handleUrlParamChange(event) {
        const param = event.currentTarget.dataset.param;
        const val = event.target.type === 'checkbox' ? event.target.checked : event.target.value;
        this.urlParams = {
            ...this.urlParams,
            [param]: val
        };
    }

    get generatedFullUrl() {
        const base = this.rawData.siteBaseUrl || '/admissions';
        const dept = (this.selectedFormForUrl.departmentCode || '').toLowerCase();
        const slug = (this.selectedFormForUrl.formSlug || '').toLowerCase();

        const params = [];
        if (dept) params.push(`dept=${encodeURIComponent(dept)}`);
        if (slug) params.push(`form=${encodeURIComponent(slug)}`);
        if (this.urlParams.utmSource) params.push(`utm_source=${encodeURIComponent(this.urlParams.utmSource)}`);
        if (this.urlParams.utmMedium) params.push(`utm_medium=${encodeURIComponent(this.urlParams.utmMedium)}`);
        if (this.urlParams.utmCampaign) params.push(`utm_campaign=${encodeURIComponent(this.urlParams.utmCampaign)}`);
        if (this.urlParams.utmContent) params.push(`utm_content=${encodeURIComponent(this.urlParams.utmContent)}`);
        if (this.urlParams.isEmbed) params.push('embed=1');

        const queryString = params.length > 0 ? `?${params.join('&')}` : '';
        return `${base}${queryString}`;
    }

    handleCopyGeneratedUrl() {
        const url = this.generatedFullUrl;
        if (navigator.clipboard) {
            navigator.clipboard.writeText(url)
                .then(() => {
                    this.showToast('Copied!', 'Campaign URL copied to clipboard', 'success');
                })
                .catch(() => {
                    this.fallbackCopy(url);
                });
        } else {
            this.fallbackCopy(url);
        }
    }

    fallbackCopy(text) {
        const textArea = document.createElement('textarea');
        textArea.value = text;
        textArea.style.position = 'fixed';
        document.body.appendChild(textArea);
        textArea.focus();
        textArea.select();
        try {
            document.execCommand('copy');
            this.showToast('Copied!', 'Campaign URL copied to clipboard', 'success');
        } catch (err) {
            this.showToast('Copy Failed', 'Please manually copy the URL text', 'warning');
        }
        document.body.removeChild(textArea);
    }

    handleTestFormUrl() {
        window.open(this.generatedFullUrl, '_blank');
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // DELETE FORM HANDLERS
    // ─────────────────────────────────────────────────────────────────────────────

    handleOpenDeleteConfirm(event) {
        const formDevName = event.currentTarget.dataset.formName;
        const target = this.rawData.forms.find(f => f.developerName === formDevName);
        if (!target) return;

        this.formToDelete = target;
        this.isDeleteModalOpen = true;
    }

    handleCloseDeleteConfirm() {
        this.isDeleteModalOpen = false;
        this.formToDelete = {};
    }

    handleConfirmDeleteForm() {
        if (!this.formToDelete.developerName) return;

        const formName = this.formToDelete.formName || this.formToDelete.developerName;
        this.isLoading = true;
        this.isDeleteModalOpen = false;

        deleteForm({
            formDeveloperName: this.formToDelete.developerName,
            formSlug: this.formToDelete.formSlug,
            departmentCode: this.formToDelete.departmentCode
        })
            .then(result => {
                this.isLoading = false;
                if (result.success) {
                    this.showToast('Form Deleted', `Successfully deleted form "${formName}"`, 'success');
                    this.loadDashboard();
                } else {
                    this.showToast('Delete Failed', result.error || 'Could not delete form metadata', 'error');
                }
            })
            .catch(error => {
                this.isLoading = false;
                this.showToast('Server Error', error.body?.message || error.message, 'error');
            });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({
            title,
            message,
            variant: variant || 'info'
        }));
    }
}