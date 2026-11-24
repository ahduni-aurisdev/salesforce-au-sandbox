/**
 * @description Tests for PartnerLeadService: partner/app check, departments and record types, programme
 *              defaults, duplicate handling, validation and bulk. Partners are supplied in memory through
 *              PartnerLeadService.testPartners; field mappings (TypeOfForm__c Partner_API) and department
 *              record types come from the deployed custom metadata.
 * @author Jitendra V
 * @date 2026-11-18
 * @version 1.0
 * @lastModified 2026-11-18
 */
@IsTest
private class PartnerLeadServiceTest {

    private static final Integer EXISTING_LEADS = 200;
    private static final Integer REGISTERED_LEADS = 10;
    private static final String APP = 'Test Partner Integration';
    private static final String OTHER_APP = 'Other Partner Integration';
    private static final String SOURCE = 'MBA Rendezvous';
    private static final String OTHER_SOURCE = 'Other Partner';
    private static final String FORM = 'MBA_Rendezvous';
    private static final String MASTERS = 'Masters';
    private static final String PHD = 'Phd';
    private static final String UG = 'Undergraduation';
    private static final String MBA = 'Master of Business Administration';
    private static final String YEAR = '2027';
    private static final String YEAR_VALUE = 'Admission Year - 2027';
    private static final String PRIOR_SOURCE = 'Website_MastersQueries';
    private static final String ORIGINAL_CITY = 'Ahmedabad';
    private static final String NEW_CITY = 'Pune';

    @TestSetup
    static void createExistingLeads() {
        List<Lead> leads = new List<Lead>();
        for (Integer i = 0; i < EXISTING_LEADS; i++) {
            leads.add(new Lead(
                FirstName = 'Existing',
                LastName = 'Student ' + i,
                Email = existingEmail(i),
                Phone = existingPhone(i),
                RecordTypeId = recordTypeId(MASTERS),
                Department__c = MASTERS,
                Preferred_Programme__c = MBA,
                Admission_Year__c = YEAR_VALUE,
                City = ORIGINAL_CITY,
                LeadSource = PRIOR_SOURCE,
                Multi_Select_Lead_Source__c = PRIOR_SOURCE,
                Registration_Number__c = i < REGISTERED_LEADS ? 'REG-' + i : null
            ));
        }
        insert leads;
    }

    private static Id recordTypeId(String department) {
        return [
            SELECT Record_Type_Id__c FROM Department_Record_Type_Mapping__mdt WHERE Department__c = :department LIMIT 1
        ].Record_Type_Id__c;
    }

    private static String existingEmail(Integer i) {
        return 'existing.student' + i + '@example.com';
    }

    private static String existingPhone(Integer i) {
        return String.valueOf(9800000000L + i);
    }

    private static Partner_Lead_Source__mdt partner(String source, String app, String defaultProgramme, String defaultDepartment) {
        return new Partner_Lead_Source__mdt(
            DeveloperName = source.replaceAll('\\W', '_'),
            Lead_Source__c = source,
            OAuth_App_Name__c = app,
            Type_Of_Form__c = FORM,
            Default_Programme__c = defaultProgramme,
            Default_Programme_Department__c = defaultDepartment,
            Is_Active__c = true
        );
    }

    /** Two partners: ours (with an MBA default for Masters) and another partner on a different app. */
    private static void configurePartners() {
        PartnerLeadService.testPartners = new List<Partner_Lead_Source__mdt>{
            partner(SOURCE, APP, MBA, MASTERS),
            partner(OTHER_SOURCE, OTHER_APP, null, null)
        };
    }

    private static PartnerLeadService.LeadRequest request(String email, String phone) {
        PartnerLeadService.LeadRequest r = new PartnerLeadService.LeadRequest();
        r.leadSource = SOURCE;
        r.department = MASTERS;
        r.firstName = 'Asha';
        r.lastName = 'Patel';
        r.email = email;
        r.phone = phone;
        r.programmeInterestedIn = MBA;
        r.admissionYear = YEAR;
        r.state = 'Maharashtra';
        r.city = NEW_CITY;
        return r;
    }

