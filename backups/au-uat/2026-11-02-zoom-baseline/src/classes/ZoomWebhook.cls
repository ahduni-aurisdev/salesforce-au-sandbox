/**
 * Zoom event subscription endpoint. Expose it through a Salesforce Site (guest user) and register
 * https://<site-domain>/services/apexrest/zoom/webhook in the Zoom Marketplace app (Event Subscriptions).
 * Every call is verified with the Zoom secret token (x-zm-signature header).
 */
@RestResource(urlMapping='/zoom/webhook/*')
global without sharing class ZoomWebhook {

    @HttpPost
    global static void receive() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        String body = req.requestBody == null ? '' : req.requestBody.toString();
        String secret = ZoomConfig.get().Webhook_Secret_Token__c;
        res.addHeader('Content-Type', 'application/json');
        if (String.isBlank(secret)) {
            res.statusCode = 500; res.responseBody = Blob.valueOf('{"error":"secret token not configured"}'); return;
        }
        Map<String, Object> root;
        try { root = (Map<String, Object>) JSON.deserializeUntyped(body); }
        catch (Exception e) { res.statusCode = 400; return; }

        // Zoom's one-time URL validation challenge
        if ('endpoint.url_validation' == (String) root.get('event')) {
            Map<String, Object> p = (Map<String, Object>) root.get('payload');
            String plain = (String) p.get('plainToken');
            res.statusCode = 200;
            res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, String>{
                'plainToken' => plain, 'encryptedToken' => hmac(plain, secret) }));
            return;
        }
        String ts = req.headers.get('x-zm-request-timestamp');
        String sig = req.headers.get('x-zm-signature');
        if (ts == null || sig == null || sig != 'v0=' + hmac('v0:' + ts + ':' + body, secret)) {
            res.statusCode = 401; res.responseBody = Blob.valueOf('{"error":"invalid signature"}'); return;
        }
        try {
            ZoomEventService.process(body);
            res.statusCode = 200; res.responseBody = Blob.valueOf('{"status":"ok"}');
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Zoom event failed: ' + e.getMessage() + ' ' + e.getStackTraceString());
            res.statusCode = 500; res.responseBody = Blob.valueOf('{"error":"processing failed"}'); // Zoom retries
        }
    }

    @TestVisible
    private static String hmac(String data, String secret) {
        return EncodingUtil.convertToHex(Crypto.generateMac('hmacSHA256', Blob.valueOf(data), Blob.valueOf(secret)));
    }
}