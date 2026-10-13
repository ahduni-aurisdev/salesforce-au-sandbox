trigger OpportunityTrigger on Opportunity(before update, after update) {
    if (Trigger.isBefore && Trigger.isUpdate) {
        OpportunityTriggerHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
    } else if (Trigger.isAfter && Trigger.isUpdate) {
        OpportunityTriggerHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
    }
}