    private static PartnerLeadService.LeadResult saveOne(PartnerLeadService.LeadRequest r) {
        return PartnerLeadService.saveLeads(new List<PartnerLeadService.LeadRequest>{ r }, APP)[0];
    }

    @IsTest
    static void newMastersLeadIsCreatedWithPartnerValues() {
        configurePartners();

        Test.startTest();
        PartnerLeadService.LeadResult result = saveOne(request('new.student@example.com', '+91 91234 56789'));
        Test.stopTest();

        System.assertEquals(true, result.success, 'New lead should be saved: ' + result.message);
        System.assertEquals(PartnerLeadService.ACTION_CREATED, result.action, 'A new student should create a Lead');
        Lead saved = [
            SELECT RecordTypeId, LeadSource, Department__c, TypeOfForm__c, Admission_Year__c, Preferred_Programme__c,
                Programme_Interested_in__c, Multi_Select_Lead_Source__c, Phone, City, State, LastName
            FROM Lead WHERE Id = :result.leadId
        ];
        System.assertEquals(recordTypeId(MASTERS), saved.RecordTypeId, 'Record type should come from the department mapping');
        System.assertEquals(SOURCE, saved.LeadSource, 'Lead Source should be the partner source');
        System.assertEquals(SOURCE, saved.Multi_Select_Lead_Source__c, 'Multi-source should start with the partner source');
        System.assertEquals(MASTERS, saved.Department__c, 'Department should be the department sent');
        System.assertEquals(FORM, saved.TypeOfForm__c, 'Form type should come from the partner configuration');
        System.assertEquals(YEAR_VALUE, saved.Admission_Year__c, 'Year 2027 should be stored as the picklist value');
        System.assertEquals(MBA, saved.Preferred_Programme__c, 'Programme should be mapped');
        System.assertEquals(MBA, saved.Programme_Interested_in__c, 'Programme text field should be mapped');
        System.assert(saved.Phone.replaceAll('\\D', '').endsWith('9123456789'), 'Phone should keep the 10-digit mobile: ' + saved.Phone);
        System.assertEquals(NEW_CITY, saved.City, 'City should be mapped');
        System.assertEquals('Maharashtra', saved.State, 'State should be mapped');
        System.assertEquals('Patel', saved.LastName, 'Last name should be mapped');
    }

    @IsTest
    static void departmentSetsRecordTypeAndIsCaseInsensitive() {
        configurePartners();
        PartnerLeadService.LeadRequest phdLead = request('phd.student@example.com', '9123400001');
        phdLead.department = 'PHD';
        phdLead.programmeInterestedIn = 'PhD in Management';
        PartnerLeadService.LeadRequest ugLead = request('ug.student@example.com', '9123400002');
        ugLead.department = UG;
        ugLead.programmeInterestedIn = 'Bachelor of Arts (Honours)';
        ugLead.state = 'Gujarat';

        Test.startTest();
        List<PartnerLeadService.LeadResult> results = PartnerLeadService.saveLeads(
            new List<PartnerLeadService.LeadRequest>{ phdLead, ugLead }, APP
        );
        Test.stopTest();

        System.assertEquals(true, results[0].success, 'Phd lead should be saved: ' + results[0].message);
        System.assertEquals(true, results[1].success, 'Undergraduation lead should be saved: ' + results[1].message);
        Lead savedPhd = [SELECT RecordTypeId, Department__c, Preferred_Programme__c FROM Lead WHERE Id = :results[0].leadId];
        Lead savedUg = [SELECT RecordTypeId, Department__c FROM Lead WHERE Id = :results[1].leadId];
        System.assertEquals(recordTypeId(PHD), savedPhd.RecordTypeId, 'Phd lead should get the Phd record type');
        System.assertEquals(PHD, savedPhd.Department__c, 'Department should use the configured spelling');
        System.assertEquals('PhD in Management', savedPhd.Preferred_Programme__c, 'Any active programme is allowed');
        System.assertEquals(recordTypeId(UG), savedUg.RecordTypeId, 'Undergraduation lead should get its record type');
    }

