/**
 * @description Runs ZoomWebinarSync every 2 hours. Start once per org: ZoomWebinarSyncScheduler.schedule();
 * @author AU Development Team
 * @date 2026-10-21
 * @version 1.1
 * @lastModified 2026-11-02
 */
public with sharing class ZoomWebinarSyncScheduler implements Schedulable {
    @TestVisible
    private static final String JOB_NAME = 'Zoom Webinar Sync';
    private static final String EVERY_TWO_HOURS = '0 0 0/2 * * ?';

    /** Tests use another name: a job name must be unique and the real job may already exist in the org. */
    @TestVisible
    private static String jobName = JOB_NAME;

    public static Id schedule() {
        return System.schedule(jobName, EVERY_TWO_HOURS, new ZoomWebinarSyncScheduler());
    }

    public void execute(SchedulableContext context) {
        System.enqueueJob(new ZoomWebinarSync());
    }
}