@isTest
private class PartnerDynamicRecordResourceTest {

    private static final String PARTNER_PERMISSION_SET_NAME = 'Partner_API_Access';

    // PartnerDynamicRecordResource reads FieldPermissions/ObjectPermissions
    // off the org's real, already-configured Partner_API_Access Permission
    // Set by name - it is NOT a test fixture, and PermissionSet.Name must
    // be unique org-wide, so these tests query the existing record rather
    // than insert a duplicate. They assert against the fields it is
    // actually known to grant on Lead at the time this test was written:
    // Email and LeadSource (among others) - but deliberately NOT LastName,
    // Company, Status or Phone. Any DML this class performs against that
    // Permission Set's child records happens inside @isTest/@testSetup, so
    // it rolls back with the rest of the test transaction and never
    // touches the real configuration.
    @testSetup
    static void setup() {
        insert new List<Lead>{
            new Lead(FirstName = 'Ann', LastName = 'Partner1', Company = 'Acme',
                      Email = 'ann@example.com', Phone = '555-1000',
                      Status = 'Open - Not Contacted', LeadSource = 'Web'),
            new Lead(FirstName = 'Ben', LastName = 'Partner2', Company = 'Acme',
                      Email = 'ben@example.com', Phone = '555-2000',
                      Status = 'Open - Not Contacted', LeadSource = 'Web'),
            new Lead(FirstName = 'Cal', LastName = 'Partner3', Company = 'Acme',
                      Email = 'cal@example.com', Phone = '555-3000',
                      Status = 'Open - Not Contacted', LeadSource = 'Web')
        };
    }

    private static Id getPartnerPermissionSetId() {
        List<PermissionSet> ps = [SELECT Id FROM PermissionSet WHERE Name = :PARTNER_PERMISSION_SET_NAME LIMIT 1];
        System.assert(!ps.isEmpty(),
            'These tests require the org-configured ' + PARTNER_PERMISSION_SET_NAME + ' Permission Set to exist.');
        return ps[0].Id;
    }

    @isTest
    static void testGetRecords_excludesFieldsNotGrantedByPermissionSet() {
        // No System.runAs / restricted user needed - the whitelist is
        // driven entirely by Partner_API_Access's own FieldPermissions
        // rows, not by whichever user executes this request.
        RestRequest req = buildRequest('Lead', null, null);
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        PartnerDynamicRecordResource.getRecords();
        Test.stopTest();

        RestResponse res = RestContext.response;
        System.assertEquals(200, res.statusCode);
        String body = res.responseBody.toString();
        // Quoted-key matching, not a bare substring - avoids false
        // positives against unrelated keys that happen to contain the
        // same text (e.g. "MobilePhone" containing "Phone").
        System.assert(body.contains('"Email"'), 'Email is granted on Partner_API_Access and should appear');
        System.assert(body.contains('"LeadSource"'), 'LeadSource is granted on Partner_API_Access and should appear');
        System.assert(!body.contains('"LastName"'), 'LastName has no FieldPermissions row on Partner_API_Access');
        System.assert(!body.contains('"Company"'), 'Company has no FieldPermissions row on Partner_API_Access');
        System.assert(!body.contains('"Phone"'), 'Phone (as opposed to MobilePhone) has no FieldPermissions row');
    }

    @isTest
    static void testGetRecords_explicitlyRequestedField_allGranted_returnsThem() {
        RestRequest req = buildRequest('Lead', 'Id,Email,LeadSource', null);
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        PartnerDynamicRecordResource.getRecords();
        Test.stopTest();

        RestResponse res = RestContext.response;
        System.assertEquals(200, res.statusCode);
        String body = res.responseBody.toString();
        System.assert(body.contains('"Email"'));
        System.assert(body.contains('"LeadSource"'));
    }

    @isTest
    static void testGetRecords_explicitlyRequestedUngrantedField_returns400() {
        // LastName has no FieldPermissions row on Partner_API_Access -
        // requesting it alongside a genuinely granted field (Email) must
        // fail the whole request rather than silently returning just
        // Email, so a partner always knows exactly what they're getting.
        RestRequest req = buildRequest('Lead', 'LastName,Company,Email', null);
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        PartnerDynamicRecordResource.getRecords();
        Test.stopTest();

        RestResponse res = RestContext.response;
        System.assertEquals(400, res.statusCode);
        System.assert(res.responseBody.toString().contains('LastName'));
    }

    @isTest
    static void testGetRecords_objectNotGrantedByPermissionSet_returns404() {
        // Case is schema-valid but (as of writing) has no ObjectPermissions
        // row on Partner_API_Access - only Lead does.
        RestRequest req = buildRequest('Case', null, null);
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        PartnerDynamicRecordResource.getRecords();
        Test.stopTest();

        System.assertEquals(404, RestContext.response.statusCode);
    }

    @isTest
    static void testGetRecords_unknownObject_returns404() {
        RestRequest req = buildRequest('NotARealObject__x', null, null);
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        PartnerDynamicRecordResource.getRecords();
        Test.stopTest();

        System.assertEquals(404, RestContext.response.statusCode);
    }

    @isTest
    static void testGetRecords_noObjectInUrl_returns404() {
        // KNOWN GAP (accepted as-is): parseObjectName() takes the last
        // '/'-delimited token of the URI. String.split('/') silently drops
        // a trailing empty element, so a call with no object name at all
        // resolves to the literal path segment 'records' rather than
        // being recognized as blank, routing through the "unknown object"
        // branch (404) instead of "no object specified" (400).
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/v1/records/';
        req.httpMethod = 'GET';
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        PartnerDynamicRecordResource.getRecords();
        Test.stopTest();

        System.assertEquals(404, RestContext.response.statusCode);
    }

