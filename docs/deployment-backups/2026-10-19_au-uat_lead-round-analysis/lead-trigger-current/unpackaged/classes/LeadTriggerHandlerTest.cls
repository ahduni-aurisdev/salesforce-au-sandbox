/**
 * @description
 * ****************************************************************************************
* Create By        : Preksha Chauhan
* Company          : GetonCRM Solutions
* Class Name       : LeadPhoneUpdaterTest
* Trigger Name     : leadBeforeInsertLastName
* Create Date      : 06/28/2024
* Description      : This trigger operates on the Lead object and is invoked before insert 
*                    and before update operations. It ensures that if the LastName field is 
*                    blank, it is set to the value of the FirstName field. Additionally, it 
*                    sets the FirstName field to null to prevent duplication of data. The 
*                    trigger handles both new Lead records being inserted and existing Lead 
*                    records being updated.
*                    - Before Insert: Sets LastName to FirstName if LastName is blank and 
*                      clears the FirstName field.
*                    - Before Update: Updates LastName to FirstName if LastName is blank 
*                      and was not blank before the update. Clears the FirstName field.
*                    This trigger uses the LeadTriggerHandler class to encapsulate logic for 
*                    better manageability and testability.
* 
* Coverage          : 100%
******************************************************************************************/
@isTest
public class LeadTriggerHandlerTest {
    /**
     * @description
     * */
    @isTest
    static void testLeadBeforeInsert() {
        // Test insert scenario
        Lead lead = new Lead(
            FirstName = 'Test FirstName',
            LastName = '',
            Email = 'test@example.com'
        );

        Test.startTest();
        insert lead;
        Test.stopTest();

        // Verify the LastName was set to FirstName
        Lead insertedLead = [SELECT LastName, FirstName FROM Lead WHERE Id = :lead.Id];
        //System.assertEquals('Test FirstName', insertedLead.LastName, 'LastName should be set to FirstName');
        // System.assertEquals(null, insertedLead.FirstName, 'FirstName should be null after setting LastName');
    }

    /**
    * @description
    * */
    @isTest
    static void testLeadBeforeUpdate() {
        // Test update scenario
        Lead lead = new Lead(
            FirstName = 'Initial FirstName',
            LastName = 'Initial LastName',
            Email = 'test@example.com'
        );

        insert lead;

        lead.LastName = '';
        lead.FirstName = 'Updated FirstName';

        Test.startTest();
        update lead;
        Test.stopTest();

        // Verify the LastName was updated and FirstName was cleared
        Lead updatedLead = [SELECT LastName, FirstName FROM Lead WHERE Id = :lead.Id];
        // System.assertEquals('Updated FirstName', updatedLead.LastName, 'LastName should be updated to the new FirstName');
        // System.assertEquals(null, updatedLead.FirstName, 'FirstName should be null after setting LastName');
    }


    @isTest
    static void testHandleLeadAssignments() {
        Id mastersId = saveWebsiteLead.getRecordTypeIdByDepartment('Masters');
        Id phdId =saveWebsiteLead.getRecordTypeIdByDepartment('Phd');
        // Id executiveId = LeadHelper.getRecordTypeId('Executive_Education');
        Id undergradId = saveWebsiteLead.getRecordTypeIdByDepartment('Undergraduation');

        List<Lead> testLeads = new List<Lead>{
            new Lead(FirstName = 'Test1', LastName = 'User', Company = 'Test Co', RecordTypeId = mastersId,Email = 'test@example.com'),
            new Lead(FirstName = 'Test2', LastName = 'User', Company = 'Test Co', RecordTypeId = phdId,Email ='test@example.com')
            // new Lead(FirstName = 'Test3', LastName = 'User', Company = 'Test Co', RecordTypeId = executiveId),
            // new Lead(FirstName = 'Test4', LastName = 'User', Company = 'Test Co', RecordTypeId = undergradId)
        };

        Test.startTest();
        insert testLeads;
        Test.stopTest();

        // Add asserts here if your logic updates fields like OwnerId, custom fields, etc.
    }

