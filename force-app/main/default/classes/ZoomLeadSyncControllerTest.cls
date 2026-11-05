/**
 * @description Tests for ZoomLeadSyncController ("Sync Leads to Salesforce"): popup context, starting a sync for a
 *              Masters and an Undergraduation session, per-student programmes for 200 students, the session lock,
 *              locked Department / Admission Year, retries of failed students, permission and feature-flag checks,
 *              every validation message and the save-failure rollback. Runs as a user holding permission set
 *              Zoom_Webinar_Full_Access (custom permission Zoom_Sync_Leads).
 * @author AU Development Team
 * @date 2026-11-05
 * @version 1.0
 * @lastModified 2026-11-05
 */
@IsTest
private class ZoomLeadSyncControllerTest {
    private static final Integer BULK_SIZE = 200;
    private static final String ZOOM_ID = '555000555';
    private static final String MASTERS = 'Masters';
    private static final String UNDERGRADUATION = 'Undergraduation';
    private static final String YEAR = 'Admission Year - 2026';
    private static final String OTHER_YEAR = 'Admission Year - 2027';
    private static final String MBA = 'Master of Business Administration';
    private static final String ECONOMICS = 'Master of Science in Economics';
    private static final String PENDING = 'Pending setup';
    private static final String PERMISSION_SET = 'Zoom_Webinar_Full_Access';
    private static final String USER_DOMAIN = '@zoomsync.test';

    @TestSetup
    static void createData() {
        Zoom_Webinar__c session = new Zoom_Webinar__c(Name = 'Open House', Webinar_Id__c = ZOOM_ID, Type__c = 'Meeting',
            Status__c = 'Scheduled', Start_Time__c = Datetime.now().addDays(2));
        insert session;
        List<Zoom_Registration__c> registrations = new List<Zoom_Registration__c>();
        for (Integer i = 0; i < BULK_SIZE; i++) {
            registrations.add(new Zoom_Registration__c(Webinar__c = session.Id, Registration_Key__c = ZOOM_ID + '|' + i,
                First_Name__c = 'Student', Last_Name__c = String.valueOf(1000 + i), Email__c = 'student' + i + '@zoomsync.test',
                Phone__c = '98' + String.valueOf(10000000 + i), Is_Registered__c = Math.mod(i, 2) == 0, Lead_Status__c = PENDING));
        }
        insert registrations;
    }

