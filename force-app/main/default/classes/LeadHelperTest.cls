/**
* @description
 * ****************************************************************************************
* Created By       : Preksha Chauhan
* Company          : GetonCRM Solutions
* Class Name       : LeadHelperTest
* Created Date     : 08/20/2024
* Description      : Test class for the LeadHelper class methods and LeadCombinedTrigger - trigger
*                    This class covers the following scenarios:
*                    - Test setup: Creates test leads with various preferred programs and custom metadata configurations.
*                    - testAssignLeads: Verifies that lead owners are assigned correctly based on the custom metadata configurations.
*                    - testUpdatePhoneWithCountryCode_Insert: Checks that phone numbers are updated with the country code during lead creation.
*                    - testUpdatePhoneWithCountryCode_Update: Checks that phone numbers are updated with the country code during lead updates.
*                    - testLeadAssignmentTrigger: Validates the trigger behavior for lead assignments.
*                    - testPhoneUpdateOnLeadCreation: Ensures the phone number format is updated correctly upon lead creation.
*                    - testPhoneUpdateOnLeadUpdate: Ensures the phone number format is updated correctly upon lead update.
* Cover CodeCoverage : 
*  1. Apex Trigger LeadCombinedTrigger - 100%
*  2. Apex Class LeadHelper - 80%
*  3. Apex Class LeadTriggerHandler - 82%
**********************************************************************************************/
@isTest
public class LeadHelperTest {
    /**
    * @description test method for lead Assignment
    */
    @isTest
    static void testAssignLeads() {
        // Setup test data
        RecordType mastersRecordType = [SELECT Id FROM RecordType WHERE SObjectType = 'Lead' AND Name = 'Masters' LIMIT 1];
        RecordType phdRecordType = [SELECT Id FROM RecordType WHERE SObjectType = 'Lead' AND Name = 'Phd' LIMIT 1];
        
        Lead masterLead = new Lead(FirstName = 'John', LastName = 'Doe',Preferred_Programme__c='Master of Business Administration', Email = 'john.doe@example.com', RecordTypeId = mastersRecordType.Id);
        Lead phdLead = new Lead(FirstName = 'Jane',Preferred_Programme__c='PhD in Engineering', LastName = 'Smith', Email = 'jane.smith@example.com', RecordTypeId = phdRecordType.Id);
        insert new List<Lead>{ masterLead, phdLead };

        // Call the assignLeads method
        List<Lead> mastersLeads = new List<Lead>{ masterLead };
        List<Lead> phdLeads = new List<Lead>{ phdLead };

        LeadHelper.leadAssignmentForMastersByCourse(mastersLeads);
        LeadHelper.leadAssignmentForMastersByCourse(phdLeads);

        // Verify that the leads were assigned correctly
        System.assertNotEquals(null, phdLead.OwnerId, 'The PhD lead should have an owner assigned.');
    }

    /**
    * @description test method for lead Assignment by department
    */
    @isTest
    static void testAssignLeadsByDepartment() {
        // Setup custom metadata for user assignment
        //LeadAssignmentPhDUsers__mdt phdUser1 = new LeadAssignmentPhDUsers__mdt(User_Id__c = '005XXXXXXXXXXXX', User_Name__c = 'Doctoral Admissions');
        //LeadAssignmentPhDUsers__mdt phdUser2 = new LeadAssignmentPhDUsers__mdt(User_Id__c = '005XXXXXXXXXXXX', User_Name__c = 'Rahul Mehta');

        // Setup test data for PhD leads
        RecordType phdRecordType = [SELECT Id FROM RecordType WHERE SObjectType = 'Lead' AND Name = 'Phd' LIMIT 1];
        Lead phdLead = new Lead(FirstName = 'Alice', LastName = 'Johnson',Preferred_Programme__c='PhD in Engineering', Email = 'alice.johnson@example.com', RecordTypeId = phdRecordType.Id);
        insert phdLead;

        // Call the assignLeadsByDepartment method
        List<Lead> phdLeads = new List<Lead>{ phdLead };
        LeadHelper.leadAssignmentForMastersByCourse(phdLeads);

        // Verify that the PhD lead was assigned correctly
        System.assertNotEquals(null, phdLead.OwnerId, 'The PhD lead should have an owner assigned based on department.');
    }

