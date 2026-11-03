/**
 * @description Reads the single Zoom_Config__mdt record ("Default"): Zoom account ID, user, webhook secret token,
 *              activity switch, allowed host IDs and (until FeatureFlag Zoom_Named_Credential is enabled) the OAuth
 *              client credentials.
 * @author AU Development Team
 * @date 2026-10-21
 * @version 1.2
 * @lastModified 2026-11-03
 */
public with sharing class ZoomConfig {
    private static final String RECORD_NAME = 'Default';
    private static final String LIST_SEPARATOR = ',';

    @TestVisible
    private static Zoom_Config__mdt testOverride;

    public static Zoom_Config__mdt get() {
        if (testOverride != null) {
            return testOverride;
        }
        Zoom_Config__mdt config = Zoom_Config__mdt.getInstance(RECORD_NAME);
        return config == null ? new Zoom_Config__mdt() : config;
    }

    /** Zoom host IDs from Allowed_Host_Ids__c (comma-separated, trimmed). Empty = every host is allowed. */
    public static Set<String> allowedHostIds() {
        Set<String> hostIds = new Set<String>();
        String configured = get().Allowed_Host_Ids__c;
        if (String.isBlank(configured)) {
            return hostIds;
        }
        for (String hostId : configured.split(LIST_SEPARATOR)) {
            if (String.isNotBlank(hostId)) {
                hostIds.add(hostId.trim());
            }
        }
        return hostIds;
    }
}