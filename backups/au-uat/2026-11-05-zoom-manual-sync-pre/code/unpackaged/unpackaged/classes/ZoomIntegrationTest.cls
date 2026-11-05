/**
 * @description Tests for the Zoom integration: ZoomWebhook, ZoomEventService, ZoomApiService, ZoomWebinarSync,
 *              ZoomWebinarSyncScheduler and ZoomConfig. Covers webinars and meetings, a 200-person bulk sync,
 *              Zoom failures (401, 429, 5xx, timeout), retries, feature flags and webhook rejection paths.
 *              Since v1.2 the webhook and the session sync never create Leads or Tasks: registrations are saved as
 *              "Pending setup" and the sync chain ends by starting ZoomLeadQueueable (see ZoomLeadServiceTest).
 * @author AU Development Team
 * @date 2026-10-21
 *              Since v1.3: default Department and Admission Year from Zoom_Config on new sessions.
 * @version 1.3
 * @lastModified 2026-11-04
 */
@IsTest
private class ZoomIntegrationTest {
    private static final Integer BULK_SIZE = 200;
    private static final String EMAIL_DOMAIN = '@zoomtest.com';
    private static final String SESSION_ID = '99887766';
    private static final String TOPIC = 'MBA Open House';
    private static final String SECRET = 'secret';

    /** HttpCalloutMock that answers by URL fragment, first match wins, and records every endpoint called. */
    private class ZoomMock implements HttpCalloutMock {
        private List<String> fragments = new List<String>();
        private List<Integer> statuses = new List<Integer>();
        private List<String> bodies = new List<String>();
        private Boolean throwTimeout = false;
        public List<String> endpoints = new List<String>();

        public ZoomMock respondTo(String fragment, Integer status, String body) {
            fragments.add(fragment);
            statuses.add(status);
            bodies.add(body);
            return this;
        }

        public ZoomMock failWithTimeout() {
            throwTimeout = true;
            return this;
        }

        public HttpResponse respond(HttpRequest request) {
            endpoints.add(request.getEndpoint());
            if (throwTimeout && !request.getEndpoint().contains('/oauth/token')) {
                throw new CalloutException('Read timed out');
            }
            HttpResponse response = new HttpResponse();
            for (Integer i = 0; i < fragments.size(); i++) {
                if (request.getEndpoint().contains(fragments[i])) {
                    response.setStatusCode(statuses[i]);
                    response.setBody(bodies[i]);
                    return response;
                }
            }
            response.setStatusCode(404);
            response.setBody('{}');
            return response;
        }
    }

    @TestSetup
    static void createLeads() {
        List<Lead> leads = new List<Lead>();
        for (Integer i = 0; i < BULK_SIZE; i++) {
            leads.add(new Lead(LastName = 'Zoom Bulk ' + i, Company = 'Zoom Test', Email = emailOf(i)));
        }
        insert leads;
    }

    private static String emailOf(Integer i) {
        return 'bulk' + i + EMAIL_DOMAIN;
    }

    private static void configure(Boolean meetingsEnabled) {
        ZoomConfig.testOverride = new Zoom_Config__mdt(Webhook_Secret_Token__c = SECRET, Account_Id__c = 'acct',
            Client_Id__c = 'client', Client_Secret__c = 'clientsecret', Zoom_User_Id__c = 'me', Create_Activities__c = true);
        FeatureFlagService.testOverrides.put(ZoomWebhook.FLAG_INTEGRATION, true);
        FeatureFlagService.testOverrides.put(ZoomEventService.FLAG_MEETINGS, meetingsEnabled);
        FeatureFlagService.testOverrides.put(ZoomEventService.FLAG_WEBINARS, true);
        FeatureFlagService.testOverrides.put(ZoomApiService.FLAG_NAMED_CREDENTIAL, false);
    }

    private static String event(String eventName, String objectFields) {
        return '{"event":"' + eventName + '","event_ts":1790000000000,"payload":{"object":{"id":"' + SESSION_ID
            + '","topic":"' + TOPIC + '","start_time":"2026-10-02T10:00:00Z","duration":60,"timezone":"Asia/Kolkata"'
            + (objectFields == null ? '' : ',' + objectFields) + '}}}';
    }

    private static RestResponse post(String body, Boolean signed) {
        RestRequest request = new RestRequest();
        RestResponse response = new RestResponse();
        request.requestBody = Blob.valueOf(body);
        if (signed) {
            request.addHeader('x-zm-request-timestamp', '123');
            request.addHeader('x-zm-signature', 'v0=' + ZoomWebhook.hmac('v0:123:' + body, SECRET));
        }
        RestContext.request = request;
        RestContext.response = response;
        ZoomWebhook.receive();
        return response;
    }

