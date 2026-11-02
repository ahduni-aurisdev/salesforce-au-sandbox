/**
 * @description Writes Zoom integration failures to API_Log__c so they are queryable and reportable.
 *              Never logs request bodies: Zoom payloads contain registrant names, emails and phone numbers.
 * @author AU Development Team
 * @date 2026-11-02
 * @version 1.0
 * @lastModified 2026-11-02
 */
// System mode is intentional: failures are raised by the Zoom webhook, which runs as the Site guest
// user with no object access. Logging must not depend on the caller's permissions, and the log
// records are never returned to the caller.
public without sharing class ZoomLogger {
    @TestVisible
    private static final String LOG_TYPE_FAILED = 'Failed';
    private static final Integer MAX_TEXT_LENGTH = 255;
    private static final Integer MAX_LONG_TEXT_LENGTH = 131072;

    /**
     * @description Inserts one failure log. Never throws, so logging cannot hide the original error.
     * @param logName short operation name, e.g. ZoomWebhook or ZoomWebinarSync
     * @param className Apex class that raised the failure
     * @param reference Zoom session ID or event name the failure relates to
     * @param error the exception that was caught
     */
    public static void logFailure(String logName, String className, String reference, Exception error) {
        String message = error == null ? null : error.getTypeName() + ': ' + error.getMessage();
        String detail = error == null ? null : error.getStackTraceString();
        logFailure(logName, className, reference, message, detail);
    }

    public static void logFailure(String logName, String className, String reference, String message, String detail) {
        API_Log__c log = new API_Log__c(
            Log_Name__c = truncate(logName, MAX_TEXT_LENGTH),
            Apex_Class_Name__c = truncate(className, MAX_TEXT_LENGTH),
            Registration_Number__c = truncate(reference, MAX_TEXT_LENGTH),
            Log_Type__c = LOG_TYPE_FAILED,
            Response__c = truncate(message, MAX_LONG_TEXT_LENGTH),
            Exception_Description__c = truncate(detail, MAX_LONG_TEXT_LENGTH)
        );
        Database.insert(new List<API_Log__c>{ log }, false);
    }

    private static String truncate(String value, Integer maxLength) {
        if (value == null || value.length() <= maxLength) {
            return value;
        }
        return value.substring(0, maxLength);
    }
}