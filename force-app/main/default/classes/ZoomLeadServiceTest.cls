/**
 * @description Tests for ZoomLeadService and ZoomLeadQueueable: Lead matching (email + phone + Department record
 *              type + Admission Year), new Lead creation, blank-only updates, Tasks, error handling, a 200-record
 *              bulk run, queueable chaining per session and the session lock release.
 * @author AU Development Team
 * @date 2026-11-03
 *              Since v1.1: owner round-robin from Zoom_Config (User Department + Role + Profile).
 *              Since v1.2: department owner pools from LeadAssignmentRule__mdt and session Preferred Programme.
 *              Since v2.0: Lead sync per session from "Sync Leads to Salesforce"; programme per student;
 *              Undergraduation owner from Zoom_Config UG_Lead_Owner_Username__c.
 * @version 2.0
 * @lastModified 2026-11-05
 */
@IsTest
private class ZoomLeadServiceTest {
    private static final Integer BULK_SIZE = 200;
    private static final String DEPARTMENT = 'Masters';
    private static final String UNDERGRADUATION = 'Undergraduation';
    private static final String YEAR = 'Admission Year - 2026';
    private static final String OTHER_YEAR = 'Admission Year - 2027';
    private static final String ZOOM_ID = '777000777';
    private static final String TOPIC = 'Masters Info Session';
    private static final String EMAIL_DOMAIN = '@zoomlead.test';
    private static final String ORIGINAL_SOURCE = 'Website';
    private static final String PENDING = 'Pending setup';
    private static final String OWNER_DEPARTMENT = 'Zoom Owner Test Dept';
    private static final String OWNER_ROLE = 'Zoom Owner Test Role';
    private static final String NEW_EMAIL_DOMAIN = '@zoomowner.test';
    private static final String MBA = 'Master of Business Administration';
    private static final String ECONOMICS = 'Master of Science in Economics';

    @TestSetup
    static void createData() {
        Id mastersRt = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get(DEPARTMENT).getRecordTypeId();
        List<Lead> leads = new List<Lead>();
        for (Integer i = 0; i < BULK_SIZE; i++) {
            leads.add(new Lead(LastName = 'Existing ' + i, Email = emailOf(i), MobilePhone = phoneOf(i),
                RecordTypeId = mastersRt, Admission_Year__c = YEAR, LeadSource = ORIGINAL_SOURCE));
        }
        insert leads;
        insert new Zoom_Webinar__c(Name = TOPIC, Webinar_Id__c = ZOOM_ID, Type__c = 'Meeting', Status__c = 'Ended',
            Start_Time__c = Datetime.now().addDays(-1), Department__c = DEPARTMENT, Admission_Year__c = YEAR);
    }

    private static String emailOf(Integer i) {
        return 'person' + i + EMAIL_DOMAIN;
    }

    private static String phoneOf(Integer i) {
        return '98' + String.valueOf(10000000 + i);
    }

    private static void configure() {
        ZoomConfig.testOverride = new Zoom_Config__mdt(Create_Activities__c = true);
        FeatureFlagService.testOverrides.put('Zoom_Integration', true);
        ZoomLeadService.testAssignmentRules = new List<LeadAssignmentRule__mdt>();
    }

    private static Zoom_Webinar__c session() {
        return [SELECT Id FROM Zoom_Webinar__c WHERE Webinar_Id__c = :ZOOM_ID];
    }

    private static Zoom_Registration__c registration(Id sessionId, String email, String phone, String firstName,
        String lastName, Boolean registered, Boolean attended) {
        return new Zoom_Registration__c(Webinar__c = sessionId, Registration_Key__c = ZOOM_ID + '|' + (email == null ? phone + firstName : email)
            + '|' + Crypto.getRandomInteger(), Email__c = email, Phone__c = phone, First_Name__c = firstName, Last_Name__c = lastName,
            Is_Registered__c = registered, Attended__c = attended, Status__c = registered ? 'Approved' : 'Not Registered',
            Lead_Status__c = PENDING, Time_In_Session_Minutes__c = attended ? 42 : null);
    }

    private static void runPending(Id sessionId) {
        ZoomLeadService.processPending(ZoomSelector.selectPendingLeadRegistrations(sessionId, PENDING, BULK_SIZE));
    }

    private static void runPending() {
        runPending(session().Id);
    }

    private static Zoom_Registration__c reload(Id registrationId) {
        return [SELECT Lead__c, Lead_Status__c, Is_Matched__c, Registration_Task_Id__c, Attendance_Task_Id__c
            FROM Zoom_Registration__c WHERE Id = :registrationId];
    }

