import { createElement } from 'lwc';
import ZoomLeadSyncModal from 'c/zoomLeadSyncModal';
import Toast from 'lightning/toast';
import { getPicklistValuesByRecordType } from 'lightning/uiObjectInfoApi';
import getSyncContext from '@salesforce/apex/ZoomLeadSyncController.getSyncContext';
import getSyncProgress from '@salesforce/apex/ZoomLeadSyncController.getSyncProgress';
import startSync from '@salesforce/apex/ZoomLeadSyncController.startSync';

jest.mock('@salesforce/apex/ZoomLeadSyncController.getSyncContext', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/ZoomLeadSyncController.getSyncProgress', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/ZoomLeadSyncController.startSync', () => ({ default: jest.fn() }), { virtual: true });

const SESSION_ID = 'a1Bxx0000000001AAA';
const MASTERS_RT = '012xx0000000001AAA';
const UG_RT = '012xx0000000002AAA';

const PICKLISTS = {
    picklistFieldValues: {
        Admission_Year__c: {
            defaultValue: { value: 'Admission Year - 2026' },
            values: [
                { label: 'Admission Year - 2026', value: 'Admission Year - 2026' },
                { label: 'Admission Year - 2027', value: 'Admission Year - 2027' }
            ]
        },
        Preferred_Programme__c: {
            controllerValues: {},
            values: [
                { label: 'Master of Business Administration', value: 'Master of Business Administration', validFor: [] },
                { label: 'Master of Science in Economics', value: 'Master of Science in Economics', validFor: [] }
            ]
        }
    }
};

function context(overrides = {}) {
    return {
        sessionId: SESSION_ID,
        sessionName: 'Open House',
        sessionType: 'Meeting',
        sessionStatus: 'Scheduled',
        startTime: '2026-11-12T11:00:00.000Z',
        department: null,
        admissionYear: null,
        isLocked: false,
        canSync: true,
        blockedReason: null,
        undergraduationOwnerName: 'Shraddha Singaurey',
        undergraduationOwnerPhoto: null,
        lastSyncByName: null,
        defaultAdmissionYear: 'Admission Year - 2027',
        departments: [
            { label: 'Undergraduation', value: 'Undergraduation', recordTypeId: UG_RT, isUndergraduation: true },
            { label: 'Masters', value: 'Masters', recordTypeId: MASTERS_RT, isUndergraduation: false }
        ],
        students: [
            { registrationId: 'a1Cxx0000000001AAA', name: 'Asha Patel', email: 'asha@test.com', phone: '9876543210', participation: 'Registered', attended: false, programme: null, hasError: false },
            { registrationId: 'a1Cxx0000000002AAA', name: 'Ravi Shah', email: 'ravi@test.com', phone: '9876543211', participation: 'Walk-in', attended: true, programme: null, hasError: false }
        ],
        progress: { isRunning: false, hasEnded: false, total: 2, notSynced: 2, created: 0, updated: 0, noContact: 0, errors: 0, attendancePending: 0 },
        ...overrides
    };
}

async function flush() {
    for (let i = 0; i < 5; i++) {
        // eslint-disable-next-line no-await-in-loop
        await Promise.resolve();
    }
}

function mount() {
    const element = createElement('c-zoom-lead-sync-modal', { is: ZoomLeadSyncModal });
    element.recordId = SESSION_ID;
    document.body.appendChild(element);
    return element;
}

function combobox(element, name) {
    return element.shadowRoot.querySelector(`lightning-combobox[data-id="${name}"]`);
}

function buttonWithLabel(element, text) {
    return Array.from(element.shadowRoot.querySelectorAll('lightning-button')).find((button) => button.label && button.label.startsWith(text));
}

async function chooseDepartment(element, value) {
    combobox(element, 'department').dispatchEvent(new CustomEvent('change', { detail: { value } }));
    await flush();
    getPicklistValuesByRecordType.emit(PICKLISTS);
    await flush();
}

