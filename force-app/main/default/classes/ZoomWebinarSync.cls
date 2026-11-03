/**
 * @description Pulls Zoom sessions (webinars when FeatureFlag Zoom_Webinars is enabled, meetings when
 *              FeatureFlag Zoom_Meetings is enabled), their
 *              registrants and, after a session ends, its participants. Safety net for missed webhooks and the way
 *              to import sessions that already exist in Zoom. One session per Queueable job; jobs are chained.
 *              Rate limits, Zoom 5xx and timeouts are retried up to MAX_RETRIES times with 1, 2, 4 minute delays;
 *              every other failure is logged to API_Log__c and the chain moves on to the next session.
 *              When the chain finishes it starts ZoomLeadQueueable, which creates / links Leads and logs Tasks.
 *                System.enqueueJob(new ZoomWebinarSync());                                // discover + sync all
 *                System.enqueueJob(new ZoomWebinarSync(new List<String>{'123456789'}));    // one webinar
 *                System.enqueueJob(new ZoomWebinarSync(new List<String>{'M:123456789'}));  // one meeting
 *              ZoomWebinarSyncScheduler.schedule() runs it every 2 hours.
 * @author AU Development Team
 * @date 2026-10-21
 * @version 1.4
 * @lastModified 2026-11-03
 */
