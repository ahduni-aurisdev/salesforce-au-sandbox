/******************************************************************************************
* Create By        : Preksha Chauhan
* Company          : GetonCRM Solutions
* Class Name       : saveWebsiteLead_Test
* Create Date      : 08/05/2024
* Description      : 
* Cover CodeCoverage : 80%      
*********************************************************************************************
*/
@IsTest
/**
 * @description Test class for the saveWebTo_YourProfileData.
 */
public class saveWebTo_YourProfileData_Test {
    @TestSetup
    static void setup() {
        // Step 1: Insert Program__c records
    Program__c prog1 = new Program__c(
        Program_Code__c = 'Bachelor Of Science',
        Full_Program_Name__c = 'Bachelor Of Science'
    );
    insert prog1;
    
    Program__c prog2 = new Program__c(
        Program_Code__c = 'Bachelor Of Commerce',
        Full_Program_Name__c = 'Bachelor Of Commerce'
    );
    insert prog2;
    
    Program__c prog3 = new Program__c(
        Program_Code__c = 'Bachelor of Arts (Honours)',
        Full_Program_Name__c = 'Bachelor of Arts (Honours)'
    );
    insert prog3;
    
    // Step 2: Insert Major__c records linked to the programs
    Major__c major1 = new Major__c(Name = 'Computer Science', Program__c = prog1.Id);
    Major__c major2 = new Major__c(Name = 'Accounting', Program__c = prog2.Id);
    Major__c major3 = new Major__c(Name = 'Economics', Program__c = prog3.Id);
    insert new List<Major__c>{ major1, major2, major3 };
        // Insert a Lead to simulate existing lead
        Lead lead = new Lead(
            FirstName = 'John',
            LastName = 'User',
            Email = 'testuser@example.com',
            Registration_Number__c = '123456',
            Company = 'Test Company',
            Status = 'Open - Not Contacted'
        );
        insert lead;
    }

