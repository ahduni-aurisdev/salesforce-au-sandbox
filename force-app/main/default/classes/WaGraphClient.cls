/**
 * @description Callouts to the Meta Graph API through Named Credential Meta_Graph. The token is never in code:
 *              the Authorization header is a merge formula resolved by Salesforce from External Credential
 *              Meta_WhatsApp ("Bearer" for normal calls, "OAuth" for the Resumable Upload data call, as Meta
 *              requires). The Graph version comes only from WA_Setting__mdt.
 *              Governor limits: tracks total callout time so one transaction stays under the 120 s limit, and
 *              checks the callout count before each call. Meta errors are turned into user-readable messages
 *              using error_user_msg (fallback: message).
 * @author AU Development Team
 * @date 2026-11-26
 * @version 1.0
 * @lastModified 2026-11-27
 */
public with sharing class WaGraphClient {
    public static final String NAMED_CREDENTIAL = 'callout:Meta_Graph';
    @TestVisible
    private static final String AUTH_BEARER = 'Bearer {!$Credential.Meta_WhatsApp.token}';
    @TestVisible
    private static final String AUTH_OAUTH = 'OAuth {!$Credential.Meta_WhatsApp.token}';
    private static final String HEADER_AUTHORIZATION = 'Authorization';
    private static final String HEADER_CONTENT_TYPE = 'Content-Type';
    private static final String HEADER_FILE_OFFSET = 'file_offset';
    private static final String CONTENT_TYPE_JSON = 'application/json';
    private static final String METHOD_GET = 'GET';
    private static final String METHOD_POST = 'POST';
    private static final Pattern GRAPH_VERSION_PATTERN = Pattern.compile('^v\\d{1,3}\\.\\d{1,2}$');

    /** Total callout time allowed per transaction; Salesforce's hard limit is 120 000 ms. */
    @TestVisible
    private static final Integer MAX_TOTAL_CALLOUT_MS = 110000;
    /** A call is not started if less than this is left in the budget. */
    @TestVisible
    private static final Integer MIN_CALLOUT_MS = 5000;

    private static final Integer META_CODE_TOKEN = 190;
    private static final Set<Integer> META_CODES_PERMISSION = new Set<Integer>{ 10, 200 };
    private static final Set<Integer> META_CODES_RATE_LIMIT = new Set<Integer>{ 4, 17, 32, 613, 80008 };

    @TestVisible
    private static Long spentMs = 0;

    /**
     * @description Returns "/vNN.N" from WA_Setting__mdt, validated.
     * @return the version path segment
     */
    public static String versionPath() {
        WA_Setting__mdt setting = WaConfigSelector.getSetting();
        String version = setting == null ? null : setting.Graph_Version__c;
        if (String.isBlank(version) || !GRAPH_VERSION_PATTERN.matcher(version.trim()).matches()) {
            throw WaException.logged(503, 'The Meta Graph version is missing or invalid in WA Setting (Default). Ask your Salesforce admin to set it, e.g. v27.0.', 'Graph_Version__c=' + version);
        }
        return '/' + version.trim();
    }

    /**
     * @description True when another call can start: callout count and time budget both have room.
     * @return whether another call can start
     */
    public static Boolean canCallAgain() {
        return (MAX_TOTAL_CALLOUT_MS - spentMs) >= MIN_CALLOUT_MS && Limits.getCallouts() < Limits.getLimitCallouts();
    }

    /**
     * @description GET with Bearer auth.
     * @param pathAndQuery path after the host, starting with the version, query already encoded
     * @param timeoutMs timeout for this call
     * @return parsed JSON body
     */
    public static Map<String, Object> get(String pathAndQuery, Integer timeoutMs) {
        HttpRequest request = newRequest(METHOD_GET, pathAndQuery, AUTH_BEARER);
        return send(request, timeoutMs);
    }

    /**
     * @description POST a JSON body with Bearer auth.
     * @param path path after the host, starting with the version
     * @param jsonBody serialized JSON
     * @param timeoutMs timeout for this call
     * @return parsed JSON body
     */
    public static Map<String, Object> postJson(String path, String jsonBody, Integer timeoutMs) {
        HttpRequest request = newRequest(METHOD_POST, path, AUTH_BEARER);
        request.setHeader(HEADER_CONTENT_TYPE, CONTENT_TYPE_JSON);
        request.setBody(jsonBody);
        return send(request, timeoutMs);
    }

    /**
     * @description POST with no body and Bearer auth (Resumable Upload step 1: start session).
     * @param pathAndQuery path and encoded query
     * @param timeoutMs timeout for this call
     * @return parsed JSON body
     */
    public static Map<String, Object> postEmpty(String pathAndQuery, Integer timeoutMs) {
        HttpRequest request = newRequest(METHOD_POST, pathAndQuery, AUTH_BEARER);
        request.setBody('');
        return send(request, timeoutMs);
    }

    /**
     * @description POST raw bytes with OAuth auth and file_offset 0 (Resumable Upload step 2).
     * @param path version + upload session id ("upload:...?sig=...")
     * @param body file bytes
     * @param timeoutMs timeout for this call
     * @return parsed JSON body
     */
    public static Map<String, Object> postFile(String path, Blob body, Integer timeoutMs) {
        HttpRequest request = newRequest(METHOD_POST, path, AUTH_OAUTH);
        request.setHeader(HEADER_FILE_OFFSET, '0');
        request.setBodyAsBlob(body);
        return send(request, timeoutMs);
    }

    private static HttpRequest newRequest(String method, String pathAndQuery, String authorization) {
        HttpRequest request = new HttpRequest();
        request.setMethod(method);
        request.setEndpoint(NAMED_CREDENTIAL + pathAndQuery);
        request.setHeader(HEADER_AUTHORIZATION, authorization);
        return request;
    }

    private static Map<String, Object> send(HttpRequest request, Integer timeoutMs) {
        String operation = request.getMethod() + ' ' + stripQuery(request.getEndpoint());
        if (Limits.getCallouts() >= Limits.getLimitCallouts()) {
            throw WaException.logged(503, 'Too many calls to Meta in one request. Try again.', operation + ': callout limit reached');
        }
        Long remaining = MAX_TOTAL_CALLOUT_MS - spentMs;
        if (remaining < MIN_CALLOUT_MS) {
            throw WaException.logged(WaException.HTTP_TRY_LATER, 'Meta is taking too long to respond. Try again in a minute.', operation + ': callout time budget used up');
        }
        request.setTimeout(Math.min((Long) timeoutMs, remaining).intValue());

        HttpResponse response;
        Long startedAt = System.currentTimeMillis();
        try {
            response = new Http().send(request);
        } catch (CalloutException calloutError) {
            throw toCalloutError(operation, calloutError);
        } finally {
            spentMs += System.currentTimeMillis() - startedAt;
        }

        Map<String, Object> body = parseBody(response.getBody());
        Integer status = response.getStatusCode();
        if (status >= 200 && status < 300) {
            return body;
        }
        throw toMetaError(operation, status, body);
    }

    private static WaException toCalloutError(String operation, CalloutException calloutError) {
        String detail = operation + ': ' + calloutError.getMessage();
        String lower = calloutError.getMessage() == null ? '' : calloutError.getMessage().toLowerCase();
        if (lower.contains('timed out')) {
            return WaException.logged(WaException.HTTP_TRY_LATER, 'Meta did not respond in time. Try again in a minute.', detail);
        }
        if (lower.contains('credential')) {
            return WaException.logged(WaException.HTTP_UPSTREAM_FAILED, 'Salesforce could not read the Meta token. Ask your Salesforce admin to check External Credential Meta_WhatsApp (principal Default, parameter token) and the guest user\'s principal access.', detail);
        }
        return WaException.logged(WaException.HTTP_UPSTREAM_FAILED, 'Could not reach Meta. Try again in a minute.', detail);
    }

    @TestVisible
    private static WaException toMetaError(String operation, Integer status, Map<String, Object> body) {
        Map<String, Object> error = body.get('error') instanceof Map<String, Object> ? (Map<String, Object>) body.get('error') : new Map<String, Object>();
        String userMessage = asString(error.get('error_user_msg'));
        String message = String.isNotBlank(userMessage) ? userMessage : asString(error.get('message'));
        if (String.isBlank(message)) {
            message = 'Meta returned HTTP ' + status + '.';
        }
        Integer code = error.get('code') instanceof Integer ? (Integer) error.get('code') : null;
        String detail = operation + ': HTTP ' + status + ' code=' + code + ' subcode=' + error.get('error_subcode') + ' ' + asString(error.get('message'));

        if (code == META_CODE_TOKEN || status == 401) {
            return WaException.logged(WaException.HTTP_UPSTREAM_FAILED, 'Meta rejected the access token. Ask your Salesforce admin to update the token in External Credential Meta_WhatsApp.', detail);
        }
        if (META_CODES_PERMISSION.contains(code)) {
            return WaException.logged(WaException.HTTP_UPSTREAM_FAILED, 'Meta denied access to this WhatsApp account. In Meta Business Settings, assign the system user to the Messaging account (WABA) with Full control. Meta said: ' + message, detail);
        }
        if (META_CODES_RATE_LIMIT.contains(code) || status == 429) {
            return WaException.logged(WaException.HTTP_TRY_LATER, 'Meta rate limit reached. Wait a while and try again. Meta said: ' + message, detail);
        }
        if (status >= 500) {
            return WaException.logged(WaException.HTTP_UPSTREAM_FAILED, 'Meta is having a problem right now. Try again in a minute. Meta said: ' + message, detail);
        }
        return WaException.logged(400, message, detail);
    }

    private static Map<String, Object> parseBody(String body) {
        if (String.isBlank(body)) {
            return new Map<String, Object>();
        }
        try {
            Object parsed = JSON.deserializeUntyped(body);
            return parsed instanceof Map<String, Object> ? (Map<String, Object>) parsed : new Map<String, Object>();
        } catch (JSONException parseError) {
            return new Map<String, Object>();
        }
    }

    private static String stripQuery(String endpoint) {
        Integer queryStart = endpoint.indexOf('?');
        return queryStart < 0 ? endpoint : endpoint.substring(0, queryStart);
    }

    private static String asString(Object value) {
        return value == null ? null : String.valueOf(value);
    }
}