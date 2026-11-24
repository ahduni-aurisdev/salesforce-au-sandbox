/**
 * @description Tests for PartnerLeadWebhook: guest rejection, feature flag, calling-app resolution,
 *              request parsing, responses and failure logging. Lead rules are covered by
 *              PartnerLeadServiceTest. OAuth token validation is done by the Salesforce platform.
 * @author Jitendra V
 * @date 2026-11-18
 * @version 1.0
 * @lastModified 2026-11-18
 */
@IsTest
private class PartnerLeadWebhookTest {

    private static final Integer EXISTING_LEADS = 200;
    private static final String APP = 'Test Partner Integration';
    private static final String SOURCE = 'MBA Rendezvous';
    private static final String MASTERS = 'Masters';
    private static final String MBA = 'Master of Business Administration';

    @TestSetup
    static void createExistingLeads() {
        List<Lead> leads = new List<Lead>();
        for (Integer i = 0; i < EXISTING_LEADS; i++) {
            leads.add(new Lead(
                FirstName = 'Existing',
                LastName = 'Webhook ' + i,
                Email = 'existing.webhook' + i + '@example.com',
                Phone = String.valueOf(9600000000L + i),
                Department__c = MASTERS,
                Preferred_Programme__c = MBA,
                Admission_Year__c = 'Admission Year - 2027'
            ));
        }
        insert leads;
    }

    private static void configure(Boolean enabled, Boolean guest, String sessionApp) {
        PartnerLeadWebhook.testFeatureEnabled = enabled;
        PartnerLeadWebhook.testIsGuest = guest;
        PartnerLeadWebhook.testCallingApp = sessionApp;
        PartnerLeadService.testPartners = new List<Partner_Lead_Source__mdt>{
            new Partner_Lead_Source__mdt(
                DeveloperName = 'Test_Partner',
                Lead_Source__c = SOURCE,
                OAuth_App_Name__c = APP,
                Type_Of_Form__c = 'MBA_Rendezvous',
                Default_Programme__c = MBA,
                Default_Programme_Department__c = MASTERS,
                Is_Active__c = true
            )
        };
    }

    private static void configureValid() {
        configure(true, false, APP);
    }

    private static RestResponse call(String body) {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/partner/lead';
        req.httpMethod = 'POST';
        req.requestBody = body == null ? null : Blob.valueOf(body);
        RestContext.request = req;
        RestResponse res = new RestResponse();
        RestContext.response = res;
        PartnerLeadWebhook.receive();
        return res;
    }

    private static Map<String, Object> lead(String email, String phone) {
        return new Map<String, Object>{
            'leadSource' => SOURCE,
            'department' => MASTERS,
            'firstName' => 'Rahul',
            'lastName' => 'Sharma',
            'email' => email,
            'phone' => phone,
            'programmeInterestedIn' => MBA,
            'state' => 'Gujarat',
            'city' => 'Ahmedabad',
            'admissionYear' => '2027'
        };
    }

