/**
 * ============================================================================
 * CLASS       : AU_FormAdminController
 * API VERSION : 60.0
 * DESCRIPTION : Controller for the Dynamic Form Admin Panel LWC (auFormAdminPanel).
 *               Provides schema describes, dashboard data, URL generation,
 *               and Metadata API deployment for Form_Config__mdt and
 *               Form_Field_Config__mdt.
 * ============================================================================
 */
public with sharing class AU_FormAdminController {

    public class DashboardDataWrapper {
        @AuraEnabled public List<Map<String, Object>> departments { get; set; }
        @AuraEnabled public List<Map<String, Object>> forms { get; set; }
        @AuraEnabled public List<Map<String, Object>> leadRecordTypes { get; set; }
        @AuraEnabled public List<Map<String, Object>> availableLeadFields { get; set; }
        @AuraEnabled public List<Map<String, String>> leadSourceOptions { get; set; }
        @AuraEnabled public String siteBaseUrl { get; set; }
        @AuraEnabled public Integer totalForms { get; set; }
        @AuraEnabled public Integer totalDepartments { get; set; }
        @AuraEnabled public Integer totalFields { get; set; }
    }

    public class FormFieldWrapper {
        @AuraEnabled public String developerName { get; set; }
        @AuraEnabled public String masterLabel { get; set; }
        @AuraEnabled public String departmentCode { get; set; }
        @AuraEnabled public String formCode { get; set; }
        @AuraEnabled public String sfApiName { get; set; }
        @AuraEnabled public String formLabel { get; set; }
        @AuraEnabled public String fieldType { get; set; }
        @AuraEnabled public Boolean isRequired { get; set; }
        @AuraEnabled public String placeholderText { get; set; }
        @AuraEnabled public String helpText { get; set; }
        @AuraEnabled public String fieldOptions { get; set; }
        @AuraEnabled public Boolean fullWidth { get; set; }
        @AuraEnabled public Boolean isNumeric { get; set; }
        @AuraEnabled public Boolean isInteger { get; set; }
        @AuraEnabled public Boolean isHidden { get; set; }
        @AuraEnabled public String defaultValue { get; set; }
        @AuraEnabled public Integer sortOrder { get; set; }
    }

    public class FormConfigWrapper {
        @AuraEnabled public String developerName { get; set; }
        @AuraEnabled public String masterLabel { get; set; }
        @AuraEnabled public String departmentCode { get; set; }
        @AuraEnabled public String formName { get; set; }
        @AuraEnabled public String formSubtitle { get; set; }
        @AuraEnabled public String formIcon { get; set; }
        @AuraEnabled public String formSlug { get; set; }
        @AuraEnabled public String sectionLabel { get; set; }
        @AuraEnabled public String leadRecordTypeName { get; set; }
        @AuraEnabled public String typeOfForm { get; set; }
        @AuraEnabled public Integer sortOrder { get; set; }
        @AuraEnabled public List<FormFieldWrapper> fields { get; set; }
    }

    /**
     * Fetches complete dashboard data including departments, forms, fields, record types, and site URL.
     */
    @AuraEnabled(cacheable=false)
    public static DashboardDataWrapper getDashboardData() {
        DashboardDataWrapper result = new DashboardDataWrapper();

        // 1. Fetch Departments
        List<Form_Department_Config__mdt> depts = [
            SELECT DeveloperName, MasterLabel, Icon_Emoji__c, Subtitle__c,
                   URL_Slugs__c, Lead_Record_Type_Name__c, Default_Lead_Source__c,
                   UTM_Source_Map__c, Sort_Order__c, TypeOfForm__c,
                   Contact_Email__c, Contact_Phone__c, Contact_Title__c
            FROM Form_Department_Config__mdt
            ORDER BY Sort_Order__c ASC NULLS LAST
        ];

        List<Map<String, Object>> deptList = new List<Map<String, Object>>();
        for (Form_Department_Config__mdt d : depts) {
            deptList.add(new Map<String, Object>{
                'developerName' => d.DeveloperName,
                'masterLabel'   => d.MasterLabel,
                'iconEmoji'     => d.Icon_Emoji__c,
                'subtitle'      => d.Subtitle__c,
                'urlSlugs'      => d.URL_Slugs__c,
                'leadRecordType'=> d.Lead_Record_Type_Name__c,
                'defaultSource' => d.Default_Lead_Source__c,
                'utmSourceMap'  => d.UTM_Source_Map__c,
                'sortOrder'     => d.Sort_Order__c,
                'typeOfForm'    => d.TypeOfForm__c,
                'contactEmail'  => d.Contact_Email__c,
                'contactPhone'  => d.Contact_Phone__c,
                'contactTitle'  => d.Contact_Title__c
            });
        }
        result.departments = deptList;
        result.totalDepartments = deptList.size();

        // 2. Fetch Form Configs
        List<Form_Config__mdt> formConfigs = [
            SELECT DeveloperName, MasterLabel, Department_Code__c, Form_Name__c,
                   Form_Subtitle__c, Form_Icon__c, Form_Slug__c, Section_Label__c,
                   Lead_Record_Type_Name__c, TypeOfForm__c, Sort_Order__c
            FROM Form_Config__mdt
            ORDER BY Department_Code__c ASC, Sort_Order__c ASC NULLS LAST
        ];

        // 3. Fetch All Field Configs
        List<Form_Field_Config__mdt> allFields = [
            SELECT DeveloperName, MasterLabel, Department_Code__c, Form_Code__c,
                   SF_API_Name__c, Form_Label__c, Field_Type__c, Is_Required__c,
                   Placeholder_Text__c, Help_Text__c, Field_Options__c,
                   Full_Width__c, Is_Numeric__c, Is_Integer__c, Sort_Order__c,
                   Is_Hidden__c, Default_Value__c
            FROM Form_Field_Config__mdt
            ORDER BY Department_Code__c ASC, Sort_Order__c ASC NULLS LAST
        ];
        result.totalFields = allFields.size();

        // Group fields by composite key: DEPT|FORM
        Map<String, List<Map<String, Object>>> fieldsByFormKey = new Map<String, List<Map<String, Object>>>();
        for (Form_Field_Config__mdt f : allFields) {
            String dCode = f.Department_Code__c != null ? f.Department_Code__c.toUpperCase() : '';
            String fCode = String.isNotBlank(f.Form_Code__c) ? f.Form_Code__c.toUpperCase() : '';
            String key = dCode + '|' + fCode;

            if (!fieldsByFormKey.containsKey(key)) {
                fieldsByFormKey.put(key, new List<Map<String, Object>>());
            }

            fieldsByFormKey.get(key).add(new Map<String, Object>{
                'developerName'  => f.DeveloperName,
                'masterLabel'    => f.MasterLabel,
                'departmentCode' => f.Department_Code__c,
                'formCode'       => f.Form_Code__c,
                'sfApiName'      => f.SF_API_Name__c,
                'formLabel'      => f.Form_Label__c,
                'fieldType'      => f.Field_Type__c,
                'isRequired'     => f.Is_Required__c == true,
                'placeholderText'=> f.Placeholder_Text__c,
                'helpText'       => f.Help_Text__c,
                'fieldOptions'   => f.Field_Options__c,
                'fullWidth'      => f.Full_Width__c == true,
                'isNumeric'      => f.Is_Numeric__c == true,
                'isInteger'      => f.Is_Integer__c == true,
                'isHidden'       => f.Is_Hidden__c == true,
                'defaultValue'   => f.Default_Value__c,
                'sortOrder'      => f.Sort_Order__c
            });
        }

        // Build Forms List with Attached Fields
        List<Map<String, Object>> formList = new List<Map<String, Object>>();
        for (Form_Config__mdt fc : formConfigs) {
            String dCode = fc.Department_Code__c != null ? fc.Department_Code__c.toUpperCase() : '';
            String slugCode = fc.Form_Slug__c != null ? fc.Form_Slug__c.toUpperCase() : '';
            String devNameUpper = fc.DeveloperName != null ? fc.DeveloperName.toUpperCase() : '';

            // Fields can match on Form_Slug or DeveloperName or blank (shared)
            List<Map<String, Object>> specificFields = new List<Map<String, Object>>();
            if (fieldsByFormKey.containsKey(dCode + '|' + slugCode)) {
                specificFields.addAll(fieldsByFormKey.get(dCode + '|' + slugCode));
            } else if (fieldsByFormKey.containsKey(dCode + '|' + devNameUpper)) {
                specificFields.addAll(fieldsByFormKey.get(dCode + '|' + devNameUpper));
            }

            // Also check for shared dept fields
            List<Map<String, Object>> sharedFields = fieldsByFormKey.containsKey(dCode + '|')
                ? fieldsByFormKey.get(dCode + '|') : new List<Map<String, Object>>();

            // Merge unique by sfApiName
            Map<String, Map<String, Object>> combinedFields = new Map<String, Map<String, Object>>();
            for (Map<String, Object> sf : specificFields) {
                String api = (String) sf.get('sfApiName');
                if (String.isNotBlank(api)) combinedFields.put(api, sf);
            }
            for (Map<String, Object> shf : sharedFields) {
                String api = (String) shf.get('sfApiName');
                if (String.isNotBlank(api) && !combinedFields.containsKey(api)) {
                    combinedFields.put(api, shf);
                }
            }

            formList.add(new Map<String, Object>{
                'developerName'     => fc.DeveloperName,
                'masterLabel'       => fc.MasterLabel,
                'departmentCode'    => fc.Department_Code__c,
                'formName'          => fc.Form_Name__c,
                'formSubtitle'      => fc.Form_Subtitle__c,
                'formIcon'          => fc.Form_Icon__c,
                'formSlug'          => fc.Form_Slug__c,
                'sectionLabel'      => fc.Section_Label__c,
                'leadRecordTypeName'=> fc.Lead_Record_Type_Name__c,
                'typeOfForm'        => fc.TypeOfForm__c,
                'sortOrder'         => fc.Sort_Order__c,
                'fields'            => combinedFields.values(),
                'fieldCount'        => combinedFields.size()
            });
        }
        result.forms = formList;
        result.totalForms = formList.size();

        // 4. Record Types & Lead Fields
        result.leadRecordTypes = getLeadRecordTypes();
        result.availableLeadFields = getLeadFieldsDescribe();
        result.leadSourceOptions = getLeadSourceOptions();
        result.siteBaseUrl = getSiteBaseUrl();

        return result;
    }

    /**
     * Retrieves active LeadSource picklist values.
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getLeadSourceOptions() {
        List<Map<String, String>> sourceList = new List<Map<String, String>>();
        for (Schema.PicklistEntry pe : Schema.SObjectType.Lead.fields.LeadSource.getPicklistValues()) {
            if (pe.isActive()) {
                sourceList.add(new Map<String, String>{
                    'label' => pe.getLabel(),
                    'value' => pe.getValue()
                });
            }
        }
        return sourceList;
    }

    /**
     * Describes the Lead object schema to return all eligible fields for the visual form builder.
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getLeadFieldsDescribe() {
        List<Map<String, Object>> fields = new List<Map<String, Object>>();
        Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Lead.fields.getMap();

        Set<String> EXCLUDED_FIELDS = new Set<String>{
            'id', 'isdeleted', 'masterrecordid', 'isconverted', 'converteddate',
            'convertedaccountid', 'convertedcontactid', 'convertedopportunityid',
            'createddate', 'createdbyid', 'lastmodifieddate', 'lastmodifiedbyid',
            'systemmodstamp', 'lastactivitydate', 'lastvieweddate', 'lastreferenceddate',
            'jigsaw', 'jigsawcontactid', 'cleanstatus', 'photourl', 'dandbcompanyid'
        };

        for (String fieldName : fieldMap.keySet()) {
            if (EXCLUDED_FIELDS.contains(fieldName)) continue;

            Schema.DescribeFieldResult dfr = fieldMap.get(fieldName).getDescribe();
            if (!dfr.isAccessible()) continue;

            String displayType = String.valueOf(dfr.getType()).toLowerCase();
            List<Map<String, String>> picklistValues = new List<Map<String, String>>();

            if (displayType == 'picklist' || displayType == 'multipicklist') {
                for (Schema.PicklistEntry pe : dfr.getPicklistValues()) {
                    if (pe.isActive()) {
                        picklistValues.add(new Map<String, String>{
                            'label' => pe.getLabel(),
                            'value' => pe.getValue()
                        });
                    }
                }
            }

            fields.add(new Map<String, Object>{
                'apiName'       => dfr.getName(),
                'label'         => dfr.getLabel(),
                'type'          => displayType,
                'isCustom'      => dfr.isCustom(),
                'isNillable'    => dfr.isNillable(),
                'inlineHelp'    => dfr.getInlineHelpText(),
                'picklistValues'=> picklistValues,
                'length'        => dfr.getLength()
            });
        }

        return fields;
    }

    /**
     * Async query to fetch lead submission counts grouped by form/campaign/leadSource.
     * Lightweight and fast aggregate query designed to be called asynchronously.
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Integer> getLeadCountsByForm() {
        Map<String, Integer> counts = new Map<String, Integer>();
        
        try {
            // 1. Group by TypeOfForm__c
            for (AggregateResult ar : [
                SELECT TypeOfForm__c tof, count(Id) cnt 
                FROM Lead 
                WHERE TypeOfForm__c != null 
                GROUP BY TypeOfForm__c
            ]) {
                String tof = String.valueOf(ar.get('tof')).toLowerCase().trim();
                Integer cnt = (Integer) ar.get('cnt');
                counts.put(tof, cnt);
            }

            // 2. Group by UTM_Campaign__c
            for (AggregateResult ar : [
                SELECT UTM_Campaign__c camp, count(Id) cnt 
                FROM Lead 
                WHERE UTM_Campaign__c != null 
                GROUP BY UTM_Campaign__c
            ]) {
                String camp = String.valueOf(ar.get('camp')).toLowerCase().trim();
                Integer cnt = (Integer) ar.get('cnt');
                if (counts.containsKey(camp)) {
                    counts.put(camp, counts.get(camp) + cnt);
                } else {
                    counts.put(camp, cnt);
                }
            }

            // 3. Group by LeadSource
            for (AggregateResult ar : [
                SELECT LeadSource src, count(Id) cnt 
                FROM Lead 
                WHERE LeadSource != null 
                GROUP BY LeadSource
            ]) {
                String src = String.valueOf(ar.get('src')).toLowerCase().trim();
                Integer cnt = (Integer) ar.get('cnt');
                if (!counts.containsKey(src)) {
                    counts.put(src, cnt);
                }
            }
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Error querying lead counts: ' + ex.getMessage());
        }

        return counts;
    }

    /**
     * Returns active Record Types for Lead.
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getLeadRecordTypes() {
        List<Map<String, Object>> rtList = new List<Map<String, Object>>();
        for (Schema.RecordTypeInfo rti : Schema.SObjectType.Lead.getRecordTypeInfos()) {
            if (rti.isActive() && !rti.isMaster()) {
                rtList.add(new Map<String, Object>{
                    'label'         => rti.getName(),
                    'developerName' => rti.getDeveloperName(),
                    'recordTypeId'  => rti.getRecordTypeId()
                });
            }
        }
        return rtList;
    }

    /**
     * Resolves the public site base URL for Admission Form using SiteDetail or DomainSite.
     */
    @AuraEnabled(cacheable=true)
    public static String getSiteBaseUrl() {
        try {
            List<Site> sites = [
                SELECT Id, Subdomain, UrlPathPrefix 
                FROM Site 
                WHERE Name = 'Admission_Form' 
                LIMIT 1
            ];
            if (!sites.isEmpty()) {
                // 1. Query SiteDetail SecureUrl (exact public site URL)
                List<SiteDetail> details = [
                    SELECT SecureUrl 
                    FROM SiteDetail 
                    WHERE DurableId = :sites[0].Id 
                    LIMIT 1
                ];
                if (!details.isEmpty() && String.isNotBlank(details[0].SecureUrl)) {
                    return details[0].SecureUrl;
                }

                // 2. Query DomainSite fallback
                List<DomainSite> domainSites = [
                    SELECT Domain.Domain, PathPrefix 
                    FROM DomainSite 
                    WHERE SiteId = :sites[0].Id 
                    LIMIT 1
                ];
                if (!domainSites.isEmpty() && domainSites[0].Domain != null) {
                    String domain = domainSites[0].Domain.Domain;
                    String prefix = domainSites[0].PathPrefix != null ? domainSites[0].PathPrefix : '/admissions';
                    if (!prefix.startsWith('/')) prefix = '/' + prefix;
                    return 'https://' + domain + prefix;
                }

                String prefix = sites[0].UrlPathPrefix != null ? '/' + sites[0].UrlPathPrefix : '/admissions';
                String domain = Url.getOrgDomainUrl().toExternalForm();
                return domain + prefix;
            }
        } catch (Exception ex) {
            System.debug('Error querying site base url: ' + ex.getMessage());
        }
        return '/admissions';
    }

    /**
     * Helper to sanitize DeveloperNames for Custom Metadata.
     * Must be alphanumeric and single underscores, <= 40 chars, cannot start with number or end with underscore.
     */
    private static String sanitizeDeveloperName(String input, String fallback) {
        if (String.isBlank(input)) input = fallback;
        String s = input.replaceAll('[^a-zA-Z0-9_]', '_');
        if (Pattern.matches('^[0-9].*', s)) {
            s = 'X' + s;
        }
        s = s.replaceAll('_{2,}', '_');
        s = s.replaceAll('^_|_$', '');
        if (String.isBlank(s)) s = fallback;
        if (s.length() > 40) {
            s = s.substring(0, 40);
            s = s.replaceAll('_+$', '');
        }
        return s;
    }

    /**
     * Generates a unique, compliant DeveloperName for Form_Field_Config Custom Metadata (max 40 chars).
     * Guarantees that even with long form names or similar field names, no duplicate or >40 char names are generated.
     */
    private static String generateFieldDeveloperName(String existingDevName, String formCode, String sfApiName, Set<String> usedNames) {
        if (String.isNotBlank(existingDevName)) {
            String sanitized = sanitizeDeveloperName(existingDevName, 'FM_FIELD');
            if (sanitized.length() > 40) {
                sanitized = sanitized.substring(0, 40).replaceAll('_+$', '');
            }
            if (!usedNames.contains(sanitized.toUpperCase())) {
                usedNames.add(sanitized.toUpperCase());
                return sanitized;
            }
        }

        // Clean formCode (budget up to 14 chars)
        String cleanForm = sanitizeDeveloperName(formCode, 'FORM');
        if (cleanForm.length() > 14) {
            cleanForm = cleanForm.substring(0, 14).replaceAll('_+$', '');
        }

        // Clean sfApiName (budget up to 18 chars, strip __c / __r)
        String rawApi = sfApiName != null ? sfApiName : 'FIELD';
        rawApi = rawApi.replaceAll('(?i)__c$|__r$', '');
        String cleanApi = sanitizeDeveloperName(rawApi, 'FIELD');
        if (cleanApi.length() > 18) {
            cleanApi = cleanApi.substring(0, 18).replaceAll('_+$', '');
        }

        String baseName = 'FM_' + cleanForm + '_' + cleanApi;
        baseName = sanitizeDeveloperName(baseName, 'FM_FIELD');
        if (baseName.length() > 35) {
            baseName = baseName.substring(0, 35).replaceAll('_+$', '');
        }

        String candidate = baseName;
        Integer counter = 1;
        while (usedNames.contains(candidate.toUpperCase())) {
            String suffix = '_' + counter;
            Integer maxBaseLen = 40 - suffix.length();
            String truncatedBase = baseName.length() > maxBaseLen 
                ? baseName.substring(0, maxBaseLen).replaceAll('_+$', '') 
                : baseName;
            candidate = truncatedBase + suffix;
            counter++;
        }

        usedNames.add(candidate.toUpperCase());
        return candidate;
    }

    /**
     * Resolves a valid API session ID, using Visualforce context if in Lightning Experience.
     */
    public static String getApiSessionId() {
        if (Test.isRunningTest()) {
            return 'TEST_SESSION_ID';
        }
        try {
            PageReference sessionPage = Page.AU_SessionHelper;
            String content = sessionPage.getContent().toString().trim();
            if (String.isNotBlank(content)) {
                return content;
            }
        } catch (Exception ex) {
            System.debug(LoggingLevel.WARN, 'AU_FormAdminController: Could not get VF session ID: ' + ex.getMessage());
        }
        return UserInfo.getSessionId();
    }

    /**
     * Executes synchronous deletion of Custom Metadata records via Metadata API SOAP callout.
     */
    public static Boolean deleteMetadataRecords(List<String> fullNamesToDelete) {
        if (fullNamesToDelete == null || fullNamesToDelete.isEmpty() || Test.isRunningTest()) {
            return true;
        }

        try {
            String fullNamesXml = '';
            for (String fn : fullNamesToDelete) {
                if (String.isBlank(fn)) continue;
                String cleanFn = fn.trim();
                // SOAP Metadata API expects type: CustomMetadata and fullName: TypeName.RecordDeveloperName (without __mdt)
                cleanFn = cleanFn.replace('__mdt.', '.');
                cleanFn = cleanFn.replace('__c.', '.');
                if (!cleanFn.contains('.')) {
                    cleanFn = 'Form_Field_Config.' + cleanFn;
                }
                fullNamesXml += '<met:fullNames>' + cleanFn + '</met:fullNames>';
            }

            if (String.isBlank(fullNamesXml)) {
                return true;
            }

            String sessionId = getApiSessionId();

            String soapBody = '<?xml version="1.0" encoding="utf-8"?>' +
                '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:met="http://soap.sforce.com/2006/04/metadata">' +
                '  <soapenv:Header>' +
                '    <met:SessionHeader>' +
                '      <met:sessionId>' + sessionId + '</met:sessionId>' +
                '    </met:SessionHeader>' +
                '  </soapenv:Header>' +
                '  <soapenv:Body>' +
                '    <met:deleteMetadata>' +
                '      <met:type>CustomMetadata</met:type>' +
                fullNamesXml +
                '    </met:deleteMetadata>' +
                '  </soapenv:Body>' +
                '</soapenv:Envelope>';

            HttpRequest req = new HttpRequest();
            req.setEndpoint(Url.getOrgDomainUrl().toExternalForm() + '/services/Soap/m/60.0');
            req.setMethod('POST');
            req.setHeader('Content-Type', 'text/xml');
            req.setHeader('SOAPAction', '""');
            req.setBody(soapBody);
            req.setTimeout(60000);

            Http http = new Http();
            HttpResponse res = http.send(req);

            System.debug('deleteMetadataRecords Status: ' + res.getStatusCode() + ' | Body: ' + res.getBody());

            if (res.getStatusCode() == 200 && !res.getBody().contains('<faultcode>')) {
                return true;
            } else {
                System.debug(LoggingLevel.ERROR, 'deleteMetadataRecords failed: ' + res.getBody());
                return false;
            }
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'deleteMetadataRecords error: ' + ex.getMessage() + '\n' + ex.getStackTraceString());
            return false;
        }
    }

    /**
     * Saves or Updates a Form and its associated Fields by building and enqueuing a Metadata Deployment.
     * Also detects any previously configured fields that were removed by the user and deletes them.
     */
    @AuraEnabled
    public static Map<String, Object> saveForm(String formJSON, String fieldsJSON) {
        Map<String, Object> response = new Map<String, Object>();

        try {
            FormConfigWrapper formConfig = (FormConfigWrapper) JSON.deserialize(formJSON, FormConfigWrapper.class);
            List<FormFieldWrapper> fields = (List<FormFieldWrapper>) JSON.deserialize(fieldsJSON, List<FormFieldWrapper>.class);

            String cleanSlug = sanitizeDeveloperName(formConfig.formSlug, 'FORM');
            String dept = sanitizeDeveloperName(formConfig.departmentCode, 'DEPT');

            if (String.isBlank(formConfig.developerName)) {
                formConfig.developerName = dept + '_' + cleanSlug;
            }
            formConfig.developerName = sanitizeDeveloperName(formConfig.developerName, dept + '_FORM');

            // Ensure TypeOfForm__c defaults to Admission_Form
            if (String.isBlank(formConfig.typeOfForm)) {
                formConfig.typeOfForm = 'Admission_Form';
            }

            // Auto-resolve Lead Record Type from Department if blank
            if (String.isBlank(formConfig.leadRecordTypeName) && String.isNotBlank(formConfig.departmentCode)) {
                List<Form_Department_Config__mdt> depts = [
                    SELECT Lead_Record_Type_Name__c 
                    FROM Form_Department_Config__mdt 
                    WHERE DeveloperName = :formConfig.departmentCode 
                    LIMIT 1
                ];
                if (!depts.isEmpty() && String.isNotBlank(depts[0].Lead_Record_Type_Name__c)) {
                    formConfig.leadRecordTypeName = depts[0].Lead_Record_Type_Name__c;
                }
            }

            String formCodeForFields = String.isNotBlank(formConfig.formSlug) ? formConfig.formSlug.toUpperCase() : formConfig.developerName.toUpperCase();
            String slugUpper = String.isNotBlank(formConfig.formSlug) ? formConfig.formSlug.toUpperCase() : '';
            String slugLower = String.isNotBlank(formConfig.formSlug) ? formConfig.formSlug.toLowerCase() : '';
            String devUpper = formConfig.developerName != null ? formConfig.developerName.toUpperCase() : '';
            String devLower = formConfig.developerName != null ? formConfig.developerName.toLowerCase() : '';
            String cleanSlugUpper = cleanSlug.toUpperCase();
            String cleanDevUpper = sanitizeDeveloperName(formConfig.developerName, 'FORM').toUpperCase();

            // 1. Detect any removed fields in database to delete
            Set<String> formCodeMatches = new Set<String>{
                formConfig.formSlug,
                slugLower,
                slugUpper,
                formConfig.developerName,
                devUpper,
                devLower,
                cleanSlug,
                cleanSlugUpper,
                cleanDevUpper,
                formCodeForFields
            };
            formCodeMatches.remove(null);
            formCodeMatches.remove('');

            List<Form_Field_Config__mdt> existingFieldsInDb = [
                SELECT Id, DeveloperName, SF_API_Name__c, Form_Code__c, Department_Code__c 
                FROM Form_Field_Config__mdt 
                WHERE Form_Code__c IN :formCodeMatches
            ];

            Set<String> usedDevNamesInBatch = new Set<String>();
            Set<String> incomingDevNames = new Set<String>();
            Set<String> incomingApiNames = new Set<String>();

            for (FormFieldWrapper f : fields) {
                if (String.isBlank(f.sfApiName)) continue;
                
                f.developerName = generateFieldDeveloperName(f.developerName, formCodeForFields, f.sfApiName, usedDevNamesInBatch);
                incomingDevNames.add(f.developerName.toUpperCase());
                incomingApiNames.add(f.sfApiName.toLowerCase().trim());
            }

            List<String> fieldFullNamesToDelete = new List<String>();
            for (Form_Field_Config__mdt existing : existingFieldsInDb) {
                String exDev = existing.DeveloperName.toUpperCase();
                String exApi = existing.SF_API_Name__c != null ? existing.SF_API_Name__c.toLowerCase().trim() : '';

                if (!incomingDevNames.contains(exDev) && !incomingApiNames.contains(exApi)) {
                    fieldFullNamesToDelete.add('Form_Field_Config.' + existing.DeveloperName);
                }
            }

            if (!fieldFullNamesToDelete.isEmpty()) {
                deleteMetadataRecords(fieldFullNamesToDelete);
            }

            Metadata.DeployContainer mdContainer = new Metadata.DeployContainer();

            // 2. Build Form_Config__mdt Record
            Metadata.CustomMetadata formMeta = new Metadata.CustomMetadata();
            formMeta.fullName = 'Form_Config__mdt.' + formConfig.developerName;
            formMeta.label = String.isNotBlank(formConfig.masterLabel) ? formConfig.masterLabel : formConfig.formName;
            if (formMeta.label != null && formMeta.label.length() > 40) {
                formMeta.label = formMeta.label.substring(0, 40);
            }

            addMetadataValue(formMeta, 'Department_Code__c', formConfig.departmentCode);
            addMetadataValue(formMeta, 'Form_Name__c', formConfig.formName);
            addMetadataValue(formMeta, 'Form_Subtitle__c', formConfig.formSubtitle);
            addMetadataValue(formMeta, 'Form_Icon__c', String.isNotBlank(formConfig.formIcon) ? formConfig.formIcon : '📋');
            addMetadataValue(formMeta, 'Form_Slug__c', formConfig.formSlug != null ? formConfig.formSlug.toLowerCase() : '');
            addMetadataValue(formMeta, 'Section_Label__c', formConfig.sectionLabel);
            addMetadataValue(formMeta, 'Lead_Record_Type_Name__c', formConfig.leadRecordTypeName);
            addMetadataValue(formMeta, 'TypeOfForm__c', formConfig.typeOfForm);
            if (formConfig.sortOrder != null) {
                addMetadataValue(formMeta, 'Sort_Order__c', Decimal.valueOf(formConfig.sortOrder));
            }

            mdContainer.addMetadata(formMeta);

            // 3. Build Form_Field_Config__mdt Records
            Integer sortIndex = 1;

            for (FormFieldWrapper f : fields) {
                if (String.isBlank(f.sfApiName)) continue;

                String fieldDevName = f.developerName;

                Metadata.CustomMetadata fieldMeta = new Metadata.CustomMetadata();
                fieldMeta.fullName = 'Form_Field_Config__mdt.' + fieldDevName;
                fieldMeta.label = String.isNotBlank(f.masterLabel) ? f.masterLabel : (String.isNotBlank(f.formLabel) ? f.formLabel : fieldDevName);
                if (fieldMeta.label != null && fieldMeta.label.length() > 40) {
                    fieldMeta.label = fieldMeta.label.substring(0, 40);
                }

                addMetadataValue(fieldMeta, 'Department_Code__c', formConfig.departmentCode);
                addMetadataValue(fieldMeta, 'Form_Code__c', formCodeForFields);
                addMetadataValue(fieldMeta, 'SF_API_Name__c', f.sfApiName);
                addMetadataValue(fieldMeta, 'Form_Label__c', f.formLabel);
                addMetadataValue(fieldMeta, 'Field_Type__c', f.fieldType);
                addMetadataValue(fieldMeta, 'Is_Required__c', f.isRequired == true);
                addMetadataValue(fieldMeta, 'Placeholder_Text__c', f.placeholderText);
                addMetadataValue(fieldMeta, 'Help_Text__c', f.helpText);
                addMetadataValue(fieldMeta, 'Field_Options__c', f.fieldOptions);
                addMetadataValue(fieldMeta, 'Full_Width__c', f.fullWidth == true);
                addMetadataValue(fieldMeta, 'Is_Numeric__c', f.isNumeric == true);
                addMetadataValue(fieldMeta, 'Is_Integer__c', f.isInteger == true);
                addMetadataValue(fieldMeta, 'Is_Hidden__c', f.isHidden == true);
                addMetadataValue(fieldMeta, 'Default_Value__c', f.defaultValue);
                addMetadataValue(fieldMeta, 'Sort_Order__c', Decimal.valueOf(f.sortOrder != null ? f.sortOrder : sortIndex));

                mdContainer.addMetadata(fieldMeta);
                sortIndex++;
            }

            // 4. Enqueue Metadata Deployment
            Id asyncResultId = null;
            if (!Test.isRunningTest()) {
                asyncResultId = Metadata.Operations.enqueueDeployment(mdContainer, new AU_FormAdminDeployCallback());
            }

            response.put('success', true);
            response.put('asyncResultId', asyncResultId);
            response.put('formDeveloperName', formConfig.developerName);
            response.put('formSlug', formConfig.formSlug);
            response.put('message', 'Form and fields packaged and queued for deployment successfully.');

        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'AU_FormAdminController.saveForm Error: ' + ex.getMessage() + '\n' + ex.getStackTraceString());
            response.put('success', false);
            response.put('error', ex.getMessage());
        }

        return response;
    }

    /**
     * Deletes a Form_Config__mdt record and all associated Form_Field_Config__mdt records using Metadata API SOAP callout.
     */
    @AuraEnabled
    public static Map<String, Object> deleteForm(String formDeveloperName, String formSlug, String departmentCode) {
        Map<String, Object> response = new Map<String, Object>();
        try {
            if (String.isBlank(formDeveloperName)) {
                response.put('success', false);
                response.put('error', 'Form Developer Name is required for deletion.');
                return response;
            }

            List<String> fullNamesToDelete = new List<String>();
            fullNamesToDelete.add('Form_Config.' + formDeveloperName);

            // Find any form-specific field configs
            String cleanSlug = sanitizeDeveloperName(formSlug, 'FORM');
            String slugUpper = String.isNotBlank(formSlug) ? formSlug.toUpperCase() : '';
            String slugLower = String.isNotBlank(formSlug) ? formSlug.toLowerCase() : '';
            String devUpper = formDeveloperName != null ? formDeveloperName.toUpperCase() : '';

            Set<String> formCodes = new Set<String>{
                formSlug,
                slugUpper,
                slugLower,
                cleanSlug,
                cleanSlug.toUpperCase(),
                formDeveloperName,
                devUpper
            };
            formCodes.remove(null);
            formCodes.remove('');

            List<Form_Field_Config__mdt> fields = [
                SELECT DeveloperName, Form_Code__c 
                FROM Form_Field_Config__mdt 
                WHERE Form_Code__c IN :formCodes
            ];

            for (Form_Field_Config__mdt f : fields) {
                fullNamesToDelete.add('Form_Field_Config.' + f.DeveloperName);
            }

            Boolean success = deleteMetadataRecords(fullNamesToDelete);

            if (success) {
                response.put('success', true);
                response.put('message', 'Form and associated fields deleted successfully.');
            } else {
                response.put('success', false);
                response.put('error', 'Failed to delete metadata records.');
            }
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'deleteForm error: ' + ex.getMessage() + '\n' + ex.getStackTraceString());
            response.put('success', false);
            response.put('error', ex.getMessage());
        }
        return response;
    }

    /**
     * Programme -> brochure list for the Programme Brochures screen. Programmes come from the
     * programme dropdown options of every form field config; saved brochure links are merged in.
     * Saved records whose programme is no longer in any dropdown are still returned so they stay editable.
     */
    @AuraEnabled
    public static List<Map<String, Object>> getProgrammeBrochures() {
        Map<String, Map<String, Object>> byKey = new Map<String, Map<String, Object>>();

        for (Form_Field_Config__mdt f : [
            SELECT Department_Code__c, Field_Options__c, Field_Type__c, SF_API_Name__c
            FROM Form_Field_Config__mdt
        ]) {
            if (String.isBlank(f.Field_Options__c)) continue;
            if (f.Field_Type__c != 'programme_picklist' && f.SF_API_Name__c != 'Preferred_Programme__c') continue;
            for (String line : f.Field_Options__c.split('\n')) {
                String name = line.trim();
                if (String.isBlank(name)) continue;
                String key = name.toLowerCase();
                if (!byKey.containsKey(key)) {
                    byKey.put(key, new Map<String, Object>{
                        'programmeName'  => name,
                        'departmentCode' => f.Department_Code__c,
                        'brochureUrl'    => null,
                        'developerName'  => null
                    });
                }
            }
        }

        for (Programme_Brochure__mdt b : [
            SELECT DeveloperName, Programme_Name__c, Brochure_URL__c FROM Programme_Brochure__mdt
        ]) {
            if (String.isBlank(b.Programme_Name__c)) continue;
            String key = b.Programme_Name__c.trim().toLowerCase();
            Map<String, Object> row = byKey.get(key);
            if (row == null) {
                row = new Map<String, Object>{
                    'programmeName'  => b.Programme_Name__c.trim(),
                    'departmentCode' => ''
                };
                byKey.put(key, row);
            }
            row.put('brochureUrl', b.Brochure_URL__c);
            row.put('developerName', b.DeveloperName);
        }

        List<Map<String, Object>> rows = byKey.values();
        rows.sort(new ProgrammeRowComparator());
        return rows;
    }

    public class ProgrammeRowComparator implements System.Comparator<Map<String, Object>> {
        public Integer compare(Map<String, Object> a, Map<String, Object> b) {
            String ka = String.valueOf(a.get('departmentCode')) + '|' + String.valueOf(a.get('programmeName'));
            String kb = String.valueOf(b.get('departmentCode')) + '|' + String.valueOf(b.get('programmeName'));
            return ka.compareTo(kb);
        }
    }

    /**
     * Saves brochure links. Input JSON: [{programmeName, brochureUrl, developerName}].
     * Only rows with a link (or an existing record being cleared) are deployed. Links must be https.
     */
    @AuraEnabled
    public static Map<String, Object> saveProgrammeBrochures(String rowsJSON) {
        Map<String, Object> response = new Map<String, Object>();
        try {
            List<Object> rows = (List<Object>) JSON.deserializeUntyped(rowsJSON);
            Metadata.DeployContainer container = new Metadata.DeployContainer();
            Integer count = 0;
            Set<String> usedDevNames = new Set<String>();

            for (Object o : rows) {
                Map<String, Object> r = (Map<String, Object>) o;
                String name = r.get('programmeName') == null ? '' : String.valueOf(r.get('programmeName')).trim();
                String url  = r.get('brochureUrl') == null ? '' : String.valueOf(r.get('brochureUrl')).trim();
                String dev  = r.get('developerName') == null ? '' : String.valueOf(r.get('developerName')).trim();
                if (String.isBlank(name)) continue;
                if (String.isBlank(url) && String.isBlank(dev)) continue;
                if (String.isNotBlank(url) && !url.startsWithIgnoreCase('https://')) {
                    response.put('success', false);
                    response.put('error', 'Brochure link for "' + name + '" must start with https://');
                    return response;
                }
                if (String.isBlank(dev)) {
                    String base = sanitizeDeveloperName(name, 'Programme');
                    if (base.length() > 26) base = base.substring(0, 26).replaceAll('_+$', '');
                    dev = 'PB_' + base + '_' + String.valueOf(Math.mod(Math.abs(name.toLowerCase().hashCode()), 1000000));
                }
                if (!usedDevNames.add(dev)) continue;

                Metadata.CustomMetadata md = new Metadata.CustomMetadata();
                md.fullName = 'Programme_Brochure__mdt.' + dev;
                md.label = name.length() > 40 ? name.substring(0, 40) : name;
                addMetadataValue(md, 'Programme_Name__c', name);
                addMetadataValue(md, 'Brochure_URL__c', url);
                container.addMetadata(md);
                count++;
            }

            if (count == 0) {
                response.put('success', true);
                response.put('message', 'Nothing to save.');
                return response;
            }

            Id asyncResultId = null;
            if (!Test.isRunningTest()) {
                asyncResultId = Metadata.Operations.enqueueDeployment(container, new AU_FormAdminDeployCallback());
            }
            response.put('success', true);
            response.put('asyncResultId', asyncResultId);
            response.put('count', count);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'AU_FormAdminController.saveProgrammeBrochures Error: ' + ex.getMessage());
            response.put('success', false);
            response.put('error', ex.getMessage());
        }
        return response;
    }

    private static void addMetadataValue(Metadata.CustomMetadata md, String fieldName, Object val) {
        if (val == null) return;
        Metadata.CustomMetadataValue customValue = new Metadata.CustomMetadataValue();
        customValue.field = fieldName;
        customValue.value = val;
        md.values.add(customValue);
    }

    /**
     * Callback handler for Metadata Deployments.
     */
    public class AU_FormAdminDeployCallback implements Metadata.DeployCallback {
        public void handleResult(Metadata.DeployResult result, Metadata.DeployCallbackContext context) {
            if (result.status == Metadata.DeployStatus.Succeeded) {
                System.debug('AU Form Admin: Custom Metadata Deployment Succeeded: ' + result.id);
            } else {
                System.debug(LoggingLevel.ERROR, 'AU Form Admin: Custom Metadata Deployment Failed: ' + result.errorMessage);
            }
        }
    }
}