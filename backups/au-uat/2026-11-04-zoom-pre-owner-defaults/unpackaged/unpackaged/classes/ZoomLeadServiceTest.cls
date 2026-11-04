/**
 * @description Tests for ZoomLeadService and ZoomLeadQueueable: Lead matching (email + phone + Department record
 *              type + Admission Year), new Lead creation, blank-only updates, Tasks, error handling, a 200-record
 *              bulk run and queueable chaining.
 * @author AU Development Team
 * @date 2026-11-03
 * @version 1.0
 * @lastModified 2026-11-03
 */
@IsTest
private class ZoomLeadServiceTest {
    private static final Integer BULK_SIZE = 200;
    private static final String DEPARTMENT = 'Masters';
    private static final String YEAR = 'Admission Year - 2026';
    private static final String OTHER_YEAR = 'Admission Year - 2027';
    private static final String ZOOM_ID = '777000777';
    private static final String TOPIC = 'Masters Info Session';
    private static final String EMAIL_DOMAIN = '@zoomlead.test';
    private static final String ORIGINAL_SOURCE = 'Website';
    private static final String PENDING = 'Pending setup';

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

    private static void runPending() {
        ZoomLeadService.processPending(ZoomSelector.selectPendingLeadRegistrations(PENDING, BULK_SIZE));
    }

    private static Zoom_Registration__c reload(Id registrationId) {
        return [SELECT Lead__c, Lead_Status__c, Is_Matched__c, Registration_Task_Id__c, Attendance_Task_Id__c
            FROM Zoom_Registration__c WHERE Id = :registrationId];
    }

    @IsTest
    static void matchesExistingLeadByEmailAndPhoneAndFillsBlanksOnly() {
        configure();
        Lead existing = [SELECT Id, Department__c FROM Lead WHERE Email = :emailOf(0)];
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
        System.assertEquals('Existing 0', after.LastName, 'A filled field must not be overwritten');
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
            Department__c, RecordType.DeveloperName FROM Lead WHERE Id = :result.Lead__c];
        System.assertEquals('919123456780', created.Phone, 'Phone must be set like website Leads: 91 + 10-digit number');
        System.assertNotEquals('Unqualified', created.Status, 'A Zoom Lead with valid email and phone must not be marked Unqualified');
        System.assertEquals('Zoom', created.LeadSource, 'A new Lead must have Lead Source Zoom');
        System.assertEquals('Zoom', created.Multi_Select_Lead_Source__c, 'A new Lead must have Multi Select Lead Source Zoom');
        System.assertEquals(DEPARTMENT, created.RecordType.DeveloperName, 'The record type must come from the session Department');
        System.assertEquals('Masters', created.Department__c, 'Department__c must be the Department label');
        System.assertEquals(YEAR, created.Admission_Year__c, 'Admission Year must come from the session');
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
        runPending();
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
        Zoom_Webinar__c second = new Zoom_Webinar__c(Name = 'Second', Webinar_Id__c = '999', Type__c = 'Meeting',
            Status__c = 'Scheduled', Department__c = DEPARTMENT, Admission_Year__c = YEAR);
        insert second;
        Zoom_Registration__c first = registration(session().Id, 'twice' + EMAIL_DOMAIN, '9111111111', 'T', 'W', true, false);
        Zoom_Registration__c again = registration(second.Id, 'twice' + EMAIL_DOMAIN, '9111111111', 'T', 'W', true, false);
        insert new List<Zoom_Registration__c>{ first, again };

        Test.startTest();
        runPending();
        Test.stopTest();

        System.assertEquals(reload(first.Id).Lead__c, reload(again.Id).Lead__c, 'One person in one batch must get one Lead');
        System.assertEquals(1, [SELECT COUNT() FROM Lead WHERE Email = :'twice' + EMAIL_DOMAIN], 'Exactly one Lead must be created');
    }

    @IsTest
    static void sessionWithoutDepartmentStaysPending() {
        configure();
        Zoom_Webinar__c unset = new Zoom_Webinar__c(Name = 'Unset', Webinar_Id__c = '555', Type__c = 'Meeting', Status__c = 'Scheduled');
        insert unset;
        Zoom_Registration__c reg = registration(unset.Id, emailOf(5), phoneOf(5), 'E', 'F', true, false);
        insert reg;

        Test.startTest();
        new ZoomLeadQueueable().execute(null);
        Test.stopTest();

        Zoom_Registration__c result = reload(reg.Id);
        System.assertEquals(PENDING, result.Lead_Status__c, 'A session without Department and Admission Year must keep its registrations pending');
        System.assertEquals(null, result.Lead__c, 'No Lead may be linked before the session is set up');
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
        runPending();
        System.assertEquals(null, reload(reg.Id).Attendance_Task_Id__c, 'No attendance Task before the session ends');
        later.Status__c = 'Ended';
        update later;

        Test.startTest();
        new ZoomLeadQueueable().execute(null);
        ZoomLeadQueueable.enqueuedJobs[0].execute(null);
        Test.stopTest();

        System.assertNotEquals(null, reload(reg.Id).Attendance_Task_Id__c, 'The attendance phase must log the Task once the session ended');
        System.assertEquals(1, [SELECT COUNT() FROM Task WHERE Subject = 'Zoom Meeting Did Not Attend: Later'],
            'The registered no-show must get one Did Not Attend Task');
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
        new ZoomLeadQueueable().execute(null);
        Test.stopTest();

        System.assertEquals(1, ZoomLeadQueueable.enqueuedJobs.size(), 'A full batch must chain another job');
        System.assertEquals('pending', ZoomLeadQueueable.enqueuedJobs[0].phase, 'A full pending batch must chain the pending phase again');
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
        ZoomLeadQueueable job = new ZoomLeadQueueable();
        job.phase = 'attendance';

        Test.startTest();
        job.execute(null);
        Test.stopTest();

        System.assertEquals(1, ZoomLeadQueueable.enqueuedJobs.size(), 'A full attendance batch must chain another job');
        System.assertEquals('attendance', ZoomLeadQueueable.enqueuedJobs[0].phase, 'The chained job must continue the attendance phase');
        System.assertEquals(ZoomLeadQueueable.BATCH_SIZE, [SELECT COUNT() FROM Task WHERE Subject LIKE 'Zoom Meeting Did Not Attend%'],
            'Every registered no-show in the batch must get a Did Not Attend Task');
    }

    @IsTest
    static void queueableFailureIsLoggedAndNotChained() {
        configure();
        ZoomLeadQueueable.simulateFailure = true;

        Test.startTest();
        new ZoomLeadQueueable().execute(null);
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM API_Log__c WHERE Apex_Class_Name__c = 'ZoomLeadService' AND Registration_Number__c = 'pending'],
            'A failed Lead step must be logged with its phase so the error alert fires');
        System.assert(ZoomLeadQueueable.enqueuedJobs.isEmpty(), 'A failed job must not chain; the next scheduled run retries');
    }

    @IsTest
    static void queueableDoesNothingWhenIntegrationDisabled() {
        configure();
        FeatureFlagService.testOverrides.put('Zoom_Integration', false);
        Zoom_Registration__c reg = registration(session().Id, emailOf(7), phoneOf(7), 'M', 'N', true, false);
        insert reg;

        Test.startTest();
        new ZoomLeadQueueable().execute(null);
        Test.stopTest();

        System.assertEquals(PENDING, reload(reg.Id).Lead_Status__c, 'Nothing may be processed while Zoom_Integration is off');
        System.assert(ZoomLeadQueueable.enqueuedJobs.isEmpty(), 'No job may be chained while Zoom_Integration is off');
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
}