    private static ZoomMock standardWebinarMock(Integer registrantCount, Integer participantCount) {
        List<String> registrants = new List<String>();
        List<String> participants = new List<String>();
        for (Integer i = 0; i < registrantCount; i++) {
            registrants.add('{"id":"r' + i + '","email":"' + emailOf(i) + '","first_name":"F","last_name":"L' + i
                + '","create_time":"2026-10-01T10:00:00Z"}');
        }
        for (Integer i = 0; i < participantCount; i++) {
            participants.add('{"user_email":"' + emailOf(i) + '","name":"P' + i + '","registrant_id":"r' + i
                + '","join_time":"2026-10-02T10:00:00Z","leave_time":"2026-10-02T10:30:00Z","duration":1800}');
        }
        return new ZoomMock()
            .respondTo('/oauth/token', 200, '{"access_token":"tok"}')
            .respondTo('status=approved', 200, '{"registrants":[' + String.join(registrants, ',') + ']}')
            .respondTo('status=pending', 200, '{"registrants":[]}')
            .respondTo('/past_webinars/', 200, '{"participants":[' + String.join(participants, ',') + ']}')
            .respondTo('/users/', 200, '{"webinars":[{"id":' + SESSION_ID + '}]}')
            .respondTo('/webinars/' + SESSION_ID, 200, '{"id":' + SESSION_ID + ',"topic":"' + TOPIC
                + '","start_time":"2020-10-02T10:00:00Z","duration":60,"timezone":"Asia/Kolkata","join_url":"https://zoom.us/j/1"}');
    }

    private static Integer logCount() {
        return [SELECT COUNT() FROM API_Log__c WHERE Log_Name__c IN ('ZoomWebhook', 'ZoomWebinarSync')];
    }

    @IsTest
    static void registrationAndAttendanceFlow() {
        configure(false);
        Lead lead = [SELECT Id FROM Lead WHERE Email = :emailOf(0)];

        Test.startTest();
        ZoomEventService.process(event('webinar.registration_created',
            '"registrant":{"id":"r1","email":"BULK0' + EMAIL_DOMAIN + '","first_name":"Anita","last_name":"S","status":"approved","custom_questions":[{"title":"City","value":"Surat"}]}'));
        ZoomEventService.process(event('webinar.registration_created',
            '"registrant":{"id":"r1","email":"' + emailOf(0) + '","status":"approved"}'));
        ZoomEventService.process(event('webinar.participant_joined',
            '"participant":{"user_name":"Anita","email":"' + emailOf(0) + '","registrant_id":"r1","join_time":"2026-10-02T10:00:00Z"}'));
        ZoomEventService.process(event('webinar.participant_left',
            '"participant":{"user_name":"Anita","email":"' + emailOf(0) + '","registrant_id":"r1","leave_time":"2026-10-02T10:20:00Z"}'));
        ZoomEventService.process(event('webinar.participant_joined',
            '"participant":{"user_name":"Guest","email":"guest@elsewhere.com","join_time":"2026-10-02T10:05:00Z"}'));
        Test.stopTest();

        Zoom_Registration__c registration = [
            SELECT Is_Registered__c, Attended__c, Lead__c, Lead_Status__c, Time_In_Session_Minutes__c, Form_Answers__c
            FROM Zoom_Registration__c WHERE Email__c = :emailOf(0)
        ];
        System.assert(registration.Is_Registered__c, 'The registrant must be marked registered');
        System.assert(registration.Attended__c, 'The registrant must be marked attended after joining');
        System.assertEquals(null, registration.Lead__c, 'The webhook must not link Leads; the scheduled sync does');
        System.assertEquals('Pending setup', registration.Lead_Status__c, 'A new registration must wait for the Lead step');
        System.assertEquals(20, registration.Time_In_Session_Minutes__c, 'Time in session must be leave minus join');
        System.assert(registration.Form_Answers__c.contains('City: Surat'), 'Custom question answers must be stored');
        System.assertEquals(0, [SELECT COUNT() FROM Task WHERE WhoId = :lead.Id], 'The webhook must not create Tasks');
        Zoom_Registration__c walkIn = [SELECT Last_Name__c, Lead_Status__c FROM Zoom_Registration__c WHERE Email__c = 'guest@elsewhere.com'];
        System.assertEquals('Guest', walkIn.Last_Name__c, 'A one-word walk-in display name must be stored as the last name');
        System.assertEquals('Pending setup', walkIn.Lead_Status__c, 'A walk-in must also wait for the Lead step');
        Zoom_Webinar__c session = [SELECT Type__c, Registered_Count__c, Attended_Count__c, Walk_In_Count__c FROM Zoom_Webinar__c];
        System.assertEquals('Webinar', session.Type__c, 'Webinar events must create a Webinar session');
        System.assertEquals(1, session.Registered_Count__c, 'One person registered');
        System.assertEquals(1, session.Attended_Count__c, 'One registered person attended');
        System.assertEquals(1, session.Walk_In_Count__c, 'The guest joined without registering');
    }

    @IsTest
    static void cancelAndEndEvents() {
        configure(false);
        Test.startTest();
        ZoomEventService.process(event('webinar.registration_created', '"registrant":{"id":"r2","email":"b@elsewhere.com","status":"approved"}'));
        ZoomEventService.process(event('webinar.registration_cancelled', '"registrant":{"id":"r2","email":"b@elsewhere.com"}'));
        ZoomEventService.process(event('webinar.ended', null));
        Test.stopTest();

        Zoom_Webinar__c session = [SELECT Registered_Count__c, Status__c FROM Zoom_Webinar__c];
        System.assertEquals(0, session.Registered_Count__c, 'A cancelled registration must not count as registered');
        System.assertEquals('Ended', session.Status__c, 'webinar.ended must set the status to Ended');
        System.assertEquals('Cancelled', [SELECT Status__c FROM Zoom_Registration__c].Status__c, 'The registration status must be Cancelled');
    }

