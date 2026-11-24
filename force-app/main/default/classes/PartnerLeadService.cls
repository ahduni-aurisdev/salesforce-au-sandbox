/**
 * @description Creates or updates Leads pushed by external lead partners (MBA Rendezvous and future
 *              partners) through the generic Partner Lead API. Called only by PartnerLeadWebhook.
 *
 *              Everything partner- or department-specific is configuration:
 *                - Partner_Lead_Source__mdt: one active record per partner. leadSource in the request
 *                  must match Lead_Source__c, and the record's OAuth_App_Name__c must be the OAuth app
 *                  that issued the caller's token, so a partner can only send its own source.
 *                - Department_Record_Type_Mapping__mdt: the allowed departments and their record types.
 *                - WebFormFieldMapping__mdt (TypeOfForm__c = Partner_API): JSON key to Lead field mapping
 *                  of the standard request format, shared by all partners and departments.
 *
 *              Programme is optional. When it is not sent, a new Lead gets the partner's
 *              Default_Programme__c only if the lead's department is Default_Programme_Department__c;
 *              otherwise it stays blank. An existing Lead keeps its own programme.
 *
 *              Duplicate rule (based on the Masters rule in saveWebsiteLead.handleDuplicateLeadDefault):
 *              an unconverted Lead in the same department with the same email and admission year whose
 *              phone contains the incoming number, and - only when a programme was sent - the same
 *              programme, is the same person.
 *                - Existing Lead has a Registration Number (application in progress): its data is kept;
 *                  only the partner source is added to Multi_Select_Lead_Source__c and
 *                  Most_Recent_Lead_Source__c.
 *                - Otherwise: the mapped fields, Department, Lead Source and form type are overwritten
 *                  and the partner source is added to Multi_Select_Lead_Source__c.
 *              Owner assignment is left to the existing Lead trigger.
 *
 *              Governor usage per call (up to 50 leads): 3 SOQL on custom metadata, 1 SOQL on Lead,
 *              1 DML (upsert). CPU is linear in the number of leads.
 *
 * @author Jitendra V
 * @date 2026-11-18
 * @version 1.0
 * @lastModified 2026-11-18
 */
