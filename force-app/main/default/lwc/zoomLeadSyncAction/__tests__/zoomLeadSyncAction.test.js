import { createElement } from 'lwc';
import ZoomLeadSyncAction from 'c/zoomLeadSyncAction';
import ZoomLeadSyncModal from 'c/zoomLeadSyncModal';

jest.mock('c/zoomLeadSyncModal', () => ({ __esModule: true, default: { open: jest.fn() } }));

const SESSION_ID = 'a1Bxx0000000001AAA';

describe('c-zoom-lead-sync-action', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('opens the large modal for the session and refreshes the page after a sync', async () => {
        ZoomLeadSyncModal.open.mockResolvedValue('synced');
        const element = createElement('c-zoom-lead-sync-action', { is: ZoomLeadSyncAction });
        element.recordId = SESSION_ID;
        const refresh = jest.fn();
        element.addEventListener('lightning__refreshevent', refresh);
        document.body.appendChild(element);

        await element.invoke();

        expect(ZoomLeadSyncModal.open).toHaveBeenCalledWith(expect.objectContaining({ size: 'large', recordId: SESSION_ID }));
        expect(refresh).toHaveBeenCalledTimes(1);
    });

    it('does not refresh when the modal is cancelled', async () => {
        ZoomLeadSyncModal.open.mockResolvedValue('cancelled');
        const element = createElement('c-zoom-lead-sync-action', { is: ZoomLeadSyncAction });
        element.recordId = SESSION_ID;
        const refresh = jest.fn();
        element.addEventListener('lightning__refreshevent', refresh);
        document.body.appendChild(element);

        await element.invoke();

        expect(refresh).not.toHaveBeenCalled();
    });
});