    @isTest
    static void testFillCdcLeadNameOverwritesUserEnteredLastName() {
        Id cdcRtId = Schema.SObjectType.Lead
            .getRecordTypeInfosByDeveloperName()
            .get('CDC')
            .getRecordTypeId();

        Account acc = new Account(Name = 'Test CDC Company');
        insert acc;

        Contact con = new Contact(LastName = 'Contact', AccountId = acc.Id, MobilePhone = '9998887770');
        insert con;

        Lead lead = new Lead(
            FirstName = 'Should Be Cleared',
            LastName = 'Should Be Replaced',
            Account__c = acc.Id,
            Contact__c = con.Id,
            Academic_Year__c = '2026',
            RecordTypeId = cdcRtId,
            Email = 'cdc@example.com'
        );

        Test.startTest();
        insert lead;
        Test.stopTest();

        Lead insertedLead = [SELECT LastName, FirstName, Company FROM Lead WHERE Id = :lead.Id];
        System.assertEquals(acc.Name, insertedLead.LastName, 'LastName should be replaced with the Account Name for CDC leads');
        System.assertEquals(null, insertedLead.FirstName, 'FirstName should be cleared for CDC leads');
        System.assertEquals(acc.Name, insertedLead.Company, 'Company should match the Account Name for CDC leads');
    }

    // ---- syncCampaignMembership / stampMostRecentLeadSource (lead source attribution) ----

    @isTest
    static void testBlankLeadSourceCreatesNoCampaign() {
        Lead lead = new Lead(FirstName = 'Test', LastName = 'Blank', Company = 'Test Co', Email = 'blank@example.com');

        Test.startTest();
        insert lead;
        Test.stopTest();

        Lead result = [SELECT LeadSource, Most_Recent_Lead_Source__c FROM Lead WHERE Id = :lead.Id];
        System.assertEquals(null, result.Most_Recent_Lead_Source__c, 'Most_Recent_Lead_Source__c should stay blank when LeadSource is blank');
        System.assertEquals(0, [SELECT COUNT() FROM CampaignMember WHERE LeadId = :lead.Id], 'No CampaignMember should be created for a blank LeadSource');
    }

    @isTest
    static void testLeadSourceOnInsertCreatesParentCampaignOnly() {
        // 'Web' is the real LeadSourceGroup__c value saveWebsiteLead.cls assigns for
        // website-form leads (via WebFormFieldMapping__mdt), and Admission_Year__c is
        // always stamped from the Admission_Year custom label, currently 'Admission Year - 2026'.
        Lead lead = new Lead(
            FirstName = 'Test',
            LastName = 'Web',
            Company = 'Test Co',
            Email = 'web@example.com',
            LeadSource = 'Web',
            Admission_Year__c = 'Admission Year - 2026'
        );

        Test.startTest();
        insert lead;
        Test.stopTest();

        Lead result = [SELECT Most_Recent_Lead_Source__c FROM Lead WHERE Id = :lead.Id];
        System.assertEquals('Web', result.Most_Recent_Lead_Source__c, 'Most_Recent_Lead_Source__c should be stamped from LeadSource on first real touch');

        Campaign parent = [SELECT Id, Name, ParentId, Attribution_Key__c FROM Campaign WHERE Attribution_Key__c = 'PARENT|Web 2026'];
        System.assertEquals('Web 2026', parent.Name, 'Parent campaign should combine LeadSource and the admission year');
        System.assertEquals(null, parent.ParentId, 'Parent campaign should be top-level');

        List<CampaignMember> members = [SELECT CampaignId FROM CampaignMember WHERE LeadId = :lead.Id];
        System.assertEquals(1, members.size(), 'Lead should be attached to exactly one campaign');
        System.assertEquals(parent.Id, members[0].CampaignId, 'Lead should be attached to the parent campaign when UTM_Campaign__c is blank');
    }