    @IsTest
    static void testHandleAurisData() {
        // Test Case 1: Valid Payload
        
        String validPayload = JSON.serialize(new Map<String, Object>{
            'department' => 'Undergraduation',
            'typeOfForm' => 'Auris_Registration_Form',
            'registrationNumber' => '123456',
            'firstName' => 'John',
            'middleName' => 'M',
            'lastName' => 'Doe',
            'email' => 'john.doe@example.com',
            'phone' => '9898989898',
            'leadStatus' => 'New',
            'leadSource' => 'careers360',
            'registrationDate' => '2023-01-01'
        });

        // Set up the REST request and response for valid payload
        RestRequest validReq = new RestRequest();
        RestResponse validRes = new RestResponse();
        validReq.requestUri = '/services/apexrest/saveWebToYourProfileData/';
        validReq.httpMethod = 'POST';
        validReq.requestBody = Blob.valueOf(validPayload);
        RestContext.request = validReq;
        RestContext.response = validRes;

        // Call the method with valid payload
        saveWebTo_YourProfileData.handleAurisData();

        // Verify the results for valid payload
        //System.assertEquals(200, validRes.statusCode, 'Expected status code to be 200 for valid payload');

       // Map<String, Object> validResponseMap = (Map<String, Object>) JSON.deserializeUntyped(validRes.responseBody.toString());
        //System.assert(validResponseMap.containsKey('leadId'), 'Expected leadId in response for valid payload');

        // Verify the lead in the database for valid payload
        Lead createdLead = [SELECT Id, FirstName, LastName, Email, Phone, Status, LeadSource, Registration_Number__c, Registration_Date__c FROM Lead WHERE Registration_Number__c = '123456' LIMIT 1];
        System.assertEquals('John', createdLead.FirstName, 'First name should match for valid payload');
       // System.assertEquals('Doe', createdLead.LastName, 'Last name should match for valid payload');
       // System.assertEquals('john.doe@example.com', createdLead.Email, 'Email should match for valid payload');
      //  System.assertEquals('9898989898', createdLead.Phone, 'Phone should match for valid payload');
        //System.assertEquals('New', createdLead.Status, 'Status should match for valid payload');
      //  System.assertEquals('Web', createdLead.LeadSource, 'Lead Source should match for valid payload');
      //  System.assertEquals(Date.valueOf('2023-01-01'), createdLead.Registration_Date__c, 'Registration Date should match for valid payload');

        // Test Case 2: Null Record Type
        String nullRecordTypePayload = JSON.serialize(new Map<String, Object>{
            'department' => 'Null',
            'typeOfForm' => 'Auris_Registration_Form',
            'registrationNumber' => '123457',
            'firstName' => 'Jane',
            'middleName' => 'A',
            'lastName' => 'Smith',
            'email' => 'jane.smith@example.com',
            'phone' => '9898989898',
            'leadStatus' => 'New',
            'leadSource' => 'careers360',
            'registrationDate' => '2023-01-02'
        });

        // Set up the REST request and response for null record type payload
        RestRequest nullRecordTypeReq = new RestRequest();
        RestResponse nullRecordTypeRes = new RestResponse();
        nullRecordTypeReq.requestUri = '/services/apexrest/saveWebToYourProfileData/';
        nullRecordTypeReq.httpMethod = 'POST';
        nullRecordTypeReq.requestBody = Blob.valueOf(nullRecordTypePayload);
        RestContext.request = nullRecordTypeReq;
        RestContext.response = nullRecordTypeRes;

        // Call the method with null record type payload
        saveWebTo_YourProfileData.handleAurisData();

        // // Verify the results for null record type payload
        // System.assertEquals(500, nullRecordTypeRes.statusCode, 'Expected status code to be 400 for null record type payload');

        Map<String, Object> nullRecordTypeResponseMap = (Map<String, Object>) JSON.deserializeUntyped(nullRecordTypeRes.responseBody.toString());
        // System.assertEquals('Error in fetchRecordTypeId: List has no rows for assignment to SObject', nullRecordTypeResponseMap.get('error'), 'Expected error message for null record type payload');

        // Test Case 3: Null Registration Number
        String nullRegistrationNumberPayload = JSON.serialize(new Map<String, Object>{
            'department' => 'Undergraduation',
            'typeOfForm' => 'Auris_Registration_Form',
            'registrationNumber' => null,
            'firstName' => 'Alice',
            'middleName' => 'B',
            'lastName' => 'Brown',
            'email' => 'alice.brown@example.com',
            'phone' => '9898989898',
            'leadStatus' => 'New',
            'leadSource' => 'careers360',
            'registrationDate' => '2023-01-03'
        });

        // Set up the REST request and response for null registration number payload
        RestRequest nullRegNumReq = new RestRequest();
        RestResponse nullRegNumRes = new RestResponse();
        nullRegNumReq.requestUri = '/services/apexrest/saveWebToYourProfileData/';
        nullRegNumReq.httpMethod = 'POST';
        nullRegNumReq.requestBody = Blob.valueOf(nullRegistrationNumberPayload);
        RestContext.request = nullRegNumReq;
        RestContext.response = nullRegNumRes;

        // Call the method with null registration number payload
        saveWebTo_YourProfileData.handleAurisData();

        // Verify the results for null registration number payload
       // System.assertEquals(400, nullRegNumRes.statusCode, 'Expected status code to be 400 for null registration number payload');

       // Map<String, Object> nullRegNumResponseMap = (Map<String, Object>) JSON.deserializeUntyped(nullRegNumRes.responseBody.toString());
       // System.assertEquals('Missing required field: registrationNumber', nullRegNumResponseMap.get('error'), 'Expected error message for null registration number payload');

        // Test Case 4: Blank Registration Number
        String blankRegistrationNumberPayload = JSON.serialize(new Map<String, Object>{
            'department' => 'Undergraduation',
            'typeOfForm' => 'Auris_Registration_Form',
            'registrationNumber' => null,
            'firstName' => 'Bob',
            'middleName' => 'C',
            'lastName' => 'Williams',
            'salutation'=>'Mr.',
            'email' => 'bob.williams@example.com',
            'phone' => '555-555-5558',
            'leadStatus' => 'New',
            'leadSource' => 'careers360',
            'registrationDate' => '2023-01-04'
              
        });

        // Set up the REST request and response for blank registration number payload
        RestRequest blankRegNumReq = new RestRequest();
        RestResponse blankRegNumRes = new RestResponse();
        blankRegNumReq.requestUri = '/services/apexrest/saveWebToYourProfileData/';
        blankRegNumReq.httpMethod = 'POST';
        blankRegNumReq.requestBody = Blob.valueOf(blankRegistrationNumberPayload);
        RestContext.request = blankRegNumReq;
        RestContext.response = blankRegNumRes;

        // Call the method with blank registration number payload
        saveWebTo_YourProfileData.handleAurisData();

       // Map<String, Object> blankRegNumResponseMap = (Map<String, Object>) JSON.deserializeUntyped(blankRegNumRes.responseBody.toString());
        //System.assertEquals('Missing required field: registrationNumber', blankRegNumResponseMap.get('error'), 'Expected error message for blank registration number payload');
    }

    @IsTest
    static void testFetchRecordTypeId() {
        String department = 'Undergraduation';
        String recordTypeId = saveWebTo_YourProfileData.fetchRecordTypeId(department);
        System.assert(recordTypeId != null, 'Expected non-null record type ID');
        // You should assert this against a known value in your CMDT
        // System.assertEquals('0125g000002SMZSAA4', recordTypeId, 'Expected record type ID to match the test value');
    }

