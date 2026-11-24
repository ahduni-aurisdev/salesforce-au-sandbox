/**
 * @description Tests for MBARendezvousLeadWebhook: guest rejection, feature flag, request parsing,
 *              responses and failure logging. Lead rules are covered by MBARendezvousLeadServiceTest.
 *              OAuth token validation is done by the Salesforce platform before the class runs.
 * @author Jitendra V
 * @date 2026-11-16
 * @version 2.0
 * @lastModified 2026-11-17 - OAuth integration user replaces the public-site API key
 */
@IsTest
private class MBARendezvousLeadWebhookTest {

    private static final Integer EXISTING_LEADS = 200;
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
                Department__c = 'Masters',
                Preferred_Programme__c = MBA,
                Admission_Year__c = 'Admission Year - 2027'
            ));
        }
        insert leads;
    }

    private static void configure(Boolean enabled, Boolean guest) {
        MBARendezvousLeadWebhook.testFeatureEnabled = enabled;
        MBARendezvousLeadWebhook.testIsGuest = guest;
    }

    private static void configureValid() {
        configure(true, false);
    }

    private static RestResponse call(String body) {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/partner/mbarendezvous/lead';
        req.httpMethod = 'POST';
        req.requestBody = body == null ? null : Blob.valueOf(body);
        RestContext.request = req;
        RestResponse res = new RestResponse();
        RestContext.response = res;
        MBARendezvousLeadWebhook.receive();
        return res;
    }

    private static Map<String, Object> lead(String email, String phone) {
        return new Map<String, Object>{
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
        return [SELECT COUNT() FROM API_Log__c WHERE Log_Name__c = :MBARendezvousLeadWebhook.LOG_NAME];
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
        System.assertEquals('MBA Rendezvous', [SELECT LeadSource FROM Lead WHERE Id = :leadId].LeadSource, 'Lead Source should be MBA Rendezvous');
        System.assertEquals(false, result.containsKey('message'), 'Empty fields should not be returned');
    }

    @IsTest
    static void realRunningUserIsNotAGuest() {
        MBARendezvousLeadWebhook.testFeatureEnabled = true;

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
        Map<String, Object> bad = lead('bad-email', '123');

        Test.startTest();
        RestResponse res = call(JSON.serialize(bad));
        Test.stopTest();

        System.assertEquals(400, res.statusCode, 'Invalid lead should return 400');
        Map<String, Object> result = body(res);
        System.assertEquals(false, result.get('success'), 'Invalid lead should not be saved');
        System.assert(((String) result.get('message')).contains('email is not a valid'), 'Reason should be returned: ' + result.get('message'));
        System.assertEquals(1, webhookLogs(), 'Rejected lead should be logged');
        API_Log__c log = [SELECT Response__c FROM API_Log__c WHERE Log_Name__c = :MBARendezvousLeadWebhook.LOG_NAME];
        System.assert(!log.Response__c.contains('bad-email'), 'Log must not contain the submitted values');
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
        for (Integer i = 0; i < MBARendezvousLeadWebhook.MAX_LEADS_PER_REQUEST; i++) {
            leads.add(lead('batch' + i + '@example.com', String.valueOf(9500000000L + i)));
        }

        Test.startTest();
        RestResponse res = call(JSON.serialize(leads));
        Test.stopTest();

        System.assertEquals(200, res.statusCode, res.responseBody.toString());
        for (Object o : (List<Object>) JSON.deserializeUntyped(res.responseBody.toString())) {
            System.assertEquals(true, ((Map<String, Object>) o).get('success'), 'Every lead should be saved: ' + o);
        }
        System.assertEquals(EXISTING_LEADS + MBARendezvousLeadWebhook.MAX_LEADS_PER_REQUEST, [SELECT COUNT() FROM Lead], 'All leads should be created');
    }

    @IsTest
    static void tooManyLeadsAreRefused() {
        configureValid();
        List<Object> leads = new List<Object>();
        for (Integer i = 0; i <= MBARendezvousLeadWebhook.MAX_LEADS_PER_REQUEST; i++) {
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
        configure(true, true);

        Test.startTest();
        RestResponse res = call(JSON.serialize(lead('guest@example.com', '9123456782')));
        Test.stopTest();

        System.assertEquals(401, res.statusCode, 'Unauthenticated (guest) calls must be refused');
        System.assertEquals(0, [SELECT COUNT() FROM Lead WHERE Email = 'guest@example.com'], 'Nothing should be saved');
        System.assertEquals(1, webhookLogs(), 'Refused call should be logged');
    }

    @IsTest
    static void switchedOffReturns503() {
        configure(false, false);

        Test.startTest();
        RestResponse res = call(JSON.serialize(lead('off@example.com', '9123456784')));
        Test.stopTest();

        System.assertEquals(503, res.statusCode, 'Switched-off API must return 503');
        System.assertEquals(0, [SELECT COUNT() FROM Lead WHERE Email = 'off@example.com'], 'Nothing should be saved');
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