/**
 * @description Starts pending Lead assignment when an Admission Round is inserted or activated.
 * @author AU Development Team
 * @date 2026-10-19
 * @version 1.0
 */
trigger AdmissionRoundTrigger on Admission_Round__c (after insert, after update) {
    if (Trigger.isAfter && Trigger.isInsert) {
        AdmissionRoundTriggerHandler.afterInsertOrUpdate(Trigger.new, null);
    }
    if (Trigger.isAfter && Trigger.isUpdate) {
        AdmissionRoundTriggerHandler.afterInsertOrUpdate(Trigger.new, Trigger.oldMap);
    }
}