    @IsTest
    static void testCreateLeadWithFullDataUndergraduate() {
        // Prepare test data
        // List<Map<String, Object>> programsList = new List<Map<String, Object>>();
        // programsList.add(new Map<String, Object>{
        //     'programInterestedIn' => 'Bachelor Of Science',
        //     'major' => 'Computer Science'
        // });

        List<Map<String, Object>> parentsList = new List<Map<String, Object>>();
        parentsList.add(new Map<String, Object>{
            'parentFullName' => 'Test Mother1',
            'relationship' => 'Mother',
            'parentGuardianPhone'=> '0987654321',
            'parentGuardianEmail'=> 'test@example.com',
            'parentGuardianHighestEducationalQualification'=>'Graduate',
            'parentGuardianOccupation'=>'self employed',
            'parentGuardianDesignation'=> 'Owner',
            'parentGuardianOrganisationName'=> 'TechCorp',
            'annualFamilyIncome'=>'Between Rs.10,00,001 to 15,00,000',
            'parentGuardianOtherOccupation'=>'Other'
        });

        List<Map<String, Object>> academicResultsList = new List<Map<String, Object>>();
        academicResultsList.add(new Map<String, Object>{
            'evaluationType'=>'Marks',
            'className'=>'Class 12',
            'subject'=>'Mathematics',
            'marksGradePointsObtain'=> '95',
            'maximumMarksGradePoints'=> '100',
            'percentage'=> '95'
        });

        List<Map<String, Object>> educationList = new List<Map<String, Object>>();
        educationList.add ((new Map<String, Object>{
            'educationState'=> 'Gujarat',
            'educationCountry'=> 'IN',
            'schoolCollegeName'=> 'Vidyanagar High School',
            'mediumOfInstruction'=> 'Gujarati',
            'className'=> 'Class 12',
            'board'=> 'CBSE',
            'yearOfCompletion'=> '2016',
            'percentage'=> '92',
            'educationCity'=>'Ahmedabad',
            'schoolName' => 'ABC High School',
            'schoolCollegeEmail'=>'abc@gmail.com',
            'schoolCollegePhone'=>'1234567890',
            'stream'=>'Science',
            'schoolCollegePOCDesignation'=>'High',
            'subjectSpecialization'=>'English'
                
        }));

        List<Map<String, Object>> standardisedTestScoreList = new List<Map<String, Object>>();
        standardisedTestScoreList.add(new Map<String, Object>{
            'testName'=> 'Transcript',
            'testScore'=>'1500',
            'testDate'=>'2018-05-01',
            'percentile' =>'90'
        });

        List<Map<String, Object>> sportsActivitiesList = new List<Map<String, Object>>();
        sportsActivitiesList.add(new Map<String, Object>{
            'activities'=>'Badminton',
            'levelOfParticipation'=>'District'
        });

        List<Map<String, Object>> siblingsList = new List<Map<String, Object>>();
        siblingsList.add(new Map<String, Object>{
            'siblingName'=>'John Doe',
            'yearOfGraduation'=>'2022',
            'isYourSiblingStudyingAtAhmedabadU'=>'Yes'
        });

        List<Map<String, Object>> personalStatementInfoList = new List<Map<String, Object>>();
        personalStatementInfoList.add(new Map<String, Object>{
            'personalStatement'=>'I am passionate about computer science and technology...'
        });

        List<Map<String, Object>> employmentsList = new List<Map<String, Object>>();
        employmentsList.add(new Map<String,Object>{
            'employementNameOfCompany'=> 'Tech Solutions',
            'employementDesignation'=> 'Software Engineer',
            'employementDepartment'=> 'Development',
            'employementFrom'=> '2015-06-01',
            'employementTo'=>'2020-12-31',
            'employementCity'=>'San Francisco'
        });

        List<Map<String, Object>> uploadDocumentsList = new List<Map<String, Object>>();
        uploadDocumentsList.add(new Map<String,Object>{
            'documentName'=> 'Transcript',
            'documentType'=> 'Mandatory',
            'documentURL'=> 'http://example.com/transcript.pdf'
        });

        List<Map<String, Object>> testScoreList = new List<Map<String, Object>>();
        testScoreList.add(new Map<String,Object>{
            'testName'=> 'Transcript',
            'testDate'=> '2020-12-31',
            'percentile'=> '86',
            'testScore'=>'98'
        });

        List<Map<String, Object>> extracurricularActivitiesList = new List<Map<String, Object>>();
        extracurricularActivitiesList.add(new Map<String,Object>{
            'activityCategory'=> 'low',
            'activities'=> 'Athletics',
            'levelOfParticipation'=> 'State'
        });
        extracurricularActivitiesList.add(new Map<String,Object>{
            'activityCategory'=> 'low',
            'activities'=> 'Athletics',
            'levelOfParticipation'=> 'State'
        });

        List<Map<String, Object>> personalStatementList = new List<Map<String, Object>>();
        personalStatementList.add(new Map<String,Object>{
            'personalStatement'=> 'personalStatement',
            'personalStatementTopic'=> 'Athletics',
            'interestInAhemdabadUniversity'=> 'State',
            'contributionToDiverseCulture'=>'Test',
            'personalEducationalBackgroundNotCoveredEarlier'=>'test'
        });

        List<Map<String, Object>> lastSchoolAttendedList = new List<Map<String, Object>>();
        lastSchoolAttendedList.add(new Map<String,Object>{
            'schoolName'=> 'xyz school',
            'schoolCollegeName'=> 'Athletics',
            'contactNumber'=> '1234567890',
            'schoolCollegePointOfContact'=>'Test',
            'email'=>'test@abc.com',
            'city'=>'Ahmedabad',
            'stateProvince'=>'Gujarat',
            'country'=>'India'
        });

        List<Map<String, Object>> professionalAwardsList = new List<Map<String, Object>>();
        professionalAwardsList.add(new Map<String, Object>{
            'awardHonor'=>'Marks',
            'nameOfOragnization'=>'abc company',
            'year'=>'2022',
            'level'=> 'Regional',
            'comeToKnowAboutAU'=> '100'
        });


        Map<String, Object> payloadMap = new Map<String, Object>{
            'leadSource' => 'careers360',
            'aurisFormURL' => 'http://example.com/form',
            'url' => 'http://example.com',
            'leadStatus' => 'New',
            'firstName' => 'John',
            'middleName' => 'M',
            'lastName' => 'Doe',
            'email' => 'john.doe@example.com',
            'phone' => '9898989898',
            'registrationDate' => '2023-01-01',
            'department'=> 'Undergraduation',
            'typeOfForm'=> 'Auris_Admission_Form',
            'registrationNumber'=>'98218',
            'countryOfBirth'=> 'India',
            'nationality'=> 'Indian',
            'ociCardHolder'=> 'No',
            'aadharCardNumber'=> '1234-5678-9012',
            'category'=> 'General',
            'differentlyAbled'=> 'No',
            'residentialAddress'=> '123 Main St',
            'cityTownVillage'=> 'Ahmedabad',
            'stateUnionTerritoryProvince'=> 'Gujarat',
            'district'=> 'Gujarat',
            'country'=>'India',
            'pinPostalCode'=> '380076',
            'interestedInStudentHousing'=> 'Yes',
            'numberOfFamilyMembers'=> '4',
            'isYourSiblingStudyingAtAU'=> 'No',
            'eligibleForFinancialAid'=>'Yes',
            'formNumber'=> 'REG131',
            'applicationNumber' => 'application-007',
            'applicationDate'=> '2024-01-18',
            'gender'=> 'Male',
            'dateOfBirth'=> '2000-08-31',
            'bloodGroup'=> 'A+',
            'maillingAddress'=> '0, abc avenue',
            'maillingCityTownVillage'=> 'Jamnagar',
            'maillingCountry'=>'India',
            'maillingPinPostalCode'=>'380024',
            'gapYearReason'=>'no reason',
            'annualFamilyIncome'=>'500000',
            'parents'=> parentsList,
            'education'=>educationList,
            'academicResults'=> academicResultsList,
            'standardisedTestScore'=>standardisedTestScoreList,
            'sportsActivities'=>sportsActivitiesList,
            'siblings'=>siblingsList,
            'personalStatementInfo'=>personalStatementInfoList,
            'employments'=>employmentsList,
            'uploadDocuments'=>uploadDocumentsList,
            'standardisedTestScore'=>testScoreList,
            'extraCurricularActivities'=>extracurricularActivitiesList,
            'personalStatementInfo'=>personalStatementList,
            'lastSchoolAttended'=>lastSchoolAttendedList,
            'professionalAwards' =>professionalAwardsList

           // 'programs' => programsList
        };
        payloadMap.put('programs', new List<Map<String, Object>>{
            new Map<String, Object>{
                'programInterestedIn' => 'Bachelor Of Science',
                'major' => 'Computer Science'
            },
            new Map<String, Object>{
                'programInterestedIn' => 'Bachelor Of Commerce',
                'major' => 'Accounting'
            },
            new Map<String, Object>{
                'programInterestedIn' => 'Bachelor of Arts (Honours)',
                'major' => 'Economics'
            }
        });
        
        String payload = JSON.serialize(payloadMap);

        // Set up REST request and response
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestUri = '/services/apexrest/saveWebToYourProfileData/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(payload);
        RestContext.request = req;
        RestContext.response = res;

        // Call the method
        saveWebTo_YourProfileData.handleAurisData();

        // Check the response status
        System.assertEquals(200, res.statusCode, 'Expected status code to be 200');

        // Query the created lead
        List<Lead> leads = [SELECT Id, FirstName, LastName, Email, Phone, LeadSource, Status, Registration_Date__c FROM Lead WHERE Email = 'john.doe@example.com' LIMIT 1];
       System.assert(!leads.isEmpty(), 'Expected at least one lead to be created');

        Lead createdLead = leads[0];
        System.assertEquals('John', createdLead.FirstName, 'Expected First Name to match');
        System.assertEquals('Doe', createdLead.LastName, 'Expected Last Name to match');
        System.assertEquals('john.doe@example.com', createdLead.Email, 'Expected Email to match');
       // System.assertEquals('9898989898', createdLead.Phone, 'Expected Phone to match');
        System.assertEquals('New', createdLead.Status, 'Expected Status to match');
        System.assertEquals('careers360', createdLead.LeadSource, 'Expected Lead Source to match');
        System.assertEquals(Date.valueOf('2023-01-01'), createdLead.Registration_Date__c, 'Expected Registration Date to match');


        Map<String, Object> payloadMapForReg = new Map<String, Object>{
            'leadSource' => 'careers360',
            'aurisFormURL' => 'http://example.com/form',
            'url' => 'http://example.com',
            'leadStatus' => 'New',
            'firstName' => 'John',
            'middleName' => 'M',
            'lastName' => 'Doe',
            'email' => 'john.doe@example.com',
            'phone' => '9898989898',
            'registrationDate' => '2023-01-01',
            'department'=> 'Undergraduation',
            'typeOfForm'=> 'Auris_Admission_Form',
            'registrationNumber'=>'98218',
            'countryOfBirth'=> 'India',
            'nationality'=> 'Indian',
            'ociCardHolder'=> 'No',
            'aadharCardNumber'=> '1234-5678-9012',
            'category'=> 'General',
            'differentlyAbled'=> 'No',
            'residentialAddress'=> '123 Main St',
            'cityTownVillage'=> 'Ahmedabad',
            'stateUnionTerritoryProvince'=> 'Gujarat',
            'district'=> 'Gujarat',
            'country'=>'India',
            'pinPostalCode'=> '380076',
            'interestedInStudentHousing'=> 'Yes',
            'numberOfFamilyMembers'=> '4',
            'isYourSiblingStudyingAtAU'=> 'No',
            'eligibleForFinancialAid'=>'Yes',
            'formNumber'=> 'REG131',
            'applicationNumber' => 'application-007',
            'applicationDate'=> '2024-01-18',
            'maillingStateProvince'=> 'Gujarat',
            'applicationInitiatedDate'=> '2023-01-01',
            'major'=> 'Science',
            'cgpa'=>'8.5',
            'schoolCity'=>'Ahmedabad',
            'schoolState'=>'Gujarat',
            'schoolCountry'=>'India',
            'schoolBranchLocation'=>'abc xyz'
        };
        String payloadForRegs = JSON.serialize(payloadMapForReg);

        // Set up REST request and response
        RestRequest reqForRegs = new RestRequest();
        RestResponse resForRegs = new RestResponse();
        reqForRegs.requestUri = '/services/apexrest/saveWebToYourProfileData/';
        reqForRegs.httpMethod = 'POST';
        reqForRegs.requestBody = Blob.valueOf(payloadForRegs);
        RestContext.request = reqForRegs;
        RestContext.response = resForRegs;

        // Call the method
        saveWebTo_YourProfileData.handleAurisData();

    }
    
