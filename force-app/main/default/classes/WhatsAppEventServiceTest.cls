@IsTest
private class WhatsAppEventServiceTest {

    private static Lead mkLead() {
        Lead l = new Lead(LastName = 'Wa', Company = 'AU', MobilePhone = '+91 98765 43210');
        insert l;
        return l;
    }

    private static String ev(String id, String status, String ts, String to, String sub) {
        return '{"messageId":"' + id + '","status":"' + status + '","timestamp":"' + ts + '","to":"' + to
            + '","subscriberKey":"' + sub + '","templateName":"welcome","journeyName":"J1"}';
    }

    @IsTest static void statusMovesForwardAndSummaryUpdates() {
        Lead l = mkLead();
        WhatsAppEventService.process('[' + ev('m1', 'sent', '2026-10-14T10:00:00Z', '919876543210', l.Id) + ']');
        WhatsAppEventService.process(ev('m1', 'delivered', '2026-10-14T10:00:05Z', '919876543210', l.Id));
        WhatsAppEventService.process(ev('m1', 'read', '2026-10-14T10:05:00Z', '919876543210', l.Id));
        // late "sent" must not downgrade
        WhatsAppEventService.process(ev('m1', 'sent', '2026-10-14T09:59:59Z', '919876543210', l.Id));

        WhatsApp_Message__c m = [SELECT Status__c, Sent_At__c, Delivered_At__c, Read_At__c, Lead__c, Is_Matched__c, Template_Name__c FROM WhatsApp_Message__c];
        System.assertEquals('Read', m.Status__c);
        System.assertEquals(l.Id, m.Lead__c);
        System.assert(m.Is_Matched__c);
        System.assertNotEquals(null, m.Delivered_At__c);
        System.assertNotEquals(null, m.Read_At__c);
        System.assertEquals('welcome', m.Template_Name__c);
        System.assertEquals(4, [SELECT COUNT() FROM WhatsApp_Message_Event__c]);

        Lead r = [SELECT WA_Last_Status__c, WA_Sent_Count__c, WA_Delivered_Count__c, WA_Read_Count__c FROM Lead WHERE Id = :l.Id];
        System.assertEquals('Read', r.WA_Last_Status__c);
        System.assertEquals(1, r.WA_Sent_Count__c);
        System.assertEquals(1, r.WA_Delivered_Count__c);
        System.assertEquals(1, r.WA_Read_Count__c);
    }

    @IsTest static void duplicateEventIgnored() {
        Lead l = mkLead();
        String body = '{"eventId":"e1",' + ev('m2', 'sent', '2026-10-14T10:00:00Z', '9876543210', l.Id).substring(1);
        WhatsAppEventService.process(body);
        WhatsAppEventService.process(body);
        System.assertEquals(1, [SELECT COUNT() FROM WhatsApp_Message_Event__c]);
    }

    @IsTest static void matchesByPhoneAndFailure() {
        Lead l = mkLead();
        WhatsAppEventService.process('{"events":[' + ev('m3', 'failed', '1760436000', '+919876543210', '')
            .replace('"templateName"', '"errorMessage":"Number not on WhatsApp","templateName"') + ']}');
        WhatsApp_Message__c m = [SELECT Status__c, Lead__c, Failure_Reason__c, Failed_At__c FROM WhatsApp_Message__c];
        System.assertEquals('Failed', m.Status__c);
        System.assertEquals(l.Id, m.Lead__c);
        System.assertEquals('Number not on WhatsApp', m.Failure_Reason__c);
        System.assertEquals(1, [SELECT WA_Failed_Count__c FROM Lead WHERE Id = :l.Id].WA_Failed_Count__c);
    }