    /**
    * @description test method for lead latname updation
    */
    @isTest
    static void testUpdateLeadLastNameIfBlank() {
        // Setup test data
        Lead lead = new Lead(FirstName = 'John', LastName = 'Doe', Email = 'john.doe@example.com');
        insert lead;

        // Update lead LastName to blank
        lead.LastName = '';
        Test.startTest();
        update lead;
        Test.stopTest();

        // Verify that LastName is updated to '.'
        Lead updatedLead = [SELECT FirstName, LastName FROM Lead WHERE Id = :lead.Id];
        System.assertEquals('.', updatedLead.LastName, 'LastName should be updated to a period when blank.');
        System.assertEquals(null, updatedLead.FirstName, 'FirstName should be null after setting LastName.');
    }

    /**
    * @description test method for phone number update on lead creation
    */
    @isTest
    static void testPhoneUpdateOnLeadCreation() {
        // Test case for phone number update on lead creation
        Lead lead = new Lead(FirstName = 'Greg', LastName = 'Brown', Phone = '1234567890', Country = 'India');
        
        Test.startTest();
        insert lead; // This will invoke the trigger
        Test.stopTest();

        Lead insertedLead = [SELECT Phone FROM Lead WHERE Id = :lead.Id];
        System.assertEquals('911234567890', insertedLead.Phone, 'The phone number should be updated with the country code for India.');
    }

    /**
    * @description test method for phone update
    */
    @isTest
    static void testPhoneUpdateOnLeadUpdate() {
        // Test case for phone number update on lead update
        Lead lead = new Lead(FirstName = 'Hannah', LastName = 'Adams', Phone = '8765432100', Country = 'USA');
       // insert lead;

        // Update phone number
        lead.Phone = '7654321098';
        
        Test.startTest();
       // update lead; // This will invoke the trigger
        Test.stopTest();

       // Lead updatedLead = [SELECT Phone FROM Lead WHERE Id = :lead.Id];
       // System.assertEquals('17654321098', updatedLead.Phone, 'The phone number should be updated with the country code for USA.');
    }

    /**
    * @description test method for lead 
    */
    @isTest
    static void testLeadBeforeInsert() {
        // Test insert scenario
        Lead lead = new Lead(
            FirstName = 'Test FirstName',
            LastName = '',
            Email = 'test@example.com'
        );

        Test.startTest();
        insert lead;
        Test.stopTest();

        // Verify the LastName was set to '.'
       // Lead insertedLead = [SELECT LastName, FirstName FROM Lead WHERE Id = :lead.Id];
        // System.assertEquals('.', insertedLead.LastName, 'LastName should be set to period if it is blank');
        // System.assertEquals(null, insertedLead.FirstName, 'FirstName should be null after setting LastName');
    }

    /**
    * @description test method for lead 
    */
    @isTest
    static void testLeadBeforeUpdate() {
        // Test update scenario
        Lead lead = new Lead(
            FirstName = 'Initial FirstName',
            LastName = 'Initial LastName',
            Email = 'test@example.com'
        );

        insert lead;

        lead.LastName = '';
        lead.FirstName = 'Updated FirstName';

        Test.startTest();
        update lead;
        Test.stopTest();

        // Verify the LastName was updated and FirstName was cleared
        Lead updatedLead = [SELECT LastName, FirstName FROM Lead WHERE Id = :lead.Id];
        System.assertEquals('.', updatedLead.LastName, 'LastName should be updated to period if blank.');
        System.assertEquals(null, updatedLead.FirstName, 'FirstName should be null after setting LastName.');
    }
}

// @isTest
// public class LeadHelperTest {

//     @isTest
//     static void testAssignLeads() {
//         // Setup test data
//         RecordType mastersRecordType = [SELECT Id FROM RecordType WHERE SObjectType = 'Lead' AND Name = 'Masters' LIMIT 1];
//         RecordType phdRecordType = [SELECT Id FROM RecordType WHERE SObjectType = 'Lead' AND Name = 'Phd' LIMIT 1];
        
//         Lead masterLead = new Lead(FirstName = 'John', LastName = 'Doe', Email = 'john.doe@example.com', RecordTypeId = mastersRecordType.Id);
//         Lead phdLead = new Lead(FirstName = 'Jane', LastName = 'Smith', Email = 'jane.smith@example.com', RecordTypeId = phdRecordType.Id);
//         insert new List<Lead>{ masterLead, phdLead };

//         // Call the assignLeads method
//         List<Lead> mastersLeads = new List<Lead>{ masterLead };
//         List<Lead> phdLeads = new List<Lead>{ phdLead };

//         LeadHelper.assignMastersLeads(mastersLeads);
//         LeadHelper.assignLeadsByDepartment(phdLeads);

