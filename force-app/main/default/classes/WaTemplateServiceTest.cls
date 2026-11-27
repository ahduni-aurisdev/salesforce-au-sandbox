/**
 * @description Tests WaTemplateService: account checks, cursor pagination (never following paging.next),
 *              page cap, the 200-template bulk scenario, create, and the two-step Resumable Upload
 *              (Bearer then OAuth with file_offset 0) including its validation and failure paths.
 * @author AU Development Team
 * @date 2026-11-26
 * @version 1.0
 * @lastModified 2026-11-27
 */
@IsTest
private class WaTemplateServiceTest {
    private static final String BEARER = 'Bearer {!$Credential.Meta_WhatsApp.token}';
    private static final String OAUTH = 'OAuth {!$Credential.Meta_WhatsApp.token}';

    @IsTest
    static void listFollowsCursorAndBuildsOwnUrl() {
        WaTestSupport.configure();
        WaGraphMock mock = new WaGraphMock()
            .route('GET', 'after=CURSOR_2', 200, WaTestSupport.templatePage(100, 100, null))
            .route('GET', '/message_templates', 200, WaTestSupport.templatePage(0, 100, 'CURSOR_2'));
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        WaTemplateModels.TemplatesResponse response = WaTemplateService.listTemplates(WaTestSupport.WABA_ACTIVE);
        Test.stopTest();

        Assert.areEqual(200, response.count, 'Bulk: both pages of 100 should be combined');
        Assert.areEqual(200, response.templates.size(), 'All 200 templates should be mapped');
        Assert.isFalse(response.truncated, 'Should not be truncated when the last page is reached');
        Assert.areEqual(2, mock.requests.size(), 'Two pages means two callouts');
        String secondUrl = mock.requests[1].getEndpoint();
        Assert.isTrue(secondUrl.startsWith('callout:Meta_Graph/v27.0/' + WaTestSupport.WABA_ACTIVE + '/message_templates?fields='), 'Next page must go through the Named Credential: ' + secondUrl);
        Assert.isFalse(secondUrl.contains('SHOULD_NOT_BE_FOLLOWED'), 'paging.next must never be followed');
        Assert.isTrue(secondUrl.contains('limit=100'), 'Page size should be sent');
        Assert.areEqual(BEARER, mock.requests[0].getHeader('Authorization'), 'List calls use Bearer from the External Credential');
        Assert.isNull(response.templates[0].rejected_reason, 'Fields Meta did not send stay null');
        Assert.areEqual('template_0', response.templates[0].name, 'Template fields should be mapped');
    }

    @IsTest
    static void listStopsAtPageCap() {
        WaTestSupport.configure();
        WaGraphMock mock = new WaGraphMock().route('GET', '/message_templates', 200, WaTestSupport.templatePage(0, 2, 'MORE'));
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        WaTemplateModels.TemplatesResponse response = WaTemplateService.listTemplates(WaTestSupport.WABA_ACTIVE);
        Test.stopTest();

        Assert.areEqual(WaTemplateService.MAX_PAGES, mock.requests.size(), 'Paging must stop at the cap');
        Assert.isTrue(response.truncated, 'Response should say the list was cut short');
    }

    @IsTest
    static void listRejectsInactiveAndMalformedAccounts() {
        WaTestSupport.configure();
        WaGraphMock mock = new WaGraphMock();
        Test.setMock(HttpCalloutMock.class, mock);

        WaException inactive = captureList(WaTestSupport.WABA_INACTIVE);
        WaException malformed = captureList('12ab');
        WaException blank = captureList(null);

        Assert.areEqual(403, inactive.statusCode, 'Inactive WABA should be forbidden');
        Assert.areEqual(400, malformed.statusCode, 'Malformed WABA should be a bad request');
        Assert.areEqual(400, blank.statusCode, 'Missing WABA should ask the user to choose a number');
        Assert.areEqual(0, mock.requests.size(), 'No callout for rejected accounts');
    }

