public class ZoomWebinarJobScheduler {
    public static void scheduleZoomWebinarFetchJob() {
        // Cron expression: Run every day at 2 AM
        // String cronExpression = '0 0 2 * * ?';
        String cronExpression = '0 0/5 * * * ?';
        
        // Schedule the job
        System.schedule('Zoom Webinar Fetch Job', cronExpression, new ZoomWebinarSchedule());
    }
}