    @IsTest static void unmatchedAndUnknownPayloads() {
        WhatsAppEventService.process(ev('m4', 'delivered', '2026-10-14T10:00:00Z', '9000000000', ''));
        System.assertEquals(false, [SELECT Is_Matched__c FROM WhatsApp_Message__c].Is_Matched__c);
        WhatsAppEventService.process('not json');
        WhatsAppEventService.process('{"foo":"bar"}');
        System.assertEquals(2, [SELECT COUNT() FROM WhatsApp_Message_Event__c WHERE Processing_Status__c = 'Ignored']);
        System.assertEquals(0, WhatsAppEventService.process(''));
    }

    @IsTest static void normalisation() {
        System.assertEquals('Failed', WhatsAppEventService.normaliseStatus('Undelivered'));
        System.assertEquals('Read', WhatsAppEventService.normaliseStatus('MessageRead'));
        System.assertEquals('Delivered', WhatsAppEventService.normaliseStatus('DELIVERED'));
        System.assertEquals('Sent', WhatsAppEventService.normaliseStatus('submitted'));
        System.assertEquals(null, WhatsAppEventService.normaliseStatus('weird'));
        System.assertEquals(null, WhatsAppEventService.last10('123'));
    }

    @IsTest static void webhookEndpoint() {
        Lead l = mkLead();
        RestContext.request = new RestRequest();
        RestContext.response = new RestResponse();
        RestContext.request.requestBody = Blob.valueOf(ev('m5', 'sent', '2026-10-14T10:00:00Z', '9876543210', l.Id));
        MarketingCloudWhatsAppWebhook.receiveEvent();
        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals(1, [SELECT COUNT() FROM WhatsApp_Message__c]);
    }

    @IsTest static void webhookStoresFailedProcessing() {
        RestContext.request = new RestRequest();
        RestContext.response = new RestResponse();
        // an over-long message id makes the save fail; the raw payload must still be kept
        RestContext.request.requestBody = Blob.valueOf(ev('m'.repeat(300), 'sent', '2026-10-14T10:00:00Z', '9876543210', ''));
        MarketingCloudWhatsAppWebhook.receiveEvent();
        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals(1, [SELECT COUNT() FROM WhatsApp_Message_Event__c WHERE Processing_Status__c = 'Error']);
    }

    @IsTest static void marketingCloudJourneyEventsGroupIntoOneMessage() {
        Lead l = mkLead();
        String base = '"mid":534006666,"eid":534006666,"activityId":"A1","journeyId":"J1","mobileNumber":"919876543210","senderId":"918488802115",'
            + '"activityName":"WhatsApp Day1","journeyName":"AGCP Journey 2027","contactKey":"' + l.Id + '","sendMethod":"JourneyBuilder"';
        WhatsAppEventService.process('[{"eventCategoryType":"EngagementEvents.OttRead","timestampUTC":1792044771000,' + base + '},'
            + '{"eventCategoryType":"EngagementEvents.OttSent","timestampUTC":1792044686000,' + base + '},'
            + '{"eventCategoryType":"EngagementEvents.OttDelivered","timestampUTC":1792044688000,' + base + '}]');
        WhatsApp_Message__c m = [SELECT Status__c, Template_Name__c, Journey_Name__c, Sender_Number__c, Lead__c, Sent_At__c, Read_At__c FROM WhatsApp_Message__c];
        System.assertEquals('Read', m.Status__c);
        System.assertEquals('WhatsApp Day1', m.Template_Name__c);
        System.assertEquals('AGCP Journey 2027', m.Journey_Name__c);
        System.assertEquals('918488802115', m.Sender_Number__c);
        System.assertEquals(l.Id, m.Lead__c);
        System.assert(m.Sent_At__c < m.Read_At__c);
        // a different contact in the same activity is a different message
        WhatsAppEventService.process('{"eventCategoryType":"EngagementEvents.OttFailed","reason":"131049 not delivered","timestampUTC":1792044771000,"activityId":"A1","journeyId":"J1","mobileNumber":"911111111111","contactKey":"00Qxx0000000000AAA"}');
        System.assertEquals(2, [SELECT COUNT() FROM WhatsApp_Message__c]);
        System.assertEquals(1, [SELECT COUNT() FROM WhatsApp_Message__c WHERE Status__c = 'Failed' AND Failure_Reason__c LIKE '131049%']);
    }

