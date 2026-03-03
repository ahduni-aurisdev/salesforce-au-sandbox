@isTest
private class LeadAssignmentCtrlTest {
    @isTest
    static void testRunAssignmentRules() {
        // Create test lead
        Lead testLead = new Lead(
            FirstName = 'Test',
            LastName = 'Lead',
            Company = 'Test Company',
            Phone = '9876543210'
        );
        insert testLead;
        
        // Get the test lead Id
        Id testLeadId = testLead.Id;
        
        Test.startTest();
        // Call the invocable method
        LeadAssignmentCtrl.runAssignmentRules(new List<Id>{testLeadId});
        Test.stopTest();
        
        // Retrieve the lead after running the assignment rules
        Lead updatedLead = [SELECT Id, Name FROM Lead WHERE Id = :testLeadId];
        
        // Assert that the lead has been updated
        System.assertEquals('Test Lead', updatedLead.Name, 'Lead name should be updated after running assignment rules');
    }
}