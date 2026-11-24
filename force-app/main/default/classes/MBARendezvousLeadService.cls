/**
 * @description Creates or updates Masters Leads pushed by the MBA Rendezvous lead portal.
 *              Called only by MBARendezvousLeadWebhook (OAuth-authenticated Apex REST endpoint).
 *
 *              Field mapping comes from WebFormFieldMapping__mdt (TypeOfForm__c = MBA_Rendezvous,
 *              Department__c = Masters), the same configuration the website and other partners use.
 *              The Lead Source value is that mapping's LeadSourceGroup__c ("MBA Rendezvous").
 *
 *              Programme is optional. When it is not sent, a new Lead gets DEFAULT_PROGRAMME (MBA, since
 *              MBA Rendezvous is an MBA portal) so the course-based Masters round robin assigns it, and an
 *              existing Lead keeps its own programme.
 *
 *              Duplicate rule (based on the Masters rule in saveWebsiteLead.handleDuplicateLeadDefault):
 *              an existing Masters Lead with the same email and admission year whose phone contains the
 *              incoming number, and - only when a programme was sent - the same programme, is the same
 *              person.
 *                - Existing Lead has a Registration Number (application in progress): its data is kept;
 *                  only "MBA Rendezvous" is added to Multi_Select_Lead_Source__c and
 *                  Most_Recent_Lead_Source__c.
 *                - Otherwise: the mapped fields and Lead Source are overwritten with the new submission
 *                  and "MBA Rendezvous" is added to Multi_Select_Lead_Source__c.
 *              Owner assignment is left to the existing Lead trigger (Masters round robin).
 *
 *              Governor usage per call (up to 50 leads): 2 SOQL on custom metadata, 1 SOQL on Lead,
 *              1 DML (upsert). CPU is linear in the number of leads.
 *
 * @author Jitendra V
 * @date 2026-11-16
 * @version 1.0
 * @lastModified 2026-11-16
 */
// without sharing (system mode) is intentional and required: the caller is the MBA Rendezvous
// integration user, which by design has access only to MBARendezvousLeadWebhook - not to Lead
// records - so its token cannot read or change Leads through the standard APIs. The duplicate check
// must still see every Masters Lead and update the matched one. Access is gated by the OAuth token
// and permission set MBA_RENDEZVOUS_API_ACCESS, input is limited to the fixed fields below, and only
// the Lead Id is ever returned to the caller - never other record data. For the same reason the
// Lead query does not use WITH SECURITY_ENFORCED.
public without sharing class MBARendezvousLeadService {

    public static final String TYPE_OF_FORM = 'MBA_Rendezvous';
    public static final String DEPARTMENT = 'Masters';
    public static final String ACTION_CREATED = 'created';
    public static final String ACTION_UPDATED = 'updated';

    public static final String KEY_FIRST_NAME = 'firstName';
    public static final String KEY_LAST_NAME = 'lastName';
    public static final String KEY_EMAIL = 'email';
    public static final String KEY_PHONE = 'phone';
    public static final String KEY_PROGRAMME = 'programmeInterestedIn';
    public static final String KEY_STATE = 'state';
    public static final String KEY_CITY = 'city';
    public static final String KEY_ADMISSION_YEAR = 'admissionYear';
    public static final String KEY_URL = 'url';

    /** Programme given to a new Lead when MBA Rendezvous does not send one. */
    @TestVisible
    private static final String DEFAULT_PROGRAMME = 'Master of Business Administration';
    @TestVisible
    private static final String MASTERS_PROGRAMME_PREFIX = 'Master of ';
    @TestVisible
    private static final String ADMISSION_YEAR_PREFIX = 'Admission Year - ';
    private static final String DEFAULT_LAST_NAME = '.';
    private static final String INDIA_COUNTRY_KEY = 'IN';
    private static final String INDIA_DIALING_CODE = '91';
    private static final String TRUNK_PREFIX = '0';
    private static final Integer INDIAN_MOBILE_LENGTH = 10;
    private static final String MULTI_SELECT_SEPARATOR = ';';
    private static final String KEY_SEPARATOR = '|';
    private static final String DATATYPE_STRING = 'String';
    private static final String DATATYPE_DATE = 'Date';
    private static final String DATATYPE_DECIMAL = 'Decimal';
    private static final String DATATYPE_BOOLEAN = 'Boolean';
    private static final Pattern EMAIL_PATTERN = Pattern.compile('^[A-Za-z0-9._%+\\-]+@[A-Za-z0-9.\\-]+\\.[A-Za-z]{2,}$');
    private static final Pattern YEAR_PATTERN = Pattern.compile('^\\d{4}$');
    private static final Set<Schema.DisplayType> LENGTH_CHECKED_TYPES = new Set<Schema.DisplayType>{
        Schema.DisplayType.STRING,
        Schema.DisplayType.EMAIL,
        Schema.DisplayType.PHONE,
        Schema.DisplayType.URL,
        Schema.DisplayType.TEXTAREA
    };

    /** Thrown when the org configuration this service depends on is missing. */
    public class ConfigurationException extends Exception {}

    /** Thrown when one submitted lead fails validation. The message is safe to return to the partner. */
    private class ValidationException extends Exception {}

    /** One lead as sent by MBA Rendezvous. Every value is read as text. */
    public class LeadRequest {
        public String firstName;
        public String lastName;
        public String email;
        public String phone;
        public String programmeInterestedIn;
        public String state;
        public String city;
        public String admissionYear;
        public String url;

        public LeadRequest() {
            this(new Map<String, Object>());
        }

        /**
         * @description Builds a request from a parsed JSON object. Unknown keys are ignored and
         *              numbers (for example a phone sent without quotes) are read as text.
         * @param source parsed JSON object for one lead
         */
        public LeadRequest(Map<String, Object> source) {
            this.firstName = text(source, KEY_FIRST_NAME);
            this.lastName = text(source, KEY_LAST_NAME);
            this.email = text(source, KEY_EMAIL);
            this.phone = text(source, KEY_PHONE);
            this.programmeInterestedIn = text(source, KEY_PROGRAMME);
            this.state = text(source, KEY_STATE);
            this.city = text(source, KEY_CITY);
            this.admissionYear = text(source, KEY_ADMISSION_YEAR);
            this.url = text(source, KEY_URL);
        }
    }

    /** Outcome for one submitted lead, returned to MBA Rendezvous. */
    public class LeadResult {
        public Boolean success;
        public String leadId;
        public String action;
        public String message;
    }

    /** Configuration loaded once per call. */
    private class Config {
        List<WebFormFieldMapping__mdt> mappings;
        String leadSource;
        Id recordTypeId;
        Map<String, String> programmes;
        Map<String, String> admissionYears;
        Map<String, Schema.SObjectField> leadFields;
    }

    /**
     * @description Validates and saves the given leads. Each lead succeeds or fails on its own.
     * @param requests leads in the order they were sent
     * @return one result per request, in the same order
     * @throws ConfigurationException when the field mapping or Masters record type is missing
     */
    public static List<LeadResult> saveLeads(List<LeadRequest> requests) {
        Config cfg = loadConfig();

        List<LeadResult> results = new List<LeadResult>();
        List<Map<String, Object>> payloads = new List<Map<String, Object>>();
        Set<String> emails = new Set<String>();
        Set<String> admissionYears = new Set<String>();
        Map<String, Integer> firstIndexByKey = new Map<String, Integer>();

        for (Integer i = 0; i < requests.size(); i++) {
            LeadResult result = new LeadResult();
            results.add(result);
            Map<String, Object> payload = null;
            try {
                payload = normalise(requests[i], cfg);
                String key = personKey(payload) + KEY_SEPARATOR + payload.get(KEY_PHONE);
                if (firstIndexByKey.containsKey(key)) {
                    throw new ValidationException('Same lead as item ' + (firstIndexByKey.get(key) + 1) + ' in this request.');
                }
                firstIndexByKey.put(key, i);
                emails.add((String) payload.get(KEY_EMAIL));
                admissionYears.add((String) payload.get(KEY_ADMISSION_YEAR));
            } catch (ValidationException e) {
                payload = null;
                result.success = false;
                result.message = e.getMessage();
            }
            payloads.add(payload);
        }

        Map<String, List<Lead>> candidatesByKey = findCandidates(emails, admissionYears);

        List<Lead> toSave = new List<Lead>();
        List<Integer> requestIndexForSave = new List<Integer>();
        for (Integer i = 0; i < payloads.size(); i++) {
            Map<String, Object> payload = payloads[i];
            if (payload == null) {
                continue;
            }
            Lead existing = findMatch(
                candidatesByKey.get(candidateKey((String) payload.get(KEY_EMAIL), (String) payload.get(KEY_ADMISSION_YEAR))),
                (String) payload.get(KEY_PHONE),
                (String) payload.get(KEY_PROGRAMME)
            );
            if (existing == null) {
                toSave.add(buildNewLead(payload, cfg));
                results[i].action = ACTION_CREATED;
            } else {
                toSave.add(buildUpdate(existing, payload, cfg));
                results[i].action = ACTION_UPDATED;
            }
            requestIndexForSave.add(i);
        }

        if (!toSave.isEmpty()) {
            List<Database.UpsertResult> saveResults = Database.upsert(toSave, false);
            for (Integer s = 0; s < saveResults.size(); s++) {
                LeadResult result = results[requestIndexForSave[s]];
                if (saveResults[s].isSuccess()) {
                    result.success = true;
                    result.leadId = saveResults[s].getId();
                } else {
                    result.success = false;
                    result.action = null;
                    result.message = describeErrors(saveResults[s].getErrors());
                }
            }
        }
        return results;
    }

    private static Config loadConfig() {
        Config cfg = new Config();
        cfg.mappings = [
            SELECT JSON_Key__c, Label, Datatype__c, LeadSourceGroup__c
            FROM WebFormFieldMapping__mdt
            WHERE Department__c = :DEPARTMENT AND TypeOfForm__c = :TYPE_OF_FORM
        ];
        if (cfg.mappings.isEmpty() || String.isBlank(cfg.mappings[0].LeadSourceGroup__c)) {
            throw new ConfigurationException('No WebFormFieldMapping__mdt records for TypeOfForm__c ' + TYPE_OF_FORM + '.');
        }
        cfg.leadSource = cfg.mappings[0].LeadSourceGroup__c;

        List<Department_Record_Type_Mapping__mdt> recordTypes = [
            SELECT Record_Type_Id__c
            FROM Department_Record_Type_Mapping__mdt
            WHERE Department__c = :DEPARTMENT
            LIMIT 1
        ];
        if (recordTypes.isEmpty() || String.isBlank(recordTypes[0].Record_Type_Id__c)) {
            throw new ConfigurationException('No Department_Record_Type_Mapping__mdt record for ' + DEPARTMENT + '.');
        }
        cfg.recordTypeId = recordTypes[0].Record_Type_Id__c;

        cfg.programmes = activeValuesByLowerCase(Lead.Preferred_Programme__c, MASTERS_PROGRAMME_PREFIX);
        cfg.admissionYears = activeValuesByLowerCase(Lead.Admission_Year__c, ADMISSION_YEAR_PREFIX);
        cfg.leadFields = Schema.SObjectType.Lead.fields.getMap();
        return cfg;
    }

    /** Active picklist values that start with the prefix, keyed by lower case for lenient matching. */
    private static Map<String, String> activeValuesByLowerCase(Schema.SObjectField field, String prefix) {
        Map<String, String> values = new Map<String, String>();
        for (Schema.PicklistEntry entry : field.getDescribe().getPicklistValues()) {
            if (entry.isActive() && entry.getValue().startsWith(prefix)) {
                values.put(entry.getValue().toLowerCase(), entry.getValue());
            }
        }
        return values;
    }

    /** Validates one request and returns its values keyed by JSON key, in the form saved to the Lead. */
    private static Map<String, Object> normalise(LeadRequest request, Config cfg) {
        List<String> errors = new List<String>();
        Map<String, Object> payload = new Map<String, Object>();

        if (String.isBlank(request.firstName)) {
            errors.add('firstName is required.');
        }
        payload.put(KEY_FIRST_NAME, request.firstName);
        payload.put(KEY_LAST_NAME, String.isBlank(request.lastName) ? DEFAULT_LAST_NAME : request.lastName);

        if (String.isBlank(request.email)) {
            errors.add('email is required.');
        } else if (!EMAIL_PATTERN.matcher(request.email).matches()) {
            errors.add('email is not a valid email address.');
        }
        payload.put(KEY_EMAIL, request.email == null ? null : request.email.toLowerCase());

        String mobile = indianMobile(request.phone);
        if (String.isBlank(request.phone)) {
            errors.add('phone is required.');
        } else if (mobile == null) {
            errors.add('phone must be a 10-digit Indian mobile number (optionally starting with +91, 91 or 0).');
        }
        payload.put(KEY_PHONE, mobile);

        // Optional. Null here means "not sent": a new Lead gets DEFAULT_PROGRAMME, an existing Lead keeps its own.
        String programme = null;
        if (String.isNotBlank(request.programmeInterestedIn)) {
            programme = cfg.programmes.get(request.programmeInterestedIn.toLowerCase());
            if (programme == null) {
                errors.add('programmeInterestedIn must be one of: ' + String.join(sorted(cfg.programmes.values()), ', ') + '.');
            }
        }
        payload.put(KEY_PROGRAMME, programme);

        String admissionYear = System.Label.Admission_Year;
        if (String.isNotBlank(request.admissionYear)) {
            String requested = YEAR_PATTERN.matcher(request.admissionYear).matches()
                ? ADMISSION_YEAR_PREFIX + request.admissionYear
                : request.admissionYear;
            admissionYear = cfg.admissionYears.get(requested.toLowerCase());
            if (admissionYear == null) {
                errors.add('admissionYear must be a year such as 2027, or one of: ' + String.join(sorted(cfg.admissionYears.values()), ', ') + '.');
            }
        }
        payload.put(KEY_ADMISSION_YEAR, admissionYear);

        payload.put(KEY_STATE, request.state);
        payload.put(KEY_CITY, request.city);
        payload.put(KEY_URL, request.url);

        errors.addAll(lengthErrors(payload, cfg));
        if (!errors.isEmpty()) {
            throw new ValidationException(String.join(errors, ' '));
        }
        return payload;
    }

    /** Checks each mapped text value against the length of the Lead field it is saved to. */
    private static List<String> lengthErrors(Map<String, Object> payload, Config cfg) {
        List<String> errors = new List<String>();
        Set<String> reported = new Set<String>();
        for (WebFormFieldMapping__mdt mapping : cfg.mappings) {
            Object value = payload.get(mapping.JSON_Key__c);
            Schema.SObjectField field = cfg.leadFields.get(mapping.Label);
            if (!(value instanceof String) || field == null || reported.contains(mapping.JSON_Key__c)) {
                continue;
            }
            Schema.DescribeFieldResult describe = field.getDescribe();
            if (LENGTH_CHECKED_TYPES.contains(describe.getType()) && ((String) value).length() > describe.getLength()) {
                errors.add(mapping.JSON_Key__c + ' must be at most ' + describe.getLength() + ' characters.');
                reported.add(mapping.JSON_Key__c);
            }
        }
        return errors;
    }

    /** Returns the 10-digit mobile number, or null when the value is not an Indian mobile number. */
    @TestVisible
    private static String indianMobile(String phone) {
        if (String.isBlank(phone)) {
            return null;
        }
        String digits = phone.replaceAll('\\D', '');
        if (digits.length() == INDIAN_MOBILE_LENGTH + INDIA_DIALING_CODE.length() && digits.startsWith(INDIA_DIALING_CODE)) {
            digits = digits.substring(INDIA_DIALING_CODE.length());
        } else if (digits.length() == INDIAN_MOBILE_LENGTH + TRUNK_PREFIX.length() && digits.startsWith(TRUNK_PREFIX)) {
            digits = digits.substring(TRUNK_PREFIX.length());
        }
        return digits.length() == INDIAN_MOBILE_LENGTH ? digits : null;
    }

    /** Identifies the same submission within one request (used to reject in-request repeats). */
    private static String personKey(Map<String, Object> payload) {
        return payload.get(KEY_EMAIL) + KEY_SEPARATOR + payload.get(KEY_PROGRAMME) + KEY_SEPARATOR + payload.get(KEY_ADMISSION_YEAR);
    }

    private static String candidateKey(String email, String admissionYear) {
        return email.toLowerCase() + KEY_SEPARATOR + admissionYear;
    }

    /**
     * One query for every possible duplicate in the request, grouped by email + admission year.
     * Programme is checked afterwards in findMatch, because a lead sent without a programme may
     * match an existing Lead on any Masters programme.
     */
    private static Map<String, List<Lead>> findCandidates(Set<String> emails, Set<String> admissionYears) {
        Map<String, List<Lead>> candidatesByKey = new Map<String, List<Lead>>();
        if (emails.isEmpty()) {
            return candidatesByKey;
        }
        for (Lead candidate : [
            SELECT Id, Phone, Email, Preferred_Programme__c, Admission_Year__c,
                Registration_Number__c, Multi_Select_Lead_Source__c
            FROM Lead
            WHERE Email IN :emails
              AND Department__c = :DEPARTMENT
              AND Admission_Year__c IN :admissionYears
              AND IsConverted = false
            ORDER BY CreatedDate ASC
        ]) {
            String key = candidateKey(candidate.Email, candidate.Admission_Year__c);
            if (!candidatesByKey.containsKey(key)) {
                candidatesByKey.put(key, new List<Lead>());
            }
            candidatesByKey.get(key).add(candidate);
        }
        return candidatesByKey;
    }

    /**
     * Oldest candidate whose phone contains the incoming mobile number and, when a programme was
     * sent, has that programme. Returns null when there is no match.
     */
    private static Lead findMatch(List<Lead> candidates, String mobile, String programme) {
        if (candidates == null) {
            return null;
        }
        for (Lead candidate : candidates) {
            Boolean samePhone = candidate.Phone != null && candidate.Phone.replaceAll('\\D', '').contains(mobile);
            Boolean sameProgramme = programme == null || programme == candidate.Preferred_Programme__c;
            if (samePhone && sameProgramme) {
                return candidate;
            }
        }
        return null;
    }

    private static Lead buildNewLead(Map<String, Object> payload, Config cfg) {
        Lead lead = new Lead(RecordTypeId = cfg.recordTypeId);
        applyMappedFields(lead, payload, cfg);
        applyStandardValues(lead, payload, cfg);
        if (String.isBlank(lead.Preferred_Programme__c)) {
            // Not sent: default so the course-based Masters round robin assigns a counsellor.
            lead.Preferred_Programme__c = DEFAULT_PROGRAMME;
            lead.Programme_Interested_in__c = DEFAULT_PROGRAMME;
        }
        lead.Multi_Select_Lead_Source__c = cfg.leadSource;
        return lead;
    }

    private static Lead buildUpdate(Lead existing, Map<String, Object> payload, Config cfg) {
        Lead lead = new Lead(Id = existing.Id);
        lead.Multi_Select_Lead_Source__c = appendSource(existing.Multi_Select_Lead_Source__c, cfg.leadSource);
        if (String.isNotBlank(existing.Registration_Number__c)) {
            // Application in progress: keep the student's data, only record that MBA Rendezvous sent them.
            lead.Most_Recent_Lead_Source__c = cfg.leadSource;
            return lead;
        }
        applyMappedFields(lead, payload, cfg);
        applyStandardValues(lead, payload, cfg);
        return lead;
    }

    private static void applyMappedFields(Lead lead, Map<String, Object> payload, Config cfg) {
        for (WebFormFieldMapping__mdt mapping : cfg.mappings) {
            Object value = payload.get(mapping.JSON_Key__c);
            if (value == null || (value instanceof String && String.isBlank((String) value))) {
                continue;
            }
            lead.put(mapping.Label, convert(String.valueOf(value), mapping.Datatype__c));
        }
    }

    /** Values every MBA Rendezvous lead gets regardless of the mapping. */
    private static void applyStandardValues(Lead lead, Map<String, Object> payload, Config cfg) {
        lead.Department__c = DEPARTMENT;
        lead.TypeOfForm__c = TYPE_OF_FORM;
        lead.LeadSource = cfg.leadSource;
        lead.Admission_Year__c = (String) payload.get(KEY_ADMISSION_YEAR);
        lead.LastName = (String) payload.get(KEY_LAST_NAME);
        lead.Phone = LeadPhoneUpdater.generatePhoneNumberWithCountryCode(INDIA_COUNTRY_KEY, (String) payload.get(KEY_PHONE));
    }

    private static Object convert(String value, String datatype) {
        if (datatype == DATATYPE_DATE) {
            return Date.valueOf(value);
        }
        if (datatype == DATATYPE_DECIMAL) {
            return Decimal.valueOf(value);
        }
        if (datatype == DATATYPE_BOOLEAN) {
            return Boolean.valueOf(value);
        }
        return value;
    }

    @TestVisible
    private static String appendSource(String currentValues, String source) {
        Set<String> values = new Set<String>();
        if (String.isNotBlank(currentValues)) {
            values.addAll(currentValues.split(MULTI_SELECT_SEPARATOR));
        }
        values.add(source);
        return String.join(new List<String>(values), MULTI_SELECT_SEPARATOR);
    }

    private static String describeErrors(List<Database.Error> errors) {
        List<String> messages = new List<String>();
        for (Database.Error error : errors) {
            messages.add(error.getMessage());
        }
        return 'Lead could not be saved: ' + String.join(messages, ' ');
    }

    private static List<String> sorted(List<String> values) {
        List<String> copy = new List<String>(values);
        copy.sort();
        return copy;
    }

    private static String text(Map<String, Object> source, String key) {
        Object value = source == null ? null : source.get(key);
        return value == null ? null : String.valueOf(value).trim();
    }
}