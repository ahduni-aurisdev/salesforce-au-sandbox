@isTest
public class WhatsappTrackingDataTriggerTest {

    @isTest
    static void testWhatsappTrackingDataTrigger_Insert() {
        // Create test data for Leads
        Lead testLead1 = new Lead(FirstName = 'Test', LastName = 'Lead1', Company = 'Test Company');
        Lead testLead2 = new Lead(FirstName = 'Test', LastName = 'Lead2', Company = 'Test Company');
        insert new List<Lead>{ testLead1, testLead2 };

        // Create test data for Whatsapp_tracking_data__c
        Whatsapp_tracking_data__c trackingData1 = new Whatsapp_tracking_data__c(
            Template_Name__c = 'Template1',
            Lead__c = testLead1.Id,
            Whatsapp_status__c = 'Read',
            Message_Data_and_time__c = DateTime.now()
        );
        
        Whatsapp_tracking_data__c trackingData2 = new Whatsapp_tracking_data__c(
            Template_Name__c = 'Template2',
            Lead__c = testLead2.Id,
            Whatsapp_status__c = 'Failed',
            Message_Data_and_time__c = DateTime.now(),
            Reason__c = 'Invalid number'
        );
        
            Whatsapp_tracking_data__c trackingData3 = new Whatsapp_tracking_data__c(
            Template_Name__c = 'Template3',
            Lead__c = testLead2.Id,
            Whatsapp_status__c = 'sent',
            Message_Data_and_time__c = DateTime.now()
        );
                    Whatsapp_tracking_data__c trackingData4 = new Whatsapp_tracking_data__c(
            Template_Name__c = 'Template4',
            Lead__c = testLead2.Id,
            Whatsapp_status__c = 'delivered',
            Message_Data_and_time__c = DateTime.now()
        );

        insert new List<Whatsapp_tracking_data__c>{ trackingData1, trackingData2,trackingData3,trackingData4 };

        // Assert that Whatsapp_Summary__c records were created
        List<Whatsapp_Summary__c> summaries = [
            SELECT Template_Name__c, Lead__c, Read__c, Sent__c, Delivered__c, Failed__c, Failed_reason__c
            FROM Whatsapp_Summary__c
            WHERE Lead__c IN :new List<Id>{testLead1.Id, testLead2.Id}
        ];

        System.assertEquals(4, summaries.size(), 'Two Whatsapp_Summary__c records should be created.');

        for (Whatsapp_Summary__c summary : summaries) {
            if (summary.Template_Name__c == 'Template1') {
                System.assert(summary.Read__c, 'Read__c should be true for Template1.');
            } else if (summary.Template_Name__c == 'Template2') {
                System.assert(summary.Failed__c, 'Failed__c should be true for Template2.');
                System.assertEquals('Invalid number', summary.Failed_reason__c, 'Failed_reason__c should match.');
            }
        }
    }

    @isTest
    static void testWhatsappTrackingDataTrigger_Update() {
        // Create a Lead
        Lead testLead = new Lead(FirstName = 'Test', LastName = 'Lead', Company = 'Test Company');
        insert testLead;

        // Create an existing Whatsapp_Summary__c record
        Whatsapp_Summary__c summary = new Whatsapp_Summary__c(
            Template_Name__c = 'Template1',
            Lead__c = testLead.Id,
            Read__c = false
        );
        insert summary;

        // Create new Whatsapp_tracking_data__c with an updated status
        Whatsapp_tracking_data__c trackingData = new Whatsapp_tracking_data__c(
            Template_Name__c = 'Template1',
            Lead__c = testLead.Id,
            Whatsapp_status__c = 'Read',
            Message_Data_and_time__c = DateTime.now()
        );
        insert trackingData;

                // Create new Whatsapp_tracking_data__c with an updated status
        Whatsapp_tracking_data__c trackingData1 = new Whatsapp_tracking_data__c(
            Template_Name__c = 'Template1',
            Lead__c = testLead.Id,
            Whatsapp_status__c = 'delivered',
            Message_Data_and_time__c = DateTime.now()
        );
        insert trackingData1;
        // Assert that the existing Whatsapp_Summary__c record was updated
        summary = [
            SELECT Read__c, Read_Date_and_Time__c
            FROM Whatsapp_Summary__c
            WHERE Id = :summary.Id
        ];

        System.assert(summary.Read__c, 'Read__c should be updated to true.');
        System.assertNotEquals(null, summary.Read_Date_and_Time__c, 'Read_Date_and_Time__c should be updated.');
    }

    @isTest
    static void testWhatsappTrackingDataTrigger_NoDuplicateInsert() {
        // Create a Lead
        Lead testLead = new Lead(FirstName = 'Test', LastName = 'Lead', Company = 'Test Company');
        insert testLead;

        // Create an existing Whatsapp_Summary__c record
        Whatsapp_Summary__c summary = new Whatsapp_Summary__c(
            Template_Name__c = 'Template1',
            Lead__c = testLead.Id,
            Read__c = false
        );
        insert summary;

        // Create new Whatsapp_tracking_data__c with the same Template_Name__c and Lead__c
        Whatsapp_tracking_data__c trackingData = new Whatsapp_tracking_data__c(
            Template_Name__c = 'Template1',
            Lead__c = testLead.Id,
            Whatsapp_status__c = 'Sent',
            Message_Data_and_time__c = DateTime.now()
        );
        insert trackingData;

        // Assert that no duplicate Whatsapp_Summary__c records were created
        List<Whatsapp_Summary__c> summaries = [
            SELECT Template_Name__c, Lead__c
            FROM Whatsapp_Summary__c
            WHERE Lead__c = :testLead.Id
        ];

        System.assertEquals(1, summaries.size(), 'Only one Whatsapp_Summary__c record should exist for the Lead.');
    }
}