/**
 * @description
* Create By        : Preksha Chauhan
* Company          : GetonCRM Solutions
* Devloper Name    : Preksha Chauhan
* Create Date      : 07/10/2024
* Class Name       : saveWebTo_YourProfileData
* URL Mapping      : saveLeadRelatedData
* Description      : This class provides RESTful API endpoints for creating and managing Lead 
*                    records in Salesforce based on data received from the Auris system. 
*                    It handles various form types (Undergraduate Registration, Master Registration, 
*                    and Master Admission), parses JSON request bodies, validates required fields, 
*                    checks for duplicate leads, inserts related records (such as educational details, 
*                    parent information, and employment history), and manages custom exceptions and error logs.
**********************************************************************************************/ 

// CHANGE LOG
// ─────────────────────────────────────────────────────────────────────────────
// Author              Date            Description
// ─────────────────────────────────────────────────────────────────────────────
// Jitendra Varma      29-Oct-2026     Fixed duplicate UG leads created when the
//                                     phone in the payload has '+', spaces or
//                                     dashes. handleDuplicateLeadUndergraduation
//                                     now matches by Registration Number first,
//                                     then by Email + last 10 digits of phone.
//                                     handleDuplicateLeadMasters also matches on
//                                     the last 10 digits of phone. A payload
//                                     phone starting with '+' is now saved as
//                                     sent instead of getting the country code
//                                     added a second time. UG Auris_Admission_Form
//                                     now requires 'leadId' and updates exactly
//                                     that Lead; missing, invalid or mismatched
//                                     leadId is an error. email / phone / mobile
//                                     / admissionYear are optional with leadId.
//                                     Masters / PhD Admission Form unchanged.
// Mihir Ramoliya      26-Mar-2026     Rewrote UG group storage model.
//                                     Groups now stored in dedicated Lead slot
//                                     fields (Group_1__c … Group_4__c) instead
//                                     of a single JSON blob in Group_Tag__c.
//                                     Added max-group validation using
//                                     UG_Validation_Settings__c custom setting.
//                                     Added three payload validations:
//                                     (1) grpPrograms not null,
//                                     (2) grpPrograms not empty,
//                                     (3) every group has grptag + programmes.
//                                     [14-Oct-2026: programmes no longer required per group]
//                                     handleDuplicateLeadUndergraduation now
//                                     queries all Group slot fields so the
//                                     returned lead can be used for slot
//                                     read/write without a second query.
// Rishav Raj          (prior)         Updated processSingleRecord with
//                                     Registration Number focus.
// Preksha Chauhan     07-Oct-2024     Original implementation of
//                                     processSingleRecord.
// =============================================================================

