/**
 * @description Apex REST endpoint that MBA Rendezvous calls to push MBA / Masters leads into Salesforce in
 *              real time. Authenticated with OAuth 2.0 (client credentials): MBA Rendezvous gets an access
 *              token from the MBA_Rendezvous_Integration Connected App, which runs as the dedicated
 *              MBA Rendezvous integration user, then calls:
 *
 *              POST https://<my-domain>.my.salesforce.com/services/apexrest/partner/mbarendezvous/lead
 *              Header  Authorization: Bearer <access token>
 *              Body    one JSON lead object, or a JSON list of up to 50 lead objects
 *
 *              Responses
 *                200  single lead saved: {"success":true,"leadId":"00Q...","action":"created"|"updated"}
 *                200  list: one result per lead, in order (check "success" on each)
 *                400  single lead rejected (message says why), body not JSON, or too many leads
 *                401  no valid token (Salesforce platform), or called as a Site guest user (this class)
 *                500  configuration missing or unexpected error (logged to API_Log__c)
 *                503  switched off with FeatureFlag__mdt MBA_Rendezvous_Lead_Webhook
 *
 *              Access: only users with permission set MBA_RENDEZVOUS_API_ACCESS can call this class.
 *              Guest (unauthenticated) calls are refused even if a public Site exposes the class.
 *              Request bodies are never logged because they contain the student's name, email and phone.
 *
 * @author Jitendra V
 * @date 2026-11-16
 * @version 2.0
 * @lastModified 2026-11-17 - switched from public-site API key to OAuth integration user
 */
// without sharing is intentional: the integration user only has access to this class, not Lead
// records. The duplicate check in MBARendezvousLeadService must see every Masters Lead. Access is
// controlled by the OAuth token plus the MBA_RENDEZVOUS_API_ACCESS permission set.
@RestResource(urlMapping='/partner/mbarendezvous/lead')
global without sharing class MBARendezvousLeadWebhook {

    @TestVisible
    private static final String FEATURE_FLAG_NAME = 'MBA_Rendezvous_Lead_Webhook';
    @TestVisible
    private static final Integer MAX_LEADS_PER_REQUEST = 50;
    @TestVisible
    private static final String LOG_NAME = 'MBARendezvousLeadWebhook';

    private static final String GUEST_USER_TYPE = 'Guest';
    private static final String CLASS_NAME = 'MBARendezvousLeadWebhook';
    private static final String CONTENT_TYPE = 'application/json';

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
        List<MBARendezvousLeadService.LeadRequest> requests = new List<MBARendezvousLeadService.LeadRequest>();
        for (Object item : items) {
            if (!(item instanceof Map<String, Object>)) {
                reply(res, STATUS_BAD_REQUEST, new ErrorResponse(MSG_NOT_OBJECT));
                return;
            }
            requests.add(new MBARendezvousLeadService.LeadRequest((Map<String, Object>) item));
        }

        try {
            List<MBARendezvousLeadService.LeadResult> results = MBARendezvousLeadService.saveLeads(requests);
            logRejectedLeads(req, results);
            if (isList) {
                reply(res, STATUS_OK, results);
            } else {
                reply(res, results[0].success ? STATUS_OK : STATUS_BAD_REQUEST, results[0]);
            }
        } catch (MBARendezvousLeadService.ConfigurationException e) {
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

    /** Logs each rejected lead's reason (no personal data) so failed partner pushes can be traced. */
    private static void logRejectedLeads(RestRequest req, List<MBARendezvousLeadService.LeadResult> results) {
        List<String> reasons = new List<String>();
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].success != true) {
                reasons.add('Item ' + (i + 1) + ': ' + results[i].message);
            }
        }
        if (!reasons.isEmpty()) {
            logFailure(req, reasons.size() + ' of ' + results.size() + ' lead(s) rejected. ' + String.join(reasons, ' | '), null);
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