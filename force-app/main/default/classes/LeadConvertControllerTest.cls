@isTest
public class LeadConvertControllerTest {

    // Helper to get a valid Lead Record Type ID and a corresponding converted status
    private static Map<String, Object> getValidLeadConversionSetup(Boolean excludeCdc) {
        List<String> devNames = new List<String>{'Graduation', 'Masters', 'Phd', 'Undergraduation', 'CLeF'};
        if (!excludeCdc) {
            devNames.add(0, 'CDC');
        }
        
        Map<String, String> rtToProcess = new Map<String, String>{
            'Graduation' => 'Graduation',
            'CDC' => 'CDC',
            'Masters' => 'Masters',
            'Phd' => 'Phd',
            'Undergraduation' => 'Undergraduation',
            'CLeF' => 'CLeF'
        };

        Map<String, String> processToConvertedStatus = new Map<String, String>{
            'Graduation' => 'Submitted',
            'CDC' => 'Closed Won',
            'Masters' => 'Qualified',
            'Phd' => 'Qualified',
            'Undergraduation' => 'Qualified',
            'CLeF' => 'Submitted'
        };

        Set<String> allConvertedStatuses = new Set<String>();
        for (LeadStatus ls : [SELECT MasterLabel FROM LeadStatus WHERE IsConverted = true]) {
            allConvertedStatuses.add(ls.MasterLabel);
        }

        Id selectedRtId = null;
        String selectedStatus = null;

        for (String devName : devNames) {
            Schema.RecordTypeInfo rtInfo = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get(devName);
            if (rtInfo != null && rtInfo.isActive()) {
                String processName = rtToProcess.get(devName);
                String typicalConvertedStatus = processToConvertedStatus.get(processName);
                
                if (allConvertedStatuses.contains(typicalConvertedStatus)) {
                    selectedRtId = rtInfo.getRecordTypeId();
                    selectedStatus = typicalConvertedStatus;
                    break;
                }
            }
        }

        // Fallback if no exact match is found
        if (selectedRtId == null) {
            for (Schema.RecordTypeInfo rtInfo : Schema.SObjectType.Lead.getRecordTypeInfos()) {
                if (rtInfo.isActive() && !rtInfo.isMaster()) {
                    selectedRtId = rtInfo.getRecordTypeId();
                    break;
                }
            }
            if (!allConvertedStatuses.isEmpty()) {
                selectedStatus = new List<String>(allConvertedStatuses)[0];
            } else {
                selectedStatus = 'Closed Won';
            }
        }

        return new Map<String, Object>{
            'recordTypeId' => selectedRtId,
            'convertedStatus' => selectedStatus
        };
    }

    // Helper to create a Lead
    private static Lead createTestLead(Id recordTypeId) {
        Lead ld = new Lead(
            RecordTypeId = recordTypeId,
            Salutation = 'Mr.',
            FirstName = 'John',
            LastName = 'Doe',
            Company = 'Acme Corp',
            Email = 'john.doe@example.com',
            Phone = '1234567890',
            MobilePhone = '9876543210',
            Title = 'Manager',
            Website = 'www.example.com',
            Street = '123 Main St',
            City = 'San Francisco',
            PostalCode = '94105',
            LeadSource = 'Web',
            Industry = 'Technology',
            Description = 'Test Lead Description',
            Academic_Year__c = '2025',
            CDC_Program__c = 'MTech - CSE',
            Drive_Type__c = 'Placement',
            Proposed_Date__c = Date.today(),
            Expected_Students__c = 50,
            Status = 'New'
        );
        insert ld;
        return ld;
    }