    @IsTest
    static void matchesExistingLeadByEmailAndPhoneAndFillsBlanksOnly() {
        configure();
        Lead existing = [SELECT Id, Department__c, LastName FROM Lead WHERE Email = :emailOf(0)];
        Zoom_Registration__c reg = registration(session().Id, emailOf(0).toUpperCase(), '+91 ' + phoneOf(0), 'Asha', 'Patel', true, true);
        insert reg;

        Test.startTest();
        runPending();
        Test.stopTest();

        Zoom_Registration__c result = reload(reg.Id);
        System.assertEquals(existing.Id, result.Lead__c, 'The existing Lead with the same email, phone, department and year must be linked');
        System.assertEquals('Lead updated', result.Lead_Status__c, 'Linking an existing Lead must set Lead updated');
        System.assert(result.Is_Matched__c, 'A linked registration must be marked matched');
        Lead after = [SELECT LeadSource, Admission_Year__c, Department__c, LastName, Phone FROM Lead WHERE Id = :existing.Id];
        System.assertNotEquals(null, after.Phone, 'A blank Phone on an existing Lead must be filled');
        System.assertEquals(ORIGINAL_SOURCE, after.LeadSource, 'Lead Source of an existing Lead must never change');
        System.assertEquals(YEAR, after.Admission_Year__c, 'Admission Year of an existing Lead must never change');
        System.assertEquals(existing.LastName, after.LastName, 'A filled field must not be overwritten');
        System.assertEquals(existing.Department__c == null ? 'Masters' : existing.Department__c, after.Department__c,
            'A blank Department must be filled from the session');
        System.assertEquals(1, [SELECT COUNT() FROM Task WHERE WhoId = :existing.Id AND Subject = :'Zoom Meeting Registered: ' + TOPIC],
            'One Registered Task must be logged');
        System.assertEquals(1, [SELECT COUNT() FROM Task WHERE WhoId = :existing.Id AND Subject = :'Zoom Meeting Attended: ' + TOPIC],
            'One Attended Task must be logged for an ended session');
        System.assertNotEquals(null, result.Attendance_Task_Id__c, 'The attendance Task must be stored on the registration');
    }

    @IsTest
    static void createsNewLeadWithZoomSourceForUnknownPerson() {
        configure();
        Zoom_Registration__c reg = registration(session().Id, 'new.person' + EMAIL_DOMAIN, '9123456780', 'Ravi', 'Shah', true, false);
        insert reg;

        Test.startTest();
        runPending();
        Test.stopTest();

        Zoom_Registration__c result = reload(reg.Id);
        System.assertEquals('Lead created', result.Lead_Status__c, 'An unknown person must get a new Lead');
        Lead created = [SELECT FirstName, LastName, Email, Phone, Status, LeadSource, Multi_Select_Lead_Source__c, Admission_Year__c,
            Department__c, Preferred_Programme__c, RecordType.DeveloperName FROM Lead WHERE Id = :result.Lead__c];
        System.assertEquals('919123456780', created.Phone, 'Phone must be set like website Leads: 91 + 10-digit number');
        System.assertNotEquals('Unqualified', created.Status, 'A Zoom Lead with valid email and phone must not be marked Unqualified');
        System.assertEquals('Zoom', created.LeadSource, 'A new Lead must have Lead Source Zoom');
        System.assertEquals('Zoom', created.Multi_Select_Lead_Source__c, 'A new Lead must have Multi Select Lead Source Zoom');
        System.assertEquals(DEPARTMENT, created.RecordType.DeveloperName, 'The record type must come from the session Department');
        System.assertEquals('Masters', created.Department__c, 'Department__c must be the Department label');
        System.assertEquals(YEAR, created.Admission_Year__c, 'Admission Year must come from the session');
        System.assertEquals(null, created.Preferred_Programme__c, 'Without a chosen programme the Lead must have none');
        System.assertEquals('Ravi', created.FirstName, 'First name must come from the registration');
        System.assertEquals('Shah', created.LastName, 'Last name must come from the registration');
        System.assertEquals(1, [SELECT COUNT() FROM Task WHERE WhoId = :created.Id AND Subject = :'Zoom Meeting Did Not Attend: ' + TOPIC],
            'A registered person who never joined an ended session must get a Did Not Attend Task');
    }

    @IsTest
    static void emailMatchWithDifferentPhoneCreatesNewLead() {
        configure();
        Zoom_Registration__c reg = registration(session().Id, emailOf(1), '9000000001', 'A', 'B', true, false);
        insert reg;

        Test.startTest();
        runPending();
        Test.stopTest();

        System.assertEquals('Lead created', reload(reg.Id).Lead_Status__c,
            'When email and phone are both known, both must match the same Lead');
    }

    @IsTest
    static void differentAdmissionYearCreatesNewLead() {
        configure();
        Zoom_Webinar__c otherYear = new Zoom_Webinar__c(Name = 'Next year', Webinar_Id__c = '888', Type__c = 'Meeting',
            Status__c = 'Scheduled', Department__c = DEPARTMENT, Admission_Year__c = OTHER_YEAR);
        insert otherYear;
        Zoom_Registration__c reg = registration(otherYear.Id, emailOf(2), phoneOf(2), 'C', 'D', true, false);
        insert reg;

        Test.startTest();
        runPending(otherYear.Id);
        Test.stopTest();

        Zoom_Registration__c result = reload(reg.Id);
        System.assertEquals('Lead created', result.Lead_Status__c, 'A Lead of another Admission Year must not match');
        System.assertEquals(OTHER_YEAR, [SELECT Admission_Year__c FROM Lead WHERE Id = :result.Lead__c].Admission_Year__c,
            'The new Lead must use the session Admission Year');
        System.assertEquals(0, [SELECT COUNT() FROM Task WHERE WhoId = :result.Lead__c AND Subject LIKE '%Did Not Attend%'],
            'A session that has not ended must not get attendance Tasks');
    }

