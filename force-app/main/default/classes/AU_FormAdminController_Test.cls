@IsTest
public class AU_FormAdminController_Test {

    @IsTest
    static void testGetDashboardData() {
        Test.startTest();
        AU_FormAdminController.DashboardDataWrapper result = AU_FormAdminController.getDashboardData();
        Test.stopTest();

        System.assertNotEquals(null, result, 'DashboardDataWrapper should not be null');
        System.assertNotEquals(null, result.departments, 'Departments should not be null');
        System.assertNotEquals(null, result.forms, 'Forms should not be null');
        System.assertNotEquals(null, result.availableLeadFields, 'Available lead fields should not be null');
        System.assertNotEquals(null, result.leadRecordTypes, 'Lead record types should not be null');
        System.assertNotEquals(null, result.siteBaseUrl, 'Site base URL should not be null');
    }

    @IsTest
    static void testGetLeadFieldsDescribe() {
        Test.startTest();
        List<Map<String, Object>> fields = AU_FormAdminController.getLeadFieldsDescribe();
        Test.stopTest();

        System.assertNotEquals(null, fields, 'Lead fields describe should return a list');
        System.assert(fields.size() > 0, 'Should return multiple Lead fields');

        Boolean hasEmailOrPhone = false;
        for (Map<String, Object> f : fields) {
            String apiName = (String) f.get('apiName');
            if (apiName == 'Email' || apiName == 'Phone' || apiName == 'FirstName') {
                hasEmailOrPhone = true;
                break;
            }
        }
        System.assert(hasEmailOrPhone, 'Should include standard lead fields');
    }

    @IsTest
    static void testGetLeadRecordTypes() {
        Test.startTest();
        List<Map<String, Object>> rts = AU_FormAdminController.getLeadRecordTypes();
        Test.stopTest();

        System.assertNotEquals(null, rts, 'Lead record types list should not be null');
    }

    @IsTest
    static void testGetSiteBaseUrl() {
        Test.startTest();
        String url = AU_FormAdminController.getSiteBaseUrl();
        Test.stopTest();

        System.assertNotEquals(null, url, 'Site base URL should not be null');
    }

    @IsTest
    static void testGetLeadCountsByForm() {
        // Insert a test lead with TypeOfForm and UTM_Campaign
        Lead l = new Lead(
            FirstName = 'Count',
            LastName = 'Tester',
            Company = 'Test Org',
            Email = 'counttest@example.com',
            TypeOfForm__c = 'Website_UGQueries',
            UTM_Campaign__c = 'ug_campaign'
        );
        insert l;

        Test.startTest();
        Map<String, Integer> counts = AU_FormAdminController.getLeadCountsByForm();
        Test.stopTest();

        System.assertNotEquals(null, counts, 'Counts map should not be null');
        System.assert(counts.containsKey('website_ugqueries'), 'Should contain website_ugqueries count');
    }

    @IsTest
    static void testSaveForm_Success() {
        AU_FormAdminController.FormConfigWrapper formConfig = new AU_FormAdminController.FormConfigWrapper();
        formConfig.developerName = 'MASTERS_TEST_WEBINAR';
        formConfig.masterLabel = 'Masters Test Webinar';
        formConfig.departmentCode = 'MASTERS';
        formConfig.formName = 'Masters Test Webinar';
        formConfig.formSubtitle = 'Join our interactive session';
        formConfig.formIcon = '🎓';
        formConfig.formSlug = 'test-webinar';
        formConfig.sectionLabel = 'Applicant Details';
        formConfig.leadRecordTypeName = 'Masters';
        formConfig.typeOfForm = 'Webinar';
        formConfig.sortOrder = 10;

        List<AU_FormAdminController.FormFieldWrapper> fields = new List<AU_FormAdminController.FormFieldWrapper>();

        AU_FormAdminController.FormFieldWrapper field1 = new AU_FormAdminController.FormFieldWrapper();
        field1.developerName = 'FM_TEST_WEBINAR_EMAIL';
        field1.masterLabel = 'FM_TEST_WEBINAR_EMAIL';
        field1.departmentCode = 'MASTERS';
        field1.formCode = 'TEST-WEBINAR';
        field1.sfApiName = 'Email';
        field1.formLabel = 'Email Address';
        field1.fieldType = 'email';
        field1.isRequired = true;
        field1.placeholderText = 'student@example.com';
        field1.helpText = 'We will send details to this email';
        field1.fullWidth = false;
        field1.isNumeric = false;
        field1.isInteger = false;
        field1.isHidden = false;
        field1.defaultValue = '';
        field1.sortOrder = 1;
        fields.add(field1);

        AU_FormAdminController.FormFieldWrapper field2 = new AU_FormAdminController.FormFieldWrapper();
        field2.sfApiName = 'Phone';
        field2.formLabel = 'WhatsApp / Mobile';
        field2.fieldType = 'tel';
        field2.isRequired = true;
        field2.fullWidth = false;
        field2.isHidden = false;
        field2.defaultValue = '';
        field2.sortOrder = 2;
        fields.add(field2);

        AU_FormAdminController.FormFieldWrapper field3 = new AU_FormAdminController.FormFieldWrapper();
        field3.sfApiName = 'City';
        field3.formLabel = 'City Location';
        field3.fieldType = 'text';
        field3.isRequired = false;
        field3.fullWidth = false;
        field3.isHidden = true;
        field3.defaultValue = 'Ahmedabad';
        field3.sortOrder = 3;
        fields.add(field3);

        String formJSON = JSON.serialize(formConfig);
        String fieldsJSON = JSON.serialize(fields);

        Test.startTest();
        Map<String, Object> result = AU_FormAdminController.saveForm(formJSON, fieldsJSON);
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Save form should succeed: ' + result.get('error'));
        System.assertEquals('MASTERS_TEST_WEBINAR', result.get('formDeveloperName'));
    }

