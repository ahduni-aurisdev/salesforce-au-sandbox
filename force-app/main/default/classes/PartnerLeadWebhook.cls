/**
 * @description Generic Apex REST endpoint that external lead partners (MBA Rendezvous and future
 *              partners) call to push leads into Salesforce in real time. Authenticated with OAuth 2.0
 *              client credentials: each partner has its own External Client App, all running as the
 *              shared Partner Integration User.
 *
 *              POST https://<my-domain>.my.salesforce.com/services/apexrest/partner/lead
 *              Header  Authorization: Bearer <access token>
 *              Body    one JSON lead object, or a JSON list of up to 50 lead objects
 *
 *              The OAuth app that issued the token is read from the session's login history and
 *              passed to PartnerLeadService, which only accepts leadSource values configured for
 *              that app in Partner_Lead_Source__mdt.
 *
 *              Responses
 *                200  single lead saved: {"success":true,"leadId":"00Q...","action":"created"|"updated"}
 *                200  list: one result per lead, in order (check "success" on each)
 *                400  single lead rejected (message says why), body not JSON, or too many leads
 *                401  no valid token (Salesforce platform), or called as a Site guest user (this class)
 *                500  configuration missing, calling app unknown, or unexpected error (logged to API_Log__c)
 *                503  switched off with FeatureFlag__mdt Partner_Lead_API
 *
 *              Access: only users with permission set PARTNER_LEAD_API_ACCESS can call this class.
 *              Request bodies are never logged because they contain the student's name, email and phone.
 *
 * @author Jitendra V
 * @date 2026-11-18
 * @version 1.0
 * @lastModified 2026-11-18
 */
