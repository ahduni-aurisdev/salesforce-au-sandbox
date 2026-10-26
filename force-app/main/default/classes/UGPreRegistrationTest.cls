/**
 * Tests for UG group pre-registration (preRegister / preRegistrationDate per group):
 *  - lead create/update stores the flag on the Lead slot
 *  - lead conversion skips pre-registered groups (no Opportunity) and mirrors all groups to the Account
 *  - pre-registered-only leads are not converted
 *  - post-conversion payloads update Lead and Account, and preRegister=false upgrades to an Opportunity
 *  - payloads without the new keys behave exactly as before
 */
@IsTest
private class UGPreRegistrationTest {

    private static Map<String, Object> post(Map<String, Object> payload) {
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestUri = '/services/apexrest/saveLeadRelatedData/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(payload));
        RestContext.request = req;
        RestContext.response = res;
        saveWebTo_YourProfileData.handleAurisData();
        return (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
    }

    private static Map<String, Object> grp(String tag, String appNo, Object preReg, String preRegDate) {
        Map<String, Object> g = new Map<String, Object>{
            'grptag' => tag, 'applicationNumber' => appNo, 'applicationDate' => '2026-01-14',
            'programmes' => new List<Object>{
                new Map<String, Object>{ 'programInterestedIn' => tag + '_Prog1', 'major' => 'Computer Science' } } };
        if (preReg != null) g.put('preRegister', preReg);
        if (preRegDate != null) g.put('preRegistrationDate', preRegDate);
        return g;
    }

    private static Map<String, Object> lead(String reg, List<Object> groups) {
        return new Map<String, Object>{
            'department' => 'Undergraduation', 'typeOfForm' => 'Auris_Admission_Form',
            'registrationNumber' => reg, 'firstName' => 'Pre', 'lastName' => 'Reg' + reg,
            'email' => 'prereg' + reg + '@test.com', 'phone' => '9876501' + reg.right(3),
            'grpPrograms' => groups };
    }

    private static Lead leadByReg(String reg) {
        return [SELECT Id, IsConverted, ConvertedAccountId,
                       Group_1__c, Group_1_Pre_Register__c, Group_1_Pre_Registration_Date__c,
                       Group_2__c, Group_2_Pre_Register__c, Group_2_Pre_Registration_Date__c,
                       Group_3__c, Group_3_Pre_Register__c FROM Lead WHERE Registration_Number__c = :reg LIMIT 1];
    }

    private static Map<String, Object> convert(Id leadId, List<Object> groups) {
        Map<String, Object> p = new Map<String, Object>{
            'leadId' => String.valueOf(leadId), 'leadStatus' => 'Application Submitted',
            'registrationNumber' => 'X', 'registrationDate' => '2026-02-16' };
        if (groups != null) p.put('grpPrograms', groups);
        return LeadConversionService.processSingleLead(p);
    }

    // ── Lead create / update ──────────────────────────────────────────────────
    @IsTest static void leadStoresPreRegisterFlagAndDate() {
        post(lead('PR1001', new List<Object>{ grp('UG_Group1', 'APP-1', null, null), grp('UG_Group2', 'APP-2', true, '2026-03-01') }));
        Lead l = leadByReg('PR1001');
        System.assertEquals('UG_Group1', l.Group_1__c);
        System.assertEquals(false, l.Group_1_Pre_Register__c, 'No key = normal group');
        System.assertEquals('UG_Group2', l.Group_2__c);
        System.assertEquals(true, l.Group_2_Pre_Register__c);
        System.assertEquals(Date.newInstance(2026, 3, 1), l.Group_2_Pre_Registration_Date__c);
    }

    @IsTest static void existingGroupKeepsFlagWhenKeyAbsentAndUpdatesWhenSent() {
        post(lead('PR1002', new List<Object>{ grp('UG_Group2', 'APP-2', true, '2026-03-01') }));
        post(lead('PR1002', new List<Object>{ grp('UG_Group2', 'APP-2', null, null) }));
        System.assertEquals(true, leadByReg('PR1002').Group_1_Pre_Register__c, 'Flag untouched when key absent');
        post(lead('PR1002', new List<Object>{ grp('UG_Group2', 'APP-2', false, null) }));
        Lead l = leadByReg('PR1002');
        System.assertEquals(false, l.Group_1_Pre_Register__c);
        System.assertEquals(Date.newInstance(2026, 3, 1), l.Group_1_Pre_Registration_Date__c, 'Date kept as history');
    }

    @IsTest static void preRegisterTrueWithoutDateDefaultsToToday() {
        post(lead('PR1003', new List<Object>{ grp('UG_Group3', 'APP-3', true, null) }));
        System.assertEquals(Date.today(), leadByReg('PR1003').Group_1_Pre_Registration_Date__c);
    }

    // ── Conversion ────────────────────────────────────────────────────────────
    @IsTest static void conversionSkipsPreRegisteredGroupAndMirrorsAccount() {
        post(lead('PR2001', new List<Object>{ grp('UG_Group1', 'APP-1', null, null), grp('UG_Group2', 'APP-2', true, '2026-03-01') }));
        Lead l = leadByReg('PR2001');
        Map<String, Object> res = convert(l.Id, null);
        l = leadByReg('PR2001');
        System.assert(l.IsConverted, 'Lead converted because it has a normal group: ' + res);
        List<Opportunity> opps = [SELECT Program_Group_Tag__c FROM Opportunity WHERE AccountId = :l.ConvertedAccountId];
        System.assertEquals(1, opps.size(), 'Only the normal group becomes an Opportunity');
        System.assertEquals('UG_Group1', opps[0].Program_Group_Tag__c);
        Account a = [SELECT Group_1__c, Group_1_Pre_Register__c, Group_2__c, Group_2_Pre_Register__c,
                            Group_2_Pre_Registration_Date__c, Group_2_Programmes__c, Group_2_Application_Number__c
                     FROM Account WHERE Id = :l.ConvertedAccountId];
        System.assertEquals('UG_Group1', a.Group_1__c);
        System.assertEquals(false, a.Group_1_Pre_Register__c);
        System.assertEquals('UG_Group2', a.Group_2__c);
        System.assertEquals(true, a.Group_2_Pre_Register__c);
        System.assertEquals(Date.newInstance(2026, 3, 1), a.Group_2_Pre_Registration_Date__c);
        System.assertEquals('UG_Group2_Prog1', a.Group_2_Programmes__c);
        System.assertEquals('APP-2', a.Group_2_Application_Number__c);
    }

    @IsTest static void allPreRegisteredLeadIsNotConverted() {
        post(lead('PR2002', new List<Object>{ grp('UG_Group2', 'APP-2', true, '2026-03-01') }));
        Lead l = leadByReg('PR2002');
        Map<String, Object> res = convert(l.Id, null);
        System.assertEquals(false, leadByReg('PR2002').IsConverted);
        System.assert(String.valueOf(res.get('message')).contains('pre-registered'), String.valueOf(res));
    }

    @IsTest static void conversionPayloadCanCarryPreRegisteredGroup() {
        post(lead('PR2003', new List<Object>{ grp('UG_Group1', 'APP-1', null, null) }));
        Lead l = leadByReg('PR2003');
        convert(l.Id, new List<Object>{ grp('UG_Group4', 'APP-4', true, '2026-04-01') });
        l = leadByReg('PR2003');
        System.assert(l.IsConverted);
        System.assertEquals(1, [SELECT COUNT() FROM Opportunity WHERE AccountId = :l.ConvertedAccountId]);
        Account a = [SELECT Group_2__c, Group_2_Pre_Register__c FROM Account WHERE Id = :l.ConvertedAccountId];
        System.assertEquals('UG_Group4', a.Group_2__c);
        System.assertEquals(true, a.Group_2_Pre_Register__c);
    }

    @IsTest static void groupsWithoutNewKeysConvertAsBefore() {
        post(lead('PR2004', new List<Object>{ grp('UG_Group1', 'APP-1', null, null), grp('UG_Group2', 'APP-2', null, null) }));
        Lead l = leadByReg('PR2004');
        convert(l.Id, null);
        l = leadByReg('PR2004');
        System.assertEquals(2, [SELECT COUNT() FROM Opportunity WHERE AccountId = :l.ConvertedAccountId]);
        System.assertEquals(false, [SELECT Group_2_Pre_Register__c FROM Account WHERE Id = :l.ConvertedAccountId].Group_2_Pre_Register__c);
    }

    // ── After conversion ──────────────────────────────────────────────────────
    @IsTest static void afterConversionNewPreRegisteredGroupUpdatesLeadAndAccountWithoutOpportunity() {
        post(lead('PR3001', new List<Object>{ grp('UG_Group1', 'APP-1', null, null) }));
        Lead l = leadByReg('PR3001');
        convert(l.Id, null);
        l = leadByReg('PR3001');
        Map<String, Object> res = LeadConversionService.processSingleLead(new Map<String, Object>{
            'personAccountId' => String.valueOf(l.ConvertedAccountId), 'registrationNumber' => 'PR3001',
            'grpPrograms' => new List<Object>{ grp('UG_Group2', 'APP-2', true, '2026-05-01') } });
        System.assertEquals(1, [SELECT COUNT() FROM Opportunity WHERE AccountId = :l.ConvertedAccountId], String.valueOf(res));
        l = leadByReg('PR3001');
        System.assertEquals('UG_Group2', l.Group_2__c);
        System.assertEquals(true, l.Group_2_Pre_Register__c);
        Account a = [SELECT Group_2__c, Group_2_Pre_Register__c, Group_2_Pre_Registration_Date__c FROM Account WHERE Id = :l.ConvertedAccountId];
        System.assertEquals('UG_Group2', a.Group_2__c);
        System.assertEquals(true, a.Group_2_Pre_Register__c);
        System.assertEquals(Date.newInstance(2026, 5, 1), a.Group_2_Pre_Registration_Date__c);
    }

    @IsTest static void preRegisteredGroupUpgradedToApplicationCreatesOpportunity() {
        post(lead('PR3002', new List<Object>{ grp('UG_Group1', 'APP-1', null, null), grp('UG_Group2', 'APP-2', true, '2026-03-01') }));
        Lead l = leadByReg('PR3002');
        convert(l.Id, null);
        l = leadByReg('PR3002');
        System.assertEquals(1, [SELECT COUNT() FROM Opportunity WHERE AccountId = :l.ConvertedAccountId]);
        LeadConversionService.processSingleLead(new Map<String, Object>{
            'personAccountId' => String.valueOf(l.ConvertedAccountId), 'registrationNumber' => 'PR3002',
            'grpPrograms' => new List<Object>{ grp('UG_Group2', 'APP-2', false, null) } });
        System.assertEquals(2, [SELECT COUNT() FROM Opportunity WHERE AccountId = :l.ConvertedAccountId], 'Upgrade creates the Opportunity');
        System.assertEquals(false, [SELECT Group_2_Pre_Register__c FROM Account WHERE Id = :l.ConvertedAccountId].Group_2_Pre_Register__c);
        System.assertEquals(false, leadByReg('PR3002').Group_2_Pre_Register__c);
    }

    @IsTest static void afterConversionNormalGroupStillCreatesOpportunity() {
        post(lead('PR3003', new List<Object>{ grp('UG_Group1', 'APP-1', null, null) }));
        Lead l = leadByReg('PR3003');
        convert(l.Id, null);
        l = leadByReg('PR3003');
        LeadConversionService.processSingleLead(new Map<String, Object>{
            'personAccountId' => String.valueOf(l.ConvertedAccountId), 'registrationNumber' => 'PR3003',
            'grpPrograms' => new List<Object>{ grp('UG_Group2', 'APP-2', null, null) } });
        System.assertEquals(2, [SELECT COUNT() FROM Opportunity WHERE AccountId = :l.ConvertedAccountId]);
        System.assertEquals('UG_Group2', [SELECT Group_2__c FROM Account WHERE Id = :l.ConvertedAccountId].Group_2__c);
    }

    @IsTest static void convertedLeadPayloadViaConversionApiSavesPreRegistration() {
        post(lead('PR3004', new List<Object>{ grp('UG_Group1', 'APP-1', null, null) }));
        Lead l = leadByReg('PR3004');
        convert(l.Id, null);
        Map<String, Object> res = convert(l.Id, new List<Object>{ grp('UG_Group3', 'APP-3', true, '2026-06-01') });
        l = leadByReg('PR3004');
        System.assertEquals(1, [SELECT COUNT() FROM Opportunity WHERE AccountId = :l.ConvertedAccountId], String.valueOf(res));
        System.assertEquals('UG_Group3', l.Group_2__c);
        System.assertEquals(true, [SELECT Group_2_Pre_Register__c FROM Account WHERE Id = :l.ConvertedAccountId].Group_2_Pre_Register__c);
    }

    @IsTest static void preRegisteredGroupGetsApplicationNumberAndDateFromConversionPayload() {
        post(lead('PR3005', new List<Object>{ grp('UG_Group1', 'APP-1', null, null) }));
        Lead l = leadByReg('PR3005');
        // Pre-registered through the webhook: no application number / date yet
        LeadConversionService.savePreRegistrationGroup(new Map<String, Object>{
            'leadId' => String.valueOf(l.Id), 'grptag' => 'UG_Group4', 'preRegister' => true, 'preRegistrationDate' => '2026-03-01' });
        System.assertEquals(null, [SELECT Group_2_Application_Number__c FROM Lead WHERE Id = :l.Id].Group_2_Application_Number__c);
        // Conversion payload sends the group again with the application number and date
        convert(l.Id, new List<Object>{ grp('UG_Group4', 'APP-4', true, '2026-03-01') });
        l = [SELECT Group_2_Application_Number__c, Group_2_Application_Date__c, Group_1_Application_Number__c, ConvertedAccountId FROM Lead WHERE Id = :l.Id];
        System.assertEquals('APP-4', l.Group_2_Application_Number__c);
        System.assertEquals(Date.newInstance(2026, 1, 14), l.Group_2_Application_Date__c);
        System.assertEquals('APP-1', l.Group_1_Application_Number__c, 'Normal group keeps its number');
        Account a = [SELECT Group_2_Application_Number__c, Group_2_Application_Date__c FROM Account WHERE Id = :l.ConvertedAccountId];
        System.assertEquals('APP-4', a.Group_2_Application_Number__c);
        System.assertEquals(Date.newInstance(2026, 1, 14), a.Group_2_Application_Date__c);
    }
}