    @IsTest
    static void phoneOnlyMatchesByLastTenDigits() {
        configure();
        Lead existing = [SELECT Id FROM Lead WHERE Email = :emailOf(3)];
        Zoom_Registration__c reg = registration(session().Id, null, '0091-' + phoneOf(3), null, null, false, true);
        insert reg;

        Test.startTest();
        runPending();
        Test.stopTest();

        System.assertEquals(existing.Id, reload(reg.Id).Lead__c, 'Without email the Lead must match on the last 10 phone digits');
    }

    @IsTest
    static void emailOnlyWalkInMatchesByEmail() {
        configure();
        Lead existing = [SELECT Id FROM Lead WHERE Email = :emailOf(4)];
        Zoom_Registration__c reg = registration(session().Id, emailOf(4), null, null, 'Walk In', false, true);
        insert reg;

        Test.startTest();
        runPending();
        Test.stopTest();

        System.assertEquals(existing.Id, reload(reg.Id).Lead__c, 'Without phone the Lead must match on email');
        System.assertEquals(1, [SELECT COUNT() FROM Task WHERE WhoId = :existing.Id], 'A walk-in gets only the Attended Task');
    }

    @IsTest
    static void noContactDetailsCreatesNoLead() {
        configure();
        Zoom_Registration__c reg = registration(session().Id, null, null, 'Nameless', 'Guest', false, true);
        insert reg;
        Integer leadsBefore = [SELECT COUNT() FROM Lead];

        Test.startTest();
        runPending();
        Test.stopTest();

        System.assertEquals('No contact details', reload(reg.Id).Lead_Status__c, 'No email and no phone must be flagged');
        System.assertEquals(leadsBefore, [SELECT COUNT() FROM Lead], 'No Lead may be created without contact details');
        System.assertEquals(0, [SELECT COUNT() FROM API_Log__c], 'Missing contact details is not an error');
    }

    @IsTest
    static void samePersonTwiceInBatchCreatesOneLead() {
        configure();
        Id sessionId = session().Id;
        Zoom_Registration__c first = registration(sessionId, 'twice' + EMAIL_DOMAIN, '9111111111', 'T', 'W', true, false);
        Zoom_Registration__c again = registration(sessionId, 'twice' + EMAIL_DOMAIN, '9111111111', 'T', 'W', false, true);
        insert new List<Zoom_Registration__c>{ first, again };

        Test.startTest();
        runPending();
        Test.stopTest();

        System.assertEquals(reload(first.Id).Lead__c, reload(again.Id).Lead__c, 'One person in one batch must get one Lead');
        System.assertEquals(1, [SELECT COUNT() FROM Lead WHERE Email = :'twice' + EMAIL_DOMAIN], 'Exactly one Lead must be created');
    }

    @IsTest
    static void samePersonInSecondSessionMatchesLeadFromFirstSync() {
        configure();
        Zoom_Webinar__c second = new Zoom_Webinar__c(Name = 'Second', Webinar_Id__c = '999', Type__c = 'Meeting',
            Status__c = 'Scheduled', Department__c = DEPARTMENT, Admission_Year__c = YEAR);
        insert second;
        Zoom_Registration__c first = registration(session().Id, 'twice' + EMAIL_DOMAIN, '9111111111', 'T', 'W', true, false);
        Zoom_Registration__c again = registration(second.Id, 'twice' + EMAIL_DOMAIN, '9111111111', 'T', 'W', true, false);
        insert new List<Zoom_Registration__c>{ first, again };

        Test.startTest();
        runPending();
        runPending(second.Id);
        Test.stopTest();

        System.assertEquals(reload(first.Id).Lead__c, reload(again.Id).Lead__c, 'The second session must link the Lead from the first sync');
        System.assertEquals('Lead updated', reload(again.Id).Lead_Status__c, 'The second sync must match, not create');
        System.assertEquals(1, [SELECT COUNT() FROM Lead WHERE Email = :'twice' + EMAIL_DOMAIN], 'Exactly one Lead must exist');
    }

    @IsTest
    static void syncOfOneSessionLeavesOtherSessionsAlone() {
        configure();
        Zoom_Webinar__c other = new Zoom_Webinar__c(Name = 'Other', Webinar_Id__c = '123', Type__c = 'Meeting',
            Status__c = 'Scheduled', Department__c = DEPARTMENT, Admission_Year__c = YEAR);
        insert other;
        Zoom_Registration__c untouched = registration(other.Id, emailOf(9), phoneOf(9), 'U', 'V', true, false);
        insert untouched;

        Test.startTest();
        new ZoomLeadQueueable(session().Id).execute(null);
        Test.stopTest();

        System.assertEquals(PENDING, reload(untouched.Id).Lead_Status__c, 'Another session must stay Not synced until its own sync');
    }

    @IsTest
    static void sessionWithoutDepartmentStaysPending() {
        configure();
        Zoom_Webinar__c unset = new Zoom_Webinar__c(Name = 'Unset', Webinar_Id__c = '555', Type__c = 'Meeting', Status__c = 'Scheduled',
            Lead_Sync_Started_At__c = Datetime.now());
        insert unset;
        Zoom_Registration__c reg = registration(unset.Id, emailOf(5), phoneOf(5), 'E', 'F', true, false);
        insert reg;

        Test.startTest();
        ZoomLeadQueueable job = new ZoomLeadQueueable(unset.Id);
        job.execute(null);
        ZoomLeadQueueable.enqueuedJobs[0].execute(null);
        Test.stopTest();

        Zoom_Registration__c result = reload(reg.Id);
        System.assertEquals(PENDING, result.Lead_Status__c, 'A session without Department and Admission Year must keep its registrations pending');
        System.assertEquals(null, result.Lead__c, 'No Lead may be linked before the session is set up');
        System.assertEquals(null, [SELECT Lead_Sync_Started_At__c FROM Zoom_Webinar__c WHERE Id = :unset.Id].Lead_Sync_Started_At__c,
            'The end of the chain must release the session lock');
    }

