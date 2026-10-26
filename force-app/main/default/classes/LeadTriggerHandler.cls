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

    /**
     * Auto-fills LastName and Company from the Account__c lookup for CDC leads.
     * Called on before insert and before update so CDC users never need to
     * type a person name — the company (Account) name is used instead.
     */
    public static void fillCdcLeadName(List<Lead> newLeads) {
        Id cdcRtId = Schema.SObjectType.Lead
            .getRecordTypeInfosByDeveloperName()
            .get('CDC')
            ?.getRecordTypeId();
        if (cdcRtId == null) return;

        Set<Id> accountIds = new Set<Id>();
        for (Lead lead : newLeads) {
            if (lead.RecordTypeId == cdcRtId && lead.Account__c != null) {
                accountIds.add(lead.Account__c);
            }
        }

        Map<Id, String> accountNameMap = new Map<Id, String>();
        if (!accountIds.isEmpty()) {
            for (Account acc : [SELECT Id, Name FROM Account WHERE Id IN :accountIds]) {
                accountNameMap.put(acc.Id, acc.Name);
            }
        }

        for (Lead lead : newLeads) {
            if (lead.RecordTypeId != cdcRtId) continue;
            String companyName = null;
            if (lead.Account__c != null && accountNameMap.containsKey(lead.Account__c)) {
                companyName = accountNameMap.get(lead.Account__c);
            } else if (String.isNotBlank(lead.Company)) {
                companyName = lead.Company;
            }
            if (String.isNotBlank(companyName)) {
                lead.LastName  = companyName;
                lead.FirstName = null;
                lead.Company   = companyName;
            }
        }
    }

    /**
     * True only for the transition that fills in a previously-blank LeadSource. Used just
     * for stamping Most_Recent_Lead_Source__c on a brand-new touch below — LeadSource
     * itself is first-touch and never overwritten once set, so a lead can legitimately be
     * created with it blank (e.g. manual entry before the source is known), and the "first
     * real touch" is whichever DML is the first to give it a non-blank value, whether
     * that's the insert itself or a later update. Campaign attachment (syncCampaignMembership
     * below) uses the broader isNewTouch/touchSource instead, since it must also react to
     * later re-touches that LeadSource itself can no longer reflect.
     */
    /**
     * This trigger runs on every Lead insert/update regardless of which class or query
     * loaded the record - a caller that queried a Lead without a given field (e.g. an
     * existing duplicate-lookup SOQL somewhere in the org that predates that field, or
     * simply forgot it) makes a direct read throw SObjectException: field not queried.
     * Treating an unqueried field as blank is a far better failure mode than crashing
     * the DML that triggered this code at all - seen in practice more than once already.
     */
    public static String safeGet(Lead ld, Schema.SObjectField field) {
        return ld.isSet(field) ? (String) ld.get(field) : null;
    }

    private static Boolean isFirstRealTouch(Lead ld, Map<Id, Lead> oldMap) {
        if (oldMap == null) {
            return String.isNotBlank(safeGet(ld, Lead.LeadSource));
        }
        return String.isBlank(safeGet(oldMap.get(ld.Id), Lead.LeadSource)) && String.isNotBlank(safeGet(ld, Lead.LeadSource));
    }

    /** Before insert/update — stamps the field directly, no extra DML. */
    public static void stampMostRecentLeadSource(List<Lead> newLeads, Map<Id, Lead> oldMap) {
        for (Lead ld : newLeads) {
            if (isFirstRealTouch(ld, oldMap)) {
                ld.Most_Recent_Lead_Source__c = safeGet(ld, Lead.LeadSource);
            }
        }
    }

    /**
     * "This touch's source" — Most_Recent_Lead_Source__c once it's been stamped (either by
     * stampMostRecentLeadSource above on the first touch, or written directly by an intake
     * class like saveWebTo_YourProfileData.cls on a later re-touch, since LeadSource itself
     * is locked by then). Falls back to LeadSource for a lead this field was never stamped on.
     */
    private static String touchSource(Lead ld) {
        String mostRecent = safeGet(ld, Lead.Most_Recent_Lead_Source__c);
        return String.isNotBlank(mostRecent) ? mostRecent : safeGet(ld, Lead.LeadSource);
    }

    /**
     * True for a genuinely new touch: the first time a lead gets a real source at all, or —
     * unlike LeadSource, which never changes again after that — any later update where
     * Most_Recent_Lead_Source__c actually changed to a different non-blank value.
     */
    private static Boolean isNewTouch(Lead ld, Map<Id, Lead> oldMap) {
        String newSource = touchSource(ld);
        if (oldMap == null) {
            return String.isNotBlank(newSource);
        }
        return String.isNotBlank(newSource) && newSource != touchSource(oldMap.get(ld.Id));
    }

    /** Pulls the 4-digit year out of Admission_Year__c (e.g. "Admission Year - 2026" -> "2026"). */
    private static String extractAdmissionYear(String admissionYearValue) {
        if (String.isBlank(admissionYearValue)) {
            return null;
        }
        Matcher m = Pattern.compile('\\d{4}').matcher(admissionYearValue);
        return m.find() ? m.group() : null;
    }

    /** Parent campaign is "<LeadSource> <AdmissionYear>" e.g. "Meta 2026"; drops the year if it can't be read. */
    private static String buildParentCampaignName(String leadSource, String admissionYearValue) {
        String year = extractAdmissionYear(admissionYearValue);
        return String.isNotBlank(year) ? (leadSource + ' ' + year) : leadSource;
    }

    private static String parentAttributionKey(String parentName) {
        return 'PARENT|' + parentName;
    }

    private static String childAttributionKey(Id parentId, String utmCampaignName) {
        return 'CHILD|' + parentId + '|' + utmCampaignName;
    }

    /**
     * Get-or-creates Campaigns keyed by Attribution_Key__c (Unique + External ID). Using
     * upsert against a unique field — instead of "query, then insert what's missing" — means
     * a genuinely concurrent attempt to create the same key can't silently produce two
     * Campaign rows: the platform's unique-index check fails the losing row outright, and
     * that row's Id is recovered below from whichever transaction actually won.
     */
    private static Map<String, Id> upsertCampaignsAndGetIds(Map<String, Campaign> campaignsByKey) {
        Map<String, Id> idByKey = new Map<String, Id>();
        if (campaignsByKey.isEmpty()) {
            return idByKey;
        }

        List<String> keys = new List<String>();
        List<Campaign> toUpsert = new List<Campaign>();
        for (String key : campaignsByKey.keySet()) {
            keys.add(key);
            toUpsert.add(campaignsByKey.get(key));
        }

        List<Database.UpsertResult> results = Database.upsert(toUpsert, Campaign.Attribution_Key__c, false);

        Set<String> keysToRecover = new Set<String>();
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                idByKey.put(keys[i], results[i].getId());
            } else {
                keysToRecover.add(keys[i]);
                System.debug(LoggingLevel.ERROR, 'syncCampaignMembership: failed to upsert Campaign for key ' + keys[i] + ': ' + results[i].getErrors());
            }
        }

        if (!keysToRecover.isEmpty()) {
            for (Campaign c : [SELECT Id, Attribution_Key__c FROM Campaign WHERE Attribution_Key__c IN :keysToRecover]) {
                idByKey.put(c.Attribution_Key__c, c.Id);
            }
        }

        // Campaigns created through the UI get default CampaignMemberStatus rows ("Sent"/
        // "Responded") automatically; Campaigns created via Apex/upsert do not, so without
        // this, adding a CampaignMember to one fails on the Status picklist. Checking what
        // each resolved Campaign already has (rather than trusting Database.UpsertResult's
        // isCreated() flag) keeps this idempotent no matter how the Campaign came to exist -
        // including a same-key Campaign resolved more than once in one transaction, which
        // previously hit FIELD_INTEGRITY_EXCEPTION re-inserting a Label that already existed.
        seedMissingDefaultMemberStatuses(idByKey.values());

        return idByKey;
    }

    private static void seedMissingDefaultMemberStatuses(List<Id> campaignIds) {
        if (campaignIds.isEmpty()) {
            return;
        }

        Map<Id, Set<String>> existingLabelsByCampaignId = new Map<Id, Set<String>>();
        Set<Id> campaignsWithADefault = new Set<Id>();
        for (Id campaignId : campaignIds) {
            existingLabelsByCampaignId.put(campaignId, new Set<String>());
        }
        for (CampaignMemberStatus cms : [SELECT CampaignId, Label, IsDefault FROM CampaignMemberStatus WHERE CampaignId IN :campaignIds]) {
            existingLabelsByCampaignId.get(cms.CampaignId).add(cms.Label);
            if (cms.IsDefault) {
                campaignsWithADefault.add(cms.CampaignId);
            }
        }

        List<CampaignMemberStatus> statusesToInsert = new List<CampaignMemberStatus>();
        for (Id campaignId : campaignIds) {
            Set<String> existingLabels = existingLabelsByCampaignId.get(campaignId);
            if (!existingLabels.contains('Sent')) {
                statusesToInsert.add(new CampaignMemberStatus(
                    CampaignId = campaignId, Label = 'Sent',
                    IsDefault = !campaignsWithADefault.contains(campaignId), HasResponded = false, SortOrder = 0
                ));
            }
            if (!existingLabels.contains('Responded')) {
                statusesToInsert.add(new CampaignMemberStatus(CampaignId = campaignId, Label = 'Responded', IsDefault = false, HasResponded = true, SortOrder = 1));
            }
        }
        // allOrNone=false: the query-then-insert-missing check above still leaves a narrow
        // window where the platform ends up seeing a Label that already exists for this
        // Campaign - a genuinely concurrent transaction, or (seen in this org's sandbox) a
        // record this SOQL can't see under test-data isolation even though it's really
        // there. Either way the platform's own Label-per-Campaign uniqueness rejects the
        // redundant row rather than corrupting data, so that failure is expected and
        // logged, not swallowed silently or allowed to abort the whole Lead save.
        if (!statusesToInsert.isEmpty()) {
            List<Database.SaveResult> statusResults = Database.insert(statusesToInsert, false);
            for (Integer i = 0; i < statusResults.size(); i++) {
                if (!statusResults[i].isSuccess()) {
                    for (Database.Error err : statusResults[i].getErrors()) {
                        System.debug(LoggingLevel.ERROR, 'seedMissingDefaultMemberStatuses: failed to insert CampaignMemberStatus for Campaign '
                            + statusesToInsert[i].CampaignId + ': ' + err.getStatusCode() + ' - ' + err.getMessage());
                    }
                }
            }
        }
    }

    /**
     * After insert/update — attaches the Lead to a parent/child Campaign structure:
     * parent = "<touch source> <AdmissionYear>" (e.g. "Meta 2026"), child = the specific
     * UTM_Campaign__c value nested under that parent (e.g. "Meta 2026" -> "meta_aug26_mba").
     * UTM_Campaign__c is blank most of the time, so when it's missing the Lead is added
     * to the parent Campaign directly instead — still attributed at the channel+year
     * level even without the specific ad campaign. Runs on every genuinely new touch
     * (isNewTouch), not just the first — a lead can pick up more than one Campaign over
     * its lifetime even though LeadSource itself never changes after the first touch.
     */
    public static void syncCampaignMembership(List<Lead> newLeads, Map<Id, Lead> oldMap) {
        List<Lead> leadsToProcess = new List<Lead>();
        Map<Id, String> parentNameByLeadId = new Map<Id, String>();
        Map<String, Campaign> parentsByKey = new Map<String, Campaign>();

        for (Lead ld : newLeads) {
            if (isNewTouch(ld, oldMap)) {
                String parentName = buildParentCampaignName(touchSource(ld), safeGet(ld, Lead.Admission_Year__c));
                String parentKey = parentAttributionKey(parentName);
                leadsToProcess.add(ld);
                parentNameByLeadId.put(ld.Id, parentName);
                if (!parentsByKey.containsKey(parentKey)) {
                    parentsByKey.put(parentKey, new Campaign(
                        Attribution_Key__c = parentKey,
                        Name = parentName,
                        IsActive = true
                    ));
                }
            }
        }
        if (leadsToProcess.isEmpty()) {
            return;
        }

        Map<String, Id> parentIdByKey = upsertCampaignsAndGetIds(parentsByKey);

        Map<String, Campaign> childrenByKey = new Map<String, Campaign>();
        for (Lead ld : leadsToProcess) {
            String utmCampaign = safeGet(ld, Lead.UTM_Campaign__c);
            if (String.isBlank(utmCampaign)) {
                continue;
            }
            Id parentId = parentIdByKey.get(parentAttributionKey(parentNameByLeadId.get(ld.Id)));
            if (parentId == null) {
                continue;
            }
            String childKey = childAttributionKey(parentId, utmCampaign);
            if (!childrenByKey.containsKey(childKey)) {
                childrenByKey.put(childKey, new Campaign(
                    Attribution_Key__c = childKey,
                    Name = utmCampaign,
                    ParentId = parentId,
                    IsActive = true
                ));
            }
        }
        Map<String, Id> childIdByKey = upsertCampaignsAndGetIds(childrenByKey);

        // Attach to the child campaign when UTM_Campaign__c is known, otherwise fall back to the parent.
        List<CampaignMember> membersToInsert = new List<CampaignMember>();
        for (Lead ld : leadsToProcess) {
            Id parentId = parentIdByKey.get(parentAttributionKey(parentNameByLeadId.get(ld.Id)));
            Id targetCampaignId = parentId;
            String utmCampaign = safeGet(ld, Lead.UTM_Campaign__c);
            if (String.isNotBlank(utmCampaign) && parentId != null) {
                targetCampaignId = childIdByKey.get(childAttributionKey(parentId, utmCampaign));
            }
            if (targetCampaignId != null) {
                membersToInsert.add(new CampaignMember(CampaignId = targetCampaignId, LeadId = ld.Id));
            }
        }

        // allOrNone=false: a lead re-touched by a source it's already a member of throws
        // DUPLICATE_VALUE on that row only — expected, not an error, rest still commit.
        // Anything else (e.g. a missing CampaignMemberStatus) is logged rather than swallowed.
        List<Database.SaveResult> memberResults = Database.insert(membersToInsert, false);
        for (Integer i = 0; i < memberResults.size(); i++) {
            if (!memberResults[i].isSuccess()) {
                for (Database.Error err : memberResults[i].getErrors()) {
                    if (err.getStatusCode() != StatusCode.DUPLICATE_VALUE) {
                        System.debug(LoggingLevel.ERROR, 'syncCampaignMembership: failed to insert CampaignMember for Lead '
                            + membersToInsert[i].LeadId + ': ' + err.getStatusCode() + ' - ' + err.getMessage());
                    }
                }
            }
        }
    }

    @TestVisible private static Boolean isAdmissionRoundAssignmentExecuting = false;

    /** Assigns an eligible Admission Round without blocking Lead creation on failure. */
    public static void assignAdmissionRounds(List<Lead> newLeads) {
        if (isAdmissionRoundAssignmentExecuting) return;
        isAdmissionRoundAssignmentExecuting = true;
        try {
            AdmissionRoundAssignmentService.assignEligibleRounds(newLeads);
        } catch (Exception exceptionValue) {
            AdmissionRoundAssignmentService.logUnexpected(
                'LeadTriggerHandler',
                exceptionValue.getMessage(),
                null
            );
        } finally {
            isAdmissionRoundAssignmentExecuting = false;
        }
    }
}
