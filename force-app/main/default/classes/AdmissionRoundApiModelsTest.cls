/**
 * @description Tests the Admission Round API request and response contracts.
 * @author AU Development Team
 * @date 2026-10-16
 * @version 1.0
 * @lastModified 2026-10-16
 */
@IsTest
private class AdmissionRoundApiModelsTest {
    @TestSetup
    static void createData() {
        List<Admission_Round__c> rounds = new List<Admission_Round__c>();
        for (Integer index = 0; index < 200; index++) {
            rounds.add(new Admission_Round__c(
                Name = 'Model Setup ' + index,
                Round_Code__c = 'MODEL-' + index
            ));
        }
        insert rounds;
    }

    @IsTest
    static void shouldDeserializeRequestAndSerializeResponse() {
        AdmissionRoundApiModels modelsContainer = new AdmissionRoundApiModels();
        System.assertNotEquals(null, modelsContainer, 'The DTO container constructor should be testable.');

        String payload = '{"records":[{"roundCode":"MODEL-API","roundName":"Model API"}]}';
        AdmissionRoundApiModels.RequestEnvelope requestEnvelope =
            (AdmissionRoundApiModels.RequestEnvelope) JSON.deserialize(
                payload,
                AdmissionRoundApiModels.RequestEnvelope.class
            );

        System.assertEquals(1, requestEnvelope.records.size(), 'One request record should deserialize.');
        System.assertEquals(
            'MODEL-API',
            requestEnvelope.records[0].roundCode,
            'The round code should retain its API value.'
        );

        AdmissionRoundApiModels.ResponseEnvelope response = new AdmissionRoundApiModels.ResponseEnvelope();
        response.requestId = 'REQ-MODEL';
        response.success = true;
        response.totalRecords = 1;
        response.successCount = 1;
        response.failureCount = 0;
        AdmissionRoundApiModels.RecordResult result = new AdmissionRoundApiModels.RecordResult();
        result.index = 0;
        result.roundCode = 'MODEL-API';
        result.action = 'INSERTED';
        result.success = true;
        response.results.add(result);

        String serializedResponse = JSON.serialize(response);
        System.assert(
            serializedResponse.contains('MODEL-API'),
            'The serialized response should contain the round code.'
        );
    }
}