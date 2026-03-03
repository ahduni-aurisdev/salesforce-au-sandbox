/******************************************************************************************
* Created By       : Preksha Chauhan
* Company          : GetonCRM Solutions
* Trigger Name     : LeadCombinedTrigger
* Created Date     : 08/20/2024
* Description      : Trigger for the Lead object to handle assignments and phone number 
*                    updates during lead creation and modification. 
*                    This trigger covers the following scenarios:
*                    - Before Insert: Assigns lead owners based on record type 
*                      configuration for Masters and PhD leads.
*                    - Before Update: Updates phone numbers to ensure they have the 
*                      appropriate country code format.
* Cover CodeCoverage: 100%
**********************************************************************************************/
//final changes after resolving SOQL 101 error and Masters depatment error related to lock record 
//error[UNABLE_TO_LOCK_ROW, unable to obtain exclusive access to this record or 1 records: a1oIm0000008yJJIAY: []] 

// trigger LeadCombinedTrigger on Lead (before insert, before update) {
//     // Handle lead assignments during insert
//     if (Trigger.isBefore && Trigger.isInsert) {
//         if (Trigger.isInsert) {
//             LeadTriggerHandler.handleLeadAssignments(Trigger.new);
//             LeadTriggerHandler.handlePhoneNumberUpdates(Trigger.new, 'insert');
//             LeadTriggerHandler.initializeLeadFields(Trigger.new);             
//         } else if (Trigger.isUpdate) {
//             LeadTriggerHandler.handlePhoneNumberUpdates(Trigger.new, 'update');
//             LeadTriggerHandler.updateLeadLastNameIfBlank(Trigger.new, Trigger.oldMap);      
//         }
//     }
// }

trigger LeadCombinedTrigger on Lead (before insert, before update) {
    if (Trigger.isBefore) {
        if (Trigger.isInsert) {
            LeadTriggerHandler.handleLeadAssignments(Trigger.new);
            LeadTriggerHandler.handlePhoneNumberUpdates(Trigger.new, 'insert');
            LeadTriggerHandler.initializeLeadFields(Trigger.new);             
        } else if (Trigger.isUpdate) {
            //LeadTriggerHandler.handleLeadAssignmentsForUpdateRecord(Trigger.new);
            LeadTriggerHandler.handlePhoneNumberUpdates(Trigger.new, 'update');
            LeadTriggerHandler.updateLeadLastNameIfBlank(Trigger.new, Trigger.oldMap);      
        }
    }
}