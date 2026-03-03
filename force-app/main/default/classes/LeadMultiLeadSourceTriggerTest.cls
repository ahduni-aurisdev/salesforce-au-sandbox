@IsTest
public class LeadMultiLeadSourceTriggerTest {

    // Helper method to create a Lead that passes all validations
    private static Lead createSafeLead(String lastName, String msls, String leadSource, String leadStatus) {
        Lead l = new Lead();
        l.LastName = lastName;
        l.Company = 'TestCo';
        l.Status = leadStatus != null ? leadStatus : 'New';
        
        // Ensure phone OR email is populated (phone_or_email_not_be_empty validation)
        l.Email = 'test' + Math.random() + '@example.com';
        l.Phone = '9999999999'; // Valid phone number for Phone_Validation
        
        // Multi-select and LeadSource - Use actual picklist values from your org
        l.Multi_Select_Lead_Source__c = msls;
        l.LeadSource = leadSource;
        
        // Add Preferred_Programme__c from your screenshot
        l.Preferred_Programme__c = 'Master of Business Administration';
        
        // Handle Other_Lead_Source validation
        if (leadSource == 'Other') {
            l.Other_Lead_Source__c = 'Test Other Source';
        }

        // Handle Required_Rating_When_Lead_Source_Spoken validation
        if (leadStatus == 'Spoken') {
            l.Rating = 'Hot';
        }

        return l;
    }

    // Overloaded method for default lead status
    private static Lead createSafeLead(String lastName, String msls, String leadSource) {
        return createSafeLead(lastName, msls, leadSource, 'New');
    }

    // ---------------- TEST INSERT ----------------
    @IsTest
    static void testBeforeInsert() {
        // Using actual picklist values: Alumni and Email (both valid for both fields)
        Lead l = createSafeLead('InsertTest', 'Alumni;Email', 'Alumni');
        
        Test.startTest();
        insert l;
        Test.stopTest();

        Lead result = [
            SELECT Multi_Select_Lead_Source__c, LeadScore__c, Preferred_Programme__c
            FROM Lead
            WHERE Id = :l.Id
        ];

        // Alumni is already in multi-select, so NOT added again (removed then not re-added)
        System.assertEquals('Alumni;Email', result.Multi_Select_Lead_Source__c);
        System.assertEquals('Master of Business Administration', result.Preferred_Programme__c);
        // Score calculation: Alumni, Email = 2 items
        System.assertEquals(2, result.LeadScore__c);
    }

    // ---------------- TEST UPDATE ----------------
    @IsTest
    static void testBeforeUpdate() {
        // Create lead with initial values using valid picklist values
        Lead l = createSafeLead('UpdateTest', 'Alumni;Facebook', 'Email');
        insert l;
        
        // Verify initial state after insert
        Lead initial = [SELECT Multi_Select_Lead_Source__c FROM Lead WHERE Id = :l.Id];
        // Initial insert: 'Alumni;Facebook' + 'Email' (LeadSource) = 'Alumni;Email;Facebook'
        System.assertEquals('Alumni;Email;Facebook', initial.Multi_Select_Lead_Source__c);

        Test.startTest();
        // Update with new valid values
        l.Multi_Select_Lead_Source__c = 'Alumni;Google_ads;Facebook';
        l.LeadSource = 'Google_ads';
        update l;
        Test.stopTest();

        Lead result = [
            SELECT Multi_Select_Lead_Source__c, LeadScore__c
            FROM Lead
            WHERE Id = :l.Id
        ];

        // On UPDATE: Old values (Alumni;Email;Facebook) + new multi values (Alumni;Google_ads;Facebook) 
        // + LeadSource (Google_ads) = Alumni;Email;Facebook;Google_ads
        System.assertEquals('Alumni;Email;Facebook;Google_ads', result.Multi_Select_Lead_Source__c);
        // Score: 4 items
        System.assertEquals(4, result.LeadScore__c);
    }

    // ---------------- TEST BLANK LEADSOURCE ----------------
    @IsTest
    static void testBlankLeadSource() {
        Lead l = createSafeLead('BlankSourceTest', 'Alumni;Facebook', null);
        
        Test.startTest();
        insert l;
        Test.stopTest();

        Lead result = [
            SELECT Multi_Select_Lead_Source__c, LeadScore__c
            FROM Lead
            WHERE Id = :l.Id
        ];

        // LeadSource is blank, so trigger skips processing
        System.assertEquals('Alumni;Facebook', result.Multi_Select_Lead_Source__c);
        // LeadScore__c is NOT set when LeadSource is blank
        System.assertEquals(null, result.LeadScore__c);
    }

