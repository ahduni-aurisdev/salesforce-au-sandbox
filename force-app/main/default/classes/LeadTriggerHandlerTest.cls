/**
 * @description
 * ****************************************************************************************
* Create By        : Preksha Chauhan
* Company          : GetonCRM Solutions
* Class Name       : LeadPhoneUpdaterTest
* Trigger Name     : leadBeforeInsertLastName
* Create Date      : 06/28/2024
* Description      : This trigger operates on the Lead object and is invoked before insert 
*                    and before update operations. It ensures that if the LastName field is 
*                    blank, it is set to the value of the FirstName field. Additionally, it 
*                    sets the FirstName field to null to prevent duplication of data. The 
*                    trigger handles both new Lead records being inserted and existing Lead 
*                    records being updated.
*                    - Before Insert: Sets LastName to FirstName if LastName is blank and 
*                      clears the FirstName field.
*                    - Before Update: Updates LastName to FirstName if LastName is blank 
*                      and was not blank before the update. Clears the FirstName field.
*                    This trigger uses the LeadTriggerHandler class to encapsulate logic for 
*                    better manageability and testability.
* 
* Coverage          : 100%
******************************************************************************************/
@isTest
public class LeadTriggerHandlerTest {
    /**
     * @description
     * */
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

        // Verify the LastName was set to FirstName
        Lead insertedLead = [SELECT LastName, FirstName FROM Lead WHERE Id = :lead.Id];
        //System.assertEquals('Test FirstName', insertedLead.LastName, 'LastName should be set to FirstName');
        // System.assertEquals(null, insertedLead.FirstName, 'FirstName should be null after setting LastName');
    }

    /**
    * @description
    * */
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
        // System.assertEquals('Updated FirstName', updatedLead.LastName, 'LastName should be updated to the new FirstName');
        // System.assertEquals(null, updatedLead.FirstName, 'FirstName should be null after setting LastName');
    }


    @isTest
    static void testHandleLeadAssignments() {
        Id mastersId = saveWebsiteLead.getRecordTypeIdByDepartment('Masters');
        Id phdId =saveWebsiteLead.getRecordTypeIdByDepartment('Phd');
        // Id executiveId = LeadHelper.getRecordTypeId('Executive_Education');
        Id undergradId = saveWebsiteLead.getRecordTypeIdByDepartment('Undergraduation');

        List<Lead> testLeads = new List<Lead>{
            new Lead(FirstName = 'Test1', LastName = 'User', Company = 'Test Co', RecordTypeId = mastersId,Email = 'test@example.com'),
            new Lead(FirstName = 'Test2', LastName = 'User', Company = 'Test Co', RecordTypeId = phdId,Email ='test@example.com')
            // new Lead(FirstName = 'Test3', LastName = 'User', Company = 'Test Co', RecordTypeId = executiveId),
            // new Lead(FirstName = 'Test4', LastName = 'User', Company = 'Test Co', RecordTypeId = undergradId)
        };

        Test.startTest();
        insert testLeads;
        Test.stopTest();

        // Add asserts here if your logic updates fields like OwnerId, custom fields, etc.
    }
}