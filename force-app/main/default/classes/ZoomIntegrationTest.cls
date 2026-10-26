@IsTest
private class ZoomIntegrationTest {

    private class ApiMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest r) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            String u = r.getEndpoint();
            if (u.contains('/oauth/token')) { res.setBody('{"access_token":"tok"}'); }
            else if (u.contains('/registrants')) {
                res.setBody(u.contains('status=approved')
                    ? '{"registrants":[{"id":"r1","email":"anita@test.com","first_name":"Anita","last_name":"S","status":"approved","create_time":"2026-10-01T10:00:00Z"}]}'
                    : '{"registrants":[]}');
            }
            else if (u.contains('/past_webinars/')) {
                res.setBody('{"participants":[{"user_email":"anita@test.com","name":"Anita","registrant_id":"r1","join_time":"2026-10-02T10:00:00Z","leave_time":"2026-10-02T10:30:00Z","duration":1800},'
                    + '{"user_email":"walkin@test.com","name":"Walk","join_time":"2026-10-02T10:05:00Z","leave_time":"2026-10-02T10:10:00Z","duration":300}]}');
            }
            else if (u.contains('/users/')) { res.setBody('{"webinars":[{"id":99887766}]}'); }
            else { res.setBody('{"id":99887766,"topic":"MBA Open House","start_time":"2020-10-02T10:00:00Z","duration":60,"timezone":"Asia/Kolkata","join_url":"https://zoom.us/j/1"}'); }
            return res;
        }
    }

    private static void config() {
        ZoomConfig.testOverride = new Zoom_Config__mdt(Webhook_Secret_Token__c = 'secret', Account_Id__c = 'a',
            Client_Id__c = 'c', Client_Secret__c = 's', Zoom_User_Id__c = 'me', Create_Activities__c = true);
    }

    private static String ev(String event, String obj) {
        return '{"event":"' + event + '","event_ts":1790000000000,"payload":{"object":{"id":"99887766","topic":"MBA Open House","start_time":"2026-10-02T10:00:00Z","duration":60,"timezone":"Asia/Kolkata",' + obj + '}}}';
    }

    @IsTest static void registrationAndAttendanceFlow() {
        config();
        Lead l = new Lead(LastName = 'Anita', Company = 'X', Email = 'anita@test.com');
        insert l;
        ZoomEventService.process(ev('webinar.registration_created',
            '"registrant":{"id":"r1","email":"Anita@Test.com","first_name":"Anita","last_name":"S","status":"approved","custom_questions":[{"title":"City","value":"Surat"}]}'));
        ZoomEventService.process(ev('webinar.registration_created',
            '"registrant":{"id":"r1","email":"Anita@Test.com","first_name":"Anita","last_name":"S","status":"approved"}')); // duplicate delivery
        ZoomEventService.process(ev('webinar.participant_joined',
            '"participant":{"user_name":"Anita","email":"anita@test.com","registrant_id":"r1","join_time":"2026-10-02T10:00:00Z"}'));
        ZoomEventService.process(ev('webinar.participant_left',
            '"participant":{"user_name":"Anita","email":"anita@test.com","registrant_id":"r1","leave_time":"2026-10-02T10:20:00Z"}'));
        ZoomEventService.process(ev('webinar.participant_joined',
            '"participant":{"user_name":"Guest","email":"guest@test.com","join_time":"2026-10-02T10:05:00Z"}'));

        Zoom_Registration__c r = [SELECT Is_Registered__c, Attended__c, Lead__c, Is_Matched__c, Time_In_Session_Minutes__c,
                                  Form_Answers__c FROM Zoom_Registration__c WHERE Email__c = 'anita@test.com'];
        System.assert(r.Is_Registered__c); System.assert(r.Attended__c); System.assert(r.Is_Matched__c);
        System.assertEquals(l.Id, r.Lead__c);
        System.assertEquals(20, r.Time_In_Session_Minutes__c);
        System.assert(r.Form_Answers__c.contains('Surat'));
        System.assertEquals(2, [SELECT COUNT() FROM Task WHERE WhoId = :l.Id]);
        Zoom_Webinar__c w = [SELECT Registered_Count__c, Attended_Count__c, Walk_In_Count__c FROM Zoom_Webinar__c];
        System.assertEquals(1, w.Registered_Count__c); System.assertEquals(1, w.Attended_Count__c); System.assertEquals(1, w.Walk_In_Count__c);
    }

    @IsTest static void cancelAndEndEvents() {
        config();
        ZoomEventService.process(ev('webinar.registration_created', '"registrant":{"id":"r2","email":"b@test.com","status":"approved"}'));
        ZoomEventService.process(ev('webinar.registration_cancelled', '"registrant":{"id":"r2","email":"b@test.com"}'));
        ZoomEventService.process(ev('webinar.ended', '"x":1'));
        System.assertEquals(0, [SELECT Registered_Count__c FROM Zoom_Webinar__c].Registered_Count__c);
        System.assertEquals('Ended', [SELECT Status__c FROM Zoom_Webinar__c].Status__c);
    }

    @IsTest static void webhookValidationAndSignature() {
        config();
        RestRequest req = new RestRequest(); RestResponse res = new RestResponse();
        RestContext.request = req; RestContext.response = res;
        req.requestBody = Blob.valueOf('{"event":"endpoint.url_validation","payload":{"plainToken":"abc"}}');
        ZoomWebhook.receive();
        System.assertEquals(200, res.statusCode);
        System.assert(res.responseBody.toString().contains(ZoomWebhook.hmac('abc', 'secret')));

        String body = ev('webinar.registration_created', '"registrant":{"id":"r3","email":"c@test.com","status":"approved"}');
        req.requestBody = Blob.valueOf(body);
        req.addHeader('x-zm-request-timestamp', '123');
        req.addHeader('x-zm-signature', 'v0=bad');
        ZoomWebhook.receive();
        System.assertEquals(401, res.statusCode);

        req.addHeader('x-zm-signature', 'v0=' + ZoomWebhook.hmac('v0:123:' + body, 'secret'));
        ZoomWebhook.receive();
        System.assertEquals(200, res.statusCode);
        System.assertEquals(1, [SELECT COUNT() FROM Zoom_Registration__c]);
    }

    @IsTest static void apiSync() {
        config();
        insert new Contact(LastName = 'Anita', Email = 'anita@test.com', MobilePhone = '9876543210');
        Test.setMock(HttpCalloutMock.class, new ApiMock());
        Test.startTest();
        System.enqueueJob(new ZoomWebinarSync());
        Test.stopTest();
        Zoom_Webinar__c w = [SELECT Status__c, Registered_Count__c, Attended_Count__c, Walk_In_Count__c FROM Zoom_Webinar__c];
        System.assertEquals('Ended', w.Status__c);
        System.assertEquals(1, w.Registered_Count__c); System.assertEquals(1, w.Attended_Count__c); System.assertEquals(1, w.Walk_In_Count__c);
    }

    @IsTest static void schedulerAndDefaultConfig() {
        System.assertNotEquals(null, ZoomConfig.get());
        Test.startTest();
        ZoomWebinarSyncScheduler.schedule();
        Test.stopTest();
        System.assertEquals(1, [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name = 'Zoom Webinar Sync']);
    }
}