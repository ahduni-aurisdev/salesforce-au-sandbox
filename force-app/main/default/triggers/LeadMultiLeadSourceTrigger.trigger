trigger LeadMultiLeadSourceTrigger on Lead (before insert, before update) {
    // Get all valid values from the multi-select picklist
    Set<String> validMultiSelectValues = new Set<String>();
    for(Schema.PicklistEntry ple : Lead.Multi_Select_Lead_Source__c.getDescribe().getPicklistValues()) {
        validMultiSelectValues.add(ple.getValue());
    }
    
    // Create a map of common typos to correct values
    Map<String, String> typoCorrectionMap = new Map<String, String>();
    for(String validValue : validMultiSelectValues) {
        String lowerValid = validValue.toLowerCase();
        
        // Add the correct value
        typoCorrectionMap.put(lowerValid, validValue);
        
        // Add common variations
        typoCorrectionMap.put(lowerValid.replace('_', ' '), validValue);
        typoCorrectionMap.put(lowerValid.replace('_', ''), validValue);
        
        // For Meta_Ads specifically, add more variations
        if (lowerValid.contains('meta') && lowerValid.contains('ads')) {
            typoCorrectionMap.put('meta ads', validValue);
            typoCorrectionMap.put('meta dds', validValue);
            typoCorrectionMap.put('meta das', validValue);  // Your actual typo!
            typoCorrectionMap.put('meta ad', validValue);
            typoCorrectionMap.put('metads', validValue);
            typoCorrectionMap.put('meta-ads', validValue);
        }

        // For KollegeApply specifically, add known misspellings
        if (lowerValid == 'kollegeapply') {
            typoCorrectionMap.put('kollageapply', validValue);  // Kollage vs Kollege
            typoCorrectionMap.put('kollage apply', validValue);
            typoCorrectionMap.put('kollege apply', validValue);
            typoCorrectionMap.put('collegeapply', validValue);
            typoCorrectionMap.put('college apply', validValue);
        }

        // For careers360 specifically, add known variations. Not 'careers 360' - that
        // exact string is its own separate valid picklist value ("Careers 360") already
        // mapped by the base loop above, so adding it here would overwrite it non-deterministically.
        if (lowerValid == 'careers360') {
            typoCorrectionMap.put('career360', validValue);  // Missing 's'
            typoCorrectionMap.put('career 360', validValue);
        }
    }
    
    // Process each lead
    for (Lead newLead : Trigger.new) {
        Set<String> allValues = new Set<String>();
        Lead oldLead = Trigger.isUpdate ? Trigger.oldMap.get(newLead.Id) : null;

        // Multi_Select_Lead_Source__c is an UNRESTRICTED multiselect picklist (confirmed via
        // Schema describe against the org - the field itself accepts any text), so nothing
        // below should require an exact match against validMultiSelectValues to be kept.
        // That Set/typoCorrectionMap still exist purely to NORMALIZE known misspellings
        // (e.g. "meta das") to their canonical picklist entry - anything else is stored as-is
        // rather than silently dropped, since the platform never rejected it in the first place.

        // This trigger runs on every Lead insert/update regardless of which class or query
        // loaded the record - a caller that queried a Lead without a given field makes a
        // direct read throw SObjectException: field not queried. LeadTriggerHandler.safeGet
        // treats an unqueried field as blank instead, since that's a far better failure mode
        // than crashing whatever DML triggered this code - seen in practice more than once.
        String oldMultiSelect = oldLead != null ? LeadTriggerHandler.safeGet(oldLead, Lead.Multi_Select_Lead_Source__c) : null;
        String newMultiSelect = LeadTriggerHandler.safeGet(newLead, Lead.Multi_Select_Lead_Source__c);
        String newLeadSource = LeadTriggerHandler.safeGet(newLead, Lead.LeadSource);
        String newMostRecent = LeadTriggerHandler.safeGet(newLead, Lead.Most_Recent_Lead_Source__c);

        // 1. Get existing values for updates - carry forward whatever was already stored,
        //    unfiltered (it was already validly saved once, being unrestricted).
        if (Trigger.isUpdate) {
            if (String.isNotBlank(oldMultiSelect)) {
                for(String val : oldMultiSelect.split(';')) {
                    val = val.trim();
                    if (String.isNotBlank(val)) {
                        allValues.add(val);
                    }
                }
            }
        }

        // 2. Process current Multi_Select_Lead_Source__c
        if (String.isNotBlank(newMultiSelect)) {
            for(String val : newMultiSelect.split(';')) {
                val = val.trim();
                if (String.isBlank(val)) {
                    continue;
                }
                String correctedVal = typoCorrectionMap.get(val.toLowerCase());
                allValues.add(correctedVal != null ? correctedVal : val);
            }
        }

        // 3. Process LeadSource - THIS IS KEY FOR DATA IMPORT
        if (String.isNotBlank(newLeadSource)) {
            String leadSourceVal = newLeadSource.trim();
            String correctedVal = typoCorrectionMap.get(leadSourceVal.toLowerCase());
            allValues.add(correctedVal != null ? correctedVal : leadSourceVal);
        }

        // 3b. Process Most_Recent_Lead_Source__c the same way LeadSource is processed above.
        //     LeadSource is locked after the first real touch (never overwritten), so a later
        //     re-touch by a different source only ever shows up on Most_Recent_Lead_Source__c -
        //     without this step, this multiselect field silently stops growing after the first
        //     touch even though the Lead has genuinely been touched by more sources since.
        if (String.isNotBlank(newMostRecent)) {
            String mostRecentVal = newMostRecent.trim();
            String correctedMostRecentVal = typoCorrectionMap.get(mostRecentVal.toLowerCase());
            allValues.add(correctedMostRecentVal != null ? correctedMostRecentVal : mostRecentVal);
        }

        // 4. Update the fields
        if (!allValues.isEmpty()) {
            newLead.Multi_Select_Lead_Source__c = String.join(new List<String>(allValues), ';');
        } else {
            newLead.Multi_Select_Lead_Source__c = null;
        }

        // 5. Update LeadScore - ONLY if LeadSource is not blank
        if (String.isBlank(newLeadSource)) {
            newLead.LeadScore__c = null;
        } else {
            newLead.LeadScore__c = allValues.size();
        }

        // 6. Track the order in which each lead source was first captured.
        //    Multi_Select_Lead_Source__c is a Set<String> under the hood, so Apex always
        //    reorders it alphabetically - it can never tell us which value arrived 1st/2nd/3rd.
        //    Multi_Select_Lead_Sources__c (Text) is untouched by any other trigger/class/flow,
        //    so it's safe to use purely as an append-only, dated history of that same field.
        String priorOrderText = Trigger.isUpdate
            ? (oldLead != null ? LeadTriggerHandler.safeGet(oldLead, Lead.Multi_Select_Lead_Sources__c) : null)
            : LeadTriggerHandler.safeGet(newLead, Lead.Multi_Select_Lead_Sources__c);

        Set<String> alreadyTrackedValues = new Set<String>();
        if (String.isNotBlank(priorOrderText)) {
            for (String entry : priorOrderText.split(';')) {
                entry = entry.trim();
                Integer dateStart = entry.indexOf('(');
                String valueName = dateStart > 0 ? entry.substring(0, dateStart).trim() : entry;
                if (String.isNotBlank(valueName)) {
                    alreadyTrackedValues.add(valueName);
                }
            }
        }

        List<String> newlyAddedEntries = new List<String>();
        Date today = Date.today();
        String todayFormatted = (today.month() < 10 ? '0' : '') + today.month() + '/'
            + (today.day() < 10 ? '0' : '') + today.day() + '/' + today.year();
        for (String val : allValues) {
            if (!alreadyTrackedValues.contains(val)) {
                newlyAddedEntries.add(val + ' (' + todayFormatted + ')');
            }
        }

        if (!newlyAddedEntries.isEmpty()) {
            String updatedOrderText = String.isNotBlank(priorOrderText)
                ? priorOrderText + '; ' + String.join(newlyAddedEntries, '; ')
                : String.join(newlyAddedEntries, '; ');

            // Multi_Select_Lead_Sources__c is a 255-char Text field. If appending would exceed
            // that, drop the oldest entries rather than let the DML fail and block the save.
            // (Field History Tracking is enabled on this field, so the full history is never lost.)
            if (updatedOrderText.length() > 255) {
                List<String> allEntries = new List<String>();
                for (String e : updatedOrderText.split(';')) {
                    allEntries.add(e.trim());
                }
                while (!allEntries.isEmpty() && String.join(allEntries, '; ').length() > 255) {
                    allEntries.remove(0);
                }
                updatedOrderText = String.join(allEntries, '; ');
            }

            newLead.Multi_Select_Lead_Sources__c = updatedOrderText;
        }
    }
}


