trigger cdc_Campus_Drive on Campus_Drive__c (before insert, after insert, after update, before update, before delete, after delete) {
    if (Trigger.isAfter) {
        cdc_Campus_DriveHandler.handleAfterInsert(Trigger.new);
    }
    if (Trigger.isBefore) {
        cdc_Campus_DriveHandler.handleBeforeInsert(Trigger.new);
    }
}