    @IsTest
    static void leadSaveFailureIsMarkedAndLoggedOnce() {
        configure();
        ZoomLeadService.simulateLeadSaveFailure = true;
        Zoom_Registration__c one = registration(session().Id, 'fail.one' + EMAIL_DOMAIN, '9222222221', 'G', 'H', true, false);
        Zoom_Registration__c two = registration(session().Id, 'fail.two' + EMAIL_DOMAIN, '9222222222', 'I', 'J', true, false);
        insert new List<Zoom_Registration__c>{ one, two };

        Test.startTest();
        runPending();
        Test.stopTest();

        System.assertEquals('Error', reload(one.Id).Lead_Status__c, 'A Lead that cannot be saved must set Error');
        System.assertEquals('Error', reload(two.Id).Lead_Status__c, 'Every failed registration must be marked');
        API_Log__c log = [SELECT Apex_Class_Name__c, Registration_Number__c, Response__c FROM API_Log__c WHERE Log_Name__c = :ZoomLeadService.LOG_NAME];
        System.assertEquals('ZoomLeadService', log.Apex_Class_Name__c, 'The log must name the class so the error alert fires');
        System.assert(log.Registration_Number__c.startsWith('2 '), 'One log must summarise both failures');
        System.assert(!log.Response__c.contains('fail.one'), 'The log must not contain personal data');
    }

    @IsTest
    static void bulk200RegistrationsLinkAndLogTasks() {
        configure();
        Id sessionId = session().Id;
        List<Zoom_Registration__c> registrations = new List<Zoom_Registration__c>();
        for (Integer i = 0; i < BULK_SIZE; i++) {
            registrations.add(registration(sessionId, emailOf(i), phoneOf(i), 'Bulk', 'Person ' + i, true, true));
        }
        insert registrations;

        Test.startTest();
        runPending();
        Test.stopTest();

        System.assertEquals(BULK_SIZE, [SELECT COUNT() FROM Zoom_Registration__c WHERE Lead_Status__c = 'Lead updated' AND Lead__c != null],
            'All 200 registrations must be linked to their existing Leads');
        System.assertEquals(BULK_SIZE * 2, [SELECT COUNT() FROM Task WHERE Subject LIKE 'Zoom Meeting%'],
            'Each Lead must get one Registered and one Attended Task');
        System.assertEquals(0, [SELECT COUNT() FROM Lead WHERE LeadSource = 'Zoom'], 'No duplicate Leads may be created');
    }

    @IsTest
    static void attendancePhaseLogsTaskAfterSessionEnds() {
        configure();
        Zoom_Webinar__c later = new Zoom_Webinar__c(Name = 'Later', Webinar_Id__c = '444', Type__c = 'Meeting',
            Status__c = 'Scheduled', Department__c = DEPARTMENT, Admission_Year__c = YEAR);
        insert later;
        Zoom_Registration__c reg = registration(later.Id, emailOf(6), phoneOf(6), 'K', 'L', true, false);
        insert reg;
        runPending(later.Id);
        System.assertEquals(null, reload(reg.Id).Attendance_Task_Id__c, 'No attendance Task before the session ends');
        later.Status__c = 'Ended';
        later.Lead_Sync_Started_At__c = Datetime.now();
        update later;

        Test.startTest();
        new ZoomLeadQueueable(later.Id).execute(null);
        ZoomLeadQueueable.enqueuedJobs[0].execute(null);
        Test.stopTest();

        System.assertNotEquals(null, reload(reg.Id).Attendance_Task_Id__c, 'The attendance phase must log the Task once the session ended');
        System.assertEquals(1, [SELECT COUNT() FROM Task WHERE Subject = 'Zoom Meeting Did Not Attend: Later'],
            'The registered no-show must get one Did Not Attend Task');
        Zoom_Webinar__c after = [SELECT Lead_Sync_Started_At__c, Last_Lead_Sync_At__c FROM Zoom_Webinar__c WHERE Id = :later.Id];
        System.assertEquals(null, after.Lead_Sync_Started_At__c, 'The finished sync must release the session lock');
        System.assertNotEquals(null, after.Last_Lead_Sync_At__c, 'The finished sync must record when it ended');
    }

    @IsTest
    static void queueableChainsWhileFullBatchesRemain() {
        configure();
        Id sessionId = session().Id;
        List<Zoom_Registration__c> registrations = new List<Zoom_Registration__c>();
        for (Integer i = 0; i < ZoomLeadQueueable.BATCH_SIZE; i++) {
            registrations.add(registration(sessionId, emailOf(i), phoneOf(i), 'Q', 'R' + i, true, false));
        }
        insert registrations;

        Test.startTest();
        new ZoomLeadQueueable(sessionId).execute(null);
        Test.stopTest();

        System.assertEquals(1, ZoomLeadQueueable.enqueuedJobs.size(), 'A full batch must chain another job');
        System.assertEquals(ZoomLeadQueueable.PHASE_PENDING, ZoomLeadQueueable.enqueuedJobs[0].phase,
            'A full pending batch must chain the pending phase again');
        System.assertEquals(sessionId, ZoomLeadQueueable.enqueuedJobs[0].sessionId, 'The chained job must stay on the same session');
        System.assertEquals(0, [SELECT COUNT() FROM Zoom_Registration__c WHERE Lead_Status__c = :PENDING],
            'Every processed registration must leave Pending setup, so the chain ends');
    }

