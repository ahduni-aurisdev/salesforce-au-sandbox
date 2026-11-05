/**
 * @description Controller for the "Sync Leads to Salesforce" quick action (LWC zoomLeadSyncAction, which opens zoomLeadSyncModal) on a Zoom Session.
 *              getSyncContext loads the session, its students that are not synced yet (and those in Error, which
 *              are retried), the department list and the sync status. startSync validates the user's choices
 *              (Department, Admission Year, per-student Preferred Programme), saves them, locks the session and
 *              enqueues ZoomLeadQueueable for that session only. getSyncProgress reports the counts while the
 *              background job runs; getSyncResults lists every processed student with their Lead afterwards.
 *              Rules (user decision 2026-11-05, docs/requirements/req_zoom-integration.md):
 *                - Department and Admission Year are required and locked once any student of the session is synced.
 *                - Admission Year must be an active Lead.Admission_Year__c value; the popup preselects Zoom_Config
 *                  Default_Admission_Year__c (fallback: the Lead picklist default).
 *                - Undergraduation: no programme; new Leads go to Zoom_Config UG_Lead_Owner_Username__c (sync is
 *                  blocked when that user is missing or inactive).
 *                - Other departments: optional programme per student, an active Lead.Preferred_Programme__c value.
 *                - One sync per session at a time (Lead_Sync_Started_At__c; older than STALE_MINUTES = stale).
 *              Governor use: getSyncContext 5 SOQL; startSync 6 SOQL + 2 DML + 1 enqueue (+1 log insert on failure); getSyncProgress 3 SOQL.
 * @author AU Development Team
 * @date 2026-11-05
 * @version 1.1
 * @lastModified 2026-11-05
 */