    @IsTest
    static void missingProgrammeDefaultsOnlyForTheConfiguredDepartment() {
        configurePartners();
        PartnerLeadService.LeadRequest mastersLead = request('no.programme.masters@example.com', '9123433333');
        mastersLead.programmeInterestedIn = null;
        PartnerLeadService.LeadRequest phdLead = request('no.programme.phd@example.com', '9123433334');
        phdLead.department = PHD;
        phdLead.programmeInterestedIn = null;

        Test.startTest();
        List<PartnerLeadService.LeadResult> results = PartnerLeadService.saveLeads(
            new List<PartnerLeadService.LeadRequest>{ mastersLead, phdLead }, APP
        );
        Test.stopTest();

        Lead savedMasters = [SELECT Preferred_Programme__c, Programme_Interested_in__c FROM Lead WHERE Id = :results[0].leadId];
        Lead savedPhd = [SELECT Preferred_Programme__c FROM Lead WHERE Id = :results[1].leadId];
        System.assertEquals(MBA, savedMasters.Preferred_Programme__c, 'Masters lead without a programme should get the partner default');
        System.assertEquals(MBA, savedMasters.Programme_Interested_in__c, 'Programme text should get the partner default');
        System.assertEquals(null, savedPhd.Preferred_Programme__c, 'Other departments without a programme stay blank');
    }

    @IsTest
    static void inactiveDefaultProgrammeIsIgnored() {
        PartnerLeadService.testPartners = new List<Partner_Lead_Source__mdt>{ partner(SOURCE, APP, 'Not A Programme', MASTERS) };
        PartnerLeadService.LeadRequest r = request('bad.default@example.com', '9123433335');
        r.programmeInterestedIn = null;

        Test.startTest();
        PartnerLeadService.LeadResult result = saveOne(r);
        Test.stopTest();

        System.assertEquals(true, result.success, 'Lead should still be saved: ' + result.message);
        System.assertEquals(null, [SELECT Preferred_Programme__c FROM Lead WHERE Id = :result.leadId].Preferred_Programme__c,
            'A default that is not an active programme must not be used');
    }

    @IsTest
    static void missingAdmissionYearAndLastNameUseDefaults() {
        configurePartners();
        PartnerLeadService.LeadRequest r = request('no.year@example.com', '9123400000');
        r.admissionYear = null;
        r.lastName = null;

        Test.startTest();
        PartnerLeadService.LeadResult result = saveOne(r);
        Test.stopTest();

        System.assertEquals(true, result.success, 'Lead without a year should be saved: ' + result.message);
        Lead saved = [SELECT Admission_Year__c, LastName FROM Lead WHERE Id = :result.leadId];
        System.assertEquals(System.Label.Admission_Year, saved.Admission_Year__c, 'Missing year should use the Admission_Year label');
        System.assertEquals('.', saved.LastName, 'Missing last name should default to a dot, as for website leads');
    }

    @IsTest
    static void duplicateWithoutRegistrationIsUpdated() {
        configurePartners();
        Integer i = REGISTERED_LEADS + 5;
        Lead before = [SELECT Id FROM Lead WHERE Email = :existingEmail(i)];
        PartnerLeadService.LeadRequest r = request(existingEmail(i).toUpperCase(), '0' + existingPhone(i));
        r.department = 'masters';

        Test.startTest();
        PartnerLeadService.LeadResult result = saveOne(r);
        Test.stopTest();

        System.assertEquals(true, result.success, 'Duplicate should be saved: ' + result.message);
        System.assertEquals(PartnerLeadService.ACTION_UPDATED, result.action, 'Duplicate should update the existing Lead');
        System.assertEquals(before.Id, result.leadId, 'The existing Lead should be returned');
        Lead after = [SELECT City, LeadSource, Multi_Select_Lead_Source__c FROM Lead WHERE Id = :before.Id];
        System.assertEquals(NEW_CITY, after.City, 'Mapped fields should be overwritten for a lead without a registration');
        System.assertEquals(SOURCE, after.LeadSource, 'Lead Source should be overwritten, as for other partners');
        Set<String> sources = new Set<String>(after.Multi_Select_Lead_Source__c.split(';'));
        System.assert(sources.contains(PRIOR_SOURCE), 'Earlier source should be kept in multi-source');
        System.assert(sources.contains(SOURCE), 'Partner source should be added to multi-source');
        System.assertEquals(EXISTING_LEADS, [SELECT COUNT() FROM Lead], 'No new Lead should be created');
    }