    @IsTest
    static void attendancePhaseChainsWhileFullBatchesRemain() {
        configure();
        Id sessionId = session().Id;
        List<Lead> leads = [SELECT Id FROM Lead ORDER BY Email LIMIT :ZoomLeadQueueable.BATCH_SIZE];
        List<Zoom_Registration__c> registrations = new List<Zoom_Registration__c>();
        for (Integer i = 0; i < leads.size(); i++) {
            Zoom_Registration__c reg = registration(sessionId, emailOf(i), phoneOf(i), 'S', 'T' + i, true, false);
            reg.Lead__c = leads[i].Id;
            reg.Lead_Status__c = 'Lead updated';
            registrations.add(reg);
        }
        insert registrations;
        ZoomLeadQueueable job = new ZoomLeadQueueable(sessionId);
        job.phase = ZoomLeadQueueable.PHASE_ATTENDANCE;

        Test.startTest();
        job.execute(null);
        Test.stopTest();

        System.assertEquals(1, ZoomLeadQueueable.enqueuedJobs.size(), 'A full attendance batch must chain another job');
        System.assertEquals(ZoomLeadQueueable.PHASE_ATTENDANCE, ZoomLeadQueueable.enqueuedJobs[0].phase,
            'The chained job must continue the attendance phase');
        System.assertEquals(ZoomLeadQueueable.BATCH_SIZE, [SELECT COUNT() FROM Task WHERE Subject LIKE 'Zoom Meeting Did Not Attend%'],
            'Every registered no-show in the batch must get a Did Not Attend Task');
    }

