/**
 * @description Tests WaGraphClient: Graph version validation, Meta error mapping (token, permission,
 *              rate limit, server error, error_user_msg vs message fallback), callout exceptions and the
 *              callout time budget.
 * @author AU Development Team
 * @date 2026-11-26
 * @version 1.0
 * @lastModified 2026-11-27
 */
@IsTest
private class WaGraphClientTest {
    @IsTest
    static void versionPathComesFromSettings() {
        WaTestSupport.configure();

        Assert.areEqual('/v27.0', WaGraphClient.versionPath(), 'Version should come from WA_Setting__mdt');

        WaConfigSelector.settingOverride = new WA_Setting__mdt(Graph_Version__c = 'latest');
        try {
            WaGraphClient.versionPath();
            Assert.fail('An invalid version must be rejected');
        } catch (WaException caught) {
            Assert.areEqual(503, caught.statusCode, 'Invalid version is a configuration error');
        }
    }

    @IsTest
    static void metaErrorsAreMappedToReadableMessages() {
        WaException token = WaGraphClient.toMetaError('GET x', 400, error(190, 'Invalid OAuth access token', null));
        WaException permission = WaGraphClient.toMetaError('GET x', 403, error(200, 'Permissions error', null));
        WaException rateLimit = WaGraphClient.toMetaError('GET x', 400, error(80008, 'Too many calls', null));
        WaException server = WaGraphClient.toMetaError('GET x', 500, error(1, 'Unknown error', null));
        WaException userMessage = WaGraphClient.toMetaError('GET x', 400, error(100, 'Invalid parameter', 'Body has too many variables'));
        WaException fallback = WaGraphClient.toMetaError('GET x', 400, error(100, 'Invalid parameter', null));
        WaException empty = WaGraphClient.toMetaError('GET x', 404, new Map<String, Object>());

        Assert.areEqual(WaException.HTTP_UPSTREAM_FAILED, token.statusCode, 'Bad token is a server-side configuration problem');
        Assert.isTrue(token.getMessage().contains('Meta_WhatsApp'), 'Token message should say where to fix it');
        Assert.isTrue(permission.getMessage().contains('Messaging account'), 'Permission message should mention the WABA assignment');
        Assert.areEqual(WaException.HTTP_TRY_LATER, rateLimit.statusCode, 'Rate limits should be 503 (Apex REST cannot return 429)');
        Assert.areEqual(WaException.HTTP_UPSTREAM_FAILED, server.statusCode, 'Meta 5xx should be 500 (Apex REST cannot return 502)');
        Assert.areEqual('Body has too many variables', userMessage.getMessage(), 'error_user_msg wins');
        Assert.areEqual('Invalid parameter', fallback.getMessage(), 'message is the fallback');
        Assert.areEqual('Meta returned HTTP 404.', empty.getMessage(), 'Empty error body still gives a message');
        Assert.isTrue(fallback.logFailure, 'Meta failures are logged');
    }

    @IsTest
    static void calloutExceptionsAreMapped() {
        WaTestSupport.configure();
        Test.setMock(HttpCalloutMock.class, new WaGraphMock()
            .fail('GET', 'timeout', 'Read timed out')
            .fail('GET', 'credential', 'We could not find the named credential principal')
            .fail('GET', 'other', 'Unable to tunnel through proxy'));

        Assert.areEqual(WaException.HTTP_TRY_LATER, capture('/timeout').statusCode, 'Timeout should be 503 (Apex REST cannot return 504)');
        WaException credential = capture('/credential');
        Assert.areEqual(WaException.HTTP_UPSTREAM_FAILED, credential.statusCode, 'Credential problem should be 500');
        Assert.isTrue(credential.getMessage().contains('External Credential'), 'Should point to the External Credential');
        Assert.areEqual(WaException.HTTP_UPSTREAM_FAILED, capture('/other').statusCode, 'Other callout failures should be 500');
    }

    @IsTest
    static void timeBudgetStopsFurtherCalls() {
        WaTestSupport.configure();
        Test.setMock(HttpCalloutMock.class, new WaGraphMock().route('GET', 'x', 200, '{}'));
        WaGraphClient.spentMs = WaGraphClient.MAX_TOTAL_CALLOUT_MS;

        Assert.isFalse(WaGraphClient.canCallAgain(), 'No call should start when the budget is used up');
        Assert.areEqual(WaException.HTTP_TRY_LATER, capture('/x').statusCode, 'A call past the budget should fail fast');
    }

    @IsTest
    static void successfulCallParsesBodyAndToleratesNonJson() {
        WaTestSupport.configure();
        Test.setMock(HttpCalloutMock.class, new WaGraphMock()
            .route('GET', '/json', 200, '{"id":"1"}')
            .route('GET', '/html', 200, '<html></html>')
            .route('GET', '/array', 200, '[1]'));

        Assert.areEqual('1', WaGraphClient.get('/json', 1000).get('id'), 'JSON body should be parsed');
        Assert.isTrue(WaGraphClient.get('/html', 1000).isEmpty(), 'Non-JSON body should become an empty map');
        Assert.isTrue(WaGraphClient.get('/array', 1000).isEmpty(), 'Non-object JSON should become an empty map');
    }

    private static Map<String, Object> error(Integer code, String message, String userMessage) {
        Map<String, Object> details = new Map<String, Object>{ 'code' => code, 'message' => message };
        if (userMessage != null) {
            details.put('error_user_msg', userMessage);
        }
        return new Map<String, Object>{ 'error' => details };
    }

    private static WaException capture(String path) {
        try {
            WaGraphClient.get(path, 1000);
        } catch (WaException caught) {
            return caught;
        }
        Assert.fail('Expected WaException for ' + path);
        return null;
    }
}