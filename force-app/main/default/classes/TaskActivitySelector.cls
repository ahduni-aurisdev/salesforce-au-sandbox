/**
 * @description Selects the Leads, Accounts, and owners needed to place Tasks received through the Task Activity API.
 * @author AU Development Team
 * @date 2026-10-23
 * @version 1.1
 * @lastModified 2026-10-23
 */
public without sharing class TaskActivitySelector {
    // System-mode selection is intentional: the partner API runs as a Salesforce Integration
    // license user that cannot be granted Lead/Account/Contact visibility. Only record IDs and
    // owner IDs are read, and none of the selected data is returned to the caller.
    public static Map<Id, Lead> selectLeadsByIds(Set<Id> leadIds) {
        if (leadIds == null || leadIds.isEmpty()) return new Map<Id, Lead>();
        return new Map<Id, Lead>([
            SELECT Id, OwnerId, IsConverted, ConvertedAccountId, ConvertedContactId, ConvertedAccount.OwnerId
            FROM Lead
            WHERE Id IN :leadIds
        ]);
    }

    public static Map<Id, Account> selectAccountsByIds(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) return new Map<Id, Account>();
        return new Map<Id, Account>([
            SELECT Id, OwnerId
            FROM Account
            WHERE Id IN :accountIds
        ]);
    }

    public static Set<Id> selectActiveUserIds(Set<Id> userIds) {
        Set<Id> activeUserIds = new Set<Id>();
        if (userIds == null || userIds.isEmpty()) return activeUserIds;
        for (User userValue : [
            SELECT Id
            FROM User
            WHERE Id IN :userIds AND IsActive = true
        ]) {
            activeUserIds.add(userValue.Id);
        }
        return activeUserIds;
    }
}
