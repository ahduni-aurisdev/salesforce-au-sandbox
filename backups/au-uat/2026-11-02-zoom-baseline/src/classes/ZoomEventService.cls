/**
 * Applies Zoom webinar events (webhook payloads or API data) to Zoom_Webinar__c / Zoom_Registration__c,
 * matches the person to a Lead or Contact by email and logs a completed Task on that record
 * ("Zoom Webinar Registered" / "Zoom Webinar Attended").
 */
public without sharing class ZoomEventService {

    public class Person {
        public String email, firstName, lastName, phone, registrantId, joinUrl, status, answers;
        public Datetime registeredAt, joinedAt, leftAt;
        public Integer minutesInSession;
        public String participantName;
    }

    /** Entry point for a webhook body. */
    public static void process(String body) {
        Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(body);
        String event = (String) root.get('event');
        Map<String, Object> payload = (Map<String, Object>) root.get('payload');
        if (event == null || payload == null) { return; }
        Map<String, Object> obj = (Map<String, Object>) payload.get('object');
        if (obj == null) { return; }

        Zoom_Webinar__c w = webinarFromObject(obj);
        if (event == 'webinar.started') { w.Status__c = 'Started'; }
        else if (event == 'webinar.ended') { w.Status__c = 'Ended'; }
        else if (event == 'webinar.deleted') { w.Status__c = 'Deleted'; }
        upsert w Webinar_Id__c;

        if (event.startsWith('webinar.registration_')) {
            Map<String, Object> reg = (Map<String, Object>) obj.get('registrant');
            if (reg == null) { return; }
            Person p = new Person();
            p.registrantId = str(reg.get('id'));
            p.email = str(reg.get('email'));
            p.firstName = str(reg.get('first_name'));
            p.lastName = str(reg.get('last_name'));
            p.phone = str(reg.get('phone'));
            p.joinUrl = str(reg.get('join_url'));
            p.answers = answersOf(reg);
            p.registeredAt = root.get('event_ts') == null ? Datetime.now()
                : Datetime.newInstance(Long.valueOf(String.valueOf(root.get('event_ts'))));
            String s = str(reg.get('status'));
            if (event == 'webinar.registration_cancelled') { p.status = 'Cancelled'; }
            else if (event == 'webinar.registration_denied') { p.status = 'Denied'; }
            else if (event == 'webinar.registration_approved') { p.status = 'Approved'; }
            else { p.status = (s == 'pending') ? 'Pending' : 'Approved'; }
            applyPeople(w, new List<Person>{ p }, true);
        } else if (event == 'webinar.participant_joined' || event == 'webinar.participant_left') {
            Map<String, Object> part = (Map<String, Object>) obj.get('participant');
            if (part == null) { return; }
            Person p = new Person();
            p.registrantId = str(part.get('registrant_id'));
            p.email = str(part.get('email'));
            p.participantName = str(part.get('user_name'));
            p.joinedAt = parseDt(str(part.get('join_time')));
            p.leftAt = parseDt(str(part.get('leave_time')));
            if (event == 'webinar.participant_joined') {
                applyPeople(w, new List<Person>{ p }, false);
            } else {
                applyLeft(w, p);
            }
        }
    }

    /** Builds the webinar record from a webhook "object" or an API webinar map. */
    public static Zoom_Webinar__c webinarFromObject(Map<String, Object> o) {
        Zoom_Webinar__c w = new Zoom_Webinar__c(Webinar_Id__c = str(o.get('id')));
        if (str(o.get('topic')) != null) { w.Name = str(o.get('topic')).left(80); }
        else { w.Name = 'Zoom Webinar ' + w.Webinar_Id__c; }
        Datetime st = parseDt(str(o.get('start_time')));
        if (st != null) { w.Start_Time__c = st; }
        if (o.get('duration') != null) {
            w.Duration_Minutes__c = Decimal.valueOf(String.valueOf(o.get('duration')));
            if (st != null) { w.End_Time__c = st.addMinutes(Integer.valueOf(w.Duration_Minutes__c)); }
        }
        if (str(o.get('timezone')) != null) { w.Timezone__c = str(o.get('timezone')); }
        if (str(o.get('join_url')) != null) { w.Join_URL__c = str(o.get('join_url')); }
        if (str(o.get('registration_url')) != null) { w.Registration_URL__c = str(o.get('registration_url')); }
        return w;
    }

    /** Registers / marks attendance for a batch of people on one webinar. */
    public static void applyPeople(Zoom_Webinar__c w, List<Person> people, Boolean fromRegistration) {
        Id webinarId = [SELECT Id FROM Zoom_Webinar__c WHERE Webinar_Id__c = :w.Webinar_Id__c LIMIT 1].Id;
        Map<String, Zoom_Registration__c> byKey = new Map<String, Zoom_Registration__c>();
        List<String> keys = new List<String>();
        for (Person p : people) { keys.add(keyOf(w.Webinar_Id__c, p)); }
        for (Zoom_Registration__c r : [SELECT Id, Registration_Key__c, Is_Registered__c, Attended__c, First_Joined_At__c,
                Last_Joined_At__c, Time_In_Session_Minutes__c, Registration_Task_Id__c, Attendance_Task_Id__c, Lead__c, Contact__c,
                Status__c, Registered_At__c, Last_Left_At__c FROM Zoom_Registration__c WHERE Registration_Key__c IN :keys]) {
            byKey.put(r.Registration_Key__c, r);
        }
        Map<String, SObject> people2match = matchByEmail(people);

        List<Zoom_Registration__c> toSave = new List<Zoom_Registration__c>();
        List<Person> ordered = new List<Person>();
        for (Person p : people) {
            String key = keyOf(w.Webinar_Id__c, p);
            Zoom_Registration__c r = byKey.get(key);
            if (r == null) {
                r = new Zoom_Registration__c(Registration_Key__c = key, Webinar__c = webinarId, Is_Registered__c = false);
                byKey.put(key, r);
            }
            if (p.email != null) { r.Email__c = p.email; }
            if (p.firstName != null) { r.First_Name__c = p.firstName; }
            if (p.lastName != null) { r.Last_Name__c = p.lastName; }
            if (p.phone != null) { r.Phone__c = p.phone; }
            if (p.joinUrl != null) { r.Join_URL__c = p.joinUrl; }
            if (p.answers != null) { r.Form_Answers__c = p.answers; }
            if (p.registrantId != null) { r.Registrant_Id__c = p.registrantId; }
            if (fromRegistration) {
                r.Status__c = p.status;
                r.Is_Registered__c = (p.status == 'Approved' || p.status == 'Pending');
                if (r.Registered_At__c == null) { r.Registered_At__c = p.registeredAt; }
            } else {
                if (p.registrantId != null && r.Is_Registered__c != true && r.Id == null) { r.Is_Registered__c = true; if (r.Status__c == null) { r.Status__c = 'Approved'; } }
                if (r.Status__c == null) { r.Status__c = 'Not Registered'; }
                r.Attended__c = true;
                if (p.joinedAt != null) {
                    if (r.First_Joined_At__c == null || p.joinedAt < r.First_Joined_At__c) { r.First_Joined_At__c = p.joinedAt; }
                    if (r.Last_Joined_At__c == null || p.joinedAt > r.Last_Joined_At__c) { r.Last_Joined_At__c = p.joinedAt; }
                }
                if (p.minutesInSession != null) { r.Time_In_Session_Minutes__c = p.minutesInSession; }
                if (p.leftAt != null) { r.Last_Left_At__c = p.leftAt; }
            }
            SObject m = p.email == null ? null : people2match.get(p.email.toLowerCase());
            if (m != null) {
                r.Is_Matched__c = true;
                if (m instanceof Lead) { r.Lead__c = m.Id; } else { r.Contact__c = m.Id; }
            }
            toSave.add(r);
            ordered.add(p);
        }
        // dedupe same key in one batch
        Map<String, Zoom_Registration__c> unique = new Map<String, Zoom_Registration__c>();
        for (Zoom_Registration__c r : toSave) { unique.put(r.Registration_Key__c, r); }
        upsert unique.values() Registration_Key__c;
        createActivities(w, unique.values());
        update unique.values();
    }

    private static void applyLeft(Zoom_Webinar__c w, Person p) {
        String key = keyOf(w.Webinar_Id__c, p);
        List<Zoom_Registration__c> rs = [SELECT Id, Last_Joined_At__c, Last_Left_At__c, Time_In_Session_Minutes__c
                                         FROM Zoom_Registration__c WHERE Registration_Key__c = :key LIMIT 1];
        if (rs.isEmpty()) { return; }
        Zoom_Registration__c r = rs[0];
        if (p.leftAt == null || (r.Last_Left_At__c != null && p.leftAt <= r.Last_Left_At__c)) { return; }
        if (r.Last_Joined_At__c != null && p.leftAt > r.Last_Joined_At__c) {
            Long mins = (p.leftAt.getTime() - r.Last_Joined_At__c.getTime()) / 60000;
            r.Time_In_Session_Minutes__c = (r.Time_In_Session_Minutes__c == null ? 0 : r.Time_In_Session_Minutes__c) + mins;
        }
        r.Last_Left_At__c = p.leftAt;
        update r;
    }

    private static void createActivities(Zoom_Webinar__c w, List<Zoom_Registration__c> regs) {
        Zoom_Config__mdt cfg = ZoomConfig.get();
        if (cfg.Create_Activities__c == false) { return; }
        List<Task> tasks = new List<Task>();
        List<Zoom_Registration__c> reg4task = new List<Zoom_Registration__c>();
        List<Boolean> isAttend = new List<Boolean>();
        String topic = w.Name == null ? w.Webinar_Id__c : w.Name;
        for (Zoom_Registration__c r : regs) {
            Id who = r.Lead__c != null ? r.Lead__c : r.Contact__c;
            if (who == null) { continue; }
            if (r.Is_Registered__c == true && r.Registration_Task_Id__c == null) {
                tasks.add(newTask(who, 'Zoom Webinar Registered: ' + topic, 'Registered for Zoom webinar "' + topic + '"'
                    + (w.Start_Time__c == null ? '' : ' scheduled on ' + w.Start_Time__c.format('dd MMM yyyy hh:mm a')) + '.'));
                reg4task.add(r); isAttend.add(false);
            }
            if (r.Attended__c == true && r.Attendance_Task_Id__c == null) {
                tasks.add(newTask(who, 'Zoom Webinar Attended: ' + topic, 'Joined Zoom webinar "' + topic + '"'
                    + (r.First_Joined_At__c == null ? '' : ' at ' + r.First_Joined_At__c.format('dd MMM yyyy hh:mm a')) + '.'));
                reg4task.add(r); isAttend.add(true);
            }
        }
        if (tasks.isEmpty()) { return; }
        insert tasks;
        for (Integer i = 0; i < tasks.size(); i++) {
            if (isAttend[i]) { reg4task[i].Attendance_Task_Id__c = tasks[i].Id; }
            else { reg4task[i].Registration_Task_Id__c = tasks[i].Id; }
        }
    }

    private static Task newTask(Id who, String subject, String body) {
        return new Task(WhoId = who, Subject = subject.left(255), Description = body, Status = 'Completed',
                        Priority = 'Normal', ActivityDate = Date.today());
    }

    private static Map<String, SObject> matchByEmail(List<Person> people) {
        Set<String> emails = new Set<String>();
        for (Person p : people) { if (p.email != null) { emails.add(p.email.toLowerCase()); } }
        Map<String, SObject> res = new Map<String, SObject>();
        if (emails.isEmpty()) { return res; }
        for (Contact c : [SELECT Id, Email FROM Contact WHERE Email IN :emails ORDER BY CreatedDate ASC]) {
            res.put(c.Email.toLowerCase(), c);
        }
        // unconverted Leads win over Contacts
        for (Lead l : [SELECT Id, Email FROM Lead WHERE Email IN :emails AND IsConverted = false ORDER BY CreatedDate ASC]) {
            res.put(l.Email.toLowerCase(), l);
        }
        return res;
    }

    private static String keyOf(String webinarId, Person p) {
        String who = p.email != null ? p.email.toLowerCase()
            : (p.registrantId != null ? p.registrantId : (p.participantName == null ? 'unknown' : p.participantName.toLowerCase()));
        return (webinarId + '|' + who).left(255);
    }

    private static String answersOf(Map<String, Object> reg) {
        List<String> lines = new List<String>();
        for (String k : new List<String>{ 'address', 'city', 'state', 'zip', 'country', 'org', 'job_title', 'industry', 'comments' }) {
            if (str(reg.get(k)) != null) { lines.add(k + ': ' + str(reg.get(k))); }
        }
        Object cq = reg.get('custom_questions');
        if (cq instanceof List<Object>) {
            for (Object o : (List<Object>) cq) {
                Map<String, Object> m = (Map<String, Object>) o;
                lines.add(str(m.get('title')) + ': ' + str(m.get('value')));
            }
        }
        return lines.isEmpty() ? null : String.join(lines, '\n').left(32768);
    }

    public static String str(Object o) { return o == null || String.valueOf(o) == '' ? null : String.valueOf(o); }

    public static Datetime parseDt(String s) {
        if (s == null) { return null; }
        try { return (Datetime) JSON.deserialize('"' + s + '"', Datetime.class); } catch (Exception e) { return null; }
    }
}