@RestResource(URLMapping = '/saveLeadRelatedData')
/**
 * @description - This class provides RESTful API endpoints for creating and managing Lead 
                    records in Salesforce based on data received from the Auris system. 
                    It handles various form types (Undergraduate Registration, Master Registration, 
                    and Master Admission), parses JSON request bodies, validates required fields, 
                    checks for duplicate leads, inserts related records (such as educational details, 
                    parent information, and employment history), and manages custom exceptions and error logs.
*/
global class saveWebTo_YourProfileData {

    /**
    * @description
     Method Name : handleAurisData
    * Created By : Preksha Chauhan
    * Created Date : 07/10/2024
    * Description : This method processes and handles incoming data from the Auris system.
    *               It is responsible for:
    *               1. Parsing the incoming JSON payload to extract relevant data.
    *               2. Determining the department and form type from the payload to route
    *                  the data processing to the appropriate methods.
    *               3. Fetching the Record Type ID based on the department specified in the payload.
    *               4. Validating the presence of required fields such as `registrationNumber`.
    *               5. Checking for an existing lead with the same `registrationNumber`:
    *                  - If an existing lead is found, it updates the lead with new values from the payload.
    *                  - If no existing lead is found, it creates a new lead using the data from the payload.
    *               6. Updating the `Auris_Last_Updated_Timestamp__c` field of the lead with the current timestamp.
    *               7. Performing an upsert operation on the lead record, using `Registration_Number__c`
    *                  as the external ID.
    *               8. Calling department-specific methods based on the `department` and `typeOfForm`
    *                  values to handle additional form details.
    *               9. Returning the lead ID in the response if the operation is successful.
    *               10. Logging errors and providing appropriate error responses if an exception occurs.
    *
    * Parameters:
    * @param payload - A JSON string containing the data for the registration or admission form.
    *                 The data includes fields such as `registrationNumber`, `firstName`, `email`, etc.
    * @param leadId - The ID of the Lead record being processed or created.
    ********************************************************************************************/
    @HttpPost
    global static void handleAurisData() {
        RestRequest request = RestContext.request;
        RestResponse response = RestContext.response;
        List<String> leadIds = new List<String>(); 
        List<Map<String, Object>> errorList = new List<Map<String, Object>>();
    
        try {
            String payload = request.requestBody.toString();
            Object payloadObj = JSON.deserializeUntyped(payload);
    
            if (payloadObj instanceof List<Object>) {
                for (Object recordObj : (List<Object>) payloadObj) {
                    Map<String, Object> payloadMap = (Map<String, Object>) recordObj;
                    try {
                        leadIds.add(processSingleRecord(payloadMap));
                    } catch (Exception e) {
                        logFailedLead(JSON.serialize(payloadMap), e, (String)payloadMap.get('registrationNumber'));
                        errorList.add(new Map<String, Object>{
                            'registrationNumber' => payloadMap.get('registrationNumber'),
                            'errorMessage' => e.getMessage()
                        });
                    }
                }
            } else if (payloadObj instanceof Map<String, Object>) {
                Map<String, Object> payloadMap = (Map<String, Object>) payloadObj;
                try {
                    leadIds.add(processSingleRecord(payloadMap));
                } catch (Exception e) {
                    logFailedLead(JSON.serialize(payloadMap), e, (String)payloadMap.get('registrationNumber'));
                    errorList.add(new Map<String, Object>{
                        'registrationNumber' => payloadMap.get('registrationNumber'),
                        'errorMessage' => e.getMessage()
                    });
                }
            }
    
            // Build response
            Map<String, Object> responseMap = new Map<String, Object>();
            responseMap.put('leadIds', leadIds);
            responseMap.put('errors', errorList);
    
            response.responseBody = Blob.valueOf(JSON.serialize(responseMap));
            if(errorList.isEmpty()){
                response.statusCode = 200; // All records processed successfully
            } else {
                response.statusCode = 500; // All records failed
            }
            response.addHeader('Content-Type', 'application/json');
        } catch (Exception e) {
            response.responseBody = Blob.valueOf('{"error": "Unexpected failure: ' + e.getMessage() + '"}');
            response.statusCode = 500;
            response.addHeader('Content-Type', 'application/json');
        }
    }
    

    /**
     * @description
     * ****************************************************************************************
    * Method Name : processSingleRecord
    * Created By : Preksha Chauhan
    * Created Date : 07/10/2024
    // Modified By : Rishav Raj    — Registration Number focus
    // Modified By : Mihir Ramoliya — 28-Mar-2026 — UG group slot field model,
    //               payload validations, max-group count check
    * Description : This method processes a single record from the incoming payload to handle 
    *               the creation or updating of a Lead record in Salesforce. It is responsible for:
    *               1. Extracting the `department` and `typeOfForm` from the provided payload.
    *               2. Fetching the appropriate Record Type ID based on the `department` value.
    *               3. Validating the presence of the required field `registrationNumber`.
    *               4. Checking for an existing Lead record with the same `registrationNumber`:
    *                  - If an existing lead is found, it updates the Lead with new values from the payload.
    *                  - If no existing lead is found, it creates a new Lead record using the data from the payload.
    *               5. Setting the `Auris_Last_Updated_Timestamp__c` field of the Lead with the current timestamp, 
    *                  formatted as a string in `yyyy-MM-dd:HH:mm:ss` format.
    *               6. Performing an upsert operation on the Lead record using `Registration_Number__c` 
    *                  as the external ID, ensuring that CRUD permissions are validated before the operation.
    *               7. Based on the `department` and `typeOfForm` values, calling the appropriate methods 
    *                  to handle additional processing specific to the form type:
    *                  - `Undergraduation` department:
    *                    - Calls `handleUndergraduationRegistrationForm` if the form type is `Auris_Registration_Form`.
    *                    - Calls `handleUndergraduationAdmissionForm` if the form type is `Auris_Admission_Form`.
    *                  - `Masters` department:
    *                    - Calls `handleMasterRegistrationForm` if the form type is `Auris_Registration_Form`.
    *                    - Calls `handleMasterAdmissionForm` if the form type is `Auris_Admission_Form`.
    *               8. Returning the Lead ID if the operation is successful.
    *               9. Throwing exceptions with appropriate error messages if any required field is missing 
    *                  or if there is an issue with permissions or record type mapping.
    *
    * Parameters:
    * @param payloadMap - A Map<String, Object> containing the data for the registration or admission form.
    *                    The data includes fields such as `registrationNumber`, `firstName`, `email`, etc.
    *
    * @return String - The ID of the Lead record that was created or updated.
    ********************************************************************************************/
    
     // Modify By: Rishav Raj
    // MODIFICATION: Updated processSingleRecord with Registration Number focus
    public static String processSingleRecord(Map<String, Object> payloadMap) {
        String department = (String) payloadMap.get('department');
        String typeOfForm = (String) payloadMap.get('typeOfForm');
        String registrationNumber = (String) payloadMap.get('registrationNumber');
    
        // Validate required fields
        if (String.isBlank(registrationNumber)) {
            throw new CustomException('Missing required field: registrationNumber');
        }
        
        if (String.isBlank(department)) {
            throw new CustomException('Missing required field: department');
        }
    
        String recordTypeId = fetchRecordTypeId(department);
        if (recordTypeId == null) {
            throw new CustomException('Invalid department or no record type mapping found');
        }

        // Added By : Jitendra Varma | 29-Oct-2026
        // A UG Admission Form must carry the 'leadId' returned by the Registration Form
        // call. That exact Lead is updated - no duplicate matching and no new Lead. A
        // missing, blank, invalid or mismatched leadId is rejected. Other departments'
        // Admission Forms are unchanged (duplicate matching, any 'leadId' key ignored).
        Lead admissionLead = (typeOfForm == AURIS_ADMISSION_FORM && department.equalsIgnoreCase(UG_DEPARTMENT))
            ? resolveAdmissionLead(payloadMap, department, registrationNumber)
            : null;

        // 🔹 Handle duplicates (same logic you already have)
        Lead existingLead, newLead;
        List<Object> programGroups = new List<Object>();

        // ── START: Undergraduation department processing ───────────────────────────
        // Modified By : Mihir Ramoliya | 28-Mar-2026
        // Purpose     : Run UG-specific duplicate check, validate and store
        //               grpPrograms data into dedicated lead slot fields.
        if (department.equalsIgnoreCase('Undergraduation')) {

            // Duplicate check — matches by Email + Phone for Undergraduation.
            // Returns the existing lead (with all slot fields queried) or null.
            // Admission Form: the Lead given by leadId is used instead.
            existingLead = (admissionLead != null)
                ? admissionLead
                : handleDuplicateLeadUndergraduation(payloadMap, department, typeOfForm);
            newLead      = (existingLead != null) ? existingLead : new Lead(RecordTypeId = recordTypeId);

            // ── START: Auris_Registration_Form path ───────────────────────────
            // Added By : Mihir Ramoliya | 02-Apr-2026
            // Purpose  : Student is signing up for the first time. This payload
            //            contains only personal and contact information.
            //            grpPrograms is not sent and must not be validated.
            //            Skip all group slot logic entirely.
            if (typeOfForm == 'Auris_Registration_Form') {

                System.debug('UG Auris_Registration_Form — skipping grpPrograms logic.');
                // programGroups intentionally left empty.
                // No slot writes, no insertPreferredPrograms call will happen.

            // ── START: Auris_Admission_Form path ──────────────────────────────
            // Added By : Mihir Ramoliya | 02-Apr-2026 (consolidated from 28-Mar-2026 logic)
            // Purpose  : Student has completed programme selection after creating
            //            their account. grpPrograms is required and must be valid.
            //            Full slot write logic runs here.
            } else if (typeOfForm == 'Auris_Admission_Form') {

                System.debug('====== UG Auris_Admission_Form — PROCESSING PROGRAM DATA ======');

                // ── grpPrograms validations ────────────────────────────────────
                // Validation 1: grpPrograms must be present and non-null
                if (!payloadMap.containsKey('grpPrograms') || payloadMap.get('grpPrograms') == null) {
                    throw new CustomException('grpPrograms is required and cannot be null.');
                }

                programGroups = (List<Object>) payloadMap.get('grpPrograms');
                System.debug('grpPrograms count: ' + programGroups.size());

                // Validation 2: grpPrograms list must not be empty
                if (programGroups.isEmpty()) {
                    throw new CustomException('grpPrograms cannot be an empty list. At least one group is required.');
                }

                // Validation 3: every group must have a grptag.
                // Modified By : Mihir Ramoliya | 14-Oct-2026
                // A group is no longer required to carry programmes. A group with null / missing /
                // empty programmes is still added to the lead (tag, application number and date).
                for (Object groupObj : programGroups) {
                    Map<String, Object> gm = (Map<String, Object>) groupObj;
                    String tag = (String) gm.get('grptag');
                    if (String.isBlank(tag)) {
                        throw new CustomException('Each group in grpPrograms must have a non-empty "grptag".');
                    }
                }
                // ── END: grpPrograms validations ──────────────────────────────

                if (!programGroups.isEmpty()) {

                    Integer maxGroups   = getMaxGroups();
                    Integer maxPrograms = getMaxProgrammes();

                    // Re-query existing lead with all slot fields so current
                    // slot state is readable before any writes
                    if (existingLead != null) {
                        newLead = Database.query(leadSoqlForCreation(existingLead.Id, maxGroups));
                    }

                    // ── Max group count validation ─────────────────────────────
                    Integer existingGroupCount = 0;
                    for (Integer s = 1; s <= maxGroups; s++) {
                        if (String.isNotBlank((String) newLead.get('Group_' + s + '__c'))) {
                            existingGroupCount++;
                        }
                    }
                    Integer newGroupCount = 0;
                    for (Object groupObj : programGroups) {
                        Map<String, Object> gm = (Map<String, Object>) groupObj;
                        String tag = (String) gm.get('grptag');
                        if (String.isBlank(tag)) continue;
                        if (findGroupSlotOnLead(newLead, tag, maxGroups) == 0) newGroupCount++;
                    }
                    System.debug('Groups on lead: ' + existingGroupCount
                        + ' | New groups in payload: ' + newGroupCount
                        + ' | Max allowed: ' + maxGroups);
                    if (existingGroupCount + newGroupCount > maxGroups) {
                        Integer available = maxGroups - existingGroupCount;
                        throw new CustomException(
                            'Cannot add ' + newGroupCount + ' new group(s). '
                            + 'This lead already has ' + existingGroupCount + ' of ' + maxGroups + ' allowed groups. '
                            + (available > 0
                                ? 'Only ' + available + ' more group(s) can be added.'
                                : 'No more groups can be added to this lead.')
                        );
                    }
                    // ── END: Max group count validation ───────────────────────

                    // ── Group slot write logic ─────────────────────────────────
                    for (Object groupObj : programGroups) {
                        Map<String, Object> groupMap  = (Map<String, Object>) groupObj;
                        String incomingTag = (String) groupMap.get('grptag');
                        if (String.isBlank(incomingTag)) continue;

                        // Normalise programme key
                        List<Object> programmesList = new List<Object>();
                        if (groupMap.containsKey('programmes') && groupMap.get('programmes') != null) {
                            programmesList = (List<Object>) groupMap.get('programmes');
                        } else if (groupMap.containsKey('programs') && groupMap.get('programs') != null) {
                            programmesList = (List<Object>) groupMap.get('programs');
                        }

                        if (programmesList.size() > maxPrograms) {
                            throw new CustomException('Maximum ' + maxPrograms + ' programs allowed per group.');
                        }

                        // Normalise programme objects
                        List<Object> normalisedProgrammes = new List<Object>();
                        for (Integer pi = 0; pi < programmesList.size(); pi++) {
                            Map<String, Object> prog        = (Map<String, Object>) programmesList[pi];
                            Map<String, Object> updatedProg = new Map<String, Object>(prog);
                            if (!prog.containsKey('preferenceOrder')) {
                                updatedProg.put('preferenceOrder', pi + 1);
                            } else {
                                Integer prefOrder = getPreferenceOrder(prog);
                                if (prefOrder < 1 || prefOrder > maxPrograms) {
                                    throw new CustomException('preferenceOrder must be between 1 and ' + maxPrograms);
                                }
                            }
                            standardizeProgramKeys(updatedProg);
                            normalisedProgrammes.add(updatedProg);
                        }

                        // Resolve applicationNumber
                        String appNumber;
                        if (groupMap.containsKey('applicationNumber') && groupMap.get('applicationNumber') != null
                                && String.isNotBlank((String) groupMap.get('applicationNumber'))) {
                            appNumber = (String) groupMap.get('applicationNumber');
                            System.debug('Preserved applicationNumber from payload: ' + appNumber);
                        } else {
                            Integer slotForNum = findGroupSlotOnLead(newLead, incomingTag, maxGroups);
                            if (slotForNum == 0) slotForNum = nextEmptySlotOnLead(newLead, maxGroups);
                            appNumber = registrationNumber + '-G' + slotForNum;
                            System.debug('Generated applicationNumber: ' + appNumber);
                        }

                        // Parse applicationDate to Date type
                        Date appDate = null;
                        if (groupMap.containsKey('applicationDate') && groupMap.get('applicationDate') != null) {
                            try {
                                appDate = Date.valueOf((String) groupMap.get('applicationDate'));
                            } catch (Exception e) {
                                System.debug('Invalid applicationDate format: ' + groupMap.get('applicationDate'));
                            }
                        }

                        Integer slot = findGroupSlotOnLead(newLead, incomingTag, maxGroups);

                        if (slot == 0) {
                            // NEW GRPTAG — write to next empty slot
                            slot = nextEmptySlotOnLead(newLead, maxGroups);
                            if (slot == 0) {
                                System.debug('Max groups (' + maxGroups + ') reached. Skipping: ' + incomingTag);
                                continue;
                            }
                            newLead.put(groupSlotField(slot, 'tag'),       incomingTag);
                            newLead.put(groupSlotField(slot, 'appNumber'), appNumber);
                            if (appDate != null) {
                                newLead.put(groupSlotField(slot, 'appDate'), appDate);
                            }
                            List<String> progNames = new List<String>();
                            List<String> majors    = new List<String>();
                            for (Object np : normalisedProgrammes) {
                                Map<String, Object> pm = (Map<String, Object>) np;
                                String pn = (String) pm.get('programInterestedIn');
                                if (String.isBlank(pn)) continue;
                                progNames.add(pn.trim());
                                String major = (String) pm.get('major');
                                majors.add(major != null ? major.trim() : '');
                            }
                            newLead.put(groupSlotField(slot, 'programmes'), String.join(progNames, ','));
                            newLead.put(groupSlotField(slot, 'majors'),     String.join(majors,    ','));
                            // Pre-registration (23-Oct-2026): store preRegister / preRegistrationDate when sent
                            LeadConversionService.applyPreRegToLead(newLead, newLead, slot, groupMap, true);
                            System.debug('New group "' + incomingTag + '" written to slot ' + slot);

                        } else {
                            // EXISTING GRPTAG — overwrite slot with incoming payload as source of truth
                            // Modified By : Mihir Ramoliya | 04-Apr-2026
                            // Requirement change: payload always sends the FULL current state of every
                            // group. So if a programme is missing from the incoming list it means the
                            // student removed it. We replace the slot contents entirely instead of merging.
                            //
                            // Rules:
                            //   - Incoming list becomes the new programme/major list for this slot.
                            //   - Programmes absent from payload are removed from the slot.
                            //   - New programmes in payload are added.
                            //   - Changed majors are updated.
                            //   - Max programmes limit still enforced.
                            if (normalisedProgrammes.size() > maxPrograms) {
                                throw new CustomException(
                                    'Group "' + incomingTag + '" cannot have more than '
                                    + maxPrograms + ' programme(s).'
                                );
                            }

                            // Build new lists directly from the incoming payload
                            List<String> newProgNames = new List<String>();
                            List<String> newMajors    = new List<String>();
                            for (Object np : normalisedProgrammes) {
                                Map<String, Object> pm = (Map<String, Object>) np;
                                String pn = (String) pm.get('programInterestedIn');
                                if (String.isBlank(pn)) continue;
                                String incomingMajor = (String) pm.get('major');
                                newProgNames.add(pn.trim());
                                newMajors.add(incomingMajor != null ? incomingMajor.trim() : '');
                            }

                            // Always overwrite — this replaces any removed programmes
                            // and captures additions and major changes in one operation.
                            // Modified By : Mihir Ramoliya | 14-Oct-2026
                            // Exception: when the payload sends NO programmes for this group
                            // (null / missing / empty) the group is still kept on the lead, but
                            // its saved programmes and majors are left untouched instead of wiped.
                            if (!newProgNames.isEmpty()) {
                                newLead.put(groupSlotField(slot, 'programmes'), String.join(newProgNames, ','));
                                newLead.put(groupSlotField(slot, 'majors'),     String.join(newMajors,    ','));
                            }

                            // Update applicationNumber only if payload provides one and slot is blank
                            if (String.isBlank((String) newLead.get(groupSlotField(slot, 'appNumber')))) {
                                newLead.put(groupSlotField(slot, 'appNumber'), appNumber);
                            }
                            // Update applicationDate only if payload provides one and slot is blank
                            if (appDate != null && newLead.get(groupSlotField(slot, 'appDate')) == null) {
                                newLead.put(groupSlotField(slot, 'appDate'), appDate);
                            }
                            // Pre-registration (23-Oct-2026): update the flag / date only when sent in the payload
                            LeadConversionService.applyPreRegToLead(newLead, newLead, slot, groupMap, false);
                            System.debug('Existing group "' + incomingTag + '" overwritten in slot ' + slot
                                + ' with ' + newProgNames.size() + ' programme(s).');
                        }
                    }
                    // ── END: Group slot write logic ───────────────────────────

                    System.debug('====== END PROGRAM DATA PROCESSING ======');
                }
            } else {
                // Unknown typeOfForm for UG — treat as registration (no group processing)
                System.debug('UG unknown typeOfForm "' + typeOfForm + '" — skipping grpPrograms logic.');
            }
            // ── END: Undergraduation typeOfForm split ─────────────────────────

        // =====================================================================
        // NON-UNDERGRADUATION DEPARTMENTS (Masters, Executive Education, etc.)
        // =====================================================================
        } else {
            existingLead = handleDuplicateLeadMasters(payloadMap, department, typeOfForm);

            newLead = (existingLead != null) ? existingLead : new Lead(RecordTypeId = recordTypeId);
        }

        // Apply field mappings
        List<Auris_Form_Mapping__mdt> mappings = [
            SELECT Label, Datatype__c, JSON_Key__c, Department__c, TypeOfForm__c 
            FROM Auris_Form_Mapping__mdt
            WHERE (Department__c = :department OR Department__c = null)
            AND   (TypeOfForm__c = :typeOfForm OR TypeOfForm__c = null)
        ];
    
        for (Auris_Form_Mapping__mdt mapRec : mappings) {
            if (String.isBlank(mapRec.JSON_Key__c) || String.isBlank(mapRec.Label)){
                continue;
            } 
    
            Object jsonValue = payloadMap.get(mapRec.JSON_Key__c);
            if (jsonValue == null){
                continue;
            } 
    
            Object fieldValue;
            try {
                switch on mapRec.Datatype__c {
                    when 'String'  { fieldValue = String.valueOf(jsonValue); }
                    when 'Date'    { fieldValue = Date.valueOf(String.valueOf(jsonValue)); }
                    when 'DateTime'{ fieldValue = Datetime.valueOf(String.valueOf(jsonValue)); }
                    when 'Decimal' { fieldValue = Decimal.valueOf(String.valueOf(jsonValue)); }
                    when 'Boolean' { fieldValue = Boolean.valueOf(String.valueOf(jsonValue)); }
                    when  else     { fieldValue = String.valueOf(jsonValue); }
                }
                // Added By : Mihir Ramoliya
                // Added on : 01st September 2026
                // "AURIS" is a retired legacy value. It still exists in the LeadSource AND
                // Multi_Select_Lead_Source__c picklists' own value sets (Salesforce does not
                // support fully deleting a STANDARD field's picklist value via the API - only
                // deactivating, which was tested and does NOT stop this), so the platform
                // silently coerces ANY case-insensitive match ("Auris", "auris", "AuRiS"...)
                // to "AURIS" at save time on either field, invisible to this code - confirmed
                // by direct testing, not fixable by changing the value's case in Apex. We
                // never want AURIS to appear as a lead source again, so treat the incoming
                // 'leadSource' payload key as not sent at all when it matches that legacy value.
                if (mapRec.JSON_Key__c == 'leadSource' && String.valueOf(fieldValue).equalsIgnoreCase('AURIS')) {
                    System.debug('Skipping legacy AURIS lead source value from payload for field ' + mapRec.Label + ' - leaving it untouched.');
                    continue;
                }
                // Added By : Mihir Ramoliya
                // Added on : 26th March 2026
                // Do not overwrite LeadSource if it is already populated on the lead - but
                // still record this touch's source on Most_Recent_Lead_Source__c (never
                // locked, unlike LeadSource) so the Lead trigger can pick up a genuine
                // re-touch for Campaign History even when LeadSource itself stays put.
                // Added By : Mihir Ramoliya
                // Added on : 12th October 2026
                // Do not push an existing Lead back to "New Lead" when the same student is
                // submitted again. Once the sales team has moved the Lead past New Lead, an
                // incoming 'leadStatus' of New Lead is ignored. Any other incoming status
                // still applies, and a Lead that is still New Lead can be updated normally.
                // Modified By : Jitendra Varma | 29th October 2026
                // An incoming legacy 'New' is saved as 'New Lead', and an existing Lead still on
                // 'New' is treated like 'New Lead' so it can be moved to 'New Lead'.
                if (mapRec.Label == 'Status') {
                    if (String.valueOf(fieldValue).equalsIgnoreCase(StaticValuesUtil.LEAD_STATUS_NEW)) {
                        fieldValue = StaticValuesUtil.LEAD_STATUS_NEW_LEAD;
                    }
                    String currentStatus = (String) newLead.get('Status');
                    if (newLead.Id != null
                        && String.isNotBlank(currentStatus)
                        && !currentStatus.equalsIgnoreCase(StaticValuesUtil.LEAD_STATUS_NEW_LEAD)
                        && !currentStatus.equalsIgnoreCase(StaticValuesUtil.LEAD_STATUS_NEW)
                        && String.valueOf(fieldValue).equalsIgnoreCase(StaticValuesUtil.LEAD_STATUS_NEW_LEAD)) {
                        System.debug('Skipping Status reset to New Lead - existing Lead is already at ' + currentStatus);
                        continue;
                    }
                }
                String currentLeadSource = LeadTriggerHandler.safeGet(newLead, Lead.LeadSource);
                System.debug('newLead.LeadSource: '+currentLeadSource);
                System.debug('mapRec.Label: '+mapRec.Label);
                if(!String.isBlank(currentLeadSource) && mapRec.Label == 'LeadSource'){
                    newLead.Most_Recent_Lead_Source__c = String.valueOf(fieldValue);
                    fieldValue = currentLeadSource;
                }
                newLead.put(mapRec.Label, fieldValue);
                System.debug('Field ' + mapRec.Label + ' mapped to ' + fieldValue + 'JSON KEY: '+mapRec.JSON_Key__c);
            } catch (Exception e) {
                System.debug('Failed to map ' + mapRec.JSON_Key__c + ' to ' + mapRec.Label + ': ' + e.getMessage());
            }
        }
    
        // Handle special business logic
        if (String.isBlank(newLead.LastName)) {
            newLead.LastName = '.';
        }
        
        // Modified By : Jitendra Varma | 29-Oct-2026
        // A UG Admission Form updating the Lead given by leadId may leave out admissionYear
        // (like email / phone / mobile) - the Lead keeps its own value instead of being
        // reset to the default Admission Year.
        if(admissionLead == null && (!payloadMap.containsKey('admissionYear') || payloadMap.get('admissionYear') == null)){
            newLead.Admission_Year__c = System.label.Admission_Year;
        }
        
        // Handle Phone
        // Modified By : Jitendra Varma | 29-Oct-2026
        // Auris sends the phone with '+' and the country code (e.g. '+919876543210').
        // Such a number is saved as sent (spaces/dashes removed) - adding the country
        // code again saved it as '91919876543210'. A number without '+' still gets the
        // country code added as before.
        String payloadPhone = (String) payloadMap.get('phone');
        String payloadPhoneDigits = (payloadPhone == null) ? '' : payloadPhone.replaceAll('\\D', '');
        if (payloadPhone != null
                && payloadPhone.trim().startsWith(INTERNATIONAL_PHONE_PREFIX)
                && String.isNotBlank(payloadPhoneDigits)) {
            newLead.Phone = INTERNATIONAL_PHONE_PREFIX + payloadPhoneDigits;
        } else if (payloadMap.containsKey('phone') && payloadMap.get('phone') != null) {
            String country = (String) payloadMap.get('country');
            if (String.isBlank(country)){
                country = 'IN';
            } 
            newLead.Phone = LeadPhoneUpdater.generatePhoneNumberWithCountryCode(country, (String) payloadMap.get('phone'));
        }
        
        // Update timestamp
        newLead.Auris_Last_Updated_Timestamp__c = System.now().format('yyyy-MM-dd:HH:mm:ss');
        System.debug('newLead: '+newLead);
        System.debug('existingLead: '+existingLead);
        // Read via safeGet, not newLead.<field> directly - some duplicate-lookup queries in
        // this class predate these fields and don't select them, which makes a direct read
        // throw "field not queried" and abort the whole save (seen in practice).
        System.debug('newLead.Most_Recent_Lead_Source__c: '+LeadTriggerHandler.safeGet(newLead, Lead.Most_Recent_Lead_Source__c));
        System.debug('newLead.Multi_Select_Lead_Sources__c: '+LeadTriggerHandler.safeGet(newLead, Lead.Multi_Select_Lead_Sources__c));
        // Added By : Mihir Ramoliya
        // Purpose  : A lead arriving from Auris with a Registration Number or a
        //            Registration Date is an Auris-registered lead, so AURIS is added
        //            to the Multi_Select_Lead_Source__c (multiselect only - the
        //            LeadSource field itself still never receives AURIS, see above).
        //            Existing values are kept; LeadMultiLeadSourceTrigger merges the
        //            rest. safeGet is used because some duplicate-lookup queries
        //            don't select these fields.
        Boolean hasRegistrationNumber = String.isNotBlank(registrationNumber)
            || String.isNotBlank(LeadTriggerHandler.safeGet(newLead, Lead.Registration_Number__c));
        Boolean hasRegistrationDate = newLead.isSet(Lead.Registration_Date__c)
            && newLead.get(Lead.Registration_Date__c) != null;
        if (hasRegistrationNumber || hasRegistrationDate) {
            String currentMulti = LeadTriggerHandler.safeGet(newLead, Lead.Multi_Select_Lead_Source__c);
            Set<String> multiValues = new Set<String>();
            if (String.isNotBlank(currentMulti)) {
                for (String v : currentMulti.split(';')) {
                    if (String.isNotBlank(v.trim())) {
                        multiValues.add(v.trim());
                    }
                }
            }
            if (multiValues.add('AURIS')) {
                newLead.Multi_Select_Lead_Source__c = String.join(new List<String>(multiValues), ';');
            }
        }

        // Save record using Registration Number as external ID
        if (Schema.sObjectType.Lead.isCreateable() && Schema.sObjectType.Lead.isUpdateable()) {
            // System.debug('Before upsert - Group_Tag__c: ' + newLead.Group_Tag__c);
            System.debug('Before upsert - RecordTypeId: ' + newLead.RecordTypeId);
            // System.debug('Before upsert - Department: ' + newLead.Department__c);
            // System.debug('Before upsert - Preferred_Programme__c: ' + newLead.Preferred_Programme__c);

            
            upsert newLead;
            
            System.debug('After upsert - Lead ID: ' + newLead.Id);
            // System.debug('After upsert - Group_Tag__c: ' + newLead.Group_Tag__c);
        } else {
            throw new CustomException('Insufficient permissions to create or update lead');
        }
        
        // ================================================
        // CRITICAL: Call insertPreferredPrograms if we have program data
        // ================================================
        // Pre-registration (23-Oct-2026): when the student's lead is already converted, mirror the
        // group slots to the converted Account too (Account is used for pre-registration reports).
        if (!programGroups.isEmpty() && newLead.Id != null && existingLead != null
                && newLead.get('IsConverted') == true && newLead.get('ConvertedAccountId') != null) {
            LeadConversionService.syncGroupsToAccount(newLead, (Id) newLead.get('ConvertedAccountId'),
                LeadConversionService.leadHasPreRegisteredGroup(newLead));
        }
        if (!programGroups.isEmpty() && newLead.Id != null) {
            System.debug('Calling insertPreferredPrograms with JSONKey: programs');
            insertPreferredPrograms('programs', programGroups, newLead.Id, registrationNumber);
        }
        
        handleAdmissionForm(payloadMap, newLead.Id, department, typeOfForm, registrationNumber);
        return newLead.Id;
    }    

    // =============================================================================
    // SECTION: CREATION-SIDE SLOT HELPERS
    // Added By : Mihir Ramoliya
    // Date     : 28-Mar-2026
    // Purpose  : Private helper methods used only within processSingleRecord.
    //            These are intentionally separate from the conversion-class helpers
    //            (groupFieldName, findGroupSlot, etc.) to keep the two classes
    //            independent. Both sets resolve the same field names.
    // =============================================================================

    /**
     * Returns the Salesforce API field name for a Lead group slot field.
     * Centralised so all slot reads/writes in this class use consistent names.
     *
     * @param slot      Slot number (1–4)
     * @param fieldType One of: 'tag' | 'appNumber' | 'appDate' | 'programmes' | 'majors'
     * @return          API field name e.g. 'Group_2_Application_Number__c'
     */
    private static String groupSlotField(Integer slot, String fieldType) {
        if (fieldType == 'tag')        return 'Group_' + slot + '__c';
        if (fieldType == 'appNumber')  return 'Group_' + slot + '_Application_Number__c';
        if (fieldType == 'appDate')    return 'Group_' + slot + '_Application_Date__c';
        if (fieldType == 'programmes') return 'Group_' + slot + '_Programmes__c';
        if (fieldType == 'majors')     return 'Group_' + slot + '_Majors__c';
        return 'Group_' + slot + '__c';
    }

    /**
     * Returns the maximum number of group slots allowed per lead.
     * Reads Max_Groups__c from UG_Validation_Settings__c. Default: 4.
     * Admins can change the limit without a code deployment.
     */
    private static Integer getMaxGroups() {
        UG_Validation_Settings__c s = UG_Validation_Settings__c.getOrgDefaults();
        return (s != null && s.Max_Groups__c != null) ? (Integer) s.Max_Groups__c : 4;
    }

    /**
     * Returns the maximum number of programmes allowed per group.
     * Reads Max_Programmes__c from UG_Validation_Settings__c. Default: 3.
     */
    private static Integer getMaxProgrammes() {
        UG_Validation_Settings__c s = UG_Validation_Settings__c.getOrgDefaults();
        return (s != null && s.Max_Programmes__c != null) ? (Integer) s.Max_Programmes__c : 3;
    }

    /**
     * Builds a dynamic SOQL string that selects all group slot fields for a Lead.
     * Used to re-query an existing lead (when a duplicate is found) so its current
     * slot state is visible for read/write operations without a separate query.
     *
     * @param leadId    Salesforce Lead record Id
     * @param maxGroups Maximum number of group slots (from custom setting)
     * @return          Full SOQL query string
     */
    private static String leadSoqlForCreation(Id leadId, Integer maxGroups) {
        String q = 'SELECT Id, RecordTypeId, Multi_Select_Lead_Source__c, Most_Recent_Lead_Source__c, LastName, Status';
        for (Integer s = 1; s <= maxGroups; s++) {
            q += ', Group_'  + s + '__c';
            q += ', Group_'  + s + '_Application_Number__c';
            q += ', Group_'  + s + '_Application_Date__c';
            q += ', Group_'  + s + '_Programmes__c';
            q += ', Group_'  + s + '_Majors__c';
            q += ', Group_'  + s + '_Pre_Register__c';
            q += ', Group_'  + s + '_Pre_Registration_Date__c';
        }
        q += ' , LeadSource, IsConverted, ConvertedAccountId';
        q += ' FROM Lead WHERE Id = \'' + leadId + '\' LIMIT 1';
        return q;
    }

    /**
     * Returns the slot number (1–maxGroups) that currently holds the given grptag.
     * Returns 0 if the grptag is not found in any slot.
     *
     * @param lead      Lead record (must include Group_N__c fields)
     * @param grptag    The group tag string to search for
     * @param maxGroups Maximum number of slots to check
     * @return          Slot number 1–4, or 0 if not found
     */
    private static Integer findGroupSlotOnLead(Lead lead, String grptag, Integer maxGroups) {
        for (Integer slot = 1; slot <= maxGroups; slot++) {
            if (grptag == (String) lead.get('Group_' + slot + '__c')) return slot;
        }
        return 0;
    }

    /**
     * Returns the first slot number (1–maxGroups) where Group_N__c is blank.
     * Returns 0 if all slots are occupied (max groups limit reached).
     *
     * @param lead      Lead record (must include Group_N__c fields)
     * @param maxGroups Maximum number of slots to check
     * @return          First empty slot number 1–4, or 0 if all are full
     */
    private static Integer nextEmptySlotOnLead(Lead lead, Integer maxGroups) {
        for (Integer slot = 1; slot <= maxGroups; slot++) {
            if (String.isBlank((String) lead.get('Group_' + slot + '__c'))) return slot;
        }
        return 0;
    }
    // END: CREATION-SIDE SLOT HELPERS

    //Helper method to extract preferenceOrder from a program map
    private static Integer getPreferenceOrder(Map<String, Object> programme) {
        if (programme.containsKey('preferenceOrder')) {
            Object order = programme.get('preferenceOrder');
            if (order instanceof Integer) return (Integer) order;
            if (order instanceof String) {
                try {
                    return Integer.valueOf((String) order);
                } catch (Exception e) {
                    return null;
                }
            }
        }
        return null;
    }
    

    //Helper method to standardize program keys (handle different cases)
    private static void standardizeProgramKeys(Map<String, Object> programme) {
        // Check for different case variations of programInterestedIn
        if (programme.containsKey('programinterestedin')) {
            programme.put('programInterestedIn', programme.get('programinterestedin'));
            programme.remove('programinterestedin');
        } else if (programme.containsKey('ProgramInterestedIn')) {
            programme.put('programInterestedIn', programme.get('ProgramInterestedIn'));
            programme.remove('ProgramInterestedIn');
        }
    }
    
    //Helper method to validate and sort programmes by preferenceOrder
    private static List<Map<String, Object>> sortProgrammesByPreference(List<Object> programmes) {
        List<Map<String, Object>> programmeMaps = new List<Map<String, Object>>();
        
        for (Object obj : programmes) {
            programmeMaps.add((Map<String, Object>) obj);
        }
        
        // Sort by preferenceOrder if available
        programmeMaps.sort(new ProgrammeComparator());
        
        return programmeMaps;
    }
    
    //Comparator class for sorting programmes by preferenceOrder
    public class ProgrammeComparator implements System.Comparator<Map<String, Object>> {
        public Integer compare(Map<String, Object> p1, Map<String, Object> p2) {
            Integer order1 = getPreferenceOrder(p1);
            Integer order2 = getPreferenceOrder(p2);
            
            if (order1 == null && order2 == null) return 0;
            if (order1 == null) return 1; // null goes last
            if (order2 == null) return -1;
            
            return order1 - order2;
        }
    }        

    /** 
    * @description - Checking duplicate lead based on combination of Email+ Phone+ Preferred Program 
                     and if the matching lead is found updates the record with payload data and lead source gets added into
                     multiple lead source for masters record type
    * @param payloadMap http response 
    * @param department of lead
    * @param typeOfForm of lead
    * @return lead 
    */
    public static Lead handleDuplicateLeadMasters(Map<String, Object> payloadMap,String department,String typeOfForm){
        String matchingphone = buildPhoneMatchPattern((String) payloadMap.get('phone'));
        System.debug('[Processed] Phone for SOQL: ' + matchingphone);
    
        String matchingEmail = (String) payloadMap.get('email');
    
        String matchingPreferedProgrm = (String) payloadMap.get('programmeInterestedIn');

        // Only treat an existing Lead as a duplicate if its Admission_Year__c matches
        // the incoming lead's admission year - a re-application for a different
        // admission year is a new lead, not a duplicate of the old one.
        String matchingAdmissionYear = (payloadMap.containsKey('admissionYear') && payloadMap.get('admissionYear') != null)
            ? String.valueOf(payloadMap.get('admissionYear'))
            : System.label.Admission_Year;

        List<Lead> matchingLead = [
            SELECT Id, Phone, Registration_Number__c, Email,
                   Multi_Select_Lead_Source__c, Preferred_Programme__c,
                   RecordTypeId, LastName, FirstName, LeadSource, Most_Recent_Lead_Source__c, Status
            FROM Lead
            WHERE Phone LIKE :matchingphone
            AND Email = :matchingEmail
            AND Preferred_Programme__c = :matchingPreferedProgrm AND department__c = :department
            AND Admission_Year__c = :matchingAdmissionYear
            LIMIT 1
        ];
        System.debug('[SOQL Result] Matching Leads Found: ' + matchingLead);
    
        Lead newLead = null;
        if(!matchingLead.isEmpty()){
            newLead = matchingLead[0];
            
            // DEFENSIVE CHECK: Ensure RecordTypeId is available
            if (newLead.RecordTypeId == null) {
                newLead = [SELECT Id, RecordTypeId, LeadSource, Most_Recent_Lead_Source__c FROM Lead WHERE Id = :newLead.Id];
            }
            
            //code to add leadsource in multipicklist field
            // Set<String> picklistValues = new Set<String>();
            // if (String.isNotBlank(newLead.Multi_Select_Lead_Source__c)) {
            //     picklistValues.addAll(newLead.Multi_Select_Lead_Source__c.split(';'));
            // }
            // String websiteLeadSource = 'AURIS';
            // picklistValues.add(websiteLeadSource);
            // newLead.Multi_Select_Lead_Source__c = String.join(new List<String>(picklistValues), ';');
    
            return newLead;
        }
        return newLead;
    }
    

    /** 
    * @description - Checking duplicate lead based on combination of Email+ Phone and if the matching
                     lead is found updates the record with payload data and lead source gets added into
                     multiple lead source for Undergraduation record type
    * @param payloadMap http response 
    * @param department of lead
    * @param typeOfForm of lead
    * @return lead 
    */

    
    // =============================================================================
    // METHOD: handleDuplicateLeadUndergraduation
    // Created By  : Preksha Chauhan  (original version — prior date)
    // Modified By : Mihir Ramoliya  — 28-Mar-2026
    //
    // Modification Details (28-Mar-2026):
    //   - Extended the SELECT query to include all Group slot fields
    //     (Group_1__c … Group_4__c plus Application_Number, Application_Date,
    //      Majors, Programmes for each slot).
    //   - This means the lead returned by this method already has all slot
    //     field values populated, so processSingleRecord can read/write them
    //     directly without issuing a second query.
    //   - Also added Department__c, LeadSource to the query for completeness.
    //
    // Purpose  : Checks for an existing Lead in Salesforce that matches the
    //            incoming payload by Email AND Phone (partial match) for the
    //            given department. If a match is found:
    //            - Adds 'AURIS' to Multi_Select_Lead_Source__c (deduped).
    //            - Returns the matching lead (in-memory, not yet saved).
    //            If no match is found, returns null so processSingleRecord
    //            creates a new Lead.
    //
    // @param payloadMap  Payload map from the REST API request
    // @param department  Department string e.g. 'Undergraduation'
    // @param typeOfForm  Form type string e.g. 'Auris_Admission_Form'
    // @return            Matching Lead sObject (with slot fields) or null
    // =============================================================================
    public static Lead handleDuplicateLeadUndergraduation(
            Map<String, Object> payloadMap,
            String department,
            String typeOfForm
    ) {
        // Modified By : Jitendra Varma | 29-Oct-2026
        // Registration Number is the same on the Registration and Admission forms
        // and unique per student, so it is checked first. Email + Phone is the
        // fallback. An empty set makes the IN filter match nothing, so a blank
        // Registration Number never matches leads that have none.
        String registrationNumber = (String) payloadMap.get('registrationNumber');
        Set<String> matchingRegistrationNumbers = new Set<String>();
        if (String.isNotBlank(registrationNumber)) {
            matchingRegistrationNumbers.add(registrationNumber.trim());
        }
        String matchingPhone = buildPhoneMatchPattern((String) payloadMap.get('phone'));
        String matchingEmail = (String) payloadMap.get('email');

        // ── START: Modified By Mihir Ramoliya | 28-Mar-2026 ───────────────────────
        // Change: Added all Group slot fields (Group_1__c … Group_4__c + related
        //         fields) to the SELECT so the returned lead can be used immediately
        //         for slot read/write in processSingleRecord without a second query.
        //         Also added Department__c and LeadSource for completeness.
        List<Lead> matchingLead = [
            SELECT Id, Phone, Registration_Number__c, Email,
                Multi_Select_Lead_Source__c, RecordTypeId,
                LastName, FirstName, Department__c, LeadSource,
                Most_Recent_Lead_Source__c, Status,
                // Group slot 1
                Group_1__c, Group_1_Application_Date__c,
                Group_1_Application_Number__c, Group_1_Majors__c, Group_1_Programmes__c,
                // Group slot 2
                Group_2__c, Group_2_Application_Date__c,
                Group_2_Application_Number__c, Group_2_Majors__c, Group_2_Programmes__c,
                // Group slot 3
                Group_3__c, Group_3_Application_Date__c,
                Group_3_Application_Number__c, Group_3_Majors__c, Group_3_Programmes__c,
                // Group slot 4
                Group_4__c, Group_4_Application_Date__c,
                Group_4_Application_Number__c, Group_4_Majors__c, Group_4_Programmes__c
            FROM   Lead
            WHERE  Department__c = :department
            AND    (Registration_Number__c IN :matchingRegistrationNumbers
                    OR (Phone LIKE :matchingPhone AND Email = :matchingEmail))
            ORDER BY CreatedDate ASC
            LIMIT  :DUPLICATE_CANDIDATE_LIMIT
        ];
        // ── END: Modified By Mihir Ramoliya | 28-Mar-2026 ─────────────────────────

        Lead newLead = null;

        if (!matchingLead.isEmpty()) {
            // Prefer the oldest lead with the same Registration Number; otherwise
            // the oldest Email + Phone match.
            newLead = matchingLead[0];
            for (Lead candidate : matchingLead) {
                if (matchingRegistrationNumbers.contains(candidate.Registration_Number__c)) {
                    newLead = candidate;
                    break;
                }
            }

            // Defensive check — if RecordTypeId is not populated on the matched record,
            // re-query to get it (can happen if the lead has no record type set). Must
            // include every field read below (Multi_Select_Lead_Source__c, LeadSource) or
            // those reads throw "field not queried", silently swallowed by the caller's
            // try/catch — this exact gap previously made the LeadSource preservation
            // and Most_Recent_Lead_Source__c updates silently no-op.
            if (newLead.RecordTypeId == null) {
                newLead = [SELECT Id, RecordTypeId, Multi_Select_Lead_Source__c, LeadSource, Most_Recent_Lead_Source__c FROM Lead WHERE Id = :newLead.Id];
            }

            // Removed By : Mihir Ramoliya | 02nd September 2026
            // Removed    : unconditional "add 'AURIS' to Multi_Select_Lead_Source__c" step.
            // This ran on every duplicate match regardless of the payload's actual leadSource,
            // re-introducing the retired AURIS value we specifically guard against elsewhere
            // in this class. Multi_Select_Lead_Source__c is now correctly maintained from the
            // real payload value by the generic field-mapping loop (with the AURIS guard) and
            // LeadMultiLeadSourceTrigger's own accumulation logic - nothing further needed here.

            return newLead;
        }

        // No matching lead found — return null so processSingleRecord creates a new one
        return newLead;
    }
    // END: handleDuplicateLeadUndergraduation

    // Max leads returned by the UG duplicate lookup before picking the best match.
    private static final Integer DUPLICATE_CANDIDATE_LIMIT = 50;
    // Number of trailing phone digits compared when matching duplicates.
    private static final Integer PHONE_MATCH_DIGITS = 10;
    // A phone starting with this already carries its country code.
    private static final String INTERNATIONAL_PHONE_PREFIX = '+';
    // Form type that must carry the leadId of the Lead to update (UG only).
    private static final String AURIS_ADMISSION_FORM = 'Auris_Admission_Form';
    // Only this department's Admission Form requires leadId.
    private static final String UG_DEPARTMENT = 'Undergraduation';
    // Payload key holding the Salesforce Lead Id on the Admission Form.
    private static final String LEAD_ID_KEY = 'leadId';

    // Added By : Jitendra Varma | 29-Oct-2026
    // Returns the Lead a UG Admission Form payload must update, taken from its 'leadId'.
    // email / phone / mobile / admissionYear are optional on such a payload - when sent
    // they are written as usual, when left out the Lead keeps its existing values.
    // Throws CustomException (returned to Auris as the error message, nothing saved) when
    // leadId is missing / blank / not a valid Lead Id / not found, or when the Lead belongs
    // to a different Registration Number or department. A blank Registration Number or
    // department on the Lead is not a mismatch - the payload value is written to it.
    // Queries every Lead field the rest of processSingleRecord reads.
    // @param payloadMap          Payload map from the REST API request
    // @param department          Payload department
    // @param registrationNumber  Payload registrationNumber (already validated as not blank)
    // @return                    The Lead to update
    @TestVisible
    private static Lead resolveAdmissionLead(Map<String, Object> payloadMap, String department, String registrationNumber) {
        Object rawLeadId = payloadMap.get(LEAD_ID_KEY);
        String leadIdValue = (rawLeadId == null) ? null : String.valueOf(rawLeadId).trim();
        if (String.isBlank(leadIdValue)) {
            throw new CustomException('Missing required field: leadId. ' + AURIS_ADMISSION_FORM
                + ' must include the leadId of the Lead to update.');
        }

        Id leadId;
        try {
            leadId = Id.valueOf(leadIdValue);
        } catch (StringException e) {
            throw new CustomException('Invalid leadId "' + leadIdValue + '": not a valid Salesforce Id.');
        }
        if (leadId.getSObjectType() != Lead.SObjectType) {
            throw new CustomException('Invalid leadId "' + leadIdValue + '": not a Lead Id.');
        }

        List<Lead> leads = [
            SELECT Id, RecordTypeId, Registration_Number__c, Department__c, Email, Phone,
                   FirstName, LastName, Status, LeadSource, Most_Recent_Lead_Source__c,
                   Multi_Select_Lead_Source__c, Preferred_Programme__c,
                   IsConverted, ConvertedAccountId
            FROM   Lead
            WHERE  Id = :leadId
            LIMIT  1
        ];
        if (leads.isEmpty()) {
            throw new CustomException('Invalid leadId "' + leadIdValue + '": no Lead found with this Id.');
        }
        Lead lead = leads[0];

        if (String.isNotBlank(lead.Registration_Number__c)
                && !lead.Registration_Number__c.trim().equalsIgnoreCase(registrationNumber.trim())) {
            throw new CustomException('leadId "' + leadIdValue + '" belongs to Registration Number "'
                + lead.Registration_Number__c + '", but the payload has "' + registrationNumber + '".');
        }
        if (String.isNotBlank(lead.Department__c) && !lead.Department__c.equalsIgnoreCase(department)) {
            throw new CustomException('leadId "' + leadIdValue + '" belongs to department "'
                + lead.Department__c + '", but the payload has "' + department + '".');
        }
        return lead;
    }

    // Added By : Jitendra Varma | 29-Oct-2026
    // Phone is saved with all non-digits removed and a country code added in front
    // (e.g. '+447887139054' is saved as '91447887139054'), so the raw payload value
    // never matches when it has '+', spaces or dashes. Matching on the last 10
    // digits works whichever country code was added.
    // @param phone  Phone value from the payload
    // @return       LIKE pattern on the last 10 digits, or null when there are no digits
    @TestVisible
    private static String buildPhoneMatchPattern(String phone) {
        if (phone == null) {
            return null;
        }
        String digits = phone.replaceAll('\\D', '');
        if (String.isBlank(digits)) {
            return null;
        }
        if (digits.length() > PHONE_MATCH_DIGITS) {
            digits = digits.right(PHONE_MATCH_DIGITS);
        }
        return '%' + digits + '%';
    }

    /**
    * @description
    * @param department of lead
    * @return record type id
    * Method Name : fetchRecordTypeId
    * Create By : Preksha Chauhan
    * Create Date : 07/07/2024
    * Description : This method retrieves the RecordTypeId for a given department using custom metadata. 
    *               It queries the Department_Record_Type_Mapping__mdt custom metadata type to get the 
    *               RecordTypeId based on the department. If any error occurs during the query, it logs 
    *               the error and throws a CustomException.
    *******************************************************************************************/
    public static String fetchRecordTypeId(String department) {
        try {
            //System.debug('Fetching Record Type ID for department: ' + department);
            Department_Record_Type_Mapping__mdt mapping = [SELECT Record_Type_Id__c 
                                                           FROM Department_Record_Type_Mapping__mdt  
                                                           WHERE Department__c = :department 
                                                           LIMIT 1];
            return (mapping != null) ? mapping.Record_Type_Id__c : null;
        } catch (Exception e) {
            //System.debug('Error in fetchRecordTypeId: ' + e.getMessage());
            throw new CustomException('Error in fetchRecordTypeId: ' + e.getMessage());
        }
    }
    /** 
    * @description - insert parent information for masters and UG, Uniquly identifies parent
                     record based on Parent Name + RelationShip combination and upserts it
    * @param parents - A list of maps containing the parent information data. Each map
    *                  represents a parent and includes details such as name, relationship,
    *                  phone number, email, and additional attributes.
    * @param leadId - The Id of the Lead to which the parent information records are related.
    * @param registrationNumber lead registrationNumber
    */
    public static void insertParentInformation(String JSONKey,Object parents, Id leadId, String registrationNumber) {
        try {
            // Query existing Parent_Information__c records related to the lead
            Map<String, Parent_Information__c> existingParentMap = new Map<String, Parent_Information__c>();
            for (Parent_Information__c existingParent : [
                SELECT Id, Name, Relationship__c 
                FROM Parent_Information__c 
                WHERE Lead__c = :leadId
            ]) {
                String uniqueKey = existingParent.Name + '-' + existingParent.Relationship__c;
                existingParentMap.put(uniqueKey, existingParent);
            }
    
            List<Parent_Information__c> parentList = new List<Parent_Information__c>();
    
            for (Object parent : (List<Object>) parents) {
                Map<String, Object> parentMap = (Map<String, Object>) parent;
                Parent_Information__c parentRec = new Parent_Information__c();
                parentRec.Lead__c = leadId;
                handleRelatedInformationFieldMappings(JSONKey,parentMap, parentRec);
                // Create a unique key using only Name and Relationship__c
                String uniqueKey = parentRec.Name + '-' + parentRec.Relationship__c;
                
    
                // Check if a record with the same key already exists
                if (!existingParentMap.containsKey(uniqueKey)) {
                    
                    parentList.add(parentRec);
                }
            }
    
            if (!parentList.isEmpty()) {
                insert parentList;
            }
        } catch (Exception e) {
            //System.debug('Error in Parent Information method: ' + e.getMessage());
            logFailedLead(JSON.serialize(parents), e, registrationNumber); // Log the failed attempt
            throw new CustomException('Error in insertParentInformation method: ' + e.getMessage());
        }
    }  

    /** 
    * @description
    ****************************************************************************************
    * Method Name : insertPreferredPrograms
    * Created By : Preksha Chauhan
    * Created Date : 07/10/2024
    * Description : This method handles the insertion of preferred programs for a given Lead
    *               in Salesforce. It updates the Lead's `Auris_Last_Updated_Timestamp__c` field
    *               with the current datetime in the format 'yyyy-MM-dd:HH:mm:ss'. It then
    *               processes the provided list of preferred programs to determine if they need
    *               to be inserted. The method performs the following tasks:
    *               - Updates the `Auris_Last_Updated_Timestamp__c` field on the Lead object
    *               - Queries existing Preferred_Program__c records to avoid duplicates
    *               - Inserts new Preferred_Program__c records if they do not already exist
    *               - Handles errors by logging the failure and throwing a CustomException
    *
    * Parameters:
    * @param programs - A list of maps where each map contains details of a preferred program
    *                  including program code and major name. This information is used to
    *                  look up and insert records into the Preferred_Program__c object.
    * @param leadId - The Id of the Lead to which the preferred programs are related.
    * @param registrationNumber lead registrationNumber
    ********************************************************************************************

    /** 
    * Modify by: Rishav Raj 
    * @description - insert preferred programs with group support************************************
    */
    // public static void insertPreferredPrograms(String JSONKey, Object programs, Id leadId, String registrationNumber) {
    //     try {
    //         // Get the current datetime
    //         Datetime now = System.now();
    //         String formattedDate = now.format('yyyy-MM-dd:HH:mm:ss');
            
    //         // Update Lead's timestamp
    //         Lead leadToUpdate = new Lead(Id = leadId);
    //         leadToUpdate.Auris_Last_Updated_Timestamp__c = formattedDate;
    //         update leadToUpdate;
            
    //         // Query lead to get program groups
    //         Lead lead = [SELECT Id, Group_Tag__c, RecordTypeId FROM Lead WHERE Id = :leadId LIMIT 1];
            
    //         if (String.isNotBlank(lead.Group_Tag__c)) {
    //             List<Object> programGroups = (List<Object>) JSON.deserializeUntyped(lead.Group_Tag__c);
                
    //             // Query existing Preferred_Program__c records
    //             Map<String, Preferred_Program__c> existingProgramMap = new Map<String, Preferred_Program__c>();
    //             for (Preferred_Program__c existingProgram : [
    //                 SELECT Id, Program__c, Major__c, Program_Group_Tag__c, Application_Number__c
    //                 FROM Preferred_Program__c 
    //                 WHERE Lead__c = :leadId 
    //             ]) {
    //                 String uniqueKey = existingProgram.Program_Group_Tag__c + '-' + 
    //                                   existingProgram.Application_Number__c + '-' +
    //                                   existingProgram.Program__c;
    //                 existingProgramMap.put(uniqueKey, existingProgram);
    //             }
    
    //             List<Preferred_Program__c> programList = new List<Preferred_Program__c>();
                
    //             for (Object groupObj : programGroups) {
    //                 Map<String, Object> groupMap = (Map<String, Object>) groupObj;
    //                 String groupTag = (String) groupMap.get('uggrouptag');
    //                 String groupAppNumber = (String) groupMap.get('applicationNumber');
                    
    //                 if (String.isBlank(groupAppNumber) && String.isNotBlank(registrationNumber)) {
    //                     groupAppNumber = registrationNumber + '-G1'; // Default if not set
    //                 }
                    
    //                 if (groupMap.containsKey('programs') && groupMap.get('programs') != null) {
    //                     List<Object> programListObj = (List<Object>) groupMap.get('programs');
                        
    //                     for (Object program : programListObj) {
    //                         Map<String, Object> programMap;
                            
    //                         if (program instanceof String) {
    //                             programMap = (Map<String, Object>) JSON.deserializeUntyped((String) program);
    //                         } else {
    //                             programMap = (Map<String, Object>) program;
    //                         }
                            
    //                         String programCode = null;
    //                         String majorName = null;
    //                         Program__c programObjRecord = null;
    //                         Major__c majorObj = null;
                            
    //                         // Query for Program__c
    //                         if (programMap.containsKey('programInterestedIn') && programMap.get('programInterestedIn') != null) {
    //                             programCode = (String) programMap.get('programInterestedIn');
                                
    //                             List<Program__c> programQuery = [
    //                                 SELECT Id, Full_Program_Name__c 
    //                                 FROM Program__c 
    //                                 WHERE Program_Code__c = :programCode 
    //                                 OR Full_Program_Name__c = :programCode
    //                                 LIMIT 1
    //                             ];
                                
    //                             if (!programQuery.isEmpty()) {
    //                                 programObjRecord = programQuery[0];
    //                             }
    //                         }
                            
    //                         if (programObjRecord != null) {
    //                             // Create unique key
    //                             String uniqueKey = groupTag + '-' + groupAppNumber + '-' + programObjRecord.Id;
                                
    //                             if (!existingProgramMap.containsKey(uniqueKey)) {
    //                                 Preferred_Program__c programRec = new Preferred_Program__c();
    //                                 programRec.Lead__c = leadId;
    //                                 programRec.Program_Group_Tag__c = groupTag;
    //                                 programRec.Application_Number__c = groupAppNumber;
    //                                 programRec.Program__c = programObjRecord.Id;
    //                                 programRec.Full_Program_Name__c = programObjRecord.Full_Program_Name__c;
                                    
    //                                 if (programMap.containsKey('major') && programMap.get('major') != null) {
    //                                     majorName = (String) programMap.get('major');
                                        
    //                                     List<Major__c> majorQuery = [
    //                                         SELECT Id 
    //                                         FROM Major__c 
    //                                         WHERE Name = :majorName AND Program__c = :programObjRecord.Id
    //                                         LIMIT 1
    //                                     ];
                                        
    //                                     if (!majorQuery.isEmpty()) {
    //                                         programRec.Major__c = majorQuery[0].Id;
    //                                     }
    //                                 }
                                    
    //                                 programList.add(programRec);
    //                             }
    //                         }
    //                     }
    //                 }
    //             }
                
    //             if (!programList.isEmpty()) {
    //                 insert programList;
    //             }
    //         }
    //     } catch (Exception e) {
    //         logFailedLead(JSON.serialize(programs), e, registrationNumber);
    //         throw new CustomException('Error insertPreferredPrograms method: ' + e.getMessage());
    //     }   
    // }
    
    
    

    public static void insertPreferredPrograms(String JSONKey,Object programs, Id leadId,String registrationNumber) {
        try {

            // Get the current datetime
            Datetime now = System.now();
            // Format the datetime to the desired format
            String formattedDate = now.format('yyyy-MM-dd:HH:mm:ss');
            
            // Update Lead's Auris_Last_Updated_Timestamp__c field with the formatted datetime
            Lead leadToUpdate = new Lead(Id = leadId);
            leadToUpdate.Auris_Last_Updated_Timestamp__c = formattedDate; // Store the formatted datetime as a String
            
            // Perform the update operation
            update leadToUpdate;
            // Query existing Preferred_Program__c records related to the lead
            Map<String, Preferred_Program__c> existingProgramMap = new Map<String, Preferred_Program__c>();
            for (Preferred_Program__c existingProgram : [
                SELECT Id, Program__c, Major__c 
                FROM Preferred_Program__c 
                WHERE Lead__c = :leadId 
            ]) {
                String uniqueKey = existingProgram.Program__c + '-' + existingProgram.Major__c;
                //system.debug(' 1171 uniqueKey---'+uniqueKey);
                existingProgramMap.put(uniqueKey, existingProgram);
            }
    
            //system.debug('1174 existingProgramMap--'+existingProgramMap);
            List<Preferred_Program__c> programList = new List<Preferred_Program__c>();
    
            for (Object program : (List<Object>) programs) {
                Map<String, Object> programMap;

                if (program instanceof String) {
                    // Case 1: stringified JSON
                    programMap = (Map<String, Object>) JSON.deserializeUntyped((String) program);
                } else {
                    // Case 2: already a map
                    programMap = (Map<String, Object>) program;
                }
    
    
    
                Preferred_Program__c programRec = new Preferred_Program__c();
                programRec.Lead__c = leadId; // Assign the Lead Id
    
                String programCode = null;
                String majorName = null;
                Program__c programObj = null;
                Major__c majorObj = null;
    
                // Query for Program__c based on a unique identifier (Program Code or Full Program Name)
                if (programMap.containsKey('programInterestedIn') && programMap.get('programInterestedIn') != null) {
                    programCode = (String) programMap.get('programInterestedIn');

                    List<Program__c> programQuery = [
                        SELECT Id, Full_Program_Name__c 
                        FROM Program__c 
                        WHERE Program_Code__c = :programCode 
                        OR Full_Program_Name__c = :programCode
                        LIMIT 1
                    ];

                    if (!programQuery.isEmpty()) {
                        programObj = programQuery[0];
                        programRec.Program__c = programObj.Id;
                        programRec.Full_Program_Name__c = programObj.Full_Program_Name__c;
                    } else {
                        throw new CustomException('Program not found for value: ' + programCode);
                    }
                }
    
                if (programMap.containsKey('major') && programMap.get('major') != null) {
                    majorName = (String) programMap.get('major');
                
                    List<Major__c> majorQuery = [
                        SELECT Id 
                        FROM Major__c 
                        WHERE Name = :majorName AND Program__c = :programObj.Id
                        LIMIT 1
                    ];
                
                    if (!majorQuery.isEmpty()) {
                        majorObj = majorQuery[0];
                        programRec.Major__c = majorObj.Id;
                    } else {
                        throw new CustomException('Major not found for name: ' + majorName);
                    }
                }
                
    
                // Create a unique key for the current program record
                if (programObj != null && majorObj != null) {
                    String uniqueKey = programObj.Id + '-' + majorObj.Id;
                    if (!existingProgramMap.containsKey(uniqueKey)) {
                        programList.add(programRec);
                       // system.debug('programRec --'+programRec);
                    }
                }
            }

    
            if (!programList.isEmpty()) {
                insert programList;
            } 
        } catch (Exception e) {
            //System.debug('Error Preferred Programs method: ' + e.getMessage());
            logFailedLead(JSON.serialize(programs), e,registrationNumber); // Log the failed attempt
            throw new CustomException('Error insertPreferredPrograms method: ' + e.getMessage());
        }   
    } 
    
    
    
    /** 
    * @description insert preffered prrogram for masters
    * @param programs - A list of maps where each map contains details of a preferred program
    *                  including program code and major name. This information is used to
    *                  look up and insert records into the Preferred_Program__c object.
    * @param leadId - The Id of the Lead to which the preferred programs are related.
    * @param registrationNumber lead registrationNumber
    **/
    
    // Created by: Rishav Raj
    public static void insertPreferredProgramsMasters(String JSONKey,Object programs, Id leadId, String registrationNumber) {
        try {
            // Query existing Preferred_Program__c records related to the lead
            Map<String, Preferred_Program__c> existingProgramMap = new Map<String, Preferred_Program__c>();
            for (Preferred_Program__c existingProgram : [
                SELECT Id, Full_Program_Name__c
                FROM Preferred_Program__c
                WHERE Lead__c = :leadId
            ]) {
                existingProgramMap.put(existingProgram.Full_Program_Name__c, existingProgram);
            }
            List<Preferred_Program__c> programList = new List<Preferred_Program__c>();
            for (Object program : (List<Object>) programs) {
                Map<String, Object> programMap;

            if (program instanceof String) {
                // Case 1: stringified JSON
                programMap = (Map<String, Object>) JSON.deserializeUntyped((String) program);
            } else {
                // Case 2: already a map
                programMap = (Map<String, Object>) program;
            }
                Preferred_Program__c programRec = new Preferred_Program__c();
                programRec.Lead__c = leadId;
                // Use Full_Program_Name__c directly from the input
                if (programMap.containsKey('programInterestedIn') && programMap.get('programInterestedIn') != null) {
                    String fullProgramName = (String) programMap.get('programInterestedIn');
                    programRec.Full_Program_Name__c = fullProgramName;
                    if (!existingProgramMap.containsKey(fullProgramName)) {
                        programList.add(programRec);
                    }
                }
            }
            // Insert new Preferred_Program__c records
            if (!programList.isEmpty()) {
                insert programList;
            }
        } catch (Exception e) {
            //System.debug('Error in Preferred Programs method: ' + e.getMessage());
            logFailedLead(JSON.serialize(programs), e, registrationNumber); // Log the failed attempt
            throw new CustomException('Error in insertPreferredProgramsMasters method: ' + e.getMessage());
        }
    }
    

    
   /**
    * @description
    ****************************************************************************************
    * Method Name : insertEducationalDetails
    * Created By : Preksha Chauhan
    * Created Date : 07/10/2024
    * Description : This method processes and inserts educational details associated with a
    *               given Lead into Salesforce. It performs the following tasks:
    *               - Updates the Lead's `Auris_Last_Updated_Timestamp__c` field with the
    *                 current datetime in the format 'yyyy-MM-dd:HH:mm:ss'.
    *               - Checks if the user has create access for the `Educational_Detail__c` object.
    *               - Collects years of completion from the provided educational details to avoid
    *                 duplicate records based on the year of completion.
    *               - Queries existing `Educational_Detail__c` records to identify duplicates.
    *               - Creates and inserts new `Educational_Detail__c` records based on the
    *                 provided data, skipping records with existing years of completion.
    *               - Logs any errors encountered and throws a `CustomException` in case of
    *                 failure.
    *
    * Parameters:
    * @param educationDetails - A list of maps where each map contains details about the
    *                          educational history of the Lead. This includes fields such as
    *                          school name, educational city, state, country, class, medium
    *                          of instruction, stream, year of completion, and percentage.
    * @param leadId - The Id of the Lead to which the educational details are related.
    * @param registrationNumber - The registration number associated with the Lead.
    ********************************************************************************************/    
    public static void insertEducationalDetails(String JSONKey,Object educationDetails, Id leadId, String registrationNumber) {
        try {
    
            // Get the current datetime
            Datetime now = System.now();
            // Format the datetime to the desired format
            String formattedDate = now.format('yyyy-MM-dd:HH:mm:ss');
    
            // Update Lead's Auris_Last_Updated_Timestamp__c field with the formatted datetime
            Lead leadToUpdate = new Lead(Id = leadId);
            leadToUpdate.Auris_Last_Updated_Timestamp__c = formattedDate; // Store the formatted datetime as a String
    
            // Perform the update operation
            update leadToUpdate;
    
            // Check create access for Educational_Detail__c
            if (!Schema.sObjectType.Educational_Detail__c.isCreateable()) {
                throw new CustomException('User does not have create access to Educational_Detail__c');
            }
    
            List<Educational_Detail__c> educationList = new List<Educational_Detail__c>();
            Set<String> yearsOfCompletion = new Set<String>();
    
            // Collect all years of completion first
            for (Object education : (List<Object>) educationDetails) {
                Map<String, Object> eduMap = (Map<String, Object>) education;
                if (eduMap.containsKey('yearOfCompletion') && eduMap.get('yearOfCompletion') != null) {
                    yearsOfCompletion.add((String) eduMap.get('yearOfCompletion'));
                }
            }
    
            // Query the Educational_Detail__c records by the collected years of completion
            Map<String, Educational_Detail__c> existingEducationDetailMap = new Map<String, Educational_Detail__c>();
            if (!yearsOfCompletion.isEmpty()) {
                for (Educational_Detail__c existingEducationDetail : [SELECT Id, Year_of_completion__c 
                                                                     FROM Educational_Detail__c 
                                                                     WHERE Lead__c = :leadId 
                                                                     AND Year_of_completion__c IN :yearsOfCompletion]) {
                    existingEducationDetailMap.put(existingEducationDetail.Year_of_completion__c, existingEducationDetail);
                }
            }
    
            // Create Educational_Detail__c records
            for (Object education : (List<Object>) educationDetails) {
                Map<String, Object> eduMap = (Map<String, Object>) education;
    
                // Check if year of completion exists in existing records (to avoid duplicates)
                if (eduMap.containsKey('yearOfCompletion') && eduMap.get('yearOfCompletion') != null) {
                    String yearOfCompletion = (String) eduMap.get('yearOfCompletion');
    
                    // Check if Educational_Detail__c record already exists for this Lead
                    if (existingEducationDetailMap.containsKey(yearOfCompletion)) {
                        continue; // Skip this record since it's a duplicate
                    }
                }
    
                // Create new Educational_Detail__c record
                Educational_Detail__c eduDetailRec = new Educational_Detail__c();
                eduDetailRec.Lead__c = leadId;
                handleRelatedInformationFieldMappings(JSONKey,eduMap, eduDetailRec);
                educationList.add(eduDetailRec);
            }
    
            // Insert the list of Educational_Detail__c records
            if (!educationList.isEmpty()) {
                insert educationList;
            }
        } catch (Exception e) {
            //System.debug('Error occurred in insertEducationalDetails: ' + e.getMessage());
        }
    }
    

   /**
    * @description 
    ****************************************************************************************
    * Method Name : insertCollegeEducationDetails
    * Created By : Preksha Chauhan
    * Created Date : 07/10/2024
    * Description : This method processes and inserts college education details associated with
    *               a given Lead into Salesforce. It performs the following tasks:
    *               - Updates the Lead's `Auris_Last_Updated_Timestamp__c` field with the
    *                 current datetime in the format 'yyyy-MM-dd:HH:mm:ss'.
    *               - Queries existing `College_Education__c` records related to the Lead to
    *                 identify records with the same degree/diploma and year of completion to
    *                 avoid duplicates.
    *               - Creates and inserts new `College_Education__c` records based on the provided
    *                 data, ensuring no duplicates based on a unique combination of degree/diploma
    *                 and year of completion.
    *               - Logs any errors encountered and throws a `CustomException` in case of
    *                 failure.
    *
    * Parameters:
    * @param collegeEducationInfo - A list of maps where each map contains details about the
    *                               college education history of the Lead. This includes fields
    *                               such as name of degree/diploma, year of completion, level
    *                               of examination, college name, name of university, expected
    *                               year of graduation, CGPA, specialization, and location.
    * @param leadId - The Id of the Lead to which the college education details are related.
    * @param registrationNumber lead registrationNumber
    ********************************************************************************************/
    public static void insertCollegeEducationDetails(String JSONKey,Object collegeEducationInfo, Id leadId,String registrationNumber) {
        try {
            //System.debug('Called insertCollegeEducationDetails method');
                
            Datetime now = System.now();
            // Format the datetime to the desired format
            String formattedDate = now.format('yyyy-MM-dd:HH:mm:ss');

            // Update Lead's Auris_Last_Updated_Timestamp__c field with the formatted datetime
            Lead leadToUpdate = new Lead(Id = leadId);
            leadToUpdate.Auris_Last_Updated_Timestamp__c = formattedDate; // Store the formatted datetime as a String
            
            // Perform the update operation
            update leadToUpdate;

            // Query existing College_Education__c records related to the lead
            Map<String, College_Education__c> existingCollegeEducationMap = new Map<String, College_Education__c>();
            for (College_Education__c existingCollegeEdu : [
                SELECT Id, Name_of_the_Degree_Diploma__c, Year_Of_Completion__c 
                FROM College_Education__c 
                WHERE Lead__c = :leadId 
            ]) {
                String uniqueKey = existingCollegeEdu.Name_of_the_Degree_Diploma__c + '-' + existingCollegeEdu.Year_Of_Completion__c;
                existingCollegeEducationMap.put(uniqueKey, existingCollegeEdu);
            }
    
            List<College_Education__c> collegeEducationList = new List<College_Education__c>();
    
            for (Object edu : (List<Object>) collegeEducationInfo) {
                Map<String, Object> collegeEduMap = (Map<String, Object>) edu;
    
                College_Education__c collegeEduRec = new College_Education__c();
                collegeEduRec.Lead__c = leadId;
                handleRelatedInformationFieldMappings(JSONKey,collegeEduMap, collegeEduRec);
                // Check for uniqueness based on Name of Degree/Diploma and Year of Completion
                String uniqueKey = collegeEduRec.Name_of_the_Degree_Diploma__c + '-' + collegeEduRec.Year_Of_Completion__c;
                // Check if a record with the same key already exists
                if (!existingCollegeEducationMap.containsKey(uniqueKey)) {
                    collegeEducationList.add(collegeEduRec);
                }
            }
    
            if (!collegeEducationList.isEmpty()) {
                insert collegeEducationList;
                //System.debug('Inserted ' + collegeEducationList.size() + ' College Education Detail records.');
            } 
            // else {
            //     System.debug('No new College Education Detail records to insert.');
            // }
        } catch (Exception e) {
            //System.debug('Error College Education Details method: ' + e.getMessage());
            logFailedLead(JSON.serialize(collegeEducationInfo), e,registrationNumber); // Log the failed attempt
            throw new CustomException('Error insertCollegeEducationDetails method: ' + e.getMessage());
        }   
    }    

    /**
     * @description
     * ****************************************************************************************
    * Method Name : insertAcademicResults
    * Created By : Preksha Chauhan
    * Created Date : 07/10/2024
    * Description : This method processes and inserts academic results details associated with
    *               a given Lead into Salesforce. It performs the following tasks:
    *               - Updates the Lead's `Auris_Last_Updated_Timestamp__c` field with the
    *                 current datetime in the format 'yyyy-MM-dd:HH:mm:ss'.
    *               - Queries existing `Academic_Results__c` records related to the Lead to
    *                 identify records with the same evaluation type, class, and subjects to
    *                 avoid duplicates.
    *               - Creates and inserts new `Academic_Results__c` records based on the provided
    *                 data, ensuring no duplicates based on a unique combination of evaluation
    *                 type, class, and subject.
    *               - Logs any errors encountered and throws a `CustomException` in case of
    *                 failure.
    *
    * Parameters:
    * @param academicResultsInfo - A list of maps where each map contains details about the
    *                              academic results of the Lead. This includes fields such as
    *                              evaluation type, class, subject, marks/grade points obtained,
    *                              maximum marks/grade points, percentage, and CGPA.
    * @param leadId - The Id of the Lead to which the academic results details are related.
    * @param registrationNumber lead registrationNumber
    ********************************************************************************************/
    public static void insertAcademicResults(String JSONKey,Object academicResultsInfo, Id leadId,String registrationNumber) {
        try {
            //System.debug('Called insertAcademicResults method');

            if (!Schema.sObjectType.Lead.isUpdateable()) {
                throw new CustomException('You do not have the necessary permissions to update Lead records.');
            }
            if (!Schema.sObjectType.Academic_Results__c.isCreateable() || !Schema.sObjectType.Academic_Results__c.isAccessible()) {
                throw new CustomException('You do not have the necessary permissions to create Academic_Results__c records.');
            }

            Datetime now = System.now();

            // Format the datetime to the desired format
            String formattedDate = now.format('yyyy-MM-dd:HH:mm:ss');

            // Update Lead's Auris_Last_Updated_Timestamp__c field with the formatted datetime
            Lead leadToUpdate = new Lead(Id = leadId);
            leadToUpdate.Auris_Last_Updated_Timestamp__c = formattedDate; // Store the formatted datetime as a String
            
            // Perform the update operation
            update leadToUpdate;
            // Query existing Academic_Results__c records related to the lead
            Map<String, Academic_Results__c> existingAcademicResultsMap = new Map<String, Academic_Results__c>();
            for (Academic_Results__c existingResult : [
                SELECT Id, Evaluation_Type__c, Class__c, Subjects__c
                FROM Academic_Results__c 
                WHERE Lead__c = :leadId 
            ]) {
                String uniqueKey = existingResult.Evaluation_Type__c + '-' + existingResult.Class__c + '-' + existingResult.Subjects__c;
                existingAcademicResultsMap.put(uniqueKey, existingResult);
            }
    
            List<Academic_Results__c> resultList = new List<Academic_Results__c>();
    
            for (Object academicResult : (List<Object>) academicResultsInfo) {
                Map<String, Object> academicResultMap = (Map<String, Object>) academicResult;
    
                Academic_Results__c resultRec = new Academic_Results__c();
                resultRec.Lead__c = leadId;
                handleRelatedInformationFieldMappings(JSONKey,academicResultMap, resultRec);
                String uniqueKey = resultRec.Evaluation_Type__c + '-' + resultRec.Class__c + '-' + resultRec.Subjects__c;
                // Check if a record with the same key already exists
                if (!existingAcademicResultsMap.containsKey(uniqueKey)) {
                    // Add more fields as needed
                    resultList.add(resultRec);
                }
            }
    
            if (!resultList.isEmpty()) {
                insert resultList;
            }
        } catch (Exception e) {
            //System.debug('Error Academic Results method: ' + e.getMessage());
            logFailedLead(JSON.serialize(academicResultsInfo), e,registrationNumber); // Log the failed attempt
            throw new CustomException('Error insertAcademicResults method: ' + e.getMessage());
        }   
    }
    
    /**
     * @description 
     * ****************************************************************************************
    * Method Name : insertEmploymentHistory
    * Created By : Preksha Chauhan
    * Created Date : 07/10/2024
    * Description : This method processes and inserts employment history details associated with
    *               a given Lead into Salesforce. It performs the following tasks:
    *               - Updates the Lead's `Auris_Last_Updated_Timestamp__c` field with the
    *                 current datetime in the format 'yyyy-MM-dd:HH:mm:ss'.
    *               - Queries existing `Employment_History__c` records related to the Lead to
    *                 identify records with the same company name, designation, and department
    *                 to avoid duplicates.
    *               - Creates and inserts new `Employment_History__c` records based on the provided
    *                 data, ensuring no duplicates based on a unique combination of company name,
    *                 designation, and department.
    *               - Logs any errors encountered and throws a `CustomException` in case of
    *                 failure.
    *
    * Parameters:
    * @param employmentHistoryInfo - A list of maps where each map contains details about the
    *                                employment history of the Lead. This includes fields such as
    *                                company name, designation, department, employment period (from
    *                                and to dates), and city.
    * @param leadId - The Id of the Lead to which the employment history details are related.
    * @param registrationNumber lead registrationNumber
    ********************************************************************************************/
    public static void insertEmploymentHistory(String JSONKey,Object employmentHistoryInfo, Id leadId,String registrationNumber) {
        try {
            Datetime now = System.now();

            // Format the datetime to the desired format
            String formattedDate = now.format('yyyy-MM-dd:HH:mm:ss');

            // Update Lead's Auris_Last_Updated_Timestamp__c field with the formatted datetime
            Lead leadToUpdate = new Lead(Id = leadId);
            leadToUpdate.Auris_Last_Updated_Timestamp__c = formattedDate; // Store the formatted datetime as a String
            
            // Perform the update operation
            update leadToUpdate;
            // Query existing Employment_History__c records related to the lead
            Map<String, Employment_History__c> existingEmploymentHistoryMap = new Map<String, Employment_History__c>();
            for (Employment_History__c existingEmployment : [
                SELECT Id, Name, Designation__c, Department__c, From__c, To__c, Employement_City__c
                FROM Employment_History__c 
                WHERE Lead__c = :leadId 
            ]) {
                String uniqueKey = existingEmployment.Name + '-' + existingEmployment.Designation__c + '-' + existingEmployment.Department__c;
                existingEmploymentHistoryMap.put(uniqueKey, existingEmployment);
            }
    
            List<Employment_History__c> employmentHistoryResultList = new List<Employment_History__c>();
    
            for (Object employmentHistory : (List<Object>) employmentHistoryInfo) {
                Map<String, Object> employmentHistoryMap = (Map<String, Object>) employmentHistory;
                Employment_History__c employmentHistoryRec = new Employment_History__c();
                 employmentHistoryRec.Lead__c = leadId;
                 handleRelatedInformationFieldMappings(JSONKey,employmentHistoryMap, employmentHistoryRec);
                String uniqueKey = employmentHistoryRec.Name + '-' + employmentHistoryRec.Designation__c + '-' + employmentHistoryRec.Department__c;
                // Check if a record with the same key already exists
                if (!existingEmploymentHistoryMap.containsKey(uniqueKey)) {
                    
                    // Add more fields as needed
                    employmentHistoryResultList.add(employmentHistoryRec);
                }
            }
    
            if (!employmentHistoryResultList.isEmpty()) {
                insert employmentHistoryResultList;
            }
        } catch (Exception e) {
            //System.debug('Error Employment History method: ' + e.getMessage());
            logFailedLead(JSON.serialize(employmentHistoryInfo), e,registrationNumber); // Log the failed attempt
            throw new CustomException('Error insertEmploymentHistory method: ' + e.getMessage());
        }   
    }
    
    /**
     * @description
     * ****************************************************************************************
    * Method Name : insertStandardisedTestScores
    * Created By : Preksha Chauhan
    * Created Date : 07/10/2024
    * Description : This method processes and inserts standardized test scores for a given Lead
    *               into Salesforce. It performs the following tasks:
    *               - Updates the Lead's `Auris_Last_Updated_Timestamp__c` field with the current
    *                 datetime in the format 'yyyy-MM-dd:HH:mm:ss'.
    *               - Checks if the user has create access to `Standardised_Test_Score_s__c`.
    *               - Collects all unique test names from the provided test scores.
    *               - Queries `Standardised_Test__c` records to get their Ids based on the collected test names.
    *               - Queries existing `Standardised_Test_Score_s__c` records related to the Lead to avoid
    *                 duplicates based on test names.
    *               - Creates new `Standardised_Test_Score_s__c` records, mapping each test score to
    *                 its corresponding `Standardised_Test__c` record.
    *               - Logs any errors encountered and throws a `CustomException` in case of failure.
    *
    * Parameters:
    * @param testScores - A list of maps where each map contains details about the standardized
    *                     test scores for the Lead. This includes fields such as test name, test
    *                     date, percentile, and total score.
    * @param leadId - The Id of the Lead to which the standardized test scores are related.
    * @param registrationNumber lead registrationNumber
    ********************************************************************************************/
    public static void insertStandardisedTestScores(String JSONKey,List<Object> testScores, Id leadId,String registrationNumber) {
        try {
            Datetime now = System.now();

            // Format the datetime to the desired format
            String formattedDate = now.format('yyyy-MM-dd:HH:mm:ss');

            // Update Lead's Auris_Last_Updated_Timestamp__c field with the formatted datetime
            Lead leadToUpdate = new Lead(Id = leadId);
            leadToUpdate.Auris_Last_Updated_Timestamp__c = formattedDate; // Store the formatted datetime as a String
            
            // Perform the update operation
            update leadToUpdate;
            // Check create access for Standardised_Test_Score_s__c
            if (!Schema.sObjectType.Standardised_Test_Score_s__c.isCreateable()) {
                throw new CustomException('User does not have create access to Standardised_Test_Score_s__c');
            }
    
            List<Standardised_Test_Score_s__c> testScoreRecords = new List<Standardised_Test_Score_s__c>();
            Set<String> testNames = new Set<String>();
    
            // Collect all test names first
            for (Object testScoreObj : testScores) {
                Map<String, Object> testScoreMap = (Map<String, Object>) testScoreObj;
                if (testScoreMap.containsKey('testName') && testScoreMap.get('testName') != null) {
                    testNames.add((String) testScoreMap.get('testName'));
                }
            }
    
            // Query the Standardised_Test__c records by the collected test names
            Map<String, Standardised_Test__c> testNameToRecordMap = new Map<String, Standardised_Test__c>();
            if (!testNames.isEmpty()) {
                for (Standardised_Test__c testRec : [SELECT Id, Name FROM Standardised_Test__c WHERE Name IN :testNames ]) {
                    testNameToRecordMap.put(testRec.Name, testRec);
                }
            }
    
            // Map to store existing Standardised_Test_Score_s__c records by Test Name and Lead Id
            Map<String, Standardised_Test_Score_s__c> existingTestScoreMap = new Map<String, Standardised_Test_Score_s__c>();
            if (!testNames.isEmpty()) {
                for (Standardised_Test_Score_s__c existingTestScore : [SELECT Id, Test__r.Name 
                                                                      FROM Standardised_Test_Score_s__c 
                                                                      WHERE Lead__c = :leadId 
                                                                      AND Test__r.Name IN :testNames]) {
                    existingTestScoreMap.put(existingTestScore.Test__r.Name, existingTestScore);
                }
            }
    
            // Create Standardised_Test_Score_s__c records with the lookup to Standardised_Test__c
            for (Object testScoreObj : testScores) {
                Map<String, Object> testScoreMap = (Map<String, Object>) testScoreObj;
    
                // Check if test name exists in Standardised_Test__c and Standardised_Test_Score_s__c (to avoid duplicates)
                if (testScoreMap.containsKey('testName') && testScoreMap.get('testName') != null) {
                    String testName = (String) testScoreMap.get('testName');
    
                    // Check if Standardised_Test__c record exists
                    if (!testNameToRecordMap.containsKey(testName)) {
                        continue; // Skip this record since the test name wasn't found
                    }
    
                    // Check if Standardised_Test_Score_s__c record already exists for this Lead
                    if (existingTestScoreMap.containsKey(testName)) {
                        continue; // Skip this record since it's a duplicate
                    }
                }
    
                // Create new Standardised_Test_Score_s__c record
                Standardised_Test_Score_s__c scoreRec = new Standardised_Test_Score_s__c();
                scoreRec.Lead__c = leadId;
                if (testScoreMap.containsKey('testName') && testScoreMap.get('testName') != null) {
                    String testName = (String) testScoreMap.get('testName');
                    scoreRec.Test__c = testNameToRecordMap.get(testName).Id;
                }
                handleRelatedInformationFieldMappings(JSONKey,testScoreMap, scoreRec);
    
                testScoreRecords.add(scoreRec);
            }
    
            if (!testScoreRecords.isEmpty()) {
                insert testScoreRecords;
            }
        } catch (Exception e) {
            //System.debug('Error insertStandardisedTestScores method: ' + e.getMessage());
            logFailedLead(JSON.serialize(testScores), e,registrationNumber); // Log the failed attempt
            throw new CustomException('Error insertStandardisedTestScores method: ' + e.getMessage());
        }
    } 
    
    /**
     * @description
     * ****************************************************************************************
    * Method Name : insertExtracurricularActivities
    * Created By : Preksha Chauhan
    * Created Date : 07/10/2024
    * Description : This method processes and inserts extracurricular activities for a given Lead
    *               into Salesforce. It performs the following tasks:
    *               - Updates the Lead's `Auris_Last_Updated_Timestamp__c` field with the current
    *                 datetime in the format 'yyyy-MM-dd:HH:mm:ss'.
    *               - Checks if the `activities` object is null and handles it appropriately.
    *               - Collects all unique activity names from the provided activities data.
    *               - Queries `Extracurricular_activities__c` records related to the Lead to avoid
    *                 duplicates based on activity names.
    *               - Creates new `Extracurricular_activities__c` records with the details provided,
    *                 avoiding duplicates.
    *               - Logs any errors encountered and throws a `CustomException` in case of failure.
    *
    * Parameters:
    * @param activities - A list of maps where each map contains details about extracurricular
    *                     activities for the Lead. This includes fields such as activity name
    *                     and level of participation.
    * @param leadId - The Id of the Lead to which the extracurricular activities are related.
    * @param registrationNumber lead registrationNumber
    ********************************************************************************************/     
    public static void insertExtracurricularActivities(String JSONKey,Object activities, Id leadId,String registrationNumber) {
        try {
            if (!Schema.sObjectType.Lead.isUpdateable()) {
                throw new CustomException('You do not have the necessary permissions to update Lead records.');
            }
            if (!Schema.sObjectType.Extracurricular_activities__c.isCreateable() || !Schema.sObjectType.Extracurricular_activities__c.isAccessible()) {
                throw new CustomException('You do not have the necessary permissions to create Extracurricular_activities__c records.');
            }
            Datetime now = System.now();

            // Format the datetime to the desired format
            String formattedDate = now.format('yyyy-MM-dd:HH:mm:ss');

            // Update Lead's Auris_Last_Updated_Timestamp__c field with the formatted datetime
            Lead leadToUpdate = new Lead(Id = leadId);
            leadToUpdate.Auris_Last_Updated_Timestamp__c = formattedDate; // Store the formatted datetime as a String
            
            // Perform the update operation
            update leadToUpdate;

            if (activities == null) {
                //System.debug('Activities object is null.');
                return;
            }
            
            List<Extracurricular_activities__c> activityList = new List<Extracurricular_activities__c>();
            Set<String> activityNames = new Set<String>();
            // Collect all activity names first
            for (Object activity : (List<Object>) activities) {
                if (activity == null) {
                    //System.debug('Encountered null activity object.');
                    continue;
                }
    
                Map<String, Object> activityMap = (Map<String, Object>) activity;
                if (activityMap.containsKey('activities') && activityMap.get('activities') != null) {
                    activityNames.add((String) activityMap.get('activities'));
                }
            }
            // Query the Extracurricular_activities__c records by the collected activity names
            Map<String, Extracurricular_activities__c> existingActivityMap = new Map<String, Extracurricular_activities__c>();
            if (!activityNames.isEmpty()) {
                for (Extracurricular_activities__c existingActivity : [SELECT Id, Activities__c 
                                                                       FROM Extracurricular_activities__c 
                                                                       WHERE Lead__c = :leadId 
                                                                       AND Activities__c IN :activityNames ]) {
                    existingActivityMap.put(existingActivity.Activities__c, existingActivity);
                }
            }
    
            // Create Extracurricular_activities__c records
            for (Object activity : (List<Object>) activities) {
                if (activity == null) {
                    //System.debug('Encountered null activity object.');
                    continue;
                }
    
                Map<String, Object> activityMap = (Map<String, Object>) activity;
    
                // Check if activity name exists in existing records (to avoid duplicates)
                if (activityMap.containsKey('activities') && activityMap.get('activities') != null) {
                    String activityName = (String) activityMap.get('activities');
                    // Check if Extracurricular_activities__c record already exists for this Lead
                    if (existingActivityMap.containsKey(activityName)) {
                        continue; // Skip this record since it's a duplicate
                    }
                }
    
                // Create new Extracurricular_activities__c record
                Extracurricular_activities__c activityRec = new Extracurricular_activities__c();
                activityRec.Lead__c = leadId;
                handleRelatedInformationFieldMappings(JSONKey,activityMap, activityRec);
    
                activityList.add(activityRec);
            }
    
            // Insert Extracurricular_activities__c records
            if (!activityList.isEmpty()) {
                insert activityList;
            }
        } catch (Exception e) {
            logFailedLead(JSON.serialize(activities), e,registrationNumber); // Log the failed attempt
            throw new CustomException('Error insertExtracurricularActivities method: ' + e.getMessage());
        }
    }
    /**
     * @description
     * ****************************************************************************************
    * Method Name : insertSiblingInformation
    * Created By : Preksha Chauhan
    * Created Date : 07/10/2024
    * Description : This method processes and inserts sibling information for a given Lead
    *               into Salesforce. It performs the following tasks:
    *               - Updates the Lead's `Auris_Last_Updated_Timestamp__c` field with the current
    *                 datetime in the format 'yyyy-MM-dd:HH:mm:ss'.
    *               - Checks if the `siblings` object is null and handles it appropriately.
    *               - Iterates over the provided siblings data to:
    *                 - Check for existing sibling records to avoid duplicates.
    *                 - Create new `Sibling_Information__c` records with the details provided.
    *                 - Links the sibling to a `Program__c` record if a valid program code is provided.
    *               - Inserts the new sibling records into Salesforce.
    *               - Logs any errors encountered and throws a `CustomException` in case of failure.
    *
    * Parameters:
    * @param siblings - A list of maps where each map contains details about a sibling, including
    *                   sibling name, year of graduation, program code, and whether the sibling
    *                   is studying at Ahmedabad University.
    * @param leadId - The Id of the Lead to which the sibling information is related.
    * @param registrationNumber lead registrationNumber
    ********************************************************************************************/
    public static void insertSiblingInformation(String JSONKey, Object siblings, Id leadId, String registrationNumber) {
        try {
            System.debug('insertSiblingInformation called | LeadId=' + leadId + ', JSONKey=' + JSONKey);
    
            if (!Schema.sObjectType.Lead.isUpdateable()) {
                throw new CustomException('You do not have the necessary permissions to update Lead records.');
            }
            if (!Schema.sObjectType.Sibling_Information__c.isCreateable() || !Schema.sObjectType.Sibling_Information__c.isAccessible()) {
                throw new CustomException('You do not have the necessary permissions to create Sibling_Information__c records.');
            }
    
            Datetime now = System.now();
            String formattedDate = now.format('yyyy-MM-dd:HH:mm:ss');
    
            Lead leadToUpdate = new Lead(Id = leadId);
            leadToUpdate.Auris_Last_Updated_Timestamp__c = formattedDate;
            update leadToUpdate;
            System.debug('Updated Lead timestamp: ' + formattedDate);
    
            if (siblings == null) {
                System.debug('No siblings data provided, exiting method.');
                return;
            }
    
            List<Sibling_Information__c> siblingList = new List<Sibling_Information__c>();
            Set<String> programCodes = new Set<String>();
            List<Map<String, Object>> siblingMaps = new List<Map<String, Object>>();
    
            for (Object sibling : (List<Object>) siblings) {
                if (sibling == null) {
                    System.debug('Skipping null sibling entry');
                    continue;
                }
                Map<String, Object> siblingMap = (Map<String, Object>) sibling;
                siblingMaps.add(siblingMap);
    
                String programCode = siblingMap.containsKey('program') ? (String) siblingMap.get('program') : null;
                if (programCode != null) {
                    programCodes.add(programCode);
                    System.debug('Found Program Code: ' + programCode);
                }
            }
    
            Map<String, Id> programCodeToIdMap = new Map<String, Id>();
            if (!programCodes.isEmpty()) {
                for (Program__c program : [
                    SELECT Id, Program_Code__c FROM Program__c 
                    WHERE Program_Code__c IN :programCodes
                ]) {
                    programCodeToIdMap.put(program.Program_Code__c, program.Id);
                    System.debug('Program Mapped: ' + program.Program_Code__c + ' → ' + program.Id);
                }
            }
    
            Set<String> siblingNames = new Set<String>();
            Set<String> graduationYears = new Set<String>();
    
            for (Map<String, Object> siblingMap : siblingMaps) {
                String siblingName = siblingMap.containsKey('siblingName') ? (String) siblingMap.get('siblingName') : null;
                String yearOfGraduation = siblingMap.containsKey('yearOfGraduation') ? String.valueOf(siblingMap.get('yearOfGraduation')) : null;
    
                if (siblingName != null && yearOfGraduation != null) {
                    siblingNames.add(siblingName);
                    graduationYears.add(yearOfGraduation);
                    System.debug('Potential sibling: ' + siblingName + ' | Year=' + yearOfGraduation);
                }
            }
    
            Map<String, Sibling_Information__c> existingSiblingMap = new Map<String, Sibling_Information__c>();
            if (!siblingNames.isEmpty() && !graduationYears.isEmpty()) {
                for (Sibling_Information__c sibling : [
                    SELECT Id, Name, Year_of_graduation__c 
                    FROM Sibling_Information__c 
                    WHERE Lead__c = :leadId 
                    AND Name IN :siblingNames 
                    AND Year_of_graduation__c IN :graduationYears
                ]) {
                    existingSiblingMap.put(sibling.Name + sibling.Year_of_graduation__c, sibling);
                    System.debug('Existing sibling found: ' + sibling.Name + ' | Year=' + sibling.Year_of_graduation__c);
                }
            }
    
            for (Map<String, Object> siblingMap : siblingMaps) {
                String programCode = siblingMap.containsKey('program') ? (String) siblingMap.get('program') : null;
    
                Sibling_Information__c siblingRec = new Sibling_Information__c();
                siblingRec.Lead__c = leadId;
    
                if (programCode != null && programCodeToIdMap.containsKey(programCode)) {
                    siblingRec.Program__c = programCodeToIdMap.get(programCode);
                    System.debug('Linked Program for sibling: ' + programCode + ' → ' + siblingRec.Program__c);
                } else if (programCode != null) {
                    System.debug('Program not found for code: ' + programCode);
                    throw new CustomException('Program with code ' + programCode + ' not found.');
                }
    
                handleRelatedInformationFieldMappings(JSONKey, siblingMap, siblingRec);
                System.debug('📄 After field mapping siblingRec: ' + JSON.serialize(siblingRec));
    
                if (siblingRec.Name == null || siblingRec.Year_of_graduation__c == null) {
                    System.debug('Skipping sibling due to missing Name or Year: ' + JSON.serialize(siblingRec));
                    continue;
                }
                if (existingSiblingMap.containsKey(siblingRec.Name + siblingRec.Year_of_graduation__c)) {
                    System.debug('Skipping duplicate sibling: ' + siblingRec.Name + ' | Year=' + siblingRec.Year_of_graduation__c);
                    continue;
                }
    
                siblingList.add(siblingRec);
            }
    
            if (!siblingList.isEmpty()) {
                insert siblingList;
                System.debug('Inserted sibling records: ' + JSON.serialize(siblingList));
            } else {
                System.debug('No new sibling records to insert.');
            }
    
        } catch (Exception e) {
            System.debug('Error in insertSiblingInformation: ' + e.getMessage());
            logFailedLead(JSON.serialize(siblings), e, registrationNumber);
            throw new CustomException('Error insertSiblingInformation method: ' + e.getMessage());
        }
    }
          
    
    /**
     * @description
     * ****************************************************************************************
    * Method Name : insertPersonalStatement
    * Created By : Preksha Chauhan
    * Created Date : 07/10/2024
    * Description : This method processes and inserts personal statement information for a given Lead
    *               into Salesforce. It performs the following tasks:
    *               - Updates the Lead's `Auris_Last_Updated_Timestamp__c` field with the current
    *                 datetime in the format 'yyyy-MM-dd:HH:mm:ss'.
    *               - Checks if the `statement` object is null and handles it appropriately.
    *               - Queries existing `Personal_Statement__c` records related to the Lead to check for
    *                 duplicates.
    *               - Iterates over the provided personal statement data to:
    *                 - Check for duplicate personal statements based on existing records.
    *                 - Create new `Personal_Statement__c` records with the details provided.
    *               - Inserts the new personal statement records into Salesforce.
    *               - Logs any errors encountered and throws a `CustomException` in case of failure.
    *
    * Parameters:
    * @param statement - A list of maps where each map contains details about a personal statement,
    *                    including the statement text.
    * @param leadId - The Id of the Lead to which the personal statements are related.
    * @param registrationNumber lead registrationNumber

    ********************************************************************************************/
    public static void insertPersonalStatement(String JSONKey,Object statement, Id leadId, String registrationNumber) {
        try {
            
            Datetime now = System.now();

            // Format the datetime to the desired format
            String formattedDate = now.format('yyyy-MM-dd:HH:mm:ss');

            // Update Lead's Auris_Last_Updated_Timestamp__c field with the formatted datetime
            Lead leadToUpdate = new Lead(Id = leadId);
            leadToUpdate.Auris_Last_Updated_Timestamp__c = formattedDate; // Store the formatted datetime as a String
            
            // Perform the update operation
            update leadToUpdate;
            if (statement == null) {
                return;
            }
            
            List<Personal_Statement__c> statementList = new List<Personal_Statement__c>();
    
            // Query existing Personal_Statement__c records for the lead
            Map<String, Personal_Statement__c> existingStatementsMap = new Map<String, Personal_Statement__c>();
            for (Personal_Statement__c existingStatement : [
                SELECT Id, Personal_Statement__c 
                FROM Personal_Statement__c 
                WHERE Lead__c = :leadId
            ]) {
                existingStatementsMap.put(existingStatement.Personal_Statement__c, existingStatement);
            }
    
            for (Object ps : (List<Object>) statement) {
                if (ps == null) {
                    continue;
                }
                
                Map<String, Object> psMap = (Map<String, Object>) ps;
                
                if (!psMap.containsKey('personalStatement') || psMap.get('personalStatement') == null) {
                    continue;
                }
                
                String statementText = (String) psMap.get('personalStatement');
    
                // Check if the statement is already in the existing records map
                if (existingStatementsMap.containsKey(statementText)) {
                    continue;
                }
                
                Personal_Statement__c psRec = new Personal_Statement__c();
                psRec.Lead__c = leadId;
                handleRelatedInformationFieldMappings(JSONKey,psMap, psRec);
                statementList.add(psRec);
            }
            
            if (!statementList.isEmpty()) {
                insert statementList;
            } 
        } catch (Exception e) {
            //System.debug('Error Personal Statement method: ' + e.getMessage());
            logFailedLead(JSON.serialize(statement), e,registrationNumber); // Log the failed attempt
            throw new CustomException('Error insertPersonalStatement method: ' + e.getMessage());
        }   
    }  
    
    /**
     * @description
     * ****************************************************************************************
    * Method Name : insertDocumentDetails
    * Created By : Preksha Chauhan
    * Created Date : 07/10/2024
    * Description : This method processes and inserts document details related to a given Lead
    *               into Salesforce. It performs the following tasks:
    *               - Updates the Lead's `Auris_Last_Updated_Timestamp__c` field with the current
    *                 datetime in the format 'yyyy-MM-dd:HH:mm:ss'.
    *               - Checks if the user has read access to `Document__c` and create access to 
    *                 `Document_Detail__c`. Throws a `CustomException` if access permissions are 
    *                 insufficient.
    *               - Collects document names from the provided documents and queries existing 
    *                 `Document__c` records by these names.
    *               - Queries existing `Document_Detail__c` records related to the Lead to avoid 
    *                 duplicates.
    *               - Iterates over the provided document data to:
    *                 - Check for duplicates and verify that the document name exists in 
    *                   `Document__c`.
    *                 - Create new `Document_Detail__c` records with the relevant details and 
    *                   lookup to `Document__c`.
    *               - Inserts the new document detail records into Salesforce.
    *               - Logs any errors encountered and throws a `CustomException` in case of failure.
    *
    * Parameters:
    * @param documents - A list of maps where each map contains details about a document, 
    *                    including the document name, type, and URL.
    * @param leadId - The Id of the Lead to which the document details are related.
    * @param registrationNumber lead registrationNumber
    ********************************************************************************************/
    public static void insertDocumentDetails(String JSONKey,Object documents, Id leadId,String registrationNumber) {
        try {
            Datetime now = System.now();

            // Format the datetime to the desired format
            String formattedDate = now.format('yyyy-MM-dd:HH:mm:ss');

            // Update Lead's Auris_Last_Updated_Timestamp__c field with the formatted datetime
            Lead leadToUpdate = new Lead(Id = leadId);
            leadToUpdate.Auris_Last_Updated_Timestamp__c = formattedDate; // Store the formatted datetime as a String
            
            // Perform the update operation
            update leadToUpdate;
            // Check read access for Document__c
            if (!Schema.sObjectType.Document__c.isAccessible()) {
                throw new CustomException('User does not have read access to Document__c');
            }
            // Check create access for Document_Detail__c
            if (!Schema.sObjectType.Document_Detail__c.isCreateable()) {
                throw new CustomException('User does not have create access to Document_Detail__c');
            }
            List<Document_Detail__c> documentList = new List<Document_Detail__c>();
            Set<String> documentNames = new Set<String>();
    
            // Collect all document names first
            for (Object document : (List<Object>) documents) {
                Map<String, Object> docMap = (Map<String, Object>) document;
                if (docMap.containsKey('documentName') && docMap.get('documentName') != null) {
                    documentNames.add((String) docMap.get('documentName'));
                }
            }
    
            // Query the Document__c records by the collected names
            Map<String, Document__c> docNameToRecordMap = new Map<String, Document__c>();
            if (!documentNames.isEmpty()) {
                for (Document__c docRec : [SELECT Id, Name FROM Document__c WHERE Name IN :documentNames]) {
                    docNameToRecordMap.put(docRec.Name, docRec);
                }
            }
    
            // Map to store existing Document_Detail__c records by Document Name
            Map<String, Document_Detail__c> existingDocDetailMap = new Map<String, Document_Detail__c>();
            if (!documentNames.isEmpty()) {
                for (Document_Detail__c existingDocDetail : [SELECT Id, Document_Name__r.Name 
                                                            FROM Document_Detail__c 
                                                            WHERE Lead__c = :leadId 
                                                            AND Document_Name__r.Name IN :documentNames]) {
                    existingDocDetailMap.put(existingDocDetail.Document_Name__r.Name, existingDocDetail);
                }
            }
    
            // Create Document_Detail__c records with the lookup to Document__c
            for (Object document : (List<Object>) documents) {
                Map<String, Object> docMap = (Map<String, Object>) document;
    
                // Check if document name exists in Document__c and Document_Detail__c (to avoid duplicates)
                if (docMap.containsKey('documentName') && docMap.get('documentName') != null) {
                    String documentName = (String) docMap.get('documentName');
                    
                    // Check if Document__c record exists
                    if (!docNameToRecordMap.containsKey(documentName)) {
                        continue; // Skip this record since the document name wasn't found
                    }
                    
                    // Check if Document_Detail__c record already exists for this Lead
                    if (existingDocDetailMap.containsKey(documentName)) {
                        continue; // Skip this record since it's a duplicate
                    }
                }
    
                // Create new Document_Detail__c record
                Document_Detail__c docDetailRec = new Document_Detail__c();
                docDetailRec.Lead__c = leadId;
    
                if (docMap.containsKey('documentName') && docMap.get('documentName') != null) {
                    String documentName = (String) docMap.get('documentName');
                    docDetailRec.Document_Name__c = docNameToRecordMap.get(documentName).Id;
                }
    
                handleRelatedInformationFieldMappings(JSONKey,docMap, docDetailRec);
    
                documentList.add(docDetailRec);
            }
    
            // Insert Document_Detail__c records
            if (!documentList.isEmpty()) {
                insert documentList;
            }
        } catch (Exception e) {
            //System.debug('Error insertDocumentDetails method: ' + e.getMessage());
            logFailedLead(JSON.serialize(documents), e,registrationNumber); // Log the failed attempt
            throw new CustomException('Error insertDocumentDetails method: ' + e.getMessage());
        }
    }    
    
   /**
    * @description
    ****************************************************************************************
    * Method Name : insertApplicationPayments
    * Created By : Preksha Chauhan
    * Created Date : 07/10/2024
    * Description : This method processes and inserts application payment details related to a 
    *               given Lead into Salesforce. It performs the following tasks:
    *               - Updates the Lead's `Auris_Last_Updated_Timestamp__c` field with the current
    *                 datetime in the format 'yyyy-MM-dd:HH:mm:ss'.
    *               - Checks if the `payments` object is null and handles it appropriately.
    *               - Collects transaction reference numbers from the provided payments and queries
    *                 existing `Application_Payment__c` records by these reference numbers.
    *               - Iterates over the provided payment data to:
    *                 - Check for duplicates based on transaction reference numbers.
    *                 - Create new `Application_Payment__c` records with the relevant payment details.
    *               - Inserts the new application payment records into Salesforce.
    *               - Logs any errors encountered and throws a `CustomException` in case of failure.
    *
    * Parameters:
    * @param payments - A list of maps where each map contains details about a payment, including
    *                    the payment source, bank name, transaction reference number, date of
    *                    transaction, and amount received.
    * @param leadId - The Id of the Lead to which the payment details are related.
    * @param registrationNumber lead registrationNumber
    ********************************************************************************************/
    public static void insertApplicationPayments(String JSONKey,Object payments, Id leadId,String registrationNumber) {
        try {
           // System.debug('Called insertApplicationPayments method');

            if (!Schema.sObjectType.Lead.isUpdateable()) {
                throw new CustomException('You do not have the necessary permissions to update Lead records.');
            }
            if (!Schema.sObjectType.Application_Payment__c.isCreateable() || !Schema.sObjectType.Application_Payment__c.isAccessible()) {
                throw new CustomException('You do not have the necessary permissions to create Application_Payment__c records.');
            }
            Datetime now = System.now();
            // Format the datetime to the desired format
            String formattedDate = now.format('yyyy-MM-dd:HH:mm:ss');

            // Update Lead's Auris_Last_Updated_Timestamp__c field with the formatted datetime
            Lead leadToUpdate = new Lead(Id = leadId);
            leadToUpdate.Auris_Last_Updated_Timestamp__c = formattedDate; // Store the formatted datetime as a String
            
            // Perform the update operation
            update leadToUpdate;
            if (payments == null) {
                return;
            }
            
            List<Application_Payment__c> paymentList = new List<Application_Payment__c>();
            Set<String> transactionReferenceNumbers = new Set<String>();
    
            // Collect all transaction reference numbers first
            for (Object payment : (List<Object>) payments) {
                Map<String, Object> paymentMap = (Map<String, Object>) payment;
                if (paymentMap.containsKey('transactionReferenceNumber') && paymentMap.get('transactionReferenceNumber') != null) {
                    transactionReferenceNumbers.add((String) paymentMap.get('transactionReferenceNumber'));
                }
            }
    
            // Query existing Application_Payment__c records by transaction reference numbers
            Map<String, Application_Payment__c> transactionRefToRecordMap = new Map<String, Application_Payment__c>();
            if (!transactionReferenceNumbers.isEmpty()) {
                for (Application_Payment__c existingPayment : [SELECT Id, Transaction_Reference_Number__c 
                                                              FROM Application_Payment__c 
                                                              WHERE Lead__c = :leadId 
                                                              AND Transaction_Reference_Number__c IN :transactionReferenceNumbers ]) {
                    transactionRefToRecordMap.put(existingPayment.Transaction_Reference_Number__c, existingPayment);
                }
            }
    
            // Create Application_Payment__c records
            for (Object payment : (List<Object>) payments) {
                Map<String, Object> paymentMap = (Map<String, Object>) payment;
    
                // Check if transaction reference number already exists for this lead
                if (paymentMap.containsKey('transactionReferenceNumber') && paymentMap.get('transactionReferenceNumber') != null) {
                    String transactionRefNumber = (String) paymentMap.get('transactionReferenceNumber');
                    
                    // Check if transaction reference number already exists
                    if (transactionRefToRecordMap.containsKey(transactionRefNumber)) {
                        continue; // Skip this record since it's a duplicate
                    }
                }
    
                // Create new Application_Payment__c record
                Application_Payment__c paymentRec = new Application_Payment__c();
                paymentRec.Lead__c = leadId;
    
                handleRelatedInformationFieldMappings(JSONKey,paymentMap, paymentRec);
                
                paymentList.add(paymentRec);
            }
    
            // Insert Application_Payment__c records
            if (!paymentList.isEmpty()) {
                insert paymentList;
            }
        } catch (Exception e) {
            //System.debug('Error Application Payments method: ' + e.getMessage());
            logFailedLead(JSON.serialize(payments), e,registrationNumber); // Log the failed attempt
            throw new CustomException('Error insertApplicationPayments method: ' + e.getMessage());
        }     
    }

    /**
     * @description
     * ****************************************************************************************
    * Method Name : insertProfessionalAwards
    * Created By  : Preksha Chauhan
    * Created Date: 07/10/2024
    * Description : This method processes and inserts professional award details related to a 
    *               given Lead into Salesforce. It performs the following tasks:
    *               - Updates the Lead's `Auris_Last_Updated_Timestamp__c` field with the current
    *                 datetime in the format 'yyyy-MM-dd:HH:mm:ss'.
    *               - Checks if the `professionalAwards` object is null and handles it appropriately.
    *               - Collects award honors from the provided professional awards and queries
    *                 existing `Professional_Award_Achievement__c` records by these award honors.
    *               - Iterates over the provided professional award data to:
    *                 - Check for duplicates based on award honors.
    *                 - Create new `Professional_Award_Achievement__c` records with the relevant award details.
    *               - Inserts the new professional award records into Salesforce.
    *               - Logs any errors encountered and throws a `CustomException` in case of failure.
    *
    * Parameters:
    * @param professionalAwards - A list of maps where each map contains details about a professional
    *                             award, including the award honor, name of the organization, year of 
    *                             the award, level, and how the lead came to know about the organization.
    * @param leadId - The Id of the Lead to which the professional award details are related.
    * @param registrationNumber lead registrationNumber
    ********************************************************************************************/
    public static void insertProfessionalAwards(String JSONKey,Object professionalAwards, Id leadId,String registrationNumber) {
        try {
            //System.debug('Called insertProfessionalAwards method ====================');
    
            // Get the current datetime
            Datetime now = System.now();
            // Format the datetime to the desired format
            String formattedDate = now.format('yyyy-MM-dd:HH:mm:ss');
            
            // Update Lead's Auris_Last_Updated_Timestamp__c field with the formatted datetime
            Lead leadToUpdate = new Lead(Id = leadId);
            leadToUpdate.Auris_Last_Updated_Timestamp__c = formattedDate; // Store the formatted datetime as a String
            
            // Perform the update operation
            update leadToUpdate;
    
            // Check create access for Professional_Award_Achievement__c
            if (!Schema.sObjectType.Professional_Award_Achievement__c.isCreateable()) {
                throw new CustomException('User does not have create access to Professional_Award_Achievement__c');
            }
    
            List<Professional_Award_Achievement__c> awardList = new List<Professional_Award_Achievement__c>();
            Set<String> awardNames = new Set<String>();
    
            // Collect all award names first
            for (Object award : (List<Object>) professionalAwards) {
                Map<String, Object> awardMap = (Map<String, Object>) award;
                if (awardMap.containsKey('awardHonor') && awardMap.get('awardHonor') != null) {
                    awardNames.add((String) awardMap.get('awardHonor'));
                }
            }
    
            // Query the Professional_Award_Achievement__c records by the collected award names
            Map<String, Professional_Award_Achievement__c> existingAwardMap = new Map<String, Professional_Award_Achievement__c>();
            if (!awardNames.isEmpty()) {
                for (Professional_Award_Achievement__c existingAward : [SELECT Id, Name FROM Professional_Award_Achievement__c WHERE Lead__c = :leadId AND Name IN :awardNames]) {
                    existingAwardMap.put(existingAward.Name, existingAward);
                }
            }
    
            // Create Professional_Award_Achievement__c records
            for (Object award : (List<Object>) professionalAwards) {
                Map<String, Object> awardMap = (Map<String, Object>) award;
    
                // Check if award honor exists in existing records (to avoid duplicates)
                if (awardMap.containsKey('awardHonor') && awardMap.get('awardHonor') != null) {
                    String awardHonor = (String) awardMap.get('awardHonor');
    
                    // Check if Professional_Award_Achievement__c record already exists for this Lead
                    if (existingAwardMap.containsKey(awardHonor)) {
                        continue; // Skip this record since it's a duplicate
                    }
                }
    
                // Create new Professional_Award_Achievement__c record
                Professional_Award_Achievement__c awardRec = new Professional_Award_Achievement__c();
                awardRec.Lead__c = leadId;
    
                handleRelatedInformationFieldMappings(JSONKey,awardMap, awardRec);
                awardList.add(awardRec);
            }
    
            // Insert Professional_Award_Achievement__c records
            if (!awardList.isEmpty()) {
                insert awardList;
            }
        } catch (Exception e) {
            logFailedLead(JSON.serialize(professionalAwards), e,registrationNumber); // Log the failed attempt
            throw new CustomException('Error in insertProfessionalAwards method: ' + e.getMessage());
        }
    }
    
    /**
     * @description
     * ****************************************************************************************
    * Method Name : insertLastSchoolAttended
    * Created By  : Preksha Chauhan
    * Created Date: 07/10/2024
    * Description : This method processes and inserts details of the last school attended by a 
    *               given Lead into Salesforce. It performs the following tasks:
    *               - Updates the Lead's `Auris_Last_Updated_Timestamp__c` field with the current
    *                 datetime in the format 'yyyy-MM-dd:HH:mm:ss'.
    *               - Checks if the `lastSchoolAttended` object is null and handles it appropriately.
    *               - Collects school names from the provided last school attended details and queries
    *                 existing `Last_School_Attended__c` records by these school names.
    *               - Iterates over the provided last school attended data to:
    *                 - Check for duplicates based on school names.
    *                 - Create new `Last_School_Attended__c` records with the relevant school details.
    *               - Inserts the new last school attended records into Salesforce.
    *               - Logs any errors encountered and throws a `CustomException` in case of failure.
    *
    * Parameters:
    * @param lastSchoolAttended - A list of maps where each map contains details about the last school
    *                             attended, including the school name, point of contact, contact number,
    *                             email, city, state/province, and country.
    * @param leadId - The Id of the Lead to which the last school attended details are related.
    * @param registrationNumber lead registrationNumber
    ********************************************************************************************/
    public static void insertLastSchoolAttended(String JSONKey,Object lastSchoolAttended, Id leadId,String registrationNumber) {
        try {
    
            // Get the current datetime
            Datetime now = System.now();
            // Format the datetime to the desired format
            String formattedDate = now.format('yyyy-MM-dd:HH:mm:ss');
            
            // Update Lead's Auris_Last_Updated_Timestamp__c field with the formatted datetime
            Lead leadToUpdate = new Lead(Id = leadId);
            leadToUpdate.Auris_Last_Updated_Timestamp__c = formattedDate; // Store the formatted datetime as a String
            
            // Perform the update operation
            update leadToUpdate;
    
            // Check create access for Last_School_Attended__c
            if (!Schema.sObjectType.Last_School_Attended__c.isCreateable()) {
                throw new CustomException('User does not have create access to Last_School_Attended__c');
            }
    
            List<Last_School_Attended__c> schoolList = new List<Last_School_Attended__c>();
            Set<String> schoolNames = new Set<String>();
    
            // Collect all school names first
            for (Object school : (List<Object>) lastSchoolAttended) {
                Map<String, Object> schoolMap = (Map<String, Object>) school;
                if (schoolMap.containsKey('schoolName') && schoolMap.get('schoolName') != null) {
                    schoolNames.add((String) schoolMap.get('schoolName'));
                }
            }
    
            // Query the Last_School_Attended__c records by the collected school names
            Map<String, Last_School_Attended__c> existingSchoolMap = new Map<String, Last_School_Attended__c>();
            if (!schoolNames.isEmpty()) {
                for (Last_School_Attended__c existingSchool : [SELECT Id, School_Name__c FROM Last_School_Attended__c WHERE Lead__c = :leadId AND School_Name__c IN :schoolNames]) {
                    existingSchoolMap.put(existingSchool.School_Name__c, existingSchool);
                }
            }
    
            // Create Last_School_Attended__c records
            for (Object school : (List<Object>) lastSchoolAttended) {
                Map<String, Object> schoolMap = (Map<String, Object>) school;
    
                // Check if school name exists in existing records (to avoid duplicates)
                if (schoolMap.containsKey('schoolName') && schoolMap.get('schoolName') != null) {
                    String schoolName = (String) schoolMap.get('schoolName');
    
                    // Check if Last_School_Attended__c record already exists for this Lead
                    if (existingSchoolMap.containsKey(schoolName)) {
                        continue; // Skip this record since it's a duplicate
                    }
                }
    
                // Create new Last_School_Attended__c record
                Last_School_Attended__c schoolRec = new Last_School_Attended__c();
                schoolRec.Lead__c = leadId;
    
                handleRelatedInformationFieldMappings(JSONKey,schoolMap, schoolRec);
                schoolList.add(schoolRec);
            }
    
            // Insert Last_School_Attended__c records
            if (!schoolList.isEmpty()) {
                insert schoolList;
            } 
        } catch (Exception e) {
            logFailedLead(JSON.serialize(lastSchoolAttended), e,registrationNumber); // Log the failed attempt
            throw new CustomException('Error in insertLastSchoolAttended method: ' + e.getMessage());
        }
    }
        public static void handleRelatedInformationFieldMappings(
            String relatedJsonName,
            Map<String, Object> jsonData,
            SObject targetRecord
        ) {
            // Fetch mapping metadata
            Map<String, FieldMapping> jsonToFieldApiMap = new Map<String, FieldMapping>();
            for (Auris_Related_Info_Field_Mapping__mdt mapping : [
                SELECT JSON_Key__c, Label, Datatype__c
                FROM Auris_Related_Info_Field_Mapping__mdt
                WHERE Related_Records_JSON_Name__c = :relatedJsonName
            ]) {
                if (!String.isBlank(mapping.JSON_Key__c) && !String.isBlank(mapping.Label)) {
                    jsonToFieldApiMap.put(
                        mapping.JSON_Key__c,
                        new FieldMapping(mapping.Label, mapping.Datatype__c)
                    );
                }
            }
            for (String jsonKey : jsonToFieldApiMap.keySet()) {
                if (jsonData.containsKey(jsonKey) && jsonData.get(jsonKey) != null) {
                    
                    FieldMapping fieldMapping = jsonToFieldApiMap.get(jsonKey);
                    String fieldApi = fieldMapping.fieldApi;
                    String datatype = fieldMapping.datatype;
        
                    Object rawValue = jsonData.get(jsonKey);
                    Object convertedValue;
        
                    try {
                        if (rawValue == null || String.valueOf(rawValue).trim() == '') {
                            continue; // skip null/empty
                        }
        
                        if (datatype == 'String'||datatype == 'Text') {
                            convertedValue = String.valueOf(rawValue);
                        } else if (datatype == 'Date') {
                            convertedValue = Date.valueOf(String.valueOf(rawValue));
                        } else if (datatype == 'DateTime') {
                            convertedValue = Datetime.valueOf(String.valueOf(rawValue));
                        } else if (datatype == 'Boolean') {
                            convertedValue = Boolean.valueOf(String.valueOf(rawValue));
                        } else if (datatype == 'Number' || datatype == 'Decimal') {
                            convertedValue = Decimal.valueOf(String.valueOf(rawValue));
                        } else if (datatype == 'Integer') {
                            convertedValue = Integer.valueOf(String.valueOf(rawValue));
                        } else {
                            // fallback: assign raw
                            convertedValue = rawValue;
                        }
        
                        targetRecord.put(fieldApi, convertedValue);
        
                    } catch (Exception e) {
                        System.debug('Failed to map key=' + jsonKey + 
                                    ', field=' + fieldApi + 
                                    ', type=' + datatype + 
                                    ', value=' + rawValue + 
                                    ' | Error: ' + e.getMessage());
                    }
                }
            }
        }
        
        public class FieldMapping {
            public String fieldApi;
            public String datatype;
        
            public FieldMapping(String fieldApi, String datatype) {
                this.fieldApi = fieldApi;
                this.datatype = datatype;
            }
        }
    
    
    // MODIFICATION: Updated handleAdmissionForm to handle program groups*****************************
    public static void handleAdmissionForm(Map<String, Object> payload, Id leadId, String department, String typeOfForm, String registrationNumber) {
        try {
            Lead masterLead = [SELECT Id, Registration_Number__c, RecordTypeId FROM Lead WHERE Id = :leadId LIMIT 1];
            
            // Process child records
            List<Auris_Child_Form_Mapping__mdt> childMappings = [
                SELECT Label, Department__c, JSONKey__c, TypeOfForm__c
                FROM Auris_Child_Form_Mapping__mdt
                WHERE (Department__c = :department OR Department__c = null)
                AND   (TypeOfForm__c = :typeOfForm OR TypeOfForm__c = null)
            ];
    
            for (Auris_Child_Form_Mapping__mdt mapRec : childMappings) {
                if (payload.containsKey(mapRec.JSONKey__c) && payload.get(mapRec.JSONKey__c) != null) {
                    handle(
                        mapRec.JSONKey__c,
                        mapRec.Label, 
                        payload.get(mapRec.JSONKey__c), 
                        masterLead.Id, 
                        registrationNumber
                    );
                }
            }
    
        } catch (Exception e) {
            logFailedLead(JSON.serialize(payload), e, registrationNumber);
            throw new CustomException('Error in handleAdmissionForm: ' + e.getMessage());
        }
    }    

    public static void handle(String JSONKey,String methodName, Object payload, Id leadId, String registrationNumber) {
        if (String.isBlank(methodName)){
            return;
        } 

        if (methodName == 'insertParentInformation') {
            insertParentInformation(JSONKey,(List<Object>) payload, leadId, registrationNumber);
        } 
        else if (methodName == 'insertPreferredPrograms') {
            insertPreferredPrograms(JSONKey,(List<Object>) payload, leadId, registrationNumber);
        } else if (methodName == 'insertEducationalDetails') {
            insertEducationalDetails(JSONKey,payload, leadId, registrationNumber);
        } else if (methodName == 'insertLastSchoolAttended') {
            insertLastSchoolAttended(JSONKey,payload, leadId, registrationNumber);
        } else if (methodName == 'insertCollegeEducationDetails') {
            insertCollegeEducationDetails(JSONKey,(List<Object>) payload, leadId, registrationNumber);
        } else if (methodName == 'insertAcademicResults') {
            insertAcademicResults(JSONKey,(List<Object>) payload, leadId, registrationNumber);
        } else if (methodName == 'insertStandardisedTestScores') {
            insertStandardisedTestScores(JSONKey,(List<Object>) payload, leadId, registrationNumber);
        } else if (methodName == 'insertExtracurricularActivities') {
            insertExtracurricularActivities(JSONKey,(List<Object>) payload, leadId, registrationNumber);
        } else if (methodName == 'insertSiblingInformation') {
            insertSiblingInformation(JSONKey,(List<Object>) payload, leadId, registrationNumber);
        } else if (methodName == 'insertPersonalStatement') {
            insertPersonalStatement(JSONKey,(List<Object>) payload, leadId, registrationNumber);
        } else if (methodName == 'insertDocumentDetails') {
            insertDocumentDetails(JSONKey,(List<Object>) payload, leadId, registrationNumber);
        } else if (methodName == 'insertEmploymentHistory') {
            insertEmploymentHistory(JSONKey,(List<Object>) payload, leadId, registrationNumber);
        } else if (methodName == 'insertApplicationPayments') {
            insertApplicationPayments(JSONKey,(List<Object>) payload, leadId, registrationNumber);
        } else if (methodName == 'insertProfessionalAwards') {
            insertProfessionalAwards(JSONKey,(List<Object>) payload, leadId, registrationNumber);
        } else if (methodName == 'insertPreferredProgramsMasters'){
            insertPreferredProgramsMasters(JSONKey,(List<Object>) payload, leadId, registrationNumber);
        }
    }

    /**
     * @description
     * ****************************************************************************************
     * Class Name  : CustomException
     * Create By   : Preksha Chauhan
     * Create Date : 07/10/2024
     * Description : This class defines a custom exception that can be used to handle specific 
     *               errors in the Salesforce application. It extends the standard Exception 
     *               class and provides a way to throw and catch customized exceptions in 
     *               your code.
     *
     * Example Usage:
     * throw new CustomException('Error message describing the issue');
     *
     * This custom exception can be used to provide more meaningful error messages 
     * and to handle specific scenarios where standard exceptions may not be sufficient.
     ******************************************************************************************/
    public class CustomException extends Exception {}

    /**
     * @description
     * ****************************************************************************************
     * Method Name : logFailedLead
     * Create By   : Preksha Chauhan
     * Create Date : 07/10/2024
     * Description : This method logs failed lead records into the API_Log__c custom object. 
     *               It captures the error message and other relevant details whenever an 
     *               exception occurs during lead processing.
     * 
     * Parameters  : 
     * @param payload   - String payload : The JSON payload that was being processed when the exception occurred.
     * @param e  - Exception e    : The exception that was thrown during the processing of the lead.
     * @param registrationNumber  - String    : The registration number of the lead that was being processed when the exception occurred.
     ******************************************************************************************/
    public static void logFailedLead(String payload, Exception e,String registrationNumber) {
        try {

            if (!Schema.sObjectType.Lead.isUpdateable()) {
                throw new CustomException('You do not have the necessary permissions to update Lead records.');
            }
            if (!Schema.sObjectType.API_Log__c.isCreateable() || !Schema.sObjectType.API_Log__c.isAccessible()) {
                throw new CustomException('You do not have the necessary permissions to create API_Log__c records.');
            }

            API_Log__c apiLog = new API_Log__c();
            apiLog.Log_Name__c = 'saveLeadRelatedData';
            apiLog.Apex_Class_Name__c = 'saveWebTo_YourProfileData';
            apiLog.Response__c = e.getMessage();
            apiLog.Log_Type__c = 'Failed';
            apiLog.Registration_Number__c = registrationNumber;
            //system.debug('3137 ' +apiLog.Registration_Number__c);
            insert apiLog;
        } catch (Exception logException) {
            //System.debug('Error in logFailedLead: ' + logException.getMessage());
        }
    }
}