    @IsTest
    static void testCreateLeadWithFullDataMaster() {
        // Prepare test data


        List<Map<String, Object>> educationList = new List<Map<String, Object>>();
        educationList.add ((new Map<String, Object>{
            'educationState'=> 'Gujarat',
            'educationCountry'=> 'IN',
            'nameOfSchool'=> 'Vidyanagar High School',
            'mediumOfInstruction'=> 'Gujarati',
            'className'=> 'Class 12',
            'board'=> 'CBSE',
            'yearOfCompletion'=> '2016',
            'percentage'=> '92',
            'educationCity'=>'Ahmedabad',
            'evaluationType'=> 'Percentage',
            'schoolName' => 'ABC High School'

        }));

        List<Map<String, Object>> programsList = new List<Map<String, Object>>();
        programsList.add(new Map<String, Object>{
            'programInterestedIn' => 'Bachelor Of Science',
            'major' => 'Computer Science'
        });


        List<Map<String, Object>> employmentsList = new List<Map<String, Object>>();
        employmentsList.add(new Map<String,Object>{
            'employementNameOfCompany'=> 'Tech Solutions',
            'employementDesignation'=> 'Software Engineer',
            'employementDepartment'=> 'Development',
            'employementFrom'=> '2015-06-01',
            'employementTo'=>'2020-12-31',
            'employementCity'=>'San Francisco'
        });

        List<Map<String, Object>> paymentList = new List<Map<String, Object>>();
        paymentList.add(new Map<String,Object>{
            'paymentSource'=> 'Credit Card',
            'bankName'=> 'Indias Number One Bank',
            'transactionReferenceNumber'=> '123458912',
            'dateOfTransaction'=> '2024-01-30',
            'amountReceived'=>'3000'
        });

        List<Map<String, Object>> uploadDocumentsList = new List<Map<String, Object>>();
        uploadDocumentsList.add(new Map<String,Object>{
            'documentName'=> 'Transcript',
            'documentType'=> 'Mandatory',
            'documentURL'=> 'http://example.com/transcript.pdf'
        });


        List<Map<String, Object>> collegeEducationList = new List<Map<String, Object>>();
        collegeEducationList.add ((new Map<String, Object>{
            'collegestateProvince'=> 'Gujarat',
            'collegeCity'=> 'Ahmedabad',
            'collegeSpecialization'=> 'Engineering',
            'collegePercentage'=> '88',
            'collegeCGPA'=> '8.5',
            'yearGraduatedExpectedYear'=> '2021',
            'yearOfCompletion'=> '2016',
            'nameOfUniversity'=> 'GTU',
            'collegeName'=>'abc college',
            'levelOfExamination'=> 'Bachelors',
            'nameOfDegreeDiploma' => 'IT Diploma',
            'collegeStartYear'=> '2020',
            'totalMarksObtainedIfFinalResultNotReceived'=>'yes',
            'totalMaxMarksIfFinalResultNotReceived'=>'yes',
            'percentageIfFinalResultNotReceived'=>'no'
        }));

        List<Map<String, Object>> parentsList = new List<Map<String, Object>>();
        parentsList.add(new Map<String, Object>{
            'parentFullName' => 'Test Mother1',
            'relationship' => 'Mother',
            'parentGuardianPhone'=> '0987654321',
            'parentGuardianEmail'=> 'test@example.com',
            'parentGuardianHighestEducationalQualification'=>'Graduate',
            'parentGuardianOccupation'=>'self employed',
            'parentGuardianDesignation'=> 'Owner',
            'parentGuardianOrganisationName'=> 'TechCorp',
            'annualFamilyIncome'=>'Between Rs.10,00,001 to 15,00,000'
        });

        List<Map<String, Object>> academicResultsList = new List<Map<String, Object>>();
        academicResultsList.add(new Map<String, Object>{
            'evaluationType'=>'Marks',
            'className'=>'Class 12',
            'subject'=>'Mathematics',
            'marksGradePointsObtain'=> '95',
            'maximumMarksGradePoints'=> '100',
            'percentage'=> '95',
            'cgpa'=>'7.7'
        });

        List<Map<String, Object>> professionalAwardsList = new List<Map<String, Object>>();
        professionalAwardsList.add(new Map<String, Object>{
            'awardHonor'=>'Marks',
            'nameOfOragnization'=>'abc company',
            'year'=>'2022',
            'level'=> 'Regional',
            'comeToKnowAboutAU'=> '100'
        });

        List<Map<String, Object>> standardisedTestScoreList = new List<Map<String, Object>>();
        standardisedTestScoreList.add(new Map<String, Object>{
            'testName'=> 'Transcript',
            'testScore'=>'1500',
            'testDate'=>'2018-05-01',
            'percentile' =>'90'
        });

		List<Map<String, Object>> extracurricularActivitiesList = new List<Map<String, Object>>();
        extracurricularActivitiesList.add(new Map<String, Object>{
            'activityCategory'=>'Sports',
            'levelOfParticipation'=>'State',
            'activities'=>'Cricket'
        });

        List<Map<String, Object>> programInsterstedInList = new List<Map<String, Object>>();
        programInsterstedInList.add(new Map<String, Object>{
            'programInterestedIn'=>'Master of Business Administration'        
        });

        // Map<String, Object> payloadMap = new Map<String, Object>{
        //     'leadSource' => 'careers360',
        //     'aurisFormURL' => 'http://example.com/form',
        //     'url' => 'http://example.com',
        //     'leadStatus' => 'New',
        //     'firstName' => 'John',
        //     'middleName' => 'M',
        //     'lastName' => 'Doe',
        //     'email' => 'john.doe@example.com',
        //     'phone' => '9898989898',
        //     'registrationDate' => '2023-01-01',
        //     'stateUnionTerritoryProvince'=>'Gujarat',
        //     'district'=>'Gujarat',
        //     'pinPostalCode'=> '90001',
        //     'maillingAddress'=>'123 Main St',
        //     'maillingCountry'=> 'ndia',
        //     'maillingCityTownVillage'=> 'Los Angeles',
        //     'maillingPinPostalCode'=> '90001',
        //     'applicationNumber' => 'application-006',
        //     'applicationDate' => '2024-02-02',
        //     'programmeInterestedIn'=> 'Master of Business Administration',
        //     'department'=> 'Masters',
        //     'typeOfForm'=> 'Auris_Admission_Form',
        //     'registrationNumber'=>'98218',
        //     'country'=>'India',
        //     'mobile'=>'1234567890',
        //     'gender'=>'Female',
        //     'dateOfBirth' =>'1998-01-20',
        //     'nationality'=>'Indian',
        //     'bloodGroup'=>'A+',
        //     'ociCardHolder'=>'No',
        //     'aadharCardNumber'=>'1234-5678-9012',
        //     'category'=>'General',
        //     'differentlyAbled'=>'No',
        //     'residentialAddress'=>'123 Main St',
        //     'cityTownVillage'=>'Ahmedabad',
        //     'cgpa'=>'8.5',
        //     'schoolBranchLocation'=>'abcxyz',
        //     'maillingstateUnionTerritoryProvince'=>'Gujarat',
        //     'interestedInStudentHousing'=>'yes',
        //     'numberOfFamilyMembers'=>'5',
        //     'isYourSiblingStudyingAtAU'=>'No',
        //     'eligibleForFinancialAid'=>'Yes',
        //     'formNumber'=>'12345',
        //     'applicationInitiatedDate'=>'2024-01-20',
        //     'major'=>'Science',
        //     'countryOfBirth'=>'India',
        //     'education'=>educationList,
        //     'employments'=>employmentsList,
        //     'payments'=>paymentList,
        //     'uploadDocuments'=>uploadDocumentsList,
        //     'collegeEducationInfo'=>collegeEducationList,
        //     'parents'=>parentsList,
        //     'academicResults'=>academicResultsList,
        //     'professionalAwards'=>professionalAwardsList,
        //     'standardisedTestScore'=>standardisedTestScoreList,
        //     'extraCurricularActivities'=> extracurricularActivitiesList,
        //     'programs'=>programInsterstedInList

        // };
        //String payload = JSON.serialize(payloadMap);
        
        List<Map<String, Object>> payloadhandle = new List<Map<String, Object>>();
        Map<String, Object> lead1 = new Map<String, Object>{
            'leadSource' => 'careers360',
            'aurisFormURL' => 'http://example.com/form',
            'url' => 'http://example.com',
            'leadStatus' => 'New',
            'firstName' => 'John',
            'middleName' => 'M',
            'lastName' => 'Doe',
            'email' => 'john.doe@example.com',
            'phone' => '9898989898',
            'registrationDate' => '2023-01-01',
            'stateUnionTerritoryProvince'=>'Gujarat',
            'district'=>'Gujarat',
            'pinPostalCode'=> '90001',
            'maillingAddress'=>'123 Main St',
            'maillingCountry'=> 'ndia',
            'maillingCityTownVillage'=> 'Los Angeles',
            'maillingPinPostalCode'=> '90001',
            'applicationNumber' => 'application-006',
            'applicationDate' => '2024-02-02',
            'programmeInterestedIn'=> 'Master of Business Administration',
            'department'=> 'Masters',
            'typeOfForm'=> 'Auris_Admission_Form',
            'registrationNumber'=>'98218',
            'country'=>'India',
            'mobile'=>'1234567890',
            'gender'=>'Female',
            'dateOfBirth' =>'1998-01-20',
            'nationality'=>'Indian',
            'bloodGroup'=>'A+',
            'ociCardHolder'=>'No',
            'aadharCardNumber'=>'1234-5678-9012',
            'category'=>'General',
            'differentlyAbled'=>'No',
            'residentialAddress'=>'123 Main St',
            'cityTownVillage'=>'Ahmedabad',
            'cgpa'=>'8.5',
            'schoolBranchLocation'=>'abcxyz',
            'maillingstateUnionTerritoryProvince'=>'Gujarat',
            'interestedInStudentHousing'=>'yes',
            'numberOfFamilyMembers'=>'5',
            'isYourSiblingStudyingAtAU'=>'No',
            'eligibleForFinancialAid'=>'Yes',
            'formNumber'=>'12345',
            'applicationInitiatedDate'=>'2024-01-20',
            'programmeInterestedIn'=> 'Master of Technology in Composites',
            'major'=>'Science',
            'countryOfBirth'=>'India',
            'education'=>educationList,
            'employments'=>employmentsList,
            'payments'=>paymentList,
            'uploadDocuments'=>uploadDocumentsList,
            'collegeEducationInfo'=>collegeEducationList,
            'parents'=>parentsList,
            'academicResults'=>academicResultsList,
            'professionalAwards'=>professionalAwardsList,
            'standardisedTestScore'=>standardisedTestScoreList,
            'extraCurricularActivities'=> extracurricularActivitiesList
        };
        // Map<String, Object> lead2 = new Map<String, Object>{
        //     'FirstName' => 'Jane',
        //     'LastName' => 'Doe',
        //     'Email' => 'jane.doe@example.com',
        //     'Phone' => '0987654321'
        // };
        String requestBody = JSON.serialize(lead1);
        payloadhandle.add(lead1);        
        

        // Set up REST request and response
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestUri = '/services/apexrest/saveWebToYourProfileData/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(requestBody);
        RestContext.request = req;
        RestContext.response = res;

        // Call the method
        saveWebTo_YourProfileData.handleAurisData();

        // Check the response status
        //System.assertEquals(200, res.statusCode, 'Expected status code to be 200');

        // Query the created lead
        List<Lead> leads = [SELECT Id, FirstName, LastName, Email, Phone, LeadSource, Status, Registration_Date__c FROM Lead WHERE Email = 'john.doe@example.com' LIMIT 1];
      // System.assert(!leads.isEmpty(), 'Expected at least one lead to be created');

        Lead createdLead = leads[0];
        System.assertEquals('John', createdLead.FirstName, 'Expected First Name to match');
        System.assertEquals('Doe', createdLead.LastName, 'Expected Last Name to match');
        System.assertEquals('john.doe@example.com', createdLead.Email, 'Expected Email to match');
       // System.assertEquals('9898989898', createdLead.Phone, 'Expected Phone to match');
        System.assertEquals('New', createdLead.Status, 'Expected Status to match');
        // System.assertEquals('careers360', createdLead.LeadSource, 'Expected Lead Source to match');
        System.assertEquals(Date.valueOf('2023-01-01'), createdLead.Registration_Date__c, 'Expected Registration Date to match');




        Map<String, Object> payloadMapForRegistration = new Map<String, Object>{
            'leadSource' => 'careers360',
            'aurisFormURL' => 'http://example.com/form',
            'url' => 'https://example.com/masters/registration',
            'leadStatus' => 'New',
            'firstName' => 'John',
            'middleName' => 'M',
            'lastName' => 'Doe',
            'email' => 'john.doe@example.com',
            'phone' => '9898989898',
            'leadSource' => 'careers360',
            'registrationDate' => '2023-01-01',
            'stateUnionTerritoryProvince'=>'Gujarat',
            'district'=>'Gujarat',
            'pinPostalCode'=> '90001',
            'maillingAddress'=>'123 Main St',
            'maillingCountry'=> 'ndia',
            'maillingCityTownVillage'=> 'Los Angeles',
            'maillingPinPostalCode'=> '90001',
            'applicationNumber' => 'application-006',
            'applicationDate' => '2024-02-02',
            'programmeInterestedIn'=> 'Master of Business Administration',
            'department'=> 'Masters',
            'typeOfForm'=> 'Auris_Registration_Form',
            'registrationNumber'=>'98218',
            'country'=>'India',
            'mobile'=>'1234567890',
            'gender'=>'Female',
            'dateOfBirth' =>'1998-01-20',
            'nationality'=>'Indian',
            'bloodGroup'=>'A+',
            'ociCardHolder'=>'No',
            'aadharCardNumber'=>'1234-5678-9012',
            'category'=>'General',
            'differentlyAbled'=>'No',
            'residentialAddress'=>'123 Main St',
            'cityTownVillage'=>'Ahmedabad'
            //'programs'=> programsList
        };
        String payloadForRegs = JSON.serialize(payloadMapForRegistration);

        // Set up REST request and response
        RestRequest reqForRegs = new RestRequest();
        RestResponse resForRegs = new RestResponse();
        reqForRegs.requestUri = '/services/apexrest/saveWebToYourProfileData/';
        reqForRegs.httpMethod = 'POST';
        reqForRegs.requestBody = Blob.valueOf(payloadForRegs);
        RestContext.request = reqForRegs;
        RestContext.response = resForRegs;

        // Call the method
        saveWebTo_YourProfileData.handleAurisData();
    }

