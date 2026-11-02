/**
 * @description Reads FeatureFlag__mdt toggles so a risky feature can be switched off without a deployment.
 *              A missing or blank flag counts as disabled.
 * @author AU Development Team
 * @date 2026-11-02
 * @version 1.0
 * @lastModified 2026-11-02
 */
public with sharing class FeatureFlagService {
    @TestVisible
    private static Map<String, Boolean> testOverrides = new Map<String, Boolean>();

    public static Boolean isEnabled(String flagName) {
        if (String.isBlank(flagName)) {
            return false;
        }
        if (testOverrides.containsKey(flagName)) {
            return testOverrides.get(flagName);
        }
        FeatureFlag__mdt flag = FeatureFlag__mdt.getInstance(flagName);
        return flag != null && flag.IsEnabled__c;
    }
}