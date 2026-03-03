/**
* @description
* ****************************************************************************************
* Create By        : Preksha Chauhan
* Company          : GetonCRM Solutions
* Create Date      : 06/25/2024
* Class Name       : saveWebsiteLead
* Description      : This class provides RESTful API endpoints for creating Lead records in Salesforce. 
*                    It handles parsing JSON request bodies, validating required fields, checking for 
*                    duplicate leads, retrieving record type IDs based on department, mapping fields from 
*                    JSON to Lead objects, and handling custom exceptions and error responses.
*********************************************************************************************
*/ 
@RestResource(urlMapping='/saveLead/*')
global with sharing class saveWebsiteLead {

   /**
    * @description
    **************************************************************************************** 
    * Method Name : saveLead
    * Created By  : Preksha Chauhan
    * Created Date: 06/25/2024
    * Modified Date: 06/26/2024
    * Description : This method handles the HTTP POST request to create a new Lead record.
    *               It parses the JSON request body, determines the department (Masters or UG),
    *               and calls the appropriate method for lead creation. It handles errors 
    *               gracefully by returning an appropriate error response if any issues occur 
    *               during processing.
    ****************************************************************************************
    */
    @HttpPost
    global static void saveLead() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        String department;
        try {
            // Parse the JSON request body
            String requestBody = req.requestBody.toString();
            // Debug entire raw JSON
        System.debug('### Incoming JSON Body: ' + requestBody);
            Map<String, Object> params = (Map<String, Object>) JSON.deserializeUntyped(requestBody);
             // Debug keys and values one by one
        for (String key : params.keySet()) {
            System.debug('### Key: ' + key + ' | Value: ' + params.get(key));
        }

            // Get department and form type from params
             department = (String) params.get(StaticValuesUtil.DEPARTMENT_FIELD);
            Id leadId = createRecord(params);
            Map<String, String> responseBody = new Map<String, String>();
            responseBody.put('leadId', leadId);
            res.responseBody = Blob.valueOf(JSON.serialize(responseBody));

        } catch (Exception e) {
            system.debug('exception occured');
            Id recordTypeId = getRecordTypeIdByDepartment(department);
            if (recordTypeId == null) {
                createErrorResponse(400, 'Invalid department specified.');
            }
            else{
                createErrorResponse(500, 'Error creating lead: ' + e.getMessage());
            }
        }
    }

    /**
    * @description
    * @param params JSON parameters from request
    * @return Id of lead record 
    * Method Name : createRecord
    * Created By  : Preksha Chauhan
    * Created Date: 06/25/2024
    * Modified Date: 06/26/2024
    * Description : This method processes the lead creation specifically for the StaticValuesUtil.DEPARTMENT_MASTERS department.
    *               It validates the required fields, retrieves the appropriate RecordTypeId, checks 
    *               for duplicate leads, and maps the JSON fields to the Lead object. It inserts the 
    *               Lead record and returns the created Lead Id in the response if successful. If any 
    *               errors occur, it returns an appropriate error response.
    ****************************************************************************************
    */

    // Constants for program groups****** 
    private static final String FIELD_UGGROUP_TAG = 'uggrouptag';
    private static final String FIELD_PROGRAMS = 'programs';
    private static final Integer MAX_GROUPS = 4;
    private static final Integer MAX_PROGRAMS_PER_GROUP = 3;    
        
    global static Id createRecord(Map<String, Object> params) {

        System.debug('====== CREATE RECORD DEBUG START ======');
        System.debug('All params keys: ' + params.keySet());
        System.debug('StaticValuesUtil.DEPARTMENT_FIELD: ' + StaticValuesUtil.DEPARTMENT_FIELD);
        System.debug('StaticValuesUtil.DEPARTMENT_UNDERGRAD: ' + StaticValuesUtil.DEPARTMENT_UNDERGRAD);        
        
        String department = (String) params.get(StaticValuesUtil.DEPARTMENT_FIELD);
        System.debug('Department from StaticValuesUtil.DEPARTMENT_FIELD: ' + department);
    
        // Get department and form type from params
        String typeOfForm = (String) params.get(StaticValuesUtil.TYPE_OF_FORM_FIELD);
        System.debug('TypeOfForm from StaticValuesUtil.TYPE_OF_FORM_FIELD: ' + typeOfForm);
        
        if (department == null) {
            department = (String) params.get('department');
            System.debug('Department from "department" key: ' + department);
        }
        
        System.debug('Final department value: ' + department);
        
        if (typeOfForm == null) {
            createErrorResponse(400, 'Type of form is required.');
        }
        
        // Retrieve the RecordTypeId from custom metadata
        Id recordTypeId = getRecordTypeIdByDepartment(department);
        System.debug('RecordTypeId returned: ' + recordTypeId);
        
        if (recordTypeId == null) {
            createErrorResponse(400, 'Invalid department specified.');
        }
        
        // Verify what RecordType this is
        if (recordTypeId != null) {
            try {
                RecordType rt = [SELECT Id, DeveloperName, Name FROM RecordType WHERE Id = :recordTypeId LIMIT 1];
                System.debug('RecordType details: ' + rt.Name + ' (' + rt.DeveloperName + ')');
                
                // Check if it's the correct one
                if (department.equalsIgnoreCase('Undergraduation') && !rt.Name.contains('Undergrad')) {
                    System.debug('WRONG: Got ' + rt.Name + ' instead of Undergraduation RecordType');
                }
            } catch (Exception e) {
                System.debug('Could not query RecordType: ' + e.getMessage());
            }
        }
        
        System.debug('Expected Undergraduation RecordTypeId: 0125g000002SMZSAA4');
        System.debug('Is this the correct ID? ' + (recordTypeId == '0125g000002SMZSAA4'));        
        
        // MODIFICATION: Check for duplicate by Registration Number first************
        String registrationNumber = (String) params.get('registrationNumber');
        if (String.isNotBlank(registrationNumber)) {
            List<Lead> existingLeads = [SELECT Id, Registration_Number__c, Department__c, RecordTypeId, Multi_Select_Lead_Source__c, LastName, FirstName, Country 
                                       FROM Lead 
                                       WHERE Registration_Number__c = :registrationNumber 
                                       AND Department__c = :department 
                                       LIMIT 1];
            
            if (!existingLeads.isEmpty()) {
                // Update existing lead
                Lead existingLead = existingLeads[0];
                System.debug('Found duplicate lead. Existing RecordTypeId: ' + existingLead.RecordTypeId);
                existingLead = updateLeadFromParams(existingLead, params, department, typeOfForm);
                update existingLead;
                return existingLead.Id;
            }
        } 
        
        // Create the Lead record using LeadRecordParams instance
        LeadRecordParams leadParams = new LeadRecordParams(params, recordTypeId, department, typeOfForm);
        Lead lead = saveLeadFieldMappings(leadParams);
        System.debug('Lead after saveLeadFieldMappings: ' + lead);
        System.debug('Lead RecordTypeId: ' + lead.RecordTypeId);
        System.debug('Lead Department__c: ' + lead.Department__c);
        System.debug('Initial lead RecordTypeId: ' + lead.RecordTypeId);
        System.debug('Initial lead Department__c: ' + lead.Department__c);

        // STEP 2: Check for duplicates WITHOUT overwriting RecordType
        Lead duplicateLead = null;
        
        if(department.equalsIgnoreCase(StaticValuesUtil.DEPARTMENT_UNDERGRAD)){
            duplicateLead = handleDuplicateLeadUnderGraduation(params, department, typeOfForm);
            System.debug('UG duplicate check - found: ' + (duplicateLead != null));
        } else {
            duplicateLead = handleDuplicateLeadDefault(params, department, typeOfForm);
            System.debug('Masters duplicate check - found: ' + (duplicateLead != null));
        }
        
        if (duplicateLead != null) {
            System.debug('Duplicate lead found. Checking its RecordType...');
            System.debug('Duplicate lead RecordTypeId: ' + duplicateLead.RecordTypeId);
            System.debug('Duplicate lead Department__c: ' + duplicateLead.Department__c);
            
            // Update the duplicate lead with correct RecordType and Department
            duplicateLead.RecordTypeId = recordTypeId; 
            duplicateLead.Department__c = department; 
            
            // update other fields from params
            duplicateLead = updateLeadFromParams(duplicateLead, params, department, typeOfForm);
            
            System.debug('Updated duplicate lead RecordTypeId to: ' + duplicateLead.RecordTypeId);
            System.debug('Updated duplicate lead Department__c to: ' + duplicateLead.Department__c);
            
            lead = duplicateLead;
        }
        
        // STEP 3: Ensure fields are set
        // Ensure Registration Number is set
        if (String.isNotBlank(registrationNumber)) {
            lead.Registration_Number__c = registrationNumber;
        }
        
        // Ensure Department__c is set
        if (String.isBlank(lead.Department__c)) {
            lead.Department__c = department;
            System.debug('Setting Department__c to: ' + department);
        }
        
        // Ensure RecordTypeId is set
        if (lead.RecordTypeId != recordTypeId) {
            System.debug('WARNING: Lead RecordTypeId (' + lead.RecordTypeId + ') is not the expected one (' + recordTypeId + '). Fixing...');
            lead.RecordTypeId = recordTypeId;
        }
        
        System.debug('Final lead before insert - RecordTypeId: ' + lead.RecordTypeId);
        System.debug('Final lead before insert - Department__c: ' + lead.Department__c);        
    
        // Check for duplicate Lead based on phone, email, and program
        String phone = (String) params.get(StaticValuesUtil.FIELD_PHONE);
        String email = (String) params.get(StaticValuesUtil.FIELD_EMAIL);
        String programmeInterestedIn = (String) params.get(StaticValuesUtil.FIELD_PROGRAMME_INTERESTED); 
        System.debug('programmeInterestedIn102: ' + programmeInterestedIn);
    
        // Create the Lead record using LeadRecordParams instance
        LeadRecordParams leadPara = new LeadRecordParams(params, recordTypeId, department, typeOfForm);
        Lead l = saveLeadFieldMappings(leadPara);
        System.debug('lead after field mappings: ' + l);
    
        // Ensure Registration Number is set
        if (String.isNotBlank(registrationNumber)) {
            lead.Registration_Number__c = registrationNumber;
        }        
    
        // Check CRUD permissions before inserting
        if (!Schema.sObjectType.Lead.isCreateable()) {
            createErrorResponse(403, 'Current user does not have permission to create Lead records.');
        }
        
        Lead undergraduationLead = null;
        Lead masterLead = null;
        if(department.equalsIgnoreCase(StaticValuesUtil.DEPARTMENT_UNDERGRAD)){
            undergraduationLead  =  handleDuplicateLeadUnderGraduation(params,department,typeOfForm);
            System.debug('undergraduationLead== ' + undergraduationLead);
            if (undergraduationLead != null){    
                lead = undergraduationLead;
            }
        } else {
            masterLead  =  handleDuplicateLeadDefault(params,department,typeOfForm);
            if (masterLead != null){
                lead = masterLead;
            }
        }
    
        // Handle program groups - Check for BOTH keys
        System.debug('====== CHECKING FOR PROGRAM DATA ======');
        List<Object> programGroups = new List<Object>();
        
        // Check for BOTH possible keys: 'grpPrograms' (from your example) AND 'programs'
        if (params.containsKey('grpPrograms') && params.get('grpPrograms') != null) {
            programGroups = (List<Object>) params.get('grpPrograms');
            System.debug('Using grpPrograms key from payload');
            System.debug('grpPrograms size: ' + programGroups.size());
            System.debug('Sample grpPrograms: ' + JSON.serialize(programGroups));
        } else if (params.containsKey(FIELD_PROGRAMS) && params.get(FIELD_PROGRAMS) != null) {
            programGroups = (List<Object>) params.get(FIELD_PROGRAMS);
            System.debug('Using programs key from payload');
            System.debug('programs size: ' + programGroups.size());
        }
        
        System.debug('programGroups final size: ' + programGroups.size());
        System.debug('====== END PROGRAM DATA CHECK ======');
    
        // If we found program data, process it
        if (!programGroups.isEmpty()) {
            System.debug('====== PROCESSING PROGRAM DATA ======');
            System.debug('Raw programGroups: ' + JSON.serializePretty(programGroups));
            
            // Validate maximum groups
            if (programGroups.size() > MAX_GROUPS) {
                createErrorResponse(400, 'Maximum ' + MAX_GROUPS + ' program groups allowed per lead.');
            }
            
            // Validate programs per group and generate application numbers
            programGroups = validateAndGenerateGroupNumbers(programGroups, registrationNumber);
            
            // Store as JSON for later processing
            lead.Group_Tag__c = JSON.serialize(programGroups);
            System.debug('Group_Tag__c stored: ' + (lead.Group_Tag__c != null));
            System.debug('Group_Tag__c value length: ' + (lead.Group_Tag__c != null ? lead.Group_Tag__c.length() : 0));
            
            // Create Preferred_Program__c records NOW
            System.debug('Calling createInitialPreferredPrograms...');
            createInitialPreferredPrograms(lead.Id, registrationNumber, programGroups);
            System.debug('After createInitialPreferredPrograms call');
            
            System.debug('====== END PROCESSING PROGRAM DATA ======');
        } else {
            System.debug('No program data found in payload');
            System.debug('Checked keys: grpPrograms=' + params.containsKey('grpPrograms') + 
                        ', programs=' + params.containsKey(FIELD_PROGRAMS));
        }
    
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
        System.debug('Lead before insert: ' + JSON.serializePretty(lead));
        
        // Ensure Email / Phone before DML
        if (String.isBlank(lead.Email) && params.containsKey('email')) {
            lead.Email = String.valueOf(params.get('email'));
        }
        
        if (String.isBlank(lead.Phone) && params.containsKey('phone')) {
            lead.Phone = String.valueOf(params.get('phone'));
        }  
        
        if (String.isBlank(lead.LastName)) {
            if (params.containsKey('lastName') && String.isNotBlank((String)params.get('lastName'))) {
                lead.LastName = (String) params.get('lastName');
            } else {
                lead.LastName = 'Unknown';
            }
        }
        
        if (params.containsKey('firstName') && String.isNotBlank((String)params.get('firstName'))) {
            lead.FirstName = (String) params.get('firstName');
        }
    
        // Insert/Upsert the Lead FIRST
        System.debug('About to upsert lead...');
        upsert lead;
        System.debug(' Lead upserted with ID: ' + lead.Id);
        
        // Force create Preferred_Program__c if not created yet
        if (!programGroups.isEmpty() && lead.Id != null) {
            // Re-query to check if Preferred_Program__c were created
            List<Preferred_Program__c> existingPrefs = [
                SELECT Id FROM Preferred_Program__c WHERE Lead__c = :lead.Id
            ];
            
            System.debug('Checking Preferred_Program__c after lead upsert: ' + existingPrefs.size() + ' found');
            
            if (existingPrefs.isEmpty()) {
                System.debug('CRITICAL: No Preferred_Program__c created, forcing creation AFTER lead upsert...');
                // Force create them with the lead ID we now have
                createInitialPreferredPrograms(lead.Id, registrationNumber, programGroups);
            } else {
                System.debug('Preferred_Program__c records already exist: ' + existingPrefs.size());
            }
        }
        
        System.debug('====== FINAL VERIFICATION ======');
        System.debug('Lead ID: ' + lead.Id);
        System.debug('Group_Tag__c: ' + lead.Group_Tag__c);
        
        // Query to verify
        List<Preferred_Program__c> finalCheck = [
            SELECT Id, Full_Program_Name__c, Major__r.Name 
            FROM Preferred_Program__c 
            WHERE Lead__c = :lead.Id
        ];
        System.debug('Preferred_Program__c records found: ' + finalCheck.size());
        for (Preferred_Program__c pref : finalCheck) {
            System.debug(' - ' + pref.Full_Program_Name__c + ' | Major: ' + pref.Major__r.Name);
        }
        System.debug('====== END VERIFICATION ======');
        
        return lead.Id;        
    }
    
    
    // method to update existing lead from params
    private static Lead updateLeadFromParams(
        Lead existingLead,
        Map<String, Object> params,
        String department,
        String typeOfForm
    ) {
        // Get lead source mapping
        Map<String, String> leadSourceGroupMapping =
            getLeadSourceMapping(department, typeOfForm);
        
        Id originalRecordTypeId = existingLead.RecordTypeId;
    
        // Update program groups if provided
        List<Object> programGroups = new List<Object>();
        if (params.containsKey('grpPrograms') && params.get('grpPrograms') != null) {
            programGroups = (List<Object>) params.get('grpPrograms');
        } else if (params.containsKey(FIELD_PROGRAMS) && params.get(FIELD_PROGRAMS) != null) {
            programGroups = (List<Object>) params.get(FIELD_PROGRAMS);
        }
        
        if (!programGroups.isEmpty()) {
            String regNumber = existingLead.Registration_Number__c;
            if (String.isBlank(regNumber)) {
                regNumber = (String) params.get('registrationNumber');
            }
    
            programGroups = validateAndGenerateGroupNumbers(programGroups, regNumber);
            existingLead.Group_Tag__c = JSON.serialize(programGroups);
            
            // update Preferred_Program__c records
            createInitialPreferredPrograms(existingLead.Id, regNumber, programGroups);
        }        
        
        // Update remaining fields
        existingLead = handleFieldAssignmentOfDuplicates(
            leadSourceGroupMapping,
            params,
            existingLead,
            department,
            typeOfForm
        );
        
        // Restore RecordTypeId if it was changed
        if (existingLead.RecordTypeId != originalRecordTypeId) {
            System.debug('Restoring RecordTypeId to original: ' + originalRecordTypeId);
            existingLead.RecordTypeId = originalRecordTypeId;
        }        
    
        return existingLead;
    }

    // Validate groups and generate application numbers
    private static List<Object> validateAndGenerateGroupNumbers(List<Object> programGroups, String registrationNumber) {
        List<Object> updatedGroups = new List<Object>();
        Integer groupCounter = 1;
        
        for (Object groupObj : programGroups) {
            Map<String, Object> groupMap = (Map<String, Object>) groupObj;
            Map<String, Object> updatedGroup = new Map<String, Object>(groupMap);
            
            // Validate programs per group
            if (groupMap.containsKey('programs') && groupMap.get('programs') != null) {
                List<Object> programs = (List<Object>) groupMap.get('programs');
                if (programs.size() > MAX_PROGRAMS_PER_GROUP) {
                    createErrorResponse(400, 'Maximum ' + MAX_PROGRAMS_PER_GROUP + ' programs allowed per group.');
                }
            }
            
            // Generate unique application number for each group
            if (String.isNotBlank(registrationNumber)) {
                String groupAppNumber = registrationNumber + '-G' + groupCounter;
                updatedGroup.put('applicationNumber', groupAppNumber);
            }
            updatedGroups.add(updatedGroup);
            groupCounter++;
        }
        return updatedGroups;
    }
    
    // Create initial preferred programs with group info
    private static void createInitialPreferredPrograms(Id leadId, String registrationNumber, List<Object> programGroups) {
        try {
            System.debug('====== createInitialPreferredPrograms START ======');
            System.debug('Lead ID: ' + leadId);
            System.debug('Registration Number: ' + registrationNumber);
            System.debug('Program groups count: ' + programGroups.size());
            System.debug('Raw programGroups: ' + JSON.serializePretty(programGroups));
            
            List<Preferred_Program__c> programsToInsert = new List<Preferred_Program__c>();
            Set<String> majorNames = new Set<String>();
            
            // First pass: Collect all major names for bulk query
            for (Object groupObj : programGroups) {
                Map<String, Object> groupMap = (Map<String, Object>) groupObj;
                
                // Check for BOTH 'programmes' AND 'programs'
                List<Object> programs = new List<Object>();
                
                if (groupMap.containsKey('programmes') && groupMap.get('programmes') != null) {
                    programs = (List<Object>) groupMap.get('programmes');
                    System.debug('Found programmes key in group');
                } else if (groupMap.containsKey('programs') && groupMap.get('programs') != null) {
                    programs = (List<Object>) groupMap.get('programs');
                    System.debug('Found programs key in group');
                }
                
                for (Object programObj : programs) {
                    Map<String, Object> program = (Map<String, Object>) programObj;
                    String major = (String) program.get('major');
                    if (String.isNotBlank(major)) {
                        majorNames.add(major);
                    }
                }
            }
            
            // Bulk query for Major records
            Map<String, Id> majorNameToId = new Map<String, Id>();
            if (!majorNames.isEmpty()) {
                List<Major__c> majorRecords = [
                    SELECT Id, Name 
                    FROM Major__c 
                    WHERE Name IN :majorNames
                ];
                for (Major__c majorRec : majorRecords) {
                    majorNameToId.put(majorRec.Name, majorRec.Id);
                }
                System.debug('Found ' + majorRecords.size() + ' Major records');
            }
            
            // Second pass: Create Preferred_Program__c records
            Integer groupCounter = 1;
            for (Object groupObj : programGroups) {
                Map<String, Object> groupMap = (Map<String, Object>) groupObj;
                String groupTag = (String) groupMap.get('grptag'); // Changed from 'uggrouptag' to 'grptag'
                String groupAppNumber = registrationNumber + '-G' + groupCounter;
                
                System.debug('Processing group ' + groupCounter + ': ' + groupTag);
                
                // Check for BOTH 'programmes' AND 'programs'
                List<Object> programs = new List<Object>();
                if (groupMap.containsKey('programmes') && groupMap.get('programmes') != null) {
                    programs = (List<Object>) groupMap.get('programmes');
                    System.debug('Found ' + programs.size() + ' programmes in group');
                } else if (groupMap.containsKey('programs') && groupMap.get('programs') != null) {
                    programs = (List<Object>) groupMap.get('programs');
                    System.debug('Found ' + programs.size() + ' programs in group');
                }
                
                Integer programCounter = 1;
                for (Object programObj : programs) {
                    Map<String, Object> program = (Map<String, Object>) programObj;
                    
                    System.debug('Program ' + programCounter + ' keys: ' + program.keySet());
                    
                    // Try to get program name with different key variations
                    String programInterestedIn = null;
                    if (program.containsKey('programInterestedIn')) {
                        programInterestedIn = (String) program.get('programInterestedIn');
                    } else if (program.containsKey('programinterestedin')) {
                        programInterestedIn = (String) program.get('programinterestedin');
                    } else if (program.containsKey('ProgramInterestedIn')) {
                        programInterestedIn = (String) program.get('ProgramInterestedIn');
                    }
                    
                    String majorName = (String) program.get('major');
                    
                    System.debug('Extracted - Program: ' + programInterestedIn + ' | Major: ' + majorName);
                    
                    if (String.isNotBlank(programInterestedIn)) {
                        Preferred_Program__c prefProgram = new Preferred_Program__c();
                        prefProgram.Lead__c = leadId;
                        prefProgram.Program_Group_Tag__c = groupTag;
                        prefProgram.Application_Number__c = groupAppNumber;
                        prefProgram.Full_Program_Name__c = programInterestedIn;
                        
                        // Set Major if we found it
                        if (String.isNotBlank(majorName) && majorNameToId.containsKey(majorName)) {
                            prefProgram.Major__c = majorNameToId.get(majorName);
                        }
                        
                        programsToInsert.add(prefProgram);
                        System.debug('Will create Preferred_Program__c: ' + programInterestedIn);
                    } else {
                        System.debug('⚠Could not extract program name from: ' + JSON.serialize(program));
                    }
                    programCounter++;
                }
                groupCounter++;
            }
            
            // Insert records
            if (!programsToInsert.isEmpty()) {
                // Delete any existing records first
                List<Preferred_Program__c> existingRecords = [SELECT Id FROM Preferred_Program__c WHERE Lead__c = :leadId];
                if (!existingRecords.isEmpty()) {
                    System.debug('Deleting ' + existingRecords.size() + ' existing Preferred_Program__c records');
                    delete existingRecords;
                }
                
                insert programsToInsert;
                System.debug('Successfully created ' + programsToInsert.size() + ' Preferred_Program__c records');
                
                // Verify the records were created
                List<Preferred_Program__c> createdRecords = [
                    SELECT Id, Full_Program_Name__c, Major__r.Name 
                    FROM Preferred_Program__c 
                    WHERE Lead__c = :leadId
                ];
                System.debug('Verification - Found ' + createdRecords.size() + ' Preferred_Program__c records after insert');
                for (Preferred_Program__c pref : createdRecords) {
                    System.debug(' - ' + pref.Full_Program_Name__c + ' | Major: ' + pref.Major__r.Name);
                }
            } else {
                System.debug('No Preferred_Program__c records to insert');
            }
            
            System.debug('====== createInitialPreferredPrograms END ======');
            
        } catch (Exception e) {
            System.debug('ERROR in createInitialPreferredPrograms: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
        }
    }

    /**
    * @description - Checking duplicate lead based on combination of Email+ Phone+ Preferred Program 
                     and if the matching lead is found and lead source of matching lead is not 'AURIS'
                     then updates the record with payload data and lead source gets added into
                     multiple lead source for all record type except UG
    * @param payloadMap payload
    * @param department master department
    * @param  typeOfForm from type
    * @return updated lead
    */
    
    // Updated duplicate handling to prioritize Registration Number
    public static Lead handleDuplicateLeadDefault(Map<String, Object> payloadMap, String department, String typeOfForm) {
        String registrationNumber = (String) payloadMap.get('registrationNumber');
        
        // First check by Registration Number
        if (String.isNotBlank(registrationNumber)) {
            List<Lead> matchingLead = [SELECT Id, Phone, Registration_Number__c, Email, LeadSource,
                                      Preferred_Programme__c, Multi_Select_Lead_Source__c,
                                      Name_of_University_College__c, Department__c, State, Country,
                                      RecordTypeId, LastName, FirstName 
                                      FROM Lead 
                                      WHERE Registration_Number__c = :registrationNumber 
                                      AND Department__c = :department
                                      LIMIT 1];
            
            if (!matchingLead.isEmpty()) {
                Lead newLead = matchingLead[0];
                
                // Merge program groups
                if (payloadMap.containsKey(FIELD_PROGRAMS) && payloadMap.get(FIELD_PROGRAMS) != null) {
                    List<Object> newGroups = (List<Object>) payloadMap.get(FIELD_PROGRAMS);
                    newGroups = validateAndGenerateGroupNumbers(newGroups, registrationNumber);
                    mergeProgramGroups(newLead, newGroups);
                }
                
                // Update other fields
                Map<String, String> leadSourceGroupMapping = getLeadSourceMapping(department, typeOfForm);
                newLead = handleFieldAssignmentOfDuplicates(leadSourceGroupMapping, payloadMap, newLead, department, typeOfForm);
                return newLead;
            }
        }
        
        // Fallback to phone/email check
        return handleDuplicateLeadByPhoneEmail(payloadMap, department, typeOfForm);
    }    
    
    
    /*
    public static Lead handleDuplicateLeadDefault(Map<String, Object> payloadMap,String department,String typeOfForm){
        String matchingphone=(String) payloadMap.get(StaticValuesUtil.FIELD_PHONE);
        String registrationNumber = (String) payloadMap.get('registrationNumber');

        Map<String, String> leadSourceGroupMapping = new Map<String, String>();
            // Retrieve field mappings from custom metadata
            List<WebFormFieldMapping__mdt> fieldMappings = [
                SELECT Department__c, JSON_Key__c, Label,
                TypeOfForm__c,LeadSourceGroup__c, Datatype__c
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
        List<Lead> matchingLead = [SELECT Id, Phone, Registration_Number__c, Email,LeadSource,Preferred_Programme__c,Multi_Select_Lead_Source__c,
                                  Name_of_University_College__c,Department__c,State, Country
                                  FROM Lead 
                                  WHERE Phone LIKE :matchingphone 
                                  AND Email = :matchingEmail AND Department__c = :matchingDepartment
                                  AND Preferred_Programme__c = :matchingPreferedProgrm
                                   LIMIT 1];
        Lead newLead =null;
        if(!matchingLead.isEmpty()){
            newLead = matchingLead[0];

            if(newLead.LeadSource == 'AURIS' ){
                newLead = matchingLead[0];

                //Get the current value of the multi-picklist field
                Set<String> picklistValues = new Set<String>();
                if (String.isNotBlank(newLead.Multi_Select_Lead_Source__c)) {
                    picklistValues.addAll(newLead.Multi_Select_Lead_Source__c.split(';'));
                }
                // Add the new value if it doesn't already exist
                String websiteLeadSource;

                
                if (leadSourceGroupMapping.containsKey(typeOfForm)) {
                    websiteLeadSource = leadSourceGroupMapping.get(typeOfForm);
                }
                picklistValues.add(websiteLeadSource);
                //Save the updated values back to the field
                newLead.Multi_Select_Lead_Source__c = String.join(new List<String>(picklistValues), ';');
              
            }
            else{
                newLead = handleFieldAssignmentOfDuplicates(fieldMappings,payloadMap,newLead,department,typeOfForm);

              
                
            }
            
            return newLead;
        }
        return newLead;
    }
    */
    
    

    /** 
    * @description - Checking duplicate lead based on combination of Email+ Phone and if the matching
                     lead is found and matching lead's lead source is not 'AURIS' then
                     updates the record with payload data and lead source gets added into
                     multiple lead source for Undergraduation record type
                     * @param payloadMap payload
    * @param department UG department
    * @param  typeOfForm from type
    * @return updated lead
    **/
  
    // Updated UG duplicate handling
    public static Lead handleDuplicateLeadUnderGraduation(Map<String, Object> payloadMap, String department, String typeOfForm) {
        String registrationNumber = (String) payloadMap.get('registrationNumber');
        
        // First check by Registration Number
        if (String.isNotBlank(registrationNumber)) {
            List<Lead> matchingLead = [SELECT Id, Phone, Registration_Number__c, Email, LeadSource,
                                      Preferred_Programme__c, Multi_Select_Lead_Source__c,
                                      Name_of_University_College__c, Department__c, State, Country,
                                      RecordTypeId, LastName, FirstName
                                      FROM Lead 
                                      WHERE Registration_Number__c = :registrationNumber 
                                      AND Department__c = :department
                                      LIMIT 1];
            
            if (!matchingLead.isEmpty()) {
                Lead newLead = matchingLead[0];
                
                // Merge program groups
                if (payloadMap.containsKey(FIELD_PROGRAMS) && payloadMap.get(FIELD_PROGRAMS) != null) {
                    List<Object> newGroups = (List<Object>) payloadMap.get(FIELD_PROGRAMS);
                    newGroups = validateAndGenerateGroupNumbers(newGroups, registrationNumber);
                    mergeProgramGroups(newLead, newGroups);
                }
                
                // Update other fields
                Map<String, String> leadSourceGroupMapping = getLeadSourceMapping(department, typeOfForm);
                newLead = handleFieldAssignmentOfDuplicates(leadSourceGroupMapping, payloadMap, newLead, department, typeOfForm);
                return newLead;
            }
        }
        
        // Fallback to phone/email check
        return handleDuplicateLeadByPhoneEmail(payloadMap, department, typeOfForm);
    }    
    
    
    /*
    public static Lead handleDuplicateLeadUnderGraduation(Map<String, Object> payloadMap,String department,String typeOfForm){
        String matchingphone=(String) payloadMap.get(StaticValuesUtil.FIELD_PHONE);
        
        Map<String, String> leadSourceGroupMapping = new Map<String, String>();
            // Retrieve field mappings from custom metadata
            List<WebFormFieldMapping__mdt> fieldMappings = [
                SELECT Department__c, JSON_Key__c, Label,
                TypeOfForm__c,LeadSourceGroup__c, Datatype__c
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
        String matchingDepartment =department;
        List<Lead> matchingLead = [SELECT Id, Phone, Registration_Number__c, Email,LeadSource,Preferred_Programme__c,Multi_Select_Lead_Source__c,
                                  Name_of_University_College__c,Department__c,State,Country
                                  FROM Lead 
                                  WHERE Phone LIKE :matchingphone 
                                  AND Email = :matchingEmail AND Department__c=:matchingDepartment
                                   LIMIT 1];
        
        Lead newLead =null;
        if(!matchingLead.isEmpty()){
            newLead = matchingLead[0];

            if(newLead.LeadSource == 'AURIS' ){
                newLead = matchingLead[0];

                //Get the current value of the multi-picklist field
                Set<String> picklistValues = new Set<String>();
                if (String.isNotBlank(newLead.Multi_Select_Lead_Source__c)) {
                    picklistValues.addAll(newLead.Multi_Select_Lead_Source__c.split(';'));
                }
                // Add the new value if it doesn't already exist
                String websiteLeadSource;

                if (leadSourceGroupMapping.containsKey(typeOfForm)) {
                    websiteLeadSource = leadSourceGroupMapping.get(typeOfForm);
                }

                picklistValues.add(websiteLeadSource);
                //Save the updated values back to the field
                newLead.Multi_Select_Lead_Source__c = String.join(new List<String>(picklistValues), ';');

            }
            else{
           newLead = handleFieldAssignmentOfDuplicates(fieldMappings,payloadMap,newLead,department,typeOfForm);
             
                
            } 
            
            return newLead;
        }
        return newLead;
    }
    */

    // Fallback duplicate check by phone/email
    private static Lead handleDuplicateLeadByPhoneEmail(Map<String, Object> payloadMap, String department, String typeOfForm) {
        String matchingphone = (String) payloadMap.get(StaticValuesUtil.FIELD_PHONE);
        
        if (matchingphone != null) {
            matchingphone = '%' + matchingphone + '%';
        }
        
        String matchingEmail = (String) payloadMap.get(StaticValuesUtil.FIELD_EMAIL);
        List<Lead> matchingLead = [SELECT Id, Phone, Registration_Number__c, Email, LeadSource,
                                  Preferred_Programme__c, Multi_Select_Lead_Source__c,
                                  Name_of_University_College__c, Department__c, State, Country, Group_Tag__c,
                                  RecordTypeId, LastName, FirstName  
                                  FROM Lead 
                                  WHERE Phone LIKE :matchingphone 
                                  AND Email = :matchingEmail 
                                  AND Department__c = :department
                                  LIMIT 1];
        
        if (!matchingLead.isEmpty()) {
            Lead newLead = matchingLead[0];
            
            // Merge program groups
            if (payloadMap.containsKey(FIELD_PROGRAMS) && payloadMap.get(FIELD_PROGRAMS) != null) {
                List<Object> newGroups = (List<Object>) payloadMap.get(FIELD_PROGRAMS);
                String registrationNumber = newLead.Registration_Number__c;
                if (String.isBlank(registrationNumber)) {
                    registrationNumber = (String) payloadMap.get('registrationNumber');
                }
                newGroups = validateAndGenerateGroupNumbers(newGroups, registrationNumber);
                mergeProgramGroups(newLead, newGroups);
            }
            
            // Update other fields
            Map<String, String> leadSourceGroupMapping = getLeadSourceMapping(department, typeOfForm);
            return handleFieldAssignmentOfDuplicates(leadSourceGroupMapping, payloadMap, newLead, department, typeOfForm);
        }
        
        return null;
    }    
    
    // MODIFICATION: Merge program groups*************************
    private static void mergeProgramGroups(Lead existingLead, List<Object> newGroups) {
        List<Object> existingGroups = new List<Object>();
        
        if (String.isNotBlank(existingLead.Group_Tag__c)) {
            existingGroups = (List<Object>) JSON.deserializeUntyped(existingLead.Group_Tag__c);
        }
        
        // Create map of existing groups by tag
        Map<String, Map<String, Object>> existingGroupsByTag = new Map<String, Map<String, Object>>();
        for (Object groupObj : existingGroups) {
            Map<String, Object> groupMap = (Map<String, Object>) groupObj;
            String tag = (String) groupMap.get('uggrouptag');
            if (tag != null) {
                existingGroupsByTag.put(tag, groupMap);
            }
        }
        
        // Merge new groups
        for (Object groupObj : newGroups) {
            Map<String, Object> newGroup = (Map<String, Object>) groupObj;
            String tag = (String) newGroup.get('uggrouptag');
            
            if (tag != null) {
                existingGroupsByTag.put(tag, newGroup); // Replace or add
            }
        }
        
        // Limit to MAX_GROUPS
        List<Object> mergedGroups = new List<Object>();
        Integer count = 0;
        for (Map<String, Object> groupMap : existingGroupsByTag.values()) {
            if (count < MAX_GROUPS) {
                mergedGroups.add(groupMap);
                count++;
            }
        }
        
        existingLead.Group_Tag__c = JSON.serialize(mergedGroups);
    }  
    
    // Get lead source mapping helper
    private static Map<String, String> getLeadSourceMapping(String department, String typeOfForm) {
        Map<String, String> leadSourceGroupMapping = new Map<String, String>();
        List<WebFormFieldMapping__mdt> fieldMappings = [
            SELECT Department__c, JSON_Key__c, Label,
            TypeOfForm__c, LeadSourceGroup__c, Datatype__c
            FROM WebFormFieldMapping__mdt
            WHERE Department__c = :department 
              AND TypeOfForm__c = :typeOfForm
        ];
        
        for (WebFormFieldMapping__mdt mapping : fieldMappings) {
            leadSourceGroupMapping.put(mapping.TypeOfForm__c, mapping.LeadSourceGroup__c);
        }
        
        return leadSourceGroupMapping;
    }
    
    // Updated field assignment
    public static Lead handleFieldAssignmentOfDuplicates(Map<String, String> leadSourceGroupMapping, 
                                                       Map<String, Object> payloadMap, 
                                                       Lead newLead, 
                                                       String department, 
                                                       String typeOfForm) {
        List<WebFormFieldMapping__mdt> fieldMappings = [
            SELECT Department__c, JSON_Key__c, Label,
            TypeOfForm__c, LeadSourceGroup__c, Datatype__c
            FROM WebFormFieldMapping__mdt
            WHERE Department__c = :department 
              AND TypeOfForm__c = :typeOfForm
        ];

        for(WebFormFieldMapping__mdt mapping : fieldMappings){
            String jsonKey = mapping.JSON_Key__c;
            String leadField = mapping.Label;
            String type = mapping.Datatype__c;

            if (payloadMap.containsKey(jsonKey) && payloadMap.get(jsonKey) != null)  {
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
                
                newLead.put(leadField, typedVal);
            }
        }

        newLead.Admission_Year__c = System.label.Admission_Year;
        newLead.Department__c = department;
        newLead.TypeOfForm__c = typeOfForm;
        
        if (leadSourceGroupMapping.containsKey(typeOfForm)) {
            newLead.LeadSource = leadSourceGroupMapping.get(typeOfForm);
        }
        
        if (String.isBlank((String)newLead.get('lastName'))) {
            newLead.LastName = '.';
        }
        
        if (payloadMap.containsKey('lastName')) {
            String lastName = (String) payloadMap.get('lastName');
            newLead.LastName = (lastName != null && lastName.trim().length() > 0) ? lastName : '.';
        }

        // Phone number formatting with country code
        String country = null;
        Integer countryLength = 0;
        if(payloadMap.containsKey('country') && payloadMap.get('country') != null && payloadMap.get('country') != newLead.Country ){
            country = (String) payloadMap.get('country');
            countryLength = country.length();
        }
        
        if (payloadMap.containsKey('phone') && payloadMap.get('phone') != null ) {
            if (payloadMap.containsKey('country') && payloadMap.get('country') != null && countryLength > 0 && payloadMap.get('country') != newLead.Country ) {
                newLead.Phone = LeadPhoneUpdater.generatePhoneNumberWithCountryCode(country, (String) payloadMap.get('phone'));
                newLead.Country = (String) payloadMap.get('country');
                if(payloadMap.containsKey('state') && payloadMap.get('state') != null && payloadMap.get('state') != newLead.State){
                    newLead.State = (String)payloadMap.get('state');
                }
            } 
        }

        // Added leadsource to multipicklist field
        Set<String> picklistValues = new Set<String>();
        if (String.isNotBlank(newLead.Multi_Select_Lead_Source__c)) {
            picklistValues.addAll(newLead.Multi_Select_Lead_Source__c.split(';'));
        }
        
        String websiteLeadSource = leadSourceGroupMapping.containsKey(typeOfForm) ? leadSourceGroupMapping.get(typeOfForm) : null;
        if (websiteLeadSource != null) {
            picklistValues.add(websiteLeadSource);
        }
        
        newLead.Multi_Select_Lead_Source__c = String.join(new List<String>(picklistValues), ';');
        return newLead;
    }    
    
    /*
    public static Lead handleFieldAssignmentOfDuplicates(List<WebFormFieldMapping__mdt> fieldMappings,Map<String,Object> payloadMap,Lead newLead,String department,String typeOfForm){
        Map<String, String> leadSourceGroupMapping = new Map<String, String>();

        for(WebFormFieldMapping__mdt mapping : fieldMappings){
            String jsonKey = mapping.JSON_Key__c;
            String leadField = mapping.Label;
            String type = mapping.Datatype__c;
            leadSourceGroupMapping.put(mapping.TypeOfForm__c, mapping.LeadSourceGroup__c);

            if (payloadMap.containsKey(jsonKey) && payloadMap.get(jsonKey) != null)  {
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
                
                newLead.put(leadField, typedVal);
            }
        }

                    newLead.Admission_Year__c = System.label.Admission_Year;
                    newLead.Department__c = department;
                    newLead.TypeOfForm__c = typeOfForm;
                    // if(newLead.Preferred_Programme__c!= null){
                    //     newLead.Programme_Interested_in__c = newLead.Preferred_Programme__c;
                    // }
                    // Assign LeadSourceGroup dynamically based on typeOfForm
                if (leadSourceGroupMapping.containsKey(typeOfForm)) {
                    newLead.LeadSource = leadSourceGroupMapping.get(typeOfForm);
                }
                if (String.isBlank((String)newLead.get('lastName'))) {
                    newLead.LastName = '.';
                }
                if (payloadMap.containsKey('lastName')) {
                    String lastName = (String) payloadMap.get('lastName');
                    newLead.LastName = (lastName != null && lastName.trim().length() > 0) ? lastName : '.';
                }

                // Logic for phone number formatting with country code
                // Done below changes for resolving issue of getting null in phone field value
                String country= null;
                Integer countryLength=0;
                if(payloadMap.containsKey('country') && payloadMap.get('country') != null && payloadMap.get('country')!=newLead.Country ){
                    country = (String) payloadMap.get('country');
                    countryLength = country.length();
                }
                
                
                if (payloadMap.containsKey('phone') && payloadMap.get('phone') != null ) {
                    if (payloadMap.containsKey('country') && payloadMap.get('country') != null && countryLength > 0 && payloadMap.get('country')!=newLead.Country ) {
                            
                        newLead.Phone = LeadPhoneUpdater.generatePhoneNumberWithCountryCode(country, (String) payloadMap.get('phone'));
                        newLead.Country = (String) payloadMap.get('country');
                        if(payloadMap.containsKey('state') && payloadMap.get('state') != null && payloadMap.get('state')!=newLead.State){
                            newLead.State =(String)payloadMap.get('state');
                        }

                    } 
                }

                //code to add leadsource in mutipicklist field
                Set<String> picklistValues = new Set<String>();
                if (String.isNotBlank(newLead.Multi_Select_Lead_Source__c)) {
                    picklistValues.addAll(newLead.Multi_Select_Lead_Source__c.split(';'));
                }
                // Add the new value if it doesn't already exist
                String websiteLeadSource;

                if (leadSourceGroupMapping.containsKey(typeOfForm)) {
                    websiteLeadSource = leadSourceGroupMapping.get(typeOfForm);
                }

                picklistValues.add(websiteLeadSource);
                // Save the updated values back to the field
                newLead.Multi_Select_Lead_Source__c = String.join(new List<String>(picklistValues), ';'); 

                return newLead;

    }
    */

    /**
    * @description
    * @param department master department
    * @return updated lead
     * **************************************************************************************** 
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
                WHERE Department__c = :department 
                LIMIT 1
            ];

            if (!mappings.isEmpty()) {
                system.debug('mapping is available');
                
                return mappings[0].Record_Type_Id__c;
            }
            else{
                system.debug('mapping is not available for department');
                createErrorResponse(400, 'Invalid department specified.');

            }
           
            return null;
        } catch (Exception e) {
            
            return null;
        }
    }


    /**Commented by Neha for dynamically add fields
    * @description
    * @param leadParams lead parameters
    * @return created lead
    */


    public static Lead saveLeadFieldMappings(LeadRecordParams leadParams) {
        try {
            Lead newLead = new Lead();
            newLead.RecordTypeId = leadParams.recordTypeId;
            newLead.Department__c = leadParams.department; // CRITICAL
            newLead.TypeOfForm__c = leadParams.typeOfForm;
            
            System.debug('saveLeadFieldMappings - Setting:');
            System.debug('RecordTypeId: ' + leadParams.recordTypeId);
            System.debug('Department__c: ' + leadParams.department);
            System.debug('TypeOfForm__c: ' + leadParams.typeOfForm);
            //newLead.RecordTypeId = recordTypeId;
            Map<String, String> leadSourceGroupMapping = new Map<String, String>();

            // Retrieve field mappings from custom metadata
            List<WebFormFieldMapping__mdt> fieldMappings = [
                SELECT Department__c, JSON_Key__c, Label, Datatype__c,
                TypeOfForm__c,LeadSourceGroup__c
                FROM WebFormFieldMapping__mdt
                WHERE Department__c = :leadParams.department 
                  AND TypeOfForm__c = :leadParams.typeOfForm
            ];
            if(fieldMappings.isEmpty()){
                System.debug('***********Field mappings found: ' + fieldMappings.size());
            }
            system.debug('The fieldMappings are '+fieldMappings);
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
                if(!leadParams.params.containsKey('admissionYear') || leadParams.params.get('admissionYear') == null){
                    newLead.Admission_Year__c = System.label.Admission_Year;
                }
                
                newLead.Department__c = leadParams.department;
                newLead.TypeOfForm__c = leadParams.typeOfForm;
                newLead.RecordTypeId = leadParams.recordTypeId;

            if (leadSourceGroupMapping.containsKey(leadParams.typeOfForm)) {
                newLead.LeadSource = leadSourceGroupMapping.get(leadParams.typeOfForm);
            }
            // Assign to Multi_Select_Lead_Source__c if LeadSource is set
            if (newLead.LeadSource != null) {
                newLead.Multi_Select_Lead_Source__c = newLead.LeadSource;
            }
            if (String.isBlank((String)newLead.get('lastName'))) {
                newLead.LastName = '.';
            }
            if (leadParams.params.containsKey('lastName')) {
                String lastName = (String) leadParams.params.get('lastName');
                newLead.LastName = (lastName != null && lastName.trim().length() > 0) ? lastName : '.';
            }

            // Logic for phone number formatting with country code 
            // Done below changes for resolving issue of getting null in phone field value
            String country= null;
            Integer countryLength=0;
            if(leadParams.params.containsKey('country') && leadParams.params.get('country') != null){
                country = (String) leadParams.params.get('country');
                countryLength = country.length();
                newLead.Country = country;
            }

            if (leadParams.params.containsKey('phone') && leadParams.params.get('phone') != null ) {
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
        }
        catch(Exception e){
            throw new CustomException('Error creating Lead record: ' + e.getMessage());

        }
    
    }


        
    
    /**
    * @description
    * Class Name : LeadRecordParams
    * Create By : Preksha Chauhan
    * Create Date : 06/26/2024
    * Description : This class encapsulates the parameters for creating a Lead record. 
    *               It contains the JSON parameters, RecordTypeId, department, and typeOfForm.
    ****************************************************************************************
    */
    public class LeadRecordParams {
        /**
        * @description
        */
        public Map<String, Object> params { get; set; }
         /**
        * @description
        */
        public Id recordTypeId { get; set; }
         /**
        * @description
        */
        public String department { get; set; }
         /**
        * @description
        */
        public String typeOfForm { get; set; }

         /**
        * @description
        * @param params lead parameters
        * @param recordTypeId record type Id of lead
        * @param department department of lead
        * @param typeOfForm of lead
        */
        public LeadRecordParams(Map<String, Object> params, Id recordTypeId, String department, String typeOfForm) {
            this.params = params;
            this.recordTypeId = recordTypeId;
            this.department = department;
            this.typeOfForm = typeOfForm;
        }
    }
    /**
    * @description
    * @param statusCode status code of Http request
    * @param message message of Http request
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
    * @description
     * **************************************************************************************** 
    * Method Name : CustomException
    * Create By : Preksha Chauhan
    * Create Date : 06/25/2024
    * Description : This class defines a custom exception to be used within the LeadRestService class. 
    *               It extends the base Exception class to provide custom error handling.
    ****************************************************************************************
    ***/
    public class CustomException extends Exception {}
}