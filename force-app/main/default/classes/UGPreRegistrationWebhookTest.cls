/** Tests for the public pre-registration webhook (shared-secret check + processing). */
@IsTest
private class UGPreRegistrationWebhookTest {
    private static final String SECRET = 'unit-test-secret';

    private static Lead makeLead(String reg) {
        Lead l = new Lead(FirstName = 'Web', LastName = 'Hook' + reg, Company = 'NA', Email = 'wh' + reg + '@test.com',
                          Registration_Number__c = reg, Department__c = 'Undergraduation');
        insert l;
        return l;
    }

    /** Calls the webhook. mode: 'sig' = valid signature, 'badsig', 'key' = valid api key, 'badkey', 'none'. */
    private static RestResponse call(String body, String mode) {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/ug/preregistration';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(body);
        if (mode == 'sig') req.addHeader('X-Signature', UGPreRegistrationWebhook.hmac(body, SECRET));
        if (mode == 'sigprefix') req.addHeader('X-Signature', 'sha256=' + UGPreRegistrationWebhook.hmac(body, SECRET).toUpperCase());
        if (mode == 'badsig') req.addHeader('X-Signature', UGPreRegistrationWebhook.hmac(body, 'wrong'));
        if (mode == 'key') req.addHeader('X-Api-Key', SECRET);
        if (mode == 'badkey') req.addHeader('X-Api-Key', 'nope');
        RestContext.request = req;
        RestResponse res = new RestResponse();
        RestContext.response = res;
        UGPreRegistrationWebhook.receive();
        return res;
    }

    private static String payload(Id leadId, String tag) {
        return JSON.serialize(new Map<String, Object>{ 'leadId' => String.valueOf(leadId), 'grptag' => tag, 'preRegister' => true, 'preRegistrationDate' => '2026-05-01' });
    }

    @IsTest static void secretMustBeConfiguredInTheOrg() {
        UGPreRegistrationWebhook.testSecret = ''; // no secret configured
        System.assertEquals(500, call('{}', 'sig').statusCode);
    }

    @IsTest static void validSignatureSavesGroup() {
        Lead l = makeLead('WH1');
        UGPreRegistrationWebhook.testSecret = SECRET;
        RestResponse r = call(payload(l.Id, 'UG_Group2'), 'sig');
        System.assertEquals(200, r.statusCode, r.responseBody.toString());
        List<Object> out = (List<Object>) JSON.deserializeUntyped(r.responseBody.toString());
        System.assertEquals(true, ((Map<String, Object>) out[0]).get('success'), r.responseBody.toString());
        Lead x = [SELECT Group_1__c, Group_1_Pre_Register__c, Group_1_Pre_Registration_Date__c FROM Lead WHERE Id = :l.Id];
        System.assertEquals('UG_Group2', x.Group_1__c);
        System.assertEquals(true, x.Group_1_Pre_Register__c);
        System.assertEquals(Date.newInstance(2026, 5, 1), x.Group_1_Pre_Registration_Date__c);
    }

    @IsTest static void prefixedUppercaseSignatureAndApiKeyAreAccepted() {
        Lead l = makeLead('WH2');
        UGPreRegistrationWebhook.testSecret = SECRET;
        System.assertEquals(200, call(payload(l.Id, 'UG_Group1'), 'sigprefix').statusCode);
        System.assertEquals(200, call(payload(l.Id, 'UG_Group2'), 'key').statusCode);
        System.assertEquals('UG_Group2', [SELECT Group_2__c FROM Lead WHERE Id = :l.Id].Group_2__c);
    }

    @IsTest static void badOrMissingSecretIsRefusedAndNothingIsSaved() {
        Lead l = makeLead('WH3');
        UGPreRegistrationWebhook.testSecret = SECRET;
        for (String mode : new List<String>{ 'badsig', 'badkey', 'none' }) {
            System.assertEquals(401, call(payload(l.Id, 'UG_Group3'), mode).statusCode, mode);
        }
        System.assertEquals(null, [SELECT Group_1__c FROM Lead WHERE Id = :l.Id].Group_1__c);
    }

    @IsTest static void signatureOfAnotherBodyIsRefused() {
        Lead l = makeLead('WH4');
        UGPreRegistrationWebhook.testSecret = SECRET;
        String signedBody = payload(l.Id, 'UG_Group1');
        RestRequest req = new RestRequest();
        req.requestBody = Blob.valueOf(payload(l.Id, 'UG_Group4')); // different body than the one signed
        req.addHeader('X-Signature', UGPreRegistrationWebhook.hmac(signedBody, SECRET));
        RestContext.request = req;
        RestResponse res = new RestResponse();
        RestContext.response = res;
        UGPreRegistrationWebhook.receive();
        System.assertEquals(401, res.statusCode);
    }

    @IsTest static void businessErrorsComeBackAsSuccessFalse() {
        Lead l = makeLead('WH5');
        UGPreRegistrationWebhook.testSecret = SECRET;
        String body = JSON.serialize(new Map<String, Object>{ 'leadId' => String.valueOf(l.Id), 'grptag' => 'G', 'preRegister' => true, 'preRegistrationDate' => '01/05/2026' });
        RestResponse r = call(body, 'sig');
        System.assertEquals(200, r.statusCode);
        Map<String, Object> first = (Map<String, Object>) ((List<Object>) JSON.deserializeUntyped(r.responseBody.toString()))[0];
        System.assertEquals(false, first.get('success'));
    }

    @IsTest static void listPayloadAndBadJson() {
        Lead l = makeLead('WH6');
        UGPreRegistrationWebhook.testSecret = SECRET;
        String list1 = '[' + payload(l.Id, 'UG_Group1') + ',' + payload(l.Id, 'UG_Group2') + ']';
        RestResponse r = call(list1, 'sig');
        System.assertEquals(2, ((List<Object>) JSON.deserializeUntyped(r.responseBody.toString())).size());
        System.assertEquals(400, call('not json', 'sig').statusCode);
        System.assertEquals(400, call('"text"', 'sig').statusCode);
    }
}