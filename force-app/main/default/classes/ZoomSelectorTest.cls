/**
 * @description Tests for ZoomSelector.
 * @author AU Development Team
 * @date 2026-11-02
 * @version 1.1
 * @lastModified 2026-11-03
 */
@IsTest
private class ZoomSelectorTest {
    private static final String SHARED_EMAIL = 'shared.selector@zoomtest.com';
    private static final String VALID_MOBILE = '9876543210';
    private static final String YEAR = 'Admission Year - 2026';

    private static Id mastersRecordTypeId() {
        return Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('Masters').getRecordTypeId();
    }

    @IsTest
    static void emptyInputsReturnEmptyResults() {
        System.assert(ZoomSelector.selectSessionsByZoomIds(new Set<String>()).isEmpty(), 'No IDs must return no sessions');
        System.assert(ZoomSelector.selectRegistrationsByKeys(null).isEmpty(), 'No keys must return no registrations');
        System.assert(ZoomSelector.selectLeadOwners(null).isEmpty(), 'No Lead IDs must return no owners');
        System.assert(ZoomSelector.selectLeadCandidates(new Set<Id>(), new Set<String>{ YEAR }, new Set<String>{ SHARED_EMAIL },
            new Set<String>()).isEmpty(), 'No record types must return no candidates');
        System.assert(ZoomSelector.selectLeadCandidates(new Set<Id>{ mastersRecordTypeId() }, new Set<String>{ YEAR },
            new Set<String>(), new Set<String>()).isEmpty(), 'No email and no phone must return no candidates');
    }

    @IsTest
    static void leadCandidatesFilteredByRecordTypeYearAndContact() {
        Id mastersRt = mastersRecordTypeId();
        Lead older = new Lead(LastName = 'Older', Email = SHARED_EMAIL, RecordTypeId = mastersRt, Admission_Year__c = YEAR);
        Lead newer = new Lead(LastName = 'Newer', MobilePhone = VALID_MOBILE, RecordTypeId = mastersRt, Admission_Year__c = YEAR);
        Lead otherYear = new Lead(LastName = 'Other year', Email = SHARED_EMAIL, RecordTypeId = mastersRt,
            Admission_Year__c = 'Admission Year - 2027');
        insert new List<Lead>{ older, newer, otherYear };
        Test.setCreatedDate(older.Id, Datetime.now().addDays(-5));

        List<Lead> candidates = ZoomSelector.selectLeadCandidates(new Set<Id>{ mastersRt }, new Set<String>{ YEAR },
            new Set<String>{ SHARED_EMAIL }, new Set<String>{ VALID_MOBILE });

        System.assertEquals(2, candidates.size(), 'Only Leads of the same record type and year with a matching email or phone must return');
        System.assertEquals(older.Id, candidates[0].Id, 'Candidates must be ordered oldest first');
    }

    @IsTest
    static void recentSessionsExcludeDeletedAndOld() {
        insert new List<Zoom_Webinar__c>{
            new Zoom_Webinar__c(Name = 'Recent', Webinar_Id__c = '1', Start_Time__c = Datetime.now().addDays(-1), Status__c = 'Ended'),
            new Zoom_Webinar__c(Name = 'Deleted', Webinar_Id__c = '2', Start_Time__c = Datetime.now().addDays(-1), Status__c = 'Deleted'),
            new Zoom_Webinar__c(Name = 'Old', Webinar_Id__c = '3', Start_Time__c = Datetime.now().addDays(-10), Status__c = 'Ended')
        };

        List<Zoom_Webinar__c> recent = ZoomSelector.selectRecentSessions(Datetime.now().addDays(-3));

        System.assertEquals(1, recent.size(), 'Only the recent, non-deleted session must be returned');
        System.assertEquals('1', recent[0].Webinar_Id__c, 'The recent session must be the one returned');
        System.assertEquals('1', ZoomSelector.selectSessionsByZoomIds(new Set<String>{ '1' }).get('1').Webinar_Id__c,
            'Sessions must be keyed by Zoom ID');
    }
}