    @IsTest
    static void duplicateWithRegistrationKeepsData() {
        configurePartners();
        Lead before = [SELECT Id FROM Lead WHERE Email = :existingEmail(0)];

        Test.startTest();
        PartnerLeadService.LeadResult result = saveOne(request(existingEmail(0), existingPhone(0)));
        Test.stopTest();

        System.assertEquals(true, result.success, 'Registered duplicate should be saved: ' + result.message);
        System.assertEquals(before.Id, result.leadId, 'The registered Lead should be returned');
        Lead after = [SELECT City, LeadSource, Most_Recent_Lead_Source__c, Multi_Select_Lead_Source__c FROM Lead WHERE Id = :before.Id];
        System.assertEquals(ORIGINAL_CITY, after.City, 'Data of a lead with an application must not change');
        System.assertEquals(PRIOR_SOURCE, after.LeadSource, 'Lead Source of a registered lead must not change');
        System.assertEquals(SOURCE, after.Most_Recent_Lead_Source__c, 'Most recent source should record the partner');
        System.assert(after.Multi_Select_Lead_Source__c.contains(SOURCE), 'Partner source should be added to multi-source');
    }

    @IsTest
    static void sameStudentInAnotherDepartmentIsANewLead() {
        configurePartners();
        PartnerLeadService.LeadRequest r = request(existingEmail(80), existingPhone(80));
        r.department = PHD;
        r.programmeInterestedIn = null;

        Test.startTest();
        PartnerLeadService.LeadResult result = saveOne(r);
        Test.stopTest();

        System.assertEquals(PartnerLeadService.ACTION_CREATED, result.action, 'Duplicates are only matched within the same department');
        System.assertEquals(EXISTING_LEADS + 1, [SELECT COUNT() FROM Lead], 'One new Lead should be created');
    }

    @IsTest
    static void leadWithoutProgrammeMatchesExistingLeadOnAnyProgrammeAndKeepsIt() {
        configurePartners();
        Lead other = [SELECT Id FROM Lead WHERE Email = :existingEmail(60)];
        other.Preferred_Programme__c = 'Master of Science in Quantitative Finance';
        update other;
        PartnerLeadService.LeadRequest r = request(existingEmail(60), existingPhone(60));
        r.programmeInterestedIn = null;

        Test.startTest();
        PartnerLeadService.LeadResult result = saveOne(r);
        Test.stopTest();

        System.assertEquals(PartnerLeadService.ACTION_UPDATED, result.action, 'Same email + phone + year without a programme is the same person');
        System.assertEquals(other.Id, result.leadId, 'The existing Lead should be returned');
        Lead after = [SELECT Preferred_Programme__c, City FROM Lead WHERE Id = :other.Id];
        System.assertEquals('Master of Science in Quantitative Finance', after.Preferred_Programme__c, 'Existing programme must be kept when none is sent');
        System.assertEquals(NEW_CITY, after.City, 'Other mapped fields should still be updated');
    }

    @IsTest
    static void differentProgrammeOrPhoneIsANewLead() {
        configurePartners();
        PartnerLeadService.LeadRequest otherProgramme = request(existingEmail(70), existingPhone(70));
        otherProgramme.programmeInterestedIn = 'Master of Science in Economics';
        PartnerLeadService.LeadRequest otherPhone = request(existingEmail(50), '9000000001');

        Test.startTest();
        List<PartnerLeadService.LeadResult> results = PartnerLeadService.saveLeads(
            new List<PartnerLeadService.LeadRequest>{ otherProgramme, otherPhone }, APP
        );
        Test.stopTest();

        System.assertEquals(PartnerLeadService.ACTION_CREATED, results[0].action, 'A different programme that was sent is a separate enquiry');
        System.assertEquals(PartnerLeadService.ACTION_CREATED, results[1].action, 'A different phone is a different person');
        System.assertEquals(EXISTING_LEADS + 2, [SELECT COUNT() FROM Lead], 'Two new Leads should be created');
    }

