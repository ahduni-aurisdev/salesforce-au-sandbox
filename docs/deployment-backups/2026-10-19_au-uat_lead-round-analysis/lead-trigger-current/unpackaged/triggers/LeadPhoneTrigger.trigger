/******************************************************************************************
* Create By        : Preksha Chauhan
* Company          : GetonCRM Solutions
* Trigger Name     : LeadPhoneTrigger
* Create Date      : 07/18/2024
* Description      : Trigger for the Lead object to update phone numbers based on country codes
*                    This trigger covers the following scenarios:
*                    - Before Insert: Invokes LeadPhoneUpdater to format phone numbers when new leads are inserted.
*                    - Before Update: Invokes LeadPhoneUpdater to format phone numbers when existing leads are updated.
*                    - Handles different contexts ('insert' or 'update') for phone number updates.
* Cover CodeCoverage: 60%
**********************************************************************************************/
trigger LeadPhoneTrigger on Lead (before insert, before update) {
    if (Trigger.isBefore) {
        if (Trigger.isInsert) {
            //system.debug('Trigger context: Insert');
            LeadPhoneUpdater.updatePhoneWithCountryCode(Trigger.oldMap, Trigger.new, 'insert');
        } else if (Trigger.isUpdate) {
           // system.debug('Trigger context: Update');
            LeadPhoneUpdater.updatePhoneWithCountryCode(Trigger.oldMap, Trigger.new, 'update');
        }
    }
}