    // Helper to create a Lead with Account and Contact pre-populated
    private static Lead createTestLeadWithLookups(Id accountId, Id contactId, Id recordTypeId) {
        Lead ld = new Lead(
            RecordTypeId = recordTypeId,
            Salutation = 'Mr.',
            FirstName = 'Jane',
            LastName = 'Doe',
            Company = 'Acme Corp 2',
            Email = 'jane.doe@example.com',
            Phone = '0987654321',
            MobilePhone = '9876543210',
            Title = 'Director',
            Website = 'www.example2.com',
            Street = '456 Main St',
            City = 'San Francisco',
            PostalCode = '94105',
            LeadSource = 'Web',
            Industry = 'Technology',
            Description = 'Test Lead Description 2',
            Academic_Year__c = '2025',
            CDC_Program__c = 'MTech - CSE',
            Drive_Type__c = 'Placement',
            Proposed_Date__c = Date.today(),
            Expected_Students__c = 30,
            Status = 'New',
            Account__c = accountId,
            Contact__c = contactId
        );
        insert ld;
        return ld;
    }

    @isTest
    static void testGetLeadDetailsWithoutLookups() {
        Map<String, Object> setup = getValidLeadConversionSetup(true); // Exclude CDC
        Id rtId = (Id)setup.get('recordTypeId');
        Lead ld = createTestLead(rtId);

        Test.startTest();
        LeadConvertController.LeadConvertWrapper wrapper = LeadConvertController.getLeadDetails(ld.Id);
        Test.stopTest();

        System.assertNotEquals(null, wrapper, 'Wrapper should not be null');
        System.assertEquals(ld.Id, wrapper.lead.Id, 'Lead ID should match');
        System.assertEquals(null, wrapper.accountId, 'Account ID should be null');
        System.assertEquals('', wrapper.accountName, 'Account name should be empty');
        System.assertEquals(null, wrapper.contactId, 'Contact ID should be null');
        System.assertEquals('', wrapper.contactName, 'Contact name should be empty');
        
        String expectedOppName = ld.Drive_Type__c + '_' + ld.Academic_Year__c + ' - ' + ld.FirstName + ' ' + ld.LastName;
        System.assertEquals(expectedOppName, wrapper.opportunityName, 'Opportunity name should match expected pattern');
        System.assertNotEquals(null, wrapper.convertedStatuses, 'Converted statuses should not be null');
    }

    @isTest
    static void testGetLeadDetailsWithLookups() {
        Map<String, Object> setup = getValidLeadConversionSetup(true); // Exclude CDC
        Id rtId = (Id)setup.get('recordTypeId');

        // Create Account and Contact
        Account acc = new Account(Name = 'Test Account', BillingCity = 'San Francisco');
        insert acc;

        Contact con = new Contact(
            Salutation = 'Mr.',
            FirstName = 'Jane',
            LastName = 'Doe',
            AccountId = acc.Id,
            Email = 'jane.doe@example.com',
            MobilePhone = '1234567890',
            MailingCity = 'San Francisco'
        );
        insert con;

        Lead ld = createTestLeadWithLookups(acc.Id, con.Id, rtId);

        Test.startTest();
        LeadConvertController.LeadConvertWrapper wrapper = LeadConvertController.getLeadDetails(ld.Id);
        Test.stopTest();

        System.assertNotEquals(null, wrapper, 'Wrapper should not be null');
        System.assertEquals(ld.Id, wrapper.lead.Id, 'Lead ID should match');
        System.assertEquals(acc.Id, wrapper.accountId, 'Account ID should match prepopulated Account');
        System.assertEquals(acc.Name, wrapper.accountName, 'Account name should match prepopulated Account name');
        System.assertEquals(con.Id, wrapper.contactId, 'Contact ID should match prepopulated Contact');
        System.assertEquals(con.FirstName + ' ' + con.LastName, wrapper.contactName, 'Contact name should match prepopulated Contact name');
    }