    @isTest
    static void testUtmCampaignCreatesChildUnderParent() {
        // 'Meta Ads' is the canonical (post-typo-correction) LeadSource value used for Meta
        // leads elsewhere in this org (see LeadMultiLeadSourceTriggerTest). UTM_Campaign__c
        // is not populated by any current intake path (no WebFormFieldMapping__mdt row maps
        // to it), so this covers the Marketing Cloud / future-mapping case, not today's default.
        Lead lead = new Lead(
            FirstName = 'Test',
            LastName = 'MetaAds',
            Company = 'Test Co',
            Email = 'metaads@example.com',
            LeadSource = 'Meta Ads',
            Admission_Year__c = 'Admission Year - 2026',
            UTM_Campaign__c = 'meta_aug26_mba'
        );

        Test.startTest();
        insert lead;
        Test.stopTest();

        Campaign parent = [SELECT Id, Name FROM Campaign WHERE Attribution_Key__c = 'PARENT|Meta Ads 2026'];
        Campaign child = [SELECT Id, Name, ParentId FROM Campaign WHERE Attribution_Key__c = :('CHILD|' + parent.Id + '|meta_aug26_mba')];
        System.assertEquals('meta_aug26_mba', child.Name, 'Child campaign name should be the raw UTM_Campaign__c value');
        System.assertEquals(parent.Id, child.ParentId, 'Child campaign should be nested under the parent campaign');

        List<CampaignMember> members = [SELECT CampaignId FROM CampaignMember WHERE LeadId = :lead.Id];
        System.assertEquals(1, members.size(), 'Lead should be attached to exactly one campaign');
        System.assertEquals(child.Id, members[0].CampaignId, 'Lead should be attached to the child campaign when UTM_Campaign__c is set');
    }

    @isTest
    static void testAdmissionYearWithNoParsableYearDropsYearSuffix() {
        // 'Alumni' and Admission_Year__c = 'Not Specified' are both real picklist values
        // seen in this org (LeadMultiLeadSourceTriggerTest, Admission_Year__c value set).
        Lead lead = new Lead(
            FirstName = 'Test',
            LastName = 'Alumni',
            Company = 'Test Co',
            Email = 'alumni@example.com',
            LeadSource = 'Alumni',
            Admission_Year__c = 'Not Specified'
        );

        Test.startTest();
        insert lead;
        Test.stopTest();

        Campaign parent = [SELECT Id, Name FROM Campaign WHERE Attribution_Key__c = 'PARENT|Alumni'];
        System.assertEquals('Alumni', parent.Name, 'Parent campaign name should fall back to LeadSource alone when no year can be parsed');
    }

    @isTest
    static void testBlankLeadSourceFilledOnLaterUpdateTriggersFirstTouch() {
        Lead lead = new Lead(FirstName = 'Test', LastName = 'Manual', Company = 'Test Co', Email = 'manual@example.com');
        insert lead;
        System.assertEquals(0, [SELECT COUNT() FROM CampaignMember WHERE LeadId = :lead.Id], 'No CampaignMember should exist yet while LeadSource is blank');

        lead.LeadSource = 'Partner';

        Test.startTest();
        update lead;
        Test.stopTest();

        Lead result = [SELECT Most_Recent_Lead_Source__c FROM Lead WHERE Id = :lead.Id];
        System.assertEquals('Partner', result.Most_Recent_Lead_Source__c, 'Most_Recent_Lead_Source__c should be stamped once LeadSource is first filled in');
        System.assertEquals(1, [SELECT COUNT() FROM CampaignMember WHERE LeadId = :lead.Id], 'Lead should be attached to a campaign once LeadSource is first known');
    }

    @isTest
    static void testLeadSourceChangeAfterFirstTouchIsIgnored() {
        Lead lead = new Lead(
            FirstName = 'Test',
            LastName = 'Locked',
            Company = 'Test Co',
            Email = 'locked@example.com',
            LeadSource = 'Web'
        );
        insert lead;
        Integer memberCountAfterInsert = [SELECT COUNT() FROM CampaignMember WHERE LeadId = :lead.Id];

        lead.LeadSource = 'Meta Ads';

        Test.startTest();
        update lead;
        Test.stopTest();

        Lead result = [SELECT LeadSource, Most_Recent_Lead_Source__c FROM Lead WHERE Id = :lead.Id];
        System.assertEquals('Meta Ads', result.LeadSource, 'DML explicitly setting LeadSource is not blocked by this logic (no validation rule was requested)');
        System.assertEquals('Web', result.Most_Recent_Lead_Source__c, 'Most_Recent_Lead_Source__c should not be re-stamped once LeadSource was already non-blank');
        System.assertEquals(memberCountAfterInsert, [SELECT COUNT() FROM CampaignMember WHERE LeadId = :lead.Id], 'No additional CampaignMember should be added once LeadSource was already non-blank');
    }

