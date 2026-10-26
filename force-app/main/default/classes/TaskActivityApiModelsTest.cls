/**
 * @description Tests the Task Activity API request and response contracts.
 * @author AU Development Team
 * @date 2026-10-23
 * @version 1.0
 * @lastModified 2026-10-23
 */
@IsTest
private class TaskActivityApiModelsTest {
    @TestSetup
    static void createData() {
        List<Account> accounts = new List<Account>();
        for (Integer index = 0; index < 200; index++) {
            accounts.add(new Account(Name = 'TaskModel Account ' + index, BillingCity = 'Ahmedabad'));
        }
        insert accounts;
    }

    @IsTest
    static void shouldDeserializeRequestAndSerializeResponse() {
        TaskActivityApiModels modelsContainer = new TaskActivityApiModels();
        System.assertNotEquals(null, modelsContainer, 'The DTO container constructor should be testable.');

        Id accountId = [SELECT Id FROM Account WHERE Name = 'TaskModel Account 0'].Id;
        String payload = '{"records":[{"recordId":"' + accountId + '","subject":"Model task",' +
            '"dueDate":"2026-10-30","comments":"Model comments"}]}';
        TaskActivityApiModels.RequestEnvelope requestEnvelope =
            (TaskActivityApiModels.RequestEnvelope) JSON.deserialize(
                payload,
                TaskActivityApiModels.RequestEnvelope.class
            );

        System.assertEquals(1, requestEnvelope.records.size(), 'One request record should deserialize.');
        System.assertEquals(String.valueOf(accountId), requestEnvelope.records[0].recordId, 'recordId should keep its API value.');
        System.assertEquals('2026-10-30', requestEnvelope.records[0].dueDate, 'dueDate should keep its API value.');

        TaskActivityApiModels.ResponseEnvelope response = new TaskActivityApiModels.ResponseEnvelope();
        response.requestId = 'REQ-MODEL';
        response.success = true;
        response.totalRecords = 1;
        response.successCount = 1;
        response.failureCount = 0;
        TaskActivityApiModels.RecordResult result = new TaskActivityApiModels.RecordResult();
        result.index = 0;
        result.recordId = accountId;
        result.targetType = 'ACCOUNT';
        result.relatedToId = accountId;
        result.taskStatus = 'In Progress';
        result.action = 'CREATED';
        result.success = true;
        response.results.add(result);

        String serializedResponse = JSON.serialize(response);
        System.assert(serializedResponse.contains('ACCOUNT'), 'The serialized response should contain the target type.');
        System.assert(serializedResponse.contains('REQ-MODEL'), 'The serialized response should contain the request ID.');
    }
}