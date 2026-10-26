/******************************************************************************************
* Created By        : Preksha Chauhan
* Company           : GetonCRM Solutions
* Trigger Name      : leadBeforeInsertLastName
* Created Date      : 08/09/2024
* Description       : Trigger for the Lead object to ensure the LastName field is populated
*                     if it is left blank during record insertion or update. This trigger
*                     covers the following scenarios:
*                     - Before Insert: Sets the LastName to the value of FirstName if LastName
*                       is blank when a new Lead record is being inserted.
*                     - Before Update: Updates the LastName to the value of FirstName if LastName
*                       is blank and was previously set (not blank) when an existing Lead record
*                       is being updated.
*                     - Handles different contexts ('insert' or 'update') for updating LastName.
* Coverage: 80%
**********************************************************************************************/

trigger leadBeforeInsertLastName on Lead (before insert, before update) {
    if (Trigger.isBefore) {
        if (Trigger.isInsert) {
           // LeadTriggerHandler.handleBeforeInsert(Trigger.new);
        } else if (Trigger.isUpdate) {
          //  LeadTriggerHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
        }
    }
}