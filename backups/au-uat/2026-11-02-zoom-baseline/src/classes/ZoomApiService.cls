/** Zoom REST API access using a Server-to-Server OAuth app (account_credentials grant). */
public with sharing class ZoomApiService {
    private static String token;

    private static String accessToken() {
        if (token != null) { return token; }
        Zoom_Config__mdt c = ZoomConfig.get();
        if (String.isBlank(c.Account_Id__c) || String.isBlank(c.Client_Id__c) || String.isBlank(c.Client_Secret__c)) {
            throw new CalloutException('Zoom API credentials are not configured in Custom Metadata Zoom_Config.Default');
        }
        HttpRequest r = new HttpRequest();
        r.setEndpoint('https://zoom.us/oauth/token?grant_type=account_credentials&account_id=' + EncodingUtil.urlEncode(c.Account_Id__c, 'UTF-8'));
        r.setMethod('POST');
        r.setHeader('Authorization', 'Basic ' + EncodingUtil.base64Encode(Blob.valueOf(c.Client_Id__c + ':' + c.Client_Secret__c)));
        HttpResponse resp = new Http().send(r);
        if (resp.getStatusCode() != 200) { throw new CalloutException('Zoom token error ' + resp.getStatusCode() + ': ' + resp.getBody()); }
        token = (String) ((Map<String, Object>) JSON.deserializeUntyped(resp.getBody())).get('access_token');
        return token;
    }

    public static Map<String, Object> get(String pathAndQuery) {
        HttpRequest r = new HttpRequest();
        r.setEndpoint('https://api.zoom.us/v2' + pathAndQuery);
        r.setMethod('GET');
        r.setHeader('Authorization', 'Bearer ' + accessToken());
        HttpResponse resp = new Http().send(r);
        if (resp.getStatusCode() == 404) { return new Map<String, Object>(); }
        if (resp.getStatusCode() >= 300) { throw new CalloutException('Zoom API ' + pathAndQuery + ' -> ' + resp.getStatusCode() + ': ' + resp.getBody()); }
        return (Map<String, Object>) JSON.deserializeUntyped(resp.getBody());
    }

    /** Follows next_page_token and returns every item under listKey. */
    public static List<Object> getAll(String path, String query, String listKey) {
        List<Object> all = new List<Object>();
        String next = null;
        Integer guard = 0;
        do {
            Map<String, Object> page = get(path + '?page_size=300' + (query == null ? '' : '&' + query)
                + (next == null ? '' : '&next_page_token=' + EncodingUtil.urlEncode(next, 'UTF-8')));
            List<Object> items = (List<Object>) page.get(listKey);
            if (items != null) { all.addAll(items); }
            next = ZoomEventService.str(page.get('next_page_token'));
            guard++;
        } while (next != null && guard < 20);
        return all;
    }
}