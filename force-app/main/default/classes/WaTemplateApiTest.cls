/**
 * @description Tests WaTemplateApi end to end through RestContext: authentication, routing, every action,
 *              response shape and HTTP status codes. Callouts are mocked with WaGraphMock.
 * @author AU Development Team
 * @date 2026-11-26
 * @version 1.0
 * @lastModified 2026-11-26
 */
@IsTest
private class WaTemplateApiTest {
    private static Map<String, String> params(String action) {
        return new Map<String, String>{ 'action' => action };
    }

    @IsTest
    static void wabasReturnsActiveAccountsSorted() {
        WaTestSupport.configure();
        WaTestSupport.request('GET', params('wabas'), null);

        Test.startTest();
        WaTemplateApi.handleGet();
        Test.stopTest();

        Map<String, Object> body = WaTestSupport.responseBody();
        List<Object> accounts = (List<Object>) body.get('accounts');
        Assert.areEqual(200, RestContext.response.statusCode, 'wabas should return 200');
        Assert.areEqual(true, body.get('ok'), 'ok should be true');
        Assert.areEqual(2, accounts.size(), 'Only the two active accounts should be returned');
        Assert.areEqual(WaTestSupport.WABA_ACTIVE, ((Map<String, Object>) accounts[0]).get('wabaId'), 'Sort_Order 1 should come first');
    }

    @IsTest
    static void headerNameIsCaseInsensitive() {
        WaTestSupport.configure();
        RestRequest request = WaTestSupport.request('GET', params('wabas'), null);
        request.headers.remove(WaAuthService.HEADER_ADMIN_KEY);
        request.addHeader('x-admin-key', WaTestSupport.ADMIN_KEY);

        WaTemplateApi.handleGet();

        Assert.areEqual(200, RestContext.response.statusCode, 'A lowercase header (HTTP/2) must be accepted');
    }

    @IsTest
    static void missingKeyReturns401() {
        WaTestSupport.configure();
        RestRequest request = WaTestSupport.request('GET', params('wabas'), null);
        request.headers.remove(WaAuthService.HEADER_ADMIN_KEY);

        WaTemplateApi.handleGet();

        Map<String, Object> body = WaTestSupport.responseBody();
        Assert.areEqual(401, RestContext.response.statusCode, 'Missing key should be 401');
        Assert.areEqual(false, body.get('ok'), 'ok should be false');
        Assert.areEqual(WaAuthService.MSG_KEY_MISSING, body.get('error'), 'Should ask for the key');
    }

    @IsTest
    static void wrongKeyReturns401() {
        WaTestSupport.configure();
        RestRequest request = WaTestSupport.request('GET', params('wabas'), null);
        request.headers.put(WaAuthService.HEADER_ADMIN_KEY, 'not-the-key');

        WaTemplateApi.handleGet();

        Assert.areEqual(401, RestContext.response.statusCode, 'Wrong key should be 401');
        Assert.areEqual(WaAuthService.MSG_KEY_WRONG, WaTestSupport.responseBody().get('error'), 'Should say the key is wrong');
    }

    @IsTest
    static void keyNotConfiguredReturns503() {
        WaTestSupport.configure();
        WaConfigSelector.adminKeyOverride = '';
        WaTestSupport.request('GET', params('wabas'), null);

        WaTemplateApi.handleGet();

        Assert.areEqual(503, RestContext.response.statusCode, 'Unset key should be 503');
        Assert.areEqual(WaAuthService.MSG_KEY_NOT_SET, WaTestSupport.responseBody().get('error'), 'Should explain the key is not set up');
    }

    @IsTest
    static void featureFlagOffReturns503() {
        WaTestSupport.configure();
        FeatureFlagService.testOverrides.put(WaAuthService.FEATURE_FLAG, false);
        WaTestSupport.request('GET', params('wabas'), null);

        WaTemplateApi.handleGet();

        Assert.areEqual(503, RestContext.response.statusCode, 'Flag off should be 503');
        Assert.areEqual(WaAuthService.MSG_SWITCHED_OFF, WaTestSupport.responseBody().get('error'), 'Should say the tool is switched off');
    }

