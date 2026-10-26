trigger LeadTrigger on Lead (after insert, after update) {
    if (Trigger.isInsert) {
        LeadTriggerHandler.syncCampaignMembership(Trigger.new, null);
    } else if (Trigger.isUpdate) {
        LeadActivityHandler.moveActivitiesOnConversion(Trigger.new, Trigger.oldMap);
        LeadTriggerHandler.syncCampaignMembership(Trigger.new, Trigger.oldMap);
    }
}