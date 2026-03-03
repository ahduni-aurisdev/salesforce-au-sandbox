public class DuplicateLeadHandler {

    // Method to create DuplicateRecordSet and DuplicateRecordItem for existing duplicate leads
    public static void createDuplicateRecordSetForExistingDuplicates() {
        System.debug('Starting the createDuplicateRecordSetForExistingDuplicates method...');
        
        // Query existing lead duplicates based on criteria (e.g., same email or phone number)
        List<Lead> duplicateLeads = [SELECT Id, Email, Phone FROM Lead WHERE Email != NULL AND Phone != NULL];
        System.debug('Found ' + duplicateLeads.size() + ' duplicate leads.');

        if (duplicateLeads.isEmpty()) {
            System.debug('No duplicate leads found.');
            return;
        }

        // Group leads by Email and Phone to form duplicate groups
        Map<String, List<Lead>> groupedLeads = new Map<String, List<Lead>>();
        
        for (Lead lead : duplicateLeads) {
            String key = lead.Email + '-' + lead.Phone;  // Unique key for grouping based on Email and Phone
            if (!groupedLeads.containsKey(key)) {
                groupedLeads.put(key, new List<Lead>());
            }
            groupedLeads.get(key).add(lead);
        }

        // Iterate over the groups of duplicates and create DuplicateRecordSets
        List<DuplicateRecordSet> recordSetsToInsert = new List<DuplicateRecordSet>();
        List<DuplicateRecordItem> recordItemsToInsert = new List<DuplicateRecordItem>();

        for (String key : groupedLeads.keySet()) {
            List<Lead> leads = groupedLeads.get(key);
            
            // Create a new DuplicateRecordSet for each group of duplicates
            DuplicateRecordSet newSet = new DuplicateRecordSet(
                DuplicateRuleId = [SELECT Id FROM DuplicateRule WHERE DeveloperName = 'Undergradution_Duplicate_Lead' LIMIT 1].Id
                // No need to set Status or DeveloperName, let Salesforce handle these
            );
            recordSetsToInsert.add(newSet);
            
            // Create DuplicateRecordItems for each lead in the group
            for (Lead lead : leads) {
                DuplicateRecordItem newItem = new DuplicateRecordItem(
                    DuplicateRecordSetId = newSet.Id,
                    RecordId = lead.Id,
                    Is_Undergraduate_Record__c = true // Set based on your business logic
                );
                recordItemsToInsert.add(newItem);
            }
        }

        // Insert the DuplicateRecordSets
        try {
            insert recordSetsToInsert;
            System.debug('Inserted ' + recordSetsToInsert.size() + ' DuplicateRecordSets.');
        } catch (Exception e) {
            System.debug('Error inserting DuplicateRecordSets: ' + e.getMessage());
        }

        // Insert the DuplicateRecordItems after DuplicateRecordSets have been created
        try {
            insert recordItemsToInsert;
            System.debug('Inserted ' + recordItemsToInsert.size() + ' DuplicateRecordItems.');
        } catch (Exception e) {
            System.debug('Error inserting DuplicateRecordItems: ' + e.getMessage());
        }
    }
}