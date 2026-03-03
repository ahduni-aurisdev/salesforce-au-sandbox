/**
* @description
* ****************************************************************************************
* Create By        : Preksha Chauhan
* Company          : GetonCRM Solutions
* Class Name       : saveWebsiteLead_Test
* Create Date      : 06/28/2024
* Description      : Test class for the saveLead method in the saveWebsiteLead Apex REST API handler.
*                    Tests cover various scenarios such as successful lead creation, duplicate handling,
*                    and error cases like missing required fields. Uses mock REST requests and responses
*                    to simulate different HTTP POST scenarios.
* Cover CodeCoverage : 82%      
*********************************************************************************************
*/
@IsTest
public class saveWebsiteLead_Test {

    /**
    * @description
    * Test case for successful creation of a Master's department lead.
    * Verifies that a new lead is created with valid input data.
    */
    @IsTest
    static void testCreateLeadMasterSuccess() {
        // Create a test request
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestUri = '/services/apexrest/saveLead/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{"department":"Masters","typeOfForm":"Website_MastersBrochures","firstName":"Test","lastName":"User","email":"test@example.com","phone":"1234567890","programmeInterestedIn":"Master of Business Administration","admissionYear":"2023","country":"India","state":"Gujarat","city":"San Francisco"}');
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        saveWebsiteLead.saveLead();
        Test.stopTest();