describe('c-zoom-lead-sync-modal', () => {
    let toastSpy;

    beforeEach(() => {
        toastSpy = jest.spyOn(Toast, 'show').mockImplementation(() => {});
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.restoreAllMocks();
        jest.clearAllMocks();
        jest.useRealTimers();
    });

    it('shows a spinner while loading, then the session, compact counters and students', async () => {
        let resolveContext;
        getSyncContext.mockReturnValue(new Promise((resolve) => { resolveContext = resolve; }));
        const element = mount();
        await flush();
        expect(element.shadowRoot.querySelector('lightning-spinner')).not.toBeNull();

        resolveContext(context());
        await flush();

        expect(element.shadowRoot.querySelector('lightning-spinner')).toBeNull();
        expect(element.shadowRoot.querySelector('lightning-modal-header').label).toBe('Sync Leads to Salesforce');
        expect(element.shadowRoot.textContent).toContain('Students to sync (2)');
        expect(element.shadowRoot.querySelectorAll('.stat-pill')).toHaveLength(4);
        expect(element.shadowRoot.querySelector('lightning-datatable').data).toHaveLength(2);
        expect(element.shadowRoot.querySelector('lightning-progress-indicator')).toBeNull();
    });

    it('shows a readable error with a retry button when loading fails', async () => {
        getSyncContext.mockRejectedValue({ body: { message: 'This Zoom session was not found.' } });
        const element = mount();
        await flush();

        expect(element.shadowRoot.textContent).toContain('This Zoom session was not found.');
        getSyncContext.mockResolvedValue(context());
        buttonWithLabel(element, 'Try Again').click();
        await flush();
        expect(getSyncContext).toHaveBeenCalledTimes(2);
    });

    it('preselects the Zoom Config default admission year over the Lead default', async () => {
        getSyncContext.mockResolvedValue(context());
        const element = mount();
        await flush();

        await chooseDepartment(element, 'Masters');

        expect(combobox(element, 'admissionYear').value).toBe('Admission Year - 2027');
        expect(element.shadowRoot.textContent).toContain('Masters · 2027');
    });

    it('falls back to the Lead default year when Zoom Config has none', async () => {
        getSyncContext.mockResolvedValue(context({ defaultAdmissionYear: null }));
        const element = mount();
        await flush();

        await chooseDepartment(element, 'Masters');

        expect(combobox(element, 'admissionYear').value).toBe('Admission Year - 2026');
    });

    it('applies a programme to selected students and sends it with the sync', async () => {
        getSyncContext.mockResolvedValue(context());
        startSync.mockResolvedValue({ started: true, progress: { isRunning: true, notSynced: 2, total: 2 } });
        const element = mount();
        await flush();
        await chooseDepartment(element, 'Masters');

        element.shadowRoot.querySelector('lightning-datatable').dispatchEvent(new CustomEvent('rowselection', {
            detail: { selectedRows: [{ registrationId: 'a1Cxx0000000001AAA' }] }
        }));
        combobox(element, 'bulkProgramme').dispatchEvent(new CustomEvent('change', { detail: { value: 'Master of Business Administration' } }));
        await flush();
        buttonWithLabel(element, 'Apply to').click();
        await flush();

        expect(element.shadowRoot.querySelector('lightning-datatable').data[0].programme).toBe('Master of Business Administration');

        buttonWithLabel(element, 'Sync 2 Students').click();
        await flush();

        expect(startSync).toHaveBeenCalledWith({
            sessionId: SESSION_ID,
            department: 'Masters',
            admissionYear: 'Admission Year - 2027',
            programmes: [{ registrationId: 'a1Cxx0000000001AAA', programme: 'Master of Business Administration' }]
        });
        expect(element.shadowRoot.querySelector('lightning-progress-bar')).not.toBeNull();
    });

    it('shows the Undergraduation owner and hides programme tools', async () => {
        getSyncContext.mockResolvedValue(context());
        const element = mount();
        await flush();

        await chooseDepartment(element, 'Undergraduation');

        expect(element.shadowRoot.textContent).toContain('Shraddha Singaurey');
        expect(combobox(element, 'bulkProgramme')).toBeNull();
        expect(element.shadowRoot.querySelector('lightning-datatable').hideCheckboxColumn).toBe(true);
    });

    it('blocks the sync and explains why when the user has no permission', async () => {
        getSyncContext.mockResolvedValue(context({ canSync: false, blockedReason: 'You do not have permission to sync Zoom Leads.' }));
        const element = mount();
        await flush();

        expect(element.shadowRoot.textContent).toContain('You do not have permission to sync Zoom Leads.');
        expect(buttonWithLabel(element, 'Sync 2 Students').disabled).toBe(true);
    });

    it('shows the empty state with a call to action when everyone is synced but attendance is due', async () => {
        getSyncContext.mockResolvedValue(context({
            students: [],
            department: 'Masters',
            admissionYear: 'Admission Year - 2026',
            isLocked: true,
            progress: { isRunning: false, hasEnded: true, total: 2, notSynced: 0, created: 2, updated: 0, noContact: 0, errors: 0, attendancePending: 2 }
        }));
        const element = mount();
        await flush();
        getPicklistValuesByRecordType.emit(PICKLISTS);
        await flush();

        expect(element.shadowRoot.textContent).toContain('Attendance Ready to Log');
        expect(buttonWithLabel(element, 'Log Attendance').disabled).toBe(false);
        expect(combobox(element, 'department').disabled).toBe(true);
    });

    it('polls progress until the background sync finishes and closes with synced', async () => {
        jest.useFakeTimers();
        getSyncContext.mockResolvedValue(context());
        startSync.mockResolvedValue({ started: true, progress: { isRunning: true, notSynced: 2, total: 2 } });
        getSyncProgress.mockResolvedValue({ isRunning: false, total: 2, notSynced: 0, created: 2, updated: 0, errors: 0, noContact: 0 });
        const element = mount();
        await flush();
        await chooseDepartment(element, 'Masters');
        buttonWithLabel(element, 'Sync 2 Students').click();
        await flush();

        jest.advanceTimersByTime(3000);
        await flush();

        expect(getSyncProgress).toHaveBeenCalledWith({ sessionId: SESSION_ID });
        expect(element.shadowRoot.textContent).toContain('Sync Complete');
        expect(toastSpy).toHaveBeenCalledWith(expect.objectContaining({ variant: 'success' }), expect.anything());

        const closed = jest.fn();
        element.addEventListener('modalclose', closed);
        buttonWithLabel(element, 'Done').click();
        expect(closed.mock.calls[0][0].detail).toBe('synced');
    });

    it('reports a start failure with a toast and keeps the form', async () => {
        getSyncContext.mockResolvedValue(context());
        startSync.mockRejectedValue({ body: { message: 'Select a valid admission year and try again.' } });
        const element = mount();
        await flush();
        await chooseDepartment(element, 'Masters');

        buttonWithLabel(element, 'Sync 2 Students').click();
        await flush();

        expect(toastSpy).toHaveBeenCalledWith(
            expect.objectContaining({ variant: 'error', message: 'Select a valid admission year and try again.' }), expect.anything());
        expect(element.shadowRoot.querySelector('lightning-datatable')).not.toBeNull();
    });

    it('closes as cancelled when nothing was synced', async () => {
        getSyncContext.mockResolvedValue(context());
        const element = mount();
        await flush();
        const closed = jest.fn();
        element.addEventListener('modalclose', closed);

        buttonWithLabel(element, 'Cancel').click();

        expect(closed.mock.calls[0][0].detail).toBe('cancelled');
    });
});
