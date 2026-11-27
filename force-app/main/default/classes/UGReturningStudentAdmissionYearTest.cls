/**
 * @description Tests for UG returning students who apply again for a new admission year:
 *              a new Lead and a new Opportunity are created for the new admission year, the
 *              earlier year's Lead and Opportunity are left unchanged, and the student keeps
 *              one person Account.
 *              Covers saveWebTo_YourProfileData.handleDuplicateLeadUndergraduation and
 *              LeadConversionService (Branch A, Branch B and the personAccountId route).
 * @author Jitendra Varma
 * @date 2026-11-27
 * @version 1.0
 * @lastModified 2026-11-27
 */
@IsTest
private class UGReturningStudentAdmissionYearTest {

    private static final String YEAR_2026 = 'Admission Year - 2026';
    private static final String YEAR_2027 = 'Admission Year - 2027';
    private static final String GROUP_TAG = 'UG_Management_Commerce_Arts_and_Sciences';
    private static final String EMAIL = 'returning.student@test.com';
    private static final String PHONE = '9876500001';
    private static final String REG_2026 = 'UG2026-TEST-0001';
    private static final String REG_2027 = 'UG2027-TEST-0001';
    private static final String APP_2026 = 'UG2026-APP-0001';
    private static final String APP_2027 = 'UG2027-APP-0001';
    private static final String PROGRAMME_2026 = 'Bachelor of Commerce (Honours)';
    private static final String PROGRAMME_2027 = 'Bachelor of Science in Management (Honours)';
    private static final String PROGRAMME_2027_CHANGED = 'Bachelor of Arts (Honours)';
    private static final Integer BULK_SIZE = 200;
    private static final String DEFAULT_ASSIGNMENT_KEY = 'default';

    // =========================================================================
    // SETUP
    // =========================================================================

    /**
     * UG Lead round-robin counter for the default assignment group, with State_Code__c set.
     * LeadAssignmentForUnderGraduation otherwise creates this counter without State_Code__c on
     * the first UG Lead and then fails (null State_Code__c) on the next UG Lead in the same test,
     * in orgs where the assignment users exist (Production). Not related to the code under test.
     */
    @TestSetup
    static void setup() {
        insert new Lead_Assignment_Tracker_for_Undergrad__c(
            Name          = DEFAULT_ASSIGNMENT_KEY,
            State__c      = DEFAULT_ASSIGNMENT_KEY,
            State_Code__c = DEFAULT_ASSIGNMENT_KEY,
            Counter__c    = 0
        );
    }

    // =========================================================================
    // HELPERS
    // =========================================================================

