/**
 * @description SOQL for the Zoom integration: Zoom sessions, registrations, and Lead / Contact matching by email.
 * @author AU Development Team
 * @date 2026-11-02
 * @version 1.0
 * @lastModified 2026-11-02
 */
// System mode is intentional: callers are the Zoom webhook (Site guest user with no object access)
// and the scheduled sync. Neither returns record data to a user; access to the endpoint is
// controlled by the Zoom HMAC signature check in ZoomWebhook.
public without sharing class ZoomSelector {
    private static final String STATUS_DELETED = 'Deleted';

    public static Map<String, Zoom_Webinar__c> selectSessionsByZoomIds(Set<String> zoomIds) {
        Map<String, Zoom_Webinar__c> byZoomId = new Map<String, Zoom_Webinar__c>();
        if (zoomIds == null || zoomIds.isEmpty()) {
            return byZoomId;
        }
        for (Zoom_Webinar__c session : [
            SELECT Id, Name, Webinar_Id__c, Type__c, Status__c, Start_Time__c
            FROM Zoom_Webinar__c
            WHERE Webinar_Id__c IN :zoomIds
            WITH SYSTEM_MODE
        ]) {
            byZoomId.put(session.Webinar_Id__c, session);
        }
        return byZoomId;
    }

    /** Sessions that started on or after the given time and are not deleted: they may still need attendance. */
    public static List<Zoom_Webinar__c> selectRecentSessions(Datetime startedOnOrAfter) {
        return [
            SELECT Id, Webinar_Id__c, Type__c
            FROM Zoom_Webinar__c
            WHERE Start_Time__c >= :startedOnOrAfter AND Status__c != :STATUS_DELETED
            WITH SYSTEM_MODE
        ];
    }

    public static Map<String, Zoom_Registration__c> selectRegistrationsByKeys(Set<String> keys) {
        Map<String, Zoom_Registration__c> byKey = new Map<String, Zoom_Registration__c>();
        if (keys == null || keys.isEmpty()) {
            return byKey;
        }
        for (Zoom_Registration__c registration : [
            SELECT Id, Registration_Key__c, Is_Registered__c, Attended__c, First_Joined_At__c, Last_Joined_At__c,
                Last_Left_At__c, Time_In_Session_Minutes__c, Registration_Task_Id__c, Attendance_Task_Id__c,
                Lead__c, Contact__c, Status__c, Registered_At__c
            FROM Zoom_Registration__c
            WHERE Registration_Key__c IN :keys
            WITH SYSTEM_MODE
        ]) {
            byKey.put(registration.Registration_Key__c, registration);
        }
        return byKey;
    }

    /**
     * @description Finds the record to log activity on for each lower-case email. An unconverted Lead wins
     *              over a Contact; among several records with the same email the oldest wins.
     */
    public static Map<String, SObject> selectPeopleByEmail(Set<String> lowerCaseEmails) {
        Map<String, SObject> byEmail = new Map<String, SObject>();
        if (lowerCaseEmails == null || lowerCaseEmails.isEmpty()) {
            return byEmail;
        }
        for (Lead lead : [
            SELECT Id, Email, OwnerId
            FROM Lead
            WHERE Email IN :lowerCaseEmails AND IsConverted = false
            WITH SYSTEM_MODE
            ORDER BY CreatedDate ASC, Id ASC
        ]) {
            String key = lead.Email.toLowerCase();
            if (!byEmail.containsKey(key)) {
                byEmail.put(key, lead);
            }
        }
        for (Contact contact : [
            SELECT Id, Email, OwnerId
            FROM Contact
            WHERE Email IN :lowerCaseEmails
            WITH SYSTEM_MODE
            ORDER BY CreatedDate ASC, Id ASC
        ]) {
            String key = contact.Email.toLowerCase();
            if (!byEmail.containsKey(key)) {
                byEmail.put(key, contact);
            }
        }
        return byEmail;
    }
}