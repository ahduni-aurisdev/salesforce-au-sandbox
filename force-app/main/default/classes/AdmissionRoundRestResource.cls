/**
 * @description Versioned REST endpoint for bulk Admission Round upserts.
 * @author AU Development Team
 * @date 2026-10-16
 * @version 1.0
 * @lastModified 2026-10-16
 */
@RestResource(urlMapping='/v1/admission-rounds/upsert')
global with sharing class AdmissionRoundRestResource {
    private static final String CONTENT_TYPE = 'application/json';

    @HttpPost
    global static void upsertAdmissionRounds() {
        RestRequest request = RestContext.request;
        RestResponse response = RestContext.response;
        response.addHeader('Content-Type', CONTENT_TYPE);
        String requestId = createRequestId();

        try {
            if (request == null || request.requestBody == null || request.requestBody.size() == 0) {
                throw new AdmissionRoundService.AdmissionRoundApiException('Request body is required.');
            }
            AdmissionRoundApiModels.RequestEnvelope requestEnvelope =
                (AdmissionRoundApiModels.RequestEnvelope) JSON.deserialize(
                    request.requestBody.toString(),
                    AdmissionRoundApiModels.RequestEnvelope.class
                );
            AdmissionRoundApiModels.ResponseEnvelope responseEnvelope =
                AdmissionRoundService.process(requestEnvelope, requestId);
            response.statusCode = responseEnvelope.success ? 200 : 207;
            response.responseBody = Blob.valueOf(JSON.serialize(responseEnvelope));
        } catch (System.JSONException exceptionValue) {
            writeError(response, 400, requestId, 'Invalid JSON payload: ' + exceptionValue.getMessage());
        } catch (AdmissionRoundService.AdmissionRoundApiException exceptionValue) {
            writeError(response, 400, requestId, exceptionValue.getMessage());
        } catch (Exception exceptionValue) {
            String errorMessage = exceptionValue.getMessage();
            AdmissionRoundService.logUnexpectedFailure(requestId, errorMessage);
            writeError(response, 500, requestId, errorMessage);
        }
    }

    private static void writeError(
        RestResponse response,
        Integer statusCode,
        String requestId,
        String message
    ) {
        AdmissionRoundApiModels.ResponseEnvelope responseEnvelope = new AdmissionRoundApiModels.ResponseEnvelope();
        responseEnvelope.requestId = requestId;
        responseEnvelope.success = false;
        responseEnvelope.totalRecords = 0;
        responseEnvelope.successCount = 0;
        responseEnvelope.failureCount = 1;
        AdmissionRoundApiModels.RecordResult result = new AdmissionRoundApiModels.RecordResult();
        result.index = -1;
        result.action = 'FAILED';
        result.success = false;
        result.errors.add(message);
        responseEnvelope.results.add(result);
        response.statusCode = statusCode;
        response.responseBody = Blob.valueOf(JSON.serialize(responseEnvelope));
    }

    private static String createRequestId() {
        return 'AR-' + Datetime.now().formatGMT('yyyyMMddHHmmssSSS') + '-' +
            EncodingUtil.convertToHex(Crypto.generateAesKey(128)).substring(0, 8);
    }
}
