/**
 * ============================================================================
 * CLASS       : AU_EnquiryFormController
 * API VERSION : 59.0
 * DESCRIPTION : Controller for AU_EnquiryForm Visualforce page.
 *               Runs as a Force.com Site Guest User.
 *
 * THREE-LEVEL METADATA HIERARCHY
 * ─────────────────────────────────────────────────────────────────────────────
 *  Level 1  Form_Department_Config__mdt   dept tile       existing, unchanged
 *  Level 2  Form_Config__mdt             form tile        NEW
 *  Level 3  Form_Field_Config__mdt       form fields      updated: Form_Code__c
 *
 *  URL patterns
 *    /enquiry                           show dept tiles (step 1)
 *    /enquiry?dept=masters              show Masters form tiles (step 2)
 *    /enquiry?dept=masters&form=mba     jump to MBA form fields (step 3)
 *    /enquiry?form=mba                  resolve dept, jump to form fields
 *
 * KEY DESIGN PRINCIPLES
 * ─────────────────────────────────────────────────────────────────────────────
 *  1. ZERO hardcoded field mapping   — Form_Field_Config__mdt.SF_API_Name__c
 *  2. ZERO hardcoded slugs           — dept: URL_Slugs__c / form: Form_Slug__c
 *  3. Record Type per form           — Form_Config__mdt.Lead_Record_Type_Name__c
 *                                      falls back to dept-level RT if blank
 *  4. LeadSource auto-resolved       — utm_source to UTM_Source_Map__c to default
 *  5. Duplicate matching             — dynamic SOQL, RecordTypeId from form/dept
 *  6. Dynamic SELECT in merge        — schema-driven, no missing-field errors
 *
 * CUSTOM METADATA TYPE : Form_Department_Config__mdt   Level 1, EXISTING
 * ─────────────────────────────────────────────────────────────────────────────
 *  DeveloperName               Canonical dept code        e.g. MASTERS
 *  MasterLabel                 Display name               e.g. Masters
 *  Icon_Emoji__c               Text 10    Tile emoji
 *  Subtitle__c                 Text 100   Tile sub-heading
 *  URL_Slugs__c                Text 255   Comma-separated dept slug aliases
 *  Lead_Record_Type_Name__c    Text 80    Fallback Lead RecordType DeveloperName
 *  Default_Lead_Source__c      Text 100   Default LeadSource when no utm_source
 *  UTM_Source_Map__c           Long Text  utm_value=LeadSource value, one per line
 *  Sort_Order__c               Number 3,0 Tile display order
 *
 * CUSTOM METADATA TYPE : Form_Config__mdt   Level 2, NEW
 * ─────────────────────────────────────────────────────────────────────────────
 *  DeveloperName               Unique form code           e.g. MASTERS_MBA
 *  MasterLabel                 System label
 *  Department_Code__c          Text 80    Matches dept DeveloperName  MASTERS
 *  Form_Name__c                Text 150   Form tile heading
 *  Form_Subtitle__c            Text 150   Form tile sub-heading
 *  Form_Icon__c                Text 10    Tile emoji
 *  Form_Slug__c                Text 100   URL form= param value        mba
 *  Section_Label__c            Text 100   Heading above dynamic fields
 *  Lead_Record_Type_Name__c    Text 80    Lead RT for this form overrides dept
 *  Sort_Order__c               Number 3,0 Order within dept
 *
 * CUSTOM METADATA TYPE : Form_Field_Config__mdt   Level 3, UPDATED
 * ─────────────────────────────────────────────────────────────────────────────
 *  Department_Code__c          Text 80    Matches dept DeveloperName
 *  Form_Code__c                Text 100   NEW Matches Form_Config__mdt DeveloperName
 *                                         BLANK means field shows on ALL forms in dept
 *  SF_API_Name__c              Text 100   EXACT Lead field API name
 *  Form_Label__c               Text 150   Label shown on form
 *  Field_Type__c               Text 50    text number picklist date email
 *                                         tel textarea programme_picklist
 *  Is_Required__c              Checkbox   Client-side required validation
 *  Placeholder_Text__c         Text 255   HTML placeholder
 *  Help_Text__c                Text 255   Hint below field
 *  Field_Options__c            Long Text  Newline-separated picklist values
 *  Full_Width__c               Checkbox   Span both columns
 *  Is_Numeric__c               Checkbox   Cast to Decimal on insert
 *  Is_Integer__c               Checkbox   Cast to Integer on insert
 *  Sort_Order__c               Number 3,0 Field order within form
 *
 * DUPLICATE MATCHING RULES
 * ─────────────────────────────────────────────────────────────────────────────
 *  UG         Phone AND Email AND RecordTypeId (from form or dept RT)
 *  ALL OTHERS Phone AND Email AND Programme_Interest__c AND RecordTypeId
 *  Dynamic SOQL via Database.query() — no hardcoded field lists anywhere.
 *
 * reCAPTCHA v3 INTEGRATION
 * ─────────────────────────────────────────────────────────────────────────────
 *  Client (JS) : grecaptcha.execute(siteKey, {action:'submit_enquiry'})
 *                → returns token, added to payload as captchaToken
 *  Server (Apex): verifyCaptcha(token, 0.5)
 *                → POST to callout:GoogleReCaptcha (Named Credential)
 *                → checks success=true AND score >= 0.5
 *                → degrade gracefully if token blank or API unreachable
 *
 *  SETUP REQUIRED:
 *    1. Named Credential: GoogleReCaptcha → https://www.google.com/recaptcha/api/siteverify
 *    2. Custom Setting: RecaptchaSettings__c → Secret_Key__c (Protected)
 *    3. Remote Site Setting: https://www.google.com
 *    4. Guest User: Callout permissions enabled on the site
 * ============================================================================
 */
