/**
 * Public webhook for the ERP: sends one pre-registered group for a lead. No Salesforce login.
 * Exposed through the "UG PreReg Webhook" Salesforce Site (guest user):
 *   POST https://<site-domain>/ugprereg/services/apexrest/ug/preregistration
 * Every call must prove it comes from the ERP with the shared secret (UG_Webhook_Config__mdt):
 *   header  X-Signature: <hex HMAC-SHA256 of the raw request body, key = shared secret>   (preferred)
 *   or      X-Api-Key:   <the shared secret>
 * Body is the same as the authenticated API (UGPreRegistrationRest): one object or a list.
 * HTTP 401 = bad or missing secret, 400 = not JSON, 500 = secret not configured, 200 = processed
 * (read "success" in each result).
 */
@RestResource(urlMapping='/ug/preregistration')
global without sharing class UGPreRegistrationWebhook {

    @HttpPost
    global static void receive() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');
        String body = req.requestBody == null ? '' : req.requestBody.toString();
        String secret = secret();
        if (String.isBlank(secret)) { reply(res, 500, '{"success":false,"message":"Webhook secret is not configured."}'); return; }
        if (!authorised(req, body, secret)) { reply(res, 401, '{"success":false,"message":"Invalid or missing signature."}'); return; }

        List<Map<String, Object>> out = new List<Map<String, Object>>();
        try {
            Object parsed = JSON.deserializeUntyped(body);
            if (parsed instanceof List<Object>) {
                for (Object o : (List<Object>) parsed) out.add(handleOne((Map<String, Object>) o));
            } else if (parsed instanceof Map<String, Object>) {
                out.add(handleOne((Map<String, Object>) parsed));
            } else {
                reply(res, 400, '{"success":false,"message":"Body must be a JSON object or list."}'); return;
            }
        } catch (JSONException e) {
            reply(res, 400, '{"success":false,"message":"Body is not valid JSON."}'); return;
        } catch (Exception e) {
            reply(res, 400, JSON.serialize(new Map<String, Object>{ 'success' => false, 'message' => 'Error: ' + e.getMessage() })); return;
        }
        reply(res, 200, JSON.serialize(out));
    }

    private static Map<String, Object> handleOne(Map<String, Object> p) {
        Savepoint sp = Database.setSavepoint();
        try {
            return LeadConversionService.savePreRegistrationGroup(p);
        } catch (Exception e) {
            Database.rollback(sp);
            return new Map<String, Object>{ 'success' => false, 'leadId' => p.get('leadId'), 'message' => 'Error: ' + e.getMessage() };
        }
    }

    @TestVisible private static String testSecret; // set only by unit tests

    private static String secret() {
        if (Test.isRunningTest() && testSecret != null) return testSecret;
        UG_Webhook_Config__mdt c = UG_Webhook_Config__mdt.getInstance('Default');
        return c == null ? null : c.Shared_Secret__c;
    }

    private static Boolean authorised(RestRequest req, String body, String secret) {
        String sig = header(req, 'x-signature');
        if (String.isNotBlank(sig)) {
            sig = sig.trim().toLowerCase();
            if (sig.startsWith('sha256=')) sig = sig.substring(7);
            return safeEquals(sig, hmac(body, secret));
        }
        String key = header(req, 'x-api-key');
        return String.isNotBlank(key) && safeEquals(key.trim(), secret);
    }

    private static String header(RestRequest req, String name) {
        for (String k : req.headers.keySet()) if (k.equalsIgnoreCase(name)) return req.headers.get(k);
        return null;
    }

    @TestVisible
    private static String hmac(String data, String secret) {
        return EncodingUtil.convertToHex(Crypto.generateMac('hmacSHA256', Blob.valueOf(data), Blob.valueOf(secret)));
    }

    /** Compares without stopping at the first different character. */
    private static Boolean safeEquals(String a, String b) {
        if (a == null || b == null || a.length() != b.length()) return false;
        Integer diff = 0;
        for (Integer i = 0; i < a.length(); i++) diff |= a.charAt(i) ^ b.charAt(i);
        return diff == 0;
    }

    private static void reply(RestResponse res, Integer code, String json) {
        res.statusCode = code;
        res.responseBody = Blob.valueOf(json);
    }
}