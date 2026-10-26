/** Tests for the pre-registration webhook (UGPreRegistrationRest). */
@IsTest
private class UGPreRegistrationRestTest {

    private static Map<String, Object> call(Map<String, Object> payload) {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/UGPreRegistration';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(payload));
        RestContext.request = req;
        RestContext.response = new RestResponse();
        List<Object> r = (List<Object>) JSON.deserializeUntyped(UGPreRegistrationRest.receive());
        return (Map<String, Object>) r[0];
    }

    private static Lead makeLead(String reg, String dept, Integer filledSlots) {
        Lead l = new Lead(FirstName = 'Pre', LastName = 'Hook' + reg, Company = 'NA', Email = 'hook' + reg + '@test.com',
                          Registration_Number__c = reg, Department__c = dept);
        if (filledSlots >= 1) l.Group_1__c = 'UG_Group1';
        if (filledSlots >= 2) l.Group_2__c = 'UG_Group2';
        if (filledSlots >= 3) l.Group_3__c = 'UG_Group3';
        if (filledSlots >= 4) l.Group_4__c = 'UG_Group4';
        insert l;
        return l;
    }

    private static Map<String, Object> body(Id leadId, String tag, Object pr, String dt) {
        Map<String, Object> m = new Map<String, Object>{ 'leadId' => String.valueOf(leadId), 'grptag' => tag };
        if (pr != null) m.put('preRegister', pr);
        if (dt != null) m.put('preRegistrationDate', dt);
        return m;
    }

    @IsTest static void newGroupGoesToNextFreeSlot() {
        Lead l = makeLead('HK1', 'Undergraduation', 1);
        Map<String, Object> r = call(body(l.Id, 'UG_Group3', true, '2026-05-01'));
        System.assertEquals(true, r.get('success'), String.valueOf(r));
        Lead x = [SELECT Group_2__c, Group_2_Pre_Register__c, Group_2_Pre_Registration_Date__c, Group_1_Pre_Register__c FROM Lead WHERE Id = :l.Id];
        System.assertEquals('UG_Group3', x.Group_2__c);
        System.assertEquals(true, x.Group_2_Pre_Register__c);
        System.assertEquals(Date.newInstance(2026, 5, 1), x.Group_2_Pre_Registration_Date__c);
    }

    @IsTest static void groupNameKeyAndDefaultDateAndOptionalProgrammes() {
        Lead l = makeLead('HK2', 'Undergraduation', 0);
        Map<String, Object> p = new Map<String, Object>{ 'leadId' => String.valueOf(l.Id), 'groupName' => 'UG_Group2', 'preRegister' => true,
            'programmes' => new List<Object>{ new Map<String, Object>{ 'programInterestedIn' => 'BSc', 'major' => 'CS' } } };
        System.assertEquals(true, call(p).get('success'));
        Lead x = [SELECT Group_1__c, Group_1_Pre_Registration_Date__c, Group_1_Programmes__c, Group_1_Majors__c FROM Lead WHERE Id = :l.Id];
        System.assertEquals('UG_Group2', x.Group_1__c);
        System.assertEquals(Date.today(), x.Group_1_Pre_Registration_Date__c);
        System.assertEquals('BSc', x.Group_1_Programmes__c);
        System.assertEquals('CS', x.Group_1_Majors__c);
    }

    @IsTest static void existingGroupSlotIsUpdatedAndProgrammesKept() {
        Lead l = makeLead('HK3', 'Undergraduation', 2);
        l.Group_2_Programmes__c = 'KeepMe';
        update l;
        Map<String, Object> r = call(body(l.Id, 'UG_Group2', true, '2026-06-01'));
        System.assertEquals(false, r.get('newGroup'), String.valueOf(r));
        Lead x = [SELECT Group_2_Pre_Register__c, Group_2_Programmes__c, Group_3__c FROM Lead WHERE Id = :l.Id];
        System.assertEquals(true, x.Group_2_Pre_Register__c);
        System.assertEquals('KeepMe', x.Group_2_Programmes__c);
        System.assertEquals(null, x.Group_3__c, 'No extra slot used');
    }

    @IsTest static void preRegisterFalseIsAllowedAndKeepsDate() {
        Lead l = makeLead('HK4', 'Undergraduation', 0);
        call(body(l.Id, 'UG_Group1', true, '2026-06-01'));
        System.assertEquals(true, call(body(l.Id, 'UG_Group1', false, null)).get('success'));
        Lead x = [SELECT Group_1_Pre_Register__c, Group_1_Pre_Registration_Date__c FROM Lead WHERE Id = :l.Id];
        System.assertEquals(false, x.Group_1_Pre_Register__c);
        System.assertEquals(Date.newInstance(2026, 6, 1), x.Group_1_Pre_Registration_Date__c);
    }

    @IsTest static void maxGroupsIsEnforced() {
        Lead l = makeLead('HK5', 'Undergraduation', 4);
        Map<String, Object> r = call(body(l.Id, 'UG_Group9', true, null));
        System.assertEquals(false, r.get('success'));
        System.assert(String.valueOf(r.get('message')).contains('maximum'), String.valueOf(r));
    }

