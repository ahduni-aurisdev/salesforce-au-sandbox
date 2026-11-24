/**
 * @description Tests for MBARendezvousLeadService: new lead, duplicate handling, validation and bulk.
 *              Relies on the deployed WebFormFieldMapping__mdt records for TypeOfForm__c MBA_Rendezvous
 *              and the Masters Department_Record_Type_Mapping__mdt record.
 * @author Jitendra V
 * @date 2026-11-16
 * @version 1.0
 * @lastModified 2026-11-16
 */
@IsTest
private class MBARendezvousLeadServiceTest {

    private static final Integer EXISTING_LEADS = 200;
    private static final Integer REGISTERED_LEADS = 10;
    private static final String MBA = 'Master of Business Administration';
    private static final String YEAR = '2027';
    private static final String YEAR_VALUE = 'Admission Year - 2027';
    private static final String PRIOR_SOURCE = 'Website_MastersQueries';
    private static final String ORIGINAL_CITY = 'Ahmedabad';
    private static final String NEW_CITY = 'Pune';

    @TestSetup
    static void createExistingLeads() {
        Id mastersRecordTypeId = [
            SELECT Record_Type_Id__c FROM Department_Record_Type_Mapping__mdt WHERE Department__c = 'Masters' LIMIT 1
        ].Record_Type_Id__c;
        List<Lead> leads = new List<Lead>();
        for (Integer i = 0; i < EXISTING_LEADS; i++) {
            leads.add(new Lead(
                FirstName = 'Existing',
                LastName = 'Student ' + i,
                Email = existingEmail(i),
                Phone = existingPhone(i),
                RecordTypeId = mastersRecordTypeId,
                Department__c = 'Masters',
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

    private static String existingEmail(Integer i) {
        return 'existing.student' + i + '@example.com';
    }

    private static String existingPhone(Integer i) {
        return String.valueOf(9800000000L + i);
    }

    private static MBARendezvousLeadService.LeadRequest request(String email, String phone) {
        MBARendezvousLeadService.LeadRequest r = new MBARendezvousLeadService.LeadRequest();
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

    private static MBARendezvousLeadService.LeadResult saveOne(MBARendezvousLeadService.LeadRequest r) {
        return MBARendezvousLeadService.saveLeads(new List<MBARendezvousLeadService.LeadRequest>{ r })[0];
    }

    private static String leadSourceValue() {
        return [
            SELECT LeadSourceGroup__c FROM WebFormFieldMapping__mdt
            WHERE TypeOfForm__c = :MBARendezvousLeadService.TYPE_OF_FORM LIMIT 1
        ].LeadSourceGroup__c;
    }

    @IsTest
    static void newStudentCreatesMastersLead() {
        Test.startTest();
        MBARendezvousLeadService.LeadResult result = saveOne(request('new.student@example.com', '+91 91234 56789'));
        Test.stopTest();

        System.assertEquals(true, result.success, 'New lead should be saved: ' + result.message);
        System.assertEquals(MBARendezvousLeadService.ACTION_CREATED, result.action, 'A new student should create a Lead');
        Lead saved = [
            SELECT LeadSource, Department__c, TypeOfForm__c, Admission_Year__c, Preferred_Programme__c,
                Programme_Interested_in__c, Multi_Select_Lead_Source__c, Phone, City, State, FirstName, LastName
            FROM Lead WHERE Id = :result.leadId
        ];
        System.assertEquals(leadSourceValue(), saved.LeadSource, 'Lead Source should come from the MBA Rendezvous mapping');
        System.assertEquals('MBA Rendezvous', saved.LeadSource, 'Lead Source should be MBA Rendezvous');
        System.assertEquals('Masters', saved.Department__c, 'Department should be Masters');
        System.assertEquals(MBARendezvousLeadService.TYPE_OF_FORM, saved.TypeOfForm__c, 'Form type should identify the partner');
        System.assertEquals(YEAR_VALUE, saved.Admission_Year__c, 'Year 2027 should be stored as the picklist value');
        System.assertEquals(MBA, saved.Preferred_Programme__c, 'Programme should be mapped');
        System.assertEquals(MBA, saved.Programme_Interested_in__c, 'Programme text field should be mapped');
        System.assertEquals('MBA Rendezvous', saved.Multi_Select_Lead_Source__c, 'Multi-source should start with MBA Rendezvous');
        System.assert(saved.Phone.replaceAll('\\D', '').endsWith('9123456789'), 'Phone should keep the 10-digit mobile: ' + saved.Phone);
        System.assertEquals(NEW_CITY, saved.City, 'City should be mapped');
        System.assertEquals('Maharashtra', saved.State, 'State should be mapped');
        System.assertEquals('Patel', saved.LastName, 'Last name should be mapped');
    }

    @IsTest
    static void missingAdmissionYearUsesOrgDefault() {
        MBARendezvousLeadService.LeadRequest r = request('no.year@example.com', '9123400000');
        r.admissionYear = null;
        r.lastName = null;

        Test.startTest();
        MBARendezvousLeadService.LeadResult result = saveOne(r);
        Test.stopTest();

        System.assertEquals(true, result.success, 'Lead without a year should be saved: ' + result.message);
        Lead saved = [SELECT Admission_Year__c, LastName FROM Lead WHERE Id = :result.leadId];
        System.assertEquals(System.Label.Admission_Year, saved.Admission_Year__c, 'Missing year should use the Admission_Year label');
        System.assertEquals('.', saved.LastName, 'Missing last name should default to a dot, as for website leads');
    }

    @IsTest
    static void duplicateWithoutRegistrationIsUpdated() {
        Integer i = REGISTERED_LEADS + 5;
        Lead before = [SELECT Id FROM Lead WHERE Email = :existingEmail(i)];

        Test.startTest();
        MBARendezvousLeadService.LeadResult result = saveOne(request(existingEmail(i).toUpperCase(), '0' + existingPhone(i)));
        Test.stopTest();

        System.assertEquals(true, result.success, 'Duplicate should be saved: ' + result.message);
        System.assertEquals(MBARendezvousLeadService.ACTION_UPDATED, result.action, 'Duplicate should update the existing Lead');
        System.assertEquals(before.Id, result.leadId, 'The existing Lead should be returned');
        Lead after = [SELECT City, LeadSource, Multi_Select_Lead_Source__c FROM Lead WHERE Id = :before.Id];
        System.assertEquals(NEW_CITY, after.City, 'Mapped fields should be overwritten for a lead without a registration');
        System.assertEquals('MBA Rendezvous', after.LeadSource, 'Lead Source should be overwritten, as for other partners');
        Set<String> sources = new Set<String>(after.Multi_Select_Lead_Source__c.split(';'));
        System.assert(sources.contains(PRIOR_SOURCE), 'Earlier source should be kept in multi-source');
        System.assert(sources.contains('MBA Rendezvous'), 'MBA Rendezvous should be added to multi-source');
        System.assertEquals(EXISTING_LEADS, [SELECT COUNT() FROM Lead], 'No new Lead should be created');
    }

    @IsTest
    static void duplicateWithRegistrationKeepsData() {
        Lead before = [SELECT Id FROM Lead WHERE Email = :existingEmail(0)];

        Test.startTest();
        MBARendezvousLeadService.LeadResult result = saveOne(request(existingEmail(0), existingPhone(0)));
        Test.stopTest();

        System.assertEquals(true, result.success, 'Registered duplicate should be saved: ' + result.message);
        System.assertEquals(before.Id, result.leadId, 'The registered Lead should be returned');
        Lead after = [SELECT City, LeadSource, Most_Recent_Lead_Source__c, Multi_Select_Lead_Source__c FROM Lead WHERE Id = :before.Id];
        System.assertEquals(ORIGINAL_CITY, after.City, 'Data of a lead with an application must not change');
        System.assertEquals(PRIOR_SOURCE, after.LeadSource, 'Lead Source of a registered lead must not change');
        System.assertEquals('MBA Rendezvous', after.Most_Recent_Lead_Source__c, 'Most recent source should record MBA Rendezvous');
        System.assert(after.Multi_Select_Lead_Source__c.contains('MBA Rendezvous'), 'MBA Rendezvous should be added to multi-source');
    }

    @IsTest
    static void newLeadWithoutProgrammeDefaultsToMba() {
        MBARendezvousLeadService.LeadRequest r = request('no.programme@example.com', '9123433333');
        r.programmeInterestedIn = null;

        Test.startTest();
        MBARendezvousLeadService.LeadResult result = saveOne(r);
        Test.stopTest();

        System.assertEquals(true, result.success, 'Lead without a programme should be saved: ' + result.message);
        System.assertEquals(MBARendezvousLeadService.ACTION_CREATED, result.action, 'A new student should create a Lead');
        Lead saved = [SELECT Preferred_Programme__c, Programme_Interested_in__c FROM Lead WHERE Id = :result.leadId];
        System.assertEquals(MBARendezvousLeadService.DEFAULT_PROGRAMME, saved.Preferred_Programme__c, 'Missing programme should default to MBA');
        System.assertEquals(MBARendezvousLeadService.DEFAULT_PROGRAMME, saved.Programme_Interested_in__c, 'Programme text should default to MBA');
    }

    @IsTest
    static void leadWithoutProgrammeMatchesExistingLeadOnAnyProgrammeAndKeepsIt() {
        Lead other = [SELECT Id FROM Lead WHERE Email = :existingEmail(60)];
        other.Preferred_Programme__c = 'Master of Science in Quantitative Finance';
        update other;
        MBARendezvousLeadService.LeadRequest r = request(existingEmail(60), existingPhone(60));
        r.programmeInterestedIn = null;

        Test.startTest();
        MBARendezvousLeadService.LeadResult result = saveOne(r);
        Test.stopTest();

        System.assertEquals(MBARendezvousLeadService.ACTION_UPDATED, result.action, 'Same email + phone + year without a programme is the same person');
        System.assertEquals(other.Id, result.leadId, 'The existing Lead should be returned');
        Lead after = [SELECT Preferred_Programme__c, City FROM Lead WHERE Id = :other.Id];
        System.assertEquals('Master of Science in Quantitative Finance', after.Preferred_Programme__c, 'Existing programme must be kept when none is sent');
        System.assertEquals(NEW_CITY, after.City, 'Other mapped fields should still be updated');
        System.assertEquals(EXISTING_LEADS, [SELECT COUNT() FROM Lead], 'No new Lead should be created');
    }

    @IsTest
    static void differentProgrammeSentIsANewLead() {
        MBARendezvousLeadService.LeadRequest r = request(existingEmail(70), existingPhone(70));
        r.programmeInterestedIn = 'Master of Science in Economics';

        Test.startTest();
        MBARendezvousLeadService.LeadResult result = saveOne(r);
        Test.stopTest();

        System.assertEquals(MBARendezvousLeadService.ACTION_CREATED, result.action, 'A different programme that was sent is a separate enquiry');
        System.assertEquals(EXISTING_LEADS + 1, [SELECT COUNT() FROM Lead], 'One new Lead should be created');
    }

    @IsTest
    static void sameEmailWithDifferentPhoneIsANewLead() {
        Test.startTest();
        MBARendezvousLeadService.LeadResult result = saveOne(request(existingEmail(50), '9000000001'));
        Test.stopTest();

        System.assertEquals(MBARendezvousLeadService.ACTION_CREATED, result.action, 'A different phone is a different person');
        System.assertEquals(EXISTING_LEADS + 1, [SELECT COUNT() FROM Lead], 'One new Lead should be created');
    }

    @IsTest
    static void invalidInputIsRejectedWithReasons() {
        MBARendezvousLeadService.LeadRequest blank = new MBARendezvousLeadService.LeadRequest();
        MBARendezvousLeadService.LeadRequest wrongValues = request('not-an-email', '12345');
        wrongValues.programmeInterestedIn = 'Bachelor of Arts (Honours)';
        wrongValues.admissionYear = '1999';
        MBARendezvousLeadService.LeadRequest tooLong = request('long.city@example.com', '9123411111');
        tooLong.city = 'C'.repeat(300);

        Test.startTest();
        List<MBARendezvousLeadService.LeadResult> results = MBARendezvousLeadService.saveLeads(
            new List<MBARendezvousLeadService.LeadRequest>{ blank, wrongValues, tooLong }
        );
        Test.stopTest();

        for (MBARendezvousLeadService.LeadResult r : results) {
            System.assertEquals(false, r.success, 'Invalid lead must be rejected');
            System.assertEquals(null, r.leadId, 'Rejected lead must not have an Id');
        }
        for (String expected : new List<String>{ 'firstName is required', 'email is required', 'phone is required' }) {
            System.assert(results[0].message.contains(expected), 'Missing "' + expected + '" in: ' + results[0].message);
        }
        System.assert(!results[0].message.contains('programmeInterestedIn'), 'Programme is optional: ' + results[0].message);
        for (String expected : new List<String>{ 'email is not a valid', 'phone must be a 10-digit', 'programmeInterestedIn must be one of', 'admissionYear must be' }) {
            System.assert(results[1].message.contains(expected), 'Missing "' + expected + '" in: ' + results[1].message);
        }
        System.assert(results[1].message.contains(MBA), 'Allowed programmes should be listed: ' + results[1].message);
        System.assert(!results[1].message.contains('Bachelor'), 'Only Masters programmes should be allowed: ' + results[1].message);
        System.assert(results[2].message.contains('city must be at most'), 'Over-long city should be rejected: ' + results[2].message);
        System.assertEquals(EXISTING_LEADS, [SELECT COUNT() FROM Lead], 'Nothing should be saved for invalid input');
    }

    @IsTest
    static void sameLeadTwiceInOneRequestIsSavedOnce() {
        Test.startTest();
        List<MBARendezvousLeadService.LeadResult> results = MBARendezvousLeadService.saveLeads(
            new List<MBARendezvousLeadService.LeadRequest>{
                request('twice@example.com', '9123422222'),
                request('twice@example.com', '+919123422222')
            }
        );
        Test.stopTest();

        System.assertEquals(true, results[0].success, 'First copy should be saved: ' + results[0].message);
        System.assertEquals(false, results[1].success, 'Second copy should be rejected');
        System.assert(results[1].message.contains('item 1'), 'Should point to the first copy: ' + results[1].message);
        System.assertEquals(1, [SELECT COUNT() FROM Lead WHERE Email = 'twice@example.com'], 'Only one Lead should exist');
    }

    @IsTest
    static void bulkOf200NewAndDuplicateLeads() {
        List<MBARendezvousLeadService.LeadRequest> requests = new List<MBARendezvousLeadService.LeadRequest>();
        for (Integer i = 0; i < 100; i++) {
            requests.add(request('bulk.student' + i + '@example.com', String.valueOf(9700000000L + i)));
        }
        for (Integer i = 100; i < EXISTING_LEADS; i++) {
            requests.add(request(existingEmail(i), existingPhone(i)));
        }

        Test.startTest();
        List<MBARendezvousLeadService.LeadResult> results = MBARendezvousLeadService.saveLeads(requests);
        Test.stopTest();

        Integer created = 0;
        Integer updated = 0;
        for (MBARendezvousLeadService.LeadResult r : results) {
            System.assertEquals(true, r.success, 'Every bulk lead should be saved: ' + r.message);
            if (r.action == MBARendezvousLeadService.ACTION_CREATED) {
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
    static void phoneFormatsAreNormalised() {
        System.assertEquals('9876543210', MBARendezvousLeadService.indianMobile('+91 98765-43210'), '+91 prefix should be removed');
        System.assertEquals('9876543210', MBARendezvousLeadService.indianMobile('919876543210'), '91 prefix should be removed');
        System.assertEquals('9876543210', MBARendezvousLeadService.indianMobile('09876543210'), 'Leading 0 should be removed');
        System.assertEquals('9876543210', MBARendezvousLeadService.indianMobile('98765 43210'), 'Spaces should be removed');
        System.assertEquals(null, MBARendezvousLeadService.indianMobile('12345'), 'Short numbers are not valid');
        System.assertEquals(null, MBARendezvousLeadService.indianMobile(null), 'Blank is not valid');
    }

    @IsTest
    static void sourceIsAppendedOnlyOnce() {
        System.assertEquals('MBA Rendezvous', MBARendezvousLeadService.appendSource(null, 'MBA Rendezvous'), 'Empty list gets the source');
        System.assertEquals('A;MBA Rendezvous', MBARendezvousLeadService.appendSource('A;MBA Rendezvous', 'MBA Rendezvous'), 'Source is not repeated');
    }

    @IsTest
    static void requestReadsNumbersAsText() {
        MBARendezvousLeadService.LeadRequest r = new MBARendezvousLeadService.LeadRequest(
            new Map<String, Object>{ 'phone' => 9876543210L, 'admissionYear' => 2027, 'firstName' => '  Asha  ', 'collegeOrUniversity' => 'ignored' }
        );
        System.assertEquals('9876543210', r.phone, 'Numeric phone should be read as text');
        System.assertEquals('2027', r.admissionYear, 'Numeric year should be read as text');
        System.assertEquals('Asha', r.firstName, 'Values should be trimmed');
    }
}