    @IsTest
    static void leadSourceMustBelongToTheCallingApp() {
        configurePartners();
        PartnerLeadService.LeadRequest otherPartnersSource = request('spoof@example.com', '9123455555');
        otherPartnersSource.leadSource = OTHER_SOURCE;
        PartnerLeadService.LeadRequest unknownSource = request('unknown@example.com', '9123455556');
        unknownSource.leadSource = 'Shiksha';

        Test.startTest();
        List<PartnerLeadService.LeadResult> results = PartnerLeadService.saveLeads(
            new List<PartnerLeadService.LeadRequest>{ otherPartnersSource, unknownSource }, APP
        );
        PartnerLeadService.LeadResult unknownApp = PartnerLeadService.saveLeads(
            new List<PartnerLeadService.LeadRequest>{ request('noapp@example.com', '9123455557') }, 'Unknown App'
        )[0];
        Test.stopTest();

        for (PartnerLeadService.LeadResult r : results) {
            System.assertEquals(false, r.success, 'A source not set up for this app must be rejected');
            System.assert(r.message.contains('leadSource must be one of: ' + SOURCE + '.'), 'Only this app\'s sources should be listed: ' + r.message);
            System.assert(!r.message.contains(OTHER_SOURCE), 'Other partners must not be revealed: ' + r.message);
        }
        System.assertEquals(false, unknownApp.success, 'An app with no partner record must be rejected');
        System.assert(unknownApp.message.contains('not set up for this connection'), 'Reason should be given: ' + unknownApp.message);
        System.assertEquals(EXISTING_LEADS, [SELECT COUNT() FROM Lead], 'Nothing should be saved');
    }

    @IsTest
    static void invalidInputIsRejectedWithReasons() {
        configurePartners();
        PartnerLeadService.LeadRequest blank = new PartnerLeadService.LeadRequest();
        PartnerLeadService.LeadRequest wrongValues = request('not-an-email', '12345');
        wrongValues.department = 'Diploma';
        wrongValues.programmeInterestedIn = 'MBA';
        wrongValues.admissionYear = '1999';
        PartnerLeadService.LeadRequest tooLong = request('long.city@example.com', '9123411111');
        tooLong.city = 'C'.repeat(300);

        Test.startTest();
        List<PartnerLeadService.LeadResult> results = PartnerLeadService.saveLeads(
            new List<PartnerLeadService.LeadRequest>{ blank, wrongValues, tooLong }, APP
        );
        Test.stopTest();

        for (PartnerLeadService.LeadResult r : results) {
            System.assertEquals(false, r.success, 'Invalid lead must be rejected');
            System.assertEquals(null, r.leadId, 'Rejected lead must not have an Id');
        }
        for (String expected : new List<String>{ 'leadSource is required', 'department is required', 'firstName is required', 'email is required', 'phone is required' }) {
            System.assert(results[0].message.contains(expected), 'Missing "' + expected + '" in: ' + results[0].message);
        }
        System.assert(!results[0].message.contains('programmeInterestedIn'), 'Programme is optional: ' + results[0].message);
        for (String expected : new List<String>{ 'department must be one of', 'email is not a valid', 'phone must be a 10-digit', 'programmeInterestedIn must be one of', 'admissionYear must be' }) {
            System.assert(results[1].message.contains(expected), 'Missing "' + expected + '" in: ' + results[1].message);
        }
        System.assert(results[1].message.contains(MASTERS) && results[1].message.contains(UG), 'Allowed departments should be listed: ' + results[1].message);
        System.assert(results[2].message.contains('city must be at most'), 'Over-long city should be rejected: ' + results[2].message);
        System.assertEquals(EXISTING_LEADS, [SELECT COUNT() FROM Lead], 'Nothing should be saved for invalid input');
    }