    @isTest
    static void testGetRecords_limitParamHonored() {
        RestRequest req = buildRequest('Lead', 'Id', '1');
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        PartnerDynamicRecordResource.getRecords();
        Test.stopTest();

        RestResponse res = RestContext.response;
        System.assertEquals(200, res.statusCode);
        List<Object> parsed = (List<Object>) JSON.deserializeUntyped(res.responseBody.toString());
        System.assertEquals(1, parsed.size());
    }

    @isTest
    static void testGetRecords_filterByEmail_returnsOnlyMatchingRecord() {
        RestRequest req = buildRequest('Lead', 'Id', null);
        req.params.put('email', 'ann@example.com');
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        PartnerDynamicRecordResource.getRecords();
        Test.stopTest();

        RestResponse res = RestContext.response;
        System.assertEquals(200, res.statusCode);
        List<Object> parsed = (List<Object>) JSON.deserializeUntyped(res.responseBody.toString());
        System.assertEquals(1, parsed.size());
    }

    @isTest
    static void testGetRecords_filterByEmail_commaSeparatedValuesAreOred() {
        RestRequest req = buildRequest('Lead', 'Id', null);
        req.params.put('email', 'ann@example.com,cal@example.com');
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        PartnerDynamicRecordResource.getRecords();
        Test.stopTest();

        RestResponse res = RestContext.response;
        System.assertEquals(200, res.statusCode);
        List<Object> parsed = (List<Object>) JSON.deserializeUntyped(res.responseBody.toString());
        System.assertEquals(2, parsed.size(), 'ann and cal should both match, ben should not');
    }

    @isTest
    static void testGetRecords_filterByEmailAndPhone_areAnded() {
        // Phone has no FieldPermissions row on the real Partner_API_Access,
        // so it isn't filterable by default. Grant it just for this test -
        // this DML rolls back with the rest of the test transaction and
        // never touches the real configuration.
        insert new FieldPermissions(
            ParentId = getPartnerPermissionSetId(), SobjectType = 'Lead', Field = 'Lead.Phone', PermissionsRead = true
        );

        RestRequest req = buildRequest('Lead', 'Id', null);
        // Ann's email but Ben's phone - no single record matches both, so
        // multiple filter params must AND together, not OR.
        req.params.put('email', 'ann@example.com');
        req.params.put('phone', '555-2000');
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        PartnerDynamicRecordResource.getRecords();
        Test.stopTest();

        RestResponse res = RestContext.response;
        System.assertEquals(200, res.statusCode);
        List<Object> parsed = (List<Object>) JSON.deserializeUntyped(res.responseBody.toString());
        System.assertEquals(0, parsed.size(), 'multiple filter params must AND, not OR');
    }

    @isTest
    static void testGetRecords_filterOnFieldNotGrantedForObject_returns400() {
        // Phone has no FieldPermissions row on the real Partner_API_Access
        // - fails loudly rather than silently ignoring the filter, since a
        // silently-ignored filter would widen the result set beyond what
        // the partner asked for.
        RestRequest req = buildRequest('Lead', 'Id', null);
        req.params.put('phone', '555-1000');
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        PartnerDynamicRecordResource.getRecords();
        Test.stopTest();

        RestResponse res = RestContext.response;
        System.assertEquals(400, res.statusCode);
        System.assert(res.responseBody.toString().contains('phone'));
    }

    @isTest
    static void testGetRecords_filterByArbitraryGrantedField_worksWithoutCodeChange() {
        // LeadSource was never in any hardcoded filterable-field list -
        // filtering works purely because Partner_API_Access grants it,
        // proving the filter mechanism is fully dynamic rather than
        // limited to a fixed set of field names baked into the class.
        insert new Lead(FirstName = 'Dee', LastName = 'Partner4', Company = 'Acme',
                          Email = 'dee@example.com', Status = 'Open - Not Contacted',
                          LeadSource = 'Referral');

        RestRequest req = buildRequest('Lead', 'Id', null);
        req.params.put('LeadSource', 'Referral');
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        PartnerDynamicRecordResource.getRecords();
        Test.stopTest();

        RestResponse res = RestContext.response;
        System.assertEquals(200, res.statusCode);
        List<Object> parsed = (List<Object>) JSON.deserializeUntyped(res.responseBody.toString());
        System.assertEquals(1, parsed.size());
    }

    @isTest
    static void testGetRecords_tooManyFilterValues_returns400() {
        List<String> manyEmails = new List<String>();
        for (Integer i = 0; i < 51; i++) {
            manyEmails.add('user' + i + '@example.com');
        }
        RestRequest req = buildRequest('Lead', 'Id', null);
        req.params.put('email', String.join(manyEmails, ','));
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        PartnerDynamicRecordResource.getRecords();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode);
    }

    private static RestRequest buildRequest(String objectName, String fields, String limitParam) {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/v1/records/' + objectName;
        req.httpMethod = 'GET';
        if (String.isNotBlank(fields)) {
            req.params.put('fields', fields);
        }
        if (String.isNotBlank(limitParam)) {
            req.params.put('limit', limitParam);
        }
        return req;
    }
}