    // ---------------- TEST BULK INSERT ----------------
    @IsTest
    static void testBulkInsert() {
        List<Lead> listLeads = new List<Lead>();
        for (Integer i = 0; i < 5; i++) {
            // Use valid picklist values
            listLeads.add(createSafeLead('BulkTest' + i, 'Alumni;Facebook', 'Email'));
        }
        
        Test.startTest();
        insert listLeads;
        Test.stopTest();

        List<Lead> results = [SELECT Multi_Select_Lead_Source__c, LeadScore__c 
                              FROM Lead 
                              WHERE Id IN :listLeads];

        for (Lead leadResult : results) {
            // Each lead: 'Alumni;Facebook' + 'Email' (LeadSource) = 'Alumni;Email;Facebook'
            System.assertEquals('Alumni;Email;Facebook', leadResult.Multi_Select_Lead_Source__c);
            System.assertEquals(3, leadResult.LeadScore__c);
        }
    }
    
    // ---------------- TEST WITH "Other" LEAD SOURCE ----------------
    @IsTest
    static void testOtherLeadSource() {
        Lead l = createSafeLead('EventTest', 'Alumni;Facebook', 'Event');
        
        Test.startTest();
        insert l;
        Test.stopTest();

        Lead result = [
            SELECT Multi_Select_Lead_Source__c, LeadScore__c
            FROM Lead
            WHERE Id = :l.Id
        ];

        // Alumni;Facebook + Event = Alumni;Event;Facebook (alphabetical order)
        System.assertEquals('Alumni;Event;Facebook', result.Multi_Select_Lead_Source__c);
        System.assertEquals(3, result.LeadScore__c);
    }
    
    // ---------------- TEST DUPLICATE HANDLING ----------------
    @IsTest
    static void testDuplicateHandling() {
        // Test with LeadSource already in Multi_Select_Lead_Source__c
        Lead l = createSafeLead('DuplicateTest', 'Alumni;Email;Facebook', 'Alumni');
        
        Test.startTest();
        insert l;
        Test.stopTest();

        Lead result = [
            SELECT Multi_Select_Lead_Source__c, LeadScore__c
            FROM Lead
            WHERE Id = :l.Id
        ];

        // Alumni already in multi-select, so NOT added again as LeadSource
        System.assertEquals('Alumni;Email;Facebook', result.Multi_Select_Lead_Source__c);
        System.assertEquals(3, result.LeadScore__c);
    }
    
    // ---------------- TEST UPDATE ONLY LEAD SOURCE ----------------
    @IsTest
    static void testUpdateOnlyLeadSource() {
        // Create lead
        Lead l = createSafeLead('UpdateLeadSourceOnly', 'Alumni;Facebook', 'Email');
        insert l;
        
        Test.startTest();
        // Only change LeadSource, keep Multi_Select_Lead_Source__c same
        l.LeadSource = 'Google_ads';
        update l;
        Test.stopTest();

        Lead result = [
            SELECT Multi_Select_Lead_Source__c, LeadScore__c
            FROM Lead
            WHERE Id = :l.Id
        ];

        // Old values: Alumni;Email;Facebook + new LeadSource (Google_ads)
        System.assertEquals('Alumni;Email;Facebook;Google_ads', result.Multi_Select_Lead_Source__c);
        System.assertEquals(4, result.LeadScore__c);
    }
    
    // ---------------- TEST UPDATE WITH EMPTY MULTI-SELECT ----------------
    @IsTest
    static void testUpdateWithEmptyMultiSelect() {
        // Create lead
        Lead l = createSafeLead('UpdateEmptyMulti', 'Alumni;Facebook', 'Email');
        insert l;
        
        Test.startTest();
        // Set Multi_Select_Lead_Source__c to empty
        l.Multi_Select_Lead_Source__c = '';
        l.LeadSource = 'Google_ads';
        update l;
        Test.stopTest();

        Lead result = [
            SELECT Multi_Select_Lead_Source__c, LeadScore__c
            FROM Lead
            WHERE Id = :l.Id
        ];

        // Old values: Alumni;Email;Facebook + empty multi + new LeadSource (Google_ads)
        System.assertEquals('Alumni;Email;Facebook;Google_ads', result.Multi_Select_Lead_Source__c);
        System.assertEquals(4, result.LeadScore__c);
    }
    