public with sharing class ZoomLeadSyncController {
    @TestVisible
    private static final String PERMISSION_SYNC = 'Zoom_Sync_Leads';
    private static final String FLAG_INTEGRATION = 'Zoom_Integration';
    private static final String LOG_NAME = 'ZoomLeadService';
    private static final String CLASS_NAME = 'ZoomLeadSyncController';
    private static final String STATUS_ENDED = 'Ended';
    @TestVisible
    private static final Integer STALE_MINUTES = 30;
    private static final String PARTICIPATION_REGISTERED = 'Registered';
    private static final String PARTICIPATION_WALK_IN = 'Walk-in';
    private static final String NAME_SEPARATOR = ' ';
    private static final String NO_NAME = '(No name)';
    private static final Set<String> OPEN_STATUSES = new Set<String>{
        ZoomLeadService.LEAD_STATUS_PENDING, ZoomLeadService.LEAD_STATUS_ERROR
    };

    @TestVisible
    private static final String MSG_NO_PERMISSION = 'You do not have permission to sync Zoom Leads. Ask your Salesforce admin for the Zoom Webinar Full Access permission set.';
    @TestVisible
    private static final String MSG_INTEGRATION_OFF = 'The Zoom integration is switched off. Ask your Salesforce admin to enable Feature Flag Zoom_Integration.';
    @TestVisible
    private static final String MSG_SESSION_NOT_FOUND = 'This Zoom session was not found or you do not have access to it. Refresh the page and try again.';
    @TestVisible
    private static final String MSG_RUNNING = 'A sync for this session is already running. Wait for it to finish, then try again.';
    @TestVisible
    private static final String MSG_DEPARTMENT_REQUIRED = 'Select a valid department and try again.';
    @TestVisible
    private static final String MSG_YEAR_REQUIRED = 'Select a valid admission year and try again.';
    @TestVisible
    private static final String MSG_LOCKED = 'Department and admission year cannot change after students of this session were synced.';
    @TestVisible
    private static final String MSG_UG_OWNER_MISSING = 'The Undergraduation Lead owner is not set up or is inactive. Ask your Salesforce admin to check Zoom Config "UG Lead Owner Username".';
    @TestVisible
    private static final String MSG_INVALID_PROGRAMME = 'One or more programmes are not valid Lead programmes. Choose them again and retry.';
    @TestVisible
    private static final String MSG_INVALID_STUDENT = 'Some students changed since the window opened. Close it, reopen and try again.';
    @TestVisible
    private static final String MSG_NOTHING_TO_SYNC = 'Everything on this session is already synced. New registrations and attendance can be synced when they arrive.';
    @TestVisible
    private static final String MSG_SAVE_FAILED = 'The sync could not start because the session could not be saved. Try again, or contact your Salesforce admin if it keeps failing.';

    /** Test hook: makes the save in startSync fail, to exercise the rollback and logging path. */
    @TestVisible
    private static Boolean simulateSaveFailure = false;

    /** Thrown for every expected validation failure; converted to an AuraHandledException with a readable message. */
    public class ZoomLeadSyncException extends Exception {
    }

    // ── Wrappers ────────────────────────────────────────────────────────────────────────────────────────────────

    public class DepartmentOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        @AuraEnabled public Id recordTypeId;
        @AuraEnabled public Boolean isUndergraduation;
    }

    public class Student {
        @AuraEnabled public Id registrationId;
        @AuraEnabled public String name;
        @AuraEnabled public String email;
        @AuraEnabled public String phone;
        @AuraEnabled public String participation;
        @AuraEnabled public Boolean attended;
        @AuraEnabled public String programme;
        @AuraEnabled public Boolean hasError;
    }

    public class SyncProgress {
        @AuraEnabled public Boolean isRunning;
        @AuraEnabled public Boolean hasEnded;
        @AuraEnabled public Integer total;
        @AuraEnabled public Integer notSynced;
        @AuraEnabled public Integer created;
        @AuraEnabled public Integer updated;
        @AuraEnabled public Integer noContact;
        @AuraEnabled public Integer errors;
        @AuraEnabled public Integer attendancePending;
        @AuraEnabled public Datetime lastSyncAt;
        @AuraEnabled public Datetime syncStartedAt;
    }

    /** One student in the after-sync summary, with the Lead it was linked to. */
    public class SyncResult {
        @AuraEnabled public Id registrationId;
        @AuraEnabled public String name;
        @AuraEnabled public String email;
        @AuraEnabled public String phone;
        @AuraEnabled public String participation;
        @AuraEnabled public String result;
        @AuraEnabled public Id leadId;
        @AuraEnabled public String leadName;
        @AuraEnabled public String leadStatus;
        @AuraEnabled public String ownerName;
        @AuraEnabled public String programme;
    }

    public class SyncContext {
        @AuraEnabled public Id sessionId;
        @AuraEnabled public String sessionName;
        @AuraEnabled public String sessionType;
        @AuraEnabled public String sessionStatus;
        @AuraEnabled public Datetime startTime;
        @AuraEnabled public String department;
        @AuraEnabled public String admissionYear;
        @AuraEnabled public Boolean isLocked;
        @AuraEnabled public Boolean canSync;
        @AuraEnabled public String blockedReason;
        @AuraEnabled public String undergraduationOwnerName;
        @AuraEnabled public String lastSyncByName;
        @AuraEnabled public String defaultAdmissionYear;
        @AuraEnabled public String undergraduationOwnerPhoto;
        @AuraEnabled public List<DepartmentOption> departments;
        @AuraEnabled public List<Student> students;
        @AuraEnabled public SyncProgress progress;
    }

    /** Outcome of startSync: started with the first progress, or not started with a readable message. */
    public class StartResult {
        @AuraEnabled public Boolean started;
        @AuraEnabled public String message;
        @AuraEnabled public SyncProgress progress;
    }

    /** One student's programme choice sent by the popup. */
    public class StudentProgramme {
        @AuraEnabled public Id registrationId { get; set; }
        @AuraEnabled public String programme { get; set; }
    }

    // ── Aura methods ───────────────────────────────────────────────────────────────────────────────────────────────

    /** Everything the popup needs to render. Not cacheable: counts change while a sync runs. */
    @AuraEnabled
    public static SyncContext getSyncContext(Id sessionId) {
        if (!FeatureManagement.checkPermission(PERMISSION_SYNC)) {
            // Without the permission set the user may not read the Zoom fields, so show only the reason.
            return blockedContext(sessionId, MSG_NO_PERMISSION);
        }
        try {
            Zoom_Webinar__c session = requireSession(sessionId);
            SyncContext context = new SyncContext();
            context.sessionId = session.Id;
            context.sessionName = session.Name;
            context.sessionType = session.Type__c;
            context.sessionStatus = session.Status__c;
            context.startTime = session.Start_Time__c;
            context.department = session.Department__c;
            context.admissionYear = session.Admission_Year__c;
            context.lastSyncByName = session.Last_Lead_Sync_By__r == null ? null : session.Last_Lead_Sync_By__r.Name;
            context.progress = progressOf(session);
            context.isLocked = isLocked(session, context.progress);
            context.departments = departmentOptions();
            User owner = ZoomLeadService.undergraduationOwner();
            context.undergraduationOwnerName = owner == null ? null : owner.Name;
            context.undergraduationOwnerPhoto = owner == null ? null : owner.SmallPhotoUrl;
            context.defaultAdmissionYear = defaultAdmissionYear();
            context.blockedReason = blockedReason();
            context.canSync = context.blockedReason == null;
            context.students = studentsOf(ZoomSelector.selectRegistrationsForLeadSync(sessionId, OPEN_STATUSES));
            return context;
        } catch (ZoomLeadSyncException e) {
            throw auraError(e.getMessage());
        }
    }

    /** Counts for the progress display while the background sync runs. */
    @AuraEnabled
    public static SyncProgress getSyncProgress(Id sessionId) {
        try {
            if (!FeatureManagement.checkPermission(PERMISSION_SYNC)) {
                throw new ZoomLeadSyncException(MSG_NO_PERMISSION);
            }
            return progressOf(requireSession(sessionId));
        } catch (ZoomLeadSyncException e) {
            throw auraError(e.getMessage());
        }
    }

    /**
     * @description After-sync summary: every student of the session processed since the sync started (all synced
     *              students when since is null), with the linked Lead, its owner, status and programme. Failed
     *              students come first. Runs in the user's access (Lead fields the user cannot read are left out).
     * @param since the sync start time captured by the popup; null = all synced students
     */
    @AuraEnabled
    public static List<SyncResult> getSyncResults(Id sessionId, Datetime since) {
        try {
            if (!FeatureManagement.checkPermission(PERMISSION_SYNC)) {
                throw new ZoomLeadSyncException(MSG_NO_PERMISSION);
            }
            requireSession(sessionId);
            List<SyncResult> failed = new List<SyncResult>();
            List<SyncResult> others = new List<SyncResult>();
            List<Zoom_Registration__c> registrations = ZoomSelector.selectSyncedRegistrations(sessionId, since);
            Set<Id> ownerIds = new Set<Id>();
            for (Zoom_Registration__c registration : registrations) {
                if (registration.Lead__r != null && registration.Lead__r.OwnerId != null) {
                    ownerIds.add(registration.Lead__r.OwnerId);
                }
            }
            Map<Id, String> ownerNames = ZoomSelector.selectOwnerNames(ownerIds);
            for (Zoom_Registration__c registration : registrations) {
                SyncResult row = resultOf(registration, ownerNames);
                if (registration.Lead_Status__c == ZoomLeadService.LEAD_STATUS_ERROR) {
                    failed.add(row);
                } else {
                    others.add(row);
                }
            }
            failed.addAll(others);
            return failed;
        } catch (ZoomLeadSyncException e) {
            throw auraError(e.getMessage());
        }
    }

    private static SyncResult resultOf(Zoom_Registration__c registration, Map<Id, String> ownerNames) {
        SyncResult row = new SyncResult();
        row.registrationId = registration.Id;
        String fullName = String.join(new List<String>{
            registration.First_Name__c == null ? '' : registration.First_Name__c,
            registration.Last_Name__c == null ? '' : registration.Last_Name__c
        }, NAME_SEPARATOR).normalizeSpace();
        row.name = String.isBlank(fullName) ? NO_NAME : fullName;
        row.email = registration.Email__c;
        row.phone = registration.Phone__c;
        row.participation = registration.Is_Registered__c == true ? PARTICIPATION_REGISTERED : PARTICIPATION_WALK_IN;
        row.result = registration.Lead_Status__c;
        if (registration.Lead__r != null) {
            row.leadId = registration.Lead__c;
            row.leadName = registration.Lead__r.Name;
            row.leadStatus = registration.Lead__r.Status;
            row.ownerName = ownerNames.get(registration.Lead__r.OwnerId);
            row.programme = registration.Lead__r.Preferred_Programme__c;
        }
        return row;
    }

    /** Context for a user who may not sync: no record data, only the reason and empty lists. */
    private static SyncContext blockedContext(Id sessionId, String reason) {
        SyncContext context = new SyncContext();
        context.sessionId = sessionId;
        context.canSync = false;
        context.blockedReason = reason;
        context.isLocked = false;
        context.departments = new List<DepartmentOption>();
        context.students = new List<Student>();
        SyncProgress progress = new SyncProgress();
        progress.isRunning = false;
        progress.hasEnded = false;
        progress.total = 0;
        progress.notSynced = 0;
        progress.created = 0;
        progress.updated = 0;
        progress.noContact = 0;
        progress.errors = 0;
        progress.attendancePending = 0;
        context.progress = progress;
        return context;
    }

    /**
     * @description Validates and saves the popup choices, locks the session and starts the background sync.
     * @param programmes one entry per student whose programme is set (ignored for Undergraduation)
     */
    @AuraEnabled
    public static StartResult startSync(Id sessionId, String department, String admissionYear, List<StudentProgramme> programmes) {
        try {
            String blocked = blockedReason();
            if (blocked != null) {
                throw new ZoomLeadSyncException(blocked);
            }
            List<Zoom_Webinar__c> locked = ZoomSelector.selectSessionForLeadSyncUpdate(sessionId);
            if (locked.isEmpty()) {
                throw new ZoomLeadSyncException(MSG_SESSION_NOT_FOUND);
            }
            Zoom_Webinar__c session = locked[0];
            if (isRunning(session)) {
                throw new ZoomLeadSyncException(MSG_RUNNING);
            }
            String departmentValue = validDepartment(department);
            if (!ZoomLeadService.isActiveLeadAdmissionYear(admissionYear)) {
                throw new ZoomLeadSyncException(MSG_YEAR_REQUIRED);
            }
            SyncProgress before = progressOf(session);
            if (isLocked(session, before) && (session.Department__c != departmentValue || session.Admission_Year__c != admissionYear)) {
                throw new ZoomLeadSyncException(MSG_LOCKED);
            }
            Boolean undergraduation = ZoomLeadService.isUndergraduation(departmentValue);
            if (undergraduation && ZoomLeadService.undergraduationOwner() == null) {
                throw new ZoomLeadSyncException(MSG_UG_OWNER_MISSING);
            }
            Integer attendanceToLog = before.hasEnded ? before.attendancePending : 0;
            if (before.notSynced + before.errors == 0 && attendanceToLog == 0) {
                throw new ZoomLeadSyncException(MSG_NOTHING_TO_SYNC);
            }

            List<Zoom_Registration__c> registrationUpdates = registrationUpdates(sessionId, undergraduation, programmes);
            // Only the fields the user sets, so user-mode FLS is checked on exactly these.
            Zoom_Webinar__c sessionUpdate = new Zoom_Webinar__c(Id = session.Id, Department__c = departmentValue,
                Admission_Year__c = admissionYear, Lead_Sync_Started_At__c = Datetime.now(), Last_Lead_Sync_By__c = UserInfo.getUserId());
            session.Lead_Sync_Started_At__c = sessionUpdate.Lead_Sync_Started_At__c;

            StartResult result = new StartResult();
            Savepoint beforeSave = Database.setSavepoint();
            try {
                if (Test.isRunningTest() && simulateSaveFailure) {
                    throw new DmlException('Simulated save failure');
                }
                Database.update(new List<SObject>{ sessionUpdate }, true, AccessLevel.USER_MODE);
                if (!registrationUpdates.isEmpty()) {
                    Database.update(registrationUpdates, true, AccessLevel.USER_MODE);
                }
            } catch (DmlException e) {
                // Returned, not thrown: a thrown Aura exception would also roll back the API_Log__c record.
                Database.rollback(beforeSave);
                ZoomLogger.logFailure(LOG_NAME, CLASS_NAME, sessionId, e);
                result.started = false;
                result.message = MSG_SAVE_FAILED;
                return result;
            }
            ZoomLeadQueueable.start(sessionId);
            result.started = true;
            result.progress = progressOf(session);
            return result;
        } catch (ZoomLeadSyncException e) {
            throw auraError(e.getMessage());
        }
    }

    // ── Helpers ────────────────────────────────────────────────────────────────────────────────────────────────────

    /**
     * @description Admission Year preselected in the popup: Zoom_Config Default_Admission_Year__c (e.g. "Admission
     *              Year - 2027", changed by the admin each cycle) when it is an active Lead year, otherwise null so the
     *              popup falls back to the Lead picklist default of the chosen department.
     */
    private static String defaultAdmissionYear() {
        String configured = ZoomConfig.get().Default_Admission_Year__c;
        String trimmed = configured == null ? null : configured.trim();
        return ZoomLeadService.isActiveLeadAdmissionYear(trimmed) ? trimmed : null;
    }

    /** Null when the user may sync, otherwise the reason shown in the popup. */
    private static String blockedReason() {
        if (!FeatureManagement.checkPermission(PERMISSION_SYNC)) {
            return MSG_NO_PERMISSION;
        }
        if (!FeatureFlagService.isEnabled(FLAG_INTEGRATION)) {
            return MSG_INTEGRATION_OFF;
        }
        return null;
    }

    private static Zoom_Webinar__c requireSession(Id sessionId) {
        List<Zoom_Webinar__c> sessions = sessionId == null ? new List<Zoom_Webinar__c>() : ZoomSelector.selectSessionForLeadSync(sessionId);
        if (sessions.isEmpty()) {
            throw new ZoomLeadSyncException(MSG_SESSION_NOT_FOUND);
        }
        return sessions[0];
    }

    private static Boolean isRunning(Zoom_Webinar__c session) {
        return session.Lead_Sync_Started_At__c != null
            && session.Lead_Sync_Started_At__c > Datetime.now().addMinutes(-STALE_MINUTES);
    }

    /** Department and Year are locked once any student of a set-up session left "Not synced". */
    private static Boolean isLocked(Zoom_Webinar__c session, SyncProgress progress) {
        return String.isNotBlank(session.Department__c) && String.isNotBlank(session.Admission_Year__c)
            && progress.total > progress.notSynced;
    }

    private static SyncProgress progressOf(Zoom_Webinar__c session) {
        Map<String, Integer> counts = ZoomSelector.countRegistrationsByLeadStatus(session.Id);
        SyncProgress progress = new SyncProgress();
        progress.isRunning = isRunning(session);
        progress.hasEnded = session.Status__c == STATUS_ENDED;
        progress.notSynced = countOf(counts, ZoomLeadService.LEAD_STATUS_PENDING);
        progress.created = countOf(counts, ZoomLeadService.LEAD_STATUS_CREATED);
        progress.updated = countOf(counts, ZoomLeadService.LEAD_STATUS_UPDATED);
        progress.noContact = countOf(counts, ZoomLeadService.LEAD_STATUS_NO_CONTACT);
        progress.errors = countOf(counts, ZoomLeadService.LEAD_STATUS_ERROR);
        progress.total = 0;
        for (Integer count : counts.values()) {
            progress.total += count;
        }
        progress.attendancePending = progress.hasEnded
            ? ZoomSelector.countRegistrationsAwaitingAttendance(session.Id, ZoomLeadService.LINKED_STATUSES)
            : 0;
        progress.lastSyncAt = session.Last_Lead_Sync_At__c;
        progress.syncStartedAt = session.Lead_Sync_Started_At__c;
        return progress;
    }

    private static Integer countOf(Map<String, Integer> counts, String status) {
        return counts.containsKey(status) ? counts.get(status) : 0;
    }

    /** Session Department values whose Lead record type is active and available. Describe only, no SOQL. */
    private static List<DepartmentOption> departmentOptions() {
        Map<String, Schema.RecordTypeInfo> recordTypes = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName();
        List<DepartmentOption> options = new List<DepartmentOption>();
        for (Schema.PicklistEntry entry : Zoom_Webinar__c.Department__c.getDescribe().getPicklistValues()) {
            Schema.RecordTypeInfo info = recordTypes.get(entry.getValue());
            if (!entry.isActive() || info == null || !info.isActive()) {
                continue;
            }
            DepartmentOption option = new DepartmentOption();
            option.label = entry.getLabel();
            option.value = entry.getValue();
            option.recordTypeId = info.getRecordTypeId();
            option.isUndergraduation = ZoomLeadService.isUndergraduation(entry.getValue());
            options.add(option);
        }
        return options;
    }

    private static String validDepartment(String department) {
        for (DepartmentOption option : departmentOptions()) {
            if (option.value == department) {
                return option.value;
            }
        }
        throw new ZoomLeadSyncException(MSG_DEPARTMENT_REQUIRED);
    }

    private static List<Student> studentsOf(List<Zoom_Registration__c> registrations) {
        List<Student> students = new List<Student>();
        for (Zoom_Registration__c registration : registrations) {
            Student student = new Student();
            student.registrationId = registration.Id;
            String fullName = String.join(new List<String>{
                registration.First_Name__c == null ? '' : registration.First_Name__c,
                registration.Last_Name__c == null ? '' : registration.Last_Name__c
            }, NAME_SEPARATOR).normalizeSpace();
            student.name = String.isBlank(fullName) ? NO_NAME : fullName;
            student.email = registration.Email__c;
            student.phone = registration.Phone__c;
            student.participation = registration.Is_Registered__c == true ? PARTICIPATION_REGISTERED : PARTICIPATION_WALK_IN;
            student.attended = registration.Attended__c == true;
            student.programme = registration.Preferred_Programme__c;
            student.hasError = registration.Lead_Status__c == ZoomLeadService.LEAD_STATUS_ERROR;
            students.add(student);
        }
        return students;
    }

    /**
     * @description The registration changes for this sync: Error rows go back to "Not synced" so they are retried,
     *              and each open student gets the chosen programme (always blank for Undergraduation).
     */
    private static List<Zoom_Registration__c> registrationUpdates(Id sessionId, Boolean undergraduation,
        List<StudentProgramme> programmes) {
        Map<Id, String> programmeById = new Map<Id, String>();
        if (!undergraduation && programmes != null) {
            for (StudentProgramme choice : programmes) {
                if (choice == null || choice.registrationId == null || String.isBlank(choice.programme)) {
                    continue;
                }
                if (!ZoomLeadService.isActiveLeadProgramme(choice.programme)) {
                    throw new ZoomLeadSyncException(MSG_INVALID_PROGRAMME);
                }
                programmeById.put(choice.registrationId, choice.programme);
            }
        }
        Map<Id, Zoom_Registration__c> open = new Map<Id, Zoom_Registration__c>(
            ZoomSelector.selectRegistrationsForLeadSync(sessionId, OPEN_STATUSES));
        if (!open.keySet().containsAll(programmeById.keySet())) {
            throw new ZoomLeadSyncException(MSG_INVALID_STUDENT);
        }
        List<Zoom_Registration__c> updates = new List<Zoom_Registration__c>();
        for (Zoom_Registration__c registration : open.values()) {
            String programme = programmeById.get(registration.Id);
            Boolean retry = registration.Lead_Status__c == ZoomLeadService.LEAD_STATUS_ERROR;
            if (!retry && programme == registration.Preferred_Programme__c) {
                continue;
            }
            Zoom_Registration__c change = new Zoom_Registration__c(Id = registration.Id, Preferred_Programme__c = programme);
            if (retry) {
                change.Lead_Status__c = ZoomLeadService.LEAD_STATUS_PENDING;
            }
            updates.add(change);
        }
        return updates;
    }

    private static AuraHandledException auraError(String message) {
        AuraHandledException error = new AuraHandledException(message);
        error.setMessage(message);
        return error;
    }
}