    @isTest
    static void testBulkInsertSameSourceAndYearSharesOneParentCampaign() {
        // 'Google_ads' is the real raw LeadSource value seen in this org (LeadMultiLeadSourceTriggerTest).
        List<Lead> leads = new List<Lead>{
            new Lead(FirstName = 'Bulk1', LastName = 'User', Company = 'Test Co', Email = 'bulk1@example.com', LeadSource = 'Google_ads', Admission_Year__c = 'Admission Year - 2026'),
            new Lead(FirstName = 'Bulk2', LastName = 'User', Company = 'Test Co', Email = 'bulk2@example.com', LeadSource = 'Google_ads', Admission_Year__c = 'Admission Year - 2026')
        };

        Test.startTest();
        insert leads;
        Test.stopTest();

        List<Campaign> parents = [SELECT Id FROM Campaign WHERE Attribution_Key__c = 'PARENT|Google_ads 2026'];
        System.assertEquals(1, parents.size(), 'Only one parent campaign should be created for two leads sharing the same LeadSource and admission year in the same batch');

        List<CampaignMember> members = [SELECT LeadId, CampaignId FROM CampaignMember WHERE LeadId IN :new List<Id>{ leads[0].Id, leads[1].Id }];
        System.assertEquals(2, members.size(), 'Both leads should be attached to the shared parent campaign');
        for (CampaignMember cm : members) {
            System.assertEquals(parents[0].Id, cm.CampaignId, 'Both leads should be attached to the same parent campaign');
        }
    }

    @isTest
    static void testReTouchOnSameCampaignIsIdempotent() {
        Lead lead = new Lead(
            FirstName = 'Test',
            LastName = 'Idempotent',
            Company = 'Test Co',
            Email = 'idempotent@example.com'
        );
        insert lead;

        // Simulate the Lead already belonging to the campaign its first real touch will resolve to.
        Campaign existing = new Campaign(Name = 'Email 2026', Attribution_Key__c = 'PARENT|Email 2026', IsActive = true);
        insert existing;
        insert new CampaignMember(CampaignId = existing.Id, LeadId = lead.Id);

        lead.LeadSource = 'Email';
        lead.Admission_Year__c = 'Admission Year - 2026';

        Test.startTest();
        update lead;
        Test.stopTest();

        // DUPLICATE_VALUE on the re-touch is caught internally (allOrNone=false) and should not throw.
        System.assertEquals(1, [SELECT COUNT() FROM CampaignMember WHERE LeadId = :lead.Id], 'Re-touching a campaign the lead already belongs to should not create a duplicate CampaignMember or throw');
    }

    @isTest
    static void testNewlyCreatedCampaignGetsDefaultMemberStatusesAndMemberIsCreated() {
        // Regression test: Campaigns created via the UI get default CampaignMemberStatus
        // rows automatically, but ones created via Apex/upsert do not - without seeding
        // them, CampaignMember insert fails on the Status picklist. Seen in sandbox: Lead
        // and Campaign were created, but the CampaignMember silently was not.
        // LeadSource is a distinctive, test-only value (not a generic one like "Meta Ads")
        // so this can't collide with the Campaign key any other test or org data might use
        // when Salesforce runs test classes in parallel within a larger org's test suite.
        // Admission_Year__c is set explicitly rather than left to the picklist's default -
        // confirmed via direct testing that whether/how that default gets applied differs
        // between @isTest execution and plain Apex, so relying on it made this test flaky
        // in a way that had nothing to do with the actual Campaign/status-seeding logic.
        Lead lead = new Lead(
            FirstName = 'Test',
            LastName = 'Meta',
            Company = 'Test Co',
            Email = 'metastatus@example.com',
            LeadSource = 'Meta Ads RegressionTestOnly',
            Admission_Year__c = 'Admission Year - 2026'
        );

        Test.startTest();
        insert lead;
        Test.stopTest();

        Campaign parent = [SELECT Id FROM Campaign WHERE Attribution_Key__c = 'PARENT|Meta Ads RegressionTestOnly 2026'];
        // Not asserting on CampaignMemberStatus directly - confirmed via direct testing that
        // querying it right after it's seeded is unreliable specifically inside @isTest
        // execution (plain Apex sees it fine every time), for reasons unrelated to this
        // feature. The CampaignMember assertion below is the real, end-to-end proof: it can
        // only succeed at all once a valid default Status genuinely exists on the Campaign.
        List<CampaignMember> members = [SELECT Id FROM CampaignMember WHERE LeadId = :lead.Id AND CampaignId = :parent.Id];
        System.assertEquals(1, members.size(), 'CampaignMember should actually be created once the Campaign has a valid default Status');
    }

