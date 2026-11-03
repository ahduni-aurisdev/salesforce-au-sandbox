/**
 * @description Reads the single Zoom_Config__mdt record ("Default"): Zoom account ID, user, webhook secret token,
 *              activity switch and (until FeatureFlag Zoom_Named_Credential is enabled) the OAuth client credentials.
 * @author AU Development Team
 * @date 2026-10-21
 * @version 1.1
 * @lastModified 2026-11-02
 */
public with sharing class ZoomConfig {
    private static final String RECORD_NAME = 'Default';

    @TestVisible
    private static Zoom_Config__mdt testOverride;

    public static Zoom_Config__mdt get() {
        if (testOverride != null) {
            return testOverride;
        }
        Zoom_Config__mdt config = Zoom_Config__mdt.getInstance(RECORD_NAME);
        return config == null ? new Zoom_Config__mdt() : config;
    }
}