global without sharing class AU_EnquiryFormController {

    /* ══════════════════════════════════════════════════════════════════════
       SLUG MAPS — built from metadata at runtime
    ══════════════════════════════════════════════════════════════════════ */

    /** Returns lowercase dept slug -> uppercase dept code */
    @TestVisible
    private static Map<String, String> buildDeptSlugMap() {
        Map<String, String> m = new Map<String, String>();
        for (Form_Department_Config__mdt d : [
            SELECT DeveloperName, URL_Slugs__c
            FROM   Form_Department_Config__mdt
        ]) {
            String code = d.DeveloperName != null ? d.DeveloperName.toUpperCase() : '';
            if (String.isBlank(code)) continue;
            m.put(code.toLowerCase(), code);
            if (String.isNotBlank(d.URL_Slugs__c)) {
                for (String s : d.URL_Slugs__c.split(',')) {
                    String t = s.trim().toLowerCase();
                    if (String.isNotBlank(t)) m.put(t, code);
                }
            }
        }
        return m;
    }

    /** Returns lowercase form slug -> lowercase form slug (self-mapping for normalisation).
     *  A Form_Slug__c value like 'wonderchat' is shared across multiple Form_Config__mdt
     *  records (one per dept). We normalise the slug to lowercase and return it as-is.
     *  The actual routing is done in JS via findFormsBySlug() which matches f.slug.
     */
    @TestVisible
    private static Map<String, String> buildFormSlugMap() {
        Map<String, String> m = new Map<String, String>();
        for (Form_Config__mdt fc : [
            SELECT DeveloperName, Form_Slug__c
            FROM   Form_Config__mdt
        ]) {
            String devName = fc.DeveloperName != null ? fc.DeveloperName.toLowerCase() : '';
            if (String.isNotBlank(devName)) m.put(devName, devName);
            if (String.isNotBlank(fc.Form_Slug__c)) {
                String slug = fc.Form_Slug__c.trim().toLowerCase();
                if (String.isNotBlank(slug)) m.put(slug, slug);
            }
        }
        return m;
    }

    public static String normaliseDeptCode(String raw) {
        if (String.isBlank(raw)) return '';
        Map<String, String> sm = buildDeptSlugMap();
        String lower = raw.toLowerCase().trim();
        return sm.containsKey(lower) ? sm.get(lower) : raw.toUpperCase();
    }

    /** Normalise a raw form slug to its canonical lowercase form.
     *  e.g. 'Wonderchat' → 'wonderchat', 'WEBSITE' → 'website'
     */
    public static String normaliseFormCode(String raw) {
        if (String.isBlank(raw)) return '';
        Map<String, String> sm = buildFormSlugMap();
        String lower = raw.toLowerCase().trim();
        return sm.containsKey(lower) ? sm.get(lower) : lower;
    }

    /* ── VF merge fields {!deptParam} and {!formParam} ──────────────────── */
    public String deptParam {
        get {
            if (ApexPages.currentPage() == null) return '';
            Map<String, String> params = ApexPages.currentPage().getParameters();
            String raw = params.containsKey('dept')
                ? params.get('dept')
                : (params.containsKey('department') ? params.get('department') : '');
            return String.isNotBlank(raw) ? normaliseDeptCode(raw) : '';
        }
        private set;
    }

    /** VF merge field {!formParam} — returns the lowercase form slug from ?form= URL param */
    public String formParam {
        get {
            if (ApexPages.currentPage() == null) return '';
            Map<String, String> params = ApexPages.currentPage().getParameters();
            String raw = params.containsKey('form') ? params.get('form') : '';
            return String.isNotBlank(raw) ? normaliseFormCode(raw) : '';
        }
        private set;
    }

    /* ══════════════════════════════════════════════════════════════════════
       REMOTE ACTION : getMetadata
       Returns three-level hierarchy:
         dept -> forms[] -> fields[]
       Field scoping:
         Form_Code__c = MASTERS_MBA  only on MBA form
         Form_Code__c = blank        shared across ALL forms in dept
    ══════════════════════════════════════════════════════════════════════ */
    @RemoteAction
    global static List<Map<String, Object>> getMetadata() {
        List<Map<String, Object>> result = new List<Map<String, Object>>();

        List<Form_Department_Config__mdt> deptConfigs = [
            SELECT DeveloperName, MasterLabel, Icon_Emoji__c, Subtitle__c,
                   URL_Slugs__c, Lead_Record_Type_Name__c,
                   Default_Lead_Source__c, UTM_Source_Map__c, Sort_Order__c,
                   Contact_Email__c, Contact_Phone__c, Contact_Title__c
            FROM   Form_Department_Config__mdt
            ORDER  BY Sort_Order__c ASC NULLS LAST
        ];

        List<Form_Config__mdt> formConfigs = [
            SELECT DeveloperName, MasterLabel, Department_Code__c,
                   Form_Name__c, Form_Subtitle__c, Form_Icon__c,
                   Form_Slug__c, Section_Label__c,
                   Lead_Record_Type_Name__c, Sort_Order__c
            FROM   Form_Config__mdt
            ORDER  BY Sort_Order__c ASC NULLS LAST
        ];

        List<Form_Field_Config__mdt> allFields = [
            SELECT Department_Code__c, Form_Code__c, SF_API_Name__c,
                   Form_Label__c, Field_Type__c, Is_Required__c,
                   Placeholder_Text__c, Help_Text__c, Field_Options__c,
                   Full_Width__c, Is_Numeric__c, Is_Integer__c, Sort_Order__c,
                   Is_Hidden__c, Default_Value__c
            FROM   Form_Field_Config__mdt
            ORDER  BY Sort_Order__c ASC NULLS LAST
        ];

        /* Group forms by dept code */
        Map<String, List<Form_Config__mdt>> formsByDept =
            new Map<String, List<Form_Config__mdt>>();
        for (Form_Config__mdt fc : formConfigs) {
            String key = fc.Department_Code__c != null
                ? fc.Department_Code__c.toUpperCase() : '';
            if (!formsByDept.containsKey(key))
                formsByDept.put(key, new List<Form_Config__mdt>());
            formsByDept.get(key).add(fc);
        }

        /* Group fields by composite key DEPTCODE|FORMCODE
           Blank Form_Code -> stored under DEPTCODE| (shared) */
        Map<String, List<Form_Field_Config__mdt>> fieldsByKey =
            new Map<String, List<Form_Field_Config__mdt>>();
        for (Form_Field_Config__mdt f : allFields) {
            String dCode = f.Department_Code__c != null
                ? f.Department_Code__c.toUpperCase() : '';
            String fCode = String.isNotBlank(f.Form_Code__c)
                ? f.Form_Code__c.toUpperCase() : '';
            String key   = dCode + '|' + fCode;
            if (!fieldsByKey.containsKey(key))
                fieldsByKey.put(key, new List<Form_Field_Config__mdt>());
            fieldsByKey.get(key).add(f);
        }

        for (Form_Department_Config__mdt d : deptConfigs) {
            String dCode = d.DeveloperName != null ? d.DeveloperName.toUpperCase() : '';

            List<String> slugs = new List<String>();
            slugs.add(dCode.toLowerCase());
            if (String.isNotBlank(d.URL_Slugs__c)) {
                for (String s : d.URL_Slugs__c.split(',')) {
                    String t = s.trim().toLowerCase();
                    if (String.isNotBlank(t) && !slugs.contains(t)) slugs.add(t);
                }
            }

            Map<String, String> utmSourceMap = parseKeyValueBlock(d.UTM_Source_Map__c);

            List<Map<String, Object>> formsOut = new List<Map<String, Object>>();
            List<Form_Config__mdt> deptForms = formsByDept.containsKey(dCode)
                ? formsByDept.get(dCode) : new List<Form_Config__mdt>();

            for (Form_Config__mdt fc : deptForms) {
                String fCode = fc.Form_Slug__c != null
                    ? fc.Form_Slug__c.toUpperCase() : '';

                String rtName = String.isNotBlank(fc.Lead_Record_Type_Name__c)
                    ? fc.Lead_Record_Type_Name__c : d.Lead_Record_Type_Name__c;

                formsOut.add(new Map<String, Object>{
                    'code'               => fCode,
                    'name'               => String.isNotBlank(fc.Form_Name__c)
                                               ? fc.Form_Name__c : fc.MasterLabel,
                    'icon'               => String.isNotBlank(fc.Form_Icon__c)
                                               ? fc.Form_Icon__c : '📋',
                    'subtitle'           => fc.Form_Subtitle__c,
                    'slug'               => String.isNotBlank(fc.Form_Slug__c)
                                               ? fc.Form_Slug__c.toLowerCase() : '',
                    'sectionLabel'       => fc.Section_Label__c,
                    'leadRecordTypeName' => rtName,
                    'deptCode'           => dCode,
                    'fields'             => buildFieldList(dCode, fCode, fieldsByKey)
                });
            }

            /* ── FALLBACK: No Form_Config__mdt records for this dept ──────────
               When Form_Config__mdt has not been set up yet (or the dept has
               no form records), synthesise a single implicit form using the
               dept-level field config (Form_Code__c = blank = shared fields).
               This makes the page work immediately without any Form_Config__mdt
               setup — students see the dept's fields directly.                 */
            if (formsOut.isEmpty()) {
                List<Map<String, Object>> sharedFields =
                    buildFieldList(dCode, '', fieldsByKey);
                /* Only add synthetic form if there are fields defined for this dept */
                if (!sharedFields.isEmpty()) {
                    formsOut.add(new Map<String, Object>{
                        'code'               => dCode + '_DEFAULT',
                        'name'               => d.MasterLabel + ' Enquiry',
                        'icon'               => String.isNotBlank(d.Icon_Emoji__c)
                                                   ? d.Icon_Emoji__c : '📋',
                        'subtitle'           => d.Subtitle__c,
                        'slug'               => dCode.toLowerCase(),
                        'sectionLabel'       => 'Programme Details',
                        'leadRecordTypeName' => d.Lead_Record_Type_Name__c,
                        'deptCode'           => dCode,
                        'fields'             => sharedFields
                    });
                }
            }

            // Resolve contact details with intelligent fallbacks
            String contactEmail = String.isNotBlank(d.Contact_Email__c)
                ? d.Contact_Email__c : getDefaultEmailForDept(dCode);
            String contactPhone = String.isNotBlank(d.Contact_Phone__c)
                ? d.Contact_Phone__c : getDefaultPhoneForDept(dCode);
            String contactTitle = String.isNotBlank(d.Contact_Title__c)
                ? d.Contact_Title__c : getDefaultTitleForDept(dCode, d.MasterLabel);

            result.add(new Map<String, Object>{
                'code'              => dCode,
                'name'              => d.MasterLabel,
                'icon'              => String.isNotBlank(d.Icon_Emoji__c)
                                           ? d.Icon_Emoji__c : '🎓',
                'subtitle'          => d.Subtitle__c,
                'slugs'             => slugs,
                'leadRecordTypeName'=> d.Lead_Record_Type_Name__c,
                'defaultLeadSource' => d.Default_Lead_Source__c,
                'utmSourceMap'      => utmSourceMap,
                'contactEmail'      => contactEmail,
                'contactPhone'      => contactPhone,
                'contactTitle'      => contactTitle,
                'forms'             => formsOut
            });
        }

        return result;
    }

    /**
     * Brochure for the chosen programme (Programme_Brochure__mdt), matched on the
     * programme name as submitted or as remapped. Returns null if none is set or the
     * link is not https.
     */
    @TestVisible
    private static String getBrochureUrl(String submittedProgramme, String mappedProgramme) {
        Set<String> names = new Set<String>();
        if (String.isNotBlank(submittedProgramme)) names.add(submittedProgramme.trim().toLowerCase());
        if (String.isNotBlank(mappedProgramme))    names.add(mappedProgramme.trim().toLowerCase());

        for (Programme_Brochure__mdt b : [
            SELECT Programme_Name__c, Brochure_URL__c FROM Programme_Brochure__mdt
        ]) {
            if (String.isNotBlank(b.Brochure_URL__c) && String.isNotBlank(b.Programme_Name__c)
                    && names.contains(b.Programme_Name__c.trim().toLowerCase())
                    && b.Brochure_URL__c.startsWithIgnoreCase('https://')) {
                return b.Brochure_URL__c;
            }
        }
        return null;
    }

    /**
     * Fallback default contact emails per department code.
     */
    @TestVisible
    private static String getDefaultEmailForDept(String deptCode) {
        if (deptCode == 'UG') return 'ugadmissions@ahduni.edu.in';
        if (deptCode == 'MASTERS') return 'masters.admissions@ahduni.edu.in';
        if (deptCode == 'PHD') return 'doctoral.admissions@ahduni.edu.in';
        if (deptCode == 'EXEC_ED') return 'execed@ahduni.edu.in';
        return 'admissions@ahduni.edu.in';
    }

    /**
     * Fallback default contact phone numbers per department code.
     */
    @TestVisible
    private static String getDefaultPhoneForDept(String deptCode) {
        if (deptCode == 'UG') return '+91 81288 18876';
        if (deptCode == 'MASTERS') return '+91 79 6191 1126';
        if (deptCode == 'PHD') return '+91 79 6191 1125';
        if (deptCode == 'EXEC_ED') return '+91 79 6191 1197';
        return '+91 79 6191 1000';
    }

    /**
     * Fallback default contact title per department.
     */
    @TestVisible
    private static String getDefaultTitleForDept(String deptCode, String masterLabel) {
        if (deptCode == 'PHD') return 'Doctoral Admissions';
        if (deptCode == 'EXEC_ED') return 'Executive Education Admissions';
        if (String.isNotBlank(masterLabel)) return masterLabel + ' Admissions';
        return 'Admissions Office';
    }

    /* ── Build field list for a form: form-specific + dept-shared merged ─── */
    private static List<Map<String, Object>> buildFieldList(
        String dCode,
        String fCode,
        Map<String, List<Form_Field_Config__mdt>> fieldsByKey
    ) {
        /* Use ordered map keyed by SF API name to avoid duplicates.
           Form-specific fields take priority over shared fields. */
        Map<String, Form_Field_Config__mdt> seen =
            new Map<String, Form_Field_Config__mdt>();

        String specificKey = dCode + '|' + fCode;
        String sharedKey   = dCode + '|';

        System.debug('specificKey' + specificKey);
        System.debug('sharedKey' + sharedKey);

        if (fieldsByKey.containsKey(specificKey)) {
            for (Form_Field_Config__mdt f : fieldsByKey.get(specificKey)) {
                if (String.isNotBlank(f.SF_API_Name__c)) seen.put(f.SF_API_Name__c, f);
            }
        }
        if (fieldsByKey.containsKey(sharedKey)) {
            for (Form_Field_Config__mdt f : fieldsByKey.get(sharedKey)) {
                if (String.isNotBlank(f.SF_API_Name__c) && !seen.containsKey(f.SF_API_Name__c)) {
                    seen.put(f.SF_API_Name__c, f);
                }
            }
        }

        List<Map<String, Object>> out = new List<Map<String, Object>>();
        for (Form_Field_Config__mdt f : seen.values()) {
            out.add(new Map<String, Object>{
                'sfApiName'   => f.SF_API_Name__c,
                'label'       => String.isNotBlank(f.Form_Label__c)
                                    ? f.Form_Label__c : f.SF_API_Name__c,
                'type'        => f.Field_Type__c != null
                                    ? f.Field_Type__c.toLowerCase() : 'text',
                'required'    => f.Is_Required__c,
                'placeholder' => f.Placeholder_Text__c,
                'hint'        => f.Help_Text__c,
                'fullWidth'   => f.Full_Width__c,
                'isNumeric'   => f.Is_Numeric__c,
                'isInteger'   => f.Is_Integer__c,
                'isHidden'    => f.Is_Hidden__c == true,
                'defaultValue'=> f.Default_Value__c,
                'options'     => parseLines(f.Field_Options__c)
            });
        }
        return out;
    }

    private static Map<String, String> parseKeyValueBlock(String raw) {
        Map<String, String> m = new Map<String, String>();
        if (String.isBlank(raw)) return m;
        for (String line : raw.split('\n')) {
            String trimmed = line.trim();
            Integer idx    = trimmed.indexOf('=');
            if (idx > 0) {
                String k = trimmed.substring(0, idx).trim().toLowerCase();
                String v = trimmed.substring(idx + 1).trim();
                if (String.isNotBlank(k) && String.isNotBlank(v)) m.put(k, v);
            }
        }
        return m;
    }

    private static List<String> parseLines(String raw) {
        List<String> out = new List<String>();
        if (String.isBlank(raw)) return out;
        for (String line : raw.split('\n')) {
            String t = line.trim();
            if (String.isNotBlank(t)) out.add(t);
        }
        return out;
    }

    /* ══════════════════════════════════════════════════════════════════════
       REMOTE ACTION : getStatePicklistValues
    ══════════════════════════════════════════════════════════════════════ */
    @RemoteAction
    global static List<String> getStatePicklistValues() {
        List<String> states = new List<String>();
        try {
            Map<String, Schema.SObjectField> leadFields = Schema.SObjectType.Lead.fields.getMap();
            Schema.SObjectField stateField = leadFields.get('State');
            if (stateField == null) {
                stateField = leadFields.get('StateCode');
            }
            if (stateField != null) {
                Schema.DescribeFieldResult fieldResult = stateField.getDescribe();
                for (Schema.PicklistEntry entry : fieldResult.getPicklistValues()) {
                    if (entry.isActive()) {
                        states.add(entry.getLabel());
                    }
                }
            }
        } catch (Exception e) {
            System.debug('Error fetching standard state picklist values: ' + e.getMessage());
        }

        if (states.isEmpty()) {
            try {
                Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
                if (gd.containsKey('state__c')) {
                    String query = 'SELECT Name FROM State__c WHERE Status__c = \'Active\' ORDER BY Name ASC';
                    List<SObject> customStates = Database.query(query);
                    for (SObject s : customStates) {
                        states.add((String) s.get('Name'));
                    }
                }
            } catch (Exception e) {
                System.debug('Error fetching custom State__c records: ' + e.getMessage());
            }
        }
        return states;
    }

    /* ══════════════════════════════════════════════════════════════════════
       REMOTE ACTION : createLead
    ══════════════════════════════════════════════════════════════════════ */
    @RemoteAction
    global static Map<String, Object> createLead(String payloadJSON) {
        Map<String, Object> response = new Map<String, Object>();

        try {
            Map<String, Object> data =
                (Map<String, Object>) JSON.deserializeUntyped(payloadJSON);

            String programVal = strVal(data, 'Preferred_Programme__c');
            String submittedProgramme = programVal;

            // Map containing old value -> new value
            Map<String, String> programMap = new Map<String, String>{
                'Global Executive MBA in Pharmaceutical Management'   => 'Gemba',
                'GROW- Executive General Management Programme'        => 'Grow - Executive General Management',
                'Building Digital Factories'                          => 'Transforming R&D in Indian Firms',
                'Finance for Non-Finance Professionals'               => 'Fin4NonFin'
            };

            // Replace value if found in mapping
            if (programMap.containsKey(programVal)) {
                data.put('Preferred_Programme__c', programMap.get(programVal));
            }

            System.debug('AU_EnquiryFormController data  === > ' + data);   

            String deptCode   = strVal(data, 'Department_Code__c').toUpperCase();
            String formCode   = strVal(data, 'Form_Code__c').toUpperCase();
            String emailVal   = strVal(data, 'Email');
            String phoneVal   = strVal(data, 'Phone');
            programVal        = strVal(data, 'Preferred_Programme__c');

            /* ── 1. Field configs: form-specific + shared (blank Form_Code) ─ */
            List<Form_Field_Config__mdt> fieldConfigs = [
                SELECT SF_API_Name__c, Is_Numeric__c, Is_Integer__c, Form_Code__c,
                       Is_Hidden__c, Default_Value__c
                FROM   Form_Field_Config__mdt
                WHERE  Department_Code__c = :deptCode
                AND    (Form_Code__c = :formCode
                        OR Form_Code__c = null
                        OR Form_Code__c = '')
            ];

            /* Form-specific wins over shared when same SF_API_Name__c */
            Map<String, Form_Field_Config__mdt> allowedFields =
                new Map<String, Form_Field_Config__mdt>();
            for (Form_Field_Config__mdt fc : fieldConfigs) {
                if (String.isBlank(fc.SF_API_Name__c)) continue;
                Boolean alreadyHaveSpecific = allowedFields.containsKey(fc.SF_API_Name__c)
                    && String.isNotBlank(allowedFields.get(fc.SF_API_Name__c).Form_Code__c);
                Boolean thisIsSpecific = String.isNotBlank(fc.Form_Code__c);
                if (!allowedFields.containsKey(fc.SF_API_Name__c)
                        || (thisIsSpecific && !alreadyHaveSpecific)) {
                    allowedFields.put(fc.SF_API_Name__c, fc);
                }
            }

            /* Apply default values configured on metadata if not supplied in payload */
            for (String apiName : allowedFields.keySet()) {
                Form_Field_Config__mdt fc = allowedFields.get(apiName);
                if (String.isNotBlank(fc.Default_Value__c) && (!data.containsKey(apiName) || String.isBlank(strVal(data, apiName)))) {
                    data.put(apiName, fc.Default_Value__c);
                }
            }

            /* ── 2. Form metadata + Dept metadata ───────────────────────── */
            List<Form_Config__mdt> formMeta = [
                SELECT Lead_Record_Type_Name__c, Department_Code__c, TypeOfForm__c
                FROM   Form_Config__mdt
                WHERE  DeveloperName = :formCode
                LIMIT  1
            ];
            List<Form_Department_Config__mdt> deptMeta = [
                SELECT Lead_Record_Type_Name__c, TypeOfForm__c,
                       Default_Lead_Source__c,
                       UTM_Source_Map__c
                FROM   Form_Department_Config__mdt
                WHERE  DeveloperName = :deptCode
                LIMIT  1
            ];

            /* ── 3. RecordType: form-level overrides dept-level ──────────── */
            String rtName = '';
            String typeOfForm = '';
            if (!formMeta.isEmpty()
                    && String.isNotBlank(formMeta[0].Lead_Record_Type_Name__c)) {
                rtName = formMeta[0].Lead_Record_Type_Name__c;
                typeOfForm = formMeta[0].TypeOfForm__c;
            } else if (!deptMeta.isEmpty()
                    && String.isNotBlank(deptMeta[0].Lead_Record_Type_Name__c)) {
                rtName = deptMeta[0].Lead_Record_Type_Name__c;
                typeOfForm = deptMeta[0].TypeOfForm__c;
            }

            System.debug('AU_EnquiryFormController rtName ' + rtName);
            /* ── 4. Create Lead + RecordTypeId ───────────────────────────── */
            Lead l = new Lead();
            if (String.isNotBlank(rtName)) {
                Map<String, Schema.RecordTypeInfo> rtMap =
                    Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName();
                   
                    System.debug(rtMap);
                    System.debug('AU_EnquiryFormController rtMap.containsKey(rtName) ' + rtMap.containsKey(rtName));
                if (rtMap.containsKey(rtName)) {
                    l.RecordTypeId = rtMap.get(rtName).getRecordTypeId();
                }
            }

            /* ── 5. Standard + tracking field sets ──────────────────────── */
            Set<String> STANDARD_LEAD_FIELDS = new Set<String>{
                'FirstName', 'LastName', 'Email', 'Phone',
                'City', 'State', 'Description', 'Company'
            };
            Set<String> TRACKING_FIELDS = new Set<String>{
                'UTM_Source__c', 'UTM_Medium__c', 'UTM_Campaign__c',
                'UTM_Content__c', 'UTM_Term__c',
                'Department__c', 'Department_Code__c', 'Form_Code__c'
            };
            Map<String, Schema.SObjectField> leadSchema =
                Schema.SObjectType.Lead.fields.getMap();

            /* ── 6. Dynamic field mapping via SObject.put() ─────────────── */
            for (String apiName : data.keySet()) {
                Object rawVal = data.get(apiName);
                if (rawVal == null) continue;
                String strValue = String.valueOf(rawVal).trim();
                if (String.isBlank(strValue)) continue;

                Boolean isStd      = STANDARD_LEAD_FIELDS.contains(apiName);
                Boolean isTracking = TRACKING_FIELDS.contains(apiName);
                Boolean isMeta     = allowedFields.containsKey(apiName);
                if (!isStd && !isTracking && !isMeta) continue;
                if (!leadSchema.containsKey(apiName.toLowerCase())) continue;

                if (isMeta) {
                    Form_Field_Config__mdt fc = allowedFields.get(apiName);
                    if (fc.Is_Integer__c) {
                        try { l.put(apiName, Integer.valueOf(strValue)); }
                        catch (Exception e) {}
                        continue;
                    }
                    if (fc.Is_Numeric__c) {
                        try { l.put(apiName, Decimal.valueOf(strValue)); }
                        catch (Exception e) {}
                        continue;
                    }
                }
                l.put(apiName, strValue);
            }

            /* ── 7. System fields ────────────────────────────────────────── */
            if (String.isBlank((String) l.get('LastName')))
                l.put('LastName', 'Unknown');

            /* LeadSource resolution
               1. LeadSource field selected in the form -> highest priority
               2. otherwise utm_source in URL            -> used as-is
               3. otherwise                              -> 'Admission Form' */
            String resolvedLeadSource = strVal(data, 'LeadSource');
            if (String.isBlank(resolvedLeadSource)) resolvedLeadSource = strVal(data, 'UTM_Source__c');
            if (String.isBlank(resolvedLeadSource)) resolvedLeadSource = 'Admission Form';

            l.put('TypeOfForm__c', TypeOfForm);
            l.put('Status', 'New Lead');

            l.put('Programme_Interested_in__c', l.get('Preferred_Programme__c') != null ? l.get('Preferred_Programme__c') : l.get('Programme_Interested_in__c'));
            /* ── 8. reCAPTCHA verification ──────────────────────────────────
               Token sent from browser is verified with Google's API.
               Score threshold: 0.5 (0.0 = bot, 1.0 = human).
               If verification fails: return captchaFailed=true to browser.
               If token is blank (script blocked): degrade gracefully.    */
            String captchaToken = strVal(data, 'captchaToken');
            if (!verifyCaptcha(captchaToken, 0.5)) {
                response.put('success',       false);
                response.put('captchaFailed', true);
                response.put('error', 'Security verification failed. Please try again.');
                return response;
            }

            /* ── 9. Duplicate check then insert or merge ─────────────────── */
            Lead masterLeadId = findDuplicate(
                deptCode, emailVal, phoneVal, programVal, rtName
            );

            System.debug(masterLeadId);

            Id      finalLeadId = null;
            Boolean isDuplicate = false;
            if(masterLeadId == null){
                System.debug('AU_EnquiryFormController masterLeadId ' + masterLeadId);
            }
            if (masterLeadId != null) {
                System.debug('AU_EnquiryFormController masterLeadId ' + masterLeadId);
                isDuplicate = true;
                finalLeadId = masterLeadId.Id;
                l.Id = masterLeadId.Id;

                // Convert Multi-Select Picklist to List
                List<String> values = new List<String>();

                if (!String.isBlank(masterLeadId.Multi_Select_Lead_Source__c)) {
                    values = masterLeadId.Multi_Select_Lead_Source__c.split(';');
                }

                // Add new value if not already present
                String newValue = resolvedLeadSource;

                if (!values.contains(newValue)) {
                    values.add(newValue);
                }
                // Convert List back to Multi-Select Picklist format
                l.Multi_Select_Lead_Source__c = String.join(values, ';');
                l.LeadSource = resolvedLeadSource;
                Database.update(l);
            } else {
                l.put('LeadSource', resolvedLeadSource);

                /* set Multi-Select Lead Source */
                if (!String.isBlank(resolvedLeadSource)) {
                    l.put('Multi_Select_Lead_Source__c', resolvedLeadSource);
                }

                Database.DmlOptions dmlOpts = new Database.DmlOptions();
                dmlOpts.DuplicateRuleHeader.allowSave        = true;
                dmlOpts.DuplicateRuleHeader.runAsCurrentUser = false;
                Database.SaveResult sr = Database.insert(l, dmlOpts);
                if (sr.isSuccess()) {
                    finalLeadId = l.Id;
                } else {
                    List<String> errMsgs = new List<String>();
                    for (Database.Error err : sr.getErrors()) {
                        errMsgs.add(err.getMessage());
                    }
                    response.put('success', false);
                    response.put('error', 'Insert failed: ' + String.join(errMsgs, ', '));
                    return response;
                }
            }

            /* ── 9. MC Journey trigger ────────────────────────────────────── */
            // System.enqueueJob(new AU_MCJourneyQueueable(finalLeadId));

            response.put('success',   true);
            response.put('leadId',    finalLeadId);
            response.put('duplicate', isDuplicate);
            response.put('brochureUrl', getBrochureUrl(submittedProgramme, programVal));

        } catch (DmlException dmlEx) {
            System.debug(LoggingLevel.ERROR,
                'AU_EnquiryFormController.createLead DML: ' + dmlEx.getMessage());
            response.put('success', false);
            response.put('error',
                'Unable to save your enquiry. Please call +91 79 6191 6191.');
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR,
                'AU_EnquiryFormController.createLead: ' + ex.getMessage());
            response.put('success', false);
            response.put('error', 'An unexpected error occurred. Please try again.');
        }

        return response;
    }

    /* ══════════════════════════════════════════════════════════════════════
       HELPER : findDuplicate
    ══════════════════════════════════════════════════════════════════════ */
    @TestVisible
    private static Lead findDuplicate(
        String deptCode,
        String emailVal,
        String phoneVal,
        String programVal,
        String rtName
    ) {
        if (String.isBlank(emailVal) || String.isBlank(phoneVal)) return null;

        Id rtId = null;
        if (String.isNotBlank(rtName)) {
            Map<String, Schema.RecordTypeInfo> rtMap =
                Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName();
            if (rtMap.containsKey(rtName)) rtId = rtMap.get(rtName).getRecordTypeId();
        }

        phoneVal = '91'+phoneVal;

        List<String> conditions = new List<String>{
            'Email       = :emailVal',
            'Phone       = :phoneVal'
        };
        if (rtId != null) conditions.add('RecordTypeId = :rtId');
        if (deptCode != 'UG' && String.isNotBlank(programVal)) {
            conditions.add('Preferred_Programme__c = :programVal');
        }

        System.debug('deptCode: ' + deptCode);
        System.debug('emailVal: ' + emailVal);
        System.debug('phoneVal: ' + phoneVal);
        System.debug('programVal: ' + programVal);
        System.debug('rtName: ' + rtName);

        String soql = 'SELECT Id, CreatedDate, Multi_Select_Lead_Source__c FROM Lead WHERE '
                    + String.join(conditions, ' AND ')
                    + ' ORDER BY CreatedDate ASC LIMIT 1';

                    System.debug(soql);

        List<Lead> matches = Database.query(soql);
        return matches.isEmpty() ? null : matches[0];
    }

    /* ══════════════════════════════════════════════════════════════════════
       HELPER : mergeIntoMaster — fully dynamic SELECT from schema
    ══════════════════════════════════════════════════════════════════════ */
    @TestVisible
    private static void mergeIntoMaster(
        Id masterLeadId,
        Map<String, Object> data,
        Map<String, Schema.SObjectField> leadSchema,
        String refNum
    ) {
        Set<String> ALWAYS_OVERWRITE = new Set<String>{
            'UTM_Source__c', 'UTM_Medium__c', 'UTM_Campaign__c',
            'UTM_Content__c', 'UTM_Term__c', 'Enquiry_Reference__c'
        };
        Set<String> NEVER_OVERWRITE = new Set<String>{
            'id', 'isconverted', 'converteddate', 'ownerid', 'createddate',
            'lastmodifieddate', 'systemmodstamp', 'createdbyid',
            'lastmodifiedbyid', 'masterrecordid', 'recordtypeid'
        };

        try {
            Set<String> fieldsToFetch = new Set<String>{ 'Id' };
            fieldsToFetch.addAll(ALWAYS_OVERWRITE);
            for (String k : data.keySet()) {
                String kLower = k.toLowerCase();
                if (NEVER_OVERWRITE.contains(kLower)) continue;
                if (!leadSchema.containsKey(kLower)) continue;
                if (leadSchema.get(kLower).getDescribe().isAccessible())
                    fieldsToFetch.add(k);
            }
            for (String nv : NEVER_OVERWRITE) {
                fieldsToFetch.remove(nv);
                fieldsToFetch.remove(nv.toUpperCase());
            }

            String dynSelect = 'SELECT '
                + String.join(new List<String>(fieldsToFetch), ', ')
                + ' FROM Lead WHERE Id = :masterLeadId LIMIT 1';
            List<Lead> results = Database.query(dynSelect);
            if (results.isEmpty()) return;
            Lead master = results[0];

            Boolean needsUpdate = false;
            for (String apiName : data.keySet()) {
                String apiLower = apiName.toLowerCase();
                if (NEVER_OVERWRITE.contains(apiLower)) continue;
                if (!leadSchema.containsKey(apiLower)) continue;
                if (!leadSchema.get(apiLower).getDescribe().isUpdateable()) continue;

                Object rawVal = data.get(apiName);
                if (rawVal == null) continue;
                String newStr = String.valueOf(rawVal).trim();
                if (String.isBlank(newStr)) continue;

                if (ALWAYS_OVERWRITE.contains(apiName)) {
                    try { master.put(apiName, newStr); needsUpdate = true; }
                    catch (Exception ex) {}
                } else {
                    Object existing = null;
                    try { existing = master.get(apiName); } catch (Exception ex) {}
                    if (existing == null || String.isBlank(String.valueOf(existing))) {
                        try { master.put(apiName, newStr); needsUpdate = true; }
                        catch (Exception ex) {}
                    }
                }
            }
            if (String.isNotBlank(refNum)
                    && leadSchema.containsKey('enquiry_reference__c')
                    && leadSchema.get('enquiry_reference__c').getDescribe().isUpdateable()) {
                master.put('Enquiry_Reference__c', refNum);
                needsUpdate = true;
            }
            if (needsUpdate) update master;
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR,
                'AU_EnquiryFormController.mergeIntoMaster: ' + ex.getMessage());
        }
    }

    /* ══════════════════════════════════════════════════════════════════════
       HELPER : verifyCaptcha
       ─────────────────────
       Calls the Google reCAPTCHA v3 siteverify API server-side.
       Returns true if the token is valid AND the score meets the threshold.

       SETUP REQUIRED:
       ─────────────────
       1. Create a Named Credential in Salesforce:
          Setup → Named Credentials → New
          Name:  GoogleReCaptcha
          URL:   https://www.google.com/recaptcha/api/siteverify
          Auth:  No Authentication (key is sent in POST body)

       2. Store your SECRET KEY in a Custom Setting or Custom Metadata:
          - Setup → Custom Settings → New (Protected) → RecaptchaSettings__c
          - Field: Secret_Key__c (Text 100, Protected)
          - Add a record with your secret key value

       3. Grant the Guest User callout permissions via Remote Site Settings:
          Setup → Remote Site Settings → New
          Remote Site URL: https://www.google.com
    ══════════════════════════════════════════════════════════════════════ */
    @TestVisible
    private static Boolean verifyCaptcha(String token, Decimal minScore) {
        /* If token is blank (reCAPTCHA script failed to load on client),
           skip verification and allow the submission through.
           You can change this to return false to block submissions
           when CAPTCHA is unavailable.                                   */
        if (String.isBlank(token)) {
            System.debug(LoggingLevel.WARN,
                'AU Form: captcha token blank — skipping verification (graceful degrade).');
            return true;
        }

        try {
            /* Read secret key from Custom Setting — never hardcode it */
            RecaptchaSettings__c settings = RecaptchaSettings__c.getOrgDefaults();
            String secretKey = settings != null ? settings.Secret_Key__c : '';

            if (String.isBlank(secretKey)) {
                System.debug(LoggingLevel.WARN,
                    'AU Form: RecaptchaSettings__c.Secret_Key__c is blank — skipping verification.');
                return true; // degrade gracefully if not configured yet
            }

            /* POST to Google siteverify endpoint via Named Credential */
            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:GoogleReCaptcha');
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
            req.setBody('secret=' + EncodingUtil.urlEncode(secretKey, 'UTF-8')
                      + '&response=' + EncodingUtil.urlEncode(token, 'UTF-8'));
            req.setTimeout(5000); // 5 second timeout

            HttpResponse res = new Http().send(req);

            if (res.getStatusCode() != 200) {
                System.debug(LoggingLevel.ERROR,
                    'AU Form: reCAPTCHA API returned status ' + res.getStatusCode());
                return true; // degrade gracefully on API error
            }

            /* Parse JSON response:
               { "success": true, "score": 0.9, "action": "submit_enquiry",
                 "challenge_ts": "...", "hostname": "..." }          */
            Map<String, Object> resp =
                (Map<String, Object>) JSON.deserializeUntyped(res.getBody());

            Boolean success = resp.containsKey('success')
                ? (Boolean) resp.get('success') : false;
            Decimal score   = resp.containsKey('score')
                ? Decimal.valueOf(String.valueOf(resp.get('score'))) : 0.0;
            String  action  = resp.containsKey('action')
                ? (String) resp.get('action') : '';

            System.debug(LoggingLevel.INFO,
                'AU Form: reCAPTCHA result — success:' + success
                + ' score:' + score + ' action:' + action);

            /* Verify: token must be valid AND score above threshold */
            return success && score >= minScore;

        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR,
                'AU Form: verifyCaptcha exception — ' + ex.getMessage());
            /* Degrade gracefully: allow submission if CAPTCHA check fails
               due to network/config error.                               */
            return true;
        }
    }

    private static String strVal(Map<String, Object> m, String key) {
        Object v = m.get(key);
        System.debug('strVal: ' + key + ' ' + v);
        return v != null ? String.valueOf(v).trim() : '';
    }

    @TestVisible
    private static String generateRefNum() {
        String year   = String.valueOf(Date.today().year());
        String suffix = String.valueOf(
            Math.abs(Math.mod(System.currentTimeMillis().intValue(), 90000)) + 10000
        );
        return 'AU-' + year + '-' + suffix;
    }
}