    /** A user with or without the Zoom permission set; setup DML isolated in runAs to avoid mixed DML. */
    private static User createUser(Boolean withPermissionSet, String alias) {
        User created;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            String unique = alias + '.' + Math.abs(Crypto.getRandomInteger());
            created = new User(LastName = 'Sync ' + alias, Alias = alias, Email = unique + USER_DOMAIN, Username = unique + USER_DOMAIN,
                ProfileId = UserInfo.getProfileId(), TimeZoneSidKey = 'Asia/Kolkata', LocaleSidKey = 'en_IN',
                EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US');
            insert created;
            if (withPermissionSet) {
                insert new PermissionSetAssignment(AssigneeId = created.Id,
                    PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = :PERMISSION_SET].Id);
            }
        }
        return created;
    }

    private static void configure(String undergraduationOwnerUsername) {
        ZoomConfig.testOverride = new Zoom_Config__mdt(Create_Activities__c = true, UG_Lead_Owner_Username__c = undergraduationOwnerUsername,
            Default_Admission_Year__c = ' ' + OTHER_YEAR + ' ');
        FeatureFlagService.testOverrides.put('Zoom_Integration', true);
    }

    private static Zoom_Webinar__c session() {
        return [SELECT Id, Department__c, Admission_Year__c, Lead_Sync_Started_At__c, Last_Lead_Sync_By__c
            FROM Zoom_Webinar__c WHERE Webinar_Id__c = :ZOOM_ID];
    }

    private static List<ZoomLeadSyncController.StudentProgramme> choices(List<Zoom_Registration__c> registrations, String programme) {
        List<ZoomLeadSyncController.StudentProgramme> result = new List<ZoomLeadSyncController.StudentProgramme>();
        for (Zoom_Registration__c registration : registrations) {
            ZoomLeadSyncController.StudentProgramme choice = new ZoomLeadSyncController.StudentProgramme();
            choice.registrationId = registration.Id;
            choice.programme = programme;
            result.add(choice);
        }
        return result;
    }

    /** Runs startSync and returns the error message, or null when it did not throw. */
    private static String startError(Id sessionId, String department, String year, List<ZoomLeadSyncController.StudentProgramme> programmes) {
        try {
            ZoomLeadSyncController.startSync(sessionId, department, year, programmes);
        } catch (AuraHandledException e) {
            return e.getMessage();
        }
        return null;
    }

    private static void setStatuses(String status, Integer count) {
        List<Zoom_Registration__c> registrations = [SELECT Id FROM Zoom_Registration__c ORDER BY Last_Name__c LIMIT :count];
        for (Zoom_Registration__c registration : registrations) {
            registration.Lead_Status__c = status;
        }
        update registrations;
    }

    @IsTest
    static void contextListsStudentsDepartmentsAndCounts() {
        User syncUser = createUser(true, 'zsync1');
        User owner = createUser(false, 'zown1');
        configure(owner.Username);
        ZoomLeadSyncController.SyncContext context;

        Test.startTest();
        System.runAs(syncUser) {
            context = ZoomLeadSyncController.getSyncContext(session().Id);
        }
        Test.stopTest();

        System.assertEquals(BULK_SIZE, context.students.size(), 'All 200 not-synced students must be listed');
        System.assertEquals(BULK_SIZE, context.progress.notSynced, 'The not-synced count must be 200');
        System.assertEquals(BULK_SIZE, context.progress.total, 'The total must be 200');
        System.assert(context.canSync, 'A user with the permission set must be allowed to sync');
        System.assertEquals(null, context.blockedReason, 'Nothing may block an allowed user');
        System.assert(!context.isLocked, 'A session with no synced student must not be locked');
        System.assertEquals('Sync zown1', context.undergraduationOwnerName, 'The configured Undergraduation owner must be shown');
        System.assertEquals(OTHER_YEAR, context.defaultAdmissionYear, 'The Zoom Config default year must be offered (trimmed)');
        System.assertEquals('Student 1000', context.students[0].name, 'Students must be sorted by name and shown with their full name');
        System.assertEquals('Registered', context.students[0].participation, 'A registrant must be labelled Registered');
        System.assertEquals('Walk-in', context.students[1].participation, 'A participant without registration must be labelled Walk-in');
        Boolean hasUndergraduation = false;
        for (ZoomLeadSyncController.DepartmentOption option : context.departments) {
            System.assertNotEquals(null, option.recordTypeId, 'Every department must carry its Lead record type');
            if (option.value == UNDERGRADUATION) {
                hasUndergraduation = option.isUndergraduation;
            }
        }
        System.assert(hasUndergraduation, 'Undergraduation must be offered and flagged');
    }

    @IsTest
    static void startSyncForMastersSavesProgrammesForAll200AndStartsJob() {
        User syncUser = createUser(true, 'zsync2');
        configure(null);
        Zoom_Webinar__c target = session();
        List<Zoom_Registration__c> registrations = [SELECT Id FROM Zoom_Registration__c ORDER BY Last_Name__c];
        List<ZoomLeadSyncController.StudentProgramme> programmes = choices(registrations, MBA);
        programmes[0].programme = ECONOMICS;
        programmes[1].programme = ' ';
        ZoomLeadSyncController.StartResult result;

        Test.startTest();
        System.runAs(syncUser) {
            result = ZoomLeadSyncController.startSync(target.Id, MASTERS, YEAR, programmes);
        }
        Test.stopTest();

        System.assert(result.started, 'The sync must start');
        System.assert(result.progress.isRunning, 'The returned progress must show the sync as running');
        Zoom_Webinar__c after = session();
        System.assertEquals(MASTERS, after.Department__c, 'The chosen Department must be saved on the session');
        System.assertEquals(YEAR, after.Admission_Year__c, 'The chosen Admission Year must be saved on the session');
        System.assertNotEquals(null, after.Lead_Sync_Started_At__c, 'The session must be locked while the sync runs');
        System.assertEquals(syncUser.Id, after.Last_Lead_Sync_By__c, 'The user who started the sync must be recorded');
        System.assertEquals(BULK_SIZE - 2, [SELECT COUNT() FROM Zoom_Registration__c WHERE Preferred_Programme__c = :MBA],
            'The bulk-applied programme must be saved for every chosen student');
        System.assertEquals(ECONOMICS, [SELECT Preferred_Programme__c FROM Zoom_Registration__c WHERE Id = :registrations[0].Id].Preferred_Programme__c,
            'A single student can get a different programme');
        System.assertEquals(null, [SELECT Preferred_Programme__c FROM Zoom_Registration__c WHERE Id = :registrations[1].Id].Preferred_Programme__c,
            'A blank choice must leave the programme empty');
        System.assertEquals(1, ZoomLeadQueueable.enqueuedJobs.size(), 'Exactly one background job must start');
        System.assertEquals(target.Id, ZoomLeadQueueable.enqueuedJobs[0].sessionId, 'The job must be for this session only');
    }

    @IsTest
    static void undergraduationSyncIgnoresProgrammesAndNeedsOwner() {
        User syncUser = createUser(true, 'zsync3');
        User owner = createUser(false, 'zown3');
        configure(null);
        Zoom_Webinar__c target = session();
        List<ZoomLeadSyncController.StudentProgramme> programmes =
            choices([SELECT Id FROM Zoom_Registration__c LIMIT 5], MBA);
        String missingOwnerError;
        ZoomLeadSyncController.StartResult result;

        Test.startTest();
        System.runAs(syncUser) {
            missingOwnerError = startError(target.Id, UNDERGRADUATION, YEAR, programmes);
            ZoomConfig.testOverride.UG_Lead_Owner_Username__c = owner.Username;
            result = ZoomLeadSyncController.startSync(target.Id, UNDERGRADUATION, YEAR, programmes);
        }
        Test.stopTest();

        System.assertEquals(ZoomLeadSyncController.MSG_UG_OWNER_MISSING, missingOwnerError,
            'Undergraduation sync must be blocked while the owner is not configured');
        System.assert(result.started, 'Undergraduation sync must start once the owner is configured');
        System.assertEquals(0, [SELECT COUNT() FROM Zoom_Registration__c WHERE Preferred_Programme__c != null],
            'Undergraduation students must never get a programme');
        System.assertEquals(UNDERGRADUATION, session().Department__c, 'Undergraduation must be saved on the session');
    }

    @IsTest
    static void runningSyncBlocksSecondStartUntilStale() {
        User syncUser = createUser(true, 'zsync4');
        configure(null);
        Zoom_Webinar__c target = session();
        target.Lead_Sync_Started_At__c = Datetime.now().addMinutes(-5);
        update target;
        String runningError;
        ZoomLeadSyncController.StartResult staleResult;
        ZoomLeadSyncController.SyncProgress progress;

        Test.startTest();
        System.runAs(syncUser) {
            runningError = startError(target.Id, MASTERS, YEAR, null);
            progress = ZoomLeadSyncController.getSyncProgress(target.Id);
            target.Lead_Sync_Started_At__c = Datetime.now().addMinutes(-(ZoomLeadSyncController.STALE_MINUTES + 1));
            update target;
            staleResult = ZoomLeadSyncController.startSync(target.Id, MASTERS, YEAR, null);
        }
        Test.stopTest();

        System.assertEquals(ZoomLeadSyncController.MSG_RUNNING, runningError, 'A second sync must not start while one runs');
        System.assert(progress.isRunning, 'Progress must report the running sync');
        System.assert(staleResult.started, 'A lock older than the stale limit must not block a new sync');
    }

    @IsTest
    static void lockedDepartmentAndYearCannotChange() {
        User syncUser = createUser(true, 'zsync5');
        configure(null);
        Zoom_Webinar__c target = session();
        target.Department__c = MASTERS;
        target.Admission_Year__c = YEAR;
        update target;
        setStatuses('Lead created', 10);
        String departmentError;
        String yearError;
        ZoomLeadSyncController.StartResult sameResult;
        ZoomLeadSyncController.SyncContext context;

        Test.startTest();
        System.runAs(syncUser) {
            context = ZoomLeadSyncController.getSyncContext(target.Id);
            departmentError = startError(target.Id, 'Phd', YEAR, null);
            yearError = startError(target.Id, MASTERS, OTHER_YEAR, null);
            sameResult = ZoomLeadSyncController.startSync(target.Id, MASTERS, YEAR, null);
        }
        Test.stopTest();

        System.assert(context.isLocked, 'A session with synced students must be shown as locked');
        System.assertEquals(BULK_SIZE - 10, context.students.size(), 'Synced students must not be listed again');
        System.assertEquals(ZoomLeadSyncController.MSG_LOCKED, departmentError, 'The Department must not change after a sync');
        System.assertEquals(ZoomLeadSyncController.MSG_LOCKED, yearError, 'The Admission Year must not change after a sync');
        System.assert(sameResult.started, 'Syncing new students with the same Department and Year must work');
    }

    @IsTest
    static void failedStudentsAreRetried() {
        User syncUser = createUser(true, 'zsync6');
        configure(null);
        setStatuses('Lead created', BULK_SIZE);
        setStatuses('Error', 3);
        Zoom_Webinar__c target = session();
        target.Department__c = MASTERS;
        target.Admission_Year__c = YEAR;
        update target;
        ZoomLeadSyncController.SyncContext context;
        ZoomLeadSyncController.StartResult result;

        Test.startTest();
        System.runAs(syncUser) {
            context = ZoomLeadSyncController.getSyncContext(target.Id);
            result = ZoomLeadSyncController.startSync(target.Id, MASTERS, YEAR, null);
        }
        Test.stopTest();

        System.assertEquals(3, context.students.size(), 'Failed students must be listed for retry');
        System.assert(context.students[0].hasError, 'A failed student must be flagged');
        System.assert(result.started, 'A retry must start');
        System.assertEquals(3, [SELECT COUNT() FROM Zoom_Registration__c WHERE Lead_Status__c = :PENDING],
            'Failed students must be set back to Not synced so the job retries them');
    }

    @IsTest
    static void nothingToSyncUntilAttendanceIsDue() {
        User syncUser = createUser(true, 'zsync7');
        configure(null);
        Zoom_Webinar__c target = session();
        target.Department__c = MASTERS;
        target.Admission_Year__c = YEAR;
        update target;
        Lead linked = new Lead(LastName = 'Linked', Email = 'linked@zoomsync.test',
            RecordTypeId = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get(MASTERS).getRecordTypeId(), Admission_Year__c = YEAR);
        insert linked;
        List<Zoom_Registration__c> registrations = [SELECT Id FROM Zoom_Registration__c];
        for (Zoom_Registration__c registration : registrations) {
            registration.Lead_Status__c = 'Lead updated';
            registration.Lead__c = linked.Id;
        }
        update registrations;
        String nothingError;
        ZoomLeadSyncController.StartResult attendanceResult;

        Test.startTest();
        System.runAs(syncUser) {
            nothingError = startError(target.Id, MASTERS, YEAR, null);
            target.Status__c = 'Ended';
            update target;
            attendanceResult = ZoomLeadSyncController.startSync(target.Id, MASTERS, YEAR, null);
        }
        Test.stopTest();

        System.assertEquals(ZoomLeadSyncController.MSG_NOTHING_TO_SYNC, nothingError, 'With every student synced there is nothing to do before the end');
        System.assert(attendanceResult.started, 'After the session ends the same button must log attendance');
        System.assertEquals(BULK_SIZE / 2, attendanceResult.progress.attendancePending,
            'Registered students without an attendance Task must be counted');
    }

    @IsTest
    static void invalidChoicesAreRejectedWithReadableMessages() {
        User syncUser = createUser(true, 'zsync8');
        configure(null);
        Zoom_Webinar__c target = session();
        Zoom_Webinar__c otherSession = new Zoom_Webinar__c(Name = 'Other', Webinar_Id__c = '1', Type__c = 'Meeting');
        insert otherSession;
        Zoom_Registration__c foreign = new Zoom_Registration__c(Webinar__c = otherSession.Id, Registration_Key__c = '1|x',
            Lead_Status__c = PENDING);
        insert foreign;
        List<ZoomLeadSyncController.StudentProgramme> badProgramme = choices([SELECT Id FROM Zoom_Registration__c WHERE Webinar__c = :target.Id LIMIT 1], 'Not A Programme');
        List<ZoomLeadSyncController.StudentProgramme> foreignStudent = choices(new List<Zoom_Registration__c>{ foreign }, MBA);
        Map<String, String> errors = new Map<String, String>();

        Test.startTest();
        System.runAs(syncUser) {
            errors.put('department', startError(target.Id, 'Not A Department', YEAR, null));
            errors.put('year', startError(target.Id, MASTERS, 'Admission Year - 1999', null));
            errors.put('programme', startError(target.Id, MASTERS, YEAR, badProgramme));
            errors.put('student', startError(target.Id, MASTERS, YEAR, foreignStudent));
            errors.put('session', startError(null, MASTERS, YEAR, null));
            try {
                ZoomLeadSyncController.getSyncContext(null);
            } catch (AuraHandledException e) {
                errors.put('context', e.getMessage());
            }
            try {
                ZoomLeadSyncController.getSyncProgress(null);
            } catch (AuraHandledException e) {
                errors.put('progress', e.getMessage());
            }
        }
        Test.stopTest();

        System.assertEquals(ZoomLeadSyncController.MSG_DEPARTMENT_REQUIRED, errors.get('department'), 'An unknown Department must be rejected');
        System.assertEquals(ZoomLeadSyncController.MSG_YEAR_REQUIRED, errors.get('year'), 'A year that is not a Lead year must be rejected');
        System.assertEquals(ZoomLeadSyncController.MSG_INVALID_PROGRAMME, errors.get('programme'), 'A programme that is not a Lead programme must be rejected');
        System.assertEquals(ZoomLeadSyncController.MSG_INVALID_STUDENT, errors.get('student'), 'A student of another session must be rejected');
        System.assertEquals(ZoomLeadSyncController.MSG_SESSION_NOT_FOUND, errors.get('session'), 'A missing session must be reported');
        System.assertEquals(ZoomLeadSyncController.MSG_SESSION_NOT_FOUND, errors.get('context'), 'A missing session must be reported when loading');
        System.assertEquals(ZoomLeadSyncController.MSG_SESSION_NOT_FOUND, errors.get('progress'), 'A missing session must be reported for progress');
        System.assertEquals(null, session().Department__c, 'A rejected sync must not save anything');
        System.assert(ZoomLeadQueueable.enqueuedJobs.isEmpty(), 'A rejected sync must not start a job');
    }

    @IsTest
    static void userWithoutPermissionIsBlocked() {
        User plainUser = createUser(false, 'zsync9');
        configure(null);
        Id sessionId = session().Id;
        ZoomLeadSyncController.SyncContext context;
        String error;

        Test.startTest();
        System.runAs(plainUser) {
            context = ZoomLeadSyncController.getSyncContext(sessionId);
            error = startError(sessionId, MASTERS, YEAR, null);
        }
        Test.stopTest();

        System.assert(!context.canSync, 'A user without the custom permission must not be allowed to sync');
        System.assertEquals(ZoomLeadSyncController.MSG_NO_PERMISSION, context.blockedReason, 'The popup must say why');
        System.assertEquals(ZoomLeadSyncController.MSG_NO_PERMISSION, error, 'startSync must refuse without the permission');
    }

    @IsTest
    static void integrationSwitchedOffIsBlocked() {
        User syncUser = createUser(true, 'zsync10');
        configure(null);
        ZoomConfig.testOverride.Default_Admission_Year__c = 'Admission Year - 1999';
        FeatureFlagService.testOverrides.put('Zoom_Integration', false);
        Id sessionId = session().Id;
        ZoomLeadSyncController.SyncContext context;
        String error;

        Test.startTest();
        System.runAs(syncUser) {
            context = ZoomLeadSyncController.getSyncContext(sessionId);
            error = startError(sessionId, MASTERS, YEAR, null);
        }
        Test.stopTest();

        System.assertEquals(ZoomLeadSyncController.MSG_INTEGRATION_OFF, context.blockedReason, 'The popup must say the integration is off');
        System.assertEquals(null, context.defaultAdmissionYear, 'A configured year that is not a Lead year must not be offered');
        System.assertEquals(ZoomLeadSyncController.MSG_INTEGRATION_OFF, error, 'startSync must refuse while the integration is off');
    }

    @IsTest
    static void syncResultsListProcessedStudentsWithTheirLeadFailedFirst() {
        User syncUser = createUser(true, 'zsync12');
        configure(null);
        Zoom_Webinar__c target = session();
        Lead lead = new Lead(LastName = 'Result Lead', Email = 'result@zoomsync.test', Preferred_Programme__c = MBA,
            RecordTypeId = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get(MASTERS).getRecordTypeId(), Admission_Year__c = YEAR);
        insert lead;
        List<Zoom_Registration__c> registrations = [SELECT Id FROM Zoom_Registration__c ORDER BY Last_Name__c LIMIT 3];
        registrations[0].Lead_Status__c = 'Lead created';
        registrations[0].Lead__c = lead.Id;
        registrations[1].Lead_Status__c = 'Error';
        registrations[2].Lead_Status__c = 'No contact details';
        update registrations;
        List<ZoomLeadSyncController.SyncResult> results;
        List<ZoomLeadSyncController.SyncResult> sinceNow;
        String noPermissionError;

        Test.startTest();
        System.runAs(syncUser) {
            results = ZoomLeadSyncController.getSyncResults(target.Id, null);
            sinceNow = ZoomLeadSyncController.getSyncResults(target.Id, Datetime.now().addDays(1));
        }
        System.runAs(createUser(false, 'zsync13')) {
            try {
                ZoomLeadSyncController.getSyncResults(target.Id, null);
            } catch (AuraHandledException e) {
                noPermissionError = e.getMessage();
            }
        }
        Test.stopTest();

        System.assertEquals(3, results.size(), 'Only processed students must be listed, never Not synced ones');
        System.assertEquals('Error', results[0].result, 'Failed students must be listed first');
        ZoomLeadSyncController.SyncResult created;
        for (ZoomLeadSyncController.SyncResult row : results) {
            if (row.leadId != null) {
                created = row;
            }
        }
        System.assertEquals(lead.Id, created.leadId, 'The linked Lead must be returned');
        System.assertEquals('Result Lead', created.leadName, 'The Lead name must be returned');
        System.assertEquals(MBA, created.programme, 'The Lead programme must be returned');
        System.assertNotEquals(null, created.ownerName, 'The Lead owner must be returned');
        System.assertEquals('Registered', created.participation, 'The participation must be returned');
        System.assert(sinceNow.isEmpty(), 'Students not changed since the given time must be left out');
        System.assertEquals(ZoomLeadSyncController.MSG_NO_PERMISSION, noPermissionError, 'Results need the permission');
    }

    @IsTest
    static void saveFailureRollsBackLogsAndReportsNotStarted() {
        User syncUser = createUser(true, 'zsync11');
        configure(null);
        ZoomLeadSyncController.simulateSaveFailure = true;
        Id sessionId = session().Id;
        ZoomLeadSyncController.StartResult result;

        Test.startTest();
        System.runAs(syncUser) {
            result = ZoomLeadSyncController.startSync(sessionId, MASTERS, YEAR,
                choices([SELECT Id FROM Zoom_Registration__c LIMIT 3], MBA));
        }
        Test.stopTest();

        System.assert(!result.started, 'A failed save must report that the sync did not start');
        System.assertEquals(ZoomLeadSyncController.MSG_SAVE_FAILED, result.message, 'A failed save must give a readable message');
        System.assertEquals(null, session().Lead_Sync_Started_At__c, 'A failed save must not leave the session locked');
        System.assertEquals(0, [SELECT COUNT() FROM Zoom_Registration__c WHERE Preferred_Programme__c != null],
            'A failed save must not keep any programme');
        System.assertEquals(1, [SELECT COUNT() FROM API_Log__c WHERE Apex_Class_Name__c = 'ZoomLeadSyncController'],
            'A failed save must be logged once');
        System.assert(ZoomLeadQueueable.enqueuedJobs.isEmpty(), 'A failed save must not start a job');
    }
}