// System mode is intentional: a scheduled system job that syncs every Zoom session regardless of who scheduled it.
public without sharing class ZoomWebinarSync implements Queueable, Database.AllowsCallouts {
    @TestVisible
    private static final Integer MAX_RETRIES = 3;
    @TestVisible
    private static final String MEETING_PREFIX = 'M:';
    private static final String FLAG_INTEGRATION = 'Zoom_Integration';
    private static final String DEFAULT_ZOOM_USER = 'me';
    private static final String LOG_NAME = 'ZoomWebinarSync';
    private static final String CLASS_NAME = 'ZoomWebinarSync';
    private static final String DISCOVER_REFERENCE = 'discover';
    private static final String UTF8 = 'UTF-8';
    private static final Integer RECENT_DAYS = 3;
    private static final Integer SECONDS_PER_MINUTE = 60;
    private static final Integer HTTP_BAD_REQUEST = 400;
    private static final String ZOOM_STATUS_APPROVED = 'approved';
    private static final String ZOOM_STATUS_PENDING = 'pending';
    private static final List<String> REGISTRANT_STATUSES = new List<String>{ ZOOM_STATUS_APPROVED, ZOOM_STATUS_PENDING };

    /** Jobs this run tried to enqueue; tests assert on it because Queueables cannot chain inside a test. */
    @TestVisible
    private static List<ZoomWebinarSync> enqueuedJobs = new List<ZoomWebinarSync>();
    @TestVisible
    private static List<Integer> enqueuedDelays = new List<Integer>();

    @TestVisible
    private List<String> sessionKeys;
    @TestVisible
    private Integer attempt = 0;

    public ZoomWebinarSync() {
    }

    /** @param sessionKeys Zoom webinar IDs, or meeting IDs prefixed with "M:" */
    public ZoomWebinarSync(List<String> sessionKeys) {
        this.sessionKeys = sessionKeys;
    }

    private ZoomWebinarSync(List<String> sessionKeys, Integer attempt) {
        this.sessionKeys = sessionKeys;
        this.attempt = attempt;
    }

    public void execute(QueueableContext context) {
        if (!FeatureFlagService.isEnabled(FLAG_INTEGRATION)) {
            return;
        }
        if (sessionKeys == null) {
            try {
                sessionKeys = discover();
            } catch (ZoomApiService.ZoomApiException e) {
                if (!handleFailure(null, DISCOVER_REFERENCE, e)) {
                    ZoomLeadQueueable.start();
                }
                return;
            }
            attempt = 0;
        }
        if (sessionKeys.isEmpty()) {
            ZoomLeadQueueable.start();
            return;
        }
        String current = sessionKeys.remove(0);
        try {
            syncOne(current);
        } catch (ZoomApiService.ZoomApiException e) {
            if (handleFailure(current, current, e)) {
                return;
            }
        } catch (DmlException e) {
            ZoomLogger.logFailure(LOG_NAME, CLASS_NAME, current, e);
        } catch (ZoomEventService.ZoomEventException e) {
            ZoomLogger.logFailure(LOG_NAME, CLASS_NAME, current, e);
        }
        if (!sessionKeys.isEmpty()) {
            enqueue(new ZoomWebinarSync(sessionKeys, 0), 0);
        } else {
            ZoomLeadQueueable.start();
        }
    }

    /**
     * @description Re-enqueues a retryable failure with exponential delay, or logs it once retries are exhausted.
     * @return true when a retry was enqueued (the caller must stop; the retry carries the rest of the queue)
     */
    private Boolean handleFailure(String currentKey, String reference, ZoomApiService.ZoomApiException e) {
        if (e.isRetryable == true && attempt < MAX_RETRIES) {
            List<String> retryKeys = null;
            if (currentKey != null) {
                retryKeys = new List<String>{ currentKey };
                retryKeys.addAll(sessionKeys);
            }
            enqueue(new ZoomWebinarSync(retryKeys, attempt + 1), Math.pow(2, attempt).intValue());
            return true;
        }
        ZoomLogger.logFailure(LOG_NAME, CLASS_NAME, reference, e);
        return false;
    }

    private static void enqueue(ZoomWebinarSync job, Integer delayMinutes) {
        enqueuedJobs.add(job);
        enqueuedDelays.add(delayMinutes);
        if (Test.isRunningTest()) {
            return;
        }
        if (delayMinutes > 0) {
            System.enqueueJob(job, delayMinutes);
        } else {
            System.enqueueJob(job);
        }
    }

    /** Upcoming Zoom webinars and meetings (each only if enabled) plus Salesforce sessions from the last RECENT_DAYS days. */
    private static List<String> discover() {
        Boolean webinarsEnabled = ZoomEventService.isTypeEnabled(ZoomEventService.TYPE_WEBINAR);
        Boolean meetingsEnabled = ZoomEventService.isTypeEnabled(ZoomEventService.TYPE_MEETING);
        String zoomUser = String.isBlank(ZoomConfig.get().Zoom_User_Id__c) ? DEFAULT_ZOOM_USER : ZoomConfig.get().Zoom_User_Id__c;
        String userPath = '/users/' + EncodingUtil.urlEncode(zoomUser, UTF8);
        Set<String> keys = new Set<String>();
        if (webinarsEnabled) {
            for (Object item : ZoomApiService.getAll(userPath + '/webinars', 'type=scheduled', 'webinars')) {
                keys.add(ZoomEventService.str(ZoomEventService.asMap(item).get('id')));
            }
        }
        if (meetingsEnabled) {
            for (Object item : ZoomApiService.getAll(userPath + '/meetings', 'type=upcoming', 'meetings')) {
                keys.add(MEETING_PREFIX + ZoomEventService.str(ZoomEventService.asMap(item).get('id')));
            }
        }
        for (Zoom_Webinar__c session : ZoomSelector.selectRecentSessions(Datetime.now().addDays(-RECENT_DAYS))) {
            if (session.Type__c == ZoomEventService.TYPE_MEETING) {
                if (meetingsEnabled) {
                    keys.add(MEETING_PREFIX + session.Webinar_Id__c);
                }
            } else if (webinarsEnabled) {
                keys.add(session.Webinar_Id__c);
            }
        }
        keys.remove(null);
        keys.remove(MEETING_PREFIX + null);
        return new List<String>(keys);
    }

    /**
     * @description Syncs one session. All callouts run before any DML (Salesforce does not allow a callout after
     *              uncommitted DML). Callouts: 1 session + 2+ registrant pages + participant pages if ended.
     */
    public static void syncOne(String sessionKey) {
        Boolean isMeeting = sessionKey.startsWith(MEETING_PREFIX);
        if (!ZoomEventService.isTypeEnabled(isMeeting ? ZoomEventService.TYPE_MEETING : ZoomEventService.TYPE_WEBINAR)) {
            return;
        }
        String rawZoomId = isMeeting ? sessionKey.removeStart(MEETING_PREFIX) : sessionKey;
        String zoomId = EncodingUtil.urlEncode(rawZoomId, UTF8);
        String resource = isMeeting ? '/meetings/' : '/webinars/';
        String pastResource = isMeeting ? '/past_meetings/' : '/past_webinars/';

        Zoom_Webinar__c existing = ZoomSelector.selectSessionsByZoomIds(new Set<String>{ rawZoomId }).get(rawZoomId);
        Map<String, Object> source = ZoomApiService.get(resource + zoomId);
        if (source.isEmpty() || !isAllowedHost(ZoomEventService.str(source.get('host_id')))) {
            return;
        }
        Zoom_Webinar__c session = ZoomEventService.sessionFromObject(source,
            isMeeting ? ZoomEventService.TYPE_MEETING : ZoomEventService.TYPE_WEBINAR);
        session.Last_Synced_At__c = Datetime.now();
        session.Status__c = resolveStatus(existing == null ? null : existing.Status__c, session.End_Time__c);

        List<ZoomEventService.Person> registrants = fetchRegistrants(resource + zoomId + '/registrants', isMeeting);
        Map<String, ZoomEventService.Person> participants = new Map<String, ZoomEventService.Person>();
        if (session.Status__c == ZoomEventService.STATUS_ENDED) {
            participants = fetchParticipants(pastResource + zoomId + '/participants');
        }

        ZoomEventService.saveSession(session);
        if (!registrants.isEmpty()) {
            ZoomEventService.applyPeople(session, registrants, true);
        }
        if (!participants.isEmpty()) {
            ZoomEventService.applyPeople(session, participants.values(), false);
        }
    }

    /** Skips sessions of hosts outside Zoom_Config Allowed_Host_Ids__c (none configured = every host allowed). */
    private static Boolean isAllowedHost(String hostId) {
        Set<String> allowedHostIds = ZoomConfig.allowedHostIds();
        return allowedHostIds.isEmpty() || hostId == null || allowedHostIds.contains(hostId);
    }

    /**
     * @description Status never moves backwards: a session the webhook already marked Started, Ended or Deleted
     *              keeps that status even when Zoom gives no end time (instant and recurring meetings have none).
     *              A planned end time in the past moves Scheduled / Started forward to Ended.
     */
    @TestVisible
    private static String resolveStatus(String currentStatus, Datetime plannedEnd) {
        if (currentStatus == ZoomEventService.STATUS_DELETED) {
            return currentStatus;
        }
        if (plannedEnd != null && plannedEnd < Datetime.now()) {
            return ZoomEventService.STATUS_ENDED;
        }
        return currentStatus == null ? ZoomEventService.STATUS_SCHEDULED : currentStatus;
    }

    private static List<ZoomEventService.Person> fetchRegistrants(String path, Boolean isMeeting) {
        List<ZoomEventService.Person> registrants = new List<ZoomEventService.Person>();
        for (String status : REGISTRANT_STATUSES) {
            List<Object> items;
            try {
                items = ZoomApiService.getAll(path, 'status=' + status, 'registrants');
            } catch (ZoomApiService.ZoomApiException e) {
                // Zoom answers 400 for a meeting that does not use registration; that meeting simply has no registrants.
                if (isMeeting && e.statusCode == HTTP_BAD_REQUEST) {
                    return registrants;
                }
                throw e;
            }
            for (Object item : items) {
                Map<String, Object> source = ZoomEventService.asMap(item);
                ZoomEventService.Person person = new ZoomEventService.Person();
                person.registrantId = ZoomEventService.str(source.get('id'));
                person.email = ZoomEventService.str(source.get('email'));
                person.firstName = ZoomEventService.str(source.get('first_name'));
                person.lastName = ZoomEventService.str(source.get('last_name'));
                person.phone = ZoomEventService.str(source.get('phone'));
                person.joinUrl = ZoomEventService.str(source.get('join_url'));
                person.status = status == ZOOM_STATUS_PENDING ? ZoomEventService.REGISTRATION_PENDING : ZoomEventService.REGISTRATION_APPROVED;
                person.registeredAt = ZoomEventService.parseDt(ZoomEventService.str(source.get('create_time')));
                registrants.add(person);
            }
        }
        return registrants;
    }

    /** Aggregates participant rows per person: earliest join, latest leave, total minutes in session. */
    private static Map<String, ZoomEventService.Person> fetchParticipants(String path) {
        Map<String, ZoomEventService.Person> byPerson = new Map<String, ZoomEventService.Person>();
        for (Object item : ZoomApiService.getAll(path, null, 'participants')) {
            Map<String, Object> source = ZoomEventService.asMap(item);
            String email = ZoomEventService.str(source.get('user_email'));
            String key = email != null
                ? email.toLowerCase()
                : ZoomEventService.str(source.get('registrant_id')) + ZoomEventService.str(source.get('name'));
            ZoomEventService.Person person = byPerson.get(key);
            if (person == null) {
                person = new ZoomEventService.Person();
                person.email = email;
                person.registrantId = ZoomEventService.str(source.get('registrant_id'));
                person.participantName = ZoomEventService.str(source.get('name'));
                person.minutesInSession = 0;
                byPerson.put(key, person);
            }
            Datetime joinedAt = ZoomEventService.parseDt(ZoomEventService.str(source.get('join_time')));
            Datetime leftAt = ZoomEventService.parseDt(ZoomEventService.str(source.get('leave_time')));
            if (person.joinedAt == null || (joinedAt != null && joinedAt < person.joinedAt)) {
                person.joinedAt = joinedAt;
            }
            if (person.leftAt == null || (leftAt != null && leftAt > person.leftAt)) {
                person.leftAt = leftAt;
            }
            String durationSeconds = ZoomEventService.str(source.get('duration'));
            if (durationSeconds != null && durationSeconds.isNumeric()) {
                person.minutesInSession += Integer.valueOf(Math.round(Decimal.valueOf(durationSeconds) / SECONDS_PER_MINUTE));
            }
        }
        return byPerson;
    }
}