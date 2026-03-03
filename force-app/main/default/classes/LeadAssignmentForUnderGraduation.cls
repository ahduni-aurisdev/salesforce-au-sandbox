/**
* @description
* Created By       : Neha Badgujar
* Company          : GetonCRM Solutions
* Developer Name   : Neha Badgujar
* Created Date     : 04/08/2025
* Class Name       : LeadAssignmentForUnderGraduation
* Description      : This class handles dynamic lead assignment for Undergraduate leads 
 *                    based on predefined rules stored in Custom Metadata. 
 *                    It supports direct assignment to users based on State, State Code, 
 *                    Country, or Country Code, handles leads from outside India with a 
 *                    specific user assignment, and uses a round-robin mechanism for leads 
 *                    from Gujarat by distributing them among users defined in metadata. 
 *                    It also includes a fallback assignment to a default user when no 
 *                    specific match is found, ensuring robust and flexible lead ownership 
 *                    assignment even when address fields are incomplete or partially filled.
**********************************************************************************************/
public with sharing class LeadAssignmentForUnderGraduation {
    /**
    * @description
     * ****************************************************************************************
     * Method Name     : leadAssignmentForUnderGraduation
     * Created By      : Neha Badgujar
     * Created Date    : 04/08/2025
         /**
     * Description     : This method assigns Undergraduate leads to users based on dynamic 
     *                   rules defined in Custom Metadata. It performs direct assignment 
     *                   using State, State Code, Country, or Country Code, handles outside 
     *                   India leads with a dedicated user, and applies round-robin logic 
     *                   for Gujarat leads. It ensures fallback assignment to a default user 
     *                   when no match is found and updates the round-robin tracker to maintain 
     *                   even distribution among Gujarat users.
    *******************************************************************************************/
    public static void leadAssignmentForUnderGraduation(List<Lead> leads) {
        if (leads == null || leads.isEmpty()) {
            return;
        }
        // Step 1: Load metadata - state to list of user IDs
        Map<String, List<Id>> stateToUsers = new Map<String, List<Id>>();
        String foreignKey = null;
        String defaultKey = null;

        // Collect all emails from metadata first
        Set<String> allEmails = new Set<String>();

        List<LeadAssignmentRuleForNonGujarat__mdt> metaRecords = [
            SELECT State__c, State_Code__c, Is_Outside_India__c, Is_Default__c, Country__c, Users_Email__c
            FROM LeadAssignmentRuleForNonGujarat__mdt
        ];

        for (LeadAssignmentRuleForNonGujarat__mdt record : metaRecords) {
            if (String.isNotBlank(record.Users_Email__c)) {
                for (String emailStr : record.Users_Email__c.split(',')) {
                    if (String.isNotBlank(emailStr)) {
                        allEmails.add(emailStr.trim().toLowerCase());
                    }
                }
            }
        }

        // Query all users in one go
        Map<String, Id> emailToUserId = new Map<String, Id>();
        for (User u : [
            SELECT Id, Email
            FROM User
            WHERE Email IN :allEmails
        ]) {
            emailToUserId.put(u.Email.toLowerCase(), u.Id);
        }

        // Build state to user IDs map
        for (LeadAssignmentRuleForNonGujarat__mdt record : metaRecords) {
            if (String.isNotBlank(record.Users_Email__c)) {
                List<Id> userList = new List<Id>();

                for (String emailStr : record.Users_Email__c.split(',')) {
                    Id uid = emailToUserId.get(emailStr.trim().toLowerCase());
                    if (uid != null) {
                        userList.add(uid);
                    } else {
                        System.debug('⚠ No matching user found for email: ' + emailStr);
                    }
                }

                if (!userList.isEmpty()) {
                    if (String.isNotBlank(record.State__c)) {
                        stateToUsers.put(record.State__c.trim().toLowerCase(), userList);
                    } else if (String.isNotBlank(record.State_Code__c)) {
                        stateToUsers.put(record.State_Code__c.trim().toLowerCase(), userList);
                    } else if (record.Is_Outside_India__c) {
                        foreignKey = 'foreign';
                        stateToUsers.put(foreignKey, userList);
                    } else if (record.Is_Default__c) {
                        defaultKey = 'default';
                        stateToUsers.put(defaultKey, userList);
                    }
                }
            }
        }


        // Step 2: Load counters
        Map<String, Lead_Assignment_Tracker_for_Undergrad__c> counterMap = new Map<String, Lead_Assignment_Tracker_for_Undergrad__c>();
        Map<String, Lead_Assignment_Tracker_for_Undergrad__c> counterMapOfCountyCode = new Map<String, Lead_Assignment_Tracker_for_Undergrad__c>();

        for (Lead_Assignment_Tracker_for_Undergrad__c cs : [
            SELECT State__c,State_Code__c, Counter__c FROM Lead_Assignment_Tracker_for_Undergrad__c
        ]) {
            counterMap.put(cs.State__c.trim().toLowerCase(), cs);
            counterMapOfCountyCode.put(cs.State_Code__c.trim().toLowerCase(), cs);

        }

        // Step 3: Assignment and counter logic
        Map<String, Integer> newCounterValues = new Map<String, Integer>();

        for (Lead lead : leads) {
            String stateKey;
            if(lead.State != null ){
               stateKey = lead.State.toLowerCase() ;
            }else if(lead.StateCode != null){
                stateKey = lead.StateCode.toLowerCase();
            }
            //lead.State = stateKey ;)
           // String stateKey = lead.State ;
            String country = lead.Country;
            // Boolean isOutsideIndia =
            //     (country != StaticValuesUtil.COUNTRY_INDIA) ||
            //     (lead.CountryCode != null && lead.CountryCode != StaticValuesUtil.COUNTRY_CODE_INDIA);

            Boolean isOutsideIndia =
                (country != 'India' && country!=null) ||
                (lead.CountryCode != null && lead.CountryCode != 'IN');
            if (isOutsideIndia && String.isNotBlank(foreignKey)) {
                stateKey = foreignKey.toLowerCase();
            }

            List<Id> users = stateToUsers.get(stateKey);
            if (users == null && String.isNotBlank(defaultKey)) {
                stateKey = defaultKey;
                users = stateToUsers.get(defaultKey);
            }

            if (users != null && !users.isEmpty()) {
                Integer userCount = users.size();
                Integer currentIndex ;  
                if(counterMap.containsKey(stateKey)){
                    currentIndex=  Integer.valueOf(counterMap.get(stateKey).Counter__c);
                }else if(counterMapOfCountyCode.containsKey(stateKey)){
                    currentIndex=  Integer.valueOf(counterMapOfCountyCode.get(stateKey).Counter__c);
                }else{
                    currentIndex = 0;
                }


                if (currentIndex >= userCount) {
                    currentIndex = 0;
                }

                lead.OwnerId = users[currentIndex];

                Integer nextIndex = (currentIndex + 1 < userCount) ? currentIndex + 1 : 0;
                newCounterValues.put(stateKey, nextIndex);
            }
        }

        // Step 4: Save updated counters
        List<Lead_Assignment_Tracker_for_Undergrad__c> counterUpdates = new List<Lead_Assignment_Tracker_for_Undergrad__c>();
        for (String state : newCounterValues.keySet()) {

                Lead_Assignment_Tracker_for_Undergrad__c tracker;
                if(counterMap.containsKey(state)){
                    tracker = counterMap.get(state);
                }else if(counterMapOfCountyCode.containsKey(state)){
                    tracker = counterMapOfCountyCode.get(state);
                }else{
                    tracker = new Lead_Assignment_Tracker_for_Undergrad__c(State__c = state,Name = state);
                }


            tracker.Counter__c = newCounterValues.get(state);
            counterUpdates.add(tracker);
        }

        if (!counterUpdates.isEmpty()) {
            upsert counterUpdates;
        }

        
    }

    
    
    
    
}