    @IsTest
    static void sameLeadTwiceInOneRequestIsSavedOnce() {
        configurePartners();

        Test.startTest();
        List<PartnerLeadService.LeadResult> results = PartnerLeadService.saveLeads(
            new List<PartnerLeadService.LeadRequest>{
                request('twice@example.com', '9123422222'),
                request('twice@example.com', '+919123422222')
            },
            APP
        );
        Test.stopTest();

        System.assertEquals(true, results[0].success, 'First copy should be saved: ' + results[0].message);
        System.assertEquals(false, results[1].success, 'Second copy should be rejected');
        System.assert(results[1].message.contains('item 1'), 'Should point to the first copy: ' + results[1].message);
        System.assertEquals(1, [SELECT COUNT() FROM Lead WHERE Email = 'twice@example.com'], 'Only one Lead should exist');
    }

    @IsTest
    static void bulkOf200NewAndDuplicateLeads() {
        configurePartners();
        List<PartnerLeadService.LeadRequest> requests = new List<PartnerLeadService.LeadRequest>();
        for (Integer i = 0; i < 100; i++) {
            requests.add(request('bulk.student' + i + '@example.com', String.valueOf(9700000000L + i)));
        }
        for (Integer i = 100; i < EXISTING_LEADS; i++) {
            requests.add(request(existingEmail(i), existingPhone(i)));
        }

        Test.startTest();
        List<PartnerLeadService.LeadResult> results = PartnerLeadService.saveLeads(requests, APP);
        Test.stopTest();

        Integer created = 0;
        Integer updated = 0;
        for (PartnerLeadService.LeadResult r : results) {
            System.assertEquals(true, r.success, 'Every bulk lead should be saved: ' + r.message);
            if (r.action == PartnerLeadService.ACTION_CREATED) {
                created++;
            } else {
                updated++;
            }
        }
        System.assertEquals(100, created, '100 new students should be created');
        System.assertEquals(100, updated, '100 existing students should be updated');
        System.assertEquals(EXISTING_LEADS + 100, [SELECT COUNT() FROM Lead], 'Lead count should grow by the new students only');
    }

    @IsTest
    static void deployedConfigurationIsUsedWhenNoTestPartnersAreSet() {
        Test.startTest();
        PartnerLeadService.LeadResult result = saveOne(request('config@example.com', '9123466666'));
        Test.stopTest();

        System.assertEquals(false, result.success, 'The test app has no deployed partner record');
        System.assert(result.message.contains('leadSource'), 'The lead source check should apply: ' + result.message);
    }

    @IsTest
    static void phoneFormatsAreNormalised() {
        System.assertEquals('9876543210', PartnerLeadService.indianMobile('+91 98765-43210'), '+91 prefix should be removed');
        System.assertEquals('9876543210', PartnerLeadService.indianMobile('919876543210'), '91 prefix should be removed');
        System.assertEquals('9876543210', PartnerLeadService.indianMobile('09876543210'), 'Leading 0 should be removed');
        System.assertEquals('9876543210', PartnerLeadService.indianMobile('98765 43210'), 'Spaces should be removed');
        System.assertEquals(null, PartnerLeadService.indianMobile('12345'), 'Short numbers are not valid');
        System.assertEquals(null, PartnerLeadService.indianMobile(null), 'Blank is not valid');
    }

    @IsTest
    static void sourceIsAppendedOnlyOnce() {
        System.assertEquals(SOURCE, PartnerLeadService.appendSource(null, SOURCE), 'Empty list gets the source');
        System.assertEquals('A;' + SOURCE, PartnerLeadService.appendSource('A;' + SOURCE, SOURCE), 'Source is not repeated');
    }

    @IsTest
    static void requestReadsNumbersAsText() {
        PartnerLeadService.LeadRequest r = new PartnerLeadService.LeadRequest(
            new Map<String, Object>{
                'phone' => 9876543210L, 'admissionYear' => 2027, 'firstName' => '  Asha  ',
                'department' => ' Masters ', 'leadSource' => SOURCE, 'unknownKey' => 'ignored'
            }
        );
        System.assertEquals('9876543210', r.phone, 'Numeric phone should be read as text');
        System.assertEquals('2027', r.admissionYear, 'Numeric year should be read as text');
        System.assertEquals('Asha', r.firstName, 'Values should be trimmed');
        System.assertEquals(MASTERS, r.department, 'Department should be trimmed');
        System.assertEquals(SOURCE, r.leadSource, 'Lead source should be read');
    }
}