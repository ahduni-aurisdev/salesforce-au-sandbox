/**
 * @description SOQL for the Zoom integration: Zoom sessions, registrations, registrations of one session waiting
 *              for Lead processing, the Lead candidates used to match a registrant (email / phone within one
 *              Department record type and Admission Year), the Undergraduation Lead owner, and the user-mode
 *              queries behind the "Sync Leads to Salesforce" popup (ZoomLeadSyncController).
 * @author AU Development Team
 * @date 2026-11-02
 * @version 1.4
 * @lastModified 2026-11-05
 */
// System mode is intentional for the integration queries: callers are the Zoom webhook (Site guest user with no
// object access), the scheduled sync and the background Lead sync. Lead matching must see every Lead regardless of the running user's sharing,
// otherwise it would create duplicates of Leads the user cannot see. No record data from these is returned to a user.
// The popup queries (selectSessionForLeadSync*, selectRegistrationsForLeadSync, countRegistrations*) run in
// USER_MODE because their results are shown to, or changed by, the user.
public without sharing class ZoomSelector {
    private static final String STATUS_DELETED = 'Deleted';
    private static final String STATUS_ENDED = 'Ended';
    private static final Integer MAX_CANDIDATES = 2000;
    private static final Integer MAX_OWNER_USERS = 200;
    private static final Integer MAX_SYNC_REGISTRATIONS = 2000;
    private static final String USER_TYPE_STANDARD = 'Standard';

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
                Lead__c, Contact__c, Status__c, Registered_At__c, First_Name__c, Last_Name__c, Lead_Status__c
            FROM Zoom_Registration__c
            WHERE Registration_Key__c IN :keys
            WITH SYSTEM_MODE
        ]) {
            byKey.put(registration.Registration_Key__c, registration);
        }
        return byKey;
    }

    /** Registrations of one session waiting for a Lead, when the session has Department and Admission Year; oldest first. */
    public static List<Zoom_Registration__c> selectPendingLeadRegistrations(Id sessionId, String pendingStatus, Integer maxRows) {
        return [
            SELECT Id, Name, Email__c, Phone__c, First_Name__c, Last_Name__c, Is_Registered__c, Attended__c,
                First_Joined_At__c, Time_In_Session_Minutes__c, Lead__c, Lead_Status__c, Preferred_Programme__c,
                Registration_Task_Id__c, Attendance_Task_Id__c,
                Webinar__c, Webinar__r.Name, Webinar__r.Webinar_Id__c, Webinar__r.Type__c, Webinar__r.Status__c,
                Webinar__r.Start_Time__c, Webinar__r.Department__c, Webinar__r.Admission_Year__c
            FROM Zoom_Registration__c
            WHERE Webinar__c = :sessionId
                AND Lead_Status__c = :pendingStatus
                AND Webinar__r.Department__c != null
                AND Webinar__r.Admission_Year__c != null
            WITH SYSTEM_MODE
            ORDER BY CreatedDate ASC, Id ASC
            LIMIT :maxRows
        ];
    }

    /**
     * @description Linked registrations of one ended session that still need their attendance Task
     *              ("Attended" or, for registered people who never joined, "Did not attend").
     */
    public static List<Zoom_Registration__c> selectRegistrationsAwaitingAttendanceTask(Id sessionId, Set<String> linkedStatuses,
        Integer maxRows) {
        return [
            SELECT Id, Name, Email__c, Phone__c, First_Name__c, Last_Name__c, Is_Registered__c, Attended__c,
                First_Joined_At__c, Time_In_Session_Minutes__c, Lead__c, Lead_Status__c, Preferred_Programme__c,
                Registration_Task_Id__c, Attendance_Task_Id__c,
                Webinar__c, Webinar__r.Name, Webinar__r.Webinar_Id__c, Webinar__r.Type__c, Webinar__r.Status__c,
                Webinar__r.Start_Time__c, Webinar__r.Department__c, Webinar__r.Admission_Year__c
            FROM Zoom_Registration__c
            WHERE Webinar__c = :sessionId
                AND Lead__c != null
                AND Attendance_Task_Id__c = null
                AND Lead_Status__c IN :linkedStatuses
                AND Webinar__r.Status__c = :STATUS_ENDED
                AND (Attended__c = true OR Is_Registered__c = true)
            WITH SYSTEM_MODE
            ORDER BY CreatedDate ASC, Id ASC
            LIMIT :maxRows
        ];
    }

    /**
     * @description Unconverted Leads of the given record types and admission years whose email is one of the
     *              given lower-case emails or whose Mobile / Phone ends with one of the given 10-digit numbers.
     *              Oldest first, so the caller can let the oldest match win.
     * @param lastTenDigits digits only (caller guarantees this), so they are safe to inline in LIKE clauses
     */
    public static List<Lead> selectLeadCandidates(Set<Id> recordTypeIds, Set<String> admissionYears,
        Set<String> lowerCaseEmails, Set<String> lastTenDigits) {
        if (recordTypeIds.isEmpty() || admissionYears.isEmpty() || (lowerCaseEmails.isEmpty() && lastTenDigits.isEmpty())) {
            return new List<Lead>();
        }
        List<String> contactConditions = new List<String>();
        if (!lowerCaseEmails.isEmpty()) {
            contactConditions.add('Email IN :lowerCaseEmails');
        }
        for (String digits : lastTenDigits) {
            contactConditions.add('MobilePhone LIKE \'%' + digits + '\'');
            contactConditions.add('Phone LIKE \'%' + digits + '\'');
        }
        String soql = 'SELECT Id, OwnerId, RecordTypeId, Admission_Year__c, Email, MobilePhone, Phone, FirstName, Department__c, Preferred_Programme__c'
            + ' FROM Lead WHERE IsConverted = false AND RecordTypeId IN :recordTypeIds AND Admission_Year__c IN :admissionYears'
            + ' AND (' + String.join(contactConditions, ' OR ') + ')'
            + ' ORDER BY CreatedDate ASC, Id ASC LIMIT ' + MAX_CANDIDATES;
        return Database.queryWithBinds(soql, new Map<String, Object>{
            'lowerCaseEmails' => lowerCaseEmails,
            'recordTypeIds' => recordTypeIds,
            'admissionYears' => admissionYears
        }, AccessLevel.SYSTEM_MODE);
    }

    public static Map<Id, Lead> selectLeadOwners(Set<Id> leadIds) {
        if (leadIds == null || leadIds.isEmpty()) {
            return new Map<Id, Lead>();
        }
        return new Map<Id, Lead>([SELECT Id, OwnerId FROM Lead WHERE Id IN :leadIds WITH SYSTEM_MODE]);
    }

    /** The active standard user with this username (Undergraduation Lead owner), or null. */
    public static User selectActiveUserByUsername(String username) {
        if (String.isBlank(username)) {
            return null;
        }
        String trimmed = username.trim();
        List<User> users = [
            SELECT Id, Name, SmallPhotoUrl
            FROM User
            WHERE IsActive = true AND UserType = :USER_TYPE_STANDARD AND Username = :trimmed
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return users.isEmpty() ? null : users[0];
    }

    /** The session for the sync popup, in the running user's access. */
    public static List<Zoom_Webinar__c> selectSessionForLeadSync(Id sessionId) {
        return [
            SELECT Id, Name, Type__c, Status__c, Start_Time__c, Department__c, Admission_Year__c,
                Lead_Sync_Started_At__c, Last_Lead_Sync_At__c, Last_Lead_Sync_By__r.Name
            FROM Zoom_Webinar__c
            WHERE Id = :sessionId
            WITH USER_MODE
            LIMIT 1
        ];
    }

    /** The session row locked while a sync starts, so two users cannot start the same sync at once. */
    public static List<Zoom_Webinar__c> selectSessionForLeadSyncUpdate(Id sessionId) {
        return [
            SELECT Id, Name, Status__c, Department__c, Admission_Year__c, Lead_Sync_Started_At__c, Last_Lead_Sync_At__c
            FROM Zoom_Webinar__c
            WHERE Id = :sessionId
            WITH USER_MODE
            LIMIT 1
            FOR UPDATE
        ];
    }

    /** Registrations of the session with the given Lead Statuses, for the sync popup; in the running user's access. */
    public static List<Zoom_Registration__c> selectRegistrationsForLeadSync(Id sessionId, Set<String> leadStatuses) {
        return [
            SELECT Id, Name, First_Name__c, Last_Name__c, Email__c, Phone__c, Is_Registered__c, Attended__c,
                Lead_Status__c, Preferred_Programme__c
            FROM Zoom_Registration__c
            WHERE Webinar__c = :sessionId AND Lead_Status__c IN :leadStatuses
            WITH USER_MODE
            ORDER BY Last_Name__c ASC NULLS LAST, First_Name__c ASC NULLS LAST, Id ASC
            LIMIT :MAX_SYNC_REGISTRATIONS
        ];
    }

    /** Registration count per Lead Status for the session; in the running user's access. */
    public static Map<String, Integer> countRegistrationsByLeadStatus(Id sessionId) {
        Map<String, Integer> counts = new Map<String, Integer>();
        for (AggregateResult row : [
            SELECT Lead_Status__c leadStatus, COUNT(Id) total
            FROM Zoom_Registration__c
            WHERE Webinar__c = :sessionId
            WITH USER_MODE
            GROUP BY Lead_Status__c
        ]) {
            counts.put((String) row.get('leadStatus'), (Integer) row.get('total'));
        }
        return counts;
    }

    /** Linked registrations of the session still without an attendance Task (counts once it has ended); user access. */
    public static Integer countRegistrationsAwaitingAttendance(Id sessionId, Set<String> linkedStatuses) {
        return [
            SELECT COUNT()
            FROM Zoom_Registration__c
            WHERE Webinar__c = :sessionId
                AND Lead__c != null
                AND Attendance_Task_Id__c = null
                AND Lead_Status__c IN :linkedStatuses
                AND (Attended__c = true OR Is_Registered__c = true)
            WITH USER_MODE
        ];
    }

    /** Active standard users with one of the given lower-case emails, oldest user first. */
    public static List<User> selectActiveUsersByEmail(Set<String> lowerCaseEmails) {
        if (lowerCaseEmails == null || lowerCaseEmails.isEmpty()) {
            return new List<User>();
        }
        return [
            SELECT Id, Email
            FROM User
            WHERE IsActive = true AND UserType = :USER_TYPE_STANDARD AND Email IN :lowerCaseEmails
            WITH SYSTEM_MODE
            ORDER BY CreatedDate ASC, Id ASC
            LIMIT :MAX_OWNER_USERS
        ];
    }
}