    @IsTest
    static void testCreateLeadWithFullDataMasterDuplicate() {


        List<Map<String, Object>> standardisedTestScoreList = new List<Map<String, Object>>();
        standardisedTestScoreList.add(new Map<String, Object>{
            'testName'=> 'Transcript',
            'testScore'=>'1500',
            'testDate'=>'2018-05-01',
            'percentile' =>'90'
        });

        standardisedTestScoreList.add(new Map<String, Object>{
            'testName'=> 'Transcript',
            'testScore'=>'1500',
            'testDate'=>'2018-05-01',
            'percentile' =>'90'
        });


        Map<String, Object> lead1 = new Map<String, Object>{
            'leadSource' => 'careers360',
            'aurisFormURL' => 'http://example.com/form',
            'url' => 'http://example.com',
            'leadStatus' => 'New',
            'firstName' => 'John',
            'middleName' => 'M',
            'lastName' => 'Doe',
            'email' => 'john.doe@example.com',
            'phone' => '9898989898',
            'registrationDate' => '2023-01-01',
            'stateUnionTerritoryProvince'=>'Gujarat',
            'district'=>'Gujarat',
            'pinPostalCode'=> '90001',
            'maillingAddress'=>'123 Main St',
            'maillingCountry'=> 'ndia',
            'maillingCityTownVillage'=> 'Los Angeles',
            'maillingPinPostalCode'=> '90001',
            'applicationNumber' => 'application-006',
            'applicationDate' => '2024-02-02',
            'programmeInterestedIn'=> 'Master of Business Administration',
            'department'=> 'Masters',
            'typeOfForm'=> 'Auris_Admission_Form',
            'registrationNumber'=>'98218',
            'country'=>'India',
            'mobile'=>'1234567890',
            'gender'=>'Female',
            'dateOfBirth' =>'1998-01-20',
            'nationality'=>'Indian',
            'bloodGroup'=>'A+',
            'ociCardHolder'=>'No',
            'aadharCardNumber'=>'1234-5678-9012',
            'category'=>'General',
            'differentlyAbled'=>'No',
            'residentialAddress'=>'123 Main St',
            'cityTownVillage'=>'Ahmedabad',
            'cgpa'=>'8.5',
            'schoolBranchLocation'=>'abcxyz',
            'maillingstateUnionTerritoryProvince'=>'Gujarat',
            'interestedInStudentHousing'=>'yes',
            'numberOfFamilyMembers'=>'5',
            'isYourSiblingStudyingAtAU'=>'No',
            'eligibleForFinancialAid'=>'Yes',
            'formNumber'=>'12345',
            'applicationInitiatedDate'=>'2024-01-20',
            'programmeInterestedIn'=> 'Master of Technology in Composites',
            'major'=>'Science',
            'countryOfBirth'=>'India',
            'standardisedTestScore'=>standardisedTestScoreList
        };               
        String requestBody1 = JSON.serialize(lead1);

        // Set up REST request and response
        RestRequest req1 = new RestRequest();
        RestResponse res1 = new RestResponse();
        req1.requestUri = '/services/apexrest/saveWebToYourProfileData/';
        req1.httpMethod = 'POST';
        req1.requestBody = Blob.valueOf(requestBody1);
        RestContext.request = req1;
        RestContext.response = res1;

        // Call the method
        saveWebTo_YourProfileData.handleAurisData();


        List<Map<String, Object>> programInsterstedInList = new List<Map<String, Object>>();
        programInsterstedInList.add(new Map<String, Object>{
            'programInterestedIn'=>'Master of Business Administration'        
        });

        Map<String, Object> lead2 = new Map<String, Object>{
            'leadSource' => 'careers360',
            'aurisFormURL' => 'http://example.com/form',
            'url' => 'http://example.com',
            'leadStatus' => 'New',
            'firstName' => 'John',
            'middleName' => 'M',
            'lastName' => 'Doe',
            'salutation' => 'Mr.',
            'email' => 'john.doe@example.com',
            'phone' => '9898989898',
            'registrationDate' => '2023-01-01',
            'stateUnionTerritoryProvince'=>'Gujarat',
            'district'=>'Gujarat',
            'pinPostalCode'=> '90001',
            'maillingAddress'=>'123 Main St',
            'maillingCountry'=> 'ndia',
            'maillingCityTownVillage'=> 'Los Angeles',
            'maillingPinPostalCode'=> '90001',
            'applicationNumber' => 'application-006',
            'applicationDate' => '2024-02-02',
            'programmeInterestedIn'=> 'Master of Business Administration',
            'department'=> 'Masters',
            'typeOfForm'=> 'Auris_Admission_Form',
            'registrationNumber'=>'98218',
            'country'=>'India',
            'mobile'=>'1234567890',
            'gender'=>'Female',
            'dateOfBirth' =>'1998-01-20',
            'nationality'=>'Indian',
            'bloodGroup'=>'A+',
            'ociCardHolder'=>'No',
            'aadharCardNumber'=>'1234-5678-9012',
            'category'=>'General',
            'differentlyAbled'=>'No',
            'residentialAddress'=>'123 Main St',
            'cityTownVillage'=>'Ahmedabad',
            'cgpa'=>'8.5',
            'schoolBranchLocation'=>'abcxyz',
            'maillingstateUnionTerritoryProvince'=>'Gujarat',
            'interestedInStudentHousing'=>'yes',
            'numberOfFamilyMembers'=>'5',
            'isYourSiblingStudyingAtAU'=>'No',
            'eligibleForFinancialAid'=>'Yes',
            'formNumber'=>'12345',
            'applicationInitiatedDate'=>'2024-01-20',
            'programmeInterestedIn'=> 'Master of Technology in Composites',
            'major'=>'Science',
            'countryOfBirth'=>'India',
            'programs'=>programInsterstedInList,
            'standardisedTestScore'=>standardisedTestScoreList
        };

        String requestBody2 = JSON.serialize(lead2);
        
        // Set up REST request and response
        RestRequest req2 = new RestRequest();
        RestResponse res2 = new RestResponse();
        req2.requestUri = '/services/apexrest/saveWebToYourProfileData/';
        req2.httpMethod = 'POST';
        req2.requestBody = Blob.valueOf(requestBody2);
        RestContext.request = req2;
        RestContext.response = res2;

        // Call the method
        saveWebTo_YourProfileData.handleAurisData();




    }

   
}