    @isTest
    static void testGetConvertedStatuses() {
        Test.startTest();
        List<LeadConvertController.StatusOption> options = LeadConvertController.getConvertedStatuses();
        Test.stopTest();

        System.assertNotEquals(null, options, 'Options list should not be null');
        List<LeadStatus> activeStatuses = [SELECT MasterLabel FROM LeadStatus WHERE IsConverted = true];
        System.assertEquals(activeStatuses.size(), options.size(), 'Number of options should match converted statuses in org');
        if (!options.isEmpty()) {
            System.assertNotEquals(null, options[0].label, 'Label should be populated');
            System.assertNotEquals(null, options[0].value, 'Value should be populated');
        }
    }

    @isTest
    static void testConvertLeadWithExistingRecords() {
        Map<String, Object> setup = getValidLeadConversionSetup(true); // Exclude CDC
        Id rtId = (Id)setup.get('recordTypeId');
        String convertedStatusName = (String)setup.get('convertedStatus');

        Account acc = new Account(Name = 'Existing Test Account', BillingCity = 'San Francisco');
        insert acc;

        Contact con = new Contact(
            Salutation = 'Mr.',
            FirstName = 'John',
            LastName = 'Doe',
            AccountId = acc.Id,
            Email = 'john.doe@example.com',
            MobilePhone = '1234567890',
            MailingCity = 'San Francisco'
        );
        insert con;

        Lead ld = createTestLeadWithLookups(acc.Id, con.Id, rtId);

        String oppName = 'Test Custom Opp Name';

        Test.startTest();
        LeadConvertController.ConversionResult result = LeadConvertController.convertLead(
            ld.Id,
            acc.Id,
            con.Id,
            oppName,
            true, // createOpportunity
            convertedStatusName
        );
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(true, result.success, 'Result should be successful: ' + result.message);
        System.assertEquals(acc.Id, result.accountId, 'Converted Account ID should match input Account ID');
        System.assertEquals(con.Id, result.contactId, 'Converted Contact ID should match input Contact ID');
        System.assertNotEquals(null, result.opportunityId, 'Opportunity ID should not be null');

        // Verify Opportunity mappings
        Opportunity opp = [
            SELECT Id, Name, AccountId, StageName, CloseDate, OwnerId, LeadSource, Description,
                   Academic_Year__c, Program__c, Drive_Type__c, Drive_Date__c, Expected_Students__c, RecordTypeId
            FROM Opportunity
            WHERE Id = :result.opportunityId
        ];

        // System.assertEquals(oppName, opp.Name);
        // // System.assertEquals(acc.Id, opp.AccountId);
        // System.assertEquals(ld.OwnerId, opp.OwnerId);
        // System.assertEquals(ld.LeadSource, opp.LeadSource);
        // System.assertEquals(ld.Description, opp.Description);
        // System.assertEquals(ld.Academic_Year__c, opp.Academic_Year__c);
        // System.assertEquals(ld.CDC_Program__c, opp.Program__c);
        // System.assertEquals(ld.Drive_Type__c, opp.Drive_Type__c);
        // System.assertEquals(ld.Proposed_Date__c, opp.Drive_Date__c);
        // System.assertEquals(ld.Expected_Students__c, opp.Expected_Students__c);

        // Verify OpportunityContactRole was created
        List<OpportunityContactRole> roles = [
            SELECT Id, ContactId, OpportunityId, Role, IsPrimary
            FROM OpportunityContactRole
            WHERE OpportunityId = :opp.Id
        ];
        System.assertEquals(1, roles.size(), 'One OpportunityContactRole should be created');
        System.assertEquals(con.Id, roles[0].ContactId, 'Contact ID on role should match input Contact');
        System.assertEquals('Decision Maker', roles[0].Role);
        System.assertEquals(true, roles[0].IsPrimary);
    }

