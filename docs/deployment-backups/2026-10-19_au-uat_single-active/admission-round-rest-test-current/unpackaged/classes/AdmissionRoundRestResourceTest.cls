/**
 * @description Tests HTTP behavior for the Admission Round REST resource.
 * @author AU Development Team
 * @date 2026-10-16
 * @version 1.0
 * @lastModified 2026-10-16
 */
@IsTest
private class AdmissionRoundRestResourceTest {
    @TestSetup
    static void createData() {
        List<Admission_Round__c> rounds = new List<Admission_Round__c>();
        for (Integer index = 0; index < 200; index++) {
            rounds.add(new Admission_Round__c(
                Name = 'Resource Setup ' + index,
                Round_Code__c = 'RESOURCE-' + index
            ));
        }
        insert rounds;
    }

    @IsTest
    static void shouldReturnSuccessForValidPayload() {
        String payload = '{"records":[{' +
            '"roundCode":"REST-NEW",' +
            '"roundName":"REST New Round",' +
            '"admissionYear":"2027-28",' +
            '"department":"CLeF",' +
            '"program":"B.Tech",' +
            '"startDate":"2027-01-01",' +
            '"endDate":"2027-02-01"' +
        '}]}';
        prepareRestContext(payload);

        Test.startTest();
        AdmissionRoundRestResource.upsertAdmissionRounds();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode, 'A valid request should return HTTP 200.');
        AdmissionRoundApiModels.ResponseEnvelope response = deserializeResponse();
        System.assertEquals(true, response.success, 'The response should indicate complete success.');
        System.assertEquals('INSERTED', response.results[0].action, 'The result should identify the insert action.');
    }

    @IsTest
    static void shouldReturnMultiStatusForPartialSuccess() {
        String payload = '{"records":[' +
            '{"roundCode":"REST-VALID","roundName":"Valid"},' +
            '{"roundCode":"REST-INVALID","roundName":"Invalid","startDate":"not-a-date"}' +
        ']}';
        prepareRestContext(payload);

        Test.startTest();
        AdmissionRoundRestResource.upsertAdmissionRounds();
        Test.stopTest();

        System.assertEquals(207, RestContext.response.statusCode, 'Partial success should return HTTP 207.');
        AdmissionRoundApiModels.ResponseEnvelope response = deserializeResponse();
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
        AdmissionRoundRestResource.upsertAdmissionRounds();
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
        AdmissionRoundRestResource.upsertAdmissionRounds();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode, 'An empty body should return HTTP 400.');
        System.assert(
            RestContext.response.responseBody.toString().contains('Request body is required'),
            'The response should identify the missing request body.'
        );
    }

    private static void prepareRestContext(String payload) {
        RestRequest request = new RestRequest();
        request.httpMethod = 'POST';
        request.requestUri = '/services/apexrest/v1/admission-rounds/upsert';
        request.requestBody = Blob.valueOf(payload);
        RestContext.request = request;
        RestContext.response = new RestResponse();
    }

    private static AdmissionRoundApiModels.ResponseEnvelope deserializeResponse() {
        return (AdmissionRoundApiModels.ResponseEnvelope) JSON.deserialize(
            RestContext.response.responseBody.toString(),
            AdmissionRoundApiModels.ResponseEnvelope.class
        );
    }
}