    @IsTest
    static void unknownActionReturns400() {
        WaTestSupport.configure();
        WaTestSupport.request('GET', params('delete'), null);

        WaTemplateApi.handleGet();

        Assert.areEqual(400, RestContext.response.statusCode, 'delete is not an action of this API');
    }

    @IsTest
    static void wrongMethodReturns405() {
        WaTestSupport.configure();
        WaTestSupport.request('GET', params('create'), null);

        WaTemplateApi.handleGet();

        Assert.areEqual(405, RestContext.response.statusCode, 'create over GET should be 405');

        WaTestSupport.request('POST', params('list'), null);
        WaTemplateApi.handlePost();
        Assert.areEqual(405, RestContext.response.statusCode, 'list over POST should be 405');
    }

    @IsTest
    static void listReturnsTemplates() {
        WaTestSupport.configure();
        WaGraphMock mock = new WaGraphMock().route('GET', '/message_templates', 200, WaTestSupport.templatePage(0, 3, null));
        Test.setMock(HttpCalloutMock.class, mock);
        WaTestSupport.request('GET', new Map<String, String>{ 'action' => 'list', 'wabaId' => WaTestSupport.WABA_ACTIVE }, null);

        Test.startTest();
        WaTemplateApi.handleGet();
        Test.stopTest();

        Map<String, Object> body = WaTestSupport.responseBody();
        Assert.areEqual(200, RestContext.response.statusCode, 'list should return 200');
        Assert.areEqual(3, ((List<Object>) body.get('templates')).size(), 'All templates should be returned');
        Assert.areEqual(false, body.get('truncated'), 'Single page should not be truncated');
    }

