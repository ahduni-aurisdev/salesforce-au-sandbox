/**
 * @description       : 
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 01-30-2025
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
public class LeadAssignmentCtrl {
    static Boolean recursiveUpdate = false;
     @InvocableMethod(label='Assign Lead' description='Assign Lead Using Lead ')
    /**
    * @description Runs Assignments Rules
    * @param leadId - Id of the Lead to be assigned
    */
    public static void runAssignmentRules(List<Id> leadId) {
 		//Id CurrentLeadId = leadId[0];
        if(recursiveUpdate) {
            return;
        }
        Database.DmlOptions dmlOptions = new Database.DmlOptions();
        dmlOptions.assignmentRuleHeader.UseDefaultRule = true;
         recursiveUpdate = true;
        List<Lead> record = [Select Id,Name From Lead WHERE Id = :leadId ];
        //record.setOptions(dmlOptions);
        //update record;
         Database.update(record, dmlOptions);
        recursiveUpdate = false;
        //system.debug('record@--'+record);
    }
}

/**
 * @description This class handles the assignment of leads using the lead assignment rules.
 * @without sharing to enforce sharing rules context.
 */
/*public without sharing class LeadAssignmentCtrl {
    
    
    @InvocableMethod(label='Assign Lead' description='Assign Lead Using Lead Assignment Rules')
    public static void runAssignmentRules(List<Id> leadId) {
        // Check if the user has read and update permissions on the Lead object
        if (leadId != null && !leadId.isEmpty() && 
            Schema.sObjectType.Lead.isAccessible() && Schema.sObjectType.Lead.isUpdateable()) {
            
            Id currentLeadId = leadId[0];
            
            // Check if the user has access to the required fields (Id, Name)
            if (Schema.sObjectType.Lead.fields.Id.isAccessible() && 
                Schema.sObjectType.Lead.fields.Name.isAccessible()) {
                
                // Get the lead record using SOQL with security enforced
                Lead record = [SELECT Id, Name FROM Lead 
                               WHERE Id = :currentLeadId];
                
                // Set up DML options for assignment rule
                Database.DmlOptions dmlOptions = new Database.DmlOptions();
                dmlOptions.assignmentRuleHeader.useDefaultRule = true;
                record.setOptions(dmlOptions);
                
                // Perform the update operation
                update record;
            }
        }
    }
}*/