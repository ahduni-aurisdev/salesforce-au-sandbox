@RestResource(urlMapping='/saveLeadRelatedData/*')
global class AurisIntegration {
    @HttpPost
    global static void handleAurisData() {
        RestRequest request = RestContext.request;
        RestResponse response = RestContext.Response;
        String leadId = '';

        String payload = request.requestBody.toString();
        Map<String, Object> payloadMap = (Map<String, Object>) JSON.deserializeUntyped(payload);

        String department = (String) payloadMap.get('department');
        String typeOfForm = (String) payloadMap.get('typeOfForm');

        try {
            Lead newLead = createLead(payloadMap);
            insert newLead;

            if (typeOfForm.equalsIgnoreCase('registration_Form')) {
                handleRegistrationForm(payloadMap, newLead.Id);
            } else if (typeOfForm.equalsIgnoreCase('admission_Form')) {
                handleAdmissionForm(payloadMap, newLead.Id);
            }

            // Construct the response JSON
            Map<String, Object> jsonResponse = new Map<String, Object>();
            jsonResponse.put('leadId', newLead.Id);
            jsonResponse.put('url', (String) payloadMap.get('url'));
            jsonResponse.put('admissionYear', (String) payloadMap.get('admissionYear'));
            jsonResponse.put('programmeInterestedIn', (String) payloadMap.get('programmeInterestedIn'));
            jsonResponse.put('country', (String) payloadMap.get('country'));
            jsonResponse.put('state', (String) payloadMap.get('state'));
            jsonResponse.put('city', (String) payloadMap.get('city'));
            jsonResponse.put('phone', (String) payloadMap.get('phone'));
            jsonResponse.put('email', (String) payloadMap.get('email'));
            jsonResponse.put('lastName', (String) payloadMap.get('lastName'));
            jsonResponse.put('firstName', (String) payloadMap.get('firstName'));
            jsonResponse.put('typeOfForm', typeOfForm);
            jsonResponse.put('department', department);

            // Set response properties
            response.responseBody = Blob.valueOf(JSON.serialize(jsonResponse));
            response.statusCode = 200;
            response.addHeader('Content-Type', 'application/json');

        } catch (Exception e) {
            // Handle exception and log if necessary
            response.responseBody = Blob.valueOf('{"error": "' + e.getMessage() + '"}');
            response.statusCode = 500;
            response.addHeader('Content-Type', 'application/json');
        }
    }

    public static Lead createLead(Map<String, Object> payloadMap) {
        Lead newLead = new Lead();
        // Set lead fields based on payload
        newLead.FirstName = (String) payloadMap.get('firstName');
        newLead.LastName = (String) payloadMap.get('lastName');
        newLead.Email = (String) payloadMap.get('email');
        newLead.Phone = (String) payloadMap.get('phone');
        newLead.Gender__c = (String) payloadMap.get('gender');
        newLead.Date_of_Birth__c = Date.valueOf((String) payloadMap.get('dateOfBirth'));
        newLead.Country_Of_Birth__c = (String) payloadMap.get('countryOfBirth');
        newLead.Nationality__c = (String) payloadMap.get('nationality');
        newLead.Are_you_an_OCI_cardholder__c = (String) payloadMap.get('ociCardHolder');
        newLead.Aadhar_card_number__c = (String) payloadMap.get('aadharCardNumber');
        newLead.Category__c = (String) payloadMap.get('category');
        newLead.Are_you_differently_abled__c = (String) payloadMap.get('differentlyAbled');
        newLead.Street = (String) payloadMap.get('residentialAddress');
        newLead.City = (String) payloadMap.get('cityTownVillage');
        newLead.State = (String) payloadMap.get('stateUnionTerritoryProvince');
        newLead.District__c = (String) payloadMap.get('district');
        newLead.Country = (String) payloadMap.get('country');
        newLead.Pin_code_Postal_code__c = (String) payloadMap.get('pinPostalCode');
        newLead.Are_you_interested_in_student_housing__c = (String) payloadMap.get('interestedInStudentHousing');
        newLead.Number_of_family_members_in_your_home__c = Decimal.valueOf((String) payloadMap.get('numberOfFamilyMembers'));
        newLead.Is_your_sibling_studying_at_AU__c = (String) payloadMap.get('isYourSiblingStudyingAtAU');
        newLead.YouAreEligibleForFinancialAidNeed__c = (String) payloadMap.get('eligibleForFinancialAid');
        
        // Add more fields as needed
        return newLead;
    }

    public static void handleRegistrationForm(Map<String, Object> payloadMap, Id leadId) {
        // Handle registration form related objects
        insertParentInformation(payloadMap.get('Parents'), leadId);
        // Add more related records handling as needed
    }

    public static void handleAdmissionForm(Map<String, Object> payloadMap, Id leadId) {
        // Handle admission form related objects
        insertParentInformation(payloadMap.get('Parents'), leadId);
        insertPrograms(payloadMap.get('Programs'), leadId);
        insertEducationalDetails(payloadMap.get('Education'), leadId);
        insertAcademicResults(payloadMap.get('AcademicResults'), leadId);
        insertStandardisedTestScores(payloadMap.get('StandardisedTestScore'), leadId);
        insertExtracurricularActivities(payloadMap.get('Sports activities'), leadId);
        insertPersonalStatement(payloadMap.get('Personal Statement'), leadId);
        insertDocumentDetails(payloadMap.get('UploadDocuments'), leadId);
        // Add more related records handling as needed
    }

    public static void insertParentInformation(Object parentInfo, Id leadId) {
        List<Parent_Information__c> parentList = new List<Parent_Information__c>();
        for (Object parent : (List<Object>)parentInfo) {
            Map<String, Object> parentMap = (Map<String, Object>)parent;
            Parent_Information__c parentRec = new Parent_Information__c();
            parentRec.Lead__c = leadId;
            parentRec.Name = (String) parentMap.get('parentFullName');
            parentRec.Relationship__c = (String) parentMap.get('relationship');
            parentRec.Mobile__c = (String) parentMap.get('parentGuardianPhone');
            parentRec.Email__c = (String) parentMap.get('parentGuardianEmail');
            parentRec.Highest_educational_qualification__c = (String) parentMap.get('parentGuardianHighestEducationalQualification');
            parentRec.Occupation__c = (String) parentMap.get('parentGuardianOccupation');
            parentRec.Designation__c = (String) parentMap.get('parentGuardianDesignation');
            parentRec.Organisation_Name__c = (String) parentMap.get('parentGuardianOragnisationName');
            parentRec.Annual_family_income__c = (String) parentMap.get('annualFamilyIncome');
           
            // Add more fields as needed
            parentList.add(parentRec);
        }
        insert parentList;
    }

    private static void insertPrograms(Object programInfo, Id leadId) {
        List<Preferred_Program__c> programList = new List<Preferred_Program__c>();
        for (Object program : (List<Object>)programInfo) {
            Map<String, Object> programMap = (Map<String, Object>)program;
            Preferred_Program__c programRec = new Preferred_Program__c();
            programRec.Lead__c = leadId;
            programRec.Program__c = (String) programMap.get('programmeInterestedIn');
            programRec.Major__c = (String) programMap.get('major');
            programList.add(programRec);
        }
        insert programList;
    }

    public static void insertEducationalDetails(Object educationInfo, Id leadId) {
        List<Educational_Detail__c> educationList = new List<Educational_Detail__c>();
        for (Object edu : (List<Object>)educationInfo) {
            Map<String, Object> eduMap = (Map<String, Object>)edu;
            Educational_Detail__c eduRec = new Educational_Detail__c();
            eduRec.Lead__c = leadId;
            eduRec.Educational_City__c= (String) eduMap.get('city');
            eduRec.Educational_State__c = (String) eduMap.get('state');
            eduRec.Educational_Country__c = (String) eduMap.get('country');
            eduRec.School_Name__c = (String) eduMap.get('schoolName');
            eduRec.School_College_Name__c = (String) eduMap.get('schoolCollegeName');
            eduRec.Designation__c = (String) eduMap.get('designation');
            eduRec.Email__c = (String) eduMap.get('schoolCollegeEmail');
            eduRec.Contact_number__c = (String) eduMap.get('schoolCollegePhone');
            eduRec.Class__c = (String) eduMap.get('className');
            eduRec.Board__c = (String) eduMap.get('board');
            eduRec.Medium_of_instruction__c = (String) eduMap.get('mediumOfInstruction');
            eduRec.Stream__c = (String) eduMap.get('stream');
            eduRec.Year_of_completion__c = (String) eduMap.get('yearOfCompletion');
            eduRec.In_case_the_passing_year_has_a_gap_of_on__c = (String) eduMap.get('inCaseThePassingYearIs12MonthsAGo');
            
            // Add more fields as needed
            educationList.add(eduRec);
        }
        insert educationList;
    }

    public static void insertAcademicResults(Object resultsInfo, Id leadId) {
        List<Academic_Results__c> resultList = new List<Academic_Results__c>();
        for (Object result : (List<Object>)resultsInfo) {
            Map<String, Object> resultMap = (Map<String, Object>)result;
            Academic_Results__c resultRec = new Academic_Results__c();
            resultRec.Lead__c = leadId;
            resultRec.Evaluation_Type__c = (String) resultMap.get('evaluationType');
            resultRec.Class__c = (String) resultMap.get('className');
            resultRec.Subjects__c = (String) resultMap.get('subject');
            resultRec.Marks_Grade_Point_Grade_Obtained__c = Decimal.valueOf((String) resultMap.get('marksGradePointsObtain'));
            resultRec.Maximum_Marks_Grade_Point_Grade__c = Decimal.valueOf((String) resultMap.get('maximumMarksGradePoints'));
            resultRec.Percentage_CGPA__c = Decimal.valueOf((String) resultMap.get('percentage'));
            // Add more fields as needed
            resultList.add(resultRec);
        }
        insert resultList;
    }

    public static void insertStandardisedTestScores(Object testScores, Id leadId) {
        List<Standardised_Test_Score_s__c> testScoreList = new List<Standardised_Test_Score_s__c>();
        for (Object score : (List<Object>)testScores) {
            Map<String, Object> scoreMap = (Map<String, Object>)score;
            Standardised_Test_Score_s__c scoreRec = new Standardised_Test_Score_s__c();
            scoreRec.Lead__c = leadId;
            scoreRec.Test__c = (String) scoreMap.get('test');
            scoreRec.Date_of_Test__c = Date.valueOf((String) scoreMap.get('dateOfTest'));
            scoreRec.Percentile__c =  Decimal.valueOf((String) scoreMap.get('percentile'));
            scoreRec.Total_score__c =  Decimal.valueOf((String) scoreMap.get('totalScore'));
            testScoreList.add(scoreRec);
        }
        insert testScoreList;
    }

    private static void insertExtracurricularActivities(Object activities, Id leadId) {
        List<Extracurricular_activities__c> activityList = new List<Extracurricular_activities__c>();
        for (Object activity : (List<Object>)activities) {
            Map<String, Object> activityMap = (Map<String, Object>)activity;
            Extracurricular_activities__c activityRec = new Extracurricular_activities__c();
            activityRec.Lead__c = leadId;
            activityRec.Activities__c = (String) activityMap.get('activities');
            activityRec.Level_of_participation__c = (String) activityMap.get('levelOfParticipation');
            activityList.add(activityRec);
        }
        insert activityList;
    }

    private static void insertPersonalStatement(Object personalStatements, Id leadId) {
        List<Personal_Statement__c> statementList = new List<Personal_Statement__c>();
        for (Object statement : (List<Object>)personalStatements) {
            Map<String, Object> statementMap = (Map<String, Object>)statement;
            Personal_Statement__c statementRec = new Personal_Statement__c();
            statementRec.Lead__c = leadId;
            statementRec.Topic_for_the_Personal_Statement__c = (String) statementMap.get('topicForPersonalStatement');
            statementRec.Personal_Statement__c = (String) statementMap.get('personalStatementAnswer');
            statementList.add(statementRec);
        }
        insert statementList;
    }

    private static void insertDocumentDetails(Object documents, Id leadId) {
        List<Document_Detail__c> documentList = new List<Document_Detail__c>();
        for (Object document : (List<Object>)documents) {
            Map<String, Object> documentMap = (Map<String, Object>)document;
            Document_Detail__c documentRec = new Document_Detail__c();
            documentRec.Lead__c = leadId;
            documentRec.Document_Name__c = (String) documentMap.get('documentName');
            documentRec.Document_Type__c = (String) documentMap.get('documentType');
            documentRec.Document_URL__c = (String) documentMap.get('documentURL');
            // Add more fields as needed
            documentList.add(documentRec);
        }
        insert documentList;
    }
}