    @IsTest static void webhookAnswersVerification() {
        RestContext.request = new RestRequest();
        RestContext.response = new RestResponse();
        RestContext.request.requestBody = Blob.valueOf('{"callbackId":"cb1","verificationKey":"vk1"}');
        MarketingCloudWhatsAppWebhook.receiveEvent();
        System.assert(RestContext.response.responseBody.toString().contains('vk1'));
        System.assertEquals(0, [SELECT COUNT() FROM WhatsApp_Message_Event__c]);
    }

    @IsTest static void customerRepliesAreStoredAsInboundMessages() {
        Lead l = mkLead();
        String base = '"senderType":"WhatsApp","channelId":"9988776655","mobileNumber":"919876543210","contactId":"77601386",'
            + '"eventCategoryType":"EngagementEvents.OttMobileOriginated","eid":530000050,"mid":530000050,';
        WhatsAppEventService.process('[{' + base + '"messageType":"document","messageId":"wamid.D1","timestampUTC":1730196900000,'
            + '"messageBody":{"document":{"filename":"My_Brochure.pdf","mime_type":"application/pdf","id":"1089682512601880"}}},'
            + '{' + base + '"messageType":"image","messageId":"wamid.I1","timestampUTC":1730197082000,'
            + '"messageBody":{"image":{"caption":"CAPTION","id":"853002090326945","mime_type":"image/jpeg"}}},'
            + '{' + base + '"messageType":"audio","messageId":"wamid.A1","timestampUTC":1730196907000,'
            + '"messageBody":{"audio":{"id":"1234196991167350","mime_type":"audio/ogg; codecs=opus"}}},'
            + '{' + base + '"messageType":"text","messageId":"wamid.T1","timestampUTC":1730197100000,"messageBody":{"text":{"body":"Hello, fees?"}}}]');
        WhatsAppEventService.process('{' + base + '"messageType":"interactive","messageId":"wamid.B1","timestampUTC":1730197200000,'
            + '"messageBody":{"interactive":{"button_reply":{"id":"repeat-order","title":"Re-order an item"},"type":"button_reply"}}}');
        System.assertEquals(5, [SELECT COUNT() FROM WhatsApp_Message__c WHERE Direction__c = 'Inbound' AND Status__c = 'Received' AND Lead__c = :l.Id]);
        WhatsApp_Message__c d = [SELECT Attachment_Name__c, Media_Mime_Type__c, Media_Id__c, Sender_Number__c, Received_At__c, Message_Type__c FROM WhatsApp_Message__c WHERE Message_Key__c = 'wamid.D1'];
        System.assertEquals('My_Brochure.pdf', d.Attachment_Name__c);
        System.assertEquals('application/pdf', d.Media_Mime_Type__c);
        System.assertEquals('1089682512601880', d.Media_Id__c);
        System.assertEquals('9988776655', d.Sender_Number__c);
        System.assertEquals('document', d.Message_Type__c);
        System.assertNotEquals(null, d.Received_At__c);
        System.assertEquals('CAPTION', [SELECT Message_Text__c FROM WhatsApp_Message__c WHERE Message_Key__c = 'wamid.I1'].Message_Text__c);
        System.assertEquals('Hello, fees?', [SELECT Message_Text__c FROM WhatsApp_Message__c WHERE Message_Key__c = 'wamid.T1'].Message_Text__c);
        System.assertEquals('Re-order an item', [SELECT Message_Text__c FROM WhatsApp_Message__c WHERE Message_Key__c = 'wamid.B1'].Message_Text__c);
        Lead r = [SELECT WA_Received_Count__c, WA_Sent_Count__c FROM Lead WHERE Id = :l.Id];
        System.assertEquals(5, r.WA_Received_Count__c);
        System.assertEquals(0, r.WA_Sent_Count__c, 'replies are not counted as sent');
    }
}