/**
 * @description       : 
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 04-13-2026
 * @last modified by  : Mihir Ramoliya
 * Modifications Log 
 * Ver   Date         Author           Modification
 * 1.0   04-13-2026   Mihir Ramoliya   Added logic to check inactive account owner and assign System Running User. Commented out full name assignment logic.
**/
@RestResource(urlMapping='/updateOpportunityStage')
global with sharing class OpportunityStageUpdater {
   // @HttpPatch
    /**
    * @description  update opportunity stages along with the other details
    * @param opportunityList List of opportunities to be updated
    * @param accountId ID of account
    * @return map of responses
    */
    global static Map<String, Object> updateOpportunityStage(List<Object> opportunityList, Id accountId) {
        Map<String, Object> response = new Map<String, Object>();
        
        try {
            System.debug('--- ENTERED updateOpportunityStage ---');
            System.debug('Incoming AccountId: ' + accountId);
            System.debug('Incoming opportunityList: ' + JSON.serialize(opportunityList));
    
            // Get the current datetime
            Datetime now = System.now();
            String formattedDate = now.format('yyyy-MM-dd:HH:mm:ss');
            System.debug('Formatted Timestamp: ' + formattedDate);
    
            // Update Account timestamp
            Account accountToUpdate = new Account(Id = accountId);
            accountToUpdate.Auris_Last_Modified_Timestamp__c = formattedDate;
            update accountToUpdate;
            System.debug('Updated Account timestamp for AccountId: ' + accountId);
    
            Map<Id, String> opportunityToBeUpdated = new Map<Id, String>();
            Map<String, Object> messageResponse = new Map<String, Object>();
    
            Account accObj = [
                // Mihir Ramoliya - 04-13-2026: Added Owner.IsActive to check if account owner is active or not
                SELECT Id, OwnerId, Owner.IsActive, FirstName, LastName, Programme_Interested_in__c 
                FROM Account 
                WHERE Id =: accountId 
                LIMIT 1
            ];
            System.debug('Fetched Account: ' + accObj);
    
            Map<Id, Map<String, Object>> opportunityToUpdateFields = new Map<Id, Map<String, Object>>();
            Id opportunityId;
    
            for (Object obj : opportunityList) {
                Map<String, Object> opportunityMap = (Map<String, Object>) obj;
                opportunityId = (Id) opportunityMap.get('opportunityId');
                String opportunityStatus = (String) opportunityMap.get('opportunityStatus');
                System.debug('Parsed Opportunity from payload → Id: ' + opportunityId + ', Status: ' + opportunityStatus);
    
                opportunityToBeUpdated.put(opportunityId, opportunityStatus);
                if (opportunityId != null) {
                    opportunityToUpdateFields.put(opportunityId, opportunityMap);
                }
            }
    
            // Query Opportunities
            List<Opportunity> opportunitiesToUpdateList = [
                SELECT Id, StageName, Auris_Last_Modified_Timestamp__c,
                       Primary_Preferred_Program__c, Secondary_Preferred_Programme__c,
                       Ternary_Preferred_Programme__c, OwnerId, Name, RecordType.DeveloperName,
                       Full_Name__c, Primary_Preferred_Major__c, Secondary_Preferred_Major__c,
                       Ternary_Preferred_Major__c 
                FROM Opportunity 
                WHERE Id IN :opportunityToUpdateFields.keySet()
            ];
            System.debug('Queried Opportunities: ' + opportunitiesToUpdateList);
    
            List<String> messages = new List<String>();
            List<Opportunity> opportunityListUpdatated = new List<Opportunity>();
    
            if (!opportunitiesToUpdateList.isEmpty()) {
                for (Opportunity opp : opportunitiesToUpdateList) {
                    Map<String, Object> opportunityMap = opportunityToUpdateFields.get(opp.Id);
                    System.debug('Updating Opportunity: ' + opp.Id + ' | Current Stage: ' + opp.StageName);
    
                    String oldStageName = opp.StageName;
    
                    if (opportunityMap.containsKey('opportunityStatus') && opportunityMap.get('opportunityStatus') != null) {
                        opp.StageName = (String) opportunityMap.get('opportunityStatus');
                        System.debug('→ New StageName: ' + opp.StageName);
                    }
    
                    if (opportunityMap.containsKey('primaryPreferredProgram') && opportunityMap.get('primaryPreferredProgram') != null) {
                        opp.Primary_Preferred_Program__c = (String) opportunityMap.get('primaryPreferredProgram');
                        accObj.Programme_Interested_in__c = (String) opportunityMap.get('primaryPreferredProgram');
                        System.debug('→ Updated Primary Program: ' + opp.Primary_Preferred_Program__c);
                    }
    
                    if (opportunityMap.containsKey('secondaryPreferredProgramme') && opportunityMap.get('secondaryPreferredProgramme') != null) {
                        opp.Secondary_Preferred_Programme__c = (String) opportunityMap.get('secondaryPreferredProgramme');
                        System.debug('→ Updated Secondary Program: ' + opp.Secondary_Preferred_Programme__c);
                    }
    
                    if (opportunityMap.containsKey('ternaryPreferredProgramme') && opportunityMap.get('ternaryPreferredProgramme') != null) {
                        opp.Ternary_Preferred_Programme__c = (String) opportunityMap.get('ternaryPreferredProgramme');
                        System.debug('→ Updated Ternary Program: ' + opp.Ternary_Preferred_Programme__c);
                    }
    
                    if (opportunityMap.containsKey('primaryPreferredMajor') && opportunityMap.get('primaryPreferredMajor') != null) {
                        opp.Primary_Preferred_Major__c = String.valueOf(opportunityMap.get('primaryPreferredMajor'));
                        System.debug('→ Updated Primary Major: ' + opp.Primary_Preferred_Major__c);
                    }
    
                    if (opportunityMap.containsKey('secondaryPreferredMajor') && opportunityMap.get('secondaryPreferredMajor') != null) {
                        opp.Secondary_Preferred_Major__c = String.valueOf(opportunityMap.get('secondaryPreferredMajor'));
                        System.debug('→ Updated Secondary Major: ' + opp.Secondary_Preferred_Major__c);
                    }
    
                    if (opportunityMap.containsKey('ternaryPreferredMajor') && opportunityMap.get('ternaryPreferredMajor') != null) {
                        opp.Ternary_Preferred_Major__c = String.valueOf(opportunityMap.get('ternaryPreferredMajor'));
                        System.debug('→ Updated Ternary Major: ' + opp.Ternary_Preferred_Major__c);
                    }
    
                    opp.Auris_Last_Modified_Timestamp__c = formattedDate;
    
                    if (opp.RecordType.DeveloperName == 'Undergraduation') {
                        if (accObj != null) {
                            // Mihir Ramoliya - 04-13-2026: Check if account owner is active, if not update to System Running user
                            if (accObj.OwnerId != null && accObj.Owner != null && !accObj.Owner.IsActive) {
                                accObj.OwnerId = UserInfo.getUserId();
                                opp.OwnerId = accObj.OwnerId;
                                System.debug('→ Updated OwnerId to Running User because Account Owner was inactive: ' + opp.OwnerId);
                            } else {
                                // Update opportunity owner with account owner
                                opp.OwnerId = accObj.OwnerId;
                                System.debug('→ Updated OwnerId to Account Owner: ' + opp.OwnerId);
                            }
                        }
                        
                        // Mihir Ramoliya - 04-13-2026: Commented below code as requested
                        /*
                        String fullName = accObj.FirstName != null && accObj.LastName != null ? accObj.FirstName + ' ' + accObj.LastName : null;
                        if (String.isNotBlank(fullName)) {
                            opp.Name = fullName;
                            opp.Full_Name__c = fullName;
                            System.debug('→ Updated Opportunity Name & Full_Name__c: ' + fullName);
                        }
                        */
                    }
    
                    String message = 'Application Stage successfully updated from ' + oldStageName + ' to ' + opp.StageName + ' for Application ID ' + opp.Id;
                    messages.add(message);
                    System.debug(message);
    
                    opportunityListUpdatated.add(opp);
                }
                update accObj;
            }
    
            if (!opportunityListUpdatated.isEmpty()) {
                update opportunityListUpdatated;
                System.debug('Opportunities updated successfully: ' + opportunityListUpdatated);
            }
    
            messageResponse.put('messageDetails', messages);
            return messageResponse;
    
        } catch (QueryException qe) {
            System.debug('❌ QueryException: ' + qe.getMessage());
            response.put('error', 'Opportunity not found.');
            return response;
        } catch (Exception e) {
            System.debug('❌ Exception: ' + e.getMessage() + ' | StackTrace: ' + e.getStackTraceString());
            response.put('error', 'An error occurred: ' + e.getMessage());
            return response;
        }
    }
    

    /**
    * @description  custom exception method
    */
    public class CustomException extends Exception {}

    /**
    * @description  update opportunity stages along with the other details
    * @param testScores List of tesytscores to be updated
    * @param accountId ID of account
    * @param registrationNumber Registration number of Auris
    * @return map of responses
    */
    public static Map<String,Object> insertStandardisedTestScores(List<Object> testScores, Id accountId,String registrationNumber) {
        try {
            //System.debug('Called insertStandardisedTestScores method ====================');
            Datetime now = System.now();

            // Format the datetime to the desired format
            String formattedDate = now.format('yyyy-MM-dd:HH:mm:ss');

            // Update Lead's Auris_Last_Updated_Timestamp__c field with the formatted datetime
            Account accountToUpdate = new Account(Id = accountId);
            accountToUpdate.Auris_Last_Modified_Timestamp__c = formattedDate; // Store the formatted datetime as a String
                        
            // Perform the update operation
            update accountToUpdate;
            //Check create access for Standardised_Test_Score_s__c
            if (!Schema.sObjectType.Standardised_Test_Score_s__c.isCreateable()) {
                throw new CustomException('User does not have create access to Standardised_Test_Score_s__c');
            }
            Map<String, Object> messageResponse = new Map<String, Object>();
            List<Standardised_Test_Score_s__c> testScoreRecords = new List<Standardised_Test_Score_s__c>();
            Set<String> testNames = new Set<String>();
            List<String> messages = new List<String>();
            // Collect all test names first
            for (Object testScoreObj : testScores) {
                Map<String, Object> testScoreMap = (Map<String, Object>) testScoreObj;
                if (testScoreMap.containsKey('testName') && testScoreMap.get('testName') != null) {
                    testNames.add((String) testScoreMap.get('testName'));
                }
            }
    
            // Query the Standardised_Test__c records by the collected test names
            Map<String, Standardised_Test__c> testNameToRecordMap = new Map<String, Standardised_Test__c>();
            if (!testNames.isEmpty()) {
                for (Standardised_Test__c testRec : [SELECT Id, Name FROM Standardised_Test__c WHERE Name IN :testNames ]) {
                    testNameToRecordMap.put(testRec.Name, testRec);
                }
            }
    
            // Map to store existing Standardised_Test_Score_s__c records by Test Name and Lead Id
            Map<String, Standardised_Test_Score_s__c> existingTestScoreMap = new Map<String, Standardised_Test_Score_s__c>();
            if (!testNames.isEmpty()) {
                for (Standardised_Test_Score_s__c existingTestScore : [SELECT Id, Test__r.Name 
                                                                      FROM Standardised_Test_Score_s__c 
                                                                      WHERE Account__c = :accountId 
                                                                      AND Test__r.Name IN :testNames]) {
                    existingTestScoreMap.put(existingTestScore.Test__r.Name, existingTestScore);
                }
            }
            //System.debug('Existing test score map: ' + existingTestScoreMap);
            Map<Id,Object> matchedStandarardisedTests = new Map<Id,Object>();
            
            List<Standardised_Test_Score_s__c> testScoreRecordsTOBeUpdated = new List<Standardised_Test_Score_s__c>();
            // Create Standardised_Test_Score_s__c records with the lookup to Standardised_Test__c
            for (Object testScoreObj : testScores) {
                Map<String, Object> testScoreMap = (Map<String, Object>) testScoreObj;
    
                // Check if test name exists in Standardised_Test__c and Standardised_Test_Score_s__c (to avoid duplicates)
                if (testScoreMap.containsKey('testName') && testScoreMap.get('testName') != null) {
                    String testName = (String) testScoreMap.get('testName');
    
                    // Check if Standardised_Test__c record exists
                    if (!testNameToRecordMap.containsKey(testName)) {
                        //System.debug('Test Name not found in Standardised_Test__c: ' + testName);
                        continue; // Skip this record since the test name wasn't found

                    }
    
                    // Check if Standardised_Test_Score_s__c record already exists for this Lead
                    if (existingTestScoreMap.containsKey(testName)) {
                        //System.debug('Duplicate Test Score record found for test name: ' + testName);
                        if(existingTestScoreMap.get(testName).Id != null)
                        {
                            matchedStandarardisedTests.put(existingTestScoreMap.get(testName).Id,testScoreObj);
                        }                        
                        continue; // Skip this record since it's a duplicate
                    }
                }
                // Create new Standardised_Test_Score_s__c record
                Standardised_Test_Score_s__c scoreRec = new Standardised_Test_Score_s__c();
                scoreRec.Account__c = accountId;
    
                if (testScoreMap.containsKey('testName') && testScoreMap.get('testName') != null) {
                    String testName = (String) testScoreMap.get('testName');
                    scoreRec.Test__c = testNameToRecordMap.get(testName).Id;
                }
    
                if (testScoreMap.containsKey('testDate') && testScoreMap.get('testDate') != null) {
                    scoreRec.Test_Date__c = (String) testScoreMap.get('testDate');
                }
    
                if (testScoreMap.containsKey('percentile') && testScoreMap.get('percentile') != null) {
                    scoreRec.Test_Percentile__c = (String) testScoreMap.get('percentile');
                    //scoreRec.Percentile__c = Decimal.valueOf(String.valueOf(testScoreMap.get('percentile')))
                }
    
                if (testScoreMap.containsKey('testScore') && testScoreMap.get('testScore') != null) {
                    scoreRec.Test_Score__c = (String) testScoreMap.get('testScore');  
                   // scoreRec.Total_score__c = Decimal.valueOf((String) testScoreMap.get('testScore'));  
                }
                //messages.add('TestScores are inserted for testcore Id : '+scoreRec.Id+'.');
                //system.debug('277 scoreRec ---'+scoreRec);
                testScoreRecords.add(scoreRec);
            }

            testScoreRecordsTOBeUpdated = [SELECT Id, Test_Score__c,Total_score__c,Test_Date__c,Percentile__c,Test__r.Name,Account__c
                                         FROM Standardised_Test_Score_s__c 
                                         WHERE Account__c = :accountId 
                                         AND ID IN: matchedStandarardisedTests.keySet()];

            //system.debug('matchedStandarardisedTests'+matchedStandarardisedTests);  
            List<Standardised_Test_Score_s__c> testScoreRecordsList = new List<Standardised_Test_Score_s__c>();          
            for(Standardised_Test_Score_s__c existingTestScore : testScoreRecordsTOBeUpdated)
            {
                //String percentile = matchedStandarardisedTests.get(existingTestScore.Id).percentile;
                if( matchedStandarardisedTests.get(existingTestScore.Id)!= null){
                    Object testScoreObj = matchedStandarardisedTests.get(existingTestScore.Id);
                    //system.debug('testScoreObj'+testScoreObj);
                    Map<String, Object> testScoreMap = (Map<String, Object>) testScoreObj;
                    if(testScoreMap.containsKey('testScore') && testScoreMap.get('testScore') != null){

                        existingTestScore.Test_Score__c = (String)testScoreMap.get('testScore');
                    }
                    if(testScoreMap.containsKey('testDate') && testScoreMap.get('testDate') != null){

                        existingTestScore.Test_Date__c = (String)testScoreMap.get('testDate');
                    }
                    if(testScoreMap.containsKey('percentile') && testScoreMap.get('percentile') != null){
                        existingTestScore.Test_Percentile__c = (String) testScoreMap.get('percentile');
                    }
                    //messages.add('TestScores are updated for testcore Id : '+existingTestScore.Id+'.');
                    testScoreRecordsList.add(existingTestScore);  
                }
            }
            if(testScoreRecordsList.size() > 0){
                update testScoreRecordsList;
                Set<Id> updatedTestScoreRecords = new Set<Id>();
                List<Standardised_Test_Score_s__c> updatedTestScoreRecordsList = [SELECT Id FROM Standardised_Test_Score_s__c WHERE Id IN :testScoreRecordsList];
                for(Standardised_Test_Score_s__c stdScore : updatedTestScoreRecordsList){
                    updatedTestScoreRecords.add(stdScore.Id);
                }
                messages.add('TestScore record are updated for student testcore Ids : '+' '+updatedTestScoreRecords);

                //System.debug('Updated ' + testScoreRecordsList.size() + ' Standardised Test Score records.');
            }
    
            if (!testScoreRecords.isEmpty()) {
                insert testScoreRecords;
                Set<Id> insertedTestScoreRecords = new Set<Id>();
                List<Standardised_Test_Score_s__c> insertedTestScoreRecordsList = [SELECT Id FROM Standardised_Test_Score_s__c WHERE Id IN :testScoreRecords];
                for(Standardised_Test_Score_s__c stdScore : insertedTestScoreRecordsList){
                    insertedTestScoreRecords.add(stdScore.Id);
                }
                messages.add('TestScore record are created for student testcore Ids : '+' '+insertedTestScoreRecords);

                //System.debug('Inserted ' + testScoreRecords.size() + ' Standardised Test Scores records.');
            } 
            // else {
            //     System.debug('No valid Standardised Test Score records to insert.');
            // }
            messageResponse.put('messageDetails', messages);
            return messageResponse;
        } catch (Exception e) {
            //System.debug('Error insertStandardisedTestScores method: ' + e.getMessage());
            saveWebTo_YourProfileData.logFailedLead(JSON.serialize(testScores), e,registrationNumber); // Log the failed attempt
            throw new CustomException('Error insertStandardisedTestScores method: ' + e.getMessage());
        }
    } 

    /**
    * @description  update parent information
    * @param parents List of parent records to be updated
    * @param accountId ID of account
    * @param registrationNumber Registration number of Auris
    * @return map of responses
    */
    public static Map<String,Object> insertParentInformation(List<Object> parents, Id accountId,String registrationNumber) {

        // Get the current datetime
        Datetime now = System.now();
        // Format the datetime to the desired format
        String formattedDate = now.format('yyyy-MM-dd:HH:mm:ss');
        // Update Lead's Auris_Last_Updated_Timestamp__c field with the formatted datetime
        Account accountToUpdate = new Account(Id = accountId);
        accountToUpdate.Auris_Last_Modified_Timestamp__c = formattedDate; // Store the formatted datetime as a String
        
        // Perform the update operation
        update accountToUpdate;

        List<Parent_Information__c> parentListToUpdate = new List<Parent_Information__c>();

        // Query existing Parent_Information__c records related to the lead
        Map<String, Parent_Information__c> existingParentMap = new Map<String, Parent_Information__c>();
        for (Parent_Information__c existingParent : [
            SELECT Id, Name, Relationship__c 
            FROM Parent_Information__c 
            WHERE Account__c = :accountId
        ]) {
            String uniqueKey = existingParent.Name + '-' + existingParent.Relationship__c;
            existingParentMap.put(uniqueKey, existingParent);
        }
        List<String> messages = new List<String>();
        Map<String, Object> messageResponse = new Map<String, Object>();
        List<Parent_Information__c> parentList = new List<Parent_Information__c>();

        for (Object parent : (List<Object>) parents) {
            Map<String, Object> parentMap = (Map<String, Object>) parent;
            Parent_Information__c parentRec = new Parent_Information__c();
            parentRec.Account__c = accountId;

            if (parentMap.containsKey('parentFullName') && parentMap.get('parentFullName') != null) {
                parentRec.Name = (String) parentMap.get('parentFullName');
            }
            if (parentMap.containsKey('relationship') && parentMap.get('relationship') != null) {
                parentRec.Relationship__c = (String) parentMap.get('relationship');
            }
            if (parentMap.containsKey('parentGuardianPhone') && parentMap.get('parentGuardianPhone') != null) {
                parentRec.Mobile__c = (String) parentMap.get('parentGuardianPhone');
            }
            if (parentMap.containsKey('parentGuardianEmail') && parentMap.get('parentGuardianEmail') != null) {
                parentRec.Email__c = (String) parentMap.get('parentGuardianEmail');
            }
            if (parentMap.containsKey('parentGuardianHighestEducationalQualification') && parentMap.get('parentGuardianHighestEducationalQualification') != null) {
                parentRec.Highest_educational_qualification__c = (String) parentMap.get('parentGuardianHighestEducationalQualification');
            }
            if (parentMap.containsKey('parentGuardianOccupation') && parentMap.get('parentGuardianOccupation') != null) {
                parentRec.Occupation__c = (String) parentMap.get('parentGuardianOccupation');
            }
            if (parentMap.containsKey('parentGuardianOtherOccupation') && parentMap.get('parentGuardianOtherOccupation') != null) {
                parentRec.Other_Occupation__c = (String) parentMap.get('parentGuardianOtherOccupation');
            }
            if (parentMap.containsKey('parentGuardianDesignation') && parentMap.get('parentGuardianDesignation') != null) {
                parentRec.Designation__c = (String) parentMap.get('parentGuardianDesignation');
            }
            if (parentMap.containsKey('parentGuardianOrganisationName') && parentMap.get('parentGuardianOrganisationName') != null) {
                parentRec.Organisation_Name__c = (String) parentMap.get('parentGuardianOrganisationName');
            }
            if (parentMap.containsKey('annualFamilyIncome') && parentMap.get('annualFamilyIncome') != null) {
                parentRec.Annual_family_income__c = (String) parentMap.get('annualFamilyIncome');
            }
            
            // Create a unique key for the current parent record')
            // Create a unique key using only Name and Relationship__c
            String uniqueKey = parentRec.Name + '-' + parentRec.Relationship__c;
            //System.debug('uniqueKey ------------------- ' + uniqueKey);

            // Check if a record with the same key already exists
            if (!existingParentMap.containsKey(uniqueKey)) {
                parentList.add(parentRec);
            }
            else{
                Parent_Information__c parentObj = [SELECT Id FROM Parent_Information__c WHERE Account__c = :accountId AND Name = :parentRec.Name LIMIT 1];
                parentRec.Id = parentObj.Id;
                parentListToUpdate.add(parentRec);
            }
        }
        
        if (!parentList.isEmpty()) {
            insert parentList;
            Set<Id> insertedParentsIdSet  = new Set<Id>();
            List<Parent_Information__c> insertedParentsList = [SELECT Id FROM Parent_Information__c WHERE Id IN :parentList];
            for(Parent_Information__c parentRec : insertedParentsList){
               // messages.add('Parent record created for given student ParentIds:' +parentRec.Id);
                insertedParentsIdSet.add(parentRec.Id);
            }
            if(!insertedParentsIdSet.isEmpty()){
                messages.add('Parent record created for given student ParentIds:' +' '+insertedParentsIdSet);

            }
            //System.debug('Inserted ' + parentList.size() + ' Parent Information records.');
        } 
        // else {
        //     System.debug('No new Parent Information records to insert.');
        // }

        if(!parentListToUpdate.isEmpty()){
            update parentListToUpdate;
            Set<Id> updatedParentsIdSet = new Set<Id>();
            List<Parent_Information__c> updatedParentsList = [SELECT Id FROM Parent_Information__c WHERE Id IN :parentListToUpdate];
            for(Parent_Information__c parentRec : updatedParentsList){
                updatedParentsIdSet.add(parentRec.Id);
            }
            if(!parentListToUpdate.isEmpty()){
                messages.add('Parent record updated for given student ParentIds:'+' ' +updatedParentsIdSet);
            }
            //System.debug('Updated ' + parentListToUpdate.size() + ' Parent Information records.');
        } 
        messageResponse.put('messageDetails', messages);
        return messageResponse;   
    }

    /**
    * @description  assign owners to UG account and Opportunities
    * @param state state name
    * @param accountId ID of account
    */
    public static void assignOpportunityOwner(String state,String accountId){
        Account accObj = [SELECT Id, OwnerId, BillingState FROM Account WHERE Id = :accountId];

        List<Opportunity> opportunityList  = [SELECT Id,OwnerId,Last_Opportunity_Assigned_User__c,Last_Index__c FROM
                                            Opportunity WHERE AccountId = :accountId];
        List<Opportunity> opportunityListToUpdate = new List<Opportunity>();

        List<OpportunityAssignmentRuleUnderGraduation__mdt> ownerIdMapping = [SELECT State__c,UserId__c
            FROM OpportunityAssignmentRuleUnderGraduation__mdt WHERE State__c=:state LIMIT 1
        ];

        if(state!=null && state == 'Gujarat'){
            if(opportunityList.size()>0){
                for(Opportunity opp:opportunityList){
                    List<OpportunityAssignmentRuleUGRoundRobin__mdt> rules = [SELECT UserId__c
                                                                FROM OpportunityAssignmentRuleUGRoundRobin__mdt
                                                                ORDER BY Round_Robin_Index__c
                    ];

                    Integer numUsers = rules.size();
                    //if (numUsers == 0) return;
                    if(numUsers!= 0){
                        OpportunityAssignmentTrackerUndergrad__c tracker = OpportunityAssignmentTrackerUndergrad__c.getOrgDefaults();
                        Integer index = tracker != null && tracker.Last_Assigned_Index__c != null ? Integer.valueOf(tracker.Last_Assigned_Index__c) : 0;
                        accObj.OwnerId = rules[index].UserId__c;
                        opp.OwnerId = rules[index].UserId__c;
                        opp.Last_Opportunity_Assigned_User__c = rules[index].UserId__c;
                        opp.Last_Index__c = index;

                        index = Math.mod(index + 1, numUsers);
                        if (tracker == null) {
                        tracker = new OpportunityAssignmentTrackerUndergrad__c();
                        }
                        tracker.Last_Assigned_Index__c = index;
                        upsert tracker;
                    }
                    opportunityListToUpdate.add(opp);
                }  
            }
        }else if(ownerIdMapping.size()>0){
            if(state ==ownerIdMapping[0].State__c){
                accObj.OwnerId = ownerIdMapping[0].UserId__c;
                for(Opportunity opp:opportunityList){
                    opp.OwnerId = accObj.OwnerId;
                    opportunityListToUpdate.add(opp);
                }
    
            }
        }
        else{
            User userObj = [SELECT Id FROM User WHERE Name= 'Swarnmani Singh' LIMIT 1];
            if(userObj!= null){
                accObj.OwnerId = userObj.Id;
                for(Opportunity opp:opportunityList){
                    opp.OwnerId = accObj.OwnerId;
                    opportunityListToUpdate.add(opp);
                }
            }   
        }
        // System.debug('OwnerID assigned is '+accObj.OwnerId);
        update accObj;
        if(!opportunityListToUpdate.isEmpty()){
            update opportunityListToUpdate;
        }
    } 
}