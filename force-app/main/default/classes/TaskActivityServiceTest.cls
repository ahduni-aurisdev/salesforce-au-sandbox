/**
 * @description Tests Task placement, owner and status rules, validation, bulk creation, and logging for the Task Activity API.
 * @author AU Development Team
 * @date 2026-10-23
 * @version 1.0
 * @lastModified 2026-10-23
 */
@IsTest
private class TaskActivityServiceTest {
    private static final String LEAD_PREFIX = 'TaskApi Lead ';
    private static final String ACCOUNT_PREFIX = 'TaskApi Account ';
    private static final String CITY = 'Ahmedabad';
    private static final String INTEGRATION_PROFILE = 'Salesforce API Only System Integrations';
    private static final String CONVERTED_STATUS = 'Application Submitted';
    private static final Long MOBILE_BASE = 9876500000L;

    @TestSetup
    static void createData() {
        List<Lead> leads = new List<Lead>();
        List<Account> accounts = new List<Account>();
        for (Integer index = 0; index < 200; index++) {
            leads.add(new Lead(
                Salutation = 'Mr.',
                FirstName = 'Task',
                LastName = LEAD_PREFIX + index,
                Company = 'AU Test ' + index,
                City = CITY,
                MobilePhone = String.valueOf(MOBILE_BASE + index)
            ));
            accounts.add(new Account(Name = ACCOUNT_PREFIX + index, BillingCity = CITY));
        }
        insert leads;
        insert accounts;
    }

    @IsTest
    static void shouldCreateInProgressTaskOnUnconvertedLead() {
        Lead leadValue = [SELECT Id, OwnerId FROM Lead WHERE LastName = :LEAD_PREFIX + '0'];
        TaskActivityApiModels.RequestEnvelope envelope = envelope(new List<TaskActivityApiModels.TaskRequest>{
            request(leadValue.Id, 'Lead follow-up', null, 'Call back about fees')
        });

        Test.startTest();
        TaskActivityApiModels.ResponseEnvelope response = TaskActivityService.process(envelope, 'REQ-LEAD');
        Test.stopTest();

        System.assertEquals(true, response.success, 'A valid Lead task should succeed.');
        TaskActivityApiModels.RecordResult result = response.results[0];
        System.assertEquals(TaskActivityService.TARGET_LEAD, result.targetType, 'An unconverted Lead keeps the task.');
        System.assertEquals(leadValue.Id, result.relatedToId, 'The task should relate to the Lead.');
        Task created = [SELECT WhoId, WhatId, OwnerId, Status, Priority, Subject, Description, ActivityDate FROM Task WHERE Id = :result.taskId];
        System.assertEquals(leadValue.Id, created.WhoId, 'The task Name should be the Lead.');
        System.assertEquals(null, created.WhatId, 'A Lead task cannot have a Related To record.');
        System.assertEquals(expectedOwner(leadValue.OwnerId), created.OwnerId, 'The Lead owner should own the task.');
        System.assertEquals('In Progress', created.Status, 'A task without a due date should be In Progress.');
        System.assertEquals('Normal', created.Priority, 'Priority should default to Normal.');
        System.assertEquals('Call back about fees', created.Description, 'Comments should map to Description.');
        System.assertEquals(null, created.ActivityDate, 'An omitted due date should stay blank.');
    }

    @IsTest
    static void shouldCreateTaskOnAccountWithAccountOwner() {
        Account accountValue = [SELECT Id, OwnerId FROM Account WHERE Name = :ACCOUNT_PREFIX + '0'];
        Date futureDate = Date.today().addDays(5);
        TaskActivityApiModels.RequestEnvelope envelope = envelope(new List<TaskActivityApiModels.TaskRequest>{
            request(accountValue.Id, 'Account follow-up', String.valueOf(futureDate), null)
        });

        Test.startTest();
        TaskActivityApiModels.ResponseEnvelope response = TaskActivityService.process(envelope, 'REQ-ACCOUNT');
        Test.stopTest();

        TaskActivityApiModels.RecordResult result = response.results[0];
        System.assertEquals(true, result.success, 'A valid Account task should succeed.');
        System.assertEquals(TaskActivityService.TARGET_ACCOUNT, result.targetType, 'The Account should receive the task.');
        Task created = [SELECT WhatId, OwnerId, Status, ActivityDate FROM Task WHERE Id = :result.taskId];
        System.assertEquals(accountValue.Id, created.WhatId, 'The task should relate to the Account.');
        System.assertEquals(expectedOwner(accountValue.OwnerId), created.OwnerId, 'The Account owner should own the task.');
        System.assertEquals(futureDate, created.ActivityDate, 'dueDate should map to the task due date.');
        System.assertEquals('In Progress', created.Status, 'A future due date should leave the task In Progress.');
    }