    @isTest
    static void testConvertLeadWithoutExistingRecords() {
        Map<String, Object> setup = getValidLeadConversionSetup(true); // Exclude CDC
        Id rtId = (Id)setup.get('recordTypeId');
        String convertedStatusName = (String)setup.get('convertedStatus');

        Lead ld = createTestLead(rtId);

        String oppName = 'Test New Opp Name';

        Test.startTest();
        LeadConvertController.ConversionResult result = LeadConvertController.convertLead(
            ld.Id,
            null, // accountId
            null, // contactId
            oppName,
            true, // createOpportunity
            convertedStatusName
        );
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(true, result.success, 'Result should be successful: ' + result.message);
        System.assertNotEquals(null, result.accountId, 'A new Account should have been created');
        System.assertNotEquals(null, result.contactId, 'A new Contact should have been created');
        System.assertNotEquals(null, result.opportunityId, 'A new Opportunity should have been created');

        // Check if Account Record Type was set correctly (Account RT CDC or fallback)
        Account acc = [SELECT Id, RecordTypeId FROM Account WHERE Id = :result.accountId];
        List<RecordType> cdcAccountRt = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Account' AND DeveloperName = 'CDC' AND IsPersonType = false AND IsActive = true
            LIMIT 1
        ];
        if (!cdcAccountRt.isEmpty()) {
            System.assertEquals(cdcAccountRt[0].Id, acc.RecordTypeId, 'Account Record Type should match DeveloperName CDC');
        } else {
            List<RecordType> fallback = [
                SELECT Id FROM RecordType
                WHERE SObjectType = 'Account' AND IsPersonType = false AND IsActive = true
                LIMIT 1
            ];
            if (!fallback.isEmpty()) {
                System.assertEquals(fallback[0].Id, acc.RecordTypeId, 'Account Record Type should match fallback non-person RT');
            }
        }
    }

    @isTest
    static void testConvertLeadWithoutOpportunity() {
        Map<String, Object> setup = getValidLeadConversionSetup(true); // Exclude CDC
        Id rtId = (Id)setup.get('recordTypeId');
        String convertedStatusName = (String)setup.get('convertedStatus');

        Lead ld = createTestLeadWithLookups(null, null, rtId);

        Account acc = new Account(Name = 'Existing Test Account No Opp', BillingCity = 'San Francisco');
        insert acc;

        Contact con = new Contact(
            Salutation = 'Mr.',
            FirstName = 'John',
            LastName = 'Doe No Opp',
            AccountId = acc.Id,
            Email = 'john.doe.noopp@example.com',
            MobilePhone = '1234567890',
            MailingCity = 'San Francisco'
        );
        insert con;

        Test.startTest();
        LeadConvertController.ConversionResult result = LeadConvertController.convertLead(
            ld.Id,
            acc.Id,
            con.Id,
            null, // opportunityName
            false, // createOpportunity
            convertedStatusName
        );
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(true, result.success, 'Result should be successful');
        System.assertEquals(acc.Id, result.accountId, 'Account should be mapped');
        System.assertEquals(con.Id, result.contactId, 'Contact should be mapped');
        System.assertEquals(null, result.opportunityId, 'No Opportunity should be created when createOpportunity is false');
    }

    @isTest
    static void testConvertLeadInvalidLeadId() {
        Map<String, Object> setup = getValidLeadConversionSetup(true);
        String convertedStatusName = (String)setup.get('convertedStatus');

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            LeadConvertController.convertLead(
                '00Q000000000000AAA', // Fake Lead ID
                null,
                null,
                'Test Opp Name',
                true,
                convertedStatusName
            );
        } catch (IllegalArgumentException e) {
            exceptionThrown = true;
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Exception should have been thrown due to invalid Lead ID');
    }

    @isTest
    static void testConvertLeadInvalidStatus() {
        Map<String, Object> setup = getValidLeadConversionSetup(true);
        Id rtId = (Id)setup.get('recordTypeId');
        Lead ld = createTestLead(rtId);

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            LeadConvertController.convertLead(
                ld.Id,
                null,
                null,
                'Test Opp Name',
                true,
                'InvalidConvertedStatusLabelXYZ'
            );
        } catch (IllegalArgumentException e) {
            exceptionThrown = true;
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Exception should have been thrown due to invalid status');
    }
}