    @IsTest
    static void updatedEventWithoutTopicKeepsName() {
        configure(false);
        Test.startTest();
        ZoomEventService.process(event('webinar.started', null));
        ZoomEventService.process('{"event":"webinar.updated","payload":{"object":{"id":"' + SESSION_ID + '","duration":90}}}');
        ZoomEventService.process('{"event":"webinar.updated","payload":{"object":{"id":"555"}}}');
        Test.stopTest();

        Zoom_Webinar__c session = [SELECT Name, Duration_Minutes__c, Status__c FROM Zoom_Webinar__c WHERE Webinar_Id__c = :SESSION_ID];
        System.assertEquals(TOPIC, session.Name, 'A partial update must not overwrite the topic');
        System.assertEquals(90, session.Duration_Minutes__c, 'A partial update must apply the fields it contains');
        System.assertEquals('Started', session.Status__c, 'A partial update must not reset the status');
        System.assertEquals('Zoom Webinar 555', [SELECT Name FROM Zoom_Webinar__c WHERE Webinar_Id__c = '555'].Name,
            'A new session without a topic must get a placeholder name');
    }

    @IsTest
    static void webhookIgnoresOtherHosts() {
        configure(true);
        ZoomConfig.testOverride.Allowed_Host_Ids__c = ' ADMISSIONS , SECONDHOST ';
        Test.startTest();
        ZoomEventService.process(event('meeting.participant_joined', '"host_id":"CLASSROOM","participant":{"user_name":"Student","email":"s@x.com"}'));
        ZoomEventService.process(event('meeting.started', null));
        ZoomEventService.process(event('meeting.started', '"host_id":"SECONDHOST"'));
        ZoomEventService.process(event('meeting.ended', null));
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Zoom_Registration__c], 'Events hosted by someone else must be ignored');
        Zoom_Webinar__c session = [SELECT Status__c FROM Zoom_Webinar__c];
        System.assertEquals('Ended', session.Status__c,
            'An allowed host is accepted, and a later event without host_id is applied to the session it already created');
        System.assertEquals(new Set<String>{ 'ADMISSIONS', 'SECONDHOST' }, ZoomConfig.allowedHostIds(), 'Host IDs must be split and trimmed');
    }

    @IsTest
    static void webhookWithoutHostIgnoresUnknownSession() {
        configure(true);
        ZoomConfig.testOverride.Allowed_Host_Ids__c = 'ADMISSIONS';
        Test.startTest();
        ZoomEventService.process(event('meeting.started', null));
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Zoom_Webinar__c],
            'Without host_id, an event may only update a session Salesforce already holds');
    }

    @IsTest
    static void syncSkipsSessionOfOtherHost() {
        configure(true);
        ZoomConfig.testOverride.Allowed_Host_Ids__c = 'ADMISSIONS';
        Test.setMock(HttpCalloutMock.class, new ZoomMock()
            .respondTo('/oauth/token', 200, '{"access_token":"tok"}')
            .respondTo('/meetings/555', 200, '{"id":555,"host_id":"CLASSROOM","topic":"Class","start_time":"2020-01-01T10:00:00Z","duration":30}'));
        Test.startTest();
        new ZoomWebinarSync(new List<String>{ ZoomWebinarSync.MEETING_PREFIX + '555' }).execute(null);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Zoom_Webinar__c], 'A session hosted by someone else must not be synced');
    }

    @IsTest
    static void meetingEventsIgnoredWhenFlagOff() {
        configure(false);
        Test.startTest();
        ZoomEventService.process(event('meeting.participant_joined',
            '"participant":{"user_name":"A","email":"' + emailOf(1) + '","join_time":"2026-10-02T10:00:00Z"}'));
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Zoom_Webinar__c], 'Meeting events must be ignored while Zoom_Meetings is off');
    }

    @IsTest
    static void meetingEventsProcessedWhenFlagOn() {
        configure(true);
        Lead lead = [SELECT Id FROM Lead WHERE Email = :emailOf(1)];
        Test.startTest();
        ZoomEventService.process(event('meeting.registration_created', '"registrant":{"id":"m1","email":"' + emailOf(1) + '","status":"pending"}'));
        ZoomEventService.process(event('meeting.participant_joined',
            '"participant":{"user_name":"A","email":"' + emailOf(1) + '","join_time":"2026-10-02T10:00:00Z"}'));
        Test.stopTest();

        System.assertEquals('Meeting', [SELECT Type__c FROM Zoom_Webinar__c].Type__c, 'Meeting events must create a Meeting session');
        System.assertEquals('Pending', [SELECT Status__c FROM Zoom_Registration__c].Status__c, 'A pending registrant must be Pending');
        System.assertEquals(0, [SELECT COUNT() FROM Task WHERE WhoId = :lead.Id], 'Meeting events must not create Tasks in the webhook');
    }

    @IsTest
    static void webinarEventsIgnoredWhenFlagOff() {
        configure(true);
        FeatureFlagService.testOverrides.put(ZoomEventService.FLAG_WEBINARS, false);
        Test.startTest();
        RestResponse response = post(event('webinar.registration_created',
            '"registrant":{"id":"r9","email":"' + emailOf(3) + '","status":"approved"}'), true);
        Test.stopTest();

        System.assertEquals(200, response.statusCode, 'A disabled session type must still be acknowledged to Zoom');
        System.assertEquals(0, [SELECT COUNT() FROM Zoom_Webinar__c], 'Webinar events must be ignored while Zoom_Webinars is off');
    }

    @IsTest
    static void discoverSyncsMeetingsOnlyWhenWebinarsOff() {
        configure(true);
        FeatureFlagService.testOverrides.put(ZoomEventService.FLAG_WEBINARS, false);
        ZoomMock mock = new ZoomMock()
            .respondTo('/oauth/token', 200, '{"access_token":"tok"}')
            .respondTo('/meetings?', 200, '{"meetings":[{"id":555}]}')
            .respondTo('/webinars', 400, '{"code":200,"message":"Webinar plan is missing."}');
        Test.setMock(HttpCalloutMock.class, mock);
        ZoomWebinarSync job = new ZoomWebinarSync();
        Test.startTest();
        job.execute(null);
        Test.stopTest();

        for (String endpoint : mock.endpoints) {
            System.assert(!endpoint.contains('/webinars'), 'No webinar endpoint may be called while Zoom_Webinars is off: ' + endpoint);
        }
        System.assert(mock.endpoints.size() >= 2, 'The meeting list and the meeting itself must be requested');
        System.assert(mock.endpoints[1].contains('/meetings?'), 'Discovery must list upcoming meetings');
        System.assertEquals(0, logCount(), 'Running meetings-only must not log errors');
    }

    @IsTest
    static void concurrentSessionInsertIsRetriedAsUpdate() {
        configure(false);
        ZoomEventService.simulatedDuplicateFailures = 1;
        Test.startTest();
        ZoomEventService.process(event('webinar.started', null));
        Test.stopTest();

        System.assertEquals(0, ZoomEventService.simulatedDuplicateFailures, 'The simulated concurrent insert must have been hit');
        Zoom_Webinar__c session = [SELECT Name, Status__c FROM Zoom_Webinar__c WHERE Webinar_Id__c = :SESSION_ID];
        System.assertEquals('Started', session.Status__c, 'The retried save must apply the event');
        System.assertEquals(TOPIC, session.Name, 'The retried save must keep the real topic');
    }

    @IsTest
    static void concurrentRegistrationInsertIsRetriedOnce() {
        configure(false);
        ZoomEventService.process(event('webinar.started', null));
        ZoomEventService.simulatedDuplicateFailures = 1;
        Test.startTest();
        ZoomEventService.process(event('webinar.registration_created',
            '"registrant":{"id":"r4","email":"' + emailOf(4) + '","status":"approved"}'));
        Test.stopTest();

        System.assertEquals(0, ZoomEventService.simulatedDuplicateFailures, 'The simulated concurrent insert must have been hit');
        System.assertEquals(1, [SELECT COUNT() FROM Zoom_Registration__c WHERE Email__c = :emailOf(4)], 'Exactly one registration must exist');
        System.assertEquals('Pending setup', [SELECT Lead_Status__c FROM Zoom_Registration__c WHERE Email__c = :emailOf(4)].Lead_Status__c,
            'The retried registration must keep its Lead Status');
    }

    @IsTest
    static void duplicateRetriedOnlyOnce() {
        configure(false);
        ZoomEventService.process(event('webinar.started', null));
        ZoomEventService.simulatedDuplicateFailures = 2;
        DmlException caught;
        Test.startTest();
        try {
            ZoomEventService.process(event('webinar.registration_created',
                '"registrant":{"id":"r5","email":"' + emailOf(5) + '","status":"approved"}'));
        } catch (DmlException e) {
            caught = e;
        }
        Test.stopTest();

        System.assertNotEquals(null, caught, 'A second DUPLICATE_VALUE must be raised, not retried again');
        System.assert(ZoomEventService.isDuplicateValue(caught), 'The raised error must be the duplicate failure');
    }

    @IsTest
    static void otherDmlErrorsAreNotTreatedAsDuplicates() {
        System.assertEquals(false, ZoomEventService.isDuplicateValue(new DmlException('REQUIRED_FIELD_MISSING')),
            'Only DUPLICATE_VALUE may trigger a retry');
    }

    @IsTest
    static void syncNeverMovesStatusBackwards() {
        Datetime past = Datetime.now().addHours(-1);
        Datetime future = Datetime.now().addHours(1);

        System.assertEquals('Ended', ZoomWebinarSync.resolveStatus('Ended', null),
            'An instant meeting the webhook marked Ended must stay Ended when Zoom gives no end time');
        System.assertEquals('Started', ZoomWebinarSync.resolveStatus('Started', null), 'A started meeting must stay Started');
        System.assertEquals('Ended', ZoomWebinarSync.resolveStatus('Ended', future),
            'A meeting that ended early must stay Ended even if its planned end is in the future');
        System.assertEquals('Deleted', ZoomWebinarSync.resolveStatus('Deleted', past), 'A deleted meeting must stay Deleted');
        System.assertEquals('Ended', ZoomWebinarSync.resolveStatus('Started', past), 'A planned end in the past must move Started to Ended');
        System.assertEquals('Ended', ZoomWebinarSync.resolveStatus('Scheduled', past), 'A planned end in the past must move Scheduled to Ended');
        System.assertEquals('Scheduled', ZoomWebinarSync.resolveStatus(null, future), 'A new future meeting must be Scheduled');
        System.assertEquals('Scheduled', ZoomWebinarSync.resolveStatus(null, null), 'A new meeting with no end time must be Scheduled');
    }

    @IsTest
    static void unknownAndEmptyEventsAreIgnored() {
        configure(true);
        Test.startTest();
        ZoomEventService.process('{"event":"recording.completed","payload":{"object":{"id":"1"}}}');
        ZoomEventService.process('{"event":"webinar.started"}');
        ZoomEventService.process('[]');
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Zoom_Webinar__c], 'Events that are not webinar or meeting events must be ignored');
    }

    @IsTest
    static void webhookValidationAndSignature() {
        configure(false);
        Test.startTest();
        RestResponse challenge = post('{"event":"endpoint.url_validation","payload":{"plainToken":"abc"}}', false);
        String body = event('webinar.registration_created', '"registrant":{"id":"r3","email":"c@elsewhere.com","status":"approved"}');
        RestRequest badRequest = new RestRequest();
        badRequest.requestBody = Blob.valueOf(body);
        badRequest.addHeader('x-zm-request-timestamp', '123');
        badRequest.addHeader('x-zm-signature', 'v0=bad');
        RestContext.request = badRequest;
        RestContext.response = new RestResponse();
        ZoomWebhook.receive();
        Integer badSignatureStatus = RestContext.response.statusCode;
        RestResponse unsigned = post(body, false);
        RestResponse accepted = post(body, true);
        Test.stopTest();

        System.assertEquals(200, challenge.statusCode, 'The URL validation challenge must succeed');
        System.assert(challenge.responseBody.toString().contains(ZoomWebhook.hmac('abc', SECRET)), 'The challenge must return HMAC(plainToken)');
        System.assertEquals(401, badSignatureStatus, 'A wrong signature must be rejected');
        System.assertEquals(401, unsigned.statusCode, 'A missing signature must be rejected');
        System.assertEquals(200, accepted.statusCode, 'A correctly signed event must be accepted');
        System.assertEquals(1, [SELECT COUNT() FROM Zoom_Registration__c], 'Only the signed event must be processed');
    }

    @IsTest
    static void webhookRejectsMalformedRequests() {
        configure(false);
        Test.startTest();
        RestResponse invalidJson = post('not json', true);
        RestResponse missingToken = post('{"event":"endpoint.url_validation","payload":{}}', false);
        ZoomConfig.testOverride = new Zoom_Config__mdt();
        RestResponse noSecret = post(event('webinar.started', null), false);
        Test.stopTest();

        System.assertEquals(400, invalidJson.statusCode, 'A non-JSON body must return 400');
        System.assertEquals(400, missingToken.statusCode, 'A validation challenge without plainToken must return 400');
        System.assertEquals(500, noSecret.statusCode, 'A missing secret token must return 500');
        System.assertEquals(1, logCount(), 'A missing secret token must be logged');
    }

    @IsTest
    static void webhookIgnoresEventsWhenIntegrationDisabled() {
        configure(false);
        FeatureFlagService.testOverrides.put(ZoomWebhook.FLAG_INTEGRATION, false);
        Test.startTest();
        RestResponse response = post(event('webinar.started', null), true);
        Test.stopTest();

        System.assertEquals(200, response.statusCode, 'A disabled integration must still acknowledge Zoom');
        System.assert(response.responseBody.toString().contains('ignored'), 'The response must say the event was ignored');
        System.assertEquals(0, [SELECT COUNT() FROM Zoom_Webinar__c], 'No records may be written while the integration is disabled');
    }

    @IsTest
    static void webhookProcessingFailureRollsBackAndLogs() {
        configure(false);
        Test.startTest();
        RestResponse response = post('{"event":"webinar.registration_created","payload":{"object":{"topic":"No id","registrant":{"email":"x@elsewhere.com"}}}}', true);
        Test.stopTest();

        System.assertEquals(500, response.statusCode, 'A processing failure must return 500 so Zoom retries');
        System.assertEquals(0, [SELECT COUNT() FROM Zoom_Webinar__c], 'Partial work must be rolled back');
        System.assertEquals(1, logCount(), 'The failure must be logged to API_Log__c');
    }

    @IsTest
    static void apiSyncImportsWebinar() {
        configure(false);
        Test.setMock(HttpCalloutMock.class, standardWebinarMock(1, 1));
        Test.startTest();
        System.enqueueJob(new ZoomWebinarSync());
        Test.stopTest();

        Zoom_Webinar__c session = [SELECT Status__c, Type__c, Registered_Count__c, Attended_Count__c, Last_Synced_At__c FROM Zoom_Webinar__c];
        System.assertEquals('Ended', session.Status__c, 'A webinar in the past must be marked Ended');
        System.assertEquals('Webinar', session.Type__c, 'The synced session must be a Webinar');
        System.assertEquals(1, session.Registered_Count__c, 'One registrant must be imported');
        System.assertEquals(1, session.Attended_Count__c, 'One participant must be imported');
        System.assertNotEquals(null, session.Last_Synced_At__c, 'The sync time must be recorded');
    }

    @IsTest
    static void apiSyncBulk200() {
        configure(false);
        Test.setMock(HttpCalloutMock.class, standardWebinarMock(BULK_SIZE, BULK_SIZE));
        ZoomWebinarSync job = new ZoomWebinarSync(new List<String>{ SESSION_ID });
        Test.startTest();
        job.execute(null);
        Test.stopTest();

        System.assertEquals(BULK_SIZE, [SELECT COUNT() FROM Zoom_Registration__c WHERE Lead_Status__c = 'Pending setup' AND Attended__c = true],
            'All 200 registrants must be stored, marked attended and left for the Lead step');
        System.assertEquals(0, [SELECT COUNT() FROM Task WHERE Subject LIKE 'Zoom Webinar%'], 'The session sync must not create Tasks');
        System.assertEquals(1, ZoomLeadQueueable.enqueuedJobs.size(), 'The end of the sync chain must start the Lead step');
        Zoom_Webinar__c session = [SELECT Registered_Count__c, Attended_Count__c FROM Zoom_Webinar__c];
        System.assertEquals(BULK_SIZE, session.Registered_Count__c, 'Roll-up must count 200 registered');
        System.assertEquals(BULK_SIZE, session.Attended_Count__c, 'Roll-up must count 200 attended');
    }

    @IsTest
    static void apiSyncMeetingWithoutRegistration() {
        configure(true);
        ZoomMock mock = new ZoomMock()
            .respondTo('/oauth/token', 200, '{"access_token":"tok"}')
            .respondTo('/registrants', 400, '{"code":3000,"message":"Registration has not been enabled for this meeting"}')
            .respondTo('/past_meetings/', 200, '{"participants":[{"user_email":"' + emailOf(2) + '","name":"P","duration":600}]}')
            .respondTo('/meetings/555', 200, '{"id":555,"topic":"Counsellor Q&A","start_time":"2020-01-01T10:00:00Z","duration":30}');
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        new ZoomWebinarSync(new List<String>{ ZoomWebinarSync.MEETING_PREFIX + '555' }).execute(null);
        Test.stopTest();

        Zoom_Webinar__c session = [SELECT Type__c, Status__c FROM Zoom_Webinar__c];
        System.assertEquals('Meeting', session.Type__c, 'The synced session must be a Meeting');
        Zoom_Registration__c registration = [SELECT Attended__c, Time_In_Session_Minutes__c, Status__c FROM Zoom_Registration__c];
        System.assert(registration.Attended__c, 'The participant must be marked attended');
        System.assertEquals(10, registration.Time_In_Session_Minutes__c, 'Duration in seconds must be converted to minutes');
        System.assertEquals('Not Registered', registration.Status__c, 'A meeting without registration has walk-in participants');
    }

    @IsTest
    static void apiSyncSkipsMeetingWhenFlagOff() {
        configure(false);
        ZoomMock mock = new ZoomMock();
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        new ZoomWebinarSync(new List<String>{ ZoomWebinarSync.MEETING_PREFIX + '555' }).execute(null);
        Test.stopTest();

        System.assert(mock.endpoints.isEmpty(), 'No Zoom call may be made for a meeting while Zoom_Meetings is off');
    }

    @IsTest
    static void rateLimitIsRetriedWithBackoff() {
        configure(false);
        Test.setMock(HttpCalloutMock.class, new ZoomMock()
            .respondTo('/oauth/token', 200, '{"access_token":"tok"}')
            .respondTo('/webinars/', 429, '{"code":429,"message":"Too many requests"}'));
        Test.startTest();
        new ZoomWebinarSync(new List<String>{ SESSION_ID, '111' }).execute(null);
        Test.stopTest();

        System.assertEquals(1, ZoomWebinarSync.enqueuedJobs.size(), 'A rate-limited call must be retried once');
        System.assert(ZoomLeadQueueable.enqueuedJobs.isEmpty(), 'A retry carries the chain, so the Lead step must not start yet');
        System.assertEquals(1, ZoomWebinarSync.enqueuedDelays[0], 'The first retry must wait 1 minute');
        System.assertEquals(1, ZoomWebinarSync.enqueuedJobs[0].attempt, 'The retry must carry the attempt number');
        System.assertEquals(new List<String>{ SESSION_ID, '111' }, ZoomWebinarSync.enqueuedJobs[0].sessionKeys,
            'The retry must keep the failed session first and the rest of the queue');
        System.assertEquals(0, logCount(), 'A retried failure must not be logged yet');
    }

    @IsTest
    static void retriesExhaustedAreLoggedAndQueueContinues() {
        configure(false);
        Test.setMock(HttpCalloutMock.class, new ZoomMock()
            .respondTo('/oauth/token', 200, '{"access_token":"tok"}')
            .respondTo('/webinars/', 503, 'Service Unavailable'));
        ZoomWebinarSync job = new ZoomWebinarSync(new List<String>{ SESSION_ID, '111' });
        job.attempt = ZoomWebinarSync.MAX_RETRIES;
        Test.startTest();
        job.execute(null);
        Test.stopTest();

        System.assertEquals(1, logCount(), 'A failure after the last retry must be logged');
        System.assertEquals(1, ZoomWebinarSync.enqueuedJobs.size(), 'The chain must continue with the next session');
        System.assertEquals(0, ZoomWebinarSync.enqueuedDelays[0], 'The next session must run without delay');
        System.assertEquals(new List<String>{ '111' }, ZoomWebinarSync.enqueuedJobs[0].sessionKeys, 'Only the remaining session must be queued');
        System.assert(ZoomLeadQueueable.enqueuedJobs.isEmpty(), 'The Lead step must wait until the last session is synced');
    }

    @IsTest
    static void unauthorizedIsLoggedNotRetried() {
        configure(false);
        Test.setMock(HttpCalloutMock.class, new ZoomMock().respondTo('/oauth/token', 401, '{"reason":"Invalid client_id or client_secret"}'));
        Test.startTest();
        new ZoomWebinarSync(new List<String>{ SESSION_ID }).execute(null);
        Test.stopTest();

        System.assert(ZoomWebinarSync.enqueuedJobs.isEmpty(), 'A 401 must not be retried');
        System.assertEquals(1, ZoomLeadQueueable.enqueuedJobs.size(), 'The Lead step must still run after the last session failed');
        API_Log__c log = [SELECT Response__c FROM API_Log__c WHERE Log_Name__c = 'ZoomWebinarSync'];
        System.assert(log.Response__c.contains('HTTP 401'), 'The log must contain the HTTP status');
    }

    @IsTest
    static void timeoutIsRetried() {
        configure(false);
        Test.setMock(HttpCalloutMock.class, new ZoomMock().respondTo('/oauth/token', 200, '{"access_token":"tok"}').failWithTimeout());
        Test.startTest();
        new ZoomWebinarSync(new List<String>{ SESSION_ID }).execute(null);
        Test.stopTest();

        System.assertEquals(1, ZoomWebinarSync.enqueuedJobs.size(), 'A callout timeout must be retried');
    }

    @IsTest
    static void discoverFailureIsRetried() {
        configure(false);
        Test.setMock(HttpCalloutMock.class, new ZoomMock()
            .respondTo('/oauth/token', 200, '{"access_token":"tok"}')
            .respondTo('/users/', 500, 'error'));
        Test.startTest();
        new ZoomWebinarSync().execute(null);
        Test.stopTest();

        System.assertEquals(1, ZoomWebinarSync.enqueuedJobs.size(), 'A Zoom 5xx during discovery must be retried');
        System.assertEquals(null, ZoomWebinarSync.enqueuedJobs[0].sessionKeys, 'The retry must run discovery again');
        System.assertEquals(0, logCount(), 'A retried discovery failure must not be logged yet');
    }

    @IsTest
    static void emptyDiscoveryStartsLeadStep() {
        configure(false);
        Test.setMock(HttpCalloutMock.class, new ZoomMock()
            .respondTo('/oauth/token', 200, '{"access_token":"tok"}')
            .respondTo('/users/', 200, '{"webinars":[]}'));
        Test.startTest();
        new ZoomWebinarSync().execute(null);
        Test.stopTest();

        System.assert(ZoomWebinarSync.enqueuedJobs.isEmpty(), 'Nothing to sync means no further sync job');
        System.assertEquals(1, ZoomLeadQueueable.enqueuedJobs.size(), 'Pending registrations must still be processed when Zoom has no sessions');
    }

    @IsTest
    static void failedDiscoveryStillStartsLeadStep() {
        configure(false);
        Test.setMock(HttpCalloutMock.class, new ZoomMock().respondTo('/oauth/token', 401, '{"reason":"Invalid client"}'));
        Test.startTest();
        new ZoomWebinarSync().execute(null);
        Test.stopTest();

        System.assertEquals(1, logCount(), 'The discovery failure must be logged');
        System.assertEquals(1, ZoomLeadQueueable.enqueuedJobs.size(), 'A failed discovery must not block the Lead step');
    }

    @IsTest
    static void missingCredentialsAreLoggedNotRetried() {
        configure(false);
        ZoomConfig.testOverride = new Zoom_Config__mdt(Account_Id__c = 'acct');
        ZoomMock mock = new ZoomMock();
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        new ZoomWebinarSync(new List<String>{ SESSION_ID }).execute(null);
        Test.stopTest();

        System.assert(mock.endpoints.isEmpty(), 'No call may be made without client credentials');
        System.assert(ZoomWebinarSync.enqueuedJobs.isEmpty(), 'Missing credentials must not be retried');
        System.assertEquals(1, logCount(), 'Missing credentials must be logged');
    }

    @IsTest
    static void syncDisabledByFlagMakesNoCalls() {
        configure(false);
        FeatureFlagService.testOverrides.put(ZoomWebhook.FLAG_INTEGRATION, false);
        ZoomMock mock = new ZoomMock();
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        new ZoomWebinarSync().execute(null);
        Test.stopTest();

        System.assert(mock.endpoints.isEmpty(), 'No Zoom call may be made while Zoom_Integration is off');
    }

    @IsTest
    static void namedCredentialPathUsesCalloutPrefix() {
        configure(false);
        FeatureFlagService.testOverrides.put(ZoomApiService.FLAG_NAMED_CREDENTIAL, true);
        ZoomMock mock = new ZoomMock()
            .respondTo('/oauth/token', 200, '{"access_token":"tok"}')
            .respondTo('/webinars/', 200, '{"id":' + SESSION_ID + ',"topic":"' + TOPIC + '"}');
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        ZoomApiService.get('/webinars/' + SESSION_ID);
        Test.stopTest();

        System.assert(mock.endpoints[0].startsWith('callout:ZOOM_OAUTH/oauth/token'), 'The token must be fetched through Named Credential ZOOM_OAUTH');
        System.assert(mock.endpoints[1].startsWith('callout:ZOOM_API/webinars/'), 'API calls must go through Named Credential ZOOM_API');
    }

    @IsTest
    static void invalidJsonFromZoomIsReported() {
        configure(false);
        Test.setMock(HttpCalloutMock.class, new ZoomMock()
            .respondTo('/oauth/token', 200, '{"access_token":"tok"}')
            .respondTo('/webinars/', 200, 'not json'));
        ZoomApiService.ZoomApiException caught;
        Test.startTest();
        try {
            ZoomApiService.get('/webinars/' + SESSION_ID);
        } catch (ZoomApiService.ZoomApiException e) {
            caught = e;
        }
        Test.stopTest();

        System.assertNotEquals(null, caught, 'Invalid JSON from Zoom must raise ZoomApiException');
        System.assertEquals(false, caught.isRetryable, 'Invalid JSON must not be retried');
    }

    @IsTest
    static void schedulerAndDefaultConfig() {
        System.assertNotEquals(null, ZoomConfig.get(), 'ZoomConfig must never return null');
        ZoomWebinarSyncScheduler.jobName = 'Zoom Webinar Sync Test';
        FeatureFlagService.testOverrides.put(ZoomWebhook.FLAG_INTEGRATION, false);
        Test.startTest();
        Id jobId = ZoomWebinarSyncScheduler.schedule();
        Test.stopTest();

        CronTrigger job = [SELECT CronJobDetail.Name, CronExpression FROM CronTrigger WHERE Id = :jobId];
        System.assertEquals('Zoom Webinar Sync Test', job.CronJobDetail.Name, 'The job must be scheduled under the configured name');
        System.assertEquals('0 0 0/2 * * ?', job.CronExpression, 'The job must run every 2 hours');
        System.assertEquals('Zoom Webinar Sync', ZoomWebinarSyncScheduler.JOB_NAME, 'The production job name must not change');
    }

    @IsTest
    static void newSessionGetsDefaultDepartmentAndYear() {
        configure(true);
        ZoomConfig.testOverride.Default_Department__c = ' undergraduation ';
        ZoomConfig.testOverride.Default_Admission_Year__c = 'Admission Year - 2027';
        Test.startTest();
        ZoomEventService.process(event('meeting.created', null));
        ZoomEventService.process(event('meeting.started', null));
        Test.stopTest();

        Zoom_Webinar__c session = [SELECT Department__c, Admission_Year__c FROM Zoom_Webinar__c WHERE Webinar_Id__c = :SESSION_ID];
        System.assertEquals('Undergraduation', session.Department__c, 'A new session must get the default Department (matched case-insensitively)');
        System.assertEquals('Admission Year - 2027', session.Admission_Year__c, 'A new session must get the default Admission Year');
    }

    @IsTest
    static void existingSessionValuesAreNeverReplacedByDefaults() {
        configure(true);
        insert new Zoom_Webinar__c(Name = TOPIC, Webinar_Id__c = SESSION_ID, Type__c = 'Meeting', Status__c = 'Scheduled');
        ZoomConfig.testOverride.Default_Department__c = 'Undergraduation';
        ZoomConfig.testOverride.Default_Admission_Year__c = 'Admission Year - 2027';
        Test.startTest();
        ZoomEventService.process(event('meeting.updated', null));
        Test.stopTest();

        Zoom_Webinar__c session = [SELECT Department__c, Admission_Year__c FROM Zoom_Webinar__c WHERE Webinar_Id__c = :SESSION_ID];
        System.assertEquals(null, session.Department__c, 'Defaults must apply only when a session is created, not to existing sessions');
        System.assertEquals(null, session.Admission_Year__c, 'Defaults must apply only when a session is created, not to existing sessions');
    }

    @IsTest
    static void invalidOrBlankDefaultsLeaveSessionBlank() {
        configure(true);
        ZoomConfig.testOverride.Default_Department__c = 'Not A Department';
        Test.startTest();
        ZoomEventService.process(event('meeting.created', null));
        Test.stopTest();

        Zoom_Webinar__c session = [SELECT Department__c, Admission_Year__c FROM Zoom_Webinar__c WHERE Webinar_Id__c = :SESSION_ID];
        System.assertEquals(null, session.Department__c, 'An invalid default must be ignored so the save does not fail');
        System.assertEquals(null, session.Admission_Year__c, 'A blank default must leave the Admission Year blank');
        System.assertEquals(0, logCount(), 'An invalid default must not cause an error');
    }

    @IsTest
    static void sessionDefaultsKeepValuesAlreadySet() {
        configure(true);
        ZoomConfig.testOverride.Default_Department__c = 'Undergraduation';
        ZoomConfig.testOverride.Default_Admission_Year__c = 'Admission Year - 2027';
        Zoom_Webinar__c session = new Zoom_Webinar__c(Department__c = 'Masters', Admission_Year__c = 'Admission Year - 2028');

        Test.startTest();
        Set<String> filled = ZoomEventService.applySessionDefaults(session);
        Test.stopTest();

        System.assert(filled.isEmpty(), 'Values already on the session must not be reported as filled');
        System.assertEquals('Masters', session.Department__c, 'A Department already set must not be replaced');
        System.assertEquals('Admission Year - 2028', session.Admission_Year__c, 'An Admission Year already set must not be replaced');
    }

    @IsTest
    static void concurrentInsertRetryKeepsDefaults() {
        configure(true);
        ZoomConfig.testOverride.Default_Department__c = 'Undergraduation';
        ZoomConfig.testOverride.Default_Admission_Year__c = 'Admission Year - 2027';
        ZoomEventService.simulatedDuplicateFailures = 1;
        Test.startTest();
        ZoomEventService.process(event('meeting.started', null));
        Test.stopTest();

        Zoom_Webinar__c session = [SELECT Department__c, Admission_Year__c FROM Zoom_Webinar__c WHERE Webinar_Id__c = :SESSION_ID];
        System.assertEquals(0, ZoomEventService.simulatedDuplicateFailures, 'The simulated concurrent insert must have been hit');
        System.assertEquals('Undergraduation', session.Department__c, 'A session created on retry must still get the default Department');
        System.assertEquals('Admission Year - 2027', session.Admission_Year__c, 'A session created on retry must still get the default Admission Year');
    }
}