    @IsTest
    static void shouldCreateCompletedTaskWhenDueDateHasPassed() {
        Account accountValue = [SELECT Id FROM Account WHERE Name = :ACCOUNT_PREFIX + '1'];
        TaskActivityApiModels.RequestEnvelope envelope = envelope(new List<TaskActivityApiModels.TaskRequest>{
            request(accountValue.Id, 'Past visit', String.valueOf(Date.today().addDays(-1)), null),
            request(accountValue.Id, 'Visit today', String.valueOf(Date.today()), null)
        });

        Test.startTest();
        TaskActivityApiModels.ResponseEnvelope response = TaskActivityService.process(envelope, 'REQ-STATUS');
        Test.stopTest();

        System.assertEquals('Completed', response.results[0].taskStatus, 'A past due date should complete the task.');
        System.assertEquals('In Progress', response.results[1].taskStatus, 'A due date of today should stay In Progress.');
        System.assertEquals(
            'Completed',
            [SELECT Status FROM Task WHERE Id = :response.results[0].taskId].Status,
            'The stored task should be Completed.'
        );
    }

    @IsTest
    static void shouldCreateTaskOnConvertedAccountAndContact() {
        Lead leadValue = [SELECT Id FROM Lead WHERE LastName = :LEAD_PREFIX + '2'];
        Database.LeadConvert convertRequest = new Database.LeadConvert();
        convertRequest.setLeadId(leadValue.Id);
        convertRequest.setConvertedStatus(CONVERTED_STATUS);
        convertRequest.setDoNotCreateOpportunity(true);
        Database.LeadConvertResult convertResult = Database.convertLead(convertRequest);
        System.assert(convertResult.isSuccess(), 'Test Lead conversion should succeed.');
        Account convertedAccount = [SELECT Id, OwnerId FROM Account WHERE Id = :convertResult.getAccountId()];

        TaskActivityApiModels.RequestEnvelope envelope = envelope(new List<TaskActivityApiModels.TaskRequest>{
            request(leadValue.Id, 'Post-conversion call', null, null)
        });

        Test.startTest();
        TaskActivityApiModels.ResponseEnvelope response = TaskActivityService.process(envelope, 'REQ-CONVERTED');
        Test.stopTest();

        TaskActivityApiModels.RecordResult result = response.results[0];
        System.assertEquals(true, result.success, 'A converted Lead task should succeed.');
        System.assertEquals(
            TaskActivityService.TARGET_CONVERTED_LEAD_ACCOUNT,
            result.targetType,
            'A converted Lead should route the task to its Account.'
        );
        Task created = [SELECT WhatId, WhoId, OwnerId FROM Task WHERE Id = :result.taskId];
        System.assertEquals(convertResult.getAccountId(), created.WhatId, 'The task should relate to the converted Account.');
        System.assertEquals(convertResult.getContactId(), created.WhoId, 'The task should name the converted Contact.');
        System.assertEquals(expectedOwner(convertedAccount.OwnerId), created.OwnerId, 'The Account owner should own the task.');
    }

    @IsTest
    static void shouldAssignIntegrationUserWhenLeadOwnedByQueue() {
        Group queueValue = new Group(Name = 'TaskApi Queue', Type = 'Queue');
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert queueValue;
            insert new QueueSobject(QueueId = queueValue.Id, SobjectType = 'Lead');
        }
        Lead leadValue = [SELECT Id FROM Lead WHERE LastName = :LEAD_PREFIX + '3'];
        leadValue.OwnerId = queueValue.Id;
        update leadValue;
        Id currentOwnerId = [SELECT OwnerId FROM Lead WHERE Id = :leadValue.Id].OwnerId;

        TaskActivityApiModels.RequestEnvelope envelope = envelope(new List<TaskActivityApiModels.TaskRequest>{
            request(leadValue.Id, 'Queue lead task', null, null)
        });

        Test.startTest();
        TaskActivityApiModels.ResponseEnvelope response = TaskActivityService.process(envelope, 'REQ-QUEUE');
        Test.stopTest();

