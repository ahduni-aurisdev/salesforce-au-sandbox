/**
 * @description Tests WaAuthService: feature flag, admin key checks, case-insensitive headers and the
 *              constant-time key comparison.
 * @author AU Development Team
 * @date 2026-11-26
 * @version 1.0
 * @lastModified 2026-11-26
 */
@IsTest
private class WaAuthServiceTest {
    @IsTest
    static void correctKeyIsAccepted() {
        WaTestSupport.configure();
        RestRequest request = new RestRequest();
        request.addHeader('X-ADMIN-KEY', WaTestSupport.ADMIN_KEY);

        WaAuthService.authorize(request);

        Assert.areEqual(WaTestSupport.ADMIN_KEY, WaAuthService.getHeader(request, 'x-admin-key'), 'Header lookup should ignore case');
    }

    @IsTest
    static void rejectsWithCorrectStatus() {
        WaTestSupport.configure();
        RestRequest noKey = new RestRequest();
        RestRequest wrongKey = new RestRequest();
        wrongKey.addHeader('x-admin-key', WaTestSupport.ADMIN_KEY + 'x');

        Assert.areEqual(401, capture(noKey).statusCode, 'Missing key');
        Assert.areEqual(401, capture(wrongKey).statusCode, 'Wrong key');
        Assert.areEqual(401, capture(null).statusCode, 'No request at all');

        WaConfigSelector.adminKeyOverride = '  ';
        Assert.areEqual(503, capture(wrongKey).statusCode, 'Blank configured key');

        FeatureFlagService.testOverrides.put(WaAuthService.FEATURE_FLAG, false);
        Assert.areEqual(503, capture(wrongKey).statusCode, 'Feature switched off');
    }

    @IsTest
    static void keyComparisonIsExact() {
        Assert.isTrue(WaAuthService.keysMatch('Abc-123', 'Abc-123'), 'Same key matches');
        Assert.isFalse(WaAuthService.keysMatch('abc-123', 'Abc-123'), 'Keys are case-sensitive');
        Assert.isFalse(WaAuthService.keysMatch('Abc-123 ', 'Abc-123'), 'Whitespace matters');
        Assert.isNull(WaAuthService.getHeader(new RestRequest(), null), 'Blank header name returns null');
    }

    private static WaException capture(RestRequest request) {
        try {
            WaAuthService.authorize(request);
        } catch (WaException caught) {
            return caught;
        }
        Assert.fail('Expected WaException');
        return null;
    }
}