    @IsTest
    static void createReturnsMetaStatusAndLogs() {
        WaTestSupport.grantGuestPermissionSet();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            WaTestSupport.configure();
            WaGraphMock mock = new WaGraphMock()
                .route('POST', '/message_templates', 200, '{"id":"5550001","status":"PENDING","category":"MARKETING"}');
            Test.setMock(HttpCalloutMock.class, mock);
            WaTestSupport.request('POST', new Map<String, String>{ 'action' => 'create', 'wabaId' => WaTestSupport.WABA_ACTIVE }, Blob.valueOf(WaTestSupport.marketingTemplateJson()));

            Test.startTest();
            WaTemplateApi.handlePost();
            Test.stopTest();

            Map<String, Object> body = WaTestSupport.responseBody();
            Assert.areEqual(200, RestContext.response.statusCode, 'create should return 200');
            Assert.areEqual('PENDING', body.get('status'), 'Meta status should be returned');
            Assert.areEqual('5550001', body.get('id'), 'Meta id should be returned');
            List<WA_Template_Log__c> logs = [SELECT Template_Name__c, Language__c, Category__c, Status__c, WABA_Id__c, Action__c FROM WA_Template_Log__c WHERE Meta_Template_Id__c = '5550001'];
            Assert.areEqual(1, logs.size(), 'One create log should be written with the guest permission set');
            Assert.areEqual('admission_open_2027', logs[0].Template_Name__c, 'Log keeps the template name');
            Assert.areEqual('Create', logs[0].Action__c, 'Log action is Create');
            Assert.areEqual(WaTestSupport.WABA_ACTIVE, logs[0].WABA_Id__c, 'Log keeps the WABA ID');
            Assert.areEqual(0, [SELECT COUNT() FROM API_Log__c], 'No failure logged on success');
        }
    }

    @IsTest
    static void createSucceedsEvenIfLogCannotBeWritten() {
        WaTestSupport.configure();
        WaGraphMock mock = new WaGraphMock()
            .route('POST', '/message_templates', 200, '{"id":"5550002","status":"PENDING","category":"UTILITY"}');
        Test.setMock(HttpCalloutMock.class, mock);
        WaTestSupport.request('POST', new Map<String, String>{ 'action' => 'create', 'wabaId' => WaTestSupport.WABA_ACTIVE }, Blob.valueOf(WaTestSupport.marketingTemplateJson()));

        Test.startTest();
        WaTemplateApi.handlePost();
        Test.stopTest();

        // Without the guest permission set the user-mode log insert normally fails (no field access);
        // either way exactly one record must exist: the audit log or the API_Log__c failure entry.
        Assert.areEqual(200, RestContext.response.statusCode, 'The template exists on Meta, so the call must still succeed: ' + RestContext.response.responseBody.toString());
        Integer auditLogs = [SELECT COUNT() FROM WA_Template_Log__c];
        Integer failureLogs = [SELECT COUNT() FROM API_Log__c WHERE Apex_Class_Name__c = 'WaTemplateService'];
        Assert.areEqual(1, auditLogs + failureLogs, 'Either the audit log or its failure must be recorded');
    }

    @IsTest
    static void createMetaErrorIsReturnedAndLogged() {
        WaTestSupport.configure();
        WaGraphMock mock = new WaGraphMock()
            .route('POST', '/message_templates', 400, '{"error":{"message":"Invalid parameter","error_user_msg":"Content in this language already exists","code":100,"error_subcode":2388024}}');
        Test.setMock(HttpCalloutMock.class, mock);
        WaTestSupport.request('POST', new Map<String, String>{ 'action' => 'create', 'wabaId' => WaTestSupport.WABA_ACTIVE }, Blob.valueOf(WaTestSupport.marketingTemplateJson()));

        Test.startTest();
        WaTemplateApi.handlePost();
        Test.stopTest();

        Map<String, Object> body = WaTestSupport.responseBody();
        Assert.areEqual(400, RestContext.response.statusCode, 'Meta 400 should map to 400');
        Assert.areEqual('Content in this language already exists', body.get('error'), 'error_user_msg should be shown');
        Assert.areEqual(0, [SELECT COUNT() FROM WA_Template_Log__c], 'No create log on failure');
        Assert.areEqual(1, [SELECT COUNT() FROM API_Log__c WHERE Apex_Class_Name__c = 'WaTemplateApi'], 'Meta failure should be written to API_Log__c');
    }

    @IsTest
    static void validationErrorIsNotLoggedAndMakesNoCallout() {
        WaTestSupport.configure();
        WaGraphMock mock = new WaGraphMock();
        Test.setMock(HttpCalloutMock.class, mock);
        WaTestSupport.request('POST', new Map<String, String>{ 'action' => 'create', 'wabaId' => WaTestSupport.WABA_ACTIVE }, Blob.valueOf('{"name":"Bad Name","language":"en_US","category":"UTILITY","components":[{"type":"BODY","text":"Hello"}]}'));

        WaTemplateApi.handlePost();

        Assert.areEqual(400, RestContext.response.statusCode, 'Validation errors should be 400');
        Assert.areEqual(0, mock.requests.size(), 'Invalid templates must never reach Meta');
        Assert.areEqual(0, [SELECT COUNT() FROM API_Log__c], 'User validation errors are not system failures');
    }

    @IsTest
    static void uploadReturnsHeaderHandle() {
        WaTestSupport.configure();
        WaGraphMock mock = new WaGraphMock()
            .route('POST', '/uploads?', 200, '{"id":"upload:MTphdHRhY2htZW50?sig=ARZabc"}')
            .route('POST', '/upload:', 200, '{"h":"4::aW1hZ2UvcG5n:ARhandle"}');
        Test.setMock(HttpCalloutMock.class, mock);
        WaTestSupport.request('POST', new Map<String, String>{ 'action' => 'upload', 'fileName' => 'banner.png', 'fileType' => 'image/png' }, Blob.valueOf('PNGDATA'));

        Test.startTest();
        WaTemplateApi.handlePost();
        Test.stopTest();

        Map<String, Object> body = WaTestSupport.responseBody();
        Assert.areEqual(200, RestContext.response.statusCode, 'upload should return 200');
        Assert.areEqual('4::aW1hZ2UvcG5n:ARhandle', body.get('header_handle'), 'Handle from Meta should be returned');
    }

    @IsTest
    static void responsesAreNotCached() {
        WaTestSupport.configure();
        WaTestSupport.request('GET', params('wabas'), null);

        WaTemplateApi.handleGet();

        Assert.areEqual('no-store', RestContext.response.headers.get('Cache-Control'), 'API responses must not be cached');
    }
}