    @IsTest static void maxProgrammesIsEnforced() {
        Lead l = makeLead('HK6', 'Undergraduation', 0);
        List<Object> progs = new List<Object>();
        for (Integer i = 0; i < 4; i++) progs.add(new Map<String, Object>{ 'programInterestedIn' => 'P' + i, 'major' => 'M' });
        Map<String, Object> p = body(l.Id, 'UG_Group1', true, null);
        p.put('programmes', progs);
        System.assertEquals(false, call(p).get('success'));
        System.assertEquals(null, [SELECT Group_1__c FROM Lead WHERE Id = :l.Id].Group_1__c);
    }

    @IsTest static void validationErrors() {
        Lead ug = makeLead('HK7', 'Undergraduation', 0);
        Lead ms = makeLead('HK8', 'Masters', 0);
        System.assertEquals(false, call(new Map<String, Object>{ 'grptag' => 'G', 'preRegister' => true }).get('success'), 'leadId missing');
        System.assertEquals(false, call(new Map<String, Object>{ 'leadId' => 'abc', 'grptag' => 'G', 'preRegister' => true }).get('success'), 'bad id');
        System.assertEquals(false, call(body(ug.Id, null, true, null)).get('success'), 'group missing');
        System.assertEquals(false, call(body(ug.Id, 'G', null, null)).get('success'), 'preRegister missing');
        System.assertEquals(false, call(body(ug.Id, 'G', true, '01/05/2026')).get('success'), 'bad date');
        System.assertEquals(false, call(body(ms.Id, 'G', true, null)).get('success'), 'not UG');
    }

    @IsTest static void listPayloadIsHandled() {
        Lead l = makeLead('HK9', 'Undergraduation', 0);
        RestRequest req = new RestRequest();
        req.requestBody = Blob.valueOf(JSON.serialize(new List<Object>{ body(l.Id, 'UG_Group1', true, null), body(l.Id, 'UG_Group2', true, null) }));
        RestContext.request = req;
        RestContext.response = new RestResponse();
        List<Object> r = (List<Object>) JSON.deserializeUntyped(UGPreRegistrationRest.receive());
        System.assertEquals(2, r.size());
        System.assertEquals('UG_Group2', [SELECT Group_2__c FROM Lead WHERE Id = :l.Id].Group_2__c);
    }

    @IsTest static void convertedLeadUpdatesLeadAndAccountWithoutOpportunity() {
        RestRequest cr = new RestRequest();
        cr.requestUri = '/services/apexrest/saveLeadRelatedData/';
        cr.httpMethod = 'POST';
        cr.requestBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
            'department' => 'Undergraduation', 'typeOfForm' => 'Auris_Admission_Form', 'registrationNumber' => 'HK10',
            'firstName' => 'Pre', 'lastName' => 'HookHK10', 'email' => 'hookhk10@test.com', 'phone' => '9876501010',
            'grpPrograms' => new List<Object>{ new Map<String, Object>{ 'grptag' => 'UG_Group1', 'applicationNumber' => 'APP-1',
                'applicationDate' => '2026-01-14', 'programmes' => new List<Object>{
                    new Map<String, Object>{ 'programInterestedIn' => 'UG_Group1_Prog1', 'major' => 'Computer Science' } } } } }));
        RestContext.request = cr;
        RestContext.response = new RestResponse();
        saveWebTo_YourProfileData.handleAurisData();
        Id leadId = [SELECT Id FROM Lead WHERE Registration_Number__c = 'HK10' LIMIT 1].Id;
        LeadConversionService.processSingleLead(new Map<String, Object>{
            'leadId' => String.valueOf(leadId), 'leadStatus' => 'Application Submitted',
            'registrationNumber' => 'X', 'registrationDate' => '2026-02-16' });
        Id accId = [SELECT ConvertedAccountId FROM Lead WHERE Id = :leadId].ConvertedAccountId;
        System.assertNotEquals(null, accId, 'Lead converted');
        Integer oppsBefore = [SELECT COUNT() FROM Opportunity WHERE AccountId = :accId];

        Map<String, Object> r = call(body(leadId, 'UG_Group2', true, '2026-07-01'));
        System.assertEquals(true, r.get('success'), String.valueOf(r));
        System.assertEquals(true, r.get('accountUpdated'));
        Account a = [SELECT Group_1__c, Group_2__c, Group_2_Pre_Register__c, Group_2_Pre_Registration_Date__c FROM Account WHERE Id = :accId];
        System.assertEquals('UG_Group1', a.Group_1__c);
        System.assertEquals('UG_Group2', a.Group_2__c);
        System.assertEquals(true, a.Group_2_Pre_Register__c);
        System.assertEquals(Date.newInstance(2026, 7, 1), a.Group_2_Pre_Registration_Date__c);
        System.assertEquals(oppsBefore, [SELECT COUNT() FROM Opportunity WHERE AccountId = :accId], 'No new opportunity');
    }
}