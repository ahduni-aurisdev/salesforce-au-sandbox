/**
 * @description Gatekeeper for every WhatsApp Template Manager API call: checks the feature flag and the
 *              admin key sent in the X-Admin-Key header. Headers are read case-insensitively because
 *              HTTP/2 lowercases them. Keys are compared as SHA-256 digests in constant time.
 *              No lockout or throttling, by user decision (2026-11-26).
 * @author AU Development Team
 * @date 2026-11-26
 * @version 1.0
 * @lastModified 2026-11-26
 */
public with sharing class WaAuthService {
    public static final String FEATURE_FLAG = 'WA_Template_Manager';
    public static final String HEADER_ADMIN_KEY = 'X-Admin-Key';
    private static final String DIGEST_ALGORITHM = 'SHA-256';

    @TestVisible
    private static final String MSG_SWITCHED_OFF = 'The WhatsApp Template Manager is switched off. Ask your Salesforce admin to turn on the WA Template Manager feature flag.';
    @TestVisible
    private static final String MSG_KEY_NOT_SET = 'The admin key has not been set up yet. Ask your Salesforce admin to set it in Setup > Custom Settings > WA Admin Key.';
    @TestVisible
    private static final String MSG_KEY_MISSING = 'Enter the admin key to continue.';
    @TestVisible
    private static final String MSG_KEY_WRONG = 'The admin key is incorrect. Check it and try again.';

    /**
     * @description Throws WaException (503 or 401) unless the feature is on and the admin key matches.
     * @param request the incoming REST request
     */
    public static void authorize(RestRequest request) {
        if (!FeatureFlagService.isEnabled(FEATURE_FLAG)) {
            throw WaException.of(503, MSG_SWITCHED_OFF);
        }
        String configuredKey = WaConfigSelector.getAdminKey();
        if (String.isBlank(configuredKey)) {
            throw WaException.of(503, MSG_KEY_NOT_SET);
        }
        String suppliedKey = getHeader(request, HEADER_ADMIN_KEY);
        if (String.isBlank(suppliedKey)) {
            throw WaException.of(401, MSG_KEY_MISSING);
        }
        if (!keysMatch(suppliedKey, configuredKey)) {
            throw WaException.of(401, MSG_KEY_WRONG);
        }
    }

    /**
     * @description Reads a request header ignoring case.
     * @param request the REST request
     * @param name header name in any case
     * @return the header value, or null
     */
    public static String getHeader(RestRequest request, String name) {
        if (request == null || request.headers == null || String.isBlank(name)) {
            return null;
        }
        for (String key : request.headers.keySet()) {
            if (key != null && key.equalsIgnoreCase(name)) {
                return request.headers.get(key);
            }
        }
        return null;
    }

    @TestVisible
    private static Boolean keysMatch(String supplied, String configured) {
        String suppliedDigest = digest(supplied);
        String configuredDigest = digest(configured);
        Integer difference = 0;
        for (Integer i = 0; i < configuredDigest.length(); i++) {
            difference |= suppliedDigest.charAt(i) ^ configuredDigest.charAt(i);
        }
        return difference == 0;
    }

    private static String digest(String value) {
        return EncodingUtil.convertToHex(Crypto.generateDigest(DIGEST_ALGORITHM, Blob.valueOf(value)));
    }
}