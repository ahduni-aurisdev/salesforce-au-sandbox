/**
 * @description Tests for ZoomSelector.
 * @author AU Development Team
 * @date 2026-11-02
 * @version 1.0
 * @lastModified 2026-11-02
 */
@IsTest
private class ZoomSelectorTest {
    private static final String SHARED_EMAIL = 'shared.selector@zoomtest.com';
    private static final String VALID_MOBILE = '9876543210';

    @IsTest
    static void emptyInputsReturnEmptyResults() {
        System.assert(ZoomSelector.selectSessionsByZoomIds(new Set<String>()).isEmpty(), 'No IDs must return no sessions');
        System.assert(ZoomSelector.selectRegistrationsByKeys(null).isEmpty(), 'No keys must return no registrations');
        System.assert(ZoomSelector.selectPeopleByEmail(new Set<String>()).isEmpty(), 'No emails must return no people');
    }

    @IsTest
    static void leadWinsOverContactAndOldestLeadWins() {
        Lead newer = new Lead(LastName = 'Newer', Company = 'X', Email = SHARED_EMAIL);
        Lead older = new Lead(LastName = 'Older', Company = 'X', Email = SHARED_EMAIL);
        insert new List<Lead>{ newer, older };
        Test.setCreatedDate(older.Id, Datetime.now().addDays(-5));
        Test.setCreatedDate(newer.Id, Datetime.now().addDays(-1));
        insert new Contact(LastName = 'Contact', Email = SHARED_EMAIL, MobilePhone = VALID_MOBILE);

        Map<String, SObject> matches = ZoomSelector.selectPeopleByEmail(new Set<String>{ SHARED_EMAIL });

        System.assertEquals(older.Id, matches.get(SHARED_EMAIL).Id, 'The oldest unconverted Lead must win over newer Leads and Contacts');
    }

    @IsTest
    static void contactMatchedWhenNoLead() {
        Contact contact = new Contact(LastName = 'Only', Email = 'only.contact@zoomtest.com', MobilePhone = VALID_MOBILE);
        insert contact;

        Map<String, SObject> matches = ZoomSelector.selectPeopleByEmail(new Set<String>{ 'only.contact@zoomtest.com' });

        System.assertEquals(contact.Id, matches.get('only.contact@zoomtest.com').Id, 'A Contact must match when no Lead has the email');
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