        System.assertEquals(true, response.success, 'A queue-owned Lead should still receive the task.');
        System.assertEquals(
            expectedOwner(currentOwnerId),
            [SELECT OwnerId FROM Task WHERE Id = :response.results[0].taskId].OwnerId,
            'A queue cannot own a task, so the integration user should own it.'
        );
    }

    @IsTest
    static void shouldCreateTasksAsIntegrationUserWithoutRecordAccess() {
        Profile integrationProfile = [SELECT Id FROM Profile WHERE Name = :INTEGRATION_PROFILE];
        String uniqueKey = String.valueOf(Datetime.now().getTime());
        User integrationUser = new User(
            ProfileId = integrationProfile.Id,
            LastName = 'TaskApi Integration',
            Alias = 'taskapi',
            Email = 'taskapi.integration@example.com',
            Username = 'taskapi.integration.' + uniqueKey + '@example.com',
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_IN',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert integrationUser;
        Lead leadValue = [SELECT Id FROM Lead WHERE LastName = :LEAD_PREFIX + '5'];
        Account accountValue = [SELECT Id FROM Account WHERE Name = :ACCOUNT_PREFIX + '3'];
        TaskActivityApiModels.RequestEnvelope envelope = envelope(new List<TaskActivityApiModels.TaskRequest>{
            request(leadValue.Id, 'Integration lead task', null, null),
            request(accountValue.Id, 'Integration account task', null, null)
        });

        TaskActivityApiModels.ResponseEnvelope response;
        Test.startTest();
        System.runAs(integrationUser) {
            response = TaskActivityService.process(envelope, 'REQ-INTEGRATION');
        }
        Test.stopTest();

        System.assertEquals(
            2,
            response.successCount,
            'The integration user should create tasks without Lead, Account, or Task permissions: ' + response.results
        );
        System.assertEquals(
            2,
            [SELECT COUNT() FROM Task WHERE CreatedById = :integrationUser.Id],
            'Both tasks should be created by the integration user.'
        );
    }

    @IsTest
    static void shouldRejectInvalidRecordsAndLogFailures() {
        Lead deletedLead = [SELECT Id FROM Lead WHERE LastName = :LEAD_PREFIX + '4'];
        delete deletedLead;
        Account accountValue = [SELECT Id FROM Account WHERE Name = :ACCOUNT_PREFIX + '2'];
        Contact contactValue = new Contact(
            Salutation = 'Mr.',
            FirstName = 'Task',
            LastName = 'Contact',
            MailingCity = CITY,
            MobilePhone = String.valueOf(MOBILE_BASE + 999),
            AccountId = accountValue.Id
        );
        insert contactValue;
        String longSubject = 'S'.repeat(256);

        TaskActivityApiModels.RequestEnvelope envelope = envelope(new List<TaskActivityApiModels.TaskRequest>{
            request(accountValue.Id, 'Valid task', null, null),
            request('not-an-id', 'Bad id', null, null),
            request(contactValue.Id, 'Contact id', null, null),
            request(deletedLead.Id, 'Missing lead', null, null),
            request(accountValue.Id, ' ', null, null),
            request(accountValue.Id, longSubject, null, null),
            request(accountValue.Id, 'Bad date', '30-10-2026', null),
            request(null, 'No id', null, null),
            null
        });

        Test.startTest();
        TaskActivityApiModels.ResponseEnvelope response = TaskActivityService.process(envelope, 'REQ-INVALID');
        Test.stopTest();

        System.assertEquals(false, response.success, 'Invalid records should mark the response unsuccessful.');
        System.assertEquals(1, response.successCount, 'Only the valid record should succeed.');
        System.assertEquals(8, response.failureCount, 'Every invalid record should fail.');
        assertError(response.results[1], 'valid 15 or 18 character');
        assertError(response.results[2], 'Lead or an Account');
        assertError(response.results[3], 'No Lead found');
        assertError(response.results[4], 'subject is required');
        assertError(response.results[5], 'must not exceed 255');
        assertError(response.results[6], 'YYYY-MM-DD');
        assertError(response.results[7], 'recordId is required');
        assertError(response.results[8], 'must not be null');
        System.assertEquals(
            8,
            [SELECT COUNT() FROM API_Log__c WHERE Log_Name__c = 'TaskActivityCreate'],
            'Each failure should be logged.'
        );
    }

    @IsTest
    static void shouldCreateTwoHundredTasksInBulk() {
        List<TaskActivityApiModels.TaskRequest> requests = new List<TaskActivityApiModels.TaskRequest>();
        for (Lead leadValue : [SELECT Id FROM Lead WHERE LastName LIKE :LEAD_PREFIX + '%' LIMIT 100]) {
            requests.add(request(leadValue.Id, 'Bulk lead task', null, null));
        }
        for (Account accountValue : [SELECT Id FROM Account WHERE Name LIKE :ACCOUNT_PREFIX + '%' LIMIT 100]) {
            requests.add(request(accountValue.Id, 'Bulk account task', String.valueOf(Date.today().addDays(1)), null));
        }

        Test.startTest();
        TaskActivityApiModels.ResponseEnvelope response = TaskActivityService.process(envelope(requests), 'REQ-BULK');
        Integer queriesUsed = Limits.getQueries();
        Test.stopTest();

        System.assertEquals(200, response.successCount, 'All 200 tasks should be created.');
        System.assertEquals(200, [SELECT COUNT() FROM Task WHERE Subject LIKE 'Bulk % task'], 'Tasks should persist.');
        System.assert(queriesUsed < 100, 'Bulk processing must stay within SOQL limits.');
    }

    @IsTest
    static void shouldRejectEmptyAndOversizedEnvelopes() {
        List<TaskActivityApiModels.TaskRequest> oversized = new List<TaskActivityApiModels.TaskRequest>();
        for (Integer index = 0; index < 201; index++) {
            oversized.add(request(null, 'Too many', null, null));
        }

        Test.startTest();
        String emptyMessage = captureException(envelope(new List<TaskActivityApiModels.TaskRequest>()));
        String nullMessage = captureException(null);
        String oversizedMessage = captureException(envelope(oversized));
        Test.stopTest();

        System.assert(emptyMessage.contains('at least one task'), 'An empty list should be rejected.');
        System.assert(nullMessage.contains('at least one task'), 'A missing envelope should be rejected.');
        System.assert(oversizedMessage.contains('maximum of 200'), 'More than 200 records should be rejected.');
    }

    @IsTest
    static void shouldLogUnexpectedFailure() {
        Test.startTest();
        TaskActivityService.logUnexpectedFailure('REQ-UNEXPECTED', 'Unexpected failure');
        Test.stopTest();

        API_Log__c logValue = [SELECT Response__c, Registration_Number__c FROM API_Log__c WHERE Log_Name__c = 'TaskActivityCreate'];
        System.assertEquals('Unexpected failure', logValue.Response__c, 'The unexpected error should be logged.');
        System.assertEquals('REQ-UNEXPECTED', logValue.Registration_Number__c, 'The request ID should identify the log.');
    }

    private static Id expectedOwner(Id recordOwnerId) {
        Boolean isActiveUser = recordOwnerId != null
            && recordOwnerId.getSobjectType() == User.SObjectType
            && [SELECT IsActive FROM User WHERE Id = :recordOwnerId].IsActive;
        return isActiveUser ? recordOwnerId : UserInfo.getUserId();
    }

    private static void assertError(TaskActivityApiModels.RecordResult result, String expectedText) {
        System.assertEquals(false, result.success, 'Record ' + result.index + ' should fail.');
        System.assert(
            String.join(result.errors, ' | ').contains(expectedText),
            'Record ' + result.index + ' should report "' + expectedText + '" but reported: ' + result.errors
        );
    }

    private static String captureException(TaskActivityApiModels.RequestEnvelope envelopeValue) {
        try {
            TaskActivityService.process(envelopeValue, 'REQ-ENVELOPE');
        } catch (TaskActivityService.TaskActivityApiException exceptionValue) {
            return exceptionValue.getMessage();
        }
        return '';
    }

    private static TaskActivityApiModels.RequestEnvelope envelope(List<TaskActivityApiModels.TaskRequest> records) {
        TaskActivityApiModels.RequestEnvelope envelopeValue = new TaskActivityApiModels.RequestEnvelope();
        envelopeValue.records = records;
        return envelopeValue;
    }

    private static TaskActivityApiModels.TaskRequest request(
        String recordId,
        String subject,
        String dueDate,
        String comments
    ) {
        TaskActivityApiModels.TaskRequest requestValue = new TaskActivityApiModels.TaskRequest();
        requestValue.recordId = recordId;
        requestValue.subject = subject;
        requestValue.dueDate = dueDate;
        requestValue.comments = comments;
        return requestValue;
    }
}