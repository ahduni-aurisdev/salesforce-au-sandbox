/******************************************************************************************
* Created By       : Preksha Chauhan
* Company          : GetonCRM Solutions
* Class Name       : LeadAssignmentHelper
* Created Date     : 08/20/2024
* Description      : This class is responsible for assigning the lead owner based on the 
*                    preferred program and record type configuration using custom metadata. 
*                    It maintains a map of configurations and provides a method to assign 
*                    lead owners accordingly.
**********************************************************************************************/
public class LeadAssignmentHelper {

    // Method to assign Masters leads in a round-robin fashion
    public static void assignLeads(List<Lead> leads) {
        LeadAssignmentTrackers__c tracker = LeadAssignmentTrackers__c.getOrgDefaults();
        Integer index = tracker != null && tracker.Last_Assigned_Index__c != null ? Integer.valueOf(tracker.Last_Assigned_Index__c) : 0;
        
        // Map<String, Department_Record_Type_Mapping__mdt> departmentRecordType = Department_Record_Type_Mapping__mdt.getAll();
        // for(String nameEmailDomain : departmentRecordType.keySet()){
        //     System.debug('departmentRecordType Id----->'+departmentRecordType.get(nameEmailDomain).Record_Type_Id__c);
        // }

        // Department_Record_Type_Mapping__mdt departmentRecordTypeId = Department_Record_Type_Mapping__mdt.getInstance('Record_Type_Id__c');
        // System.debug('departmentRecordTypeId Id ----->'+departmentRecordTypeId);

        Set<Id> mastersRecordTypeIds = new Set<Id>();
        for (Department_Record_Type_Mapping__mdt mapping : [
            SELECT Record_Type_Id__c
            FROM Department_Record_Type_Mapping__mdt
            WHERE Department__c = 'Masters'
        ]) {
            mastersRecordTypeIds.add(mapping.Record_Type_Id__c);
        }
        
        if (mastersRecordTypeIds.isEmpty()) return;
        
        List<LeadAssignmentRule__mdt> rules = [
            SELECT User__c
            FROM LeadAssignmentRule__mdt
            ORDER BY Round_Robin_Index__c
        ];

        Integer numUsers = rules.size();
        if (numUsers == 0) return;

        for (Lead lead : leads) {
            if (mastersRecordTypeIds.contains(lead.RecordTypeId)) {
                lead.OwnerId = rules[index].User__c;
                lead.Last_Lead_Assigned_User__c = rules[index].User__c;
                lead.Last_Index__c = index;
                
                index = Math.mod(index + 1, numUsers);
            }
        }

        if (tracker == null) {
            tracker = new LeadAssignmentTrackers__c();
        }
        tracker.Last_Assigned_Index__c = index;
        upsert tracker;
    }

    // Updated method to assign PhD leads using custom metadata for the "Doctoral Admission User"
    public static void assignPhdLeads(List<Lead> leads) {
        // Query custom metadata to get the user ID for "Doctoral Admission User"
        LeadAssignmentPhDUsers__mdt phdUserMetadata = [
            SELECT User_Id__c 
            FROM LeadAssignmentPhDUsers__mdt 
            WHERE User_Name__c = 'Doctoral Admissions' 
            LIMIT 1
        ];

        // Check if the user was found in the custom metadata
        if (phdUserMetadata != null) {
            String doctoralAdmissionUserId = phdUserMetadata.User_Id__c;
            
            for (Lead lead : leads) {
                lead.OwnerId = doctoralAdmissionUserId;
            }
        } else {
            // Handle case where the user is not found in custom metadata
            System.debug('No user found for Doctoral Admission in custom metadata');
        }
    }

    // Helper method to check if a record type is "Masters"
    public static Boolean isMastersRecordType(Id recordTypeId) {
        String recordTypeName = [SELECT Name FROM RecordType WHERE Id = :recordTypeId].Name;
        return recordTypeName == 'Masters';
    }

    // Helper method to check if a record type is "PhD"
    public static Boolean isPhdRecordType(Id recordTypeId) {
        String recordTypeName = [SELECT Name FROM RecordType WHERE Id = :recordTypeId].Name;
        return recordTypeName == 'PhD';
    }

    public static Map<String,String> getRecordTypeWithName(){
        Map<String,String> recordTypeIdWithName = new Map<String,String>();
        List<Department_Record_Type_Mapping__mdt> recordTypeListMetadata = [SELECT Record_Type_Id__c , MasterLabel
                                                                            FROM Department_Record_Type_Mapping__mdt
                                                                            ]; 

        for(Department_Record_Type_Mapping__mdt singleRecord : recordTypeListMetadata){
            recordTypeIdWithName.put(singleRecord.Record_Type_Id__c,singleRecord.MasterLabel);
        }

        return recordTypeIdWithName;
    }
}