    @IsTest
    static void queueableFailureIsLoggedReleasesLockAndIsNotChained() {
        configure();
        Zoom_Webinar__c target = session();
        target.Lead_Sync_Started_At__c = Datetime.now();
        update target;
        ZoomLeadQueueable.simulateFailure = true;

        Test.startTest();
        new ZoomLeadQueueable(target.Id).execute(null);
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM API_Log__c WHERE Apex_Class_Name__c = 'ZoomLeadService' AND Registration_Number__c = 'pending'],
            'A failed Lead step must be logged with its phase so the error alert fires');
        System.assert(ZoomLeadQueueable.enqueuedJobs.isEmpty(), 'A failed job must not chain; the user retries from the popup');
        System.assertEquals(null, [SELECT Lead_Sync_Started_At__c FROM Zoom_Webinar__c WHERE Id = :target.Id].Lead_Sync_Started_At__c,
            'A failed sync must release the session lock so the user can retry');
    }

    @IsTest
    static void queueableDoesNothingWhenIntegrationDisabled() {
        configure();
        FeatureFlagService.testOverrides.put('Zoom_Integration', false);
        Zoom_Registration__c reg = registration(session().Id, emailOf(7), phoneOf(7), 'M', 'N', true, false);
        insert reg;

        Test.startTest();
        new ZoomLeadQueueable(session().Id).execute(null);
        new ZoomLeadQueueable(null).execute(null);
        Test.stopTest();

        System.assertEquals(PENDING, reload(reg.Id).Lead_Status__c, 'Nothing may be processed while Zoom_Integration is off');
        System.assert(ZoomLeadQueueable.enqueuedJobs.isEmpty(), 'No job may be chained while Zoom_Integration is off');
    }

    @IsTest
    static void startEnqueuesOneJobForTheSession() {
        Id sessionId = session().Id;

        Test.startTest();
        ZoomLeadQueueable.start(sessionId);
        Test.stopTest();

        System.assertEquals(1, ZoomLeadQueueable.enqueuedJobs.size(), 'start must enqueue exactly one job');
        System.assertEquals(sessionId, ZoomLeadQueueable.enqueuedJobs[0].sessionId, 'The job must be for the given session');
        System.assertEquals(ZoomLeadQueueable.PHASE_PENDING, ZoomLeadQueueable.enqueuedJobs[0].phase, 'A new sync must start with Leads');
    }

    @IsTest
    static void tasksSkippedWhenActivitiesDisabled() {
        configure();
        ZoomConfig.testOverride = new Zoom_Config__mdt(Create_Activities__c = false);
        Zoom_Registration__c reg = registration(session().Id, emailOf(8), phoneOf(8), 'O', 'P', true, true);
        insert reg;

        Test.startTest();
        runPending();
        Test.stopTest();

        System.assertEquals('Lead updated', reload(reg.Id).Lead_Status__c, 'The Lead must still be linked');
        System.assertEquals(0, [SELECT COUNT() FROM Task WHERE Subject LIKE 'Zoom Meeting%'], 'No Task may be created when activities are off');
    }

    @IsTest
    static void nameAndPhoneHelpers() {
        System.assertEquals(new List<String>{ 'Anita', 'Shah' }, ZoomLeadService.splitName('  Anita   Shah '), 'The last word must be the last name');
        System.assertEquals(new List<String>{ 'Mary Ann', 'Lee' }, ZoomLeadService.splitName('Mary Ann Lee'), 'Earlier words must be the first name');
        System.assertEquals(new List<String>{ null, 'Cher' }, ZoomLeadService.splitName('Cher'), 'A single word must be the last name');
        System.assertEquals(new List<String>{ null, null }, ZoomLeadService.splitName(' '), 'A blank name must give no names');
        System.assertEquals('9876543210', ZoomLeadService.lastTen('+91 98765-43210'), 'Only the last 10 digits must be kept');
        System.assertEquals('919876543210', ZoomLeadService.standardPhone('98765 43210'), 'A 10-digit number must get country code 91');
        System.assertEquals('919876543210', ZoomLeadService.standardPhone('09876543210'), 'A leading trunk 0 must be dropped before adding 91');
        System.assertEquals('919876543210', ZoomLeadService.standardPhone('+91-98765-43210'), 'A number with country code must be kept as digits');
        System.assertEquals('14155550123', ZoomLeadService.standardPhone('+1 (415) 555-0123'), 'A foreign number must keep its own country code');
        System.assertEquals(null, ZoomLeadService.standardPhone('123'), 'Too few digits must give no phone');
        System.assertEquals(null, ZoomLeadService.standardPhone(null), 'A null phone must give null');
        System.assertEquals(null, ZoomLeadService.lastTen('12345'), 'Fewer than 7 digits is not a phone number');
        System.assertEquals(null, ZoomLeadService.lastTen(null), 'A null phone must give null');
    }

    // ── Owners ─────────────────────────────────────────────────────────────────────────────────────────────────────

    /** Creates owner users (setup DML isolated in runAs to avoid mixed DML); the last inactiveCount are inactive. */
    private static List<User> createOwnerUsers(Integer activeCount, Integer inactiveCount) {
        List<User> users = new List<User>();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            UserRole role = new UserRole(Name = OWNER_ROLE);
            insert role;
            for (Integer i = 0; i < activeCount + inactiveCount; i++) {
                String unique = 'zoomowner' + i + '.' + Math.abs(Crypto.getRandomInteger());
                users.add(new User(LastName = 'Owner ' + i, Alias = 'zown' + i, Email = unique + NEW_EMAIL_DOMAIN,
                    Username = unique + NEW_EMAIL_DOMAIN, ProfileId = UserInfo.getProfileId(), UserRoleId = role.Id,
                    Department = OWNER_DEPARTMENT, IsActive = i < activeCount, TimeZoneSidKey = 'Asia/Kolkata',
                    LocaleSidKey = 'en_IN', EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'));
            }
            insert users;
        }
        return users;
    }

    private static List<Zoom_Registration__c> newPeople(Integer count, String programme) {
        Id sessionId = session().Id;
        List<Zoom_Registration__c> registrations = new List<Zoom_Registration__c>();
        for (Integer i = 0; i < count; i++) {
            Zoom_Registration__c reg = registration(sessionId, 'owner' + i + NEW_EMAIL_DOMAIN, '97' + String.valueOf(10000000 + i),
                'New', 'Person ' + i, true, false);
            reg.Preferred_Programme__c = programme;
            registrations.add(reg);
        }
        return registrations;
    }

    private static LeadAssignmentRule__mdt rule(String department, String course, String emails) {
        return new LeadAssignmentRule__mdt(Department__c = department, Course__c = course, User_Email__c = emails);
    }

    private static void setSessionDepartment(String department) {
        Zoom_Webinar__c target = session();
        target.Department__c = department;
        update target;
    }

    private static Set<Id> idsOf(List<User> users) {
        return new Map<Id, User>(users).keySet();
    }

    private static Map<Id, Integer> newLeadCountByOwner() {
        Map<Id, Integer> countByOwner = new Map<Id, Integer>();
        for (AggregateResult row : [SELECT OwnerId owner, COUNT(Id) total FROM Lead WHERE Email LIKE :'%' + NEW_EMAIL_DOMAIN GROUP BY OwnerId]) {
            countByOwner.put((Id) row.get('owner'), (Integer) row.get('total'));
        }
        return countByOwner;
    }

    @IsTest
    static void undergraduationLeadsAllGoToConfiguredOwner() {
        List<User> users = createOwnerUsers(3, 0);
        configure();
        ZoomConfig.testOverride.UG_Lead_Owner_Username__c = ' ' + users[1].Username + ' ';
        ZoomLeadService.testAssignmentRules = new List<LeadAssignmentRule__mdt>{
            rule(UNDERGRADUATION, 'Test Course', users[0].Email)
        };
        setSessionDepartment(UNDERGRADUATION);
        insert newPeople(10, null);

        Test.startTest();
        runPending();
        Test.stopTest();

        Map<Id, Integer> countByOwner = newLeadCountByOwner();
        System.assertEquals(1, countByOwner.size(), 'Every new Undergraduation Lead must have the same owner');
        System.assertEquals(10, countByOwner.get(users[1].Id), 'The configured Undergraduation owner must own every new Lead');
        Lead sample = [SELECT Id, OwnerId, RecordType.DeveloperName FROM Lead WHERE Email = :'owner0' + NEW_EMAIL_DOMAIN];
        System.assertEquals(UNDERGRADUATION, sample.RecordType.DeveloperName, 'The Lead must be an Undergraduation Lead');
        System.assertEquals(sample.OwnerId, [SELECT OwnerId FROM Task WHERE WhoId = :sample.Id LIMIT 1].OwnerId,
            'The Registered Task must belong to the new Lead owner');
    }

    @IsTest
    static void inactiveUndergraduationOwnerKeepsTriggerOwnerWithoutError() {
        List<User> users = createOwnerUsers(0, 1);
        configure();
        ZoomConfig.testOverride.UG_Lead_Owner_Username__c = users[0].Username;
        setSessionDepartment(UNDERGRADUATION);
        insert newPeople(1, null);

        Test.startTest();
        runPending();
        Test.stopTest();

        Lead created = [SELECT OwnerId FROM Lead WHERE Email = :'owner0' + NEW_EMAIL_DOMAIN];
        System.assertNotEquals(users[0].Id, created.OwnerId, 'An inactive user must never receive Leads');
        System.assertEquals('Lead created', [SELECT Lead_Status__c FROM Zoom_Registration__c WHERE Email__c = :'owner0' + NEW_EMAIL_DOMAIN].Lead_Status__c,
            'A missing owner must not mark the registration as an error');
        System.assertEquals(0, [SELECT COUNT() FROM API_Log__c WHERE Log_Name__c = :ZoomLeadService.LOG_NAME],
            'A missing owner must not log an error');
    }

    @IsTest
    static void ownerLookupByUsername() {
        List<User> users = createOwnerUsers(1, 0);
        configure();
        System.assertEquals(null, ZoomSelector.selectActiveUserByUsername(null), 'A null username must find nobody');
        System.assertEquals(null, ZoomSelector.selectActiveUserByUsername(' '), 'A blank username must find nobody');
        System.assertEquals(null, ZoomSelector.selectActiveUserByUsername('nobody' + NEW_EMAIL_DOMAIN), 'An unknown username must find nobody');
        System.assertEquals(users[0].Id, ZoomSelector.selectActiveUserByUsername(users[0].Username).Id, 'An active username must be found');
        System.assertEquals(null, ZoomLeadService.undergraduationOwner(), 'Without configuration there is no Undergraduation owner');
    }

    @IsTest
    static void otherDepartmentWithoutProgrammeUsesDepartmentUsers() {
        List<User> users = createOwnerUsers(3, 0);
        configure();
        ZoomLeadService.testAssignmentRules = new List<LeadAssignmentRule__mdt>{
            rule('Masters', 'Test Course', users[0].Email + ', ' + users[1].Email.toUpperCase()),
            rule('Phd', 'Other Course', users[2].Email)
        };
        insert newPeople(4, null);

        Test.startTest();
        runPending();
        Test.stopTest();

        Map<Id, Integer> countByOwner = newLeadCountByOwner();
        System.assertEquals(2, countByOwner.get(users[0].Id), 'Masters Leads without a programme must rotate over the Masters users');
        System.assertEquals(2, countByOwner.get(users[1].Id), 'Masters Leads without a programme must rotate over the Masters users');
        System.assert(!countByOwner.containsKey(users[2].Id), 'Users of another department must not receive Masters Leads');
        System.assertEquals(0, Zoom_Lead_Round_Robin__c.getInstance('masters').Next_Index__c, 'The Masters position must be saved');
    }

    @IsTest
    static void departmentRoundRobinContinuesFromSavedPosition() {
        List<User> users = createOwnerUsers(2, 0);
        configure();
        ZoomLeadService.testAssignmentRules = new List<LeadAssignmentRule__mdt>{
            rule('Masters', 'Test Course', users[0].Email + ',' + users[1].Email)
        };
        insert new Zoom_Lead_Round_Robin__c(Name = 'masters', Next_Index__c = 1);
        insert newPeople(1, null);

        Test.startTest();
        runPending();
        Test.stopTest();

        System.assertEquals(users[1].Id, [SELECT OwnerId FROM Lead WHERE Email = :'owner0' + NEW_EMAIL_DOMAIN].OwnerId,
            'The next Lead must go to the user at the saved position');
        System.assertEquals(0, Zoom_Lead_Round_Robin__c.getInstance('masters').Next_Index__c, 'The position must wrap to the first user');
    }

    @IsTest
    static void savedPositionOutOfRangeRestartsAtFirstUser() {
        List<User> users = createOwnerUsers(2, 0);
        configure();
        ZoomLeadService.testAssignmentRules = new List<LeadAssignmentRule__mdt>{
            rule('Masters', 'Test Course', users[0].Email + ',' + users[1].Email)
        };
        insert new Zoom_Lead_Round_Robin__c(Name = 'masters', Next_Index__c = 7);
        insert newPeople(1, null);

        Test.startTest();
        runPending();
        Test.stopTest();

        System.assertEquals(users[0].Id, [SELECT OwnerId FROM Lead WHERE Email = :'owner0' + NEW_EMAIL_DOMAIN].OwnerId,
            'A saved position beyond the user list (a user left) must restart at the first user');
    }

    @IsTest
    static void departmentWithoutUsersKeepsTriggerOwner() {
        List<User> users = createOwnerUsers(1, 0);
        configure();
        ZoomConfig.testOverride.UG_Lead_Owner_Username__c = users[0].Username;
        insert newPeople(1, null);

        Test.startTest();
        runPending();
        Test.stopTest();

        Lead created = [SELECT OwnerId FROM Lead WHERE Email = :'owner0' + NEW_EMAIL_DOMAIN];
        System.assertNotEquals(users[0].Id, created.OwnerId, 'Leads of other departments must never fall back to the Undergraduation owner');
        System.assertEquals(null, Zoom_Lead_Round_Robin__c.getInstance('masters'), 'No position may be saved when no owner is used');
    }

    @IsTest
    static void programmeWithRuleUsersKeepsTriggerOwner() {
        List<User> users = createOwnerUsers(2, 0);
        configure();
        ZoomLeadService.testAssignmentRules = new List<LeadAssignmentRule__mdt>{
            rule('Masters', MBA, users[0].Email)
        };
        insert newPeople(1, MBA);

        Test.startTest();
        runPending();
        Test.stopTest();

        Lead created = [SELECT OwnerId, Preferred_Programme__c FROM Lead WHERE Email = :'owner0' + NEW_EMAIL_DOMAIN];
        System.assertEquals(MBA, created.Preferred_Programme__c, 'A new Lead must get the student programme');
        System.assert(!idsOf(users).contains(created.OwnerId),
            'When the programme has users, the owner set by the Lead trigger programme rule must be kept');
    }

    @IsTest
    static void programmeWithoutRuleUsesDepartmentUsers() {
        List<User> users = createOwnerUsers(2, 0);
        configure();
        ZoomLeadService.testAssignmentRules = new List<LeadAssignmentRule__mdt>{
            rule('Masters', 'Test Course', users[1].Email)
        };
        insert newPeople(1, ECONOMICS);

        Test.startTest();
        runPending();
        Test.stopTest();

        System.assertEquals(users[1].Id, [SELECT OwnerId FROM Lead WHERE Email = :'owner0' + NEW_EMAIL_DOMAIN].OwnerId,
            'A programme without its own rule must fall back to the department users');
    }

    @IsTest
    static void studentsOfOneSessionCanHaveDifferentProgrammes() {
        configure();
        List<Zoom_Registration__c> people = newPeople(2, MBA);
        people[1].Preferred_Programme__c = ECONOMICS;
        insert people;

        Test.startTest();
        runPending();
        Test.stopTest();

        System.assertEquals(MBA, [SELECT Preferred_Programme__c FROM Lead WHERE Email = :'owner0' + NEW_EMAIL_DOMAIN].Preferred_Programme__c,
            'The first student must get their own programme');
        System.assertEquals(ECONOMICS, [SELECT Preferred_Programme__c FROM Lead WHERE Email = :'owner1' + NEW_EMAIL_DOMAIN].Preferred_Programme__c,
            'The second student must get their own programme');
    }

    @IsTest
    static void existingLeadProgrammeFilledOnlyWhenBlank() {
        configure();
        Lead withProgramme = [SELECT Id FROM Lead WHERE Email = :emailOf(3)];
        withProgramme.Preferred_Programme__c = ECONOMICS;
        update withProgramme;
        Zoom_Registration__c blankLead = registration(session().Id, emailOf(2), phoneOf(2), 'A', 'B', true, false);
        Zoom_Registration__c filledLead = registration(session().Id, emailOf(3), phoneOf(3), 'C', 'D', true, false);
        blankLead.Preferred_Programme__c = MBA;
        filledLead.Preferred_Programme__c = MBA;
        insert new List<Zoom_Registration__c>{ blankLead, filledLead };

        Test.startTest();
        runPending();
        Test.stopTest();

        System.assertEquals(MBA, [SELECT Preferred_Programme__c FROM Lead WHERE Email = :emailOf(2)].Preferred_Programme__c,
            'A blank programme on an existing Lead must be filled from the student choice');
        System.assertEquals(ECONOMICS, [SELECT Preferred_Programme__c FROM Lead WHERE Id = :withProgramme.Id].Preferred_Programme__c,
            'A programme already on an existing Lead must never change');
    }

    @IsTest
    static void programmeYearAndDepartmentHelpers() {
        Zoom_Registration__c registration = new Zoom_Registration__c();
        System.assertEquals(null, ZoomLeadService.programmeOf(registration), 'No programme must give no programme');
        registration.Preferred_Programme__c = 'Not A Programme';
        System.assertEquals(null, ZoomLeadService.programmeOf(registration), 'A value not on Lead must be ignored');
        registration.Preferred_Programme__c = 'Gemba';
        System.assertEquals('Gemba', ZoomLeadService.programmeOf(registration), 'A valid Lead programme must be used');
        System.assert(ZoomLeadService.isActiveLeadAdmissionYear(YEAR), 'An active Lead admission year must be accepted');
        System.assert(!ZoomLeadService.isActiveLeadAdmissionYear('Admission Year - 1999'), 'An unknown year must be rejected');
        System.assert(!ZoomLeadService.isActiveLeadAdmissionYear(null), 'A blank year must be rejected');
        System.assert(ZoomLeadService.isUndergraduation('Undergraduation'), 'The record type name must be Undergraduation');
        System.assert(!ZoomLeadService.isUndergraduation('Masters'), 'Masters is not Undergraduation');
        System.assert(!ZoomLeadService.isUndergraduation(null), 'No department is not Undergraduation');
        System.assertEquals(ZoomLeadService.departmentKey('Executive Education '), ZoomLeadService.departmentKey('Executive_Education'),
            'Record type names and metadata departments must give the same key');
        System.assertEquals(null, ZoomLeadService.departmentKey(' '), 'A blank department must give no key');
    }
}