    /** Posts a UG Auris Registration Form payload to saveLeadRelatedData. */
    private static void register(String registrationNumber, String admissionYear) {
        Map<String, Object> payload = new Map<String, Object>{
            'department'         => 'Undergraduation',
            'typeOfForm'         => 'Auris_Registration_Form',
            'registrationNumber' => registrationNumber,
            'firstName'          => 'Returning',
            'lastName'           => 'Student',
            'email'              => EMAIL,
            'phone'              => PHONE,
            'mobile'             => PHONE,
            'admissionYear'      => admissionYear
        };
        RestRequest req = new RestRequest();
        req.requestUri  = '/services/apexrest/saveLeadRelatedData/';
        req.httpMethod  = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(payload));
        RestContext.request  = req;
        RestContext.response = new RestResponse();
        saveWebTo_YourProfileData.handleAurisData();
        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString());
        List<Object> errors = (List<Object>) response.get('errors');
        System.assert(errors == null || errors.isEmpty(),
            'Registration ' + registrationNumber + ' must succeed. Errors: ' + errors);
    }

    /** One grpPrograms entry for GROUP_TAG with a single programme. */
    private static List<Object> groups(String applicationNumber, String programme) {
        return new List<Object>{
            new Map<String, Object>{
                'grptag'            => GROUP_TAG,
                'applicationNumber' => applicationNumber,
                'applicationDate'   => '2026-11-01',
                'programmes'        => new List<Object>{
                    new Map<String, Object>{ 'programInterestedIn' => programme, 'major' => 'Finance' }
                }
            }
        };
    }

    /** Sends a conversion payload for a Lead through LeadConversionService. */
    private static Map<String, Object> convert(Id leadId, String registrationNumber, String admissionYear,
            String applicationNumber, String programme) {
        return LeadConversionService.processSingleLead(new Map<String, Object>{
            'leadId'             => String.valueOf(leadId),
            'leadStatus'         => System.label.LeadToOppootunityConversionStage,
            'registrationNumber' => registrationNumber,
            'admissionYear'      => admissionYear,
            'grpPrograms'        => groups(applicationNumber, programme)
        });
    }

    private static List<Lead> studentLeads() {
        return [SELECT Id, Registration_Number__c, Admission_Year__c, IsConverted, ConvertedAccountId
                FROM Lead WHERE Email = :EMAIL ORDER BY CreatedDate ASC, Id ASC];
    }

    private static Lead leadByRegistration(String registrationNumber) {
        return [SELECT Id, Registration_Number__c, Admission_Year__c, IsConverted, ConvertedAccountId
                FROM Lead WHERE Registration_Number__c = :registrationNumber LIMIT 1];
    }

    private static Map<String, Opportunity> oppsByYear(Id accountId) {
        Map<String, Opportunity> byYear = new Map<String, Opportunity>();
        for (Opportunity o : [SELECT Id, Admission_Year__c, Application_Number__c, Program_Group_Tag__c,
                                     Primary_Preferred_Program__c
                              FROM Opportunity WHERE AccountId = :accountId]) {
            byYear.put(o.Admission_Year__c, o);
        }
        return byYear;
    }

    /** Registers and converts the student's 2026 application; returns the 2026 Lead. */
    private static Lead createConverted2026Student() {
        register(REG_2026, YEAR_2026);
        Lead lead2026 = leadByRegistration(REG_2026);
        convert(lead2026.Id, REG_2026, YEAR_2026, APP_2026, PROGRAMME_2026);
        lead2026 = leadByRegistration(REG_2026);
        System.assert(lead2026.IsConverted, 'Setup: the 2026 Lead must be converted.');
        return lead2026;
    }

    // =========================================================================
    // 1. Lead matching (saveWebTo_YourProfileData)
    // =========================================================================

    @IsTest
    static void newAdmissionYear_createsNewLead_andKeepsEarlierLead() {
        register(REG_2026, YEAR_2026);

        Test.startTest();
        register(REG_2027, YEAR_2027);
        Test.stopTest();

        List<Lead> leads = studentLeads();
        System.assertEquals(2, leads.size(), 'A new admission year must create a second Lead.');
        System.assertEquals(REG_2026, leads[0].Registration_Number__c, 'The 2026 Lead must keep its Registration Number.');
        System.assertEquals(YEAR_2026, leads[0].Admission_Year__c, 'The 2026 Lead must keep its Admission Year.');
        System.assertEquals(REG_2027, leads[1].Registration_Number__c, 'The new Lead must carry the 2027 Registration Number.');
        System.assertEquals(YEAR_2027, leads[1].Admission_Year__c, 'The new Lead must carry the 2027 Admission Year.');
    }

    @IsTest
    static void sameAdmissionYear_updatesExistingLead() {
        register(REG_2027, YEAR_2027);

        Test.startTest();
        register('UG2027-TEST-0002', YEAR_2027);
        Test.stopTest();

        List<Lead> leads = studentLeads();
        System.assertEquals(1, leads.size(), 'Same Email + Phone in the same admission year must reuse the Lead.');
        System.assertEquals('UG2027-TEST-0002', leads[0].Registration_Number__c,
            'The existing Lead must be updated with the incoming Registration Number.');
    }

    // =========================================================================
    // 2. Conversion - Branch A (new-year Lead converts into the existing Account)
    // =========================================================================

    @IsTest
    static void returningStudent_newLeadConvertsIntoExistingAccount() {
        Lead lead2026 = createConverted2026Student();
        register(REG_2027, YEAR_2027);
        Lead lead2027 = leadByRegistration(REG_2027);
        System.assertNotEquals(lead2026.Id, lead2027.Id, 'Setup: the 2027 application must have its own Lead.');

        Test.startTest();
        Map<String, Object> response = convert(lead2027.Id, REG_2027, YEAR_2027, APP_2027, PROGRAMME_2027);
        Test.stopTest();

        lead2027 = leadByRegistration(REG_2027);
        System.assert(lead2027.IsConverted, 'The 2027 Lead must be converted. Response: ' + response);
        System.assertEquals(lead2026.ConvertedAccountId, lead2027.ConvertedAccountId,
            'The 2027 Lead must convert into the student\'s existing Account.');

        Map<String, Opportunity> byYear = oppsByYear(lead2026.ConvertedAccountId);
        System.assertEquals(2, byYear.size(), 'The Account must hold one Opportunity per admission year.');
        System.assertEquals(PROGRAMME_2026, byYear.get(YEAR_2026).Primary_Preferred_Program__c,
            'The 2026 Opportunity must keep its programme.');
        System.assertEquals(PROGRAMME_2027, byYear.get(YEAR_2027).Primary_Preferred_Program__c,
            'The 2027 Opportunity must carry the 2027 programme.');
    }

    // =========================================================================
    // 3. Conversion - Branch B (already-converted Lead re-sent for a new year)
    // =========================================================================

    @IsTest
    static void convertedLead_newAdmissionYear_createsNewOppAndKeepsEarlierOpp() {
        Lead lead2026 = createConverted2026Student();

        Test.startTest();
        Map<String, Object> response = convert(lead2026.Id, REG_2026, YEAR_2027, APP_2027, PROGRAMME_2027);
        Test.stopTest();

        Map<String, Opportunity> byYear = oppsByYear(lead2026.ConvertedAccountId);
        System.assertEquals(2, byYear.size(), 'A new-year Opportunity must be created. Response: ' + response);
        System.assertEquals(PROGRAMME_2026, byYear.get(YEAR_2026).Primary_Preferred_Program__c,
            'The 2026 Opportunity must not be overwritten with the 2027 programme.');
        System.assertEquals(GROUP_TAG, byYear.get(YEAR_2027).Program_Group_Tag__c,
            'The 2027 Opportunity must be created for the same group.');
        System.assertEquals(APP_2026, byYear.get(YEAR_2026).Application_Number__c,
            'The 2026 Opportunity must keep its application number.');
    }

    @IsTest
    static void convertedLead_sameAdmissionYear_updatesExistingOpp() {
        Lead lead2026 = createConverted2026Student();

        Test.startTest();
        convert(lead2026.Id, REG_2026, YEAR_2026, APP_2026, PROGRAMME_2027_CHANGED);
        Test.stopTest();

        Map<String, Opportunity> byYear = oppsByYear(lead2026.ConvertedAccountId);
        System.assertEquals(1, byYear.size(), 'The same admission year must not create a second Opportunity.');
        System.assertEquals(PROGRAMME_2027_CHANGED, byYear.get(YEAR_2026).Primary_Preferred_Program__c,
            'The same-year Opportunity must receive the updated programme.');
    }

    // =========================================================================
    // 4. personAccountId route
    // =========================================================================

    @IsTest
    static void personAccountRoute_updatesOnlySameYearOpp() {
        Lead lead2026 = createConverted2026Student();
        register(REG_2027, YEAR_2027);
        convert(leadByRegistration(REG_2027).Id, REG_2027, YEAR_2027, APP_2027, PROGRAMME_2027);

        Test.startTest();
        Map<String, Object> response = LeadConversionService.processSingleLead(new Map<String, Object>{
            'personAccountId'    => String.valueOf(lead2026.ConvertedAccountId),
            'registrationNumber' => REG_2027,
            'grpPrograms'        => groups(APP_2027, PROGRAMME_2027_CHANGED)
        });
        Test.stopTest();

        String message = (String) response.get('message');
        System.assert(message != null && !message.startsWith('Error'),
            'The update must complete without an error. Response: ' + response);
        Map<String, Opportunity> byYear = oppsByYear(lead2026.ConvertedAccountId);
        System.assertEquals(2, byYear.size(), 'No extra Opportunity may be created. Response: ' + response);
        System.assertEquals(PROGRAMME_2027_CHANGED, byYear.get(YEAR_2027).Primary_Preferred_Program__c,
            'The 2027 Opportunity must receive the changed programme.');
        System.assertEquals(PROGRAMME_2026, byYear.get(YEAR_2026).Primary_Preferred_Program__c,
            'The 2026 Opportunity must not be changed.');
        Lead slot2027 = [SELECT Group_1_Programmes__c FROM Lead WHERE Registration_Number__c = :REG_2027 LIMIT 1];
        Lead slot2026 = [SELECT Group_1_Programmes__c FROM Lead WHERE Registration_Number__c = :REG_2026 LIMIT 1];
        System.assert(String.valueOf(slot2027.Group_1_Programmes__c).contains(PROGRAMME_2027_CHANGED),
            'The 2027 Lead slot must receive the changed programme: ' + slot2027.Group_1_Programmes__c);
        System.assert(!String.valueOf(slot2026.Group_1_Programmes__c).contains(PROGRAMME_2027_CHANGED),
            'The 2026 Lead slot must not be changed: ' + slot2026.Group_1_Programmes__c);
    }

    // =========================================================================
    // 5. Helper edge cases and bulk
    // =========================================================================

    @IsTest
    static void findReturningStudentAccountId_returnsNullWhenNotApplicable() {
        Lead noEmail = new Lead(LastName = 'NoEmail', Phone = PHONE);
        Lead noPhone = new Lead(LastName = 'NoPhone', Email = 'no.phone@test.com');
        Lead firstTime = new Lead(LastName = 'FirstTime', Email = 'first.time@test.com', Phone = PHONE);

        Test.startTest();
        Id blankEmailResult = LeadConversionService.findReturningStudentAccountId(noEmail);
        Id blankPhoneResult = LeadConversionService.findReturningStudentAccountId(noPhone);
        Id noEarlierLeadResult = LeadConversionService.findReturningStudentAccountId(firstTime);
        Test.stopTest();

        System.assertEquals(null, blankEmailResult, 'A Lead without Email cannot be matched to an earlier Account.');
        System.assertEquals(null, blankPhoneResult, 'A Lead without Phone cannot be matched to an earlier Account.');
        System.assertEquals(null, noEarlierLeadResult, 'A first-time student has no earlier Account.');
    }

    // =========================================================================
    // 6. Blank application number filled later, never overwritten
    // =========================================================================

    @IsTest
    static void blankApplicationNumber_filledByLaterPayload_neverOverwritten() {
        register(REG_2027, YEAR_2027);
        Lead lead2027 = leadByRegistration(REG_2027);
        convert(lead2027.Id, REG_2027, YEAR_2027, null, PROGRAMME_2027);
        lead2027 = leadByRegistration(REG_2027);
        System.assertEquals(null, oppsByYear(lead2027.ConvertedAccountId).get(YEAR_2027).Application_Number__c,
            'Setup: without an application number the Opportunity must be created blank.');

        Test.startTest();
        convert(lead2027.Id, REG_2027, YEAR_2027, APP_2027, PROGRAMME_2027);
        convert(lead2027.Id, REG_2027, YEAR_2027, 'UG2027-APP-OTHER', PROGRAMME_2027);
        Test.stopTest();

        Map<String, Opportunity> byYear = oppsByYear(lead2027.ConvertedAccountId);
        System.assertEquals(1, byYear.size(), 'Re-sending the group must not create another Opportunity.');
        System.assertEquals(APP_2027, byYear.get(YEAR_2027).Application_Number__c,
            'The blank application number must be filled by the first payload that sends it, and not overwritten later.');
    }

    @IsTest
    static void fillBlankApplicationNumber_rules() {
        Opportunity blankOpp = new Opportunity(Name = 'Blank');
        Opportunity numberedOpp = new Opportunity(Name = 'Numbered', Application_Number__c = APP_2026);
        Map<String, Object> withNumber = new Map<String, Object>{ 'applicationNumber' => APP_2027 };
        Map<String, Object> withoutNumber = new Map<String, Object>{ 'applicationNumber' => '' };

        Test.startTest();
        Boolean filledBlank = LeadConversionService.fillBlankApplicationNumber(blankOpp, withNumber);
        Boolean filledNumbered = LeadConversionService.fillBlankApplicationNumber(numberedOpp, withNumber);
        Boolean filledFromEmpty = LeadConversionService.fillBlankApplicationNumber(new Opportunity(Name = 'X'), withoutNumber);
        Test.stopTest();

        System.assert(filledBlank, 'A blank Opportunity number must be filled.');
        System.assertEquals(APP_2027, blankOpp.Application_Number__c, 'The incoming number must be used.');
        System.assert(!filledNumbered, 'An existing Opportunity number must not be overwritten.');
        System.assertEquals(APP_2026, numberedOpp.Application_Number__c, 'The existing number must stay.');
        System.assert(!filledFromEmpty, 'A blank incoming number must not change the Opportunity.');
    }

    @IsTest
    static void filterOppsByAdmissionYear_bulk200() {
        List<Opportunity> opps = new List<Opportunity>();
        for (Integer i = 0; i < BULK_SIZE; i++) {
            opps.add(new Opportunity(
                Name = 'Bulk ' + i,
                Admission_Year__c = Math.mod(i, 2) == 0 ? YEAR_2026 : YEAR_2027
            ));
        }

        Test.startTest();
        List<Opportunity> scoped = LeadConversionService.filterOppsByAdmissionYear(opps, YEAR_2027);
        Test.stopTest();

        System.assertEquals(BULK_SIZE / 2, scoped.size(), 'Only the 2027 Opportunities must be kept.');
        for (Opportunity o : scoped) {
            System.assertEquals(YEAR_2027, o.Admission_Year__c, 'Every kept Opportunity must be from 2027.');
        }
    }
}