    @IsTest
    static void createWithoutMetaIdIsAnError() {
        WaTestSupport.configure();
        Test.setMock(HttpCalloutMock.class, new WaGraphMock().route('POST', '/message_templates', 200, '{}'));
        WaException error;

        Test.startTest();
        try {
            WaTemplateService.createTemplate(WaTestSupport.WABA_ACTIVE, WaTestSupport.marketingTemplateJson());
        } catch (WaException caught) {
            error = caught;
        }
        Test.stopTest();

        Assert.isNotNull(error, 'A missing id must not be reported as success');
        Assert.areEqual(WaException.HTTP_UPSTREAM_FAILED, error.statusCode, 'Missing id is a Meta failure');
        Assert.isTrue(error.logFailure, 'Missing id should be logged');
    }

    @IsTest
    static void createRejectsUnreadableBody() {
        WaTestSupport.configure();
        Test.setMock(HttpCalloutMock.class, new WaGraphMock());
        List<String> bodies = new List<String>{ null, '', 'not json', '[1,2]' };
        for (String body : bodies) {
            try {
                WaTemplateService.createTemplate(WaTestSupport.WABA_ACTIVE, body);
                Assert.fail('Body should be rejected: ' + body);
            } catch (WaException caught) {
                Assert.areEqual(400, caught.statusCode, 'Unreadable body should be 400: ' + body);
            }
        }
    }

    @IsTest
    static void uploadUsesBearerThenOAuthWithOffset() {
        WaTestSupport.configure();
        WaGraphMock mock = new WaGraphMock()
            .route('POST', '/uploads?', 200, '{"id":"upload:MTphdHRhY2htZW50OmFiYw==?sig=ARZ-x_y"}')
            .route('POST', '/upload:', 200, '{"h":"4::handle"}');
        Test.setMock(HttpCalloutMock.class, mock);
        Blob file = Blob.valueOf('%PDF-1.7 sample');

        Test.startTest();
        WaTemplateModels.UploadResponse response = WaTemplateService.uploadSample(file, 'C:\\Users\\me\\Course Brochure.pdf', 'application/pdf');
        Test.stopTest();

        Assert.areEqual('4::handle', response.header_handle, 'Handle should be returned');
        Assert.areEqual(2, mock.requests.size(), 'Resumable upload is two calls');
        HttpRequest start = mock.requests[0];
        HttpRequest data = mock.requests[1];
        Assert.areEqual(BEARER, start.getHeader('Authorization'), 'Step 1 uses Bearer');
        Assert.isTrue(start.getEndpoint().startsWith('callout:Meta_Graph/v27.0/' + WaTestSupport.APP_ID + '/uploads?file_name=Course+Brochure.pdf'), 'Step 1 URL with sanitised name: ' + start.getEndpoint());
        Assert.isTrue(start.getEndpoint().contains('file_length=' + file.size()), 'Step 1 sends the file length');
        Assert.isTrue(start.getEndpoint().contains('file_type=application%2Fpdf'), 'Step 1 sends the file type');
        Assert.areEqual(OAUTH, data.getHeader('Authorization'), 'Step 2 must use OAuth, not Bearer');
        Assert.areEqual('0', data.getHeader('file_offset'), 'Step 2 sends file_offset 0');
        Assert.areEqual('callout:Meta_Graph/v27.0/upload:MTphdHRhY2htZW50OmFiYw==?sig=ARZ-x_y', data.getEndpoint(), 'Step 2 posts to the session id');
        Assert.areEqual(file.size(), data.getBodyAsBlob().size(), 'Step 2 sends the raw bytes');
    }

    @IsTest
    static void uploadNormalisesJpgType() {
        WaTestSupport.configure();
        WaGraphMock mock = new WaGraphMock()
            .route('POST', '/uploads?', 200, '{"id":"upload:abc"}')
            .route('POST', '/upload:', 200, '{"h":"4::jpg"}');
        Test.setMock(HttpCalloutMock.class, mock);

        WaTemplateService.uploadSample(Blob.valueOf('jpg'), 'photo.JPG', 'image/jpg');

        Assert.isTrue(mock.requests[0].getEndpoint().contains('file_type=image%2Fjpeg'), 'image/jpg should be sent as image/jpeg');
    }