    // ---------------- TEST CASE SENSITIVITY ----------------
    @IsTest
    static void testCaseSensitivity() {
        // Test 1: Normal case
        Lead l = createSafeLead('CaseTest', 'Alumni;Facebook', 'Email');
        
        Test.startTest();
        insert l;
        Test.stopTest();

        Lead result = [
            SELECT Multi_Select_Lead_Source__c
            FROM Lead
            WHERE Id = :l.Id
        ];

        System.assertEquals('Alumni;Email;Facebook', result.Multi_Select_Lead_Source__c);
        
        // Test 2: Meta_ads conversion
        Lead l2 = createSafeLead('CaseTest2', 'Alumni', 'meta_ads');
        insert l2;
        
        Lead result2 = [
            SELECT Multi_Select_Lead_Source__c
            FROM Lead
            WHERE Id = :l2.Id
        ];
        
        // Should convert lowercase "meta_ads" to "Meta_Ads"
        System.assertEquals('Alumni;Meta_Ads', result2.Multi_Select_Lead_Source__c);
    }
    
    // ---------------- TEST WITH SPACES IN VALUES ----------------
    @IsTest
    static void testSpacesInValues() {
        Lead l = createSafeLead('SpacesTest', 'Alumni;Corporate Partner Visit', 'Event');
        
        Test.startTest();
        insert l;
        Test.stopTest();

        Lead result = [
            SELECT Multi_Select_Lead_Source__c, LeadScore__c
            FROM Lead
            WHERE Id = :l.Id
        ];

        // Values with spaces should be preserved
        System.assertEquals('Alumni;Corporate Partner Visit;Event', result.Multi_Select_Lead_Source__c);
        System.assertEquals(3, result.LeadScore__c);
    }
    
    // ---------------- TEST CHECK VALIDATION RULES ----------------
    @IsTest
    static void testCheckValidationRules() {
        Lead testLead = new Lead(
            LastName = 'ValidationTest',
            Company = 'TestCo',
            Status = 'New',
            Email = 'test@example.com',
            Phone = '9999999999',
            LeadSource = 'Alumni',
            Multi_Select_Lead_Source__c = 'Alumni;Facebook',
            Preferred_Programme__c = 'Master of Business Administration'
        );
        
        Test.startTest();
        try {
            insert testLead;
            // If we get here, validation passed
            System.assert(true, 'Lead inserted successfully');
        } catch (Exception e) {
            // If validation fails, the test should fail
            System.assert(false, 'Validation error: ' + e.getMessage());
        }
        Test.stopTest();
    }
    
    // ---------------- TEST META ADS FIX ----------------
    @IsTest
    static void testMetaAdsFix() {
        // Test 1: LeadSource = "Meta Ads" (Label from UI)
        Lead l1 = createSafeLead('MetaAdsTest1', 'Alumni;Facebook', 'Meta Ads');
        
        Test.startTest();
        insert l1;
        Test.stopTest();

        Lead result1 = [
            SELECT Multi_Select_Lead_Source__c, LeadScore__c
            FROM Lead
            WHERE Id = :l1.Id
        ];

        // Should convert "Meta Ads" to "Meta_Ads"
        System.assertEquals('Alumni;Facebook;Meta_Ads', result1.Multi_Select_Lead_Source__c);
        System.assertEquals(3, result1.LeadScore__c);
        
        // Test 2: LeadSource = "Meta_Ads" (API name - already correct)
        Lead l2 = createSafeLead('MetaAdsTest2', 'Email;Google_ads', 'Meta_Ads');
        
        insert l2;
        
        Lead result2 = [
            SELECT Multi_Select_Lead_Source__c
            FROM Lead
            WHERE Id = :l2.Id
        ];

        // Should keep "Meta_Ads" as-is
        System.assertEquals('Email;Google_ads;Meta_Ads', result2.Multi_Select_Lead_Source__c);
        
        // Test 3: Update from other source to Meta Ads
        Lead l3 = createSafeLead('MetaAdsTest3', 'Alumni', 'Email');
        insert l3;
        
        l3.LeadSource = 'Meta Ads'; // Update to Meta Ads
        update l3;
        
        Lead result3 = [
            SELECT Multi_Select_Lead_Source__c
            FROM Lead
            WHERE Id = :l3.Id
        ];
        
        // Should have old values + converted Meta_Ads
        System.assertEquals('Alumni;Email;Meta_Ads', result3.Multi_Select_Lead_Source__c);
    }
}