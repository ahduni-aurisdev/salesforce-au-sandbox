/**
* @description
********************************************************************************************************************
* Created By        : Preksha Chauhan
* Company           : GetonCRM Solutions
* Developer Name    : Preksha Chauhan
* Created Date      : 08/09/2024
* Class Name        : LeadTriggerHandler
* Description       : This class handles the logic for assigning leads, updating phone numbers, 
*                     initializing lead fields, and ensuring last name integrity during Lead trigger events.  
*                     It includes the following methods:  
*                  -  `handleLeadAssignments`: Distributes leads based on record type (Masters, PhD,  
*                    Executive Education, and Undergraduation) to the appropriate users or departments.  
*                  - `handlePhoneNumberUpdates`: Updates lead phone numbers by adding the appropriate  
*                     country code, based on the operation passed.  
*                   - `initializeLeadFields`: Initializes key fields for new Lead records to ensure data  
*                     consistency upon creation.  
*                   - `updateLeadLastNameIfBlank`: Updates the LastName field with the value of FirstName  
*                     if LastName is blank, ensuring data integrity during Lead creation or updates.  
*                   This class helps in organizing logic outside of the trigger for better code maintainability  
*                   and reusability.  
*********************************************************************************************************************/
public class LeadTriggerHandler {
    // Static boolean flag to prevent recursion
    public static Boolean isTriggerExecuted = false;
    
    /**
    * @description
    * @param newLeads - The list of Lead records that are being inserted
    ****************************************************************************************
    * Method Name       : handleLeadAssignments
    * Created By        : Preksha Chauhan
    * Created Date      : 13/10/2024
    * Description       : This method handles lead assignments based on the record type.
    *                     It categorizes leads into Masters, PhD, Executive Education, and 
    *                     Undergraduation and assigns them using specific logic for each type.
    * Parameters        : List<Lead> newLeads - The list of Lead records that are being inserted.
    * Return Type       : void
    ******************************************************************************************/
    
    public static void handleLeadAssignments(List<Lead> newLeads) {
         // Prevent recursion
         if (isTriggerExecuted) {
            return;
        }
        isTriggerExecuted = true;

        
        List<Lead> otherLeads = new List<Lead>();
        
        List<Lead> undergraduationLeads = new List<Lead>();

        Map<String, String> recordTypeResponse = LeadHelper.getRecordTypeWithName();

        for (Lead lead : newLeads) {
            String recordTypeName = recordTypeResponse.get(lead.RecordTypeId);
            
            // if (recordTypeName == 'Masters') {
            //     mastersLeads.add(lead);
            // } else if (recordTypeName == 'Phd') {
            //     phdLeads.add(lead);
            // } else if (recordTypeName == 'Executive Education') {
            //     executiveLeads.add(lead);
            // } 
            
             if (recordTypeName == 'Undergraduation') {
                undergraduationLeads.add(lead);
            }
            else{
                otherLeads.add(lead);
            }
        }
       
        // Assign leads for 'Masters' record type
        // assignMastersLeads - This Apex method assignMastersLeads is responsible for assigning Lead records with the "Masters"
        // record type to users in a controlled way — some go to a specific user ("Aaquib"), others are
        // assigned via a round-robin strategy, and the state of round-robin is tracked in a custom setting (LeadAssignmentTrackerMasters__c).
        if (!otherLeads.isEmpty()) {
            LeadHelper.leadAssignmentForMastersByCourse(otherLeads);
        }

        // Assign leads for 'PhD' and 'Executive Education' record types
        // assignLeadsByDepartment - It checks the lead’s Record Type name by using the getRecordTypeWithName() method.
        // If the record type is PhD, it assigns the lead to the Doctoral Admissions user.
        // If the record type is Executive Education, it assigns the lead to Rahul Mehta.

        // Assign leads for 'Undergraduation' record type
        // leadAssignmentForUnderGraduation - this method assigns Undergraduate Leads to users based on state/country and
        // rotates assignments using counters stored in custom metadata and custom objects.
        if (!undergraduationLeads.isEmpty()) {
            
            LeadAssignmentForUnderGraduation.leadAssignmentForUnderGraduation(undergraduationLeads);
        }
        isTriggerExecuted = false; // Reset the flag after successful execution
    }

