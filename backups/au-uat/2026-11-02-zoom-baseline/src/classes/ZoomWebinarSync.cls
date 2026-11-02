/**
 * Pulls webinars, registrants and (after the webinar) participants from the Zoom API.
 * Safety net for missed webhooks and the way to import webinars that already exist in Zoom.
 *   System.enqueueJob(new ZoomWebinarSync());                 // import upcoming webinars + sync them
 *   System.enqueueJob(new ZoomWebinarSync(new List<String>{'123456789'}));
 * ZoomWebinarSyncScheduler.schedule() runs it every 2 hours.
 */
public without sharing class ZoomWebinarSync implements Queueable, Database.AllowsCallouts {
    private List<String> webinarIds;

    public ZoomWebinarSync() { }
    public ZoomWebinarSync(List<String> ids) { this.webinarIds = ids; }

    public void execute(QueueableContext qc) {
        if (webinarIds == null) {
            try { webinarIds = discover(); }
            catch (Exception e) { System.debug(LoggingLevel.ERROR, 'Zoom discover failed: ' + e.getMessage()); return; }
            if (webinarIds.isEmpty()) { return; }
        }
        String current = webinarIds.remove(0);
        try { syncOne(current); }
        catch (Exception e) { System.debug(LoggingLevel.ERROR, 'Zoom sync failed for ' + current + ': ' + e.getMessage()); }
        if (!webinarIds.isEmpty() && !Test.isRunningTest()) { System.enqueueJob(new ZoomWebinarSync(webinarIds)); }
    }

    /** Upcoming webinars from Zoom plus webinars in Salesforce from the last 3 days that may still need attendance. */
    private static List<String> discover() {
        Set<String> ids = new Set<String>();
        String user = ZoomConfig.get().Zoom_User_Id__c == null ? 'me' : ZoomConfig.get().Zoom_User_Id__c;
        for (Object o : ZoomApiService.getAll('/users/' + EncodingUtil.urlEncode(user, 'UTF-8') + '/webinars', 'type=scheduled', 'webinars')) {
            ids.add(String.valueOf(((Map<String, Object>) o).get('id')));
        }
        for (Zoom_Webinar__c w : [SELECT Webinar_Id__c FROM Zoom_Webinar__c
                                  WHERE Start_Time__c >= :Datetime.now().addDays(-3) AND Status__c != 'Deleted']) {
            ids.add(w.Webinar_Id__c);
        }
        return new List<String>(ids);
    }

    public static void syncOne(String webinarId) {
        Map<String, Object> wm = ZoomApiService.get('/webinars/' + webinarId);
        if (wm.isEmpty()) { return; }
        Zoom_Webinar__c w = ZoomEventService.webinarFromObject(wm);
        w.Last_Synced_At__c = Datetime.now();
        if (w.Start_Time__c != null && w.End_Time__c != null && w.End_Time__c < Datetime.now()) { w.Status__c = 'Ended'; }
        else if (w.Status__c == null) { w.Status__c = 'Scheduled'; }
        // all callouts first - Salesforce does not allow a callout after DML in the same transaction
        List<ZoomEventService.Person> regs = new List<ZoomEventService.Person>();
        for (String status : new List<String>{ 'approved', 'pending' }) {
            for (Object o : ZoomApiService.getAll('/webinars/' + webinarId + '/registrants', 'status=' + status, 'registrants')) {
                Map<String, Object> m = (Map<String, Object>) o;
                ZoomEventService.Person p = new ZoomEventService.Person();
                p.registrantId = ZoomEventService.str(m.get('id'));
                p.email = ZoomEventService.str(m.get('email'));
                p.firstName = ZoomEventService.str(m.get('first_name'));
                p.lastName = ZoomEventService.str(m.get('last_name'));
                p.phone = ZoomEventService.str(m.get('phone'));
                p.joinUrl = ZoomEventService.str(m.get('join_url'));
                p.status = status == 'pending' ? 'Pending' : 'Approved';
                p.registeredAt = ZoomEventService.parseDt(ZoomEventService.str(m.get('create_time')));
                regs.add(p);
            }
        }
        Map<String, ZoomEventService.Person> agg = new Map<String, ZoomEventService.Person>();
        if (w.Status__c == 'Ended') for (Object o : ZoomApiService.getAll('/past_webinars/' + webinarId + '/participants', null, 'participants')) {
            Map<String, Object> m = (Map<String, Object>) o;
            String email = ZoomEventService.str(m.get('user_email'));
            String k = email != null ? email.toLowerCase() : ZoomEventService.str(m.get('registrant_id')) + ZoomEventService.str(m.get('name'));
            ZoomEventService.Person p = agg.get(k);
            if (p == null) {
                p = new ZoomEventService.Person();
                p.email = email; p.registrantId = ZoomEventService.str(m.get('registrant_id'));
                p.participantName = ZoomEventService.str(m.get('name')); p.minutesInSession = 0;
                agg.put(k, p);
            }
            Datetime j = ZoomEventService.parseDt(ZoomEventService.str(m.get('join_time')));
            Datetime l = ZoomEventService.parseDt(ZoomEventService.str(m.get('leave_time')));
            if (p.joinedAt == null || (j != null && j < p.joinedAt)) { p.joinedAt = j; }
            if (p.leftAt == null || (l != null && l > p.leftAt)) { p.leftAt = l; }
            if (m.get('duration') != null) { p.minutesInSession += Integer.valueOf(Math.round(Decimal.valueOf(String.valueOf(m.get('duration'))) / 60)); }
        }
        upsert w Webinar_Id__c;
        if (!regs.isEmpty()) { ZoomEventService.applyPeople(w, regs, true); }
        if (!agg.isEmpty()) { ZoomEventService.applyPeople(w, agg.values(), false); }
    }
}