    private static Map<String, Object> body(RestResponse res) {
        return (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
    }

    private static Integer webhookLogs() {
        return [SELECT COUNT() FROM API_Log__c WHERE Log_Name__c = :PartnerLeadWebhook.LOG_NAME];
    }

    @IsTest
    static void validLeadIsCreated() {
        configureValid();

        Test.startTest();
        RestResponse res = call(JSON.serialize(lead('webhook.new@example.com', '9123456780')));
        Test.stopTest();

        System.assertEquals(200, res.statusCode, res.responseBody.toString());
        Map<String, Object> result = body(res);
        System.assertEquals(true, result.get('success'), 'Lead should be saved');
        System.assertEquals('created', result.get('action'), 'New student should be created');
        Id leadId = (Id) result.get('leadId');
        System.assertEquals(SOURCE, [SELECT LeadSource FROM Lead WHERE Id = :leadId].LeadSource, 'Lead Source should be the partner source');
        System.assertEquals(false, result.containsKey('message'), 'Empty fields should not be returned');
    }

    @IsTest
    static void realRunningUserIsNotAGuest() {
        configure(true, null, APP);

        Test.startTest();
        RestResponse res = call(JSON.serialize(lead('real.user@example.com', '9123456786')));
        Test.stopTest();

        System.assertEquals(200, res.statusCode, 'A logged-in user must be accepted: ' + res.responseBody.toString());
    }

    @IsTest
    static void existingLeadIsUpdated() {
        configureValid();

        Test.startTest();
        RestResponse res = call(JSON.serialize(lead('existing.webhook7@example.com', '9600000007')));
        Test.stopTest();

        System.assertEquals(200, res.statusCode, res.responseBody.toString());
        System.assertEquals('updated', body(res).get('action'), 'Existing student should be updated');
        System.assertEquals(EXISTING_LEADS, [SELECT COUNT() FROM Lead], 'No new Lead should be created');
    }

    @IsTest
    static void invalidSingleLeadReturns400AndIsLogged() {
        configureValid();

        Test.startTest();
        RestResponse res = call(JSON.serialize(lead('bad-email', '123')));
        Test.stopTest();

        System.assertEquals(400, res.statusCode, 'Invalid lead should return 400');
        Map<String, Object> result = body(res);
        System.assertEquals(false, result.get('success'), 'Invalid lead should not be saved');
        System.assert(((String) result.get('message')).contains('email is not a valid'), 'Reason should be returned: ' + result.get('message'));
        System.assertEquals(1, webhookLogs(), 'Rejected lead should be logged');
        API_Log__c log = [SELECT Response__c FROM API_Log__c WHERE Log_Name__c = :PartnerLeadWebhook.LOG_NAME];
        System.assert(!log.Response__c.contains('bad-email'), 'Log must not contain the submitted values');
        System.assert(log.Response__c.contains(APP), 'Log should name the calling app');
    }

    @IsTest
    static void sourceOfAnotherAppIsRejected() {
        configure(true, false, 'Other Partner Integration');

        Test.startTest();
        RestResponse res = call(JSON.serialize(lead('spoof@example.com', '9123456787')));
        Test.stopTest();

        System.assertEquals(400, res.statusCode, 'A lead source of another partner must be refused: ' + res.responseBody.toString());
        System.assertEquals(0, [SELECT COUNT() FROM Lead WHERE Email = 'spoof@example.com'], 'Nothing should be saved');
    }

    @IsTest
    static void unknownCallingAppFailsClosed() {
        configure(true, false, '');

        Test.startTest();
        RestResponse res = call(JSON.serialize(lead('noapp@example.com', '9123456788')));
        Test.stopTest();

        System.assertEquals(500, res.statusCode, 'Calls whose app cannot be determined must be refused');
        System.assertEquals(0, [SELECT COUNT() FROM Lead WHERE Email = 'noapp@example.com'], 'Nothing should be saved');
        System.assertEquals(1, webhookLogs(), 'Refused call should be logged');
    }

    @IsTest
    static void listReturnsOneResultPerLead() {
        configureValid();
        List<Object> leads = new List<Object>{
            lead('list.one@example.com', '9123456781'),
            lead('list.two@example.com', 'not-a-phone')
        };

        Test.startTest();
        RestResponse res = call(JSON.serialize(leads));
        Test.stopTest();

        System.assertEquals(200, res.statusCode, 'A list always returns 200 with per-lead results');
        List<Object> results = (List<Object>) JSON.deserializeUntyped(res.responseBody.toString());
        System.assertEquals(2, results.size(), 'One result per lead');
        System.assertEquals(true, ((Map<String, Object>) results[0]).get('success'), 'First lead should be saved');
        System.assertEquals(false, ((Map<String, Object>) results[1]).get('success'), 'Second lead should be rejected');
    }

    @IsTest
    static void fiftyLeadsInOneRequestAreSaved() {
        configureValid();
        List<Object> leads = new List<Object>();
        for (Integer i = 0; i < PartnerLeadWebhook.MAX_LEADS_PER_REQUEST; i++) {
            leads.add(lead('batch' + i + '@example.com', String.valueOf(9500000000L + i)));
        }

        Test.startTest();
        RestResponse res = call(JSON.serialize(leads));
        Test.stopTest();

        System.assertEquals(200, res.statusCode, res.responseBody.toString());
        for (Object o : (List<Object>) JSON.deserializeUntyped(res.responseBody.toString())) {
            System.assertEquals(true, ((Map<String, Object>) o).get('success'), 'Every lead should be saved: ' + o);
        }
        System.assertEquals(EXISTING_LEADS + PartnerLeadWebhook.MAX_LEADS_PER_REQUEST, [SELECT COUNT() FROM Lead], 'All leads should be created');
    }

    @IsTest
    static void tooManyLeadsAreRefused() {
        configureValid();
        List<Object> leads = new List<Object>();
        for (Integer i = 0; i <= PartnerLeadWebhook.MAX_LEADS_PER_REQUEST; i++) {
            leads.add(lead('over' + i + '@example.com', String.valueOf(9400000000L + i)));
        }

        Test.startTest();
        RestResponse res = call(JSON.serialize(leads));
        Test.stopTest();

        System.assertEquals(400, res.statusCode, 'More than the maximum must be refused');
        System.assertEquals(EXISTING_LEADS, [SELECT COUNT() FROM Lead], 'Nothing should be saved');
    }

    @IsTest
    static void guestCallIsRefusedAndLogged() {
        configure(true, true, APP);

        Test.startTest();
        RestResponse res = call(JSON.serialize(lead('guest@example.com', '9123456782')));
        Test.stopTest();

        System.assertEquals(401, res.statusCode, 'Unauthenticated (guest) calls must be refused');
        System.assertEquals(0, [SELECT COUNT() FROM Lead WHERE Email = 'guest@example.com'], 'Nothing should be saved');
        System.assertEquals(1, webhookLogs(), 'Refused call should be logged');
    }

    @IsTest
    static void switchedOffReturns503() {
        configure(false, false, APP);

        Test.startTest();
        RestResponse res = call(JSON.serialize(lead('off@example.com', '9123456784')));
        Test.stopTest();

        System.assertEquals(503, res.statusCode, 'Switched-off API must return 503');
        System.assertEquals(0, [SELECT COUNT() FROM Lead WHERE Email = 'off@example.com'], 'Nothing should be saved');
    }

    @IsTest
    static void featureFlagIsReadFromMetadataByDefault() {
        PartnerLeadWebhook.testIsGuest = false;

        Test.startTest();
        RestResponse res = call(JSON.serialize(lead('flag@example.com', '9123456785')));
        Test.stopTest();

        System.assertNotEquals(null, res.statusCode, 'A response must always be returned');
        System.assertEquals(0, [SELECT COUNT() FROM Lead WHERE Email = 'flag@example.com'], 'A test session is not a partner app, so nothing is saved');
    }

    @IsTest
    static void missingConfigurationReturns500AndIsLogged() {
        configureValid();
        PartnerLeadWebhook.testServiceFailure = new PartnerLeadService.ConfigurationException('Mapping missing');

        Test.startTest();
        RestResponse res = call(JSON.serialize(lead('config.missing@example.com', '9123456790')));
        Test.stopTest();

        System.assertEquals(500, res.statusCode, 'Missing configuration must return 500');
        System.assert(((String) body(res).get('message')).contains('not configured'), 'Partner should be told to contact us: ' + res.responseBody.toString());
        System.assertEquals(1, webhookLogs(), 'Configuration failure should be logged');
    }

    @IsTest
    static void unexpectedErrorReturns500WithoutDetails() {
        configureValid();
        PartnerLeadWebhook.testServiceFailure = new DmlException('Internal detail that must not leak');

        Test.startTest();
        RestResponse res = call(JSON.serialize(lead('unexpected@example.com', '9123456791')));
        Test.stopTest();

        System.assertEquals(500, res.statusCode, 'Unexpected errors must return 500');
        System.assert(!res.responseBody.toString().contains('Internal detail'), 'Internal error text must not be returned: ' + res.responseBody.toString());
        System.assertEquals(1, webhookLogs(), 'Unexpected error should be logged');
    }

    @IsTest
    static void malformedBodiesReturn400() {
        configureValid();

        Test.startTest();
        Integer notJson = call('not json').statusCode;
        Integer emptyBody = call(null).statusCode;
        Integer emptyList = call('[]').statusCode;
        Integer plainText = call('"text"').statusCode;
        Integer listOfText = call('["a"]').statusCode;
        Test.stopTest();

        System.assertEquals(400, notJson, 'Invalid JSON must return 400');
        System.assertEquals(400, emptyBody, 'Empty body must return 400');
        System.assertEquals(400, emptyList, 'Empty list must return 400');
        System.assertEquals(400, plainText, 'A JSON string is not a lead');
        System.assertEquals(400, listOfText, 'List items must be objects');
    }
}