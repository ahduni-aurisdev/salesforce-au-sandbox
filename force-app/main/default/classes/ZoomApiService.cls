/**
 * @description Zoom REST API v2 access through a Server-to-Server OAuth app (account_credentials grant).
 *              With FeatureFlag Zoom_Named_Credential enabled, calls go through Named Credentials ZOOM_OAUTH and
 *              ZOOM_API and the client secret never leaves the External Credential; otherwise the client
 *              credentials are read from Zoom_Config__mdt (legacy path kept until the switch-over is validated).
 * @author AU Development Team
 * @date 2026-10-21
 * @version 1.1
 * @lastModified 2026-11-02
 */
public with sharing class ZoomApiService {
    @TestVisible
    private static final Integer TIMEOUT_MS = 30000;
    @TestVisible
    private static final String FLAG_NAMED_CREDENTIAL = 'Zoom_Named_Credential';
    private static final String NAMED_OAUTH_BASE = 'callout:ZOOM_OAUTH';
    private static final String NAMED_API_BASE = 'callout:ZOOM_API';
    private static final String DIRECT_OAUTH_BASE = 'https://zoom.us';
    private static final String DIRECT_API_BASE = 'https://api.zoom.us/v2';
    private static final String TOKEN_PATH = '/oauth/token?grant_type=account_credentials&account_id=';
    private static final String ACCESS_TOKEN_KEY = 'access_token';
    private static final String NEXT_PAGE_KEY = 'next_page_token';
    private static final String UTF8 = 'UTF-8';
    private static final Integer PAGE_SIZE = 300;
    @TestVisible
    private static final Integer MAX_PAGES = 20;
    private static final Integer MAX_ERROR_BODY_LENGTH = 500;
    private static final Integer HTTP_OK = 200;
    private static final Integer HTTP_MULTIPLE_CHOICES = 300;
    private static final Integer HTTP_NOT_FOUND = 404;
    private static final Integer HTTP_TOO_MANY_REQUESTS = 429;
    private static final Integer HTTP_SERVER_ERROR = 500;

    /** Raised for any failed Zoom call. isRetryable is true for rate limits, server errors and timeouts. */
    public class ZoomApiException extends Exception {
        public Integer statusCode;
        public Boolean isRetryable = false;
    }

    private static String token;

    /** GET a Zoom resource. A 404 returns an empty map (the resource does not exist or has no report yet). */
    public static Map<String, Object> get(String pathAndQuery) {
        HttpRequest request = new HttpRequest();
        request.setEndpoint(apiBase() + pathAndQuery);
        request.setMethod('GET');
        request.setTimeout(TIMEOUT_MS);
        request.setHeader('Authorization', 'Bearer ' + accessToken());
        HttpResponse response = send(request, pathAndQuery);
        if (response.getStatusCode() == HTTP_NOT_FOUND) {
            return new Map<String, Object>();
        }
        if (response.getStatusCode() >= HTTP_MULTIPLE_CHOICES) {
            throw failure('Zoom API ' + pathAndQuery, response);
        }
        return parseObject(response.getBody(), pathAndQuery);
    }

    /** Follows next_page_token and returns every item under listKey, up to MAX_PAGES pages of PAGE_SIZE. */
    public static List<Object> getAll(String path, String query, String listKey) {
        List<Object> all = new List<Object>();
        String nextPage = null;
        Integer pages = 0;
        do {
            Map<String, Object> page = get(path + '?page_size=' + PAGE_SIZE
                + (query == null ? '' : '&' + query)
                + (nextPage == null ? '' : '&next_page_token=' + EncodingUtil.urlEncode(nextPage, UTF8)));
            Object items = page.get(listKey);
            if (items instanceof List<Object>) {
                all.addAll((List<Object>) items);
            }
            nextPage = ZoomEventService.str(page.get(NEXT_PAGE_KEY));
            pages++;
        } while (nextPage != null && pages < MAX_PAGES);
        return all;
    }

    private static String accessToken() {
        if (token != null) {
            return token;
        }
        Zoom_Config__mdt config = ZoomConfig.get();
        if (String.isBlank(config.Account_Id__c)) {
            throw new ZoomApiException('Zoom Account ID is not configured in Custom Metadata Zoom_Config.Default');
        }
        Boolean useNamedCredential = FeatureFlagService.isEnabled(FLAG_NAMED_CREDENTIAL);
        HttpRequest request = new HttpRequest();
        request.setEndpoint((useNamedCredential ? NAMED_OAUTH_BASE : DIRECT_OAUTH_BASE)
            + TOKEN_PATH + EncodingUtil.urlEncode(config.Account_Id__c, UTF8));
        request.setMethod('POST');
        request.setTimeout(TIMEOUT_MS);
        if (!useNamedCredential) {
            if (String.isBlank(config.Client_Id__c) || String.isBlank(config.Client_Secret__c)) {
                throw new ZoomApiException('Zoom client credentials are not configured in Custom Metadata Zoom_Config.Default');
            }
            request.setHeader('Authorization', 'Basic '
                + EncodingUtil.base64Encode(Blob.valueOf(config.Client_Id__c + ':' + config.Client_Secret__c)));
        }
        HttpResponse response = send(request, 'oauth/token');
        if (response.getStatusCode() != HTTP_OK) {
            throw failure('Zoom token request', response);
        }
        Object accessToken = parseObject(response.getBody(), 'oauth/token').get(ACCESS_TOKEN_KEY);
        if (!(accessToken instanceof String)) {
            throw new ZoomApiException('Zoom token response did not contain an access_token');
        }
        token = (String) accessToken;
        return token;
    }

    private static String apiBase() {
        return FeatureFlagService.isEnabled(FLAG_NAMED_CREDENTIAL) ? NAMED_API_BASE : DIRECT_API_BASE;
    }

    private static HttpResponse send(HttpRequest request, String operation) {
        try {
            return new Http().send(request);
        } catch (CalloutException e) {
            ZoomApiException timeoutOrNetwork = new ZoomApiException('Zoom callout failed for ' + operation + ': ' + e.getMessage(), e);
            timeoutOrNetwork.isRetryable = true;
            throw timeoutOrNetwork;
        }
    }

    private static Map<String, Object> parseObject(String body, String operation) {
        try {
            return (Map<String, Object>) JSON.deserializeUntyped(body);
        } catch (JSONException e) {
            throw new ZoomApiException('Zoom returned invalid JSON for ' + operation, e);
        } catch (TypeException e) {
            throw new ZoomApiException('Zoom returned an unexpected JSON shape for ' + operation, e);
        }
    }

    private static ZoomApiException failure(String operation, HttpResponse response) {
        Integer status = response.getStatusCode();
        String body = response.getBody() == null ? '' : response.getBody().left(MAX_ERROR_BODY_LENGTH);
        ZoomApiException error = new ZoomApiException(operation + ' -> HTTP ' + status + ': ' + body);
        error.statusCode = status;
        error.isRetryable = status == HTTP_TOO_MANY_REQUESTS || status >= HTTP_SERVER_ERROR;
        return error;
    }
}