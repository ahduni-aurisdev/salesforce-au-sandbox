/**
 * @description Tests WaConfigSelector: active-account filtering and sorting, lookup by WABA ID, and reading
 *              the real (empty in tests) custom metadata and custom setting when no override is set.
 * @author AU Development Team
 * @date 2026-11-26
 * @version 1.0
 * @lastModified 2026-11-26
 */
@IsTest
private class WaConfigSelectorTest {
    @IsTest
    static void activeAccountsAreFilteredAndSorted() {
        WaConfigSelector.accountsOverride = new List<WA_Account__mdt>{
            new WA_Account__mdt(WABA_Id__c = '30000', Display_Label__c = 'B', Active__c = true),
            new WA_Account__mdt(WABA_Id__c = '20000', Display_Label__c = 'A', Active__c = true),
            new WA_Account__mdt(WABA_Id__c = '10000', Display_Label__c = 'First', Active__c = true, Sort_Order__c = 1),
            new WA_Account__mdt(WABA_Id__c = '40000', Display_Label__c = 'Hidden', Active__c = false, Sort_Order__c = 0),
            new WA_Account__mdt(WABA_Id__c = ' ', Display_Label__c = 'No ID', Active__c = true)
        };

        List<WA_Account__mdt> active = WaConfigSelector.getActiveAccounts();

        Assert.areEqual(3, active.size(), 'Inactive and blank-ID accounts are excluded');
        Assert.areEqual('10000', active[0].WABA_Id__c, 'Lowest sort order first');
        Assert.areEqual('20000', active[1].WABA_Id__c, 'Unsorted accounts are ordered by label');
        Assert.areEqual('30000', active[2].WABA_Id__c, 'Unsorted accounts are ordered by label');
        Assert.isNotNull(WaConfigSelector.findActiveAccount('20000'), 'Active account is found');
        Assert.isNull(WaConfigSelector.findActiveAccount('40000'), 'Inactive account is not found');
        Assert.isNull(WaConfigSelector.findActiveAccount(null), 'Blank ID is not found');
    }

    @IsTest
    static void readsOrgConfigurationWithoutOverrides() {
        insert new WA_Admin_Key__c(SetupOwnerId = UserInfo.getOrganizationId(), Key__c = 'org-default-key');

        Assert.areEqual('org-default-key', WaConfigSelector.getAdminKey(), 'Org default key is read from the custom setting');
        WaConfigSelector.getSetting();
        Assert.isNotNull(WaConfigSelector.getActiveAccounts(), 'Reading real custom metadata never returns null');
    }
}