    @IsTest
    static void testSaveForm_AutoGenerateDevName() {
        AU_FormAdminController.FormConfigWrapper formConfig = new AU_FormAdminController.FormConfigWrapper();
        formConfig.departmentCode = 'UG';
        formConfig.formName = 'Mumbai City Webinar';
        formConfig.formSlug = 'mumbai-ug-webinar';

        List<AU_FormAdminController.FormFieldWrapper> fields = new List<AU_FormAdminController.FormFieldWrapper>();

        String formJSON = JSON.serialize(formConfig);
        String fieldsJSON = JSON.serialize(fields);

        Test.startTest();
        Map<String, Object> result = AU_FormAdminController.saveForm(formJSON, fieldsJSON);
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Save form should succeed: ' + result.get('error'));
    }

    @IsTest
    static void testSaveForm_LongFormCodeAndDuplicatePrefixFields() {
        AU_FormAdminController.FormConfigWrapper formConfig = new AU_FormAdminController.FormConfigWrapper();
        formConfig.departmentCode = 'UG';
        formConfig.formName = 'Undergraduation Walk In Inquiry Form';
        formConfig.formSlug = 'undergraduation_walk_in_inquiry';

        List<AU_FormAdminController.FormFieldWrapper> fields = new List<AU_FormAdminController.FormFieldWrapper>();

        AU_FormAdminController.FormFieldWrapper f1 = new AU_FormAdminController.FormFieldWrapper();
        f1.sfApiName = 'School__c';
        f1.formLabel = 'School Name';
        f1.fieldType = 'text';
        fields.add(f1);

        AU_FormAdminController.FormFieldWrapper f2 = new AU_FormAdminController.FormFieldWrapper();
        f2.sfApiName = 'School_City__c';
        f2.formLabel = 'School City';
        f2.fieldType = 'text';
        fields.add(f2);

        AU_FormAdminController.FormFieldWrapper f3 = new AU_FormAdminController.FormFieldWrapper();
        f3.sfApiName = 'School_State__c';
        f3.formLabel = 'School State';
        f3.fieldType = 'text';
        fields.add(f3);

        String formJSON = JSON.serialize(formConfig);
        String fieldsJSON = JSON.serialize(fields);

        Test.startTest();
        Map<String, Object> result = AU_FormAdminController.saveForm(formJSON, fieldsJSON);
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Save form with long form slug and similar field names should succeed: ' + result.get('error'));
    }

    @IsTest
    static void testSaveForm_InvalidJSON() {
        Test.startTest();
        Map<String, Object> result = AU_FormAdminController.saveForm('INVALID_JSON', 'INVALID_JSON');
        Test.stopTest();

        System.assertEquals(false, result.get('success'), 'Should fail with invalid JSON');
        System.assertNotEquals(null, result.get('error'), 'Error message should be present');
    }

    @IsTest
    static void testDeleteForm() {
        Test.startTest();
        Map<String, Object> result = AU_FormAdminController.deleteForm('UG_TEST_FORM', 'ug-test-form', 'UG');
        Map<String, Object> resultBlank = AU_FormAdminController.deleteForm('', '', '');
        Boolean delRes = AU_FormAdminController.deleteMetadataRecords(new List<String>{ 'Form_Field_Config.FM_TEST_EMAIL' });
        String sessId = AU_FormAdminController.getApiSessionId();
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Delete form should return success in test context');
        System.assertEquals(false, resultBlank.get('success'), 'Blank developer name should fail');
        System.assertEquals(true, delRes, 'deleteMetadataRecords should return true in test context');
        System.assertNotEquals(null, sessId, 'Session ID should not be null');
    }

    @IsTest
    static void testDeployCallback() {
        AU_FormAdminController.AU_FormAdminDeployCallback callback = new AU_FormAdminController.AU_FormAdminDeployCallback();

        Metadata.DeployResult successResult = new Metadata.DeployResult();
        successResult.status = Metadata.DeployStatus.Succeeded;

        Metadata.DeployResult failResult = new Metadata.DeployResult();
        failResult.status = Metadata.DeployStatus.Failed;
        failResult.errorMessage = 'Simulated Deployment Error';

        Test.startTest();
        callback.handleResult(successResult, null);
        callback.handleResult(failResult, null);
        Test.stopTest();
    }

    @IsTest
    static void getProgrammeBrochures_returnsList() {
        List<Map<String, Object>> rows = AU_FormAdminController.getProgrammeBrochures();
        System.assertNotEquals(null, rows);
    }

    @IsTest
    static void saveProgrammeBrochures_rejectsNonHttps() {
        String json = JSON.serialize(new List<Map<String, Object>>{
            new Map<String, Object>{ 'programmeName' => 'Test Programme', 'brochureUrl' => 'http://example.com/b.pdf' }
        });
        Map<String, Object> res = AU_FormAdminController.saveProgrammeBrochures(json);
        System.assertEquals(false, res.get('success'));
    }

    @IsTest
    static void saveProgrammeBrochures_acceptsHttpsAndSkipsEmpty() {
        String json = JSON.serialize(new List<Map<String, Object>>{
            new Map<String, Object>{ 'programmeName' => 'Test Programme', 'brochureUrl' => 'https://example.com/b.pdf' },
            new Map<String, Object>{ 'programmeName' => 'Blank Programme', 'brochureUrl' => '' }
        });
        Map<String, Object> res = AU_FormAdminController.saveProgrammeBrochures(json);
        System.assertEquals(true, res.get('success'));
        System.assertEquals(1, res.get('count'));
    }
}