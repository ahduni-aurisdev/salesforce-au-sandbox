public with sharing class CallLogController {

    @AuraEnabled
    public static void updateLeadAndCreateTask(Id leadId, String callStatus, String comments) {
        try {
            // Update Lead
            Lead leadToUpdate = new Lead(
                Id = leadId,
                Call_Log_Comment__c = comments,
                Call_Log__c = callStatus
            );
            update leadToUpdate;
            
            // Create Task
            Task callLogTask = new Task(
                Subject = 'Call Log - ' + callStatus,
                Description = 'Call Status: ' + callStatus + 
                             (String.isNotBlank(comments) ? '\nComments: ' + comments : ''),
                Status = 'Completed',
                Priority = 'Normal',
                WhoId = leadId,
                ActivityDate = Date.today()
            );
            insert callLogTask;
            
        } catch (Exception e) {
            throw new AuraHandledException('Error updating lead and creating task: ' + e.getMessage());
        }
    }
}