/*
trigger LeadMultiLeadSourceTrigger on Lead (before insert, before update) {
    // First, get the allowed values for the multi-select picklist
    Schema.DescribeFieldResult multiSelectFieldDescribe = Lead.Multi_Select_Lead_Source__c.getDescribe();
    List<Schema.PicklistEntry> multiSelectPicklistValues = multiSelectFieldDescribe.getPicklistValues();
    Set<String> allowedMultiSelectValues = new Set<String>();
    
    // Create a map of normalized (lowercase) values to actual picklist values
    Map<String, String> normalizedToActualValue = new Map<String, String>();
    
    for (Schema.PicklistEntry ple : multiSelectPicklistValues) {
        allowedMultiSelectValues.add(ple.getValue());
        normalizedToActualValue.put(ple.getValue().toLowerCase(), ple.getValue());
    }
    
    Map<Id, Lead> oldMap = Trigger.isUpdate ? Trigger.oldMap : new Map<Id, Lead>();

    for (Lead newLead : Trigger.new) {
        // STEP 1: Build final list
        List<String> finalValues = new List<String>();
        
        // Add existing values from old record
        if (Trigger.isUpdate) {
            Lead oldRec = oldMap.get(newLead.Id);
            if (oldRec != null && String.isNotBlank(oldRec.Multi_Select_Lead_Source__c)) {
                for (String val : oldRec.Multi_Select_Lead_Source__c.split(';')) {
                    val = val.trim();
                    if (!finalValues.contains(val) && allowedMultiSelectValues.contains(val)) {
                        finalValues.add(val);
                    }
                }
            }
        }
        
        // STEP 2: Process current Multi_Select_Lead_Source__c
        if (String.isNotBlank(newLead.Multi_Select_Lead_Source__c)) {
            for (String val : newLead.Multi_Select_Lead_Source__c.split(';')) {
                val = val.trim();
                String normalizedVal = val.toLowerCase();
                
                // Check if the exact value exists in picklist
                if (allowedMultiSelectValues.contains(val)) {
                    if (!finalValues.contains(val)) {
                        finalValues.add(val);
                    }
                }
                // Check if a normalized version exists
                else if (normalizedToActualValue.containsKey(normalizedVal)) {
                    String actualValue = normalizedToActualValue.get(normalizedVal);
                    if (!finalValues.contains(actualValue)) {
                        finalValues.add(actualValue);
                    }
                }
                // Try to fix common typos
                else if (normalizedVal.contains('meta') && (normalizedVal.contains('ads') || normalizedVal.contains('dds'))) {
                    // Try to find a matching meta ads value
                    String metaAdsValue = null;
                    
                    // Look for any allowed value that contains 'meta' and 'ads'
                    for (String allowedValue : allowedMultiSelectValues) {
                        String allowedLower = allowedValue.toLowerCase();
                        if (allowedLower.contains('meta') && 
                            (allowedLower.contains('ads') || allowedLower.contains('ad'))) {
                            metaAdsValue = allowedValue;
                            break;
                        }
                    }
                    
                    if (metaAdsValue != null && !finalValues.contains(metaAdsValue)) {
                        finalValues.add(metaAdsValue);
                    }
                }
            }
        }
        
        // STEP 3: Process LeadSource - Map to corresponding multi-select value
        if (String.isNotBlank(newLead.LeadSource)) {
            String leadSourceVal = newLead.LeadSource.trim();
            String normalizedLeadSource = leadSourceVal.toLowerCase();
            
            // First, check if LeadSource directly matches a multi-select value
            if (allowedMultiSelectValues.contains(leadSourceVal)) {
                if (!finalValues.contains(leadSourceVal)) {
                    finalValues.add(leadSourceVal);
                }
            }
            // Check if normalized version matches
            else if (normalizedToActualValue.containsKey(normalizedLeadSource)) {
                String actualValue = normalizedToActualValue.get(normalizedLeadSource);
                if (!finalValues.contains(actualValue)) {
                    finalValues.add(actualValue);
                }
            }
            // Try to map common LeadSource values to multi-select values
            else {
                // Common mapping logic - you may need to customize this based on your org
                String mappedValue = null;
                
                if (normalizedLeadSource.contains('meta') && 
                    (normalizedLeadSource.contains('ads') || normalizedLeadSource.contains('dds'))) {
                    // Look for any Meta Ads related value in multi-select picklist
                    for (String allowedValue : allowedMultiSelectValues) {
                        String allowedLower = allowedValue.toLowerCase();
                        if (allowedLower.contains('meta') && 
                            (allowedLower.contains('ads') || allowedLower.contains('ad'))) {
                            mappedValue = allowedValue;
                            break;
                        }
                    }
                }
                // Add more mappings as needed for other LeadSource values
                
                if (mappedValue != null && !finalValues.contains(mappedValue)) {
                    finalValues.add(mappedValue);
                }
            }
        }
        
        // STEP 4: Update the multi-select field
        if (!finalValues.isEmpty()) {
            newLead.Multi_Select_Lead_Source__c = String.join(finalValues, ';');
        } else {
            newLead.Multi_Select_Lead_Source__c = null;
        }
        
        // STEP 5: Update LeadScore
        newLead.LeadScore__c = finalValues.size();
    }
}
*/