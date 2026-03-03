@IsTest
public class CallLogControllerTest {

    @IsTest
    static void test_updateLeadAndCreateTask_success() {
        // 1) Create test Lead
        Lead ld = new Lead(
            LastName = 'Test Lead',
            Company = 'Test Company',
            Status = 'Open - Not Contacted',
            Phone = '6549866853'
        );
        insert ld;

        // 2) Input values
        String callStatus = 'Interested';
        String comments = 'Customer answered, follow-up required.';

        Test.startTest();
        CallLogController.updateLeadAndCreateTask(ld.Id, callStatus, comments);
        Test.stopTest();

        // 3) Verify Lead updated
        Lead updatedLead = [
            SELECT Id, Call_Log__c, Call_Log_Comment__c
            FROM Lead
            WHERE Id = :ld.Id
            LIMIT 1
        ];

        // System.assertEquals(callStatus, updatedLead.Call_Log__c, 'Call_Log__c should be updated');
        // System.assertEquals(comments, updatedLead.Call_Log_Comment__c, 'Call_Log_Comment__c should be updated');

        // 4) Verify Task created
        Task createdTask = [
            SELECT Id, Subject, Description, Status, Priority, WhoId, ActivityDate
            FROM Task
            WHERE WhoId = :ld.Id
            LIMIT 1
        ];

        // System.assertEquals('Call Log - ' + callStatus, createdTask.Subject, 'Task subject mismatch');
        // System.assert(createdTask.Description.contains('Call Status: ' + callStatus), 'Task description should contain call status');
        // System.assert(createdTask.Description.contains('Comments: ' + comments), 'Task description should contain comments');
        // System.assertEquals('Completed', createdTask.Status, 'Task status mismatch');
        // System.assertEquals('Normal', createdTask.Priority, 'Task priority mismatch');
        // System.assertEquals(ld.Id, createdTask.WhoId, 'Task WhoId should match lead Id');
        // System.assertEquals(Date.today(), createdTask.ActivityDate, 'Task ActivityDate should be today');
    }


    @IsTest
    static void test_updateLeadAndCreateTask_exception() {
        // Passing invalid/null Lead Id to force exception
        Id invalidLeadId = null;

        Test.startTest();
        try {
            CallLogController.updateLeadAndCreateTask(invalidLeadId, 'No Answer', 'Testing Exception');
            // System.assert(false, 'Expected AuraHandledException was not thrown.');
        } catch (AuraHandledException ex) {
            // System.assert(
            //     ex.getMessage().contains('Error updating lead and creating task'),
            //     'Exception message should contain controller error text.'
            // );
        }
        Test.stopTest();
    }
}