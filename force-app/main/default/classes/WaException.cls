/**
 * @description Error raised by the WhatsApp Template Manager. Carries the HTTP status returned to the page
 *              and whether the failure must be written to API_Log__c (Meta, callout and system failures only,
 *              never user validation or admin-key errors). The message is always safe to show to the user.
 * @author AU Development Team
 * @date 2026-11-26
 * @version 1.1
 * @lastModified 2026-11-27
 */
public with sharing class WaException extends Exception {
    /**
     * Apex REST only accepts these HTTP statuses: 200, 201, 202, 204, 206, 300, 301, 302, 304, 400, 401, 403,
     * 404, 405, 406, 409, 410, 412, 413, 414, 415, 417, 500 and 503. Any other value (for example 429, 502
     * or 504) makes Salesforce discard the response body and return a bare HTTP 500, so the user never sees
     * the message. Meta, token and callout failures therefore use these two codes only.
     */
    public static final Integer HTTP_UPSTREAM_FAILED = 500;
    public static final Integer HTTP_TRY_LATER = 503;

    public Integer statusCode = HTTP_UPSTREAM_FAILED;
    public Boolean logFailure = false;
    public String detail;

    /**
     * @description Builds an error that is shown to the user and not logged.
     * @param statusCode HTTP status for the response
     * @param message human-readable message
     * @return the exception
     */
    public static WaException of(Integer statusCode, String message) {
        WaException error = new WaException(message);
        error.statusCode = statusCode;
        return error;
    }

    /**
     * @description Builds an error that is shown to the user and also written to API_Log__c.
     * @param statusCode HTTP status for the response
     * @param message human-readable message
     * @param detail technical detail for the log only (never contains the token)
     * @return the exception
     */
    public static WaException logged(Integer statusCode, String message, String detail) {
        WaException error = of(statusCode, message);
        error.logFailure = true;
        error.detail = detail;
        return error;
    }
}