//below is round robbin logic in sandbox org
/*public class LeadAssignmentHelper {
    public static void assignLeads(List<Lead> leads) {
        // Fetch the last assigned index from custom setting
        LeadAssignmentTrackers__c tracker = LeadAssignmentTrackers__c.getOrgDefaults();
        
        Integer index = tracker != null && tracker.Last_Assigned_Index__c != null ? Integer.valueOf(tracker.Last_Assigned_Index__c) : 0;

        // Fetching record type IDs for "Masters"
        Set<Id> mastersRecordTypeIds = new Set<Id>();
        for (Department_Record_Type_Mapping__mdt mapping : [
            SELECT Record_Type_Id__c
            FROM Department_Record_Type_Mapping__mdt
            WHERE Department__c = 'Masters'
        ]) {
            mastersRecordTypeIds.add(mapping.Record_Type_Id__c);
        }
        
        // Exit if no record types for "Masters" are found
        if (mastersRecordTypeIds.isEmpty()) {
            return;
        }

        // Fetch lead assignment rules from custom metadata
        List<LeadAssignmentRule__mdt> rules = [
            SELECT User__c
            FROM LeadAssignmentRule__mdt
            ORDER BY Round_Robin_Index__c
        ];

        Integer numUsers = rules.size();
        if (numUsers == 0) return;

        // Assign leads in a round-robin fashion
        for (Lead lead : leads) {
            if (mastersRecordTypeIds.contains(lead.RecordTypeId)) {
                // Assign the lead to the user based on the round-robin index
                lead.OwnerId = rules[index].User__c;
                
                // Update Last_Lead_Assigned_User__c and Last_Index__c on the Lead record
                lead.Last_Lead_Assigned_User__c = rules[index].User__c;
                lead.Last_Index__c = index;
                
                // Move to the next user in the list
                index = Math.mod(index + 1, numUsers);
            }
        }

        // Update the index in the custom setting
        if (tracker == null) {
            tracker = new LeadAssignmentTrackers__c();
        }
        tracker.Last_Assigned_Index__c = index;
        upsert tracker;
    }

    // Helper method to check if a record type is "Masters"
    public static Boolean isMastersRecordType(Id recordTypeId) {
        String recordTypeName = [SELECT Name FROM RecordType WHERE Id = :recordTypeId].Name;
        return recordTypeName == 'Masters';
    }
}*/

// below code is assigning leads based on Preferred Program for each lead and assigns the OwnerId from custom metadata.
/*public without sharing class LeadAssignmentHelper {
    /******************************************************************************************
    * Method Name: handleBeforeInsert
    * Created By    : Preksha Chauhan
    * Created Date  : 08/20/2024
    * Description   : This static method handles lead assignments before insertion. It fetches
    *                 the custom metadata configuration, maps the preferred programs to user 
    *                 IDs, and updates the lead owner based on the configuration.
    *******************************************************************************************/
/*    public static void handleBeforeInsert(List<Lead> newLeads) {
        // Fetch the custom metadata records
        List<LeadAssignmentConfig__mdt> configList = [SELECT Lead_Record_Type__c, Preferred_Program__c, User_Id__c FROM LeadAssignmentConfig__mdt WITH SECURITY_ENFORCED];

        // Create a map to hold custom metadata configurations for quick lookup
        Map<String, Id> configMap = new Map<String, Id>();
        for (LeadAssignmentConfig__mdt config : configList) {
            String key = config.Lead_Record_Type__c + '|' + config.Preferred_Program__c;
            configMap.put(key, config.User_Id__c);
        }

        // Iterate through each lead being inserted
        for (Lead leadRecord : newLeads) {
            // Ensure RecordType is valid and Preferred_Program__c is not null
            if (leadRecord.RecordTypeId != null && leadRecord.Preferred_Programme__c != null) {
                // Query RecordType Name
                RecordType rt = [SELECT Name FROM RecordType WHERE Id = :leadRecord.RecordTypeId WITH SECURITY_ENFORCED LIMIT 1 ];
                String recordTypeName = rt.Name;

                // Create the key for lookup
                String key = recordTypeName + '|' + leadRecord.Preferred_Programme__c;

                // Check if the key exists in the custom metadata map
                if (configMap.containsKey(key)) {
                    leadRecord.OwnerId = configMap.get(key);
                }
            }
        }
    }
}*/