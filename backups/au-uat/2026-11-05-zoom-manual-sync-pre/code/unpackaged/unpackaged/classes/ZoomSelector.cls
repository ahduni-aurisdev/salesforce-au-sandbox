/**
 * @description SOQL for the Zoom integration: Zoom sessions, registrations, registrations waiting for Lead
 *              processing, and the Lead candidates used to match a registrant (email / phone within one
 *              Department record type and Admission Year), and the users who own new Zoom Leads.
 * @author AU Development Team
 * @date 2026-11-02
 * @version 1.3
 * @lastModified 2026-11-04
 */
// System mode is intentional: callers are the Zoom webhook (Site guest user with no object access)
// and the scheduled sync. Lead matching must see every Lead regardless of the running user's sharing,
// otherwise it would create duplicates of Leads the user cannot see. No record data is returned to a user.
public without sharing class ZoomSelector {
    private static final String STATUS_DELETED = 'Deleted';
    private static final String STATUS_ENDED = 'Ended';
    private static final Integer MAX_CANDIDATES = 2000;
    private static final Integer MAX_OWNER_USERS = 200;
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

    /** Registrations waiting for a Lead whose session has both Department and Admission Year set; oldest first. */
    public static List<Zoom_Registration__c> selectPendingLeadRegistrations(String pendingStatus, Integer maxRows) {
        return [
            SELECT Id, Name, Email__c, Phone__c, First_Name__c, Last_Name__c, Is_Registered__c, Attended__c,
                First_Joined_At__c, Time_In_Session_Minutes__c, Lead__c, Lead_Status__c,
                Registration_Task_Id__c, Attendance_Task_Id__c,
                Webinar__c, Webinar__r.Name, Webinar__r.Webinar_Id__c, Webinar__r.Type__c, Webinar__r.Status__c,
                Webinar__r.Start_Time__c, Webinar__r.Department__c, Webinar__r.Admission_Year__c,
                Webinar__r.Preferred_Programme__c
            FROM Zoom_Registration__c
            WHERE Lead_Status__c = :pendingStatus
                AND Webinar__r.Department__c != null
                AND Webinar__r.Admission_Year__c != null
            WITH SYSTEM_MODE
            ORDER BY CreatedDate ASC, Id ASC
            LIMIT :maxRows
        ];
    }

    /**
     * @description Linked registrations of ended sessions that still need their attendance Task
     *              ("Attended" or, for registered people who never joined, "Did not attend").
     */
    public static List<Zoom_Registration__c> selectRegistrationsAwaitingAttendanceTask(Set<String> linkedStatuses, Integer maxRows) {
        return [
            SELECT Id, Name, Email__c, Phone__c, First_Name__c, Last_Name__c, Is_Registered__c, Attended__c,
                First_Joined_At__c, Time_In_Session_Minutes__c, Lead__c, Lead_Status__c,
                Registration_Task_Id__c, Attendance_Task_Id__c,
                Webinar__c, Webinar__r.Name, Webinar__r.Webinar_Id__c, Webinar__r.Type__c, Webinar__r.Status__c,
                Webinar__r.Start_Time__c, Webinar__r.Department__c, Webinar__r.Admission_Year__c
            FROM Zoom_Registration__c
            WHERE Lead__c != null
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

    /**
     * @description Active standard users with the given User Department, Role name and Profile name, oldest user
     *              first (a stable order for the Zoom Lead owner round-robin).
     */
    public static List<User> selectLeadOwnerUsers(String department, String roleName, String profileName) {
        if (String.isBlank(department) || String.isBlank(roleName) || String.isBlank(profileName)) {
            return new List<User>();
        }
        return [
            SELECT Id
            FROM User
            WHERE IsActive = true AND UserType = :USER_TYPE_STANDARD
                AND Department = :department.trim() AND UserRole.Name = :roleName.trim() AND Profile.Name = :profileName.trim()
            WITH SYSTEM_MODE
            ORDER BY CreatedDate ASC, Id ASC
            LIMIT :MAX_OWNER_USERS
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