    @IsTest
    static void uploadRejectsBadFiles() {
        WaTestSupport.configure();
        WaTemplateService.maxUploadBytes = 10;
        WaGraphMock mock = new WaGraphMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Assert.areEqual(400, captureUpload(null, 'a.png', 'image/png').statusCode, 'Missing file');
        Assert.areEqual(400, captureUpload(Blob.valueOf(''), 'a.png', 'image/png').statusCode, 'Empty file');
        Assert.areEqual(413, captureUpload(Blob.valueOf('12345678901'), 'a.png', 'image/png').statusCode, 'File over the cap');
        Assert.areEqual(415, captureUpload(Blob.valueOf('gif'), 'a.gif', 'image/gif').statusCode, 'Unsupported type');
        Assert.areEqual(415, captureUpload(Blob.valueOf('png'), 'a.pdf', 'image/png').statusCode, 'Extension must match the type');
        Assert.areEqual(400, captureUpload(Blob.valueOf('png'), '   ', 'image/png').statusCode, 'File name required');
        Assert.areEqual(0, mock.requests.size(), 'Rejected files never reach Meta');
    }

    @IsTest
    static void uploadNeedsAppId() {
        WaTestSupport.configure();
        WaConfigSelector.settingOverride = new WA_Setting__mdt(Graph_Version__c = 'v27.0');
        Test.setMock(HttpCalloutMock.class, new WaGraphMock());

        WaException error = captureUpload(Blob.valueOf('png'), 'a.png', 'image/png');

        Assert.areEqual(503, error.statusCode, 'Missing App ID is a configuration error');
        Assert.isTrue(error.getMessage().contains('App ID'), 'Message should name the missing setting');
    }

    @IsTest
    static void uploadFailsOnUnexpectedMetaReplies() {
        WaTestSupport.configure();
        Test.setMock(HttpCalloutMock.class, new WaGraphMock().route('POST', '/uploads?', 200, '{"id":"weird id with spaces"}'));
        Assert.areEqual(WaException.HTTP_UPSTREAM_FAILED, captureUpload(Blob.valueOf('png'), 'a.png', 'image/png').statusCode, 'Unexpected session id');

        Test.setMock(HttpCalloutMock.class, new WaGraphMock()
            .route('POST', '/uploads?', 200, '{"id":"upload:abc"}')
            .route('POST', '/upload:', 200, '{}'));
        Assert.areEqual(WaException.HTTP_UPSTREAM_FAILED, captureUpload(Blob.valueOf('png'), 'a.png', 'image/png').statusCode, 'Missing handle');
    }

    @IsTest
    static void listAccountsFallsBackToMasterLabel() {
        WaConfigSelector.accountsOverride = new List<WA_Account__mdt>{
            new WA_Account__mdt(WABA_Id__c = ' 444444444 ', MasterLabel = 'Fallback', Active__c = true)
        };

        WaTemplateModels.AccountsResponse response = WaTemplateService.listAccounts();

        Assert.areEqual(1, response.accounts.size(), 'One active account');
        Assert.areEqual('444444444', response.accounts[0].wabaId, 'WABA ID should be trimmed');
        Assert.areEqual('Fallback', response.accounts[0].label, 'Blank display label falls back to the record label');
    }

    private static WaException captureList(String wabaId) {
        try {
            WaTemplateService.listTemplates(wabaId);
        } catch (WaException caught) {
            return caught;
        }
        Assert.fail('Expected WaException for ' + wabaId);
        return null;
    }

    private static WaException captureUpload(Blob body, String fileName, String fileType) {
        try {
            WaTemplateService.uploadSample(body, fileName, fileType);
        } catch (WaException caught) {
            return caught;
        }
        Assert.fail('Expected WaException for ' + fileName);
        return null;
    }
}