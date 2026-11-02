/** Runs ZoomWebinarSync every 2 hours: ZoomWebinarSyncScheduler.schedule(); */
public with sharing class ZoomWebinarSyncScheduler implements Schedulable {
    public static void schedule() {
        System.schedule('Zoom Webinar Sync', '0 0 0/2 * * ?', new ZoomWebinarSyncScheduler());
    }
    public void execute(SchedulableContext sc) { System.enqueueJob(new ZoomWebinarSync()); }
}