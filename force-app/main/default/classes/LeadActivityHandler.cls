public class LeadActivityHandler {

    public static void moveActivitiesOnConversion(
        List<Lead> newLeads,
        Map<Id, Lead> oldMap
    ) {

        Set<Id> convertedLeadIds = new Set<Id>();
        Map<Id, Lead> convertedLeads = new Map<Id, Lead>();

        for (Lead ld : newLeads) {

            Lead oldLead = oldMap.get(ld.Id);

            if (!oldLead.IsConverted && ld.IsConverted) {
                convertedLeadIds.add(ld.Id);
                convertedLeads.put(ld.Id, ld);
            }
        }

        if (convertedLeadIds.isEmpty()) {
            return;
        }

        // Fetch Tasks related to Lead
        List<Task> tasksToUpdate = [
            SELECT Id, WhoId, WhatId
            FROM Task
            WHERE WhoId IN :convertedLeadIds
        ];

        for (Task t : tasksToUpdate) {

            Lead convertedLead = convertedLeads.get(t.WhoId);

            if (convertedLead.ConvertedContactId != null) {
                t.WhoId = convertedLead.ConvertedContactId;
            }

            if (convertedLead.ConvertedAccountId != null) {
                t.WhatId = convertedLead.ConvertedAccountId;
            }
        }

        if (!tasksToUpdate.isEmpty()) {
            update tasksToUpdate;
        }

        // Events
        List<Event> eventsToUpdate = [
            SELECT Id, WhoId, WhatId
            FROM Event
            WHERE WhoId IN :convertedLeadIds
        ];

        for (Event e : eventsToUpdate) {

            Lead convertedLead = convertedLeads.get(e.WhoId);

            if (convertedLead.ConvertedContactId != null) {
                e.WhoId = convertedLead.ConvertedContactId;
            }

            if (convertedLead.ConvertedAccountId != null) {
                e.WhatId = convertedLead.ConvertedAccountId;
            }
        }

        if (!eventsToUpdate.isEmpty()) {
            update eventsToUpdate;
        }
    }
}