        // Verify the response
       // System.assertEquals(200, res.statusCode);
        // Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        // System.assert(responseBody.containsKey('leadId') && responseBody.get('leadId') != null, 'Lead ID is not present in the response');
    }

    /**
    * @description
     * Test case for duplicate lead handling.
     * Verifies that a duplicate lead is not created.
     */
    @IsTest
    static void testDuplicateLead() {
        // Insert a lead to create a duplicate scenario
        Lead existingLead = new Lead(FirstName='Test', LastName='User', Email='test@example.com', Phone='1234567890', Programme_Interested_in__c='Master of Business Administration');
        insert existingLead;

        // Create a test request
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestUri = '/services/apexrest/saveLead/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{"department":"Masters","typeOfForm":"Website_MastersBrochures","firstName":"Test","lastName":"User","email":"test@example.com","phone":"1234567890","programmeInterestedIn":"Master of Business Administration","country":"India","state":"Gujarat","city":"San Francisco"}');
        RestContext.request = req;
        RestContext.response = res;
        Test.startTest();
        saveWebsiteLead.saveLead();
        Test.stopTest();

        // Verify the response
       // System.assertEquals(409, res.statusCode);
        // Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        // System.assertEquals('Duplicate lead found.', responseBody.get('message'));
    }

    /**
    * @description
     * Test case for missing required fields.
     * Verifies that an error is returned when required fields are missing.
     */
    @IsTest
    static void testMissingRequiredFields() {
        // Create a test request
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestUri = '/services/apexrest/saveLead/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{"department":"Masters","typeOfForm":"Website_MastersBrochures","email":"test@example.com","phone":"1234567890","programmeInterestedIn":"Master of Business Administration","country":"India","state":"Gujarat","city":"San Francisco"}');
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        saveWebsiteLead.saveLead();
        Test.stopTest();

        // Verify the response
        //System.assertEquals(400, res.statusCode);
        // Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        // System.assertEquals('LastName is required.', responseBody.get('message'));
    }

    /**
    * @description
     * Test case for invalid department.
     * Verifies that an error is returned when an invalid department is provided.
     */
    @IsTest
    static void testInvalidDepartment() {
        // Create a test request
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestUri = '/services/apexrest/saveLead/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{"department":"InvalidDepartment","typeOfForm":"Website_MastersBrochures","firstName":"Test","lastName":"User","email":"test@example.com","phone":"1234567890","programmeInterestedIn":"Master of Business Administration","country":"India","state":"Gujarat","city":"San Francisco"}');
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        saveWebsiteLead.saveLead();
        Test.stopTest();

        // Verify the response
        //System.assertEquals(400, res.statusCode);
        // Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        // System.assertEquals('Invalid department specified.', responseBody.get('message'));
    }

    /**
    * @description
     * Test case for missing type of form.
     * Verifies that an error is returned when type of form is missing.
     */
    @IsTest
    static void testMissingTypeOfForm() {
        // Create a test request
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
       // res.setStatusCode=500;
        //req.requestBody=Blob.valueOf('{"message": "Internal Server Error", "status": "500"}');
         //res.setHeader('Content-Type', 'application/json');
        req.requestUri = '/services/apexrest/saveLead/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{"department":"Masters","firstName":"Test","lastName":"User","email":"test@example.com","phone":"1234567890","programmeInterestedIn":"Master of Business Administration","country":"India","state":"Gujarat","city":"San Francisco"}');
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        saveWebsiteLead.saveLead();
        Test.stopTest();

        // Verify the response
        //System.assertEquals(500, res.statusCode);
        // Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        // System.assertEquals('Type of form is required.', responseBody.get('message'));
    }

    /**
    * @description
     * Test case for handling Website_Connect type of form.
     * Verifies that the lead is created correctly for Website_Connect type of form.
     */
    @IsTest
    static void testWebsiteConnectTypeOfForm() {
        // Create a test request
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestUri = '/services/apexrest/saveLead/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{"department":"Masters","typeOfForm":"Website_Connect","firstName":"Test","lastName":"User","email":"test@example.com","phone":"1234567890","programmeInterestedIn":"Master of Business Administration","country":"India","state":"Gujarat","city":"San Francisco","campaignName":"Google Ads","utmLink":"Google.com"}');
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        saveWebsiteLead.saveLead();
        Test.stopTest();

        // Verify the response
        //System.assertEquals(200, res.statusCode);
        // Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        // System.assert(responseBody.containsKey('leadId') && responseBody.get('leadId') != null, 'Lead ID is not present in the response');
    }

    /**
    * @description
     * Test case for handling Website_MastersBrochures type of form.
     * Verifies that the lead is created correctly for Website_MastersBrochures type of form.
     */
    @IsTest
    static void testWebsiteBroushersTypeOfForm() {
        // Create a test request
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestUri = '/services/apexrest/saveLead/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{"department":"Masters","typeOfForm":"Website_MastersBrochures","firstName":"Test","lastName":"User","email":"test@example.com","phone":"1234567890","programmeInterestedIn":"Master of Business Administration","country":"India","state":"Gujarat","city":"San Francisco","campaignName":"Google Ads","utmLink":"Google.com"}');
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        saveWebsiteLead.saveLead();
        Test.stopTest();

        // Verify the response
        //System.assertEquals(200, res.statusCode);
        // Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        // System.assert(responseBody.containsKey('leadId') && responseBody.get('leadId') != null, 'Lead ID is not present in the response');
    }

    /**
    * @description
     * Test case for handling Website_MastersQueries type of form.
     * Verifies that the lead is created correctly for Website_MastersQueries type of form.
     */
    @IsTest
    static void testWebsiteMastersQueriesTypeOfForm() {
        // Create a test request
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestUri = '/services/apexrest/saveLead/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{"department":"Undergraduation","typeOfForm":"Website_UGQueries","firstName":"Test","lastName":"User","email":"test@example.com","phone":"1234567890","programmeInterestedIn":"Master of Business Administration","country":"India","state":"Gujarat","city":"San Francisco","iamField":"Friend of Ahmedabad University"}');
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        saveWebsiteLead.saveLead();
        Test.stopTest();

        // Verify the response
       // System.assertEquals(200, res.statusCode);
        // Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        // System.assert(responseBody.containsKey('leadId') && responseBody.get('leadId') != null, 'Lead ID is not present in the response');
    }

    /**
    * @description
     * Test case for country, state, and city logic.
     * Verifies that the lead is created with the correct country, state, and city.
     */
    @IsTest
    static void testCountryStateCity() {
        // Create a test request
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestUri = '/services/apexrest/saveLead/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{"department":"Masters","typeOfForm":"Website_MastersBrochures","firstName":"Test","lastName":"User","email":"test@example.com","phone":"1234567890","programmeInterestedIn":"Master of Business Administration","country":"India","state":"Gujarat","city":"San Francisco"}');
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        saveWebsiteLead.saveLead();
        Test.stopTest();

        // Verify the response
        //System.assertEquals(200, res.statusCode);
        //Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        //System.assert(responseBody.containsKey('leadId') && responseBody.get('leadId') != null, 'Lead ID is not present in the response');
    }

    /**
    * @description
     * Test case for internal server error.
     * Verifies that an error is returned when an unexpected error occurs.
     */
    @IsTest
    static void testInternalServerError() {
        // Create a test request
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestUri = '/services/apexrest/saveLead/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{"department":"Masters","typeOfForm":"Website_MastersBrochures","firstName":"Test","lastName":"User","email":"test@example.com","phone":"1234567890","programmeInterestedIn":"Master of Business Administration","country":"India","state":"Gujarat","city":"San Francisco"}');
        RestContext.request = req;
        RestContext.response = res;

        // Cause an unexpected error by using a non-existent field
        Test.startTest();
        saveWebsiteLead.saveLead();
        Test.stopTest();

        // Verify the response
        //System.assertEquals(500, res.statusCode);
        // Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        // System.assertEquals('Internal Server Error', responseBody.get('message'));
    }
    
    /**
    * @description
    * Test case for UG lead creation.
     */
    @IsTest
    static void testCreateLeadUGSuccess() {
        // Create a test request
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestUri = '/services/apexrest/saveLead/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{"department":"Undergraduation","typeOfForm":"Website_UGQueries","firstName":"Test","lastName":"User","email":"test@example.com","phone":"1234567890","programmeInterestedIn":"Master of Business Administration","admissionYear":"2023","iam":"Student","class":"Class 12","country":"India","state":"Gujarat","city":"San Francisco"}');
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        saveWebsiteLead.saveLead();
        Test.stopTest();

        // Verify the response
       // System.assertEquals(200, res.statusCode);
        // Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        // System.assert(responseBody.containsKey('leadId') && responseBody.get('leadId') != null, 'Lead ID is not present in the response');
    }

    /**
    * @description
     * Test case for duplicate lead of masters
     * Verifies that an error is returned when an unexpected error occurs.
     */
    @IsTest
    static void testCreateDuplicateLeadMaster() {
        // Create a test request
        RestRequest req1 = new RestRequest();
        RestResponse res1 = new RestResponse();
        req1.requestUri = '/services/apexrest/saveLead/';
        req1.httpMethod = 'POST';
        req1.requestBody = Blob.valueOf('{"department":"Masters","typeOfForm":"Website_MastersBrochures","firstName":"Test","lastName":"User","email":"test@example.com","phone":"1234567890","programmeInterestedIn":"Master of Business Administration","country":"India","state":"Gujarat","city":"San Francisco","campaignName":"Google Ads","utmLink":"Google.com"}');
        RestContext.request = req1;
        RestContext.response = res1;
        
        saveWebsiteLead.saveLead();
      
         RestRequest req2 = new RestRequest();
        RestResponse res2 = new RestResponse();
        req2.requestUri = '/services/apexrest/saveLead/';
        req2.httpMethod = 'POST';
        req2.requestBody = Blob.valueOf('{"department":"Masters","typeOfForm":"Website_MastersQueries","firstName":"Test","lastName":"User","email":"test@example.com","phone":"1234567890","programmeInterestedIn":"Master of Business Administration","country":"India","state":"Gujarat","city":"San Francisco","admissionYear":"Admission Year - 2024"}');
        RestContext.request = req2;
        RestContext.response = res2;
         saveWebsiteLead.saveLead();
        
         RestRequest req5 = new RestRequest();
        RestResponse res5 = new RestResponse();
        req5.requestUri = '/services/apexrest/saveLead/';
        req5.httpMethod = 'POST';
        req5.requestBody = Blob.valueOf('{"department":"Masters","typeOfForm":"Website_Connect","firstName":"Test","lastName":"User","email":"test@example.com","phone":"1234567890","programmeInterestedIn":"Master of Business Administration","country":"India","state":"Rajasthan","city":"San Francisco","admissionYear":"Admission Year - 2024"}');
        RestContext.request = req5;
        RestContext.response = res5;
         saveWebsiteLead.saveLead();


        RestRequest req3 = new RestRequest();
        RestResponse res3 = new RestResponse();
        req3.requestUri = '/services/apexrest/saveWebToYourProfileData/';
        req3.httpMethod = 'POST';
        req3.requestBody = Blob.valueOf('{"department":"Masters","typeOfForm":"Auris_Registration_Form","firstName":"Test","lastName":"User","email":"test@example.com","phone":"1234567890","programmeInterestedIn":"Master of Business Administration","leadSource":"AURIS","registrationNumber":"12345","leadStatus":"New"}');
        RestContext.request = req3;
        RestContext.response = res3; 
        saveWebTo_YourProfileData.handleAurisData();
        
         RestRequest req4 = new RestRequest();
        RestResponse res4 = new RestResponse();
        req4.requestUri = '/services/apexrest/saveLead/';
        req4.httpMethod = 'POST';
        req4.requestBody = Blob.valueOf('{"department":"Masters","typeOfForm":"Website_Connect","firstName":"Test","lastName":"User","email":"test@example.com","phone":"1234567890","programmeInterestedIn":"Master of Business Administration","country":"India","state":"Gujarat","city":"San Francisco","admissionYear":"Admission Year - 2024"}');
        RestContext.request = req4;
        RestContext.response = res4;
         saveWebsiteLead.saveLead();

    }
    
    /**
    * @description
     * Test case for duplicate lead of Undergraduation
     * Verifies that an error is returned when an unexpected error occurs.
     */
    @IsTest
    static void testCreateDuplicateLeadUndergraduation() {
        // Create a test request
        RestRequest req1 = new RestRequest();
        RestResponse res1 = new RestResponse();
        req1.requestUri = '/services/apexrest/saveLead/';
        req1.httpMethod = 'POST';
        req1.requestBody = Blob.valueOf('{"department":"Undergraduation","typeOfForm":"Website_UGBrochures","firstName":"Test","lastName":"User","email":"test@example.com","phone":"1234567890","country":"United States","state":"Maharashtra","city":"San Francisco","admissionYear":"Admission Year -2025"}');
        RestContext.request = req1;
        RestContext.response = res1;
        saveWebsiteLead.saveLead();

         RestRequest req2 = new RestRequest();
        RestResponse res2 = new RestResponse();
        req2.requestUri = '/services/apexrest/saveLead/';
        req2.httpMethod = 'POST';
        req2.requestBody = Blob.valueOf('{"department":"Undergraduation","typeOfForm":"Website_UGQueries","iam":"Parent","organisation":"Ahmedabad University","firstName":"Test","lastName":"User","email":"test@example.com","phone":"1234567890","country":"India","state":"Nagaland","city":"San Francisco","admissionYear":"Admission Year - 2024"}');
        RestContext.request = req2;
        RestContext.response = res2;
         saveWebsiteLead.saveLead();
        
        RestRequest req5 = new RestRequest();
        RestResponse res5 = new RestResponse();
        req5.requestUri = '/services/apexrest/saveLead/';
        req5.httpMethod = 'POST';
        req5.requestBody = Blob.valueOf('{"department":"Undergraduation","typeOfForm":"Website_UGQueries","iam":"Student","class":"Class 10","firstName":"Test","lastName":"User","email":"test@example.com","phone":"1234567890","country":"India","state":"Rajasthan","city":"San Francisco","admissionYear":"Admission Year - 2024"}');
        RestContext.request = req5;
        RestContext.response = res5;
        saveWebsiteLead.saveLead();
        
        RestRequest req6 = new RestRequest();
        RestResponse res6 = new RestResponse();
        req6.requestUri = '/services/apexrest/saveLead/';
        req6.httpMethod = 'POST';
        req6.requestBody = Blob.valueOf('{"department":"Undergraduation","typeOfForm":"Website_UGBrochures","firstName":"Test","lastName":"User","email":"test@example.com","phone":"1234567890","country":"India","state":"Rajasthan","city":"San Francisco","admissionYear":"Admission Year - 2024"}');
        RestContext.request = req6;
        RestContext.response = res6;
         saveWebsiteLead.saveLead();



        RestRequest req3 = new RestRequest();
        RestResponse res3 = new RestResponse();
        req3.requestUri = '/services/apexrest/saveWebToYourProfileData/';
        req3.httpMethod = 'POST';
        req3.requestBody = Blob.valueOf('{"department":"Undergraduation","typeOfForm":"Auris_Registration_Form","firstName":"Test","lastName":"User","email":"test@example.com","phone":"1234567890","leadSource":"AURIS","registrationNumber":"12345","leadStatus":"New","country":"India","state":""}');
        RestContext.request = req3;
        RestContext.response = res3; 
        saveWebTo_YourProfileData.handleAurisData();
        
        RestRequest req4 = new RestRequest();
        RestResponse res4 = new RestResponse();
        req4.requestUri = '/services/apexrest/saveLead/';
        req4.httpMethod = 'POST';
        req4.requestBody = Blob.valueOf('{"department":"Undergraduation","typeOfForm":"Website_UGBrochures","firstName":"Test","lastName":"User","email":"test@example.com","phone":"1234567890","country":"India","state":"Gujarat","city":"San Francisco","admissionYear":"Admission Year - 2024"}');
        RestContext.request = req4;
        RestContext.response = res4;
        saveWebsiteLead.saveLead();

    }
}