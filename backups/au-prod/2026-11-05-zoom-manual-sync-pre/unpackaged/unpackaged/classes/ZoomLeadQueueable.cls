/**
 * @description Lead step of the scheduled Zoom sync. ZoomWebinarSync enqueues it when its session chain finishes.
 *              Phase 1 creates / links Leads for "Pending setup" registrations whose session has a Department and
 *              Admission Year; phase 2 logs attendance Tasks for linked registrations of ended sessions.
 *              Each job handles up to BATCH_SIZE registrations and chains itself while a full batch was found.
 *              Every processed registration leaves the queried state (new Lead Status or Task ID), so the chain
 *              always ends. Runs as the user who scheduled the sync, so Leads get a real creator and owner.
 *                System.enqueueJob(new ZoomLeadQueueable());   // run the Lead step on its own
 * @author AU Development Team
 * @date 2026-11-03
 * @version 1.0
 * @lastModified 2026-11-03
 */
// System mode is intentional: a scheduled system job processing every pending Zoom registration (see ZoomLeadService).
public without sharing class ZoomLeadQueueable implements Queueable {
    @TestVisible
    private static final Integer BATCH_SIZE = 100;
    private static final String FLAG_INTEGRATION = 'Zoom_Integration';
    private static final String LOG_NAME = 'ZoomLeadService';
    private static final String CLASS_NAME = 'ZoomLeadService';
    private static final String PHASE_PENDING = 'pending';
    private static final String PHASE_ATTENDANCE = 'attendance';

    /** Jobs this run tried to enqueue; tests assert on it because Queueables cannot chain inside a test. */
    @TestVisible
    private static List<ZoomLeadQueueable> enqueuedJobs = new List<ZoomLeadQueueable>();

    @TestVisible
    private String phase = PHASE_PENDING;

    /** Test hook: makes execute fail as if a query or save failed, to exercise the logging path. */
    @TestVisible
    private static Boolean simulateFailure = false;

    public ZoomLeadQueueable() {
    }

    private ZoomLeadQueueable(String phase) {
        this.phase = phase;
    }

    public void execute(QueueableContext context) {
        if (!FeatureFlagService.isEnabled(FLAG_INTEGRATION)) {
            return;
        }
        try {
            if (Test.isRunningTest() && simulateFailure) {
                throw new DmlException('Simulated failure');
            }
            if (phase == PHASE_PENDING) {
                List<Zoom_Registration__c> pending =
                    ZoomSelector.selectPendingLeadRegistrations(ZoomLeadService.LEAD_STATUS_PENDING, BATCH_SIZE);
                ZoomLeadService.processPending(pending);
                enqueue(new ZoomLeadQueueable(pending.size() == BATCH_SIZE ? PHASE_PENDING : PHASE_ATTENDANCE));
                return;
            }
            List<Zoom_Registration__c> awaiting =
                ZoomSelector.selectRegistrationsAwaitingAttendanceTask(ZoomLeadService.LINKED_STATUSES, BATCH_SIZE);
            ZoomLeadService.processAttendance(awaiting);
            if (awaiting.size() == BATCH_SIZE) {
                enqueue(new ZoomLeadQueueable(PHASE_ATTENDANCE));
            }
        } catch (DmlException e) {
            ZoomLogger.logFailure(LOG_NAME, CLASS_NAME, phase, e);
        } catch (QueryException e) {
            ZoomLogger.logFailure(LOG_NAME, CLASS_NAME, phase, e);
        }
    }

    /** Starts the Lead step; used by ZoomWebinarSync at the end of its chain. */
    public static void start() {
        enqueue(new ZoomLeadQueueable());
    }

    private static void enqueue(ZoomLeadQueueable job) {
        enqueuedJobs.add(job);
        if (Test.isRunningTest()) {
            return;
        }
        System.enqueueJob(job);
    }
}