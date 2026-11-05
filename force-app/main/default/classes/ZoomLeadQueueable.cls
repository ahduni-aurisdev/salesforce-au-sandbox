/**
 * @description Background Lead sync for one Zoom session, started by "Sync Leads to Salesforce"
 *              (ZoomLeadSyncController). Phase 1 creates / links Leads for the session's "Not synced" registrations
 *              (API value Pending setup); phase 2 logs attendance Tasks for its linked registrations once the session
 *              has ended. Each job handles up to BATCH_SIZE registrations and chains itself while a full batch was
 *              found. Every processed registration leaves the queried state (new Lead Status or Task ID), so the
 *              chain always ends. When it ends (or fails) the session's Lead_Sync_Started_At__c is cleared and
 *              Last_Lead_Sync_At__c set, which unlocks the popup. Runs as the user who clicked, so Leads and Tasks
 *              get a real creator.
 *                System.enqueueJob(new ZoomLeadQueueable(sessionId));   // run the Lead sync for one session
 * @author AU Development Team
 * @date 2026-11-03
 * @version 2.0
 * @lastModified 2026-11-05
 */
// System mode is intentional: Lead matching must see every Lead regardless of the clicking user's sharing, otherwise
// it would create duplicates of Leads that user cannot see (see ZoomLeadService). The user's right to run the sync is
// checked by ZoomLeadSyncController (custom permission Zoom_Sync_Leads) before this job is enqueued.
public without sharing class ZoomLeadQueueable implements Queueable {
    @TestVisible
    private static final Integer BATCH_SIZE = 100;
    private static final String FLAG_INTEGRATION = 'Zoom_Integration';
    private static final String LOG_NAME = 'ZoomLeadService';
    private static final String CLASS_NAME = 'ZoomLeadService';
    @TestVisible
    private static final String PHASE_PENDING = 'pending';
    @TestVisible
    private static final String PHASE_ATTENDANCE = 'attendance';

    /** Jobs this run tried to enqueue; tests assert on it because Queueables cannot chain inside a test. */
    @TestVisible
    private static List<ZoomLeadQueueable> enqueuedJobs = new List<ZoomLeadQueueable>();

    @TestVisible
    private Id sessionId;
    @TestVisible
    private String phase = PHASE_PENDING;

    /** Test hook: makes execute fail as if a query or save failed, to exercise the logging path. */
    @TestVisible
    private static Boolean simulateFailure = false;

    public ZoomLeadQueueable(Id sessionId) {
        this.sessionId = sessionId;
    }

    private ZoomLeadQueueable(Id sessionId, String phase) {
        this.sessionId = sessionId;
        this.phase = phase;
    }

    public void execute(QueueableContext context) {
        if (sessionId == null) {
            return;
        }
        if (!FeatureFlagService.isEnabled(FLAG_INTEGRATION)) {
            finish();
            return;
        }
        try {
            if (Test.isRunningTest() && simulateFailure) {
                throw new DmlException('Simulated failure');
            }
            if (phase == PHASE_PENDING) {
                List<Zoom_Registration__c> pending =
                    ZoomSelector.selectPendingLeadRegistrations(sessionId, ZoomLeadService.LEAD_STATUS_PENDING, BATCH_SIZE);
                ZoomLeadService.processPending(pending);
                enqueue(new ZoomLeadQueueable(sessionId, pending.size() == BATCH_SIZE ? PHASE_PENDING : PHASE_ATTENDANCE));
                return;
            }
            List<Zoom_Registration__c> awaiting = ZoomSelector.selectRegistrationsAwaitingAttendanceTask(sessionId,
                ZoomLeadService.LINKED_STATUSES, BATCH_SIZE);
            ZoomLeadService.processAttendance(awaiting);
            if (awaiting.size() == BATCH_SIZE) {
                enqueue(new ZoomLeadQueueable(sessionId, PHASE_ATTENDANCE));
                return;
            }
            finish();
        } catch (DmlException e) {
            ZoomLogger.logFailure(LOG_NAME, CLASS_NAME, phase, e);
            finish();
        } catch (QueryException e) {
            ZoomLogger.logFailure(LOG_NAME, CLASS_NAME, phase, e);
            finish();
        }
    }

    /** Unlocks the session for the next sync and records when this one finished. 1 DML. */
    private void finish() {
        update new Zoom_Webinar__c(Id = sessionId, Lead_Sync_Started_At__c = null, Last_Lead_Sync_At__c = Datetime.now());
    }

    /** Starts the Lead sync of one session; used by ZoomLeadSyncController. */
    public static void start(Id sessionId) {
        enqueue(new ZoomLeadQueueable(sessionId));
    }

    private static void enqueue(ZoomLeadQueueable job) {
        enqueuedJobs.add(job);
        if (Test.isRunningTest()) {
            return;
        }
        System.enqueueJob(job);
    }
}
