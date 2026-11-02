/**
 * @description Zoom event subscription endpoint, exposed through Site Zoom_Webhook (guest user). Register
 *              https://<site-domain>/zoomwebhook/services/apexrest/zoom/webhook in the Zoom Marketplace app.
 *              Every event is verified with the Zoom secret token (x-zm-signature header) before it is processed.
 *              Responses: 200 processed or ignored, 400 malformed body, 401 bad signature, 500 not configured or
 *              processing failed (Zoom retries 5xx).
 * @author AU Development Team
 * @date 2026-10-21
 * @version 1.1
 * @lastModified 2026-11-02
 */
// System mode is intentional: Zoom calls this endpoint as the Site guest user, which has no record access.
// Authenticity is enforced by the HMAC-SHA256 signature check below; nothing but a status is returned.
@RestResource(urlMapping='/zoom/webhook/*')
global without sharing class ZoomWebhook {
    @TestVisible
    private static final String FLAG_INTEGRATION = 'Zoom_Integration';
    private static final String EVENT_URL_VALIDATION = 'endpoint.url_validation';
    private static final String HEADER_TIMESTAMP = 'x-zm-request-timestamp';
    private static final String HEADER_SIGNATURE = 'x-zm-signature';
    private static final String SIGNATURE_VERSION = 'v0';
    private static final String HMAC_ALGORITHM = 'hmacSHA256';
    private static final String LOG_NAME = 'ZoomWebhook';
    private static final String CLASS_NAME = 'ZoomWebhook';
    private static final Integer HTTP_OK = 200;
    private static final Integer HTTP_BAD_REQUEST = 400;
    private static final Integer HTTP_UNAUTHORIZED = 401;
    private static final Integer HTTP_SERVER_ERROR = 500;

    @HttpPost
    global static void receive() {
        RestRequest request = RestContext.request;
        RestResponse response = RestContext.response;
        response.addHeader('Content-Type', 'application/json');
        String body = request.requestBody == null ? '' : request.requestBody.toString();

        String secret = ZoomConfig.get().Webhook_Secret_Token__c;
        if (String.isBlank(secret)) {
            ZoomLogger.logFailure(LOG_NAME, CLASS_NAME, null, 'Webhook secret token is not configured in Zoom_Config.Default', null);
            respond(response, HTTP_SERVER_ERROR, '{"error":"secret token not configured"}');
            return;
        }

        Map<String, Object> root;
        try {
            root = ZoomEventService.asMap(JSON.deserializeUntyped(body));
        } catch (JSONException e) {
            root = null;
        }
        if (root == null) {
            respond(response, HTTP_BAD_REQUEST, '{"error":"invalid JSON"}');
            return;
        }
        String event = ZoomEventService.str(root.get('event'));

        // Zoom's URL validation challenge: prove we hold the secret by returning HMAC(plainToken).
        if (event == EVENT_URL_VALIDATION) {
            Map<String, Object> payload = ZoomEventService.asMap(root.get('payload'));
            String plainToken = payload == null ? null : ZoomEventService.str(payload.get('plainToken'));
            if (plainToken == null) {
                respond(response, HTTP_BAD_REQUEST, '{"error":"plainToken missing"}');
                return;
            }
            respond(response, HTTP_OK, JSON.serialize(new Map<String, String>{
                'plainToken' => plainToken, 'encryptedToken' => hmac(plainToken, secret) }));
            return;
        }

        String timestamp = request.headers.get(HEADER_TIMESTAMP);
        String signature = request.headers.get(HEADER_SIGNATURE);
        if (timestamp == null || signature == null
            || signature != SIGNATURE_VERSION + '=' + hmac(SIGNATURE_VERSION + ':' + timestamp + ':' + body, secret)) {
            respond(response, HTTP_UNAUTHORIZED, '{"error":"invalid signature"}');
            return;
        }

        if (!FeatureFlagService.isEnabled(FLAG_INTEGRATION)) {
            respond(response, HTTP_OK, '{"status":"ignored","reason":"integration disabled"}');
            return;
        }

        Savepoint beforeProcessing = Database.setSavepoint();
        try {
            ZoomEventService.process(body);
            respond(response, HTTP_OK, '{"status":"ok"}');
        } catch (Exception e) {
            // Every failure must roll back partial work, be logged with full context, and return 500 so Zoom retries.
            Database.rollback(beforeProcessing);
            ZoomLogger.logFailure(LOG_NAME, CLASS_NAME, event, e);
            respond(response, HTTP_SERVER_ERROR, '{"error":"processing failed"}');
        }
    }

    @TestVisible
    private static String hmac(String data, String secret) {
        return EncodingUtil.convertToHex(Crypto.generateMac(HMAC_ALGORITHM, Blob.valueOf(data), Blob.valueOf(secret)));
    }

    private static void respond(RestResponse response, Integer statusCode, String body) {
        response.statusCode = statusCode;
        response.responseBody = Blob.valueOf(body);
    }
}