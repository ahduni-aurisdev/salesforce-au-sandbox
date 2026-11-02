/**
 * @description Applies Zoom webinar and meeting events (webhook payloads or API data) to Zoom_Webinar__c
 *              ("Zoom Session") and Zoom_Registration__c, matches each person to a Lead or Contact by email
 *              and logs a completed Task on that record ("Zoom Webinar Registered" / "Zoom Meeting Attended" ...).
 *              Webinar events are ignored unless FeatureFlag Zoom_Webinars is enabled, and meeting events unless
 *              FeatureFlag Zoom_Meetings is enabled.
 * @author AU Development Team
 * @date 2026-10-21
 * @version 1.3
 * @lastModified 2026-11-02
 */
// System mode is intentional: events arrive through the Zoom webhook, which runs as the Site guest user
// with no access to Zoom, Lead, Contact or Task records, and through the scheduled sync. Callers are
// authenticated by the Zoom HMAC signature (ZoomWebhook) and no record data is returned to them.
public without sharing class ZoomEventService {
    public static final String TYPE_WEBINAR = 'Webinar';
    public static final String TYPE_MEETING = 'Meeting';
    @TestVisible
    private static final String FLAG_MEETINGS = 'Zoom_Meetings';
    @TestVisible
    private static final String FLAG_WEBINARS = 'Zoom_Webinars';

    public static final String STATUS_SCHEDULED = 'Scheduled';
    public static final String STATUS_STARTED = 'Started';
    public static final String STATUS_ENDED = 'Ended';
    public static final String STATUS_DELETED = 'Deleted';

    public static final String REGISTRATION_APPROVED = 'Approved';
    public static final String REGISTRATION_PENDING = 'Pending';
    private static final String REGISTRATION_CANCELLED = 'Cancelled';
    private static final String REGISTRATION_DENIED = 'Denied';
    private static final String REGISTRATION_NOT_REGISTERED = 'Not Registered';
    private static final String ZOOM_STATUS_PENDING = 'pending';

    private static final String PREFIX_WEBINAR = 'webinar.';
    private static final String PREFIX_MEETING = 'meeting.';
    private static final String ACTION_STARTED = 'started';
    private static final String ACTION_ENDED = 'ended';
    private static final String ACTION_DELETED = 'deleted';
    private static final String ACTION_REGISTRATION_PREFIX = 'registration_';
    private static final String ACTION_REGISTRATION_CANCELLED = 'registration_cancelled';
    private static final String ACTION_REGISTRATION_DENIED = 'registration_denied';
    private static final String ACTION_REGISTRATION_APPROVED = 'registration_approved';
    private static final String ACTION_PARTICIPANT_JOINED = 'participant_joined';
    private static final String ACTION_PARTICIPANT_LEFT = 'participant_left';

    private static final String TASK_STATUS_COMPLETED = 'Completed';
    private static final String TASK_PRIORITY_NORMAL = 'Normal';
    private static final String DISPLAY_DATE_FORMAT = 'dd MMM yyyy hh:mm a';
    private static final String USER_ID_PREFIX = '005';
    private static final String UNKNOWN_PERSON = 'unknown';
    private static final Integer MAX_NAME_LENGTH = 80;
    private static final Integer MAX_TEXT_LENGTH = 255;
    private static final Integer MAX_ANSWERS_LENGTH = 32768;
    private static final Long MILLIS_PER_MINUTE = 60000;
    private static final String DUPLICATE_VALUE = 'DUPLICATE_VALUE';
    private static final List<String> STANDARD_ANSWER_KEYS = new List<String>{
        'address', 'city', 'state', 'zip', 'country', 'org', 'job_title', 'industry', 'comments'
    };

    /** Raised when a Zoom event cannot be applied (for example, it has no session ID). */
    public class ZoomEventException extends Exception {
    }

    public class Person {
        public String email, firstName, lastName, phone, registrantId, joinUrl, status, answers;
        public Datetime registeredAt, joinedAt, leftAt;
        public Integer minutesInSession;
        public String participantName;
    }

    /**
     * @description Entry point for a webhook body. Events other than webinar.* and meeting.* are ignored.
     * @throws JSONException if the body is not JSON; ZoomEventException if the event has no session ID
     */
    public static void process(String body) {
        Map<String, Object> root = asMap(JSON.deserializeUntyped(body));
        if (root == null) {
            return;
        }
        String event = str(root.get('event'));
        Map<String, Object> payload = asMap(root.get('payload'));
        Map<String, Object> obj = payload == null ? null : asMap(payload.get('object'));
        String type = typeOfEvent(event);
        if (type == null || obj == null) {
            return;
        }
        if (!isTypeEnabled(type)) {
            return;
        }
        String action = event.substringAfter('.');

        Zoom_Webinar__c session = sessionFromObject(obj, type);
        if (session.Webinar_Id__c == null) {
            throw new ZoomEventException('Zoom event ' + event + ' has no object id');
        }
        if (action == ACTION_STARTED) {
            session.Status__c = STATUS_STARTED;
        } else if (action == ACTION_ENDED) {
            session.Status__c = STATUS_ENDED;
        } else if (action == ACTION_DELETED) {
            session.Status__c = STATUS_DELETED;
        }
        saveSession(session);

        if (action.startsWith(ACTION_REGISTRATION_PREFIX)) {
            Map<String, Object> registrant = asMap(obj.get('registrant'));
            if (registrant != null) {
                applyPeople(session, new List<Person>{ personFromRegistrant(registrant, action, root.get('event_ts')) }, true);
            }
        } else if (action == ACTION_PARTICIPANT_JOINED || action == ACTION_PARTICIPANT_LEFT) {
            Map<String, Object> participant = asMap(obj.get('participant'));
            if (participant == null) {
                return;
            }
            Person person = personFromParticipant(participant);
            if (action == ACTION_PARTICIPANT_JOINED) {
                applyPeople(session, new List<Person>{ person }, false);
            } else {
                applyLeft(session, person);
            }
        }
    }

    /** True when the feature flag for this session type (Webinar or Meeting) is enabled. */
    public static Boolean isTypeEnabled(String type) {
        if (type == TYPE_MEETING) {
            return FeatureFlagService.isEnabled(FLAG_MEETINGS);
        }
        if (type == TYPE_WEBINAR) {
            return FeatureFlagService.isEnabled(FLAG_WEBINARS);
        }
        return false;
    }

    /**
     * @description Builds the session record from a webhook "object" or an API webinar / meeting map.
     *              Only fields present in the source are set, so partial "updated" payloads do not blank data.
     */
    public static Zoom_Webinar__c sessionFromObject(Map<String, Object> source, String type) {
        Zoom_Webinar__c session = new Zoom_Webinar__c(Webinar_Id__c = str(source.get('id')), Type__c = type);
        String topic = str(source.get('topic'));
        if (topic != null) {
            session.Name = topic.left(MAX_NAME_LENGTH);
        }
        Datetime startTime = parseDt(str(source.get('start_time')));
        if (startTime != null) {
            session.Start_Time__c = startTime;
        }
        String duration = str(source.get('duration'));
        if (duration != null && duration.isNumeric()) {
            session.Duration_Minutes__c = Decimal.valueOf(duration);
            if (startTime != null) {
                session.End_Time__c = startTime.addMinutes(Integer.valueOf(duration));
            }
        }
        if (str(source.get('timezone')) != null) {
            session.Timezone__c = str(source.get('timezone'));
        }
        if (str(source.get('join_url')) != null) {
            session.Join_URL__c = str(source.get('join_url'));
        }
        if (str(source.get('registration_url')) != null) {
            session.Registration_URL__c = str(source.get('registration_url'));
        }
        return session;
    }

    /**
     * @description Upserts the session by Zoom ID. A new session without a topic gets a placeholder name.
     *              Zoom often sends two events for a new meeting at the same instant (e.g. participant joined and
     *              left); both transactions then try to insert the same Zoom ID and one fails with DUPLICATE_VALUE.
     *              That one is retried once: by then the record exists, so the retry updates it.
     */
    public static void saveSession(Zoom_Webinar__c session) {
        saveSession(session, true);
    }

    private static void saveSession(Zoom_Webinar__c session, Boolean retryOnDuplicate) {
        Boolean usesPlaceholderName = false;
        if (session.Name == null
            && !ZoomSelector.selectSessionsByZoomIds(new Set<String>{ session.Webinar_Id__c }).containsKey(session.Webinar_Id__c)) {
            session.Name = ('Zoom ' + session.Type__c + ' ' + session.Webinar_Id__c).left(MAX_NAME_LENGTH);
            usesPlaceholderName = true;
        }
        try {
            simulateDuplicateForTest();
            upsert session Webinar_Id__c;
        } catch (DmlException e) {
            if (!retryOnDuplicate || !isDuplicateValue(e)) {
                throw e;
            }
            // Retry without the placeholder name so the concurrent insert's real topic is not overwritten.
            Zoom_Webinar__c retry = new Zoom_Webinar__c();
            for (String field : session.getPopulatedFieldsAsMap().keySet()) {
                if (field != 'Id' && !(usesPlaceholderName && field == 'Name')) {
                    retry.put(field, session.get(field));
                }
            }
            saveSession(retry, false);
            session.Id = retry.Id;
        }
    }

    /**
     * @description Registers or marks attendance for a batch of people on one saved session.
     *              Bulk-safe: 3 SOQL (registrations, Leads, Contacts) and 2 DML (Tasks, registrations) per call.
     *              A DUPLICATE_VALUE on the registration key (a concurrent event inserted the same person) rolls back
     *              this attempt, Tasks included, and retries once against the now-existing rows, so Tasks are never
     *              created twice.
     */
    public static void applyPeople(Zoom_Webinar__c session, List<Person> people, Boolean fromRegistration) {
        Savepoint beforeApply = Database.setSavepoint();
        try {
            applyPeopleOnce(session, people, fromRegistration);
        } catch (DmlException e) {
            if (!isDuplicateValue(e)) {
                throw e;
            }
            Database.rollback(beforeApply);
            applyPeopleOnce(session, people, fromRegistration);
        }
    }

    /**
     * @description True when the DML failed because another transaction inserted the same unique key first.
     *              Checks the status code in the message (e.g. "first error: DUPLICATE_VALUE, duplicate value found"),
     *              which works for platform DML errors and for the simulated test error alike.
     */
    @TestVisible
    private static Boolean isDuplicateValue(DmlException e) {
        return e.getMessage() != null && e.getMessage().contains(DUPLICATE_VALUE);
    }

    /** Test hook: number of upcoming upserts that must fail as if a concurrent transaction won the insert. */
    @TestVisible
    private static Integer simulatedDuplicateFailures = 0;

    private static void simulateDuplicateForTest() {
        if (Test.isRunningTest() && simulatedDuplicateFailures > 0) {
            simulatedDuplicateFailures--;
            throw new DmlException('Upsert failed. ' + DUPLICATE_VALUE + ', duplicate value found (simulated concurrent insert)');
        }
    }

    private static void applyPeopleOnce(Zoom_Webinar__c session, List<Person> people, Boolean fromRegistration) {
        Set<String> keys = new Set<String>();
        Set<String> emails = new Set<String>();
        for (Person person : people) {
            keys.add(keyOf(session.Webinar_Id__c, person));
            if (person.email != null) {
                emails.add(person.email.toLowerCase());
            }
        }
        Map<String, Zoom_Registration__c> byKey = ZoomSelector.selectRegistrationsByKeys(keys);
        Map<String, SObject> matches = ZoomSelector.selectPeopleByEmail(emails);
        Map<Id, Id> ownerByPersonId = new Map<Id, Id>();

        for (Person person : people) {
            String key = keyOf(session.Webinar_Id__c, person);
            Zoom_Registration__c registration = byKey.get(key);
            if (registration == null) {
                registration = new Zoom_Registration__c(Registration_Key__c = key, Webinar__c = session.Id, Is_Registered__c = false);
                byKey.put(key, registration);
            }
            copyContactDetails(person, registration);
            if (fromRegistration) {
                applyRegistration(person, registration);
            } else {
                applyAttendance(person, registration);
            }
            SObject match = person.email == null ? null : matches.get(person.email.toLowerCase());
            if (match != null) {
                registration.Is_Matched__c = true;
                if (match instanceof Lead) {
                    registration.Lead__c = match.Id;
                } else {
                    registration.Contact__c = match.Id;
                }
                ownerByPersonId.put(match.Id, (Id) match.get('OwnerId'));
            }
        }
        List<Zoom_Registration__c> registrations = new List<Zoom_Registration__c>();
        for (String key : keys) {
            registrations.add(byKey.get(key));
        }
        createActivities(session, registrations, ownerByPersonId);
        simulateDuplicateForTest();
        upsert registrations Registration_Key__c;
    }

    private static void copyContactDetails(Person person, Zoom_Registration__c registration) {
        if (person.email != null) {
            registration.Email__c = person.email;
        }
        if (person.firstName != null) {
            registration.First_Name__c = person.firstName;
        }
        if (person.lastName != null) {
            registration.Last_Name__c = person.lastName;
        }
        if (person.phone != null) {
            registration.Phone__c = person.phone;
        }
        if (person.joinUrl != null) {
            registration.Join_URL__c = person.joinUrl;
        }
        if (person.answers != null) {
            registration.Form_Answers__c = person.answers;
        }
        if (person.registrantId != null) {
            registration.Registrant_Id__c = person.registrantId;
        }
    }

    private static void applyRegistration(Person person, Zoom_Registration__c registration) {
        registration.Status__c = person.status;
        registration.Is_Registered__c = (person.status == REGISTRATION_APPROVED || person.status == REGISTRATION_PENDING);
        if (registration.Registered_At__c == null) {
            registration.Registered_At__c = person.registeredAt;
        }
    }

    private static void applyAttendance(Person person, Zoom_Registration__c registration) {
        // A participant with a Zoom registrant ID registered through Zoom even if the registration event was missed.
        if (person.registrantId != null && registration.Is_Registered__c != true && registration.Id == null) {
            registration.Is_Registered__c = true;
            if (registration.Status__c == null) {
                registration.Status__c = REGISTRATION_APPROVED;
            }
        }
        if (registration.Status__c == null) {
            registration.Status__c = REGISTRATION_NOT_REGISTERED;
        }
        registration.Attended__c = true;
        if (person.joinedAt != null) {
            if (registration.First_Joined_At__c == null || person.joinedAt < registration.First_Joined_At__c) {
                registration.First_Joined_At__c = person.joinedAt;
            }
            if (registration.Last_Joined_At__c == null || person.joinedAt > registration.Last_Joined_At__c) {
                registration.Last_Joined_At__c = person.joinedAt;
            }
        }
        if (person.minutesInSession != null) {
            registration.Time_In_Session_Minutes__c = person.minutesInSession;
        }
        if (person.leftAt != null) {
            registration.Last_Left_At__c = person.leftAt;
        }
    }

    private static void applyLeft(Zoom_Webinar__c session, Person person) {
        String key = keyOf(session.Webinar_Id__c, person);
        Zoom_Registration__c registration = ZoomSelector.selectRegistrationsByKeys(new Set<String>{ key }).get(key);
        if (registration == null || person.leftAt == null
            || (registration.Last_Left_At__c != null && person.leftAt <= registration.Last_Left_At__c)) {
            return;
        }
        if (registration.Last_Joined_At__c != null && person.leftAt > registration.Last_Joined_At__c) {
            Long minutes = (person.leftAt.getTime() - registration.Last_Joined_At__c.getTime()) / MILLIS_PER_MINUTE;
            registration.Time_In_Session_Minutes__c =
                (registration.Time_In_Session_Minutes__c == null ? 0 : registration.Time_In_Session_Minutes__c) + minutes;
        }
        registration.Last_Left_At__c = person.leftAt;
        update registration;
    }

    /** Inserts one Task per new registration / attendance and stores its ID so repeated events never duplicate it. */
    private static void createActivities(Zoom_Webinar__c session, List<Zoom_Registration__c> registrations, Map<Id, Id> ownerByPersonId) {
        if (ZoomConfig.get().Create_Activities__c != true) {
            return;
        }
        String label = 'Zoom ' + (session.Type__c == null ? TYPE_WEBINAR : session.Type__c);
        String topic = session.Name == null ? session.Webinar_Id__c : session.Name;
        List<Task> tasks = new List<Task>();
        List<Zoom_Registration__c> taskRegistrations = new List<Zoom_Registration__c>();
        List<Boolean> isAttendanceTask = new List<Boolean>();
        for (Zoom_Registration__c registration : registrations) {
            Id whoId = registration.Lead__c != null ? registration.Lead__c : registration.Contact__c;
            if (whoId == null) {
                continue;
            }
            if (registration.Is_Registered__c == true && registration.Registration_Task_Id__c == null) {
                tasks.add(newTask(whoId, ownerByPersonId.get(whoId), label + ' Registered: ' + topic,
                    'Registered for ' + label + ' "' + topic + '"'
                    + (session.Start_Time__c == null ? '' : ' scheduled on ' + session.Start_Time__c.format(DISPLAY_DATE_FORMAT)) + '.'));
                taskRegistrations.add(registration);
                isAttendanceTask.add(false);
            }
            if (registration.Attended__c == true && registration.Attendance_Task_Id__c == null) {
                tasks.add(newTask(whoId, ownerByPersonId.get(whoId), label + ' Attended: ' + topic,
                    'Joined ' + label + ' "' + topic + '"'
                    + (registration.First_Joined_At__c == null ? '' : ' at ' + registration.First_Joined_At__c.format(DISPLAY_DATE_FORMAT)) + '.'));
                taskRegistrations.add(registration);
                isAttendanceTask.add(true);
            }
        }
        if (tasks.isEmpty()) {
            return;
        }
        insert tasks;
        for (Integer i = 0; i < tasks.size(); i++) {
            if (isAttendanceTask[i]) {
                taskRegistrations[i].Attendance_Task_Id__c = tasks[i].Id;
            } else {
                taskRegistrations[i].Registration_Task_Id__c = tasks[i].Id;
            }
        }
    }

    /** The Task goes to the Lead / Contact owner when that owner is a user (a queue cannot own a Task). */
    private static Task newTask(Id whoId, Id recordOwnerId, String subject, String description) {
        Task activity = new Task(WhoId = whoId, Subject = subject.left(MAX_TEXT_LENGTH), Description = description,
            Status = TASK_STATUS_COMPLETED, Priority = TASK_PRIORITY_NORMAL, ActivityDate = Date.today());
        if (recordOwnerId != null && String.valueOf(recordOwnerId).startsWith(USER_ID_PREFIX)) {
            activity.OwnerId = recordOwnerId;
        }
        return activity;
    }

    private static Person personFromRegistrant(Map<String, Object> registrant, String action, Object eventTimestamp) {
        Person person = new Person();
        person.registrantId = str(registrant.get('id'));
        person.email = str(registrant.get('email'));
        person.firstName = str(registrant.get('first_name'));
        person.lastName = str(registrant.get('last_name'));
        person.phone = str(registrant.get('phone'));
        person.joinUrl = str(registrant.get('join_url'));
        person.answers = answersOf(registrant);
        String timestamp = str(eventTimestamp);
        person.registeredAt = (timestamp == null || !timestamp.isNumeric()) ? Datetime.now() : Datetime.newInstance(Long.valueOf(timestamp));
        if (action == ACTION_REGISTRATION_CANCELLED) {
            person.status = REGISTRATION_CANCELLED;
        } else if (action == ACTION_REGISTRATION_DENIED) {
            person.status = REGISTRATION_DENIED;
        } else if (action == ACTION_REGISTRATION_APPROVED) {
            person.status = REGISTRATION_APPROVED;
        } else {
            person.status = str(registrant.get('status')) == ZOOM_STATUS_PENDING ? REGISTRATION_PENDING : REGISTRATION_APPROVED;
        }
        return person;
    }

    private static Person personFromParticipant(Map<String, Object> participant) {
        Person person = new Person();
        person.registrantId = str(participant.get('registrant_id'));
        person.email = str(participant.get('email'));
        person.participantName = str(participant.get('user_name'));
        person.joinedAt = parseDt(str(participant.get('join_time')));
        person.leftAt = parseDt(str(participant.get('leave_time')));
        return person;
    }

    private static String typeOfEvent(String event) {
        if (event == null) {
            return null;
        }
        if (event.startsWith(PREFIX_WEBINAR)) {
            return TYPE_WEBINAR;
        }
        if (event.startsWith(PREFIX_MEETING)) {
            return TYPE_MEETING;
        }
        return null;
    }

    private static String keyOf(String sessionId, Person person) {
        String who = person.email != null
            ? person.email.toLowerCase()
            : (person.registrantId != null
                ? person.registrantId
                : (person.participantName == null ? UNKNOWN_PERSON : person.participantName.toLowerCase()));
        return (sessionId + '|' + who).left(MAX_TEXT_LENGTH);
    }

    private static String answersOf(Map<String, Object> registrant) {
        List<String> lines = new List<String>();
        for (String key : STANDARD_ANSWER_KEYS) {
            if (str(registrant.get(key)) != null) {
                lines.add(key + ': ' + str(registrant.get(key)));
            }
        }
        Object customQuestions = registrant.get('custom_questions');
        if (customQuestions instanceof List<Object>) {
            for (Object item : (List<Object>) customQuestions) {
                Map<String, Object> question = asMap(item);
                if (question != null) {
                    lines.add(str(question.get('title')) + ': ' + str(question.get('value')));
                }
            }
        }
        return lines.isEmpty() ? null : String.join(lines, '\n').left(MAX_ANSWERS_LENGTH);
    }

    public static Map<String, Object> asMap(Object value) {
        return value instanceof Map<String, Object> ? (Map<String, Object>) value : null;
    }

    public static String str(Object value) {
        return value == null || String.valueOf(value) == '' ? null : String.valueOf(value);
    }

    public static Datetime parseDt(String value) {
        if (value == null) {
            return null;
        }
        try {
            return (Datetime) JSON.deserialize('"' + value + '"', Datetime.class);
        } catch (JSONException e) {
            return null;
        } catch (TypeException e) {
            return null;
        }
    }
}