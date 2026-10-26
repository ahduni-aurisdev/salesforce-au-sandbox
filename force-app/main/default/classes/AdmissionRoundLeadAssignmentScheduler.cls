/**
 * @description Event-driven Scheduled Apex launcher for pending Lead assignment.
 * @author AU Development Team
 * @date 2026-10-19
 * @version 1.0
 * @lastModified 2026-10-19
 */
global without sharing class AdmissionRoundLeadAssignmentScheduler implements Schedulable {
    private static final Integer BATCH_SIZE = 200;
    @TestVisible private static Boolean forceSchedulingInTest = false;
    @TestVisible private static Integer scheduleRequestCount = 0;

    global void execute(SchedulableContext context) {
        try {
            Database.executeBatch(new AdmissionRoundLeadAssignmentBatch(), BATCH_SIZE);
        } catch (Exception exceptionValue) {
            AdmissionRoundAssignmentService.logUnexpected('AdmissionRoundLeadAssignmentScheduler', exceptionValue.getMessage(), null);
        }
    }

    public static void scheduleAfterCommit() {
        scheduleRequestCount++;
        if (Test.isRunningTest() && !forceSchedulingInTest) return;
        Datetime runAt = Datetime.now().addMinutes(1);
        String cronExpression = runAt.second() + ' ' + runAt.minute() + ' ' + runAt.hour() + ' ' +
            runAt.day() + ' ' + runAt.month() + ' ? ' + runAt.year();
        String jobName = 'Admission Round Lead Assignment ' + runAt.getTime();
        System.schedule(jobName, cronExpression, new AdmissionRoundLeadAssignmentScheduler());
    }
}