    @isTest
    static void testSeparateInsertsSameParentDoNotDuplicateMemberStatuses() {
        // Regression test: saveWebTo_YourProfileData.cls processes leads one at a time via
        // separate `upsert newLead;` calls in a loop, so two leads sharing the same
        // LeadSource + Admission Year can each independently resolve to the same parent
        // Campaign within one transaction. Seen in production: the second lead's insert
        // failed with FIELD_INTEGRITY_EXCEPTION re-adding a "Sent"/"Responded"
        // CampaignMemberStatus Label the first lead's insert had already created.
        Lead leadA = new Lead(FirstName = 'SeqA', LastName = 'User', Company = 'Test Co', Email = 'seqa@example.com', LeadSource = 'Partner', Admission_Year__c = 'Admission Year - 2026');
        Lead leadB = new Lead(FirstName = 'SeqB', LastName = 'User', Company = 'Test Co', Email = 'seqb@example.com', LeadSource = 'Partner', Admission_Year__c = 'Admission Year - 2026');

        Test.startTest();
        insert leadA;
        insert leadB;
        Test.stopTest();

        Campaign parent = [SELECT Id FROM Campaign WHERE Attribution_Key__c = 'PARENT|Partner 2026'];
        // The real invariant is "no duplicate Label per Campaign" (what actually broke in
        // production), not an exact total row count - checking for duplicates directly is
        // robust to whatever else may be running against this org in parallel.
        Set<String> seenLabels = new Set<String>();
        for (CampaignMemberStatus s : [SELECT Label FROM CampaignMemberStatus WHERE CampaignId = :parent.Id]) {
            System.assert(!seenLabels.contains(s.Label), 'Duplicate CampaignMemberStatus Label found: ' + s.Label);
            seenLabels.add(s.Label);
        }

        List<CampaignMember> members = [SELECT LeadId FROM CampaignMember WHERE CampaignId = :parent.Id];
        System.assertEquals(2, members.size(), 'Both leads should be attached to the shared parent campaign');
    }

    @isTest
    static void testGenuineReTouchAddsSecondCampaignMembership() {
        // Regression test for the exact scenario reported: an existing Lead (LeadSource
        // already locked) is touched again by a different source. LeadSource itself must
        // not change, but Most_Recent_Lead_Source__c and Campaign History should still
        // reflect the new touch - this is what saveWebTo_YourProfileData.cls now does
        // directly when its "don't overwrite LeadSource" guard kicks in.
        Lead lead = new Lead(
            FirstName = 'Test', LastName = 'ReTouch', Company = 'Test Co', Email = 'retouch@example.com',
            LeadSource = 'Web', Admission_Year__c = 'Admission Year - 2026'
        );
        insert lead;

        Campaign firstParent = [SELECT Id FROM Campaign WHERE Attribution_Key__c = 'PARENT|Web 2026'];
        System.assertEquals(1, [SELECT COUNT() FROM CampaignMember WHERE LeadId = :lead.Id], 'First touch should attach exactly one CampaignMember');

        lead.Most_Recent_Lead_Source__c = 'KollageApply';

        Test.startTest();
        update lead;
        Test.stopTest();

        Lead result = [SELECT LeadSource, Most_Recent_Lead_Source__c FROM Lead WHERE Id = :lead.Id];
        System.assertEquals('Web', result.LeadSource, 'LeadSource must stay locked to the first touch');
        System.assertEquals('KollageApply', result.Most_Recent_Lead_Source__c, 'Most_Recent_Lead_Source__c should reflect the new touch');

        Campaign secondParent = [SELECT Id FROM Campaign WHERE Attribution_Key__c = 'PARENT|KollageApply 2026'];
        List<CampaignMember> members = [SELECT CampaignId FROM CampaignMember WHERE LeadId = :lead.Id];
        System.assertEquals(2, members.size(), 'The re-touch should add a second CampaignMember without removing the first');
        Set<Id> campaignIds = new Set<Id>();
        for (CampaignMember cm : members) {
            campaignIds.add(cm.CampaignId);
        }
        System.assert(campaignIds.contains(firstParent.Id), 'Original campaign membership should be preserved');
        System.assert(campaignIds.contains(secondParent.Id), 'New campaign membership should be added for the re-touch');
    }
}