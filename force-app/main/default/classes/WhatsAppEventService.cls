/**
 * Turns Marketing Cloud WhatsApp status events (JSON) into WhatsApp_Message__c / WhatsApp_Message_Event__c
 * records and keeps the summary fields on Lead / Contact up to date.
 *
 * The payload shape is read tolerantly (field names are looked up from a list of known aliases), and
 * every event is stored with its raw JSON so it can be re-processed if the mapping changes.
 */
public without sharing class WhatsAppEventService {

    private static final Map<String, Integer> RANK = new Map<String, Integer>{
        'Sent' => 1, 'Delivered' => 2, 'Read' => 3
    };

    private static final List<String> KEY_MESSAGE = new List<String>{
        'messageid', 'message_id', 'wamid', 'messagekey', 'whatsappmessageid', 'messagetrackingid', 'externalmessageid' };
    private static final List<String> KEY_JOURNEY_ID = new List<String>{ 'journeyid', 'definitionid' };
    private static final List<String> KEY_ACTIVITY_ID = new List<String>{ 'activityid' };
    private static final List<String> KEY_SENDER = new List<String>{ 'senderid', 'channelid', 'from' };
    private static final List<String> KEY_EVENT_ID = new List<String>{ 'eventid', 'event_id', 'notificationid', 'transactionid' };
    private static final List<String> KEY_STATUS = new List<String>{
        'status', 'messagestatus', 'deliverystatus', 'eventtype', 'eventcategorytype', 'event', 'state' };
    private static final List<String> KEY_TIME = new List<String>{
        'timestamp', 'timestamputc', 'eventdate', 'eventtime', 'statustimestamp', 'time', 'createddate', 'date' };
    private static final List<String> KEY_PHONE = new List<String>{
        'mobilenumber', 'to', 'recipient', 'phonenumber', 'phone', 'msisdn', 'mobile', 'mobilenumber', 'contactnumber', 'wa_id', 'waid' };
    private static final List<String> KEY_SUBSCRIBER = new List<String>{ 'subscriberkey', 'contactkey', 'leadid', 'contactid', 'recordid' };
    private static final List<String> KEY_TEMPLATE = new List<String>{ 'templatename', 'template', 'messagetemplate', 'activityname' };
    private static final List<String> KEY_JOURNEY = new List<String>{ 'journeyname', 'definitionname' };
    private static final List<String> KEY_CAMPAIGN = new List<String>{ 'campaignname', 'campaign', 'messagename' };
    private static final List<String> KEY_TEXT = new List<String>{ 'messagetext', 'messagebody', 'body', 'text', 'message', 'content' };
    private static final List<String> KEY_REASON = new List<String>{
        'errormessage', 'errordescription', 'failurereason', 'reason', 'errortitle', 'error', 'errorcode', 'errors' };

    /** One parsed webhook event. */
    public class ParsedEvent implements System.Comparable {
        public String raw;
        public String eventKey;
        public String messageKey;
        public String status;       // Sent / Delivered / Read / Failed, or null when not recognised
        public String rawStatus;
        public Datetime eventTime;
        public String phone;
        public String subscriberKey;
        public String templateName;
        public String journeyName;
        public String campaignName;
        public String messageText;
        public String failureReason;
        public String journeyId;
        public String activityId;
        public String senderId;
        public String messageType;
        public String mediaId;
        public String mimeType;
        public String fileName;

        public Integer compareTo(Object o) {
            Datetime a = eventTime;
            Datetime b = ((ParsedEvent) o).eventTime;
            if (a == b) { return 0; }
            if (a == null) { return -1; }
            if (b == null) { return 1; }
            return a < b ? -1 : 1;
        }
    }

    /** Entry point called by the REST resource. Returns the number of events stored. */
    public static Integer process(String body) {
        List<ParsedEvent> events = parse(body);
        if (events.isEmpty()) {
            return 0;
        }
        save(events);
        return events.size();
    }

    // ---------------------------------------------------------------- parsing

    public static List<ParsedEvent> parse(String body) {
        List<ParsedEvent> result = new List<ParsedEvent>();
        if (String.isBlank(body)) {
            return result;
        }
        Object root;
        try {
            root = JSON.deserializeUntyped(body);
        } catch (Exception e) {
            ParsedEvent bad = new ParsedEvent();
            bad.raw = body;
            result.add(bad);
            return result;
        }
        for (Object item : explode(root)) {
            ParsedEvent pe = new ParsedEvent();
            pe.raw = JSON.serialize(item);
            if (item instanceof Map<String, Object>) {
                Map<String, String> flat = new Map<String, String>();
                flatten('', item, flat, 0);
                fill(pe, flat);
            }
            result.add(pe);
        }
        return result;
    }

    /** A top-level array, or an object wrapping an array of events, becomes one item per event. */
    private static List<Object> explode(Object root) {
        List<Object> items = new List<Object>();
        if (root instanceof List<Object>) {
            for (Object o : (List<Object>) root) {
                items.addAll(explode(o));
            }
            return items;
        }
        if (root instanceof Map<String, Object>) {
            Map<String, Object> m = (Map<String, Object>) root;
            for (String k : new List<String>{ 'events', 'entry', 'entries', 'statuses', 'messages', 'items', 'data' }) {
                if (m.get(k) instanceof List<Object>) {
                    List<Object> nested = (List<Object>) m.get(k);
                    if (!nested.isEmpty() && nested[0] instanceof Map<String, Object>) {
                        for (Object o : nested) {
                            items.addAll(explode(o));
                        }
                        return items;
                    }
                }
            }
        }
        items.add(root);
        return items;
    }

    /** Lower-cased leaf name -> value; the shallowest occurrence wins. Dotted paths are also kept. */
    private static void flatten(String path, Object node, Map<String, String> out, Integer depth) {
        if (depth > 6) {
            return;
        }
        if (node instanceof Map<String, Object>) {
            for (String k : ((Map<String, Object>) node).keySet()) {
                Object v = ((Map<String, Object>) node).get(k);
                String lk = k.toLowerCase();
                if (v instanceof Map<String, Object> || v instanceof List<Object>) {
                    flatten(path + lk + '.', v, out, depth + 1);
                } else if (v != null) {
                    String sv = String.valueOf(v);
                    if (!out.containsKey(path + lk)) {
                        out.put(path + lk, sv);
                    }
                    if (!out.containsKey(lk)) {
                        out.put(lk, sv);
                    }
                }
            }
        } else if (node instanceof List<Object>) {
            List<Object> l = (List<Object>) node;
            if (!l.isEmpty()) {
                flatten(path, l[0], out, depth + 1);
            }
        }
    }

    private static String pick(Map<String, String> flat, List<String> keys) {
        for (String k : keys) {
            String v = flat.get(k);
            if (String.isNotBlank(v)) {
                return v;
            }
        }
        return null;
    }

    private static void fill(ParsedEvent pe, Map<String, String> flat) {
        pe.messageKey = pick(flat, KEY_MESSAGE);
        pe.rawStatus = pick(flat, KEY_STATUS);
        pe.status = normaliseStatus(pe.rawStatus);
        pe.eventTime = parseTime(pick(flat, KEY_TIME));
        pe.phone = pick(flat, KEY_PHONE);
        pe.subscriberKey = pick(flat, KEY_SUBSCRIBER);
        pe.templateName = pick(flat, KEY_TEMPLATE);
        pe.journeyName = pick(flat, KEY_JOURNEY);
        pe.campaignName = pick(flat, KEY_CAMPAIGN);
        pe.messageText = pick(flat, KEY_TEXT);
        pe.failureReason = pick(flat, KEY_REASON);
        pe.journeyId = pick(flat, KEY_JOURNEY_ID);
        pe.activityId = pick(flat, KEY_ACTIVITY_ID);
        pe.senderId = pick(flat, KEY_SENDER);
        pe.messageType = pick(flat, new List<String>{ 'messagetype' });
        if (pe.status == 'Received') {
            fillInbound(pe, flat);
        }
        // Marketing Cloud journey events carry no message id: one journey activity sent to one contact is one message.
        if (pe.messageKey == null && pe.journeyId != null && pe.activityId != null) {
            String who = pe.subscriberKey != null ? pe.subscriberKey : pe.phone;
            if (who != null) {
                pe.messageKey = (pe.journeyId + '|' + pe.activityId + '|' + who).left(255);
            }
        }
        String id = pick(flat, KEY_EVENT_ID);
        pe.eventKey = String.isNotBlank(id) ? id : null;
    }

    /** Customer reply (EngagementEvents.OttMobileOriginated): text, image, video, audio, document ... */
    private static void fillInbound(ParsedEvent pe, Map<String, String> flat) {
        pe.mediaId = pick(flat, new List<String>{ 'messagebody.' + pe.messageType + '.id', 'messagebody.id' });
        pe.mimeType = pick(flat, new List<String>{ 'messagebody.' + pe.messageType + '.mime_type', 'messagebody.mime_type' });
        pe.fileName = pick(flat, new List<String>{ 'messagebody.' + pe.messageType + '.filename', 'messagebody.filename' });
        pe.messageText = pick(flat, new List<String>{
            'messagebody.text.body', 'messagebody.' + pe.messageType + '.caption', 'messagebody.text', 'messagebody.body',
            'messagebody.button.text', 'messagebody.interactive.button_reply.title', 'messagebody.interactive.list_reply.title', 'messagebody' });
    }

    public static String normaliseStatus(String s) {
        if (String.isBlank(s)) {
            return null;
        }
        String v = s.toLowerCase();
        if (v.contains('mobileoriginated') || v.contains('inbound')) {
            return 'Received';
        }
        if (v.contains('fail') || v.contains('undeliver') || v.contains('error') || v.contains('reject') || v.contains('expired')) {
            return 'Failed';
        }
        if (v.contains('read') || v.contains('seen') || v.contains('open')) {
            return 'Read';
        }
        if (v.contains('deliver')) {
            return 'Delivered';
        }
        if (v.contains('sent') || v.contains('submit') || v.contains('accept') || v.contains('queue') || v.contains('send')) {
            return 'Sent';
        }
        return null;
    }

    public static Datetime parseTime(String s) {
        if (String.isBlank(s)) {
            return null;
        }
        try {
            if (s.isNumeric() || (s.contains('.') && s.replace('.', '').isNumeric())) {
                Decimal d = Decimal.valueOf(s);
                Long ms = (d > 99999999999L) ? d.longValue() : (d * 1000).longValue();
                return Datetime.newInstance(ms);
            }
            String iso = s.trim().replace(' ', 'T');
            if (iso.endsWith('Z') || iso.contains('+') || iso.lastIndexOf('-') > 9) {
                return (Datetime) JSON.deserialize('"' + iso + '"', Datetime.class);
            }
            return (Datetime) JSON.deserialize('"' + iso + 'Z"', Datetime.class);
        } catch (Exception e) {
            return null;
        }
    }

    // ---------------------------------------------------------------- saving

    private static void save(List<ParsedEvent> events) {
        // Resolve event keys and skip events that were already stored.
        for (ParsedEvent pe : events) {
            if (pe.eventKey == null) {
                pe.eventKey = EncodingUtil.convertToHex(Crypto.generateDigest('SHA1', Blob.valueOf(pe.raw)));
            }
        }
        Set<String> keys = new Set<String>();
        for (ParsedEvent pe : events) {
            keys.add(pe.eventKey);
        }
        Set<String> existing = new Set<String>();
        for (WhatsApp_Message_Event__c e : [SELECT Event_Key__c FROM WhatsApp_Message_Event__c WHERE Event_Key__c IN :keys]) {
            existing.add(e.Event_Key__c);
        }

        List<ParsedEvent> fresh = new List<ParsedEvent>();
        Set<String> seen = new Set<String>();
        for (ParsedEvent pe : events) {
            if (!existing.contains(pe.eventKey) && seen.add(pe.eventKey)) {
                fresh.add(pe);
            }
        }
        if (fresh.isEmpty()) {
            return;
        }

        // Existing messages for these events.
        Set<String> msgKeys = new Set<String>();
        for (ParsedEvent pe : fresh) {
            if (pe.messageKey != null) {
                msgKeys.add(pe.messageKey);
            }
        }
        Map<String, WhatsApp_Message__c> messages = new Map<String, WhatsApp_Message__c>();
        for (WhatsApp_Message__c m : [
            SELECT Id, Message_Key__c, Status__c, Lead__c, Contact__c, Phone__c, Template_Name__c, Journey_Name__c,
                   Campaign_Name__c, Message_Text__c, Journey_Id__c, Activity_Id__c, Sender_Number__c, Phone_Key__c, Direction__c, Message_Type__c, Media_Id__c, Media_Mime_Type__c, Attachment_Name__c, Received_At__c, Sent_At__c, Delivered_At__c, Read_At__c, Failed_At__c, Last_Event_At__c,
                   Failure_Reason__c, Is_Matched__c
            FROM WhatsApp_Message__c WHERE Message_Key__c IN :msgKeys
        ]) {
            messages.put(m.Message_Key__c, m);
        }

        // Match students for messages that are new or still unmatched.
        List<ParsedEvent> toMatch = new List<ParsedEvent>();
        for (ParsedEvent pe : fresh) {
            WhatsApp_Message__c m = pe.messageKey == null ? null : messages.get(pe.messageKey);
            if (m == null || !m.Is_Matched__c) {
                toMatch.add(pe);
            }
        }
        Map<ParsedEvent, Id> matched = matchStudents(toMatch);

        // Apply events (in event-time order) to the messages.
        fresh.sort();
        Map<String, WhatsApp_Message__c> toUpsert = new Map<String, WhatsApp_Message__c>();
        Map<ParsedEvent, String> eventMessage = new Map<ParsedEvent, String>();
        for (ParsedEvent pe : fresh) {
            if (pe.messageKey == null || pe.status == null) {
                continue;
            }
            WhatsApp_Message__c m = toUpsert.get(pe.messageKey);
            if (m == null) {
                m = messages.get(pe.messageKey);
            }
            if (m == null) {
                m = new WhatsApp_Message__c(Message_Key__c = pe.messageKey, Is_Matched__c = false);
            }
            apply(m, pe, matched.get(pe));
            toUpsert.put(pe.messageKey, m);
            eventMessage.put(pe, pe.messageKey);
        }
        if (!toUpsert.isEmpty()) {
            upsert toUpsert.values() Message_Key__c;
        }

        List<WhatsApp_Message_Event__c> rows = new List<WhatsApp_Message_Event__c>();
        for (ParsedEvent pe : fresh) {
            WhatsApp_Message_Event__c ev = new WhatsApp_Message_Event__c(
                Event_Key__c = pe.eventKey,
                Event_Type__c = pe.rawStatus == null ? null : pe.rawStatus.left(255),
                Event_Time__c = pe.eventTime,
                Raw_Payload__c = pe.raw.left(131072)
            );
            String mk = eventMessage.get(pe);
            if (mk != null) {
                ev.Message__c = toUpsert.get(mk).Id;
                ev.Processing_Status__c = toUpsert.get(mk).Is_Matched__c ? 'Processed' : 'Unmatched';
            } else {
                ev.Processing_Status__c = 'Ignored';
                ev.Error__c = pe.messageKey == null ? 'No message id found in payload' : 'Status not recognised: ' + pe.rawStatus;
            }
            rows.add(ev);
        }
        insert rows;

        refreshSummaries(toUpsert.values());
    }

    private static void apply(WhatsApp_Message__c m, ParsedEvent pe, Id studentId) {
        Datetime t = pe.eventTime != null ? pe.eventTime : Datetime.now();
        if (studentId != null && (m.Lead__c == null && m.Contact__c == null)) {
            if (studentId.getSObjectType() == Lead.SObjectType) {
                m.Lead__c = studentId;
            } else {
                m.Contact__c = studentId;
            }
            m.Is_Matched__c = true;
        }
        if (m.Phone__c == null && pe.phone != null) {
            m.Phone__c = pe.phone.left(40);
        }
        if (m.Phone_Key__c == null && last10(pe.phone) != null) {
            m.Phone_Key__c = last10(pe.phone);
        }
        if (m.Journey_Id__c == null) { m.Journey_Id__c = trim(pe.journeyId, 80); }
        if (m.Activity_Id__c == null) { m.Activity_Id__c = trim(pe.activityId, 80); }
        if (m.Sender_Number__c == null) { m.Sender_Number__c = trim(pe.senderId, 40); }
        if (m.Template_Name__c == null) { m.Template_Name__c = trim(pe.templateName, 255); }
        if (m.Journey_Name__c == null) { m.Journey_Name__c = trim(pe.journeyName, 255); }
        if (m.Campaign_Name__c == null) { m.Campaign_Name__c = trim(pe.campaignName, 255); }
        if (m.Message_Text__c == null) { m.Message_Text__c = trim(pe.messageText, 32768); }

        if (pe.status == 'Received') {
            m.Direction__c = 'Inbound';
            m.Received_At__c = earliest(m.Received_At__c, t);
            m.Status__c = 'Received';
            if (m.Message_Type__c == null) { m.Message_Type__c = trim(pe.messageType, 30); }
            if (m.Media_Id__c == null) { m.Media_Id__c = trim(pe.mediaId, 100); }
            if (m.Media_Mime_Type__c == null) { m.Media_Mime_Type__c = trim(pe.mimeType, 100); }
            if (m.Attachment_Name__c == null) { m.Attachment_Name__c = trim(pe.fileName, 255); }
            if (m.Last_Event_At__c == null || t > m.Last_Event_At__c) { m.Last_Event_At__c = t; }
            return;
        }
        if (pe.status == 'Sent') {
            m.Sent_At__c = earliest(m.Sent_At__c, t);
        } else if (pe.status == 'Delivered') {
            m.Delivered_At__c = earliest(m.Delivered_At__c, t);
        } else if (pe.status == 'Read') {
            m.Read_At__c = earliest(m.Read_At__c, t);
        } else if (pe.status == 'Failed') {
            m.Failed_At__c = earliest(m.Failed_At__c, t);
            m.Failure_Reason__c = trim(pe.failureReason, 255);
        }
        if (m.Last_Event_At__c == null || t > m.Last_Event_At__c) {
            m.Last_Event_At__c = t;
        }

        // Status only moves forward: Sent < Delivered < Read. Failed only replaces a message that never got delivered.
        Integer cur = RANK.containsKey(m.Status__c) ? RANK.get(m.Status__c) : 0;
        if (pe.status == 'Failed') {
            if (cur < 2) {
                m.Status__c = 'Failed';
            }
        } else if (RANK.get(pe.status) > cur || m.Status__c == 'Failed') {
            m.Status__c = pe.status;
        }
    }

    private static Datetime earliest(Datetime a, Datetime b) {
        return (a == null || b < a) ? b : a;
    }

    private static String trim(String s, Integer max) {
        return s == null ? null : s.left(max);
    }

    // ---------------------------------------------------------------- student matching

    private static Map<ParsedEvent, Id> matchStudents(List<ParsedEvent> events) {
        Map<ParsedEvent, Id> result = new Map<ParsedEvent, Id>();
        Set<Id> leadIds = new Set<Id>();
        Set<Id> contactIds = new Set<Id>();
        Set<String> last10 = new Set<String>();
        for (ParsedEvent pe : events) {
            Id sid = asId(pe.subscriberKey);
            if (sid != null) {
                if (sid.getSObjectType() == Lead.SObjectType) { leadIds.add(sid); }
                else if (sid.getSObjectType() == Contact.SObjectType) { contactIds.add(sid); }
            }
            String p = last10(pe.phone);
            if (p != null) { last10.add(p); }
        }
        Set<Id> validLeads = new Map<Id, Lead>([SELECT Id FROM Lead WHERE Id IN :leadIds]).keySet();
        Set<Id> validContacts = new Map<Id, Contact>([SELECT Id FROM Contact WHERE Id IN :contactIds]).keySet();

        Map<String, Id> byPhone = new Map<String, Id>();
        if (!last10.isEmpty()) {
            // last10 values contain digits only (see last10()), so they are safe to inline in the LIKE clauses.
            List<Decimal> numbers = new List<Decimal>();
            List<String> leadConds = new List<String>{ 'MC_Phone_Number__c IN :numbers' };
            List<String> contactConds = new List<String>();
            for (String p : last10) {
                numbers.add(Decimal.valueOf(p));
                numbers.add(Decimal.valueOf('91' + p));
                for (String f : new List<String>{ 'MobilePhone', 'Phone', 'Whatsapp_Number__c' }) {
                    leadConds.add(f + ' LIKE \'%' + p + '\'');
                    if (f != 'Whatsapp_Number__c') { contactConds.add(f + ' LIKE \'%' + p + '\''); }
                }
            }
            String leadSoql = 'SELECT Id, Phone, MobilePhone, MC_Phone_Number__c, Whatsapp_Number__c FROM Lead WHERE IsConverted = false AND ('
                + String.join(leadConds, ' OR ') + ') ORDER BY CreatedDate DESC LIMIT 2000';
            String contactSoql = 'SELECT Id, Phone, MobilePhone FROM Contact WHERE (' + String.join(contactConds, ' OR ')
                + ') ORDER BY CreatedDate DESC LIMIT 2000';
            for (Lead l : (List<Lead>) Database.query(leadSoql)) {
                                String mc = l.MC_Phone_Number__c == null ? null : l.MC_Phone_Number__c.toPlainString();
                for (String n : new List<String>{ l.Whatsapp_Number__c, l.MobilePhone, mc, l.Phone }) {
                    String k = last10(n);
                    if (k != null && last10.contains(k) && !byPhone.containsKey(k)) { byPhone.put(k, l.Id); }
                }
            }
            for (Contact c : (List<Contact>) Database.query(contactSoql)) {
                for (String n : new List<String>{ c.MobilePhone, c.Phone }) {
                    String k = last10(n);
                    if (k != null && last10.contains(k) && !byPhone.containsKey(k)) { byPhone.put(k, c.Id); }
                }
            }
        }
        for (ParsedEvent pe : events) {
            Id sid = asId(pe.subscriberKey);
            if (sid != null && (validLeads.contains(sid) || validContacts.contains(sid))) {
                result.put(pe, sid);
            } else {
                String p = last10(pe.phone);
                if (p != null && byPhone.containsKey(p)) { result.put(pe, byPhone.get(p)); }
            }
        }
        return result;
    }

    private static Id asId(String s) {
        if (s == null || (s.length() != 15 && s.length() != 18)) { return null; }
        try { return Id.valueOf(s); } catch (Exception e) { return null; }
    }

    public static String last10(String phone) {
        if (phone == null) { return null; }
        String d = phone.replaceAll('[^0-9]', '');
        if (d.length() < 7) { return null; }
        return d.length() > 10 ? d.right(10) : d;
    }

    // ---------------------------------------------------------------- summaries on Lead / Contact

    private static void refreshSummaries(List<WhatsApp_Message__c> messages) {
        Set<Id> leadIds = new Set<Id>();
        Set<Id> contactIds = new Set<Id>();
        for (WhatsApp_Message__c m : messages) {
            if (m.Lead__c != null) { leadIds.add(m.Lead__c); }
            if (m.Contact__c != null) { contactIds.add(m.Contact__c); }
        }
        if (!leadIds.isEmpty()) {
            Map<Id, Lead> upd = new Map<Id, Lead>();
            for (Id i : leadIds) { upd.put(i, new Lead(Id = i, WA_Sent_Count__c = 0, WA_Delivered_Count__c = 0, WA_Read_Count__c = 0, WA_Failed_Count__c = 0, WA_Received_Count__c = 0)); }
            for (WhatsApp_Message__c m : [
                SELECT Lead__c, Status__c, Direction__c, Last_Event_At__c FROM WhatsApp_Message__c WHERE Lead__c IN :leadIds ORDER BY Last_Event_At__c ASC NULLS FIRST
            ]) {
                Lead l = upd.get(m.Lead__c);
                if (m.Direction__c == 'Inbound') { l.WA_Received_Count__c += 1; continue; }
                l.WA_Last_Status__c = m.Status__c;
                l.WA_Last_Message_At__c = m.Last_Event_At__c;
                l.WA_Sent_Count__c += 1;
                if (m.Status__c == 'Delivered' || m.Status__c == 'Read') { l.WA_Delivered_Count__c += 1; }
                if (m.Status__c == 'Read') { l.WA_Read_Count__c += 1; }
                if (m.Status__c == 'Failed') { l.WA_Failed_Count__c += 1; }
            }
            Database.update(upd.values(), false);
        }
        if (!contactIds.isEmpty()) {
            Map<Id, Contact> upd = new Map<Id, Contact>();
            for (Id i : contactIds) { upd.put(i, new Contact(Id = i, WA_Sent_Count__c = 0, WA_Delivered_Count__c = 0, WA_Read_Count__c = 0, WA_Failed_Count__c = 0, WA_Received_Count__c = 0)); }
            for (WhatsApp_Message__c m : [
                SELECT Contact__c, Status__c, Direction__c, Last_Event_At__c FROM WhatsApp_Message__c WHERE Contact__c IN :contactIds ORDER BY Last_Event_At__c ASC NULLS FIRST
            ]) {
                Contact c = upd.get(m.Contact__c);
                if (m.Direction__c == 'Inbound') { c.WA_Received_Count__c += 1; continue; }
                c.WA_Last_Status__c = m.Status__c;
                c.WA_Last_Message_At__c = m.Last_Event_At__c;
                c.WA_Sent_Count__c += 1;
                if (m.Status__c == 'Delivered' || m.Status__c == 'Read') { c.WA_Delivered_Count__c += 1; }
                if (m.Status__c == 'Read') { c.WA_Read_Count__c += 1; }
                if (m.Status__c == 'Failed') { c.WA_Failed_Count__c += 1; }
            }
            Database.update(upd.values(), false);
        }
    }
}