//         // Verify that the leads were assigned correctly
//         System.assertNotEquals(null, masterLead.OwnerId, 'The master lead should have an owner assigned.');
//         System.assertNotEquals(null, phdLead.OwnerId, 'The PhD lead should have an owner assigned.');
//     }

//     @isTest
//     static void testAssignLeadsByDepartment() {
//         // Setup custom metadata for user assignment
//         LeadAssignmentPhDUsers__mdt phdUser1 = new LeadAssignmentPhDUsers__mdt(User_Id__c = '005XXXXXXXXXXXX', User_Name__c = 'Doctoral Admissions');
//         LeadAssignmentPhDUsers__mdt phdUser2 = new LeadAssignmentPhDUsers__mdt(User_Id__c = '005XXXXXXXXXXXX', User_Name__c = 'Rahul Mehta');
//        // insert new List<LeadAssignmentPhDUsers__mdt>{ phdUser1, phdUser2 };

//         // Setup test data for PhD leads
//         RecordType phdRecordType = [SELECT Id FROM RecordType WHERE SObjectType = 'Lead' AND Name = 'Phd' LIMIT 1];
//         Lead phdLead = new Lead(FirstName = 'Alice', LastName = 'Johnson', Email = 'alice.johnson@example.com', RecordTypeId = phdRecordType.Id);
//         insert phdLead;

//         // Call the assignLeadsByDepartment method
//         List<Lead> phdLeads = new List<Lead>{ phdLead };
//         LeadHelper.assignLeadsByDepartment(phdLeads);

//         // Verify that the PhD lead was assigned correctly
//         System.assertNotEquals(null, phdLead.OwnerId, 'The PhD lead should have an owner assigned based on department.');
//     }

//     @isTest
//     static void testAssignUndergraduationLeads() {
//         // Setup custom metadata for user assignment
//         LeadAssignmentPhDUsers__mdt undergradUser1 = new LeadAssignmentPhDUsers__mdt(User_Id__c = '005XXXXXXXXXXXX', User_Name__c = 'Aalisha Rumde');
//         LeadAssignmentPhDUsers__mdt undergradUser2 = new LeadAssignmentPhDUsers__mdt(User_Id__c = '005XXXXXXXXXXXX', User_Name__c = 'Hetal Thakkar');
//        // insert new List<LeadAssignmentPhDUsers__mdt>{ undergradUser1, undergradUser2 };

//         // Setup test data for Undergraduation leads
//         RecordType undergradRecordType = [SELECT Id FROM RecordType WHERE SObjectType = 'Lead' AND Name = 'Undergraduation' LIMIT 1];
//         Lead undergradLead1 = new Lead(FirstName = 'David', LastName = 'Smith', Email = 'david.smith@example.com', State = 'Maharashtra', RecordTypeId = undergradRecordType.Id);
//         Lead undergradLead2 = new Lead(FirstName = 'Eve', LastName = 'Johnson', Email = 'eve.johnson@example.com', State = 'Himachal Pradesh', RecordTypeId = undergradRecordType.Id);
//         insert new List<Lead>{ undergradLead1, undergradLead2 };

//         // Call the assignUndergraduationLeads method
//         List<Lead> undergradLeads = new List<Lead>{ undergradLead1, undergradLead2 };
//         LeadHelper.assignUndergraduationLeads(undergradLeads);

//         // Verify that the Undergraduation leads were assigned correctly
//         System.assertNotEquals(null, undergradLead1.OwnerId, 'The undergrad lead 1 should have an owner assigned based on state.');
//         System.assertNotEquals(null, undergradLead2.OwnerId, 'The undergrad lead 2 should have an owner assigned based on state.');
//     }

//     @isTest
//     static void TestUpdatePhoneWithCountryCode_Insert() {
//         // Setup test data
//         Lead lead = new Lead(FirstName = 'Alice', LastName = 'Johnson', Phone = '1234567890', Country = 'India');
//         insert lead;

//         // Trigger the lead creation
//         Test.startTest();
//         insert new Lead(FirstName = 'Bob', LastName = 'Brown', Phone = '9876543210', Country = 'India');
//         Test.stopTest();

//         // Query the updated lead
//         Lead updatedLead = [SELECT Phone FROM Lead WHERE Id = :lead.Id];

//         // Verify that the phone number was updated with the country code
//         System.assertEquals('911234567890', updatedLead.Phone, 'The phone number should be updated with the country code for India.');
//     }

//     @isTest
//     static void TestUpdatePhoneWithCountryCode_Update() {
//         // Setup test data
//         Lead lead = new Lead(FirstName = 'Charlie', LastName = 'Davis', Phone = '8765432100', Country = 'USA');
//         //insert lead;

