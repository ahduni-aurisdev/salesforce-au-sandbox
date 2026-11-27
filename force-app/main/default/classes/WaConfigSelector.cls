/**
 * @description Reads WhatsApp Template Manager configuration: WA_Setting__mdt (app ID, Graph version),
 *              WA_Account__mdt (allowed WABAs) and the WA_Admin_Key__c custom setting. No SOQL is used
 *              (getInstance / getAll / getOrgDefaults), so no query limits are consumed.
 *              Tests set the @TestVisible overrides so they never depend on real records.
 * @author AU Development Team
 * @date 2026-11-26
 * @version 1.0
 * @lastModified 2026-11-26
 */
public with sharing class WaConfigSelector {
    public static final String SETTING_RECORD_NAME = 'Default';
    private static final Decimal DEFAULT_SORT_ORDER = 9999;

    @TestVisible
    private static WA_Setting__mdt settingOverride;
    @TestVisible
    private static List<WA_Account__mdt> accountsOverride;
    @TestVisible
    private static String adminKeyOverride;

    /**
     * @description Returns the Default settings record, or null when it does not exist.
     * @return WA_Setting__mdt
     */
    public static WA_Setting__mdt getSetting() {
        if (settingOverride != null) {
            return settingOverride;
        }
        return WA_Setting__mdt.getInstance(SETTING_RECORD_NAME);
    }

    /**
     * @description Returns the active accounts sorted by Sort_Order__c, then label.
     * @return active WA_Account__mdt records
     */
    public static List<WA_Account__mdt> getActiveAccounts() {
        List<WA_Account__mdt> source = accountsOverride != null ? accountsOverride : WA_Account__mdt.getAll().values();
        List<WA_Account__mdt> active = new List<WA_Account__mdt>();
        for (WA_Account__mdt account : source) {
            if (account.Active__c == true && String.isNotBlank(account.WABA_Id__c)) {
                active.add(account);
            }
        }
        active.sort(new AccountComparator());
        return active;
    }

    /**
     * @description Finds an active account by WABA ID.
     * @param wabaId WhatsApp Business Account ID
     * @return the account, or null when the ID is not configured or not active
     */
    public static WA_Account__mdt findActiveAccount(String wabaId) {
        if (String.isBlank(wabaId)) {
            return null;
        }
        for (WA_Account__mdt account : getActiveAccounts()) {
            if (account.WABA_Id__c.trim() == wabaId) {
                return account;
            }
        }
        return null;
    }

    /**
     * @description Returns the admin key from the org default of WA_Admin_Key__c.
     * @return the key, or null when it has not been set
     */
    public static String getAdminKey() {
        if (adminKeyOverride != null) {
            return adminKeyOverride;
        }
        WA_Admin_Key__c setting = WA_Admin_Key__c.getOrgDefaults();
        return setting == null ? null : setting.Key__c;
    }

    private class AccountComparator implements Comparator<WA_Account__mdt> {
        public Integer compare(WA_Account__mdt first, WA_Account__mdt second) {
            Decimal firstOrder = first.Sort_Order__c == null ? DEFAULT_SORT_ORDER : first.Sort_Order__c;
            Decimal secondOrder = second.Sort_Order__c == null ? DEFAULT_SORT_ORDER : second.Sort_Order__c;
            if (firstOrder != secondOrder) {
                return firstOrder < secondOrder ? -1 : 1;
            }
            String firstLabel = first.Display_Label__c == null ? '' : first.Display_Label__c;
            String secondLabel = second.Display_Label__c == null ? '' : second.Display_Label__c;
            return firstLabel.compareTo(secondLabel);
        }
    }
}