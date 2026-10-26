/**
 * @description Tests HTTP behavior for the Task Activity REST resource.
 * @author AU Development Team
 * @date 2026-10-23
 * @version 1.0
 * @lastModified 2026-10-23
 */
@IsTest
private class TaskActivityRestResourceTest {
    private static final String ACCOUNT_PREFIX = 'TaskRest Account ';

    @TestSetup
    static void createData() {
        List<Account> accounts = new List<Account>();
        for (Integer index = 0; index < 200; index++) {
            accounts.add(new Account(Name = ACCOUNT_PREFIX + index, BillingCity = 'Ahmedabad'));
        }
        insert accounts;
    }

    @IsTest
    static void shouldReturnSuccessForValidPayload() {
        Id accountId = [SELECT Id FROM Account WHERE Name = :ACCOUNT_PREFIX + '0'].Id;
        prepareRestContext('{"records":[{' +
            '"recordId":"' + accountId + '",' +
            '"subject":"REST follow-up",' +
            '"dueDate":"' + String.valueOf(Date.today().addDays(3)) + '",' +
            '"comments":"Created from REST test"' +
        '}]}');

        Test.startTest();
        TaskActivityRestResource.createTasks();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode, 'A valid request should return HTTP 200.');
        TaskActivityApiModels.ResponseEnvelope response = deserializeResponse();
        System.assertEquals(true, response.success, 'The response should indicate complete success.');
        System.assertEquals('CREATED', response.results[0].action, 'The result should identify the create action.');
        System.assertNotEquals(null, response.results[0].taskId, 'The result should return the new Task ID.');
    }

    @IsTest
    static void shouldReturnMultiStatusForPartialSuccess() {
        Id accountId = [SELECT Id FROM Account WHERE Name = :ACCOUNT_PREFIX + '1'].Id;
        prepareRestContext('{"records":[' +
            '{"recordId":"' + accountId + '","subject":"Valid"},' +
            '{"recordId":"' + accountId + '","subject":"Invalid","dueDate":"not-a-date"}' +
        ']}');

        Test.startTest();
        TaskActivityRestResource.createTasks();
        Test.stopTest();

        System.assertEquals(207, RestContext.response.statusCode, 'Partial success should return HTTP 207.');
        TaskActivityApiModels.ResponseEnvelope response = deserializeResponse();
        System.assertEquals(1, response.successCount, 'One record should succeed.');
        System.assertEquals(1, response.failureCount, 'One record should fail.');
        System.assert(
            response.results[1].errors[0].contains('YYYY-MM-DD'),
            'The API should return the exact date-format error.'
        );
    }

    @IsTest
    static void shouldReturnBadRequestForMalformedJson() {
        prepareRestContext('{"records":[');

        Test.startTest();
        TaskActivityRestResource.createTasks();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode, 'Malformed JSON should return HTTP 400.');
        System.assert(
            RestContext.response.responseBody.toString().contains('Invalid JSON payload'),
            'The response should explain that the JSON is invalid.'
        );
    }

    @IsTest
    static void shouldReturnBadRequestForEmptyBody() {
        prepareRestContext('');

        Test.startTest();
        TaskActivityRestResource.createTasks();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode, 'An empty body should return HTTP 400.');
        System.assert(
            RestContext.response.responseBody.toString().contains('Request body is required'),
            'The response should identify the missing request body.'
        );
    }

    @IsTest
    static void shouldReturnBadRequestForEmptyRecords() {
        prepareRestContext('{"records":[]}');

        Test.startTest();
        TaskActivityRestResource.createTasks();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode, 'An empty records list should return HTTP 400.');
        System.assert(
            RestContext.response.responseBody.toString().contains('at least one task'),
            'The response should explain that records are required.'
        );
    }

    private static void prepareRestContext(String payload) {
        RestRequest request = new RestRequest();
        request.httpMethod = 'POST';
        request.requestUri = '/services/apexrest/v1/activities/tasks';
        request.requestBody = Blob.valueOf(payload);
        RestContext.request = request;
        RestContext.response = new RestResponse();
    }

    private static TaskActivityApiModels.ResponseEnvelope deserializeResponse() {
        return (TaskActivityApiModels.ResponseEnvelope) JSON.deserialize(
            RestContext.response.responseBody.toString(),
            TaskActivityApiModels.ResponseEnvelope.class
        );
    }
}