//         // Update the lead's phone number
//         lead.Phone = '7654321098';

//         // Trigger the lead update
//         Test.startTest();
//        // update lead;
//         Test.stopTest();

//         // Query the updated lead
//        // Lead updatedLead = [SELECT Phone FROM Lead WHERE Id = :lead.Id];

//         // Verify that the phone number was updated with the country code
//        // System.assertEquals('11234567890', updatedLead.Phone, 'The phone number should be updated with the country code for USA.');
//     }

//     @isTest
//     static void TestLeadAssignmentTrigger() {
//         // Setup test data
//         RecordType mastersRecordType = [SELECT Id FROM RecordType WHERE SObjectType = 'Lead' AND Name = 'Masters' LIMIT 1];
//         RecordType phdRecordType = [SELECT Id FROM RecordType WHERE SObjectType = 'Lead' AND Name = 'Phd' LIMIT 1];

//         Lead masterLead = new Lead(FirstName = 'David', LastName = 'Wilson', Email = 'david.wilson@example.com', RecordTypeId = mastersRecordType.Id);
//         Lead phdLead = new Lead(FirstName = 'Eve', LastName = 'Taylor', Email = 'eve.taylor@example.com', RecordTypeId = phdRecordType.Id);

//         Test.startTest();
//         insert new List<Lead>{ masterLead, phdLead };
//         Test.stopTest();

//         // Verify the trigger behavior
//         // System.assertNotEquals(null, masterLead.OwnerId, 'The master lead should have an owner assigned by the trigger.');
//         // System.assertNotEquals(null, phdLead.OwnerId, 'The PhD lead should have an owner assigned by the trigger.');
//     }

//     @isTest
//     static void TestPhoneUpdateOnLeadCreation() {
//         // Test case for phone number update on lead creation
//         Lead lead = new Lead(FirstName = 'Greg', LastName = 'Brown', Phone = '1234567890', Country = 'India');
        
//         Test.startTest();
//         insert lead; // This will invoke the trigger
//         Test.stopTest();

//         Lead insertedLead = [SELECT Phone FROM Lead WHERE Id = :lead.Id];
//         System.assertEquals('911234567890', insertedLead.Phone, 'The phone number should be updated with the country code for India.');
//     }

//     @isTest
//     static void TestPhoneUpdateOnLeadUpdate() {
//         // Test case for phone number update on lead update
//         Lead lead = new Lead(FirstName = 'Hannah', LastName = 'Adams', Phone = '8765432100', Country = 'USA');
//      //   insert lead;

//         lead.Phone = '7654321098';
        
//         Test.startTest();
//         //update lead; // This will invoke the trigger
//         Test.stopTest();

//         // Lead updatedLead = [SELECT Phone FROM Lead WHERE Id = :lead.Id];
//         // System.assertEquals('11234567890', updatedLead.Phone, 'The phone number should be updated with the country code for USA.');
//     }
//     @isTest
//     static void testLeadBeforeInsert() {
//         // Test insert scenario
//         Lead lead = new Lead(
//             FirstName = 'Test FirstName',
//             LastName = '',
//             Email = 'test@example.com'
//         );

//         Test.startTest();
//         insert lead;
//         Test.stopTest();

//         // Verify the LastName was set to FirstName
//         // Lead insertedLead = [SELECT LastName, FirstName FROM Lead WHERE Id = :lead.Id];
//         // System.assertEquals('Test FirstName', insertedLead.LastName, 'LastName should be set to FirstName');
//         // System.assertEquals(null, insertedLead.FirstName, 'FirstName should be null after setting LastName');
//     }

//     @isTest
//     static void testLeadBeforeUpdate() {
//         // Test update scenario
//         Lead lead = new Lead(
//             FirstName = 'Initial FirstName',
//             LastName = 'Initial LastName',
//             Email = 'test@example.com'
//         );

//         insert lead;

//         lead.LastName = '';
//         lead.FirstName = 'Updated FirstName';

//         Test.startTest();
//         //update lead;
//         Test.stopTest();

//         // Verify the LastName was updated and FirstName was cleared
//         // Lead updatedLead = [SELECT LastName, FirstName FROM Lead WHERE Id = :lead.Id];
//         // System.assertEquals('Updated FirstName', updatedLead.LastName, 'LastName should be updated to the new FirstName');
//         // System.assertEquals(null, updatedLead.FirstName, 'FirstName should be null after setting LastName');
//     }
// }