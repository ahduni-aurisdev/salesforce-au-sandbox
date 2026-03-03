/******************************************************************************************
* Create By        : Preksha Chauhan
* Company          : GetonCRM Solutions
* Create Date      : 06/25/2024
* Description      : This class provides RESTful API endpoints for creating Lead records in Salesforce. 
*                    It handles parsing JSON request bodies, validating required fields, checking for 
*                    duplicate leads, retrieving record type IDs based on department, mapping fields from 
*                    JSON to Lead objects, and handling custom exceptions and error responses.
*********************************************************************************************
*/ 

@RestResource(urlMapping='/CreateLead/')
global with sharing class LeadRestService {

    /****************************************************************************************** 
    * Method Name : createLead
    * Create By : Preksha Chauhan
    * Create Date : 06/25/2024
    * Modified Date : 06/26/2024
    * Description : This method handles the HTTP POST request to create a new Lead record. 
    *               It parses the JSON request body, validates required fields, checks for 
    *               duplicate leads, retrieves the RecordTypeId, maps JSON fields to Lead object, 
    *               and inserts the Lead record. If any error occurs, it returns an appropriate 
    *               error response.
    ****************************************************************************************
    */
    @HttpPost
    global static void createLead() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        try {
            // Parse the JSON request body
            String requestBody = req.requestBody.toString();
            System.debug('Request Body: ' + requestBody);
            Map<String, Object> params = (Map<String, Object>) JSON.deserializeUntyped(requestBody);
            System.debug('params ------------- ' + params);

            // Get department and form type from params
            String department = (String) params.get('department');
            String typeOfForm = (String) params.get('typeOfForm');
            if (department == null) {
                createErrorResponse(400, 'Department is required.');
            }
            if (typeOfForm == null) {
                 createErrorResponse(400, 'Type of form is required.');
            }
            System.debug('Department: ' + department + ', TypeOfForm: ' + typeOfForm);

            // Retrieve the RecordTypeId from custom metadata
            Id recordTypeId = getRecordTypeIdByDepartment(department);
            if (recordTypeId == null) {
                 createErrorResponse(400, 'Invalid department specified.');
            }
            System.debug('RecordTypeId: ' + recordTypeId);

            // Check for duplicate Lead based on phone, email, and program
            String phone = (String) params.get('phone');
            String email = (String) params.get('email');
            String programmeInterestedIn = (String) params.get('programmeInterestedIn'); // Corrected variable name

            if (isDuplicateLead(phone, email, programmeInterestedIn)) { // Updated method parameter
                 createErrorResponse(409, 'Duplicate lead found.');
            }

            // Create the Lead record using LeadRecordParams instance
            LeadRecordParams leadParams = new LeadRecordParams(params, recordTypeId, department, typeOfForm);
            Lead lead = createLeadRecord(leadParams);

            // Check CRUD permissions before inserting
            if (!Schema.sObjectType.Lead.isCreateable()) {
                 createErrorResponse(403, 'Current user does not have permission to create Lead records.');
            }

            // Insert the Lead record
            insert lead;

            // List<WebFormFieldMapping__mdt> fieldMappings = [
            //     SELECT Department__c, JSON_Key__c, Label
            //     FROM WebFormFieldMapping__mdt
            //     WHERE Department__c = :leadParams.department AND TypeOfForm__c = :leadParams.typeOfForm
            //     WITH SECURITY_ENFORCED
            // ];
            
            // Map<String,Object> leadDataMap = lead.getPopulatedFieldsAsMap();
            // Map<String,Object> responseMap = new Map<String,Object>();

            // for (WebFormFieldMapping__mdt mapping : fieldMappings) {
            //     String Label = mapping.Label;
            //     System.debug('JSON Key: ' + Label);
            //     if (leadDataMap.containsKey(Label)) {
            //         // Directly use JSON key as Lead field API name
            //         responseMap.put(mapping.JSON_Key__c, leadDataMap.get(Label));
            //     }
            // }

            params.put('leadId',lead.Id);
            res.statusCode = 201; // Created
            res.addHeader('Content-Type', 'application/json');
            res.responseBody = Blob.valueOf(JSON.serialize(params));
             //   JSON.serialize(lead);
        } catch (Exception e) {
            System.debug('Error creating lead: ' + e.getMessage());
             createErrorResponse(500, 'Error creating lead: ' + e.getMessage());
        }
    }
    
    /****************************************************************************************** 
    * Method Name : getRecordTypeIdByDepartment
    * Create By : Preksha Chauhan
    * Create Date : 06/25/2024
    * Description : This method retrieves the RecordTypeId for a given department using custom metadata. 
    *               It queries the Department_Record_Type_Mapping__mdt custom metadata type to get the 
    *               RecordTypeId based on the department. If any error occurs, it logs the error and returns null.
    ****************************************************************************************
    ***/
    public static Id getRecordTypeIdByDepartment(String department) {
        try {
            List<Department_Record_Type_Mapping__mdt> mappings = [
                SELECT Record_Type_Id__c
                FROM Department_Record_Type_Mapping__mdt
                WHERE Department__c = :department WITH SECURITY_ENFORCED
                LIMIT 1
            ];

            if (!mappings.isEmpty()) {
                System.debug('RecordTypeId found for department ' + department + ': ' + mappings[0].Record_Type_Id__c);
                return mappings[0].Record_Type_Id__c;
            }
            System.debug('No RecordTypeId found for department ' + department);
            return null;
        } catch (Exception e) {
            System.debug('Error retrieving RecordTypeId: ' + e.getMessage());
            return null;
        }
    }

    /****************************************************************************************** 
    * Method Name : isDuplicateLead
    * Create By : Preksha Chauhan
    * Create Date : 06/25/2024
    * Description : This method checks for duplicate leads based on phone, email, and program. 
    *               It queries the Lead object to find any existing leads with the same phone, 
    *               email, or program. If any error occurs, it logs the error and returns false.
    ****************************************************************************************
    ***/
    public static Boolean isDuplicateLead(String phone, String email, String programmeInterestedIn) {
        try {
            List<Lead> existingLeads = [SELECT Id FROM Lead
                WHERE (Phone = :phone OR Email = :email) AND Programme_Interested_in__c = :programmeInterestedIn
                WITH SECURITY_ENFORCED
            ];
            System.debug('Duplicate Leads Found: ' + existingLeads.size());
            return !existingLeads.isEmpty();
        } catch (Exception e) {
            System.debug('Error checking for duplicate leads: ' + e.getMessage());
            return false;
        }
    }

    /****************************************************************************************** 
    * Method Name : createLeadRecord
    * Create By : Preksha Chauhan
    * Create Date : 06/25/2024
    * Description : This method creates a Lead record based on the input LeadRecordParams instance. 
    *               It retrieves field mappings from custom metadata, maps JSON fields to Lead object, 
    *               sets required fields, handles school state and city lookup fields, sets LeadSource, 
    *               and returns the created Lead object. If any error occurs, it logs the error and throws a custom exception.
    ****************************************************************************************
    ***/
    public static Lead createLeadRecord(LeadRecordParams leadParams) {
        try {
            Lead lead = new Lead();
            lead.RecordTypeId = leadParams.recordTypeId;
    
            // Retrieve field mappings from custom metadata
            List<WebFormFieldMapping__mdt> fieldMappings = [
                SELECT Department__c, JSON_Key__c, Label
                FROM WebFormFieldMapping__mdt
                WHERE Department__c = :leadParams.department AND TypeOfForm__c = :leadParams.typeOfForm
                WITH SECURITY_ENFORCED
            ];
            System.debug('params: ' + leadParams.params);
            System.debug('fieldMappings: ' + fieldMappings);
    
            // Check if field mappings are retrieved
            if (fieldMappings.isEmpty()) {
                System.debug('No field mappings found for department: ' + leadParams.department + ' and typeOfForm: ' + leadParams.typeOfForm);
            }
    
            // Dynamically map fields from JSON payload to Lead object based on custom metadata
            for (WebFormFieldMapping__mdt mapping : fieldMappings) {
                String jsonKey = mapping.JSON_Key__c;
                System.debug('JSON Key: ' + jsonKey);
                if (leadParams.params.containsKey(jsonKey)) {
                    // Directly use JSON key as Lead field API name
                    lead.put(mapping.Label, leadParams.params.get(jsonKey));
                }
            }
    
            // Additional Logic 1: Explicitly set required fields
            if (leadParams.params.containsKey('firstName')) {
                lead.FirstName = (String) leadParams.params.get('firstName');
            }
            if (leadParams.params.containsKey('lastName')) {
                lead.LastName = (String) leadParams.params.get('lastName');
            } else {
                throw new CustomException('LastName is required.');
            }
    
            // Set the department and type of form custom fields
            lead.Department__c = leadParams.department;
            lead.TypeOfForm__c = leadParams.typeOfForm;

            // Additional Logic 2: Lead Source based on Type of Form
            if (leadParams.params.containsKey('LeadSource')) {
                lead.LeadSource = (String) leadParams.params.get('LeadSource');
            } else {
                lead.LeadSource = 'Website';
            }
    
            if (leadParams.typeOfForm == 'Website_MastersBrochures') {
                lead.LeadSource = 'Website_MastersBrochures';
            } else if (leadParams.typeOfForm == 'Website_MastersQueries') {
                lead.LeadSource = 'Website_MastersQueries';
            } else if (leadParams.typeOfForm == 'Website_Connect') {
                lead.LeadSource = 'Website_Connect';
            }
    
            // Additional Logic 3: logic for setting country, state, and city
            if (String.isBlank((String) leadParams.params.get('country')) && !String.isBlank((String) leadParams.params.get('state'))) {
                lead.Country__c = getCountryIdByName('India');
                System.debug('Country is blank and state is not blank. Setting Country to India.');
            } else if (!String.isBlank((String) leadParams.params.get('country')) && String.isBlank((String) leadParams.params.get('state'))) {
                lead.Country__c = getCountryIdByName((String) leadParams.params.get('country'));
                System.debug('Country is not blank and state is blank. Setting Country to ' + lead.Country__c);
            }
    
            if (leadParams.params.containsKey('state')) {
                lead.School_State__c = getStateIdByName((String) leadParams.params.get('state'));
                System.debug('Setting State to ' + lead.School_State__c);
            }
    
            if (leadParams.params.containsKey('city')) {
                lead.School_City__c = getCityIdByName((String) leadParams.params.get('city'));
                System.debug('Setting City to ' + lead.School_City__c);
            }
    
            // Additional Logic 3: for department "Undergraduation" and form type "Website_MastersQueries"
            if (leadParams.department == 'Undergraduation' && leadParams.typeOfForm == 'Website_MastersQueries') {
                String iamField = (String) leadParams.params.get('iam');
                if (iamField == 'Student') {
                    lead.Class__c = (String) leadParams.params.get('class');
                } else if (iamField == 'Friend of Ahmedabad University' || iamField == 'Parent' || iamField == 'Educator') {
                    lead.Organisation_Institute_Name__c = (String) leadParams.params.get('Organisation_Institute_Name__c');
                }
            }
            System.debug('Lead Created: ' + JSON.serialize(lead));
            return lead;
        } catch (Exception e) {
            System.debug('Error creating Lead record: ' + e.getMessage());
            throw new CustomException('Error creating Lead record: ' + e.getMessage());
        }
    }
    
    /****************************************************************************************** 
    * Method Name : getCountryIdByName
    * Create By : Preksha Chauhan
    * Create Date : 06/25/2024
    * Description : This method retrieves the ID of a country record based on the country name. 
    *               It queries the Country__c custom object to find the country record with the given name. 
    *               If any error occurs, it logs the error and returns null.
    ****************************************************************************************
    ***/
    public static Id getCountryIdByName(String countryName) {
        try {
            Country__c country = [SELECT Id FROM Country__c WHERE Name = :countryName WITH SECURITY_ENFORCED LIMIT 1];
            return country.Id;
        } catch (Exception e) {
            System.debug('Error retrieving country ID: ' + e.getMessage());
            return null;
        }
    }
    
    /****************************************************************************************** 
    * Method Name : getStateIdByName
    * Create By : Preksha Chauhan
    * Create Date : 06/25/2024
    * Description : This method retrieves the ID of a state record based on the state name. 
    *               It queries the State__c custom object to find the state record with the given name. 
    *               If any error occurs, it logs the error and returns null.
    ****************************************************************************************
    ***/
    public static Id getStateIdByName(String stateName) {
        try {
            State__c state = [SELECT Id FROM State__c WHERE Name = :stateName WITH SECURITY_ENFORCED LIMIT 1];
            return state.Id;
        } catch (Exception e) {
            System.debug('Error retrieving state ID: ' + e.getMessage());
            return null;
        }
    }
    
   /****************************************************************************************** 
    * Method Name : getCityIdByName
    * Create By : Preksha Chauhan
    * Create Date : 06/25/2024
    * Description : This method retrieves the ID of a city record based on the city name. 
    *               It queries the City__c custom object to find the city record with the given name. 
    *               If any error occurs, it logs the error and returns null.
    ****************************************************************************************
    ***/
    public static Id getCityIdByName(String cityName) {
        try {
            City__c city = [SELECT Id FROM City__c WHERE Name = :cityName WITH SECURITY_ENFORCED LIMIT 1];
            return city.Id;
        } catch (Exception e) {
            System.debug('Error retrieving city ID: ' + e.getMessage());
            return null;
        }
    }
    
    /****************************************************************************************** 
    * Class Name : LeadRecordParams
    * Create By : Preksha Chauhan
    * Create Date : 06/26/2024
    * Description : This class encapsulates the parameters for creating a Lead record. 
    *               It contains the JSON parameters, RecordTypeId, department, and typeOfForm.
    ****************************************************************************************
    */
    public class LeadRecordParams {
        public Map<String, Object> params { get; set; }
        public Id recordTypeId { get; set; }
        public String department { get; set; }
        public String typeOfForm { get; set; }

        public LeadRecordParams(Map<String, Object> params, Id recordTypeId, String department, String typeOfForm) {
            this.params = params;
            this.recordTypeId = recordTypeId;
            this.department = department;
            this.typeOfForm = typeOfForm;
        }
    }

    /****************************************************************************************** 
    * Method Name : createErrorResponse
    * Create By : Preksha Chauhan
    * Create Date : 06/25/2024
    * Description : This helper method creates an error response with the given status code and message. 
    *               It sets the response status code, content type, and serializes the error message to JSON. 
    *               If any error occurs, it logs the error and returns a generic error response.
    ****************************************************************************************
    ***/
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
            System.debug('Error creating error response: ' + e.getMessage());
            RestResponse res = RestContext.response;
            res.statusCode = statusCode;

            res.addHeader('Content-Type', 'application/json');
            res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
                'status' => 500,
                'message' => 'Error creating error response: ' + e.getMessage()
            }));
        }
    }

    /****************************************************************************************** 
    * Method Name : CustomException
    * Create By : Preksha Chauhan
    * Create Date : 06/25/2024
    * Description : This class defines a custom exception to be used within the LeadRestService class. 
    *               It extends the base Exception class to provide custom error handling.
    ****************************************************************************************
    ***/
    public class CustomException extends Exception {}
}