    /*public static void handleLeadAssignmentsForUpdateRecord(List<Lead> newLeads){
        // Prevent recursion
        if (isTriggerExecuted) {
            return;
        }
        isTriggerExecuted = true;

        List<Lead> undergraduationLeads = new List<Lead>();

        Map<String, String> recordTypeResponse = LeadHelper.getRecordTypeWithName();

        for (Lead lead : newLeads) {
            String recordTypeName = recordTypeResponse.get(lead.RecordTypeId);
            if (recordTypeName == 'Undergraduation'  ) {
                undergraduationLeads.add(lead);
            }
        }
        if (!undergraduationLeads.isEmpty()) {
            
            LeadAssignmentForUnderGraduation.leadAssignmentForUnderGraduation(undergraduationLeads);
        }
        isTriggerExecuted = false;
    }*/
    /**
    * @description
    * @param newLeads The list of Lead records that are being inserted
    * @param operation The type of operation ('insert' or 'update')
    * Method Name       : handlePhoneNumberUpdates
    * Created By        : Preksha Chauhan
    * Created Date      : 13/10/2024
    * Description       : This method processes lead phone number updates. It ensures phone
    *                     numbers are updated with the appropriate country code during insert 
    *                     and update operations.
    * Parameters        : List<Lead> newLeads - The list of Lead records being processed.
    *                     String operation - The type of operation ('insert' or 'update').
    * Return Type       : void
    ******************************************************************************************/
    public static void handlePhoneNumberUpdates(List<Lead> newLeads, String operation) {
        LeadHelper.updatePhoneWithCountryCode(newLeads, operation);  
    }
    
    /**
    public static void handlePhoneNumberUpdates(List<Lead> newLeads, String operation, Map<Id, Lead> oldLeads) {
        LeadPhoneUpdater.updatePhoneWithCountryCode(oldLeads, newLeads, operation);
    }
    */

    /**
    * @description
    * @param newLeads The list of Lead records that are being inserted
    * Method Name       : initializeLeadFields
    * Created By        : Preksha Chauhan
    * Created Date      : 13/10/2024
    * Description       : This method ensures that required fields are initialized when leads
    *                     are inserted. Specifically, it checks if LastName is provided and 
    *                     assigns a default value ('.') if not.
    * Parameters        : List<Lead> newLeads - The list of Lead records that are being inserted.
    * Return Type       : void
    ******************************************************************************************/
    public static void initializeLeadFields(List<Lead> newLeads) {
        LeadHelper.initializeLeadFields(newLeads); // Call helper method
    }

    /**
    * @description
    * @param newLeads The list of Lead records that are being inserted
    * @param oldLeadsMap A map of Lead records before the update
      ****************************************************************************************
    * Method Name       : updateLeadLastNameIfBlank
    * Created By        : Preksha Chauhan
    * Created Date      : 13/10/2024
    * Description       : This method ensures that if a lead's LastName is cleared during an update
    *                     and was previously set, it will be updated to a default value ('.'). This
    *                     ensures that LastName is never left blank during updates.
    * Parameters        : List<Lead> newLeads - The list of Lead records that are being updated.
    *                     Map<Id, Lead> oldLeadsMap - A map of Lead records before the update.
    * Return Type       : void
    ******************************************************************************************/
    public static void updateLeadLastNameIfBlank(List<Lead> newLeads, Map<Id, Lead> oldLeadsMap) {
        LeadHelper.updateLeadLastNameIfBlank(newLeads, oldLeadsMap); // Call helper method
    }
}