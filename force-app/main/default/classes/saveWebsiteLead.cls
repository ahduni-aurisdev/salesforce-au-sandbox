/**
 * ****************************************************************************************
 * Class Name   : saveWebsiteLead
 * Created By   : Preksha Chauhan
 * Company      : GetonCRM Solutions
 * Created Date : 06/25/2024
 * Description  : This class provides RESTful API endpoints for creating Lead records in
 *                Salesforce. It handles parsing JSON request bodies, validating required
 *                fields, checking for duplicate leads, retrieving record type IDs based on
 *                department, mapping fields from JSON to Lead objects, and handling custom
 *                exceptions and error responses.
 * ****************************************************************************************
 */
@RestResource(urlMapping='/saveLead/*')
global with sharing class saveWebsiteLead {

    /**
     * ****************************************************************************************
     * Method Name   : saveLead
     * Created By    : Preksha Chauhan
     * Created Date  : 06/25/2024
     * Modified Date : 06/26/2024
     * Description   : Handles the HTTP POST request to create a new Lead record. Parses the
     *                 JSON request body, determines the department (Masters or UG), and calls
     *                 the appropriate method for lead creation. Returns an appropriate error
     *                 response if any issues occur during processing.
     * ****************************************************************************************
     */
    @HttpPost
    global static void saveLead() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        String department;
        try {
            // Parse the JSON request body
            String requestBody = req.requestBody.toString();
            System.debug('Incoming JSON Body: ' + requestBody);
            Map<String, Object> params = (Map<String, Object>) JSON.deserializeUntyped(requestBody);

            for (String key : params.keySet()) {
                System.debug('Key: ' + key + ' | Value: ' + params.get(key));
            }

            // Get department and form type from params
            department = (String) params.get(StaticValuesUtil.DEPARTMENT_FIELD);
            Id leadId = createRecord(params);
            Map<String, String> responseBody = new Map<String, String>();
            responseBody.put('leadId', leadId);
            res.responseBody = Blob.valueOf(JSON.serialize(responseBody));

        } catch (Exception e) {
            System.debug('Exception occurred: ' + e.getMessage());
            Id recordTypeId = getRecordTypeIdByDepartment(department);
            if (recordTypeId == null) {
                createErrorResponse(400, 'Invalid department specified.');
            } else {
                createErrorResponse(500, 'Error creating lead: ' + e.getMessage());
            }
        }
    }

    /**
     * ****************************************************************************************
     * Method Name   : createRecord
     * Created By    : Preksha Chauhan
     * Created Date  : 06/25/2024
     * Modified Date : 06/26/2024
     * Description   : Processes Lead creation for a given department/form type. Validates the
     *                 required fields, retrieves the appropriate RecordTypeId, checks for
     *                 duplicate leads, and maps the JSON fields onto the Lead object. Inserts
     *                 (or updates, if a duplicate was matched) the Lead record and returns the
     *                 resulting Lead Id.
     * @param params JSON parameters from the request
     * @return       Id of the created or updated Lead record
     * ****************************************************************************************
     */
    global static Id createRecord(Map<String, Object> params) {
        String department = (String) params.get(StaticValuesUtil.DEPARTMENT_FIELD);

        // Get department and form type from params
        String typeOfForm = (String) params.get(StaticValuesUtil.TYPE_OF_FORM_FIELD);
        if (department == null) {
            createErrorResponse(400, 'Department is required.');
        }
        if (typeOfForm == null) {
            createErrorResponse(400, 'Type of form is required.');
        }

        // Retrieve the RecordTypeId from custom metadata
        Id recordTypeId = getRecordTypeIdByDepartment(department);
        if (recordTypeId == null) {
            createErrorResponse(400, 'Invalid department specified.');
        }

        // Check for duplicate Lead based on phone, email, and program
        String phone = (String) params.get(StaticValuesUtil.FIELD_PHONE);
        String email = (String) params.get(StaticValuesUtil.FIELD_EMAIL);
        String programmeInterestedIn = (String) params.get(StaticValuesUtil.FIELD_PROGRAMME_INTERESTED);
        System.debug('programmeInterestedIn: ' + programmeInterestedIn);

        // Create the Lead record using LeadRecordParams instance
        LeadRecordParams leadParams = new LeadRecordParams(params, recordTypeId, department, typeOfForm);
        Lead lead = saveLeadFieldMappings(leadParams);
        System.debug('Lead after field mappings: ' + lead);

        // Check CRUD permissions before inserting
        if (!Schema.sObjectType.Lead.isCreateable()) {
            createErrorResponse(403, 'Current user does not have permission to create Lead records.');
        }

        Lead undergraduationLead = null;
        Lead masterLead = null;
        if (department.equalsIgnoreCase(StaticValuesUtil.DEPARTMENT_UNDERGRAD)) {
            undergraduationLead = handleDuplicateLeadUnderGraduation(params, department, typeOfForm);
            System.debug('undergraduationLead == ' + undergraduationLead);
            if (undergraduationLead != null) {
                lead = undergraduationLead;
            }
        } else {
            masterLead = handleDuplicateLeadDefault(params, department, typeOfForm);
            if (masterLead != null) {
                lead = masterLead;
            }
        }

        // Note (historical, by Neha): Masters' duplicate-lead logic above was made the default
        // for every department except UG; the department-specific Masters branch below was
        // superseded by that change and is kept only for reference.
        /*
        if (department.equalsIgnoreCase(StaticValuesUtil.DEPARTMENT_MASTERS)) {
            masterLead = handleDuplicateLeadMasters(params, department, typeOfForm);
            if (masterLead != null) {
                lead = masterLead;
            }
        }
        */

        System.debug('--- Entered createRecord ---');
        System.debug('Input Params: ' + JSON.serializePretty(params));
        System.debug('Department: ' + department + ', TypeOfForm: ' + typeOfForm);
        System.debug('RecordTypeId resolved: ' + recordTypeId);
        System.debug('Phone from params: ' + phone);
        System.debug('Email from params: ' + email);
        System.debug('ProgrammeInterestedIn: ' + programmeInterestedIn);
        System.debug('Lead after saveLeadFieldMappings: ' + JSON.serializePretty(lead));

        if (undergraduationLead != null) {
            System.debug('Duplicate UG Lead found: ' + JSON.serializePretty(undergraduationLead));
        }
        if (masterLead != null) {
            System.debug('Duplicate Master Lead found: ' + JSON.serializePretty(masterLead));
        }

        System.debug('Final Lead before insert/upsert: ' + JSON.serializePretty(lead));

        // Insert (or update) the Lead record
        upsert lead;
        return lead.Id;
    }

    /**
     * ****************************************************************************************
     * Method Name  : handleDuplicateLeadDefault
     * Description  : Checks for a duplicate Lead based on the combination of Email + Phone +
     *                Preferred Programme, for every department except Undergraduation. If a
     *                matching Lead is found and its LeadSource is 'AURIS', its other fields are
     *                left untouched and only the new source is appended to
     *                Multi_Select_Lead_Source__c. Otherwise, the matched Lead's fields are
     *                overwritten with the incoming payload data via handleFieldAssignmentOfDuplicates.
     * @param payloadMap  Payload map from the REST API request
     * @param department  Department of the lead
     * @param typeOfForm  Form type of the lead
     * @return            The matched/updated Lead (in-memory, not yet saved), or null if no match
     * ****************************************************************************************
     */
    public static Lead handleDuplicateLeadDefault(Map<String, Object> payloadMap, String department, String typeOfForm) {
        String matchingphone = (String) payloadMap.get(StaticValuesUtil.FIELD_PHONE);

        // Retrieve field mappings from custom metadata
        Map<String, String> leadSourceGroupMapping = new Map<String, String>();
        List<WebFormFieldMapping__mdt> fieldMappings = [
            SELECT Department__c, JSON_Key__c, Label, TypeOfForm__c, LeadSourceGroup__c, Datatype__c
            FROM WebFormFieldMapping__mdt
            WHERE Department__c = :department
              AND TypeOfForm__c = :typeOfForm
        ];

        for (WebFormFieldMapping__mdt mapping : fieldMappings) {
            leadSourceGroupMapping.put(mapping.TypeOfForm__c, mapping.LeadSourceGroup__c);
        }

        if (matchingphone != null) {
            matchingphone = '%' + matchingphone + '%'; // Adding % for partial match
        }
        String matchingEmail = (String) payloadMap.get(StaticValuesUtil.FIELD_EMAIL);
        String matchingDepartment = department;
        String matchingPreferedProgrm = (String) payloadMap.get(StaticValuesUtil.FIELD_PROGRAMME_INTERESTED);
        // Only treat an existing Lead as a duplicate if its Admission_Year__c matches
        // the incoming lead's admission year - a re-application for a different
        // admission year is a new lead, not a duplicate of the old one.
        String matchingAdmissionYear = (payloadMap.containsKey(StaticValuesUtil.FIELD_ADMISSION_YEAR) && payloadMap.get(StaticValuesUtil.FIELD_ADMISSION_YEAR) != null)
            ? String.valueOf(payloadMap.get(StaticValuesUtil.FIELD_ADMISSION_YEAR))
            : System.label.Admission_Year;
        List<Lead> matchingLead = [
            SELECT Id, Phone, Registration_Number__c, Email, LeadSource, Preferred_Programme__c,
                Multi_Select_Lead_Source__c, Name_of_University_College__c, Department__c, State, Country, Status
            FROM Lead
            WHERE Phone LIKE :matchingphone
              AND Email = :matchingEmail
              AND Department__c = :matchingDepartment
              AND Preferred_Programme__c = :matchingPreferedProgrm
              AND Admission_Year__c = :matchingAdmissionYear
            LIMIT 1
        ];

        Lead newLead = null;
        if (!matchingLead.isEmpty()) {
            newLead = matchingLead[0];

            // Changed from checking LeadSource == 'AURIS' to checking Registration_Number__c,
            // since LeadSource is now populated from the UTM source in the payload and will
            // never be 'AURIS' going forward. A non-blank Registration_Number__c means the lead
            // already has an application in progress, so preserve its data and only
            // append the new form's lead-source group into the multi-select field.
            if (String.isNotBlank(newLead.Registration_Number__c)) {
                Set<String> picklistValues = new Set<String>();
                if (String.isNotBlank(newLead.Multi_Select_Lead_Source__c)) {
                    picklistValues.addAll(newLead.Multi_Select_Lead_Source__c.split(';'));
                }
                String websiteLeadSource;
                if (leadSourceGroupMapping.containsKey(typeOfForm)) {
                    websiteLeadSource = leadSourceGroupMapping.get(typeOfForm);
                }
                picklistValues.add(websiteLeadSource);
                newLead.Multi_Select_Lead_Source__c = String.join(new List<String>(picklistValues), ';');
                newLead.Most_Recent_Lead_Source__c = websiteLeadSource;
            } else {
                newLead = handleFieldAssignmentOfDuplicates(fieldMappings, payloadMap, newLead, department, typeOfForm);
            }

            return newLead;
        }
        return newLead;
    }

    /**
     * ****************************************************************************************
     * Method Name  : handleDuplicateLeadUnderGraduation
     * Description  : Checks for a duplicate Lead based on the combination of Email + Phone, for
     *                the Undergraduation department. If a matching Lead is found and its
     *                LeadSource is 'AURIS', its other fields are left untouched and only the new
     *                source is appended to Multi_Select_Lead_Source__c. Otherwise, the matched
     *                Lead's fields are overwritten with the incoming payload data via
     *                handleFieldAssignmentOfDuplicates.
     * @param payloadMap  Payload map from the REST API request
     * @param department  UG department
     * @param typeOfForm  Form type of the lead
     * @return            The matched/updated Lead (in-memory, not yet saved), or null if no match
     * ****************************************************************************************
     */
    public static Lead handleDuplicateLeadUnderGraduation(Map<String, Object> payloadMap, String department, String typeOfForm) {
        String matchingphone = (String) payloadMap.get(StaticValuesUtil.FIELD_PHONE);

        // Retrieve field mappings from custom metadata
        Map<String, String> leadSourceGroupMapping = new Map<String, String>();
        List<WebFormFieldMapping__mdt> fieldMappings = [
            SELECT Department__c, JSON_Key__c, Label, TypeOfForm__c, LeadSourceGroup__c, Datatype__c
            FROM WebFormFieldMapping__mdt
            WHERE Department__c = :department
              AND TypeOfForm__c = :typeOfForm
        ];

        for (WebFormFieldMapping__mdt mapping : fieldMappings) {
            leadSourceGroupMapping.put(mapping.TypeOfForm__c, mapping.LeadSourceGroup__c);
        }

        if (matchingphone != null) {
            matchingphone = '%' + matchingphone + '%'; // Adding % for partial match
        }
        String matchingEmail = (String) payloadMap.get(StaticValuesUtil.FIELD_EMAIL);
        String matchingDepartment = department;
        List<Lead> matchingLead = [
            SELECT Id, Phone, Registration_Number__c, Email, LeadSource, Preferred_Programme__c,
                Multi_Select_Lead_Source__c, Name_of_University_College__c, Department__c, State, Country, Status
            FROM Lead
            WHERE Phone LIKE :matchingphone
              AND Email = :matchingEmail
              AND Department__c = :matchingDepartment
            LIMIT 1
        ];

        Lead newLead = null;
        if (!matchingLead.isEmpty()) {
            newLead = matchingLead[0];

            // Changed from checking LeadSource == 'AURIS' to checking Registration_Number__c,
            // since LeadSource is now populated from the UTM source in the payload and will
            // never be 'AURIS' going forward. A non-blank Registration_Number__c means the lead
            // already has an application in progress, so preserve its data and only
            // append the new form's lead-source group into the multi-select field.
            if (String.isNotBlank(newLead.Registration_Number__c)) {
                Set<String> picklistValues = new Set<String>();
                if (String.isNotBlank(newLead.Multi_Select_Lead_Source__c)) {
                    picklistValues.addAll(newLead.Multi_Select_Lead_Source__c.split(';'));
                }
                String websiteLeadSource;
                if (leadSourceGroupMapping.containsKey(typeOfForm)) {
                    websiteLeadSource = leadSourceGroupMapping.get(typeOfForm);
                }
                picklistValues.add(websiteLeadSource);
                newLead.Multi_Select_Lead_Source__c = String.join(new List<String>(picklistValues), ';');
                newLead.Most_Recent_Lead_Source__c = websiteLeadSource;
            } else {
                newLead = handleFieldAssignmentOfDuplicates(fieldMappings, payloadMap, newLead, department, typeOfForm);
            }

            return newLead;
        }
        return newLead;
    }

    /**
     * ****************************************************************************************
     * Method Name  : handleFieldAssignmentOfDuplicates
     * Description  : Maps the incoming JSON payload onto an existing (duplicate) Lead using the
     *                WebFormFieldMapping__mdt field mappings, then applies the same
     *                admission-year/department/form-type/last-name/phone-formatting defaults and
     *                Multi_Select_Lead_Source__c handling used for new Leads.
     * @param fieldMappings  Custom metadata field mappings for this department/form type
     * @param payloadMap     Payload map from the REST API request
     * @param newLead        The existing Lead to update
     * @param department     Department of the lead
     * @param typeOfForm     Form type of the lead
     * @return               The updated Lead (in-memory, not yet saved)
     * ****************************************************************************************
     */
    public static Lead handleFieldAssignmentOfDuplicates(List<WebFormFieldMapping__mdt> fieldMappings, Map<String, Object> payloadMap, Lead newLead, String department, String typeOfForm) {
        Map<String, String> leadSourceGroupMapping = new Map<String, String>();

        for (WebFormFieldMapping__mdt mapping : fieldMappings) {
            String jsonKey = mapping.JSON_Key__c;
            String leadField = mapping.Label;
            String type = mapping.Datatype__c;
            leadSourceGroupMapping.put(mapping.TypeOfForm__c, mapping.LeadSourceGroup__c);

            if (payloadMap.containsKey(jsonKey) && payloadMap.get(jsonKey) != null) {
                Object val = payloadMap.get(jsonKey);
                Object typedVal;

                if (type == 'String') {
                    typedVal = String.valueOf(val);
                } else if (type == 'Date') {
                    typedVal = Date.valueOf(String.valueOf(val));
                } else if (type == 'Decimal') {
                    typedVal = Decimal.valueOf(String.valueOf(val));
                } else if (type == 'Boolean') {
                    typedVal = Boolean.valueOf(String.valueOf(val));
                } else {
                    typedVal = val;
                }

                // Added By : Mihir Ramoliya | 12th October 2026
                // Never push an existing Lead back to "New Lead" on a repeat submission once
                // the sales team has moved it to a later stage.
                if (leadField == 'Status' && newLead.Id != null) {
                    String currentStatus = (String) newLead.get('Status');
                    if (String.isNotBlank(currentStatus)
                        && !currentStatus.equalsIgnoreCase('New Lead')
                        && String.valueOf(typedVal).equalsIgnoreCase('New Lead')) {
                        continue;
                    }
                }
                newLead.put(leadField, typedVal);
            }
        }

        if (!payloadMap.containsKey('admissionYear') || payloadMap.get('admissionYear') == null) {
            newLead.Admission_Year__c = System.label.Admission_Year;
        }
        newLead.Department__c = department;
        newLead.TypeOfForm__c = typeOfForm;

        // Assign LeadSourceGroup dynamically based on typeOfForm
        if (leadSourceGroupMapping.containsKey(typeOfForm)) {
            newLead.LeadSource = leadSourceGroupMapping.get(typeOfForm);
        }
        if (String.isBlank((String) newLead.get('lastName'))) {
            newLead.LastName = '.';
        }
        if (payloadMap.containsKey('lastName')) {
            String lastName = (String) payloadMap.get('lastName');
            newLead.LastName = (lastName != null && lastName.trim().length() > 0) ? lastName : '.';
        }

        // Logic for phone number formatting with country code
        // (resolves the issue of getting a null value in the phone field)
        String country = null;
        Integer countryLength = 0;
        if (payloadMap.containsKey('country') && payloadMap.get('country') != null && payloadMap.get('country') != newLead.Country) {
            country = (String) payloadMap.get('country');
            countryLength = country.length();
        }

        if (payloadMap.containsKey('phone') && payloadMap.get('phone') != null) {
            if (payloadMap.containsKey('country') && payloadMap.get('country') != null && countryLength > 0 && payloadMap.get('country') != newLead.Country) {
                newLead.Phone = LeadPhoneUpdater.generatePhoneNumberWithCountryCode(country, (String) payloadMap.get('phone'));
                newLead.Country = (String) payloadMap.get('country');
                if (payloadMap.containsKey('state') && payloadMap.get('state') != null && payloadMap.get('state') != newLead.State) {
                    newLead.State = (String) payloadMap.get('state');
                }
            }
        }

        // Add the lead source into the multi-select picklist field
        Set<String> picklistValues = new Set<String>();
        if (String.isNotBlank(newLead.Multi_Select_Lead_Source__c)) {
            picklistValues.addAll(newLead.Multi_Select_Lead_Source__c.split(';'));
        }
        String websiteLeadSource;
        if (leadSourceGroupMapping.containsKey(typeOfForm)) {
            websiteLeadSource = leadSourceGroupMapping.get(typeOfForm);
        }
        picklistValues.add(websiteLeadSource);
        newLead.Multi_Select_Lead_Source__c = String.join(new List<String>(picklistValues), ';');

        return newLead;
    }

    /**
     * ****************************************************************************************
     * Method Name  : getRecordTypeIdByDepartment
     * Created By   : Preksha Chauhan
     * Created Date : 06/25/2024
     * Description  : Retrieves the RecordTypeId for a given department using the
     *                Department_Record_Type_Mapping__mdt custom metadata type. Logs and returns
     *                null if no mapping is found or an error occurs.
     * @param department  Department to look up
     * @return            The mapped Record Type Id, or null if not found
     * ****************************************************************************************
     */
    public static Id getRecordTypeIdByDepartment(String department) {
        try {
            List<Department_Record_Type_Mapping__mdt> mappings = [
                SELECT Record_Type_Id__c
                FROM Department_Record_Type_Mapping__mdt
                WHERE Department__c = :department
                LIMIT 1
            ];

            if (!mappings.isEmpty()) {
                System.debug('Mapping is available');
                return mappings[0].Record_Type_Id__c;
            } else {
                System.debug('Mapping is not available for department');
                createErrorResponse(400, 'Invalid department specified.');
            }

            return null;
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * ****************************************************************************************
     * Method Name  : saveLeadFieldMappings
     * Description  : Builds a new Lead from the WebFormFieldMapping__mdt field mappings for the
     *                given department/form type, applying admission-year, department, form-type,
     *                record-type, lead-source, last-name, and phone-formatting defaults.
     *                (Historical note, by Neha: fields are assigned dynamically via custom
     *                metadata mappings rather than being hardcoded per department/form.)
     * @param leadParams  Wrapper containing the payload, RecordTypeId, department, and form type
     * @return            The newly built Lead (in-memory, not yet saved)
     * ****************************************************************************************
     */
    public static Lead saveLeadFieldMappings(LeadRecordParams leadParams) {
        try {
            Lead newLead = new Lead();
            Map<String, String> leadSourceGroupMapping = new Map<String, String>();

            // Retrieve field mappings from custom metadata
            List<WebFormFieldMapping__mdt> fieldMappings = [
                SELECT Department__c, JSON_Key__c, Label, Datatype__c, TypeOfForm__c, LeadSourceGroup__c
                FROM WebFormFieldMapping__mdt
                WHERE Department__c = :leadParams.department
                  AND TypeOfForm__c = :leadParams.typeOfForm
            ];
            if (fieldMappings.isEmpty()) {
                System.debug('Field mappings found: ' + fieldMappings.size());
            }
            System.debug('The fieldMappings are ' + fieldMappings);

            // Iterate over field mappings and map JSON fields to Lead fields
            for (WebFormFieldMapping__mdt mapping : fieldMappings) {
                leadSourceGroupMapping.put(mapping.TypeOfForm__c, mapping.LeadSourceGroup__c);
                String jsonKey = mapping.JSON_Key__c;
                String leadField = mapping.Label;
                String type = mapping.Datatype__c;

                if (leadParams.params.containsKey(jsonKey) && leadParams.params.get(jsonKey) != null) {
                    Object val = leadParams.params.get(jsonKey);
                    Object typedVal;

                    if (type == 'String') {
                        typedVal = String.valueOf(val);
                    } else if (type == 'Date') {
                        typedVal = Date.valueOf(String.valueOf(val));
                    } else if (type == 'Decimal') {
                        typedVal = Decimal.valueOf(String.valueOf(val));
                    } else if (type == 'Boolean') {
                        typedVal = Boolean.valueOf(String.valueOf(val));
                    } else {
                        typedVal = val;
                    }
                    System.debug('Mapping JSON key ' + jsonKey + ' to Lead field ' + leadField + ' with value: ' + typedVal);
                    newLead.put(leadField, typedVal);
                }
                if (!leadParams.params.containsKey('admissionYear') || leadParams.params.get('admissionYear') == null) {
                    newLead.Admission_Year__c = System.label.Admission_Year;
                }

                newLead.Department__c = leadParams.department;
                newLead.TypeOfForm__c = leadParams.typeOfForm;
                newLead.RecordTypeId = leadParams.recordTypeId;

                // Assign LeadSourceGroup dynamically based on typeOfForm
                if (leadSourceGroupMapping.containsKey(leadParams.typeOfForm)) {
                    newLead.LeadSource = leadSourceGroupMapping.get(leadParams.typeOfForm);
                }
                // Assign to Multi_Select_Lead_Source__c if LeadSource is set
                if (newLead.LeadSource != null) {
                    newLead.Multi_Select_Lead_Source__c = newLead.LeadSource;
                }
                if (String.isBlank((String) newLead.get('lastName'))) {
                    newLead.LastName = '.';
                }
                if (leadParams.params.containsKey('lastName')) {
                    String lastName = (String) leadParams.params.get('lastName');
                    newLead.LastName = (lastName != null && lastName.trim().length() > 0) ? lastName : '.';
                }

                // Logic for phone number formatting with country code
                // (resolves the issue of getting a null value in the phone field)
                String country = null;
                Integer countryLength = 0;
                if (leadParams.params.containsKey('country') && leadParams.params.get('country') != null) {
                    country = (String) leadParams.params.get('country');
                    countryLength = country.length();
                    newLead.Country = country;
                }
                if (leadParams.params.containsKey('phone') && leadParams.params.get('phone') != null) {
                    if (leadParams.params.containsKey('country') && leadParams.params.get('country') != null && countryLength > 0) {
                        newLead.Phone = LeadPhoneUpdater.generatePhoneNumberWithCountryCode(country, (String) leadParams.params.get('phone'));
                    } else {
                        newLead.Phone = LeadPhoneUpdater.generatePhoneNumberWithCountryCode('IN', (String) leadParams.params.get('phone'));
                    }
                }
            }

            System.debug('--- Entered saveLeadFieldMappings ---');
            System.debug('Lead Params JSON: ' + JSON.serializePretty(leadParams.params));

            if (leadParams.params.containsKey('phone')) {
                System.debug('Raw phone param: ' + leadParams.params.get('phone'));
                System.debug('Final phone after formatting: ' + newLead.Phone);
            }
            if (leadParams.params.containsKey('email')) {
                System.debug('Raw email param: ' + leadParams.params.get('email'));
            }
            System.debug('Lead fields after mapping (partial): ' +
                ' LastName=' + newLead.LastName +
                ', Email=' + newLead.Email +
                ', Phone=' + newLead.Phone +
                ', Department=' + newLead.Department__c +
                ', TypeOfForm=' + newLead.TypeOfForm__c);

            return newLead;
        } catch (Exception e) {
            throw new CustomException('Error creating Lead record: ' + e.getMessage());
        }
    }

    /**
     * ****************************************************************************************
     * Class Name   : LeadRecordParams
     * Created By   : Preksha Chauhan
     * Created Date : 06/26/2024
     * Description  : Encapsulates the parameters needed to create a Lead record: the parsed
     *                JSON payload, the resolved RecordTypeId, the department, and the form type.
     * ****************************************************************************************
     */
    public class LeadRecordParams {
        /** Parsed JSON payload from the incoming request. */
        public Map<String, Object> params { get; set; }

        /** Record Type Id resolved for the lead's department. */
        public Id recordTypeId { get; set; }

        /** Department the lead belongs to (e.g. Masters, Undergraduation). */
        public String department { get; set; }

        /** Type of the web form that submitted this lead. */
        public String typeOfForm { get; set; }

        /**
         * @param params       Parsed JSON payload
         * @param recordTypeId Record Type Id of the lead
         * @param department   Department of the lead
         * @param typeOfForm   Form type of the lead
         */
        public LeadRecordParams(Map<String, Object> params, Id recordTypeId, String department, String typeOfForm) {
            this.params = params;
            this.recordTypeId = recordTypeId;
            this.department = department;
            this.typeOfForm = typeOfForm;
        }
    }

    /**
     * ****************************************************************************************
     * Method Name  : createErrorResponse
     * Created By   : Preksha Chauhan
     * Created Date : 06/25/2024
     * Description  : Builds and sets a JSON error response on the current RestResponse with the
     *                given status code and message. Falls back to a generic 500 error response
     *                if building the response itself fails.
     * @param statusCode  HTTP status code to return
     * @param message     Error message to return
     * ****************************************************************************************
     */
    public static void createErrorResponse(Integer statusCode, String message) {
        try {
            RestResponse res = RestContext.response;
            res.statusCode = statusCode;
            res.addHeader('Content-Type', 'application/json');
            res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
                'status' => statusCode,
                'message' => message
            }));
        } catch (Exception e) {
            RestResponse res = RestContext.response;
            res.statusCode = statusCode;
            res.addHeader('Content-Type', 'application/json');
            res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
                'status' => 500,
                'message' => 'Error creating error response: ' + e.getMessage()
            }));
        }
    }

    /**
     * ****************************************************************************************
     * Class Name   : CustomException
     * Created By   : Preksha Chauhan
     * Created Date : 06/25/2024
     * Description  : Custom exception type used within saveWebsiteLead for error handling.
     * ****************************************************************************************
     */
    public class CustomException extends Exception {}
}