// without sharing is intentional: the integration user only has access to this class, not to Lead or
// LoginHistory records. Access is controlled by the OAuth token, the PARTNER_LEAD_API_ACCESS permission
// set and the leadSource-to-app check in PartnerLeadService.
@RestResource(urlMapping='/partner/lead')
global without sharing class PartnerLeadWebhook {

    @TestVisible
    private static final String FEATURE_FLAG_NAME = 'Partner_Lead_API';
    @TestVisible
    private static final Integer MAX_LEADS_PER_REQUEST = 50;
    @TestVisible
    private static final String LOG_NAME = 'PartnerLeadWebhook';

    private static final String GUEST_USER_TYPE = 'Guest';
    private static final String CLASS_NAME = 'PartnerLeadWebhook';
    private static final String CONTENT_TYPE = 'application/json';
    private static final String SESSION_LOGIN_HISTORY_KEY = 'LoginHistoryId';

    private static final Integer STATUS_OK = 200;
    private static final Integer STATUS_BAD_REQUEST = 400;
    private static final Integer STATUS_UNAUTHORISED = 401;
    private static final Integer STATUS_SERVER_ERROR = 500;
    private static final Integer STATUS_UNAVAILABLE = 503;

    private static final String MSG_DISABLED = 'The lead API is temporarily switched off. Please retry later.';
    private static final String MSG_NOT_CONFIGURED = 'The lead API is not configured. Please contact Ahmedabad University.';
    private static final String MSG_UNAUTHORISED = 'Authentication required. Call this API with an OAuth access token.';
    private static final String MSG_NOT_JSON = 'Body is not valid JSON.';
    private static final String MSG_EMPTY = 'Body must contain at least one lead.';
    private static final String MSG_TOO_MANY = 'Send at most ' + MAX_LEADS_PER_REQUEST + ' leads per request.';
    private static final String MSG_NOT_OBJECT = 'Each lead must be a JSON object.';
    private static final String MSG_UNEXPECTED = 'Unexpected error. Please retry later.';

    /** Set only by unit tests: overrides FeatureFlag__mdt. */
    @TestVisible
    private static Boolean testFeatureEnabled;
    /** Set only by unit tests: simulates a call from a Site guest user. */
    @TestVisible
    private static Boolean testIsGuest;
    /** Set only by unit tests: the OAuth app name, which cannot be read from a test session. */
    @TestVisible
    private static String testCallingApp;
    /** Set only by unit tests: thrown in place of the service call to exercise the error handling. */
    @TestVisible
    private static Exception testServiceFailure;

    /** Error body returned to the partner. */
    private class ErrorResponse {
        public Boolean success = false;
        public String message;

        public ErrorResponse(String message) {
            this.message = message;
        }
    }

    @HttpPost
    global static void receive() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', CONTENT_TYPE);

        if (isGuest()) {
            logFailure(req, 'Rejected call: no authenticated user (Site guest).', null);
            reply(res, STATUS_UNAUTHORISED, new ErrorResponse(MSG_UNAUTHORISED));
            return;
        }
        if (!isEnabled()) {
            reply(res, STATUS_UNAVAILABLE, new ErrorResponse(MSG_DISABLED));
            return;
        }

        Object parsed;
        try {
            parsed = JSON.deserializeUntyped(req.requestBody == null ? '' : req.requestBody.toString());
        } catch (JSONException e) {
            reply(res, STATUS_BAD_REQUEST, new ErrorResponse(MSG_NOT_JSON));
            return;
        }

        Boolean isList = parsed instanceof List<Object>;
        List<Object> items = isList ? (List<Object>) parsed : new List<Object>{ parsed };
        if (items.isEmpty()) {
            reply(res, STATUS_BAD_REQUEST, new ErrorResponse(MSG_EMPTY));
            return;
        }
        if (items.size() > MAX_LEADS_PER_REQUEST) {
            reply(res, STATUS_BAD_REQUEST, new ErrorResponse(MSG_TOO_MANY));
            return;
        }
        List<PartnerLeadService.LeadRequest> requests = new List<PartnerLeadService.LeadRequest>();
        for (Object item : items) {
            if (!(item instanceof Map<String, Object>)) {
                reply(res, STATUS_BAD_REQUEST, new ErrorResponse(MSG_NOT_OBJECT));
                return;
            }
            requests.add(new PartnerLeadService.LeadRequest((Map<String, Object>) item));
        }

        String app = callingApp(req);
        if (String.isBlank(app)) {
            logFailure(req, 'Rejected call: the OAuth app of the session could not be determined.', null);
            reply(res, STATUS_SERVER_ERROR, new ErrorResponse(MSG_NOT_CONFIGURED));
            return;
        }

        try {
            if (Test.isRunningTest() && testServiceFailure != null) {
                throw testServiceFailure;
            }
            List<PartnerLeadService.LeadResult> results = PartnerLeadService.saveLeads(requests, app);
            logRejectedLeads(req, app, results);
            if (isList) {
                reply(res, STATUS_OK, results);
            } else {
                reply(res, results[0].success ? STATUS_OK : STATUS_BAD_REQUEST, results[0]);
            }
        } catch (PartnerLeadService.ConfigurationException e) {
            logFailure(req, null, e);
            reply(res, STATUS_SERVER_ERROR, new ErrorResponse(MSG_NOT_CONFIGURED));
        } catch (Exception e) {
            // Last-resort handler so the partner always gets JSON; the full error is logged.
            logFailure(req, null, e);
            reply(res, STATUS_SERVER_ERROR, new ErrorResponse(MSG_UNEXPECTED));
        }
    }

    private static Boolean isGuest() {
        if (Test.isRunningTest() && testIsGuest != null) {
            return testIsGuest;
        }
        return UserInfo.getUserType() == GUEST_USER_TYPE;
    }

    private static Boolean isEnabled() {
        if (Test.isRunningTest() && testFeatureEnabled != null) {
            return testFeatureEnabled;
        }
        FeatureFlag__mdt flag = FeatureFlag__mdt.getInstance(FEATURE_FLAG_NAME);
        return flag != null && flag.IsEnabled__c;
    }

    /**
     * Name of the OAuth app that issued the caller's token (LoginHistory.Application, for example
     * "MBA Rendezvous Integration"), or null when it cannot be determined. Null fails closed.
     */
    private static String callingApp(RestRequest req) {
        if (Test.isRunningTest() && testCallingApp != null) {
            return testCallingApp;
        }
        try {
            Map<String, String> session = Auth.SessionManagement.getCurrentSession();
            String loginHistoryId = session == null ? null : session.get(SESSION_LOGIN_HISTORY_KEY);
            if (String.isBlank(loginHistoryId)) {
                return null;
            }
            List<LoginHistory> logins = [SELECT Application FROM LoginHistory WHERE Id = :loginHistoryId LIMIT 1];
            return logins.isEmpty() ? null : logins[0].Application;
        } catch (Exception e) {
            // Session details are unavailable in some contexts; fail closed and keep the full error.
            logFailure(req, null, e);
            return null;
        }
    }

    /** Logs each rejected lead's reason (no personal data) so failed partner pushes can be traced. */
    private static void logRejectedLeads(RestRequest req, String app, List<PartnerLeadService.LeadResult> results) {
        List<String> reasons = new List<String>();
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].success != true) {
                reasons.add('Item ' + (i + 1) + ': ' + results[i].message);
            }
        }
        if (!reasons.isEmpty()) {
            logFailure(req, app + ': ' + reasons.size() + ' of ' + results.size() + ' lead(s) rejected. ' + String.join(reasons, ' | '), null);
        }
    }

    private static void logFailure(RestRequest req, String message, Exception error) {
        String reference = req == null ? null : req.remoteAddress;
        if (error != null) {
            ZoomLogger.logFailure(LOG_NAME, CLASS_NAME, reference, error);
        } else {
            ZoomLogger.logFailure(LOG_NAME, CLASS_NAME, reference, message, null);
        }
    }

    private static void reply(RestResponse res, Integer statusCode, Object body) {
        res.statusCode = statusCode;
        res.responseBody = Blob.valueOf(JSON.serialize(body, true));
    }
}