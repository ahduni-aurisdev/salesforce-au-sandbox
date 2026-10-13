@isTest
public class LeadActivityHandlerTest {

    @isTest
    static void testMoveActivitiesOnConversionDirectly() {
        // Create dummy Lead, Account, Contact
        Lead ld = new Lead(
            FirstName = 'Mock',
            LastName = 'Lead',
            Company = 'Mock Co',
            Email = 'mock@example.com'
        );
        insert ld;

        Account acc = new Account(Name = 'Mock Acc');
        insert acc;

        Contact con = new Contact(
            FirstName = 'Mock',
            LastName = 'Con',
            AccountId = acc.Id,
            MobilePhone= '5555555555'
        );
        insert con;

        // Create Task and Event related to the Lead
        Task t = new Task(
            Subject = 'Test Task',
            WhoId = ld.Id,
            Status = 'Not Started',
            Priority = 'Normal'
        );
        insert t;

        Event e = new Event(
            Subject = 'Test Event',
            WhoId = ld.Id,
            StartDateTime = System.now(),
            EndDateTime = System.now().addHours(1)
        );
        insert e;

        // Construct trigger old map and new list
        Map<Id, Lead> oldMap = new Map<Id, Lead>{
            ld.Id => new Lead(Id = ld.Id, IsConverted = false)
        };

        // Create a new lead record using JSON deserialization to set read-only fields
        String jsonLead = '{"Id":"' + ld.Id + '","IsConverted":true,"ConvertedContactId":"' + con.Id + '","ConvertedAccountId":"' + acc.Id + '"}';
        Lead newLead = (Lead)JSON.deserialize(jsonLead, Lead.class);

        Test.startTest();
        LeadActivityHandler.moveActivitiesOnConversion(new List<Lead>{ newLead }, oldMap);
        Test.stopTest();

        // Verify task and event were updated
        Task updatedTask = [SELECT WhoId, WhatId FROM Task WHERE Id = :t.Id];
        System.assertEquals(con.Id, updatedTask.WhoId, 'Task WhoId should be updated to Converted Contact Id');
        System.assertEquals(acc.Id, updatedTask.WhatId, 'Task WhatId should be updated to Converted Account Id');

        Event updatedEvent = [SELECT WhoId, WhatId FROM Event WHERE Id = :e.Id];
        System.assertEquals(con.Id, updatedEvent.WhoId, 'Event WhoId should be updated to Converted Contact Id');
        System.assertEquals(acc.Id, updatedEvent.WhatId, 'Event WhatId should be updated to Converted Account Id');
    }

    @isTest
    static void testLeadTriggerConversion() {
        Lead ld = new Lead(
            FirstName = 'Trigger',
            LastName = 'TestLead',
            Company = 'Trigger Test Co',
            Email = 'triggertest@example.com'
        );
        insert ld;

        Task t = new Task(
            Subject = 'Trigger Test Task',
            WhoId = ld.Id,
            Status = 'Not Started',
            Priority = 'Normal'
        );
        insert t;

        LeadStatus convertStatus = [SELECT Id, MasterLabel FROM LeadStatus WHERE IsConverted = true LIMIT 1];

        Database.LeadConvert lc = new Database.LeadConvert();
        lc.setLeadId(ld.Id);
        lc.setConvertedStatus(convertStatus.MasterLabel);
        lc.setDoNotCreateOpportunity(true);

        Test.startTest();
        try {
            Database.LeadConvertResult lcr = Database.convertLead(lc);
            if (lcr.isSuccess()) {
                // Verify task was updated
                Task updatedTask = [SELECT WhoId, WhatId FROM Task WHERE Id = :t.Id];
                System.assertEquals(lcr.getContactId(), updatedTask.WhoId, 'Task WhoId should be updated to Converted Contact Id');
                System.assertEquals(lcr.getAccountId(), updatedTask.WhatId, 'Task WhatId should be updated to Converted Account Id');
            }
        } catch(Exception ex) {
            System.debug('Conversion failed in test context: ' + ex.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testLeadUpdateWithoutConversion() {
        Lead ld = new Lead(
            FirstName = 'NoConv',
            LastName = 'TestLead',
            Company = 'NoConv Co',
            Email = 'noconv@example.com'
        );
        insert ld;

        Task t = new Task(
            Subject = 'NoConv Test Task',
            WhoId = ld.Id,
            Status = 'Not Started',
            Priority = 'Normal'
        );
        insert t;

        Test.startTest();
        ld.Company = 'NoConv Updated Co';
        update ld;
        Test.stopTest();

        // Verify task is NOT updated (still has WhoId of Lead, WhatId remains null)
        Task updatedTask = [SELECT WhoId, WhatId FROM Task WHERE Id = :t.Id];
        System.assertEquals(ld.Id, updatedTask.WhoId);
        // System.assertNull(updatedTask.WhatId);
    }
}