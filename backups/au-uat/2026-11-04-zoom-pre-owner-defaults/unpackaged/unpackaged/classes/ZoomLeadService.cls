/**
 * @description Creates or updates the Lead for each Zoom registration (registrants and walk-ins) once its
 *              session has a Department and Admission Year, links it to the registration and logs completed Tasks
 *              ("Zoom Meeting Registered" / "Attended" / "Did Not Attend"). Called only by ZoomLeadQueueable, which
 *              the scheduled ZoomWebinarSync starts; the webhook never creates Leads.
 *
 *              Matching (unconverted Leads only, same Record Type = session Department, same Admission Year):
 *                email and phone known  -> Lead email AND Lead mobile/phone (last 10 digits) must both match
 *                only email known       -> Lead email must match
 *                only phone known       -> Lead mobile/phone (last 10 digits) must match
 *                neither                -> no Lead, Lead Status "No contact details"
 *              The oldest matching Lead wins.
 *
 *              New Lead: Record Type and Department__c from the session Department, Admission_Year__c, name, email,
 *              mobile, Phone in the website format (country code + number, e.g. 91 + 10 digits), LeadSource and
 *              Multi_Select_Lead_Source__c = Zoom. Phone matters: the org Flow "Automation for Unqualified Status
 *              Incorrect Details" marks a Lead Unqualified when the standard Phone field is blank or not 10-15 characters. The owner comes from the Lead trigger
 *              (department round-robin), as for website Leads; Assignment Rules are not run.
 *              Existing Lead: only blank First Name, Email, Mobile, Phone and Department__c are filled; Lead Source,
 *              Most Recent Lead Source and Admission Year are never changed.
 *
 *              Governor use per call (up to BATCH_SIZE registrations): 2 SOQL, up to 4 DML statements + 1 log insert.
 *              Lead trigger work (owner round-robin, campaign membership) runs inside the Lead insert, so the caller keeps
 *              the batch at 100 registrations to stay well inside CPU limits.
 * @author AU Development Team
 * @date 2026-11-03
 * @version 1.1
 * @lastModified 2026-11-03
 */
// System mode is intentional: a scheduled system job. Matching must see every Lead regardless of the running
// user's sharing, otherwise it would create duplicates of Leads that user cannot see. No data is returned to a user.
public without sharing class ZoomLeadService {
    public static final String LEAD_STATUS_PENDING = 'Pending setup';
    public static final String LEAD_STATUS_CREATED = 'Lead created';
    public static final String LEAD_STATUS_UPDATED = 'Lead updated';
    public static final String LEAD_STATUS_NO_CONTACT = 'No contact details';
    public static final String LEAD_STATUS_ERROR = 'Error';
    public static final String LEAD_SOURCE_ZOOM = 'Zoom';
    public static final Set<String> LINKED_STATUSES = new Set<String>{ LEAD_STATUS_CREATED, LEAD_STATUS_UPDATED };

    @TestVisible
    private static final String LOG_NAME = 'ZoomLeadService';
    private static final String CLASS_NAME = 'ZoomLeadService';
    private static final String UNKNOWN_LAST_NAME = 'Unknown';
    private static final String STATUS_ENDED = 'Ended';
    private static final String TYPE_WEBINAR = 'Webinar';
    private static final String TASK_STATUS_COMPLETED = 'Completed';
    private static final String TASK_PRIORITY_NORMAL = 'Normal';
    private static final String DISPLAY_DATE_FORMAT = 'dd MMM yyyy hh:mm a';
    private static final String USER_ID_PREFIX = '005';
    private static final String KEY_SEPARATOR = '|';
    private static final Integer MIN_PHONE_DIGITS = 7;
    private static final Integer PHONE_KEY_LENGTH = 10;
    private static final Integer MAX_SUBJECT_LENGTH = 255;
    private static final Integer MAX_FIRST_NAME_LENGTH = 40;
    private static final Integer MAX_LAST_NAME_LENGTH = 80;
    private static final Integer MAX_EMAIL_LENGTH = 80;
    private static final Integer MAX_PHONE_LENGTH = 40;
    private static final Integer MAX_INTERNATIONAL_DIGITS = 15;
    private static final String INDIA_COUNTRY_CODE = '91';

    /**
     * @description Creates / links Leads for registrations in Lead Status "Pending setup" whose session has a
     *              Department and Admission Year, logs their Tasks and saves the new Lead Status on every one.
     *              A registration whose Lead or Task cannot be saved gets Lead Status "Error" and all failures of
     *              the call are written to one API_Log__c record.
     */
    public static void processPending(List<Zoom_Registration__c> registrations) {
        if (registrations == null || registrations.isEmpty()) {
            return;
        }
        Map<String, Schema.RecordTypeInfo> recordTypes = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName();
        Map<String, String> departmentLabels = departmentLabels();
        List<String> failures = new List<String>();

        Set<Id> recordTypeIds = new Set<Id>();
        Set<String> years = new Set<String>();
        Set<String> emails = new Set<String>();
        Set<String> phones = new Set<String>();
        List<Zoom_Registration__c> matchable = new List<Zoom_Registration__c>();
        for (Zoom_Registration__c registration : registrations) {
            String email = normalizeEmail(registration.Email__c);
            String phone = lastTen(registration.Phone__c);
            if (email == null && phone == null) {
                registration.Lead_Status__c = LEAD_STATUS_NO_CONTACT;
                continue;
            }
            Id recordTypeId = recordTypeIdOf(recordTypes, registration.Webinar__r.Department__c);
            if (recordTypeId == null) {
                registration.Lead_Status__c = LEAD_STATUS_ERROR;
                failures.add(registration.Name + ': Lead record type "' + registration.Webinar__r.Department__c + '" is missing or inactive');
                continue;
            }
            recordTypeIds.add(recordTypeId);
            years.add(registration.Webinar__r.Admission_Year__c);
            if (email != null) {
                emails.add(email);
            }
            if (phone != null) {
                phones.add(phone);
            }
            matchable.add(registration);
        }

        LeadIndex index = new LeadIndex(ZoomSelector.selectLeadCandidates(recordTypeIds, years, emails, phones));
        Map<Id, Lead> leadUpdates = new Map<Id, Lead>();
        Map<String, Lead> newLeadByKey = new Map<String, Lead>();
        List<Zoom_Registration__c> newLeadRegistrations = new List<Zoom_Registration__c>();
        List<String> newLeadKeys = new List<String>();
        for (Zoom_Registration__c registration : matchable) {
            Id recordTypeId = recordTypeIdOf(recordTypes, registration.Webinar__r.Department__c);
            String scope = recordTypeId + KEY_SEPARATOR + registration.Webinar__r.Admission_Year__c;
            String email = normalizeEmail(registration.Email__c);
            String phone = lastTen(registration.Phone__c);
            String departmentLabel = departmentLabels.get(registration.Webinar__r.Department__c);
            Lead match = index.find(scope, email, phone);
            if (match != null) {
                registration.Lead__c = match.Id;
                registration.Is_Matched__c = true;
                registration.Lead_Status__c = LEAD_STATUS_UPDATED;
                fillBlanks(match, registration, departmentLabel, leadUpdates);
                continue;
            }
            String newLeadKey = scope + KEY_SEPARATOR + email + KEY_SEPARATOR + phone;
            if (!newLeadByKey.containsKey(newLeadKey)) {
                newLeadByKey.put(newLeadKey, newLead(registration, recordTypeId, departmentLabel));
            }
            newLeadRegistrations.add(registration);
            newLeadKeys.add(newLeadKey);
        }

        Map<String, String> insertErrorByKey = insertLeads(newLeadByKey);
        for (Integer i = 0; i < newLeadRegistrations.size(); i++) {
            Zoom_Registration__c registration = newLeadRegistrations[i];
            String key = newLeadKeys[i];
            Lead created = newLeadByKey.get(key);
            if (created.Id != null) {
                registration.Lead__c = created.Id;
                registration.Is_Matched__c = true;
                registration.Lead_Status__c = LEAD_STATUS_CREATED;
            } else {
                registration.Lead_Status__c = LEAD_STATUS_ERROR;
                failures.add(registration.Name + ': Lead not created - ' + insertErrorByKey.get(key));
            }
        }
        failures.addAll(updateLeads(leadUpdates.values()));
        failures.addAll(createTasks(registrations));

        update registrations;
        logFailures(failures);
    }

    /**
     * @description Logs the attendance Task ("Attended" / "Did Not Attend") for linked registrations of ended
     *              sessions. A registration whose Task cannot be saved gets Lead Status "Error", so it is not
     *              picked up again.
     */
    public static void processAttendance(List<Zoom_Registration__c> registrations) {
        if (registrations == null || registrations.isEmpty()) {
            return;
        }
        List<String> failures = createTasks(registrations);
        update registrations;
        logFailures(failures);
    }

    /** Last 10 digits of a phone number, or null when it has fewer than MIN_PHONE_DIGITS digits. */
    @TestVisible
    private static String lastTen(String phone) {
        if (phone == null) {
            return null;
        }
        String digits = phone.replaceAll('[^0-9]', '');
        if (digits.length() < MIN_PHONE_DIGITS) {
            return null;
        }
        return digits.length() > PHONE_KEY_LENGTH ? digits.right(PHONE_KEY_LENGTH) : digits;
    }

    /**
     * @description Phone in the format website Leads use: digits only, with country code. A 10-digit number
     *              (after dropping leading zeros) is Indian and gets "91"; a longer number already has its country
     *              code and is kept (max 15 digits, the E.164 limit). Null when there are fewer than MIN_PHONE_DIGITS.
     */
    @TestVisible
    private static String standardPhone(String phone) {
        if (phone == null) {
            return null;
        }
        String digits = phone.replaceAll('[^0-9]', '').replaceFirst('^0+', '');
        if (digits.length() < MIN_PHONE_DIGITS) {
            return null;
        }
        if (digits.length() == PHONE_KEY_LENGTH) {
            return INDIA_COUNTRY_CODE + digits;
        }
        return digits.left(MAX_INTERNATIONAL_DIGITS);
    }

    private static String normalizeEmail(String email) {
        return String.isBlank(email) ? null : email.trim().toLowerCase();
    }

    private static Id recordTypeIdOf(Map<String, Schema.RecordTypeInfo> recordTypes, String developerName) {
        Schema.RecordTypeInfo info = developerName == null ? null : recordTypes.get(developerName);
        return info == null || !info.isActive() ? null : info.getRecordTypeId();
    }

    /** Session Department picklist: API name = Lead record type developer name, label = Lead.Department__c text. */
    private static Map<String, String> departmentLabels() {
        Map<String, String> labels = new Map<String, String>();
        for (Schema.PicklistEntry entry : Zoom_Webinar__c.Department__c.getDescribe().getPicklistValues()) {
            labels.put(entry.getValue(), entry.getLabel());
        }
        return labels;
    }

    private static Lead newLead(Zoom_Registration__c registration, Id recordTypeId, String departmentLabel) {
        Lead lead = new Lead(
            RecordTypeId = recordTypeId,
            Admission_Year__c = registration.Webinar__r.Admission_Year__c,
            Department__c = departmentLabel,
            LeadSource = LEAD_SOURCE_ZOOM,
            Multi_Select_Lead_Source__c = LEAD_SOURCE_ZOOM,
            Email = String.isBlank(registration.Email__c) ? null : registration.Email__c.trim().left(MAX_EMAIL_LENGTH),
            MobilePhone = String.isBlank(registration.Phone__c) ? null : registration.Phone__c.trim().left(MAX_PHONE_LENGTH),
            Phone = standardPhone(registration.Phone__c)
        );
        String firstName = registration.First_Name__c;
        String lastName = registration.Last_Name__c;
        if (String.isBlank(lastName) && String.isNotBlank(firstName)) {
            List<String> parts = splitName(firstName);
            firstName = parts[0];
            lastName = parts[1];
        }
        lead.FirstName = String.isBlank(firstName) ? null : firstName.trim().left(MAX_FIRST_NAME_LENGTH);
        lead.LastName = String.isBlank(lastName) ? UNKNOWN_LAST_NAME : lastName.trim().left(MAX_LAST_NAME_LENGTH);
        if (Test.isRunningTest() && simulateLeadSaveFailure) {
            lead.Email = INVALID_EMAIL_FOR_TEST;
        }
        return lead;
    }

    /** Test hook: makes every new Lead fail to save (invalid email), to exercise the error path. */
    @TestVisible
    private static Boolean simulateLeadSaveFailure = false;
    private static final String INVALID_EMAIL_FOR_TEST = 'not-an-email';

    /**
     * @description Splits a full name: the last word is the last name, the rest the first name.
     * @return [firstName or null, lastName or null]
     */
    public static List<String> splitName(String fullName) {
        if (String.isBlank(fullName)) {
            return new List<String>{ null, null };
        }
        String trimmed = fullName.normalizeSpace();
        Integer lastSpace = trimmed.lastIndexOf(' ');
        if (lastSpace < 0) {
            return new List<String>{ null, trimmed };
        }
        return new List<String>{ trimmed.substring(0, lastSpace), trimmed.substring(lastSpace + 1) };
    }

    /** Fills only blank fields on the matched Lead; records the change in leadUpdates (one update per Lead). */
    private static void fillBlanks(Lead match, Zoom_Registration__c registration, String departmentLabel, Map<Id, Lead> leadUpdates) {
        Lead changes = leadUpdates.containsKey(match.Id) ? leadUpdates.get(match.Id) : new Lead(Id = match.Id);
        Boolean changed = false;
        if (String.isBlank(match.FirstName) && String.isNotBlank(registration.First_Name__c) && String.isNotBlank(registration.Last_Name__c)) {
            changes.FirstName = registration.First_Name__c.trim().left(MAX_FIRST_NAME_LENGTH);
            match.FirstName = changes.FirstName;
            changed = true;
        }
        if (String.isBlank(match.Email) && String.isNotBlank(registration.Email__c)) {
            changes.Email = registration.Email__c.trim().left(MAX_EMAIL_LENGTH);
            match.Email = changes.Email;
            changed = true;
        }
        if (String.isBlank(match.MobilePhone) && String.isNotBlank(registration.Phone__c)) {
            changes.MobilePhone = registration.Phone__c.trim().left(MAX_PHONE_LENGTH);
            match.MobilePhone = changes.MobilePhone;
            changed = true;
        }
        String phone = standardPhone(registration.Phone__c);
        if (String.isBlank(match.Phone) && phone != null) {
            changes.Phone = phone;
            match.Phone = changes.Phone;
            changed = true;
        }
        if (String.isBlank(match.Department__c) && String.isNotBlank(departmentLabel)) {
            changes.Department__c = departmentLabel;
            match.Department__c = changes.Department__c;
            changed = true;
        }
        if (changed) {
            leadUpdates.put(match.Id, changes);
        }
    }

    /**
     * @description Inserts the new Leads; returns the error message per failed key. Assignment Rules are deliberately
     *              not run: the owner is set by the Lead trigger (LeadCombinedTrigger department round-robin), the same
     *              as website and form Leads; an Assignment Rule would run after it and override that owner.
     */
    private static Map<String, String> insertLeads(Map<String, Lead> newLeadByKey) {
        Map<String, String> errorByKey = new Map<String, String>();
        if (newLeadByKey.isEmpty()) {
            return errorByKey;
        }
        Database.DMLOptions options = new Database.DMLOptions();
        options.duplicateRuleHeader.allowSave = true;
        options.optAllOrNone = false;
        List<String> keys = new List<String>(newLeadByKey.keySet());
        List<Lead> leads = new List<Lead>();
        for (String key : keys) {
            leads.add(newLeadByKey.get(key));
        }
        List<Database.SaveResult> results = Database.insert(leads, options);
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                errorByKey.put(keys[i], errorsOf(results[i].getErrors()));
            }
        }
        return errorByKey;
    }

    /** Saves blank-field fills on existing Leads. A failure keeps the link (the Lead exists) and is reported. */
    private static List<String> updateLeads(List<Lead> leads) {
        List<String> failures = new List<String>();
        if (leads.isEmpty()) {
            return failures;
        }
        Database.DMLOptions options = new Database.DMLOptions();
        options.duplicateRuleHeader.allowSave = true;
        options.optAllOrNone = false;
        List<Database.SaveResult> results = Database.update(leads, options);
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                failures.add('Lead ' + leads[i].Id + ' not updated - ' + errorsOf(results[i].getErrors()));
            }
        }
        return failures;
    }

    /**
     * @description Inserts the missing Tasks for linked registrations: "Registered" for registered people, and
     *              once the session has ended, "Attended" or (registered but never joined) "Did Not Attend".
     *              Stores each Task ID on the registration so a Task is never created twice.
     * @return one message per registration whose Task could not be saved (that registration is set to Error)
     */
    private static List<String> createTasks(List<Zoom_Registration__c> registrations) {
        List<String> failures = new List<String>();
        if (ZoomConfig.get().Create_Activities__c != true) {
            return failures;
        }
        Set<Id> leadIds = new Set<Id>();
        for (Zoom_Registration__c registration : registrations) {
            if (registration.Lead__c != null) {
                leadIds.add(registration.Lead__c);
            }
        }
        Map<Id, Lead> owners = ZoomSelector.selectLeadOwners(leadIds);

        List<Task> tasks = new List<Task>();
        List<Zoom_Registration__c> taskRegistrations = new List<Zoom_Registration__c>();
        List<Boolean> isAttendanceTask = new List<Boolean>();
        for (Zoom_Registration__c registration : registrations) {
            if (registration.Lead__c == null || !LINKED_STATUSES.contains(registration.Lead_Status__c)) {
                continue;
            }
            Zoom_Webinar__c session = registration.Webinar__r;
            String label = 'Zoom ' + (session.Type__c == null ? TYPE_WEBINAR : session.Type__c);
            String topic = session.Name == null ? session.Webinar_Id__c : session.Name;
            Lead owner = owners.get(registration.Lead__c);
            Id ownerId = owner == null ? null : owner.OwnerId;
            if (registration.Is_Registered__c == true && registration.Registration_Task_Id__c == null) {
                tasks.add(newTask(registration.Lead__c, ownerId, label + ' Registered: ' + topic,
                    'Registered for ' + label + ' "' + topic + '"' + scheduledOn(session) + '.'));
                taskRegistrations.add(registration);
                isAttendanceTask.add(false);
            }
            if (session.Status__c == STATUS_ENDED && registration.Attendance_Task_Id__c == null) {
                if (registration.Attended__c == true) {
                    tasks.add(newTask(registration.Lead__c, ownerId, label + ' Attended: ' + topic,
                        'Joined ' + label + ' "' + topic + '"'
                        + (registration.First_Joined_At__c == null ? '' : ' at ' + registration.First_Joined_At__c.format(DISPLAY_DATE_FORMAT))
                        + (registration.Time_In_Session_Minutes__c == null ? '' : ' and stayed ' + registration.Time_In_Session_Minutes__c + ' minutes')
                        + '.'));
                    taskRegistrations.add(registration);
                    isAttendanceTask.add(true);
                } else if (registration.Is_Registered__c == true) {
                    tasks.add(newTask(registration.Lead__c, ownerId, label + ' Did Not Attend: ' + topic,
                        'Registered for ' + label + ' "' + topic + '"' + scheduledOn(session) + ' but did not join.'));
                    taskRegistrations.add(registration);
                    isAttendanceTask.add(true);
                }
            }
        }
        if (tasks.isEmpty()) {
            return failures;
        }
        List<Database.SaveResult> results = Database.insert(tasks, false);
        for (Integer i = 0; i < results.size(); i++) {
            Zoom_Registration__c registration = taskRegistrations[i];
            if (!results[i].isSuccess()) {
                registration.Lead_Status__c = LEAD_STATUS_ERROR;
                failures.add(registration.Name + ': Task not created - ' + errorsOf(results[i].getErrors()));
            } else if (isAttendanceTask[i]) {
                registration.Attendance_Task_Id__c = tasks[i].Id;
            } else {
                registration.Registration_Task_Id__c = tasks[i].Id;
            }
        }
        return failures;
    }

    private static String scheduledOn(Zoom_Webinar__c session) {
        return session.Start_Time__c == null ? '' : ' scheduled on ' + session.Start_Time__c.format(DISPLAY_DATE_FORMAT);
    }

    /** The Task goes to the Lead owner when that owner is a user (a queue cannot own a Task). */
    private static Task newTask(Id leadId, Id leadOwnerId, String subject, String description) {
        Task activity = new Task(WhoId = leadId, Subject = subject.left(MAX_SUBJECT_LENGTH), Description = description,
            Status = TASK_STATUS_COMPLETED, Priority = TASK_PRIORITY_NORMAL, ActivityDate = Date.today());
        if (leadOwnerId != null && String.valueOf(leadOwnerId).startsWith(USER_ID_PREFIX)) {
            activity.OwnerId = leadOwnerId;
        }
        return activity;
    }

    private static String errorsOf(List<Database.Error> errors) {
        List<String> messages = new List<String>();
        for (Database.Error error : errors) {
            messages.add(error.getStatusCode() + ': ' + error.getMessage());
        }
        return String.join(messages, '; ');
    }

    /** One API_Log__c per call; references are registration numbers (ZR-…), never personal data. */
    private static void logFailures(List<String> failures) {
        if (failures.isEmpty()) {
            return;
        }
        ZoomLogger.logFailure(LOG_NAME, CLASS_NAME, failures.size() + ' Zoom registration(s) failed',
            String.join(failures, '\n'), null);
    }

    /** Candidate Leads indexed by scope (record type | admission year) + email or + last-10 phone digits, oldest first. */
    private class LeadIndex {
        private Map<String, List<Lead>> byEmail = new Map<String, List<Lead>>();
        private Map<String, List<Lead>> byPhone = new Map<String, List<Lead>>();

        LeadIndex(List<Lead> candidates) {
            for (Lead lead : candidates) {
                String scope = lead.RecordTypeId + KEY_SEPARATOR + lead.Admission_Year__c;
                String email = normalizeEmail(lead.Email);
                if (email != null) {
                    add(byEmail, scope + KEY_SEPARATOR + email, lead);
                }
                Set<String> phones = new Set<String>{ lastTen(lead.MobilePhone), lastTen(lead.Phone) };
                phones.remove(null);
                for (String phone : phones) {
                    add(byPhone, scope + KEY_SEPARATOR + phone, lead);
                }
            }
        }

        private void add(Map<String, List<Lead>> index, String key, Lead lead) {
            if (!index.containsKey(key)) {
                index.put(key, new List<Lead>());
            }
            index.get(key).add(lead);
        }

        Lead find(String scope, String email, String phone) {
            if (email != null && phone != null) {
                for (Lead lead : leadsAt(byEmail, scope + KEY_SEPARATOR + email)) {
                    if (lastTen(lead.MobilePhone) == phone || lastTen(lead.Phone) == phone) {
                        return lead;
                    }
                }
                return null;
            }
            List<Lead> matches = email != null ? leadsAt(byEmail, scope + KEY_SEPARATOR + email) : leadsAt(byPhone, scope + KEY_SEPARATOR + phone);
            return matches.isEmpty() ? null : matches[0];
        }

        private List<Lead> leadsAt(Map<String, List<Lead>> index, String key) {
            return index.containsKey(key) ? index.get(key) : new List<Lead>();
        }
    }
}