// without sharing (system mode) is intentional and required: the caller is the shared Partner
// Integration User, which by design has no access to Lead records (profile Partner API Only
// Integration), so its token cannot read or change Leads through the standard APIs. The duplicate
// check must still see every Lead of the department and update the matched one. Access is gated by
// the OAuth token, the PARTNER_LEAD_API_ACCESS permission set and the leadSource-to-app check below;
// input is limited to the fixed fields of the standard format, and only the Lead Id is returned.
// For the same reason the Lead query does not use WITH SECURITY_ENFORCED.
public without sharing class PartnerLeadService {

    public static final String TYPE_OF_FORM_MAPPING = 'Partner_API';
    public static final String ACTION_CREATED = 'created';
    public static final String ACTION_UPDATED = 'updated';

    public static final String KEY_LEAD_SOURCE = 'leadSource';
    public static final String KEY_DEPARTMENT = 'department';
    public static final String KEY_FIRST_NAME = 'firstName';
    public static final String KEY_LAST_NAME = 'lastName';
    public static final String KEY_EMAIL = 'email';
    public static final String KEY_PHONE = 'phone';
    public static final String KEY_PROGRAMME = 'programmeInterestedIn';
    public static final String KEY_STATE = 'state';
    public static final String KEY_CITY = 'city';
    public static final String KEY_ADMISSION_YEAR = 'admissionYear';
    public static final String KEY_URL = 'url';

    @TestVisible
    private static final String ADMISSION_YEAR_PREFIX = 'Admission Year - ';
    private static final String DEFAULT_LAST_NAME = '.';
    private static final String INDIA_COUNTRY_KEY = 'IN';
    private static final String INDIA_DIALING_CODE = '91';
    private static final String TRUNK_PREFIX = '0';
    private static final Integer INDIAN_MOBILE_LENGTH = 10;
    private static final String MULTI_SELECT_SEPARATOR = ';';
    private static final String KEY_SEPARATOR = '|';
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

    /** Set only by unit tests: replaces the Partner_Lead_Source__mdt records. */
    @TestVisible
    private static List<Partner_Lead_Source__mdt> testPartners;

    /** Thrown when the org configuration this service depends on is missing. */
    public class ConfigurationException extends Exception {}

    /** Thrown when one submitted lead fails validation. The message is safe to return to the partner. */
    private class ValidationException extends Exception {}

    /** One lead in the standard partner format. Every value is read as text. */
    public class LeadRequest {
        public String leadSource;
        public String department;
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
            this.leadSource = text(source, KEY_LEAD_SOURCE);
            this.department = text(source, KEY_DEPARTMENT);
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

    /** Outcome for one submitted lead, returned to the partner. */
    public class LeadResult {
        public Boolean success;
        public String leadId;
        public String action;
        public String message;
    }

    /** A department the API accepts and the record type its Leads get. */
    private class Department {
        String name;
        Id recordTypeId;
    }

    /** Configuration loaded once per call. */
    private class Config {
        List<WebFormFieldMapping__mdt> mappings;
        Map<String, Partner_Lead_Source__mdt> partnersBySource;
        List<String> allowedSourceNames;
        Map<String, Department> departments;
        Map<String, String> programmes;
        Map<String, String> admissionYears;
        Map<String, Schema.SObjectField> leadFields;
    }

    /**
     * @description Validates and saves the given leads. Each lead succeeds or fails on its own.
     * @param requests leads in the order they were sent
     * @param callingApp name of the OAuth app that issued the caller's token
     * @return one result per request, in the same order
     * @throws ConfigurationException when the field mapping or department configuration is missing
     */
    public static List<LeadResult> saveLeads(List<LeadRequest> requests, String callingApp) {
        Config cfg = loadConfig(callingApp);

        List<LeadResult> results = new List<LeadResult>();
        List<Map<String, Object>> payloads = new List<Map<String, Object>>();
        Set<String> emails = new Set<String>();
        Set<String> departmentNames = new Set<String>();
        Set<String> admissionYears = new Set<String>();
        Map<String, Integer> firstIndexByKey = new Map<String, Integer>();

        for (Integer i = 0; i < requests.size(); i++) {
            LeadResult result = new LeadResult();
            results.add(result);
            Map<String, Object> payload = null;
            try {
                payload = normalise(requests[i], cfg);
                String key = personKey(payload);
                if (firstIndexByKey.containsKey(key)) {
                    throw new ValidationException('Same lead as item ' + (firstIndexByKey.get(key) + 1) + ' in this request.');
                }
                firstIndexByKey.put(key, i);
                emails.add((String) payload.get(KEY_EMAIL));
                departmentNames.add(((Department) payload.get(KEY_DEPARTMENT)).name);
                admissionYears.add((String) payload.get(KEY_ADMISSION_YEAR));
            } catch (ValidationException e) {
                payload = null;
                result.success = false;
                result.message = e.getMessage();
            }
            payloads.add(payload);
        }

        Map<String, List<Lead>> candidatesByKey = findCandidates(emails, departmentNames, admissionYears);

        List<Lead> toSave = new List<Lead>();
        List<Integer> requestIndexForSave = new List<Integer>();
        for (Integer i = 0; i < payloads.size(); i++) {
            Map<String, Object> payload = payloads[i];
            if (payload == null) {
                continue;
            }
            Lead existing = findMatch(
                candidatesByKey.get(candidateKey(
                    (String) payload.get(KEY_EMAIL),
                    ((Department) payload.get(KEY_DEPARTMENT)).name,
                    (String) payload.get(KEY_ADMISSION_YEAR)
                )),
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

    private static Config loadConfig(String callingApp) {
        Config cfg = new Config();
        cfg.mappings = [
            SELECT JSON_Key__c, Label, Datatype__c
            FROM WebFormFieldMapping__mdt
            WHERE TypeOfForm__c = :TYPE_OF_FORM_MAPPING
        ];
        if (cfg.mappings.isEmpty()) {
            throw new ConfigurationException('No WebFormFieldMapping__mdt records for TypeOfForm__c ' + TYPE_OF_FORM_MAPPING + '.');
        }

        cfg.partnersBySource = new Map<String, Partner_Lead_Source__mdt>();
        cfg.allowedSourceNames = new List<String>();
        for (Partner_Lead_Source__mdt partner : activePartners()) {
            if (String.isNotBlank(partner.Lead_Source__c)
                && String.isNotBlank(callingApp)
                && callingApp.equalsIgnoreCase(partner.OAuth_App_Name__c)) {
                cfg.partnersBySource.put(partner.Lead_Source__c.toLowerCase(), partner);
                cfg.allowedSourceNames.add(partner.Lead_Source__c);
            }
        }
        cfg.allowedSourceNames.sort();

        cfg.departments = new Map<String, Department>();
        for (Department_Record_Type_Mapping__mdt mapping : [
            SELECT Department__c, Record_Type_Id__c
            FROM Department_Record_Type_Mapping__mdt
        ]) {
            if (String.isNotBlank(mapping.Department__c) && String.isNotBlank(mapping.Record_Type_Id__c)) {
                Department dept = new Department();
                dept.name = mapping.Department__c;
                dept.recordTypeId = mapping.Record_Type_Id__c;
                cfg.departments.put(dept.name.toLowerCase(), dept);
            }
        }
        if (cfg.departments.isEmpty()) {
            throw new ConfigurationException('No Department_Record_Type_Mapping__mdt records.');
        }

        cfg.programmes = activeValuesByLowerCase(Lead.Preferred_Programme__c, null);
        cfg.admissionYears = activeValuesByLowerCase(Lead.Admission_Year__c, ADMISSION_YEAR_PREFIX);
        cfg.leadFields = Schema.SObjectType.Lead.fields.getMap();
        return cfg;
    }

    private static List<Partner_Lead_Source__mdt> activePartners() {
        if (Test.isRunningTest() && testPartners != null) {
            return testPartners;
        }
        return [
            SELECT Lead_Source__c, OAuth_App_Name__c, Type_Of_Form__c, Default_Programme__c, Default_Programme_Department__c
            FROM Partner_Lead_Source__mdt
            WHERE Is_Active__c = true
        ];
    }

    /** Active picklist values (optionally only those starting with the prefix), keyed by lower case. */
    private static Map<String, String> activeValuesByLowerCase(Schema.SObjectField field, String prefix) {
        Map<String, String> values = new Map<String, String>();
        for (Schema.PicklistEntry entry : field.getDescribe().getPicklistValues()) {
            if (entry.isActive() && (prefix == null || entry.getValue().startsWith(prefix))) {
                values.put(entry.getValue().toLowerCase(), entry.getValue());
            }
        }
        return values;
    }

    /** Validates one request and returns its values keyed by JSON key, in the form saved to the Lead. */
    private static Map<String, Object> normalise(LeadRequest request, Config cfg) {
        List<String> errors = new List<String>();
        Map<String, Object> payload = new Map<String, Object>();

        Partner_Lead_Source__mdt partner = null;
        if (String.isBlank(request.leadSource)) {
            errors.add('leadSource is required.');
        } else {
            partner = cfg.partnersBySource.get(request.leadSource.toLowerCase());
            if (partner == null) {
                errors.add(cfg.allowedSourceNames.isEmpty()
                    ? 'leadSource is not set up for this connection. Please contact Ahmedabad University.'
                    : 'leadSource must be one of: ' + String.join(cfg.allowedSourceNames, ', ') + '.');
            }
        }
        payload.put(KEY_LEAD_SOURCE, partner);

        Department dept = null;
        if (String.isBlank(request.department)) {
            errors.add('department is required.');
        } else {
            dept = cfg.departments.get(request.department.toLowerCase());
            if (dept == null) {
                errors.add('department must be one of: ' + String.join(departmentNames(cfg), ', ') + '.');
            }
        }
        payload.put(KEY_DEPARTMENT, dept);

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

        // Optional. Null here means "not sent": a new Lead may get the partner default, an existing Lead keeps its own.
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

    private static List<String> departmentNames(Config cfg) {
        List<String> names = new List<String>();
        for (Department dept : cfg.departments.values()) {
            names.add(dept.name);
        }
        names.sort();
        return names;
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
        return String.join(new List<String>{
            (String) payload.get(KEY_EMAIL),
            ((Department) payload.get(KEY_DEPARTMENT)).name,
            String.valueOf(payload.get(KEY_PROGRAMME)),
            (String) payload.get(KEY_ADMISSION_YEAR),
            (String) payload.get(KEY_PHONE)
        }, KEY_SEPARATOR);
    }

    private static String candidateKey(String email, String department, String admissionYear) {
        return String.join(new List<String>{ email.toLowerCase(), department.toLowerCase(), admissionYear }, KEY_SEPARATOR);
    }

    /**
     * One query for every possible duplicate in the request, grouped by email + department +
     * admission year. Programme is checked afterwards in findMatch, because a lead sent without a
     * programme may match an existing Lead on any programme.
     */
    private static Map<String, List<Lead>> findCandidates(Set<String> emails, Set<String> departmentNames, Set<String> admissionYears) {
        Map<String, List<Lead>> candidatesByKey = new Map<String, List<Lead>>();
        if (emails.isEmpty()) {
            return candidatesByKey;
        }
        for (Lead candidate : [
            SELECT Id, Phone, Email, Department__c, Preferred_Programme__c, Admission_Year__c,
                Registration_Number__c, Multi_Select_Lead_Source__c
            FROM Lead
            WHERE Email IN :emails
              AND Department__c IN :departmentNames
              AND Admission_Year__c IN :admissionYears
              AND IsConverted = false
            ORDER BY CreatedDate ASC
        ]) {
            String key = candidateKey(candidate.Email, candidate.Department__c, candidate.Admission_Year__c);
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
        Department dept = (Department) payload.get(KEY_DEPARTMENT);
        Partner_Lead_Source__mdt partner = (Partner_Lead_Source__mdt) payload.get(KEY_LEAD_SOURCE);
        Lead lead = new Lead(RecordTypeId = dept.recordTypeId);
        applyMappedFields(lead, payload, cfg);
        applyStandardValues(lead, payload);
        String defaultProgramme = defaultProgramme(partner, dept, cfg);
        if (String.isBlank(lead.Preferred_Programme__c) && defaultProgramme != null) {
            lead.Preferred_Programme__c = defaultProgramme;
            lead.Programme_Interested_in__c = defaultProgramme;
        }
        lead.Multi_Select_Lead_Source__c = partner.Lead_Source__c;
        return lead;
    }

    /** The partner's default programme, only for its configured department and only if it is an active value. */
    private static String defaultProgramme(Partner_Lead_Source__mdt partner, Department dept, Config cfg) {
        if (String.isBlank(partner.Default_Programme__c)
            || String.isBlank(partner.Default_Programme_Department__c)
            || !dept.name.equalsIgnoreCase(partner.Default_Programme_Department__c)) {
            return null;
        }
        return cfg.programmes.get(partner.Default_Programme__c.toLowerCase());
    }

    private static Lead buildUpdate(Lead existing, Map<String, Object> payload, Config cfg) {
        Partner_Lead_Source__mdt partner = (Partner_Lead_Source__mdt) payload.get(KEY_LEAD_SOURCE);
        Lead lead = new Lead(Id = existing.Id);
        lead.Multi_Select_Lead_Source__c = appendSource(existing.Multi_Select_Lead_Source__c, partner.Lead_Source__c);
        if (String.isNotBlank(existing.Registration_Number__c)) {
            // Application in progress: keep the student's data, only record that the partner sent them.
            lead.Most_Recent_Lead_Source__c = partner.Lead_Source__c;
            return lead;
        }
        applyMappedFields(lead, payload, cfg);
        applyStandardValues(lead, payload);
        return lead;
    }

    private static void applyMappedFields(Lead lead, Map<String, Object> payload, Config cfg) {
        for (WebFormFieldMapping__mdt mapping : cfg.mappings) {
            Object value = payload.get(mapping.JSON_Key__c);
            if (!(value instanceof String) || String.isBlank((String) value)) {
                continue;
            }
            lead.put(mapping.Label, convert((String) value, mapping.Datatype__c));
        }
    }

    /** Values every partner lead gets regardless of the mapping. */
    private static void applyStandardValues(Lead lead, Map<String, Object> payload) {
        Partner_Lead_Source__mdt partner = (Partner_Lead_Source__mdt) payload.get(KEY_LEAD_SOURCE);
        Department dept = (Department) payload.get(KEY_DEPARTMENT);
        lead.Department__c = dept.name;
        lead.TypeOfForm__c = partner.